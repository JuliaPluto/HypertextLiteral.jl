# Utility Classes

This is a regression test for components upon which HTL is constructed.

## UnwrapHTML

This utility class acts as the inverse of HTML.

    using HypertextLiteral: UnwrapHTML

    print(UnwrapHTML(HTML("Hello World")))
    #-> Hello World

    display("text/html", UnwrapHTML(HTML("Hello World")))
    #-> Hello World

    display("text/html", UnwrapHTML(UnwrapHTML(HTML("Hello World"))))
    #-> Hello World

    print(UnwrapHTML(HTML("Hello "), HTML("World")))
    #-> Hello World

    display("text/html", UnwrapHTML(HTML("Hello "), HTML("World")))
    #-> Hello World

    print(UnwrapHTML("This is an error!"))
    #-> ERROR: MethodError: … show(… ::MIME{Symbol("text/html")}⋮

    print(UnwrapHTML("Error", HTML("Good")))
    #-> ERROR: MethodError: … show(… ::MIME{Symbol("text/html")}⋮

## EscapeProxy

This utility class acts wraps an `IO` stream to provide HTML escaping.

    using HypertextLiteral: EscapeProxy
    
    io = IOBuffer()
    ep = EscapeProxy(io)

    macro echo(expr)
        :($expr; print(String(take!(io))))
    end

The result of this proxy is that regular content is escaped. We also use
`HTML` as a way to bypass this proxy.


    @echo print(ep, "A&B")
    #-> A&amp;B

    @echo print(ep, HTML("<span>"), "A&B", HTML("</span>"))
    #-> <span>A&amp;B</span>

Let's suppose someone has written a `Custom` object that is printable
via `"text/html"`. This could be done as follows.

    struct Custom
        content
    end

    Base.show(io::IO, m::MIME"text/html", c::Custom) = print(io, c.content)

Since there is no standard `trait` for `"text/html"` content and since
invoking `showable` in a type loop is expensive, we've decided to be a
bit stupid about custom data. This can be addressed with `UnwrapHTML`.

    @echo print(ep, Custom("<tag/>"))
    #-> …Custom("&lt;tag/>")

    @echo print(ep, UnwrapHTML(Custom("<tag/>")))
    #-> <tag/>

