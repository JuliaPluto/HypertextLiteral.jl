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
support context-sensitive escaping and other clever features. Here we
show an example using triple-quoted `htl` string literal, notice how
ampersands are properly escaped in the book name and author listing.

    using HypertextLiteral

    books = [
     (name="Who Gets What & Why", year=2012, authors=["Alvin Roth"]),
     (name="Switch", year=2010, authors=["Chip Heath", "Dan Heath"]),
     (name="Governing The Commons", year=1990, authors=["Elinor Ostrom"])]

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
      <tr><td>Who Gets What &#38; Why (2012)<td>Alvin Roth
      <tr><td>Switch (2010)<td>Chip Heath &#38; Dan Heath
      <tr><td>Governing The Commons (1990)<td>Elinor Ostrom
    </tbody></table>
    =#

We use [NarrativeTest][nt] to ensure our examples are correct. After
each command is a comment with the expected output. This tool ensures
the README can be validated by running `./test/runtests.jl`. To enhance
readability, we define the following macro.

    macro print(expr)
        :(display("text/html", $expr))
    end

## Introduction to Hypertext Literal

`HypertextLiteral` provides an `htl` string literal and equivalent
`@htl` macro that implement contextual escaping and expression
interpolation, producing `HTL` objects that render to `"text/html"`.

    htl"<span>Hello World</span>"
    #-> HTL("<span>Hello World</span>")

An `HTL` object can be rendered to `"text/html"` with `display()`.

    display("text/html", htl"<span>Hello World</span>")
    #-> <span>Hello World</span>

In this tutorial, we use the `@print` macro defined above to increase
readability without having to type this `display` function.

    @print htl"<span>Hello World</span>"
    #-> <span>Hello World</span>

Hypertext literal provides interpolation via `$`. Within interpolated
content, both the ampersand (`&`) and less-than (`<`) are escaped.

    book = "Strunk & White"

    @print htl"<span>Today's Reading: $book</span>"
    #-> <span>Today's Reading: Strunk &#38; White</span>

Equivalently, in macro form, we can write:

    @print @htl("<span>Today's Reading: $book</span>")
    #-> <span>Today's Reading: Strunk &#38; White</span>

To include a literal `$` in the output string, use `\$` as one would in
a regular Julia string. Other escape sequences, such as `\"` also work.

    @print htl"They said, \"your total is \$42.50\"."
    #-> They said, "your total is $42.50".

String literals can also be triple-quoted, which could span multiple
lines. Within triple quotes, single quoted strings can go unescaped,
however, we still need to escape the dollar sign (`$`).

    @print htl"""They said, "your total is \$42.50"."""
    #-> They said, "your total is $42.50".

Within any of these forms, Julia results can be interpolated using the
`$(expr)` notation. Numeric values are automatically converted to their
string representation.

    @print htl"2+2 = $(2+2)"
    #-> 2+2 = 4

Functions returning string values will be escaped.

    input() = "<script>alert('a&b!')"

    @print htl"$(input())"
    #-> &#60;script>alert('a&#38;b!')

Functions returning `HTL` objects are not further escaped. This permits
us to build reusable HTML templates.

    sq(x) = htl"<span>$(x*x)</span>"

    @print htl"<div>3^2 is $(sq(3))</div>"
    #-> <div>3^2 is <span>9</span></div>

Within a triple-quoted `htl` string, a single-quoted `htl` string can be
included. This technique only works for one level of nesting.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @print htl"""<ul>$([htl"<li>$b" for b in books])</ul>"""
    #=>
    <ul><li>Who Gets What &#38; Why<li>Switch<li>Governing The Commons</ul>
    =#

The equivalent macro syntax supports arbitrary levels of nesting. Here
we show only one level of nesting.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @print @htl("<ul>$(map(books) do b @htl("<li>$b") end)</ul>")
    #=>
    <ul><li>Who Gets What &#38; Why<li>Switch<li>Governing The Commons</ul>
    =#

List comprehensions and functions returning lists work within hypertext
literals because elements of a `Vector{HTL}` value are concatenated.

## Attribute Interpolation

Escaping of Julia values depends upon the context. For attributes,
escaping depends upon quoting style. Within double quotes, the double
quote is escaped. Within single quotes, the single quote is escaped.

    qval = "\"h&b'"

    @print htl"""<tag double="$qval" single='$qval' />"""
    #-> <tag double="&#34;h&#38;b'" single='"h&#38;b&#39;' />

Unquoted attributes are supported. Here the escaping is extensive. Note
that adjacent expressions (not separated by a space) are permitted, the
resulting attribute value is concatenated.

    one = "key="
    two = "bing >"

    @print htl"<tag bare=$one$two />"
    #-> <tag bare=key&#61;bing&#32;&#62; />

Symbols and numbers are automatically converted within attributes.

    @print htl"<tag one=$(0) sym=$(:sym) qone='$(1.0)' qsym='$(:sym)' />"
    #-> <tag one=0 sym=sym qone='1.0' qsym='sym' />

