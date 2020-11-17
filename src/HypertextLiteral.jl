module HypertextLiteral

export @htl_str htl_escape

"""
    @html_str -> Docs.HTML

Create an `HTML` object with string interpolation. The dollar-sign
character may be escaped by doubling it. Due to Julia parser, we have
no way to distinguish a quoted string subexpression from
"""
macro htl_str(expr)
    if isa(expr, String)
        expr = Meta.parse(
            "\"\"\"" *
            replace(replace(expr, "\\" => "\\\\"), "\$\$" => "\\\$") *
            "\"\"\"")
        if typeof(expr) == String
           return Expr(:call, :HTML, expr)
        end
    end
    @assert typeof(expr) == Expr
    return Expr(:call, :HTML, htl_str(expr, :content, Symbol[]))
end

function htl_str(expr::Expr, cntx::Symbol, locals::Vector{Symbol})::Expr
    if expr.head == :string
        args = []
        for arg in expr.args
            if isa(arg, String)
                push!(args, arg)
            elseif isa(arg, Symbol)
                if arg in locals
                    push!(args, Expr(:call, :htl_escape, arg))
                else
                    push!(args, Expr(:call, :htl_escape, esc(arg)))
                end
            elseif isa(arg, Expr)
                push!(args, htl_str(arg, cntx, locals))
            else
                throw(DomainError(arg, "unconvertable string argument"))
            end
        end
        return Expr(:call, :string, args...)
    end

    #  htl"""<ul>$(map([1,2]) do x "<li>$x</li>" end)</ul>"""
    if expr.head == :do
       @assert expr.args[2].head == Symbol("->")
       scope = expr.args[2].args[1]
       @assert scope.head == :tuple
       @assert length(scope.args) == 1
       nested_locals = [scope.args[1], locals...]
       block = expr.args[2].args[2]
       @assert block.head == :block
       @assert length(block.args) == 2
       block.args[2] = htl_str(block.args[2], cntx, nested_locals)
       return Expr(:call, :join, expr)
    end

    return Expr(:call, :htl_escape, esc(expr))
end

function htl_escape(var, ctx::Symbol = :content)::String
    if isa(var, HTML{String})
        return var.content
    elseif isa(var, AbstractString)
        return replace(replace(var, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(var, Number)
        return string(var)
    elseif isa(var, AbstractVector) && eltype(var) == HTML{String}
        return join([i.content for i in var])
    else
        throw(DomainError(var, "unescapable type $(typeof(var))"))
    end
end

end
