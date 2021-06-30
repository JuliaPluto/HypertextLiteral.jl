"""
    StyleTagProxy(io)

This is a transparent proxy that ensures neither `<!--` nor `</style>`
occur in the output stream.

# Examples
```julia-repl
julia> gp = StyleTagProxy(stdout);
julia> print(gp, "valid");
valid
julia> print(gp, "</style>")
ERROR: "Content within a style tag must not contain `</style>`"
```
"""
mutable struct StyleTagProxy{T<:IO} <: IO where {T}
    io::T
    index::Int

    StyleTagProxy(io::T) where T = new{T}(io::T, 0)
end


"""
    StyleTag(data)

This object prints `data` unescaped within a `<style>` tag, wrapped in a
`StyleTagProxy` that guards against invalid style content. Content is
treated as if it had occurred within an attribute value, only that
amperstand escaping is not used.
"""
struct StyleTag
    content
end

Base.print(ep::EscapeProxy, x::StyleTag) =
    print_value(StyleTagProxy(ep.io), x.content)

function scan_for_style(index::Int, octet::UInt8)::Int
    if 1 == index
        return octet == Int('!') ? 12 : octet == Int('/') ? 2 : 0
    elseif 2 == index
        return (octet == Int('S') || octet == Int('s')) ? 3 : 0
    elseif 3 == index
        return (octet == Int('T') || octet == Int('t')) ? 4 : 0
    elseif 4 == index
        return (octet == Int('Y') || octet == Int('y')) ? 5 : 0
    elseif 5 == index
        return (octet == Int('L') || octet == Int('l')) ? 6 : 0
    elseif 6 == index
        return (octet == Int('E') || octet == Int('e')) ? 7 : 0
    elseif 7 == index
        if octet == Int('>')
            throw("Content within a style tag must not contain `</style>`")
        end
    elseif 12 == index
        return octet == Int('-') ? 13 : 0
    elseif 13 == index
        if octet == Int('-')
            throw("Content within a style tag must not contain `<!--`")
        end
    else
        @assert false # unreachable?!
    end
    return 0
end

function Base.write(sp::StyleTagProxy, octet::UInt8)
    if 0 == sp.index
        if octet == Int('<')
            sp.index = 1
        end
        return write(sp.io, octet)
    end
    sp.index = scan_for_style(sp.index, octet)
    return write(sp.io, octet)
end

function Base.unsafe_write(sp::StyleTagProxy, input::Ptr{UInt8}, nbytes::UInt)
    cursor = input
    index = sp.index
    final = input + nbytes
    while cursor < final
        octet = unsafe_load(cursor)
        if octet == Int('<')
            index = 1
        elseif 0 != index
            index = scan_for_style(index, octet)
        end
        cursor += 1
    end
    sp.index = index
    return unsafe_write(sp.io, input, nbytes)
end
