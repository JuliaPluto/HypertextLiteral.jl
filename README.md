# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks hypertext escaping needs
and provides handy conversions dependent upon context.*

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]). You can read more about it
> [here][observablehq].

This package provides a Julia string literal macro, `htl`, that builds
an `HTML` object from a string template using Julia's interpolation
syntax. We use Julia's parser to generate an Abstract Syntax Tree (AST),
and then convert this tree to add variable escaping that takes into
account the hypertext context.

    using HypertextLiteral

    books = [
     (name="Who Gets What and Why", year=2012, authors=["Alvin Roth"]),
     (name="Switch", year=2010, authors=["Chip Heath", "Dan Heath"]),
     (name="Governing The Commons", year=1990, authors=["Elinor Ostrom"]),
     (name="Peopleware", year=1987, authors=["Tom Demarco", "Tim Lister"]),
     (name="Innovation & Entrepreneurship", year=1985, 
      authors=["Peter Drucker"])]

    render_row(book) = htl"""
      <tr><td>$(book.name) ($(book.year))<td>$(join(book.authors, " & "))
    """

    render_table(books) = htl"""
      <table><caption><h3>Selected Books</h3></caption>
      <thead><tr><th>Book<th>Authors<tbody>
      $([render_row(b) for b in books])</tbody></table>"""

    display("text/html", render_table(books))
    #=>
    <table><caption><h3>Selected Books</h3></caption>
    <thead><tr><th>Book<th>Authors<tbody>
      <tr><td>Who Gets What and Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &amp; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
      <tr><td>Peopleware (1987)<td>Tom Demarco &amp; Tim Lister
      <tr><td>Innovation &amp; Entrepreneurship (1985)<td>Peter Drucker
    </tbody></table>
    =#

## Introduction

The Julia ecosystem provides an `HTML` object type as part of its
built-in documentation package. This lets us indicate that a given
value is intended to be syntactically correct hypertext.

    html"<span>Hello World!</span>"
    #-> HTML{String}("<span>Hello World!</span>")

An the underlying string for a given `HTML` object can be accessed using
the `content` attribute. However, there's little else, besides marking a
string as hypertext, that is provided by the `html` syntax literal.

    html"<span>Hello World</span>".content
    #-> "<span>Hello World</span>"

Julia uses `$` for string interpolation syntax, letting local variables
or arbitrary expressions be accessed. However, it doesn't know about
proper escaping in the context of hypertext content.

    book = "Strunk & White"

    "<span>Today's Reading: $book</span>"
    #-> "<span>Today's Reading: Strunk & White</span>"

Conversely, the built-in the `html` string literal doesn't provide
interpolation, the `$` character is simply that, a dollar sign.

    html"<span>Today's Reading: $book</span>"
    #-> HTML{String}("<span>Today's Reading: \$book</span>")

This package, `HypertextLiteral` provides an `htl` string literal which
produces an `HTML` object, implementing common interpolation patterns
and convenient data conversions.

    using HypertextLiteral

    htl"<span>Today's Reading: $book</span>"
    #-> HTML{String}("<span>Today's Reading: Strunk &amp; White</span>")

The remainder of this documentation reviews functionality provided by
the `htl` string macro. We use [NarrativeTest][nt] to ensure that
examples provided here are executable. After each command is a comment
(staring with the pound sign `#`) that indicates the output expected.

## Basic Operations

Besides simple string interpolation, there is an implicit conversion of
`Number` values to their `String` representation.

    var = 3

    htl"$var"
    #-> HTML{String}("3")

To include a literal `$` in the output string, use `$$`. This differs
from normal Julia strings where you would instead use `\$`.

    htl"$$42.50"
    #-> HTML{String}("\$42.50")

Interpolated strings are escaped.

    var = "3<4 & 5>4"

    htl"$var"
    #-> HTML{String}("3&lt;4 &amp; 5>4")

If a variable is already a `HTML` object, it is not further escaped.

    var = html"<span>no-escape</span>"

    htl"$var"
    #-> HTML{String}("<span>no-escape</span>")