Within bare attributes, boolean values provide special support for
boolean HTML properties, such as `"disabled"`. When a bare value `false`
then the attribute is removed. When the value is `true` then the
attribute is kept, with value being an empty string (`''`).

    @print htl"<button checked=$(true) disabled=$(false)>"
    #-> <button checked=''>

Within attributes, independent of quoting style, other datatypes are
treated as an error. This includes `Vector` as well as `HTL` objects.

    htl"<tag att='$([1,2,3])'"
    #=>
    ERROR: DomainError with [1, 2, 3]:
      Unable to convert Array{Int64,1} to an attribute; either expressly
      convert to a string, or provide an `htl_render_attribute` method
    =#

There is special support for the unquoted `"style"` attribute. In this
case, `Pair` and `Dict` objects are expanded as style attributes
separated by the semi-colon (`;`). Style names that are `Symbol` objects
go though `camelCase` conversion to `camel-case`.

    header_styles = Dict(:fontSize => "25px", "padding-left" => "2em")

    @print htl"<div style=$header_styles/>"
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print @htl("<div style=$(:fontSize=>"25px")$("padding-left"=>"2em")/>")
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print htl"""<div style=$(:fontSize=>"25px","padding-left"=>"2em")/>"""
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

Similarly, attributes may be provided by `Dict` or though `Pair`
objects. Attribute names provided as strings are passed though as-is,
while `Symbol` values go though `camelCase` case conversion.

     attributes = Dict(:dataValue => 42, "class" => :green )

     @print htl"<div $attributes/>"
     #-> <div data-value=42 class=green/>

     @print htl"""<button $(:disabled=>false,:class=>"large shadow")>"""
     #-> <button class=large&#32;shadow>

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
    #-> Look, Ma, &#60;i>automatic escaping&#60;/i>!

We cannot reliably detect interpolated string literals using the `@htl`
macro, so they are errors (in the cases we can find them).

    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &#60;i>automatic escaping&#60;/i>!

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

    htl"Hello\World"
    #-> ERROR: LoadError: ArgumentError: invalid escape sequence⋮

    @htl "Hello\World"
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

Within an unquoted attribute value, we must escape whitespace, the
ampersand (&), quotation ("), greater-than (>), less-than (<),
apostrophe ('), grave accent (`), and equals (=) characters.

     escape_me = " \t\n\"&><'`="

     @print htl"<tag quot=$escape_me/>"
     #-> <tag quot=&#32;&#9;&#10;&#34;&#38;&#62;&#60;&#39;&#96;&#61;/>

Symbols are also properly handled; e.g. escaping happens after
conversion of numbers, symbols and custom types to strings.

    @print htl"""<tag att=$(Symbol(">3"))>$(Symbol("a&b"))</tag>"""
    #-> <tag att=&#62;3>a&#38;b</tag>

Boolean valued attributes should not have two interpolated values.

    htl"<tag att=$(true)$(:anything)/>"
    #-> ERROR: "Too many values for boolean attribute `att`"

    htl"<tag att=$(false)$(1.0)/>"
    #-> ERROR: "Too many values for boolean attribute `att`"

Even though booleans are considered numeric in Julia, we treat them as
an error to guard against quoted use in boolean HTML attributes.

    htl"<button checked='$(true)'"
    #=>
    ERROR: DomainError with true:
      Unable to convert Bool to an attribute; either expressly
      convert to a string, or provide an `htl_render_attribute` method
    =#

Interpolation should handle splat and concatenate.

    @print htl"$([x for x in [1,2,3]]...)"
    #-> 123

    @print @htl "$([x for x in [1,2,3]]...)"
    #-> 123

However, it shouldn't concatenate lists by default, or assume treatment
of any other sorts of native Julia objects.

    @print htl"$([x for x in 1:3])"
    #=>
    ERROR: DomainError with [1, 2, 3]:
      Type Array{Int64,1} lacks a show method for text/html.
      Perhaps use splatting? e.g. htl"$([x for x in 1:3]...)
    =#

String literals should not be used within the macro style since we
cannot reliably detect them. Here is an example usage where the macro
style lets an unescaped string literal though the gaps; this requires
Julia issue #38501 to be addressed before we could catch this case.
Observe that the string macro form can detect and properly escape.

    x = ""

    @print htl"""$x$("should escape (<)")"""
    #-> should escape (&#60;)

    @print @htl("$x$("should escape (<)")")
    #-> should escape (<)

Hence, for a cases where we could detect a string literal, we raise an
error condition to discourage its use. The string macro form works.

    @print @htl "$("escape&me")"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

    @print htl"""$("escape&me")"""
    #-> escape&#38;me

In particular, these three cases have the same representation provided to
the interpolation code, and since we can't distinguish among them, we
raise an error for all.

    @print @htl "one$("two")"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

    @print @htl "$("one")two"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

    @print @htl "$("one")$("two")"
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
