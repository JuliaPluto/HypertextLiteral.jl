module HypertextLiteral

export @htl_str, htl_escape

"""
    @htl_str -> Docs.HTML

Create an `HTML` object with string interpolation. The dollar-sign
character may be escaped by doubling it.
"""
macro htl_str(expr::String)
    if !occursin("\$", expr)
        return Expr(:call, :HTML, unescape_string(expr))
    end
    return Expr(:call, :HTML, htl_str(expr, :content))
end

function htl_str(expr::AbstractString, cntx::Symbol)::Expr
    # TODO: track hypertext context for proper escaping
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
    return Expr(:call, :string, args...)
end

function htl_escape(ctx::Symbol, var)::String
    # TODO: take hypertext context into account while escaping
    if isa(var, HTML{String})
        return var.content
    elseif isa(var, Vector{HTML{String}})
        return join([part.content for part in var])
    elseif isa(var, AbstractString)
        return replace(replace(var, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(var, Number)
        return string(var)
    else
        extra = ""
        if isa(var, AbstractVector)
            extra = ("\nPerhaps use splatting? e.g. " *
                     "htl\"\"\"\$([x for x in 1:3]...)\"\"\"")
        end
        throw(DomainError(var,
         "Type $(typeof(var)) lacks an `htl_escape` specialization.$(extra)"))
    end
end

function htl_escape(ctx::Symbol, var...)::String
    # htl"""$([x for x in [1:3]]...)"""
    return join([htl_escape(ctx, x) for x in var])
end


end
