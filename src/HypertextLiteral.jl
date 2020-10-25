module HypertextLiteral

import Base: print, show, ==, hash

export HTL, @htl_str

"""
`HTL(s)`: Create an object that renders `s` as html.

    HTL("<div>foo</div>")

You can also use a stream for large amounts of data:

    HTL() do io
      println(io, "<div>foo</div>")
    end
"""
mutable struct HTL{T}
    content::T
end

function HTL(xs...)
    HTL() do io
        for x in xs
            print(io, x)
        end
    end
end

show(io::IO, ::MIME"text/html", h::HTL) = print(io, h.content)
show(io::IO, ::MIME"text/html", h::HTL{<:Function}) = h.content(io)

"""
    @html_str -> Docs.HTL

Create an `HTL` object from a literal string.
"""
macro htl_str(s)
    :(HTL($s))
end

==(t1::T, t2::T) where {T<:Union{HTL,Text}} = t1.content == t2.content
hash(t::T, h::UInt) where {T<:Union{HTL,Text}} = hash(T, hash(t.content, h))

end
