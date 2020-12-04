# HypertextLiteral.jl

*HypertextLiteral is a Julia package for generating [HTML][html],
[SVG][svg], and other [SGML][sgml] tagged content. It works similar to
Julia string interpolation, only that it tracks hypertext escaping needs
and provides handy conversions dependent upon context.*

> This project is inspired by [Hypertext Literal][htl] by Mike Bostock
> ([@mbostock][@mbostock]) available at [here][observablehq]. This work
> is based upon a port to Julia written by Michiel Dral.

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
      $(render_row(b) for b in books)</tbody></table>"""

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
* Handles boolean valued HTML attributes, such as `disabled`, `checked`
* Representation of Julia `Pair` and `Dict` as unquoted attributes
* Special handling of "style" attribute via Julia `Pair` and `Dict`
* Automatic `camelCase` => `camel-case` conversion for attributes & styles
* Detection of `script` and `style` tags to suppress escaping
* Direct inclusion of objects (like `HTML`) showable by `MIME"text/html"`
* Implements both string macros `@htl_str` and regular macros `@htl`

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

Hypertext literal provides interpolation via `$`. Within element
content, both the ampersand (`&`) and less-than (`<`) are escaped.

    book = "Strunk & White"

    @print htl"<span>Today's Reading: $book</span>"
    #-> <span>Today's Reading: Strunk &#38; White</span>

Equivalently, in macro form, we can write:

    @print @htl("<span>Today's Reading: $book</span>")
    #-> <span>Today's Reading: Strunk &#38; White</span>

To include a literal `$` in the output, use `\$` as one would in a
regular Julia string. Other escape sequences, such as `\"` also work.

    @print htl"They said, \"your total is \$42.50\"."
    #-> They said, "your total is $42.50".

String literals can also be triple-quoted, allowing them to span
multiple lines. Within triple quotes, single quoted strings can go
unescaped, however, we still need to escape the dollar sign (`$`).

    @print htl"""They said, "your total is \$42.50"."""
    #-> They said, "your total is $42.50".

Within any of these forms, Julia results can be interpolated using the
`$(expr)` notation. Numeric values (including `Bool`) and symbols are
automatically converted to their string representation.

    @print htl"2+2 = $(2+2)"
    #-> 2+2 = 4

    @print htl"<bool>$(false)</bool><sym>$(:sym)</sym>"
    #-> <bool>false</bool><sym>sym</sym>

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

The equivalent macro syntax supports arbitrary levels of nesting,
although we only show one level of nesting here.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @print @htl("<ul>$(map(books) do b @htl("<li>$b") end)</ul>")
    #=>
    <ul><li>Who Gets What &#38; Why<li>Switch<li>Governing The Commons</ul>
    =#

## Attribute Interpolation

Escaping of Julia values depends upon the context: within a double
quoted attribute value, the double quote is escaped; single quoted
attributes are likewise escaped.

    qval = "\"h&b'"

    @print htl"""<tag double="$qval" single='$qval' />"""
    #-> <tag double="&#34;h&#38;b'" single='"h&#38;b&#39;' />

Unquoted attributes are also supported. Here the escaping is extensive.
Note that adjacent expressions (not separated by a space) are permitted.

    one = "key="
    two = "bing >"

    @print htl"<tag bare=$one$two />"
    #-> <tag bare=key&#61;bing&#32;&#62; />

Attributes may also be provided by `Dict` or though `Pair` objects.
Attribute names provided as a `String` are passed though as-is, while
`Symbol` values go though `camelCase` case conversion.

     attributes = Dict(:dataValue => 42, "data-style" => :green )

     @print htl"<div $attributes/>"
     #-> <div data-value=42 data-style=green/>

     @print htl"""<div $(:dataValue=>42, "data-style"=>:green)/>"""
     #-> <div data-value=42 data-style=green/>

As you can see from this example, symbols and numbers (but not boolean
values) are automatically converted within attributes. This works for
quoted values as well.

    @print htl"""<tag numeric="$(0)" symbol='$(:sym)'/>"""
    #-> <tag numeric="0" symbol='sym'/>

Within bare attributes, boolean values provide special support for
boolean HTML properties, such as `"disabled"`. When a bare value `false`
then the attribute is removed. When the value is `true` then the
attribute is kept, with value being an empty string (`''`).

    @print htl"<button checked=$(true) disabled=$(false)>"
    #-> <button checked=''>

There is special support for the *unquoted* `"style"` attribute. In this
case, `Pair` and `Dict` values are expanded as style attributes
separated by the semi-colon (`;`). Style names that are `Symbol` values
go though `camelCase` conversion to `camel-case`, while `String` values
are passed along as-is.

    header_styles = Dict(:fontSize => "25px", "padding-left" => "2em")

    @print htl"<div style=$header_styles/>"
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print @htl("<div style=$(:fontSize=>"25px")$("padding-left"=>"2em")/>")
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print htl"""<div style=$(:fontSize=>"25px","padding-left"=>"2em")/>"""
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

## Design Discussion and Custom Extensions

So that we could distinguish between regular strings and strings that
are meant to be hypertext, we define the type `HTL` which is an array
containing `String` values, which are assumed to be valid hypertext, and
objects that are [Multimedia.showable][showable] as `"text/html"`.

    htl"<span>Hello World!</span>"
    #-> HTL("<span>Hello World!</span>")

    display("text/html", HTL("<span>Hello World!</span>"))
    #-> <span>Hello World!</span>

We considered using `Docs.HTML` for this purpose, but it has the wrong
semantics. The `HTML` type it is intended to promote the `"text/plain"`
representation of any object to something showable as `"text/html"`.

    display("text/html", HTML(["<span>", HTML("content"), "</span>"]))
    #-> Any["<span>", HTML{String}("content"), "</span>"]

By contrast, `HTL` concatenates vectors and unwraps objects showable as
`"text/html"`. Like HTML, `String` values are assumed to be properly
escaped (the `htl` string literal and macro do this escaping).

    display("text/html", HTL(["<span>", HTL("content"), "</span>"]))
    #-> <span>content</span>

If one attempts to reference a user defined type, it will be an error.

    struct Custom data::String end

    HTL(Custom("a&b"))
    #=>
    ERROR: DomainError with …Custom("a&b"):
    Elements must be strings or objects showable as "text/html".
    =#

However, this can be addressed by implementing `Base.show` for the
custom type in question. In this case, be sure to escape ampersand
(`&`) and less-than (`<`).

     function Base.show(io::IO, mime::MIME"text/html", c::Custom)
         value = replace(replace(c.data, "&" => "&amp;"), "<" => "&lt;")
         print(io, "<custom>$(value)</custom>")
     end

     @print @htl("<span>$(Custom("a&b"))</span>")
     #-> <span><custom>a&amp;b</custom></span>

To increase usability on the command line, the default representation of
an `HTL` object is its equivalent pre-rendered string. Even so, the HTL
object retains component parts so they could be inspected.

    @htl("<span>$(Custom("a&b"))</span>")
    #-> HTL("<span><custom>a&amp;b</custom></span>")

    dump(@htl("<span>$(Custom("a&b"))</span>"))
    #=>
    HTL
      content: Array{Any}((3,))
        1: String "<span>"
        2: HypertextLiteral.ElementData
          value: ReadmeMd.Custom
            data: String "a&b"
        3: String "</span>"
    =#

## Quirks

Since this string format uses Julia macro processing, there are some
differences between an `htl` literal and native Julia interpolation.
For starters, Julia doesn't recognize and treat `$` syntax natively for
these macros, hence, at a very deep level parsing is different.

    "$("Hello")"
    #-> "Hello"

In this interpolation, the expression `"Hello"` is seen as a string, and
hence Julia can produce the above output. However, Julia does not given
this special treatment to string literals. Hence, if you try this
expression using `htl` you'll get an error.

    htl"$("Hello")"
    #-> ERROR: syntax: cannot juxtapose string literal

The above expression is seen by Julia as 3 tokens, `htl"$("`, followed
by `Hello`, and then `")`. This combination is a syntax error. One might
correct this using triple strings.

    htl"""$("Hello")"""
    #-> HTL("Hello")

Alternatively, in Julia v1.6+, one could use the HTL macro format.

    #? VERSION >= v"1.6"
    @htl "$("Hello")"
    #-> HTL("Hello")

Before v1.6, we cannot reliably detect interpolated string literals
using the `@htl` macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6"
    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &#60;i>automatic escaping&#60;/i>!

The string literal style is not without its quirks. See `@raw_str` for
exceptional cases where a slash immediately precedes the double quote.
This is one case where the `htl` string macro cannot be made to work in
a manner identical to regular string interpolation.

    htl"\\\"\n"
    #-> HTL("\"\n")

    @htl("\\\"\n")
    #-> HTL("\\\"\n")

## Regression Tests

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

Within attributes, independent of quoting style, other datatypes are
treated as an error. This includes `Vector` as well as `HTL` objects.

    htl"<tag att='$([1,2,3])'"
    #=>
    ERROR: DomainError with [1, 2, 3]:
      Unable to convert Array{Int64,1} to an attribute; either expressly
      convert to a string, or provide an `htl_render_attribute` method
    =#

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

Interpolation should handle splat operator by concatenating results.

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

The `script` and `style` tags use a "raw text" encoding where all
content up-to the end tag is not escaped using ampersands.

    book = "Strunk & White"
    @print htl"""<script>var book = "$book"</script>"""
    #-> <script>var book = "Strunk & White"</script>

We throw an error if the end tag is accidently included.

    bad = "</style>"

    htl"""<style>$bad</style>"""
    #=>
    ERROR: DomainError with "</style>":
      Content of <style> cannot contain the end tag (`</style>`).
    =#

Attribute names should be non-empty and not in a list of excluded
characters.

    @htl("<tag $("" => "value")/>")
    #=>
    ERROR: DomainError with :
    Attribute name must not be empty.
    =#

    @htl("<tag $("&att" => "value")/>")
    #=>
    ERROR: DomainError with &att:
    Invalid character ('&') found within an attribute name.
    =#

Before Julia v1.6 (see issue #38501), string literals should not be used
within the macro style since we cannot reliably detect them.

    x = ""

    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &#60;script>alert('Hello')&#60;/script>

    #? VERSION >= v"1.6"
    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &#60;script>alert('Hello')&#60;/script>

    #? VERSION < v"1.6"
    @print @htl("$x$("<script>alert(\"Hello\")</script>")")
    #-> <script>alert("Hello")</script>

Hence, for a cases where we could detect a string literal, we raise an
error condition to discourage its use. The string macro form works.

    @print htl"""$("escape&me")"""
    #-> escape&#38;me

    #? VERSION >= v"1.6"
    @print @htl "$("escape&me")"
    #-> escape&#38;me

    #? VERSION < v"1.6"
    @print @htl "$("escape&me")"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

A string ending with `$` is an syntax error since it is an incomplete
interpolation.

    @print htl"$"
    #-> ERROR: LoadError: "invalid interpolation syntax"⋮

    @print htl"Foo$"
    #-> ERROR: LoadError: "invalid interpolation syntax"⋮

## Contributing

We are absolutely open to suggested improvements. This package is
implemented according to several design criteria.

* Operation of interpolated expressions (`$`) should mirror what they
  would do with regular Julia strings, updated with hypertext escaping
  sensibilities including proper escaping and helpful representations.

* With exception of boolean attributes (which must be removed to be
  false), input is treated as-is and not otherwise modified.

* Interpolations having string values are injected "as-is" into the
  output (subject to context sensitive checking or escaping);
  conversely, non-string values may be given helpful interpretations.

* Given that this library will be used by content producers, it should
  be conservative, raising an error when invalid hypertext is discovered
  and only serializing Julia objects that have an express representation.

* There should be an extension API that permits custom data types to
  provide their own context-sensitive serialization strategies.

* As much processing (e.g. hypertext lexical analysis) should be done
  during macro expansion to reduce runtime and to report errors early.
  Error messages should guide the user towards addressing the problem.

* To be helpful, HTML tags and attributes may be recognized. Special
  behavior may be provided to attributes such as `"style"` (CSS),
  `"class"` and, eventually, `"script"`. What about CSS units?

* Full coverage of HTML is ideal. However, during early versions there
  may be poor coverage of `script`, CDATA, COMMENTS, etc.

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
[show]: https://docs.julialang.org/en/v1/base/io-network/#Base.show-Tuple{IO,Any,Any}
[showable]: https://docs.julialang.org/en/v1/base/io-network/#Base.Multimedia.showable
