# HypertextLiteral.jl

First, one must import `HypertextLiteral`

    using HypertextLiteral

## Basic Operations

We can construct a HTML object using the `htl` string macro. We use
Julia's built-in HTML data type to represent string values that should
not be further escaped.

    htl"<h1>Hello World!</h1>"
    #-> HTML{String}("<h1>Hello World!</h1>")

For strings that do not include `$` interpolation, the values are
equivalent as their raw `HTML` equivalent.

    htl"<h1>Hello World!</h1>" == html"<h1>Hello World!</h1>"
    #-> true

Quotes and slash characters survive this translation.

    htl"\"\\" == html"\"\\"
    #-> true

Interpolation of variables works.

    var = 3
    htl"$var"
    #-> HTML{String}("3")

To include a literal `$` in the output string, use `$$`.

    htl"$$42.50"
    #-> HTML{String}("\$42.50")

Strings are escaped. In the default `:content` context only less-than
(`<`) and amperstand (`&`) need conversion.

    var = "3<4 & 5>4"
    htl"$var"
    #-> HTML{String}("3&lt;4 &amp; 5>4")

If a variable is already a `HTML` string used in the default `:content`
context, it is not escaped.

    var = html"<span>no-escape</span>"
    htl"$var"
    #-> HTML{String}("<span>no-escape</span>")

Of course, more than one variable can be interpolated.

    s = "World"
    n = 42

    htl"Hello $s, $n"
    #-> HTML{String}("Hello World, 42")

## Quirks

Since this string format uses Julia macro processing, there are some
differences between an `htl` literal and native Julia interpolation.
For starters, Julia doesn't recognize and treat `$` syntax natively for
these macros, hence, at a very deep level parsing is different.

    "$("Hello")"
    #-> "Hello"

In this interplolation, the expression `"Hello"` is seen as a string,
and hence Julia can produce the above output. However, for `htl`, which
does not recognize `$` natively, the tokens are `htl"$("`, followed by
`Hello`, and then `")`. This is a syntax error.

    htl"$("Hello")"
    #-> ERROR: syntax: cannot juxtapose string literal

One might correct this using triple strings. It works as expected in
Julia land.

    """$("Hello")"""
    #-> "Hello"

When processed with `htl` macro, we could make it have a similar effect,
with output wrapped as a `HTML` string object. This is the current
behavior, but it's incorrect. We need to fix this.

    htl"""$("Hello")"""
    #-> HTML{String}("Hello")
