# HypertextLiteral.jl

This package provides a Julia string literal, `htl`, and macro `@htl`
that return an object that can be rendered to `MIME"text/html"`
displays. These macros support context-sensitive interpolation sensible
to the needs of HTML generation.

    using HypertextLiteral

We use `NarrativeTest.jl` to ensure our examples are correct. After each
command is a comment with the expected output. This tool ensures the
README can be validated by running `./test/runtests.jl`. To enhance
readability, we define the following macro.

    macro print(expr)
        :(display("text/html", $expr))
    end

`HypertextLiteral` provides an `htl` string literal and equivalent
`@htl` macro that implement contextual escaping and expression
interpolation, producing `HTL` objects that render to `"text/html"`.

    htl"<span>Hello World</span>"
    #-> HTL("<span>Hello World</span>")

    @htl("<span>Hello World</span>")
    #-> HTL("<span>Hello World</span>")

An `HTL` object can be rendered to `"text/html"` with `display()`.
The expected output is shown in the comment below the command.

    display("text/html", htl"<span>Hello World</span>")
    #-> <span>Hello World</span>

In this tutorial, we use the `@print` macro defined above to increase
readability without having to type this `display` function.

    @print htl"<span>Hello World</span>"
    #-> <span>Hello World</span>

## Content Interpolation

Hypertext literal provides interpolation via `$`. Within element
content, both the ampersand (`&`) and less-than (`<`) are escaped.

    book = "Strunk & White"

    @print htl"<span>Today's Reading: $book</span>"
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

    arg = "book=Strunk & White"

    @print htl"<tag bare=$arg />"
    #-> <tag bare=book&#61;Strunk&#32;&#38;&#32;White />

Attributes may also be provided by `Dict` or `Pair`. Attribute names
provided as a `String` are passed though as-is, while `Symbol` values go
though `camelCase` case conversion. For those that prefer unix style
names, underscores to dash conversion is also provided.

     attributes = Dict(:dataValue => 42, "data-style" => :green )

     @print @htl("<div $attributes/>")
     #-> <div data-value=42 data-style=green/>

     @print @htl("<div $(:data_value=>42) $("data-style"=>:green)/>")
     #-> <div data-value=42 data-style=green/>

Within string literals (but not `@htl` macro), a compact syntax inspired
by named tuples is also supported.

     @print htl"<div $(data_value=42, dataStyle=:green)/>"
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

## Cascading Style Sheets

There is special support for the *unquoted* `"style"` attribute. In this
case, `Pair` and `Dict` values are expanded as style attributes
separated by the semi-colon (`;`). Style names that are `Symbol` values
go though `camelCase` conversion to `camel-case`, while `String` values
are passed along as-is.

    header_styles = Dict(:fontSize => "25px", "padding-left" => "2em")

    @print htl"<div style=$header_styles/>"
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print htl"""<div style=$(:fontSize=>"25px","padding-left"=>"2em")/>"""
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

    @print htl"""<div style=$(fontSize="25px",paddingLeft="2em")/>"""
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

Only symbols, numbers, and strings have a specified serialization as css
style values. Therefore, use of components from other libraries will
cause an exception.  However, this can be fixed by registering a
conversion using `css_value()`.

    using Hyperscript

    HypertextLiteral.css_value(x::Hyperscript.Unit) = string(x)

Then, the syntax for CSS can be even more compact.

    @print htl"<div style=$(fontSize=25px,paddingLeft=2em)/>"
    #-> <div style=font-size:&#32;25px;padding-left:&#32;2em;/>

For the *unquoted* `"class"` attribute, a `Vector` provides a space
between each of the elements.

    @print @htl("<div class=$([:one, :two])/>")
    #-> <div class=one&#32;two/>

    @print htl"<div class=$(:one, :two)/>"
    #-> <div class=one&#32;two/>

## Design Discussion and Custom Extensions

So that we could distinguish between regular strings and strings that
are meant to be hypertext, we define the type `HTL` which is an array
containing `String` values, which are assumed to be valid hypertext, and
objects that are `Multimedia.showable` as `"text/html"`.

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

