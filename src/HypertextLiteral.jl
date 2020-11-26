module HypertextLiteral

export @htl_str, htl_escape

"""
    @htl_str -> Base.Docs.HTML{String}

Create a `HTML{String}` with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escaping of interpolated results
is performed by `htl_escape`. Escape sequences should work identically
to Julia strings, except in cases where a slash immediately precedes the
double quote (see `@raw_str` and Julia issue #22926 for details).
"""
macro htl_str(expr::String)
    if !occursin("\$", expr)
        return Expr(:call, :HTML, unescape_string(expr))
    end
    cntx = :content  # this is the escaping context
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
        if isa(nest, AbstractString)
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
concatinates these escaped values. This fallback implements:
`HTML{String}` objects are assumed to be propertly escaped, and hence
its content is returned; `Vector{HTML{String}}` are concatinated; any
`Number` is converted to a string using `string()`; and `AbstractString`
objects are escaped according to context.

There are several escaping contexts. The `:content` context is for HTML
content, at a minimum, the amperstand (`&`) and lessthan (`<`) characters
must be escaped.
"""
function htl_escape(context::Symbol, obj)::String
    @assert context == :content
    if isa(obj, HTML{String})
        return obj.content
    elseif isa(obj, Vector{HTML{String}})
        return join([part.content for part in obj])
    elseif isa(obj, AbstractString)
        return replace(replace(obj, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(obj, Number)
        return string(obj)
    else
        extra = ""
        if isa(obj, AbstractVector)
            extra = ("\nPerhaps use splatting? e.g. " *
                     "htl\"\"\"\$([x for x in 1:3]...)\"\"\"")
        end
        throw(DomainError(obj,
         "Type $(typeof(obj)) lacks an `htl_escape` specialization.$(extra)"))
    end
end

function htl_escape(context::Symbol, obj...)::String
    # support splatting interpolation via concatination
    return join([htl_escape(context, x) for x in obj])
end


end
