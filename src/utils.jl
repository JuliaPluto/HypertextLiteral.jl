"""
    UnwrapHTML(data) - delegate regular printing to text/html

This is the inverse wrapper to `Docs.HTML` -- instead of enabling
regular objects to be printed as `MIME"text/html"` it unwraps an `HTML`
or any other object showable as `text/html` to be printable. Conversely,
it will cause an error if that object is not showable as `text/html`.

# Examples
```julia-repl
julia> print(UnwrapHTML(HTML("Hello World")))
Hello World
```
"""
struct UnwrapHTML{T}
    content::T
end

function UnwrapHTML(xs...)
    UnwrapHTML{Function}() do io::IO
        for x in xs
            show(io, MIME"text/html"(), x)
        end
    end
end

Base.print(io::IO, wrap::UnwrapHTML) =
    show(io, MIME"text/html"(), wrap.content)
Base.show(io::IO, m::MIME"text/html", wrap::UnwrapHTML) =
    show(io, m, wrap.content)

Base.print(io::IO, wrap::UnwrapHTML{<:Function}) = wrap.content(io)
Base.show(io::IO, wrap::UnwrapHTML{<:Function}) = wrap.content(io)
Base.show(io::IO, m::MIME"text/html", wrap::UnwrapHTML{<:Function}) =
    wrap.content(io)


"""
    EscapeProxy(io) - wrap an `io` to perform HTML escaping

This is a transparent proxy that performs HTML escaping so that objects
that are printed are properly converted into valid HTML values.  As a
special case, `HTML` objects are not escaped, hence, they could be used
to bypass this proxy. At this time, it only supports & and < escaping. 

# Examples
```julia-repl
julia> ep = EscapeProxy(stdout);
julia> print(ep, "A&B")
A&amp;B
julia> print(ep, HTML("<tag/>"))
<tag/>
```
"""
struct EscapeProxy{T<:IO} <: IO
    io::T
end

EscapeProxy(io::EscapeProxy) = io

Base.print(ep::EscapeProxy, h::HTML{<:Function}) = h.content(ep.io)
Base.print(ep::EscapeProxy, h::HTML) = print(ep.io, h.content)
Base.print(ep::EscapeProxy, w::UnwrapHTML{<:Function}) = w.content(ep.io)
Base.print(ep::EscapeProxy, w::UnwrapHTML) =
    show(ep.io, MIME"text/html"(), w.content)

function Base.write(ep::EscapeProxy, octet::UInt8)
    if octet == Int('&')
        write(ep.io, "&amp;")
    elseif  octet == Int('<')
        write(ep.io, "&lt;")
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


