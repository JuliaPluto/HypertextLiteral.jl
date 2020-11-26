"""
    HypertextLiteral

This library provides for a `@htl()` macro and a `htl` string literal,
implementing interpolation that is aware of hypertext escape context.
The `@htl` macro has the advantage of using Julia's native string
parsing, so that it can handle arbitrarily deep nesting. However, it is
a more verbose than the `htl` string literal and doesn't permit
interpolated string literals. Conversely, the `htl` string literal,
`@htl_str`, uses custom parsing letting it handle string literal
escaping, however, it can only be used two levels deep (using three
quotes for the outer nesting, and a single double quote for the inner).

Both macros use the same hypertext lexing algorithm and call
`htl_escape` to perform context sensitive hypertext escaping. User
defined methods could be added to `htl_escape` so that this library
could be made aware of custom data types.
"""
module HypertextLiteral

export @htl_str, @htl, htl_escape

"""
    @htl string-expression

Create a `HTML{String}` with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escaping of interpolated results
is performed by `htl_escape`. Rather than escaping interpolated string
literals, e.g. `\$("Strunk & White")`, they are treated as errors since
they cannot be reliably detected (see Julia issue #38501).
"""
macro htl(expr)
    # The implementation tracks hypertext context and wraps calls to any
    # other object to `htl_escape`. It attempts to identify interpolated
    # string literals, raising an error if they are discovered.
    if expr isa String
        return HTML(expr)
    end
    @assert expr isa Expr
    @assert expr.head == :string
    cntx = :content
    last = nothing
    if length(expr.args) == 1 && expr.args[1] isa String
        throw("interpolated string literals are not supported")
    end
    for (idx, nest) in enumerate(expr.args)
        if nest isa String        
            if last isa String
                throw("interpolated string literals are not supported")
            end
            last = nest
            continue
        end
        last = nest
        expr.args[idx] = Expr(:call, :htl_escape, QuoteNode(cntx), esc(nest))
    end
    return Expr(:call, :HTML, expr)
end

"""
    @htl_str -> Base.Docs.HTML{String}

Create a `HTML{String}` with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escaping of interpolated results
is performed by `htl_escape`. Escape sequences should work identically
to Julia strings, except in cases where a slash immediately precedes the
double quote (see `@raw_str` and Julia issue #22926 for details).
"""
macro htl_str(expr::String)
    # The implementation of this macro attempts to emulate Julia's string
    # processing behavior by: (a) unescaping strings, (b) searching for
    # unescaped `\$` and using `parse()` to treat the subordinate
    # expression, (c) building up string literals and sending them
    # though an hypertext lexer to track escaping context, (d)
    # immediately escaping string values by context with `htl_escape`,
    # and (e) wrapping dynamic expressions with a call to `htl_escape`
    # with the given escaping context.
    if !occursin("\$", expr)
        return HTML(unescape_string(expr))
    end
    cntx = :content
    args = Union{String, Expr}[]
    svec = String[]
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
        if escaped
            escaped = false
            push!(svec, unescape_string(SubString(expr, start:idx-2)))
            push!(svec, "\$")
            start = idx += 1
            continue
        end
        push!(svec, unescape_string(SubString(expr, start:idx-1)))
        start = idx += 1
        (nest, idx) = Meta.parse(expr, start; greedy=false)
        if nest == nothing
            throw("invalid interpolation syntax")
        end
        start = idx
        if nest isa AbstractString
            push!(svec, htl_escape(cntx, nest))
            continue
        end
        if !isempty(svec)
            push!(args, join(svec))
            empty!(svec)
        end
        push!(args, Expr(:call, :htl_escape, QuoteNode(cntx), esc(nest)))
    end
    if start <= strlen
        push!(svec, unescape_string(SubString(expr, start:strlen)))
    end
    if !isempty(svec)
        push!(args, join(svec))
        empty!(svec)
    end
    return Expr(:call, :HTML, Expr(:call, :string, args...))
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
                     "htl\"\"\"\$([x for x in 1:3]...)\"\"\"")
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
