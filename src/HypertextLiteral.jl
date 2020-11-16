module HypertextLiteral

export @htl_str htl_escape

"""
    @html_str -> Docs.HTML

Create an `HTML` object with string interpolation.
"""
macro htl_str(expr)
    if isa(expr, String)
        expr = Meta.parse("\"$(escape_string(expr))\"")
        if typeof(expr) == String
           return Expr(:call, :HTML, expr)
        end
    end
    @assert typeof(expr) == Expr
    return Expr(:call, :HTML, htl_str(expr, :content))
end

function htl_str(expr::Expr, cntx::Symbol)::Expr
    args = []
    if expr.head == :string
        for arg in expr.args
            if isa(arg, String)
                push!(args, arg)
            elseif isa(arg, Symbol)
                push!(args, Expr(:call, :htl_escape, esc(arg)))
            elseif isa(arg, Expr)
                push!(args, htl_string(arg, cntx))
            else
                throw(DomainError(arg, "Unconvertable string argument."))
            end
        end
        return Expr(:string, args...)
    end
    throw(DomainError(expr.head, "Unconvertable expression type."))
end

function htl_escape(var, ctx::Symbol = :content)::String
    if isa(var, HTML)
        return var.content
    elseif isa(var, AbstractString)
        return replace(replace(var, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(var, Number)
        return string(var)
    else
        throw(DomainError(var, "Don't know how to escape $(typeof(var))."))
    end
end

end
