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
> is based upon a port to Julia written by Michiel Dral.

This package provides a Julia string literal, `htl`, and macro `@htl`
that return an object that can be rendered to `MIME"text/html"`
displays. These macros support context-sensitive interpolation sensible
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
      <tr><td>Who Gets What &amp; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &amp; Dan Heath
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
[Julia's Zulip][chat-url]. We are expressly interested in feedback about
the following design questions:

* Should bare attributes be treated differently than quoted ones?
* Should we keep both string literal and regular macro form?
* Should vectors be treated as a concatenation, or raise an error?
* Should string macros use grammar that is succinct but not legal Julia?
* Should dispatch be enabled on just values, or on attribute names?
* How much built-in support should we have for CSS, and SVG?
* Generally, should unknown objects be stringified or made into errors?

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

[support-img]: https://img.shields.io/github/issues/clarkevans/HypertextLiteral.jl.svg
[support-url]: https://github.com/clarkevans/HypertextLiteral.jl/issues
[docs-dev-img]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/docs-dev/badge.svg
[docs-dev-url]: https://clarkevans.github.com/HypertextLiteral.jl/dev/
[docs-stable-img]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/docs-stable/badge.svg
[docs-stable-url]: https://clarkevans.github.com/HypertextLiteral.jl/stable/
[nightly-img]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/nightly-ci/badge.svg
[nightly-url]: https://github.com/clarkevans/HypertextLiteral.jl/actions?query=workflow%3Anightly-ci
[release-img]: https://github.com/clarkevans/HypertextLiteral.jl/workflows/release-ci/badge.svg
[release-url]: https://github.com/clarkevans/HypertextLiteral.jl/actions?query=workflow%3Arelease-ci
[chat-img]: https://img.shields.io/badge/chat-julia--zulip-blue
[chat-url]: https://julialang.zulipchat.com/#narrow/stream/267585-HypertextLiteral.2Ejl
[license-img]: https://img.shields.io/badge/license-ISC-brightgreen.svg
[license-url]: https://raw.githubusercontent.com/clarkevans/HypertextLiteral.jl/master/LICENSE.md
