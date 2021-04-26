"""
    Style(data) - object printed as text/css
"""
struct Style
    content
end

Base.print(ep::EscapeProxy, x::Style) =
    print_style(ep.io, x.content)

"""
    print_style(io, value)

Show `value` as `"text/css"` to the given `io`, this provides some
baseline functionality for built-in data types.

    - `nothing` is omitted
    - `Number` values are printed; no escaping
    - `Symbol` becomes an unquoted name; no escaping
    - `Bool` values are printed directly, as `true` or `false`
"""
print_style(io::IO, value) =
    show(io, MIME"text/css"(), value)
print_style(io::IO, ::Nothing) =
    nothing
print_style(io::IO, value::Union{Number, Symbol}) =
    print(io, value)
print_style(io::IO, value::AbstractString) =
    print(io, rawtext(:style, value))