This can be addressed by implementing the `"text/html" mimetype in
`Base.show` for the custom type in question. In this case, be sure to
escape ampersand (`&`) and less-than (`<`).

     struct Custom data::String end

     function Base.show(io::IO, mime::MIME"text/html", c::Custom)
         value = replace(replace(c.data, "&" => "&amp;"), "<" => "&lt;")
         print(io, "<custom>$(value)</custom>")
     end

     @print @htl("<span>$(Custom("a&b"))</span>")
     #-> <span><custom>a&amp;b</custom></span>

In this conservative approach, unknown types are not simply stringified
when they are used in element content or as an array value. Instead,
they produce an error.

    struct Custom data::String end

    @htl("<tag data-custom=$(Custom("a&b"))/>")
    #=>
    ERROR: DomainError with …Custom("a&b"):
      Unable to convert …Custom for use as an attribute value;
      convert to a string or, for a specific attribute, implement a
      `Base.show` method using `HTLAttribute` (and `htl_escape`)
    =#

We could tell HTL how to serialize our `Custom` values to the
`data-custom` attribute by implementing `Base.show` using
`HTLAttribute`, as show below.

    import HypertextLiteral: HTLAttribute, htl_escape

    struct Custom data::String end

    Base.show(io::IO, at::HTLAttribute{Symbol("data-custom")}, value::Custom) =
        print(io, htl_escape(value.data))

    @print @htl("<tag data-custom=$(Custom("a&b"))/>")
    #-> <tag data-custom=a&#38;b/>

    @print @htl("<tag $(:dataCustom => Custom("a&b"))/>")
    #-> <tag data-custom=a&#38;b/>

So that the scope of objects serialized in this manner is clear, we
don't permit adjacent unquoted values.

    htl"<tag bare=$(true)$(:invalid)"
    #=>
    ERROR: LoadError: DomainError with bare=true:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

To have a convenient notation, our string macro syntax interpolate
tuples and generated expressions as concatinated output. This is
currently not supported by `@htl` macro (see Julia ticket #38734).

    a = "A"
    b = "B"

    @print htl"$(a,b)"
    #-> AB

    @print htl"$(x for x in (a,b))"
    #-> AB

    @htl("$(x for x in (a,b))")
    #-> ERROR: syntax: invalid interpolation syntax

While assigment operator is permitted in Julia string interpolation, we
exclude it in both string literal and macro forms so to guard against
accidentially forgetting the trailing comma for a 1-tuple.

    @print htl"""<div $(dataValue=42,)/>"""
    #-> <div data-value=42/>

    htl"""<div $(dataValue=42)/>"""
    #=>
    ERROR: LoadError: DomainError with dataValue = 42:
    assignments are not permitted in an interpolation⋮
    =#

    @htl("<div $(dataValue=42)/>")
    #=>
    ERROR: LoadError: DomainError with dataValue = 42:
    assignments are not permitted in an interpolation⋮
    =#

Even though booleans are considered numeric in Julia, we treat them as
an error to guard against quoted use in boolean HTML attributes.

    htl"<button checked='$(true)'"
    #=>
    ERROR: DomainError with true:
      Unable to convert Bool for use as an attribute value;
      convert to a string or, for a specific attribute, implement a
      `Base.show` method using `HTLAttribute` (and `htl_escape`)
    =#

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
          value: ….Custom
            data: String "a&b"
        3: String "</span>"
    =#

## Quirks & Regression

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

    #? VERSION >= v"1.6.0-DEV"
    @htl "$("Hello")"
    #-> HTL("Hello")

Before v1.6, we cannot reliably detect interpolated string literals
using the `@htl` macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
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
      Unable to convert Vector{Int64} for use as an attribute value;
      convert to a string or, for a specific attribute, implement a
      `Base.show` method using `HTLAttribute` (and `htl_escape`)
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
      Type Vector{Int64} lacks a show method for text/html.
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

Unquoted interpolation adjacent to a raw string is also an error.

    htl"<tag bare=literal$(:invalid)"
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

    htl"<tag bare=$(invalid)literal"
    #=>
    ERROR: LoadError: DomainError with bare=invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

We limit string interpolation to symbols or parenthesized expressions.
For more details on this see Julia #37817.

    htl"$[1,2,3]"
    #=>
    ERROR: LoadError: DomainError with [1, 2, 3]:
    interpolations must be symbols or parenthesized⋮
    =#

    @htl("$[1,2,3]")
    #=>
    ERROR: syntax: invalid interpolation syntax: "$["⋮
    =#

Before Julia v1.6 (see issue #38501), string literals should not be used
within the macro style since we cannot reliably detect them.

    x = ""

    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &#60;script>alert('Hello')&#60;/script>

    #? VERSION >= v"1.6.0-DEV"
    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &#60;script>alert('Hello')&#60;/script>

    #? VERSION < v"1.6.0-DEV"
    @print @htl("$x$("<script>alert(\"Hello\")</script>")")
    #-> <script>alert("Hello")</script>

Hence, for a cases where we could detect a string literal, we raise an
error condition to discourage its use. The string macro form works.

    @print htl"""<tag>$("escape&me")</tag>"""
    #-> <tag>escape&#38;me</tag>

    #? VERSION >= v"1.6.0-DEV"
    @print @htl "<tag>$("escape&me")</tag>"
    #-> <tag>escape&#38;me</tag>

    #? VERSION < v"1.6.0-DEV"
    @print @htl "<tag>$("escape&me")</tag>"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

A string ending with `$` is an syntax error since it is an incomplete
interpolation.

    @print htl"$"
    #-> ERROR: LoadError: "missing interpolation expression"⋮

    @print htl"Foo$"
    #-> ERROR: LoadError: "missing interpolation expression"⋮

Here's something that perhaps should work... but fails currently.

    # htl"<div $(:dataValue=>42, "data-style"=>:green)/>

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
  `"class"` and, eventually, `"script"`.

* Full coverage of HTML syntax is ideal, but unnecessary.

