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
    if expr.head == :string
        args = []
        for arg in expr.args
            if isa(arg, String)
                push!(args, arg)
            elseif isa(arg, Symbol)
                push!(args, Expr(:call, :htl_escape, esc(arg)))
            elseif isa(arg, Expr)
                push!(args, htl_str(arg, cntx))
            else
                throw(DomainError(arg, "unconvertable string argument"))
            end
        end
        return Expr(:string, args...)
    end
    return Expr(:call, :htl_escape, esc(expr))
end

function htl_escape(var, ctx::Symbol = :content)::String
    if isa(var, HTML)
        return var.content
    elseif isa(var, AbstractString)
        return replace(replace(var, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(var, Number)
        return string(var)
    else
        throw(DomainError(var, "unescapable type $(typeof(var))"))
    end
end

end
