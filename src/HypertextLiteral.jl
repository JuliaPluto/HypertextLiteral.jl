module HypertextLiteral

export @htl_str

"""
    @html_str -> Docs.HTML

Create an `HTML` object from a string template.
"""
macro htl_str(expr::String)
    # We want to use Julia's parser to pull out string interpolations,
    # hence we first make a string (by escaping) and then parse it.
    qs = "\"" * replace(replace(expr, "\\" => "\\\\"), "\"" => "\\\"") * "\""
    expr = Meta.parse(qs)
    if typeof(expr) == String
       return HTML(expr)
    end
    @assert typeof(expr) == Expr && expr.head == :string
    return HTML("TODO")
end

end
