# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks hypertext escaping needs
and provides handy conversions dependent upon context.*

**Documentation** | **Build Status** | **Process**
:---: | :---: | :---:
[![Stable Docs][docs-stable-img]][docs-stable-url] [![Dev Docs][docs-dev-img]][docs-dev-url] | [![Actions Status][release-img]][release-url] [![Actions Status][nightly-img]][nightly-url] | [![Zulip Chat][chat-img]][chat-url] [![ISC License][license-img]][license-url]

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]) available at [here][observablehq]. This work
> is based upon a port to Julia written by Michiel Dral with significant
> architectural feedback by Kirill Simonov ([@xitology][@xitology]).

This package provides the macro `@htl` which returns an object that can
be rendered to `MIME"text/html"` displays. This macro provides
contextual interpolation sensible to the needs of HTML construction.

```julia

    using HypertextLiteral

    books = [
     (name="Who Gets What & Why", year=2012, authors=["Alvin Roth"]),
     (name="Switch", year=2010, authors=["Chip Heath", "Dan Heath"]),
     (name="Governing The Commons", year=1990, authors=["Elinor Ostrom"])]

    render_row(book) = @htl("""
      <tr><td>$(book.name) ($(book.year))<td>$(join(book.authors, " & "))
    """)

    render_table(books) = @htl("""
      <table><caption><h3>Selected Books</h3></caption>
      <thead><tr><th>Book<th>Authors<tbody>
      $((render_row(b) for b in books))</tbody></table>""")

    display("text/html", render_table(books))
    #=>
    <table><caption><h3>Selected Books</h3></caption>
    <thead><tr><th>Book<th>Authors<tbody>
      <tr><td>Who Gets What &amp; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &amp; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
    </tbody></table>
    =#

```

This library implements many features for working with HTML data within
the Julia language, including:

* Performant escaping of interpolated values
* Handles boolean valued attributes, such as `disabled`, `checked`
* Serialization of `Pair` and `Tuple` objects as attribute pairs
* Conversion of `snake_case` => `camel-case` for attribute names
* Support for CSS style formatting via `Pair`, `Tuple` and `Dict`
* Detection of `script` and `style` tags to suppress escaping
* Direct inclusion of objects (like `HTML`) showable by `MIME"text/html"`
* Extension API for customizing object display in various contexts

For more detail, please see the [documentation][docs-stable-url] and
join us on [Julia's Zulip][chat-url].

[htl]: https://github.com/observablehq/htl
[@mbostock]: https://github.com/mbostock
[@xitology]: https://github.com/xitology
[@mattt]: https://github.com/mattt
[names]: https://github.com/NSHipster/HypertextLiteral
[observablehq]: https://observablehq.com/@observablehq/htl
[xml entities]: https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
[named character references]: https://html.spec.whatwg.org/multipage/named-characters.html#named-character-references
[xml]: https://en.wikipedia.org/wiki/XML
[sgml]: https://en.wikipedia.org/wiki/Standard_Generalized_Markup_Language
[svg]: https://en.wikipedia.org/wiki/Scalable_Vector_Graphics
[html]: https://en.wikipedia.org/wiki/HTML

[support-img]: https://img.shields.io/github/issues/MechanicalRabbit/HypertextLiteral.jl.svg
[support-url]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/issues
[docs-dev-img]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/workflows/docs-dev/badge.svg
[docs-dev-url]: https://mechanicalrabbit.github.com/HypertextLiteral.jl/dev/
[docs-stable-img]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/workflows/docs-stable/badge.svg
[docs-stable-url]: https://mechanicalrabbit.github.com/HypertextLiteral.jl/stable/
[nightly-img]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/workflows/nightly-ci/badge.svg
[nightly-url]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/actions?query=workflow%3Anightly-ci
[release-img]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/workflows/release-ci/badge.svg
[release-url]: https://github.com/MechanicalRabbit/HypertextLiteral.jl/actions?query=workflow%3Arelease-ci
[chat-img]: https://img.shields.io/badge/chat-julia--zulip-blue
[chat-url]: https://julialang.zulipchat.com/#narrow/stream/267585-HypertextLiteral.2Ejl
[license-img]: https://img.shields.io/badge/license-ISC-brightgreen.svg
[license-url]: https://raw.githubusercontent.com/MechanicalRabbit/HypertextLiteral.jl/master/LICENSE.md
