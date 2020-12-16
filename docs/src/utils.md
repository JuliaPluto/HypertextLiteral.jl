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

    using HypertextLiteral: EscapeProxy, BypassEscape

    io = IOBuffer()
    ep = EscapeProxy(io)

    macro echo(expr)
        :($expr; print(String(take!(io))))
    end

The result of this proxy is that regular content is escaped. We also use
`HTML` as a way to bypass this proxy.


    @echo print(ep, "(&'<\")")
    #-> (&amp;&apos;&lt;&quot;)

    @echo print(ep, BypassEscape("<span>"), "<A&B>", BypassEscape("</span>"))
    #-> <span>&lt;A&amp;B></span>

Let's suppose someone has written a `Custom` object.

    struct Custom
        content
    end

    Custom("<tag/>")
    #-> Custom("<tag/>")

If we print this though the escape proxy, we'll get the escaped
representation of the above string value.

    @echo print(ep, Custom("<tag/>"))
    #-> …Custom(&quot;&lt;tag/>&quot;)

We can address this with two parts. First, we can ensure this object is
`showable` for `"text/html"`. Second, we need to wrap this object so
that the escape proxy knows to invoke this method.

    Base.show(io::IO, m::MIME"text/html", c::Custom) =
       print(io, c.content)

    @echo print(ep, UnwrapHTML(Custom("<tag/>")))
    #-> <tag/>