Of course, more than one variable can be interpolated.

    s = "World"
    n = 42

    htl"Hello $s, $n"
    #-> HTML{String}("Hello World, 42")

Functions returning values can be included in an interpolation, this
uses the Julia syntax `$(expr)`.

    sq(x) = x*x

    htl"3 squared is $(sq(3))"
    #-> HTML{String}("3 squared is 9")

Functions returning string values will be escaped.

    input() = "<script>alert('ouch!')"

    htl"$(input())"
    #-> HTML{String}("&lt;script>alert('ouch!')")

Functions returning HTML fragments are passed on, as-is.

    frag() = html"<span>Hello!</span>"

    htl"$(frag())"
    #-> HTML{String}("<span>Hello!</span>")

## Expression Translation

This package attempts to convert common string literal conventions from
their Julia equivalent.

    htl"""<ul>$([ htl"<li>$x</li>" for x in ["A", "B&C"]])</ul>"""
    #-> HTML{String}("<ul><li>A</li><li>B&amp;C</li></ul>")

This technique works with arbitrary Julia expressions.

    htl"""<ul>$(map(["A", "B&C"]) do x htl"<li>$x</li>" end)</ul>"""
    #-> HTML{String}("<ul><li>A</li><li>B&amp;C</li></ul>")

## Quirks

Since this string format uses Julia macro processing, there are some
differences between an `htl` literal and native Julia interpolation.
For starters, Julia doesn't recognize and treat `$` syntax natively for
these macros, hence, at a very deep level parsing is different.

    "$("Hello")"
    #-> "Hello"

In this interpolation, the expression `"Hello"` is seen as a string,
and hence Julia can produce the above output. However, Julia does not
given this special treatment to string literals. Hence, if you try this
expression using `htl` you'll get an error.

    htl"$("Hello")"
    #-> ERROR: syntax: cannot juxtapose string literal

The above expression is seen by Julia as 3 tokens, `htl"$("`, followed
by `Hello`, and then `")`. This combination is a syntax error. One might
correct this using triple strings.

    """$("Hello")"""
    #-> "Hello"

When processed with `htl` macro, we could make it have a similar effect,
with output wrapped as a `HTML` string object.

    htl"""$("Hello")"""
    #-> HTML{String}("Hello")

Only that internal string literals like this are properly escaped.

    htl"""Look, Ma, $("<i>automatic escaping</i>")!"""
    #-> HTML{String}("Look, Ma, &lt;i>automatic escaping&lt;/i>!")

We can nest literal expressions, so long as the outer nesting uses
triple quotes.

    htl"""$( htl"Hello" )"""
    #-> HTML{String}("Hello")

We should be able to nest these arbitrarily deep. Perhaps this is
something we can fix...

    htl"""$( htl"$( htl"Hello" )" )"""
    #-> ERROR: LoadError: Base.Meta.ParseError⋮

## Edge Cases & Regression Tests

Escaped strings should just pass-though.

    htl"\"\\".content
    #-> "\"\\"

We double-up on `$` to escape it.

    println(htl"$$42.00".content)
    #-> $42.00

Interpolation should handle splat and concatinate.

    htl"""$([x for x in [1,2,3]]...)"""
    #-> HTML{String}("123")

However, it shouldn't concatinate by default.

    htl"""$([x for x in 1:3])"""
    #=>
    ERROR: DomainError with [1, 2, 3]:
    Type Array{Int64,1} lacks an `htl_escape` specialization.
    Perhaps use splatting? e.g. htl"""$([x for x in 1:3]...)"""
    =#

A string ending with `$` is an syntax error since it is an incomplete
interpolation.

    htl"$"
    #-> ERROR: LoadError: "incomplete interpolation"⋮

    htl"Foo$"
    #-> ERROR: LoadError: "incomplete interpolation"⋮

[nt]: https://github.com/rbt-lang/NarrativeTest.jl
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
