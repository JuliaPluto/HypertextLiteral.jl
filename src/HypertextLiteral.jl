module HypertextLiteral

export @htl_str

"""
    @html_str -> Docs.HTML

Create an `HTML` object from a string template.
"""
macro htl_str(s)
    :(HTML($s))
end

end
