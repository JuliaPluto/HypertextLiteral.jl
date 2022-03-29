"""
    Reprint(fn) - apply the lambda function when printed
"""
mutable struct Reprint
    content::Function
end

Base.print(io::IO, r::Reprint) = r.content(io)

"""
    Render(data) - printed object shows its text/html
"""
struct Render{T}
    content::T
end

Base.print(io::IO, r::Render) =
    show(io, MIME"text/html"(), r.content)

"""
    Bypass(data) - printed object passes though EscapeProxy unescaped
"""

mutable struct Bypass{T}
    content::T
end

Base.print(io::IO, x::Bypass) = print(io, x.content)

abstract type IOProxy <: IO end

"""
    EscapeProxy(io) - wrap an `io` to perform HTML escaping

This is a transparent proxy that performs HTML escaping so that objects
that are printed are properly converted into valid HTML values. As a
special case, objects wrapped with `Bypass` are not escaped, and
bypass the proxy.

# Examples
```julia-repl
julia> ep = EscapeProxy(stdout);
julia> print(ep, "A&B")
A&amp;B
julia> print(ep, Bypass("<tag/>"))
<tag/>
```
"""
struct EscapeProxy{T<:IO} <: IOProxy
    io::T
end

Base.print(ep::EscapeProxy, h::Reprint) = h.content(ep)
Base.print(ep::EscapeProxy, w::Render) =
    show(ep.io, MIME"text/html"(), w.content)
Base.print(ep::EscapeProxy, x::Bypass) = print(ep.io, x)

function Base.write(ep::EscapeProxy, octet::UInt8)
    if octet == Int('&')
        write(ep.io, "&amp;")
    elseif octet == Int('<')
        write(ep.io, "&lt;")
    elseif octet == Int('"')
        write(ep.io, "&quot;")
    elseif octet == Int('\'')
        write(ep.io, "&apos;")
    else
        write(ep.io, octet)
    end
end

function Base.unsafe_write(ep::EscapeProxy, input::Ptr{UInt8}, nbytes::UInt)
    written = 0
    last = cursor = input
    final = input + nbytes
    while cursor < final
        ch = unsafe_load(cursor)
        if ch == Int('&')
            written += unsafe_write(ep.io, last, cursor - last)
            written += unsafe_write(ep.io, pointer("&amp;"), 5)
            cursor += 1
            last = cursor
            continue
        end
        if ch == Int('<')
            written += unsafe_write(ep.io, last, cursor - last)
            written += unsafe_write(ep.io, pointer("&lt;"), 4)
            cursor += 1
            last = cursor
            continue
        end
        if ch == Int('\'')
            written += unsafe_write(ep.io, last, cursor - last)
            written += unsafe_write(ep.io, pointer("&apos;"), 6)
            cursor += 1
            last = cursor
            continue
        end
        if ch == Int('"')
            written += unsafe_write(ep.io, last, cursor - last)
            written += unsafe_write(ep.io, pointer("&quot;"), 6)
            cursor += 1
            last = cursor
            continue
        end
        cursor += 1
    end
    if last < final
        written += unsafe_write(ep.io, last, final - last)
    end
    return written
end

# IO passthrough methods:
Base.in(key_value::Pair, io::IOProxy) = in(key_value, io.io)
Base.haskey(io::IOProxy, key) = haskey(io.io, key)
Base.getindex(io::IOProxy, key) = getindex(io.io, key)
Base.get(io::IOProxy, key, default) = get(io.io, key, default)
Base.keys(io::IOProxy) = keys(io.io)
Base.displaysize(io::IOProxy) = displaysize(io.io)
