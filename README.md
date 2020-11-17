# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks escaping needs and
provides handy conversions dependent upon context.*

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]). You can read more about it
> [here][observablehq].

This package provides a string literal macro, `htl` which builds an
`HTML` object from a string template using Julia's interpolation syntax.
This works by using Julia's parser to generate an Abstract Syntax Tree
(AST). As hypertext fragments are discovered in a string expression, an
escaping context is tracked. Then, interpolation patterns discovered in
the AST are converted to use the correct form of escaping based upon the
hypertext's context.

After installing this Julia package, you could use it.

    using HypertextLiteral

## Introduction

The Julia ecosystem provides an `HTML` object type as part of its
built-in documentation package. This enables us to work with a string
knowing it is intended to be syntactically valid hypertext.

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
    #-> "Strunk & White"

    "<span>Book Recommendation: $book</span>"
    #-> "<span>Book Recommendation: Strunk & White</span>"

Conversely, the built-in the `html` string literal doesn't provide
interpolation, the `$` character is simply that, a dollar sign.

    html"<span>Book Recommendation: $book</span>"
    #-> HTML{String}("<span>Book Recommendation: \$book</span>")

This package, `HypertextLiteral` provides an `htl` string literal which
produces an `HTML` object, implementing common interpolation patterns
and convenient data conversions.

    htl"<span>Book Recommendation: $book</span>"
    #-> HTML{String}("<span>Book Recommendation: Strunk &amp; White</span>")

The remainder of this documentation reviews functionality provided by
the `htl` string macro. We use [NarrativeTest][nt] to ensure that the
examples provided here work as part of our regression tests. After each
command is a comment (staring with the pound sign `#`) that indicates
the output expected.

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

    company() = "Smith & Johnson"

    htl"$(company())"
    #-> HTML{String}("Smith &amp; Johnson")

Functions returning HTML fragments are passed on, as-is.

    frag() = html"<span>Hello!</span>"

    htl"$(frag())"
    #-> HTML{String}("<span>Hello!</span>")

## Expression Translation

This package attempts to convert common string literal conventions from
their Julia equivalent. For example, using string interpolation in
Julia, one could build a string list using the following.

    "<ul>$(map([1,2]) do x "<li>$x</li>" end)</ul>"
    #-> "<ul>[\"<li>1</li>\", \"<li>2</li>\"]</ul>"

Since all of the expressions here should be seen as HTML objects, we can
concatenate them. Note that a triple quote is needed in our case.

    htl"""<ul>$(map([1,2]) do x "<li>$x</li>" end)</ul>"""
    #-> HTML{String}("<ul><li>1</li><li>2</li></ul>")

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

That said, we are unable to automatically escape strings provided this
way (as found in mbostock's examples) since Julia's AST provides no
distinction between `"""$("<tag/>")"""` and just `"<tag/>"`.

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
