"""
    HypertextLiteral

This library provides for a `@htl()` macro and a `htl` string literal,
both implementing interpolation that is aware of hypertext escape
context. The `@htl` macro has the advantage of using Julia's native
string parsing, so that it can handle arbitrarily deep nesting. However,
it is a more verbose than the `htl` string literal and doesn't permit
interpolated string literals. Conversely, the `htl` string literal,
`@htl_str`, uses custom parsing letting it handle string literal
escaping, however, it can only be used two levels deep (using three
quotes for the outer nesting, and a single double quote for the inner).

Both macros use the same hypertext lexing algorithm, implemented in
`HypertextLiteral.htl_convert` and call `HypertextLiteral.htl_escape` to
perform context sensitive hypertext escaping. User defined methods could
be added to `htl_escape` so that this library could be made aware of
custom data types.
"""
module HypertextLiteral

export @htl_str, @htl

"""
    @htl string-expression

Create a `HTML{String}` with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escaping of interpolated results
is performed by `htl_escape`. Rather than escaping interpolated string
literals, e.g. `\$("Strunk & White")`, they are treated as errors since
they cannot be reliably detected (see Julia issue #38501).
"""
macro htl(expr, context=:content)
    if expr isa String
        return HTML(expr)
    end
    # Find cases where we may have an interpolated string literal and
    # raise an exception (till Julia issue #38501 is addressed)
    @assert expr isa Expr
    @assert expr.head == :string
    if length(expr.args) == 1 && expr.args[1] isa String
        throw("interpolated string literals are not supported")
    end
    for idx in 2:length(expr.args)
        if expr.args[idx] isa String && expr.args[idx-1] isa String
            throw("interpolated string literals are not supported")
        end
    end
    return htl_convert(context, expr.args)
end

"""
    @htl_str -> Base.Docs.HTML{String}

Create a `HTML{String}` with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escaping of interpolated results
is performed by `htl_escape`. Escape sequences should work identically
to Julia strings, except in cases where a slash immediately precedes the
double quote (see `@raw_str` and Julia issue #22926 for details).
"""
macro htl_str(expr::String, context=:content)
    # This implementation emulates Julia's string interpolation behavior
    # as close as possible to produce an expression vector similar to
    # what would be produced by the `@htl` macro. Unlike most text
    # literals, we unescape content here. This logic also directly
    # handles interpolated literals, with contextual escaping.
    if !('$' in expr)
        return HTML(unescape_string(expr))
    end
    args = Any[]
    start = idx = 1
    strlen = length(expr)
    escaped = false
    while idx <= strlen
        c = expr[idx]
        if c == '\\'
            escaped = !escaped
            idx += 1
            continue
        end
        if c != '$'
            escaped = false
            idx += 1
            continue
        end
        finish = idx - (escaped ? 2 : 1)
        push!(args, unescape_string(SubString(expr, start:finish)))
        start = idx += 1
        if escaped
            escaped = false
            push!(args, "\$")
            continue
        end
        (nest, idx) = Meta.parse(expr, start; greedy=false)
        if nest == nothing
            throw("invalid interpolation syntax")
        end
        start = idx
        if nest isa String
            # this is an interpolated string literal
            nest = Expr(:string, nest)
        end
        push!(args, nest)
    end
    if start <= strlen
        push!(args, unescape_string(SubString(expr, start:strlen)))
    end
    return htl_convert(context, args)
end

"""
    htl_convert(context, exprs[])::Expr

Transform a vector consisting of string literals (leave as-is) and
interpolated expressions (that are to be escaped) into an expression
with context-sensitive escaping.
"""
function htl_convert(context::Symbol, exprs::Vector{Any})::Expr
    args = Union{String, Expr}[]
    for expr in exprs
        if expr isa String
            # update the context....
            push!(args, expr)
            continue
        end
        if expr isa Expr && expr.head == :string && length(expr.args) == 1
            # we can escape interpolated string literals early
            push!(args, htl_escape(context, expr.args[1]))
            continue
        end
        push!(args, Expr(:call, :htl_escape, QuoteNode(context), esc(expr)))
    end
    return Expr(:call, :HTML, Expr(:string, args...))
end

"""
    htl_escape(context::Symbol, obj)::String

For a given HTML lexical context and an arbitrary Julia object, return
a `String` value that is properly escaped. Splatting interpolation
concatenates these escaped values. This fallback implements:
`HTML{String}` objects are assumed to be properly escaped, and hence
its content is returned; `Vector{HTML{String}}` are concatenated; any
`Number` is converted to a string using `string()`; and `AbstractString`
objects are escaped according to context.

There are several escaping contexts. The `:content` context is for HTML
content, at a minimum, the ampersand (`&`) and less-than (`<`) characters
must be escaped.
"""
function htl_escape(context::Symbol, obj)::String
    @assert context == :content
    if obj isa HTML{String}
        return obj.content
    elseif obj isa Vector{HTML{String}}
        return join([part.content for part in obj])
    elseif obj isa AbstractString
        return replace(replace(obj, "&" => "&amp;"), "<" => "&lt;")
    elseif obj isa Number
        return string(obj)
    else
        extra = ""
        if obj isa AbstractVector
            extra = ("\nPerhaps use splatting? e.g. " *
                     "htl\"\$([x for x in 1:3]...)\"")
        end
        throw(DomainError(obj,
         "Type $(typeof(obj)) lacks an `htl_escape` specialization.$(extra)"))
    end
end

function htl_escape(context::Symbol, obj...)::String
    # support splatting interpolation via concatenation
    return join([htl_escape(context, x) for x in obj])
end



end
