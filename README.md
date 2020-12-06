# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks hypertext escaping needs
and provides handy conversions dependent upon context.*

**Documentation** | **Build Status** | **Process**
:---: | :---: | :---:
[![Docs Status][docs-badge]][docs-url] | [![Actions Status][release-badge]][release-url] [![Actions Status][nightly-badge]][nightly-url] | [![Zulip Chat][chat-badge]][chat-url] [![ISC License][license-img]][license-url]

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]) available at [here][observablehq]. This work
> is based upon a port to Julia written by Michiel Dral.

This package provides a Julia string literal, `htl`, and macro `@htl`
that return an object that can be rendered to `MIME"text/html"`
displays. These macros support context-senstive interpolation sensible
to the needs of HTML generation.

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
      $([render_row(b) for b in books]...)</tbody></table>""")

    display("text/html", render_table(books))
    #=>
    <table><caption><h3>Selected Books</h3></caption>
    <thead><tr><th>Book<th>Authors<tbody>
      <tr><td>Who Gets What &#38; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &#38; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
    </tbody></table>
    =#

This library implements many features for working with HTML data within
the Julia language, including:

* Element content (ampersand and less-than) are properly escaped
* Single quoted, double quoted, and unquoted attribute values are escaped
* Handles boolean valued attributes, such as `disabled`, `checked`
* Representation of Julia `Pair` and `Dict` as unquoted attributes
* Special handling of unquoted "style" attribute via Julia `Pair` and `Dict`
* Automatic `camelCase` => `camel-case` conversion for attributes & styles
* Detection of `script` and `style` tags to suppress escaping
* Direct inclusion of objects (like `HTML`) showable by `MIME"text/html"`
* Implements both string macros `@htl_str` and regular macros `@htl`

For more detail, please see the [documentation][docs-url] and join us on
[Julia's Zulip][chat-url].

[htl]: https://github.com/observablehq/htl
[@mbostock]: https://github.com/mbostock
[@mattt]: https://github.com/mattt
[names]: https://github.com/NSHipster/HypertextLiteral
[observablehq]: https://observablehq.com/@observablehq/htl
[xml entities]: https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
[named character references]: https://html.spec.whatwg.org/multipage/named-characters.html#named-character-references
[xml]: https://en.wikipedia.org/wiki/XML
[sgml]: https://en.wikipedia.org/wiki/Standard_Generalized_Markup_Language
[svg]: https://en.wikipedia.org/wiki/Scalable_Vector_Graphics
[html]: https://en.wikipedia.org/wiki/HTML

[support-badge]: https://img.shields.io/github/issues/clarkevans/HypertextLiteral.jl.svg
[support-url]: https://github.com/clarkevans/HypertextLiteral.jl/issues
[docs-badge]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/docs/badge.svg
[docs-url]: https://clarkevans.github.com/HypertextLiteral.jl/dev/
[nightly-badge]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/nightly-ci/badge.svg
[nightly-url]: https://github.com/clarkevans/HypertextLiteral.jl/actions?query=workflow%3Anightly-ci
[release-badge]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/release-ci/badge.svg
[release-url]: https://github.com/clarkevans/HypertextLiteral.jl/actions?query=workflow%3Arelease-ci
[chat-badge]: https://img.shields.io/badge/chat-julia--zulip-blue
[chat-url]: https://julialang.zulipchat.com/#narrow/stream/267585-HypertextLiteral.2Ejl
[license-img]: https://img.shields.io/badge/license-ISC-brightgreen.svg
[license-url]: https://raw.githubusercontent.com/clarkevans/HypertextLiteral.jl/master/LICENSE.md
