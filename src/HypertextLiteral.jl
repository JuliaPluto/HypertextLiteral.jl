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
        for (idx, arg) in enumerate(expr.args)
            if isa(arg, String)
                continue
            elseif isa(arg, Symbol)
                if !in(arg, locals)
                    arg = esc(arg)
                end
                expr.args[idx] = Expr(:call, :htl_escape, arg)
            elseif isa(arg, Expr)
                expr.args[idx] = htl_str(arg, cntx, locals)
            else
                @assert false # this shouldn't happen
            end
        end
        return expr
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

    # TODO: improve translation to handle local variables
    if expr.head == :call && length(locals) == 0
        return Expr(:call, :htl_escape, esc(expr))
    end

    # unless it is well defined, let's not translate it
    return throw(DomainError(expr, "undefined interpolation"))
end

function htl_escape(var, ctx::Symbol = :content)::String
    if isa(var, HTML{String})
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
