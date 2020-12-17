# Utility Classes

This is a regression test for components upon which HTL is constructed,
the design centers around `EscapeProxy` which escapes content printed to
it. There are several wrappers which drive special proxy handling.

    using HypertextLiteral: EscapeProxy, Reprint, Render, Passthru

## EscapeProxy

This utility class acts wraps an `IO` stream to provide HTML escaping.

    io = IOBuffer()
    ep = EscapeProxy(io)

    macro echo(expr)
        :($expr; print(String(take!(io))))
    end

The result of this proxy is that regular content printed to it is passed
along to the wrapped `IO`, after escaping the ampersand (`&`), less-than
(`<`), single-quote (`'`), and double-quote (`"`).

    @echo print(ep, "(&'<\")")
    #-> (&amp;&apos;&lt;&quot;)

## Reprint

This wrapper holds a closure that prints to an `io`.

    print(Reprint(io::IO -> print(io, "Hello World")))
    #-> Hello World

Reprinted content is still subject to escaping.

    @echo print(ep, Reprint(io -> print(io, "(&'<\")")))
    #-> (&amp;&apos;&lt;&quot;)

## Passthru

This wrapper simply prints its content.

    print(Passthru("<tagged/>"))
    #-> <tagged/>

Unlike `Reprint`, the printed content is not subject to escaping.

    @echo print(ep, Passthru("<span>"), "<A&B>", Passthru("</span>"))
    #-> <span>&lt;A&amp;B></span>

## Render

This wrapper prints text/html display of an object.

    struct Custom
        content
    end

    Base.show(io::IO, m::MIME"text/html", c::Custom) =
       print(io, c.content)

    print(Render(Custom("<tag/>")))
    #-> <tag/>

The printed content is not subject to escaping.

    @echo print(ep, Render(Custom("<tag/>")))
    #-> <tag/>

It's an error if the wrapped object isn't showable to `"text/html"`.

    print(Render("This is an error!"))
    #-> ERROR: MethodError: … show(… ::MIME{Symbol("text/html")}⋮
