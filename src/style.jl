"""
    StyleProxy(io)

This is a transparent proxy that ensures neither `<!--` nor `</style>`
occur in the output stream.

# Examples
```julia-repl
julia> gp = StyleProxy(stdout);
julia> print(gp, "valid");
valid
julia> print(gp, "</style>")
</styleERROR: "Content within a style tag must not contain `</style>`"
```
"""
mutable struct StyleProxy{T<:IO} <: IO where {T}
    io::T
    index::Int

    StyleProxy(io::T) where T = new{T}(io::T, 0)
end


"""
    Style(data)

This object prints `data` unescaped within a `<script>` tag, wrapped in
a `StyleProxy` that guards against invalid script content.
"""
struct Style
    content
end

Base.print(ep::EscapeProxy, x::Style) =
    print_style_lower(StyleProxy(ep.io), x.content)

"""
    print_style_lower(io, value)

Provides a hook to override `print_value` to provide custom CSS encoding.
"""
print_style_lower(io::IO, value) =
   print_value(io, value)


"""
    CSS(js) - shows `js` as `"text/css"`
"""
struct CSS
    content
end

Base.show(io::IO, ::MIME"text/css", css::CSS) =
    print(io, css.content)

function Base.write(sp::StyleProxy, octet::UInt8)
    if 0 == sp.index
        if octet == Int('<')
            sp.index = 1
        end
        write(sp.io, octet)
        return
    end
    if 1 == sp.index
        sp.index = octet == Int('!') ? 12 :
                   octet == Int('/') ? 2 : 0
    elseif 2 == sp.index
        sp.index = (octet == Int('S') || octet == Int('s')) ? 3 : 0
    elseif 3 == sp.index
        sp.index = (octet == Int('T') || octet == Int('t')) ? 4 : 0
    elseif 4 == sp.index
        sp.index = (octet == Int('Y') || octet == Int('y')) ? 5 : 0
    elseif 5 == sp.index
        sp.index = (octet == Int('L') || octet == Int('l')) ? 6 : 0
    elseif 6 == sp.index
        sp.index = (octet == Int('E') || octet == Int('e')) ? 7 : 0
    elseif 7 == sp.index
        sp.index = 0
        if octet == Int('>')
            throw("Content within a style tag must not contain `</style>`")
        end
    elseif 12 == sp.index
        sp.index = octet == Int('-') ? 13 : 0
    elseif 13 == sp.index
        sp.index = 0
        if octet == Int('-')
            throw("Content within a style tag must not contain `<!--`")
        end
    end
    write(sp.io, octet)
end

function Base.unsafe_write(sp::StyleProxy, input::Ptr{UInt8}, nbytes::UInt)
    written = 0
    last = cursor = input
    final = input + nbytes
    while cursor < final
        ch = unsafe_load(cursor)
        if ch == Int('<') || sp.index != 0
            written += unsafe_write(sp.io, last, cursor - last)
            write(sp, ch)
            written += 1
            cursor += 1
            last = cursor
            continue
        end
        cursor += 1
    end
    if last < final
        written += unsafe_write(sp.io, last, final - last)
    end
    return written
end
