module HypertextLiteral

export @htl_str

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
    @assert typeof(expr) == Expr && expr.head == :string
    return Expr(:call, :HTML, esc(expr))
end

end
