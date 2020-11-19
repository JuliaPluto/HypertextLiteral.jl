module HypertextLiteral

export @htl_str, htl_escape

"""
    @htl_str -> Docs.HTML

Create an `HTML` object with string interpolation. The dollar-sign
character may be escaped by doubling it.
"""
macro htl_str(expr::String)
    if !occursin("\$", expr)
        return Expr(:call, :HTML, expr)
    end
    return Expr(:call, :HTML, htl_str(expr, :content))
end

function htl_str(expr::String, cntx::Symbol)::Expr
    # TODO: track hypertext context for proper escaping
    start = 1
    mixed = false
    args = []
    while start <= length(expr)
        next = findnext("\$", expr, start)
        if next == nothing
            push!(args, expr[start:end])
            break
        end
        next = next[end]
        if next > start
            push!(args, expr[start:next-1])
        end
        start = next + 1
        if start > length(expr)
            throw("incomplete interpolation")
        end
        if expr[start] == '$'
            push!(args, "\$")
            start += 1
            continue
        end
        (nest, start) = Meta.parse(expr, start; greedy=false)
        if isa(nest, String)
            push!(args, htl_escape(cntx, nest))
            continue
        end
        mixed = true
        push!(args, Expr(:call, :htl_escape, QuoteNode(cntx), esc(nest)))
    end
    if mixed
        return Expr(:call, :string, args...)
    end
    return Expr(:call, :string, join(args))
end

function htl_escape(ctx::Symbol, var...)::String
    return join([htl_escape(ctx, x) for x in var])
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
        throw(DomainError(var, "unescapable type $(typeof(var))"))
    end
end

end
