"""
    Script(data) - object printed as text/javascript
"""
mutable struct Script{T}
    content::T
end

"""
    script(value)

Convert a Julia value into something suitable for use within a
`<script>` tag. By default, this will attempt to render the object as
`"text/javascript"`. Default serialization is provided for string,
vector, and dictionary data types.
"""
script(value::Missing) = Bypass("null")
script(value::Nothing) = Bypass("undefined")
script(value::Union{Bool, Integer, AbstractFloat}) = 
    Bypass(string(value))


function script(value::AbstractString)
    if occursin("</script>", lowercase(value))
        throw(DomainError(repr(value), "  Content of <script> cannot " *
            "contain the end tag (`</script>`)."))
    end
    if occursin("<!--", value)
        throw(DomainError(repr(value), "  Content of <script> should " *
            "not contain a comment block (`<!--`)."))
    end
    return Bypass(value)
end
