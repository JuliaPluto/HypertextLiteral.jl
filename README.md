# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks hypertext escaping needs
and provides handy conversions dependent upon context.*

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]). You can read more about it
> [here][observablehq].

This package provides a Julia string literal, `htl`, and macro `@htl`
that return an object that can be rendered to `"text/html"` displays.
Unlike the built-in `HTML` object, this macro supports interpolation to
support context-sensitive escaping and other clever fatures. Here we
show an example using triple-quoted `htl` string literal, notice how
ampersands are properly escaped in the book name and author listing.

    using HypertextLiteral

    books = [
     (name="Who Gets What & Why", year=2012, authors=["Alvin Roth"]),
     (name="Switch", year=2010, authors=["Chip Heath", "Dan Heath"]),
     (name="Governing The Commons", year=1990, authors=["Elinor Ostrom"]),
     (name="Peopleware", year=1987, authors=["Tom Demarco", "Tim Lister"])]

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
      <tr><td>Who Gets What &amp; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &amp; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
      <tr><td>Peopleware (1987)<td>Tom Demarco &amp; Tim Lister
    </tbody></table>
    =#

We use [NarrativeTest][nt] to ensure our examples are correct. After
each command is a comment with the expected output. This README can be
validated by running `./test/runtests.jl` on the command line. So that
we can more easily see content as rendered to `"text/html"`, let's
define `@print` as follows.

    macro print(expr)
        :(display("text/html", $expr))
    end

We could then see output of `htl"<span>Hello</span>"` using `@print` on
the subsequent line, prefixed by `"->`.

    @print htl"<span>Hello World</span>"
    #-> <span>Hello World</span>

## Basic Operations

This package, `HypertextLiteral` provides an `htl` string literal and
`@htl` function macro which produce objects that render to `"text/html"
mimetype, implementing interpolation with convenient data conversions.

    using HypertextLiteral

    book = "Strunk & White"

    @print htl"<span>Today's Reading: $book</span>"
    #-> <span>Today's Reading: Strunk &amp; White</span>

Besides simple string interpolation, there is an implicit conversion of
`Number` values to their `String` representation.

    var = 3

    @print htl"$var"
    #-> 3

Within an `htl` string, Julia results can be interpolated.

    @print htl"2+2 = $(2+2)"
    #-> 2+2 = 4

To include a literal `$` in the output string, use `\$`.

    @print htl"\$42.50"
    #-> $42.50

Interpolated strings are escaped.

    var = "3<4 & 5>4"

    @print htl"$var"
    #-> 3&lt;4 &amp; 5>4

If a variable is already a `HTML` object, it is not further escaped.

    var = html"<span>no-escape</span>"

    @print htl"$var"
    #-> <span>no-escape</span>

Of course, more than one variable can be interpolated.

    s = "World"
    n = 42

    @print htl"Hello $s, $n"
    #-> Hello World, 42

Functions returning values can be included in an interpolation, this
uses the Julia syntax `$(expr)`.

    sq(x) = x*x

    @print htl"3 squared is $(sq(3))"
    #-> 3 squared is 9

Functions returning string values will be escaped.

    input() = "<script>alert('ouch!')"

    @print htl"$(input())"
    #-> &lt;script>alert('ouch!')

Functions returning HTML fragments are passed on, as-is.

    frag() = html"<span>Hello!</span>"

    @print htl"$(frag())"
    #-> <span>Hello!</span>

## Context Sensitive Escaping

There is extensive support for attribute generation. First, quoted
attributes are escaped. Within double quotes, the double quote is
escaped. Within single quotes, the single quote is escaped.

    qval = """has " & '"""

    @print htl"""<tag dq="$qval" sq='$qval' />"""
    #-> <tag dq="has &quot; &amp; '" sq='has " &amp; &apos;' />

Within bare attributes, space, ampersand, and less-than are quoted.

    @print htl"""<tag att=$("one" * " " * "& two > three") />"""
    #-> <tag att=one&#32;&amp;&#32;two&#32;&gt;&#32;three />

Within element content and attribute values, `Symbol` and `Number`
values are treated as string content (and escaped).

    @print htl"""<tag a=$(:one) b="$(:two)" c='$(:three)'>$(:four)</tag>"""
    #-> <tag a=one b="two" c='three'>four</tag>

    @print htl"""<tag a=$(1.0) b="$(2.0)" c='$(3.0)'>$(4.0)</tag>"""
    #-> <tag a=1.0 b="2.0" c='3.0'>4.0</tag>

## Expression Translation

This package attempts to convert common string literal conventions from
their Julia equivalent.

    @print htl"""<ul>$([ htl"<li>$x</li>" for x in ["A", "B&C"]])</ul>"""
    #-> <ul><li>A</li><li>B&amp;C</li></ul>

This technique works with arbitrary Julia expressions.

    @print htl"""<ul>$(map(["A", "B&C"]) do x htl"<li>$x</li>" end)</ul>"""
    #-> <ul><li>A</li><li>B&amp;C</li></ul>

## HTL Macro

These same operations can be invoked using the `@htl` macro. Note that
unlike the string literal, arbitrary nesting is possible even while
using only single quotes.

    book = "Strunk & White"

    @print @htl("<span>Today's Reading: $book</span>")
    #-> <span>Today's Reading: Strunk &amp; White</span>

    @print @htl("<ul>$([ @htl("<li>$x</li>") for x in ["A", "B&C"]])</ul>")
    #-> <ul><li>A</li><li>B&amp;C</li></ul>

## Design Discussion

The Julia ecosystem provides an `HTML` data type as part of its built-in
documentation package. We use this data type to indicate that a string
value is intended to be syntactically valid hypertext.

    @print html"<span>Hello World!</span>"
    #-> <span>Hello World!</span>

Julia uses `$` for string interpolation syntax, letting local variables
or arbitrary expressions be accessed. However, it doesn't know about
proper escaping in the context of hypertext content.

    book = "Strunk & White"

    "<span>Today's Reading: $book</span>"
    #-> "<span>Today's Reading: Strunk & White</span>"

Conversely, the built-in the `html` string literal doesn't provide
interpolation, the `$` character is simply that, a dollar sign.

    @print html"<span>Today's Reading: $book</span>"
    #-> <span>Today's Reading: $book</span>

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

    @print htl"""$("Hello")"""
    #-> Hello

Only that internal string literals like this are properly escaped.

    @print htl"""Look, Ma, $("<i>automatic escaping</i>")!"""
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

We cannot reliably detect interpolated string literals using the `@htl`
macro, so they are errors (in the cases we can find them).

    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

We can nest literal expressions, so long as the outer nesting uses
triple quotes.

    @print htl"""$( htl"Hello" )"""
    #-> Hello

We should be able to nest these arbitrarily deep. Perhaps this is
something we can fix...

    @print htl"""$( htl"$( htl"Hello" )" )"""
    #-> ERROR: LoadError: Base.Meta.ParseError⋮

## Edge Cases & Regression Tests

In Julia, to support regular expressions and other formats, string
literals don't provide regular escaping semantics. This package adds
those semantics.

    @print htl"Hello\World"
    #-> ERROR: LoadError: ArgumentError: invalid escape sequence⋮

    @print @htl "Hello\World"
    #-> ERROR: syntax: invalid escape sequence⋮

Escaped strings should just pass-though.

    htl"\"\\\n"
    #-> HTL("\"\\\n")

    @htl("\"\\\n")
    #-> HTL("\"\\\n")

Note that Julia has interesting rules when an escape precedes a double
quote, see `raw_str` for details. This is one case where the `htl`
string macro cannot be made equivalent to regular string interpretation.

    htl"\\\"\n"
    #-> HTL("\"\n")

    @htl("\\\"\n")
    #-> HTL("\\\"\n")

To prevent interpolation, use `\` for an escape.

    @print htl"\$42.00"
    #-> $42.00

    @print @htl("\$42.00")
    #-> $42.00

Interpolation should handle splat and concatenate.

    @print htl"$([x for x in [1,2,3]]...)"
    #-> 123

    @print @htl "$([x for x in [1,2,3]]...)"
    #-> 123

However, it shouldn't concatenate by default.

    @print htl"$([x for x in 1:3])"
    #=>
    ERROR: DomainError with [1, 2, 3]:
      Type Array{Int64,1} lacks a show method for text/html.
      Perhaps use splatting? e.g. htl"$([x for x in 1:3]...)
    =#

    @print @htl "$([x for x in 1:3])"
    #=>
    ERROR: DomainError with [1, 2, 3]:
      Type Array{Int64,1} lacks a show method for text/html.
      Perhaps use splatting? e.g. htl"$([x for x in 1:3]...)
    =#

Bare string literals cannot be used with macro either.

    @print @htl "$("bare")"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

A string ending with `$` is an syntax error since it is an incomplete
interpolation.

    @print htl"$"
    #-> ERROR: LoadError: "invalid interpolation syntax"⋮

    @print htl"Foo$"
    #-> ERROR: LoadError: "invalid interpolation syntax"⋮


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
