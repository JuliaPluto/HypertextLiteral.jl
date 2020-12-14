# HypertextLiteral.jl

This package provides a Julia string literal, `htl`, and equivalent
macro, `@htl`, that construct an object that could be rendered to
`MIME"text/html"` displays. These macros support context-sensitive
interpolation sensible to the needs of HTML generation.

    using HypertextLiteral

When printed directly to the console (via `show`), the output of these
macros reproduce a verified expression that generated them.

```julia
name = "World"

htl"<span>Hello $name</span>"
#-> htl"<span>Hello $name</span>"

@htl("<span>Hello $name</span>")
#-> @htl "<span>Hello $(name)</span>"
```

When displayed to `"text/html"` the evaluation is shown.

    name = "World"

    display("text/html", htl"<span>Hello $name</span>")
    #-> <span>Hello World</span>

    display("text/html", @htl("<span>Hello $name</span>"))
    #-> <span>Hello World</span>

We use `NarrativeTest.jl` to ensure our examples are correct. After each
command is a comment with the expected output. To enhance readability,
we'll also use the following macro.

    macro print(expr)
        :(display("text/html", $expr))
    end

    @print htl"<span>Hello World</span>"
    #-> <span>Hello World</span>

    @print @htl("<span>Hello World</span>")
    #-> <span>Hello World</span>

Throughout this tutorial, we'll mostly stick with the string literal form
of this macro, however, the `@htl` macro form should work equivalently,
except for a few cases we annotate.

## Content Interpolation

Hypertext literal provides interpolation via `$`. Within element
content, both the ampersand (`&`) and less-than (`<`) are escaped.

    book = "Strunk & White"

    @print @htl("<span>Today's Reading: $book</span>")
    #-> <span>Today's Reading: Strunk &amp; White</span>

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
    #-> &lt;script>alert(&apos;a&amp;b!&apos;)

Functions returning `HTL` objects are not further escaped. This permits
us to build reusable HTML templates.

    sq(x) = htl"<span>$(x*x)</span>"

    @print htl"<div>3^2 is $(sq(3))</div>"
    #-> <div>3^2 is <span>9</span></div>

Within a triple double-quoted `htl` string, a single double-quoted `htl`
string can be included. This technique works for one level of nesting.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @print htl"""<ul>$([htl"<li>$b" for b in books])</ul>"""
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

The equivalent macro syntax supports arbitrary levels of nesting,
although we only show one level of nesting here.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @print @htl("<ul>$(map(books) do b @htl("<li>$b") end)</ul>")
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

## Attribute Interpolation

Escaping of Julia values depends upon the context: within a double
quoted attribute value, the double quote is escaped; single quoted
attributes are likewise escaped.

    qval = "\"h&b'"

    @print htl"""<tag double="$qval" single='$qval' />"""
    #-> <tag double="&quot;h&amp;b'" single='"h&amp;b&apos;' />

Unquoted attributes are also supported. These are serialized using the
single quoted style.

    arg = "book='Strunk & White'"

    @print htl"<tag bare=$arg />"
    #-> <tag bare='book=&apos;Strunk &amp; White&apos;' />

Attributes may also be provided by `Dict` or `Pair`. Attribute names are
normalized, where `snake_case` becomes `kebab-case`. We do not convert
`camelCase` due to XML (MathML and SVG) attribute case sensitivity.
Moreover, `String` attribute names are passed along as-is.

     attributes = Dict(:data_style => :green, "data_value" => 42, )

     @print @htl("<div $attributes/>")
     #-> <div data-style='green' data_value='42'/>

     @print @htl("<div $(:data_style=>:green) $(:dataValue=>42)/>")
     #-> <div data-style='green' dataValue='42'/>

Within string literals (but not `@htl` macro), a compact syntax inspired
by named tuples is also supported.

     @print htl"<div $(data_style=:green, dataValue=42)/>"
     #-> <div data-style='green' dataValue='42'/>

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

Boolean values within quoted strings are returned as-is. We could make
this raise an error, however, there could be cases where this may be the
desired effect.

    @print htl"<button disabled='$(false)'>"
    #-> <button disabled='false'>

## Cascading Style Sheets

There is special support for the *unquoted* `"style"` attribute. In this
case, `Pair` and `Dict` values are expanded as style attributes
separated by the semi-colon (`;`). Like attributes, `snake_case` is
converted to `kebab-case`.

    header_styles = Dict(:font_size => "25px", "padding-left" => "2em")

    @print htl"<div style=$header_styles/>"
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

    @print htl"""<div style=$(:font_size=>"25px","padding-left"=>"2em")/>"""
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

    @print htl"""<div style=$(font_size="25px", padding_left="2em")/>"""
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

Only symbols, numbers, and strings have a specified serialization as CSS
style values. Therefore, use of components from other libraries will
cause an exception.  However, this can be fixed by registering a
conversion using `nested_value()`.

    using Hyperscript

    HypertextLiteral.nested_value(x::Hyperscript.Unit) = string(x)

Then, the syntax for CSS can be even more compact.

    @print htl"<div style=$(font_size=25px, padding_left=2em)/>"
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

For the *unquoted* `"class"` attribute, a `Vector` provides a space
between each of the elements.

    @print @htl("<div class=$([:one, :two])/>")
    #-> <div class='one two'/>

    @print htl"<div class=$(:one, :two)/>"
    #-> <div class='one two'/>

## Custom Extensions

We've seen our first extension, but it is specific to CSS. But how can
we serialize a custom data object within an interpolated result? If one
attempts to reference a user defined type, it will be an error.

    struct Custom data::String end

    @print @htl "$(Custom("a&b"))</tag>"
    #-> ERROR: MethodError: no method matching show(…"text/html"…Custom)⋮

This can be addressed by implementing the `"text/html" mimetype in
`Base.show` for the custom type in question. In this case, be sure to
escape ampersand (`&`) and less-than (`<`).

     struct Custom data::String end

     function Base.show(io::IO, mime::MIME"text/html", c::Custom)
         value = replace(replace(c.data, "&"=>"&amp;"), "<"=>"&lt;")
         print(io, "<custom>$(value)</custom>")
     end

     @print @htl("<span>$(Custom("a&b"))</span>")
     #-> <span><custom>a&amp;b</custom></span>

This approach of using `show(io, MIME"text/html"(), ...)` lets us
support many other systems out of the box without needing any glue.

    using Hyperscript
    @tags span

    @print @htl("<div>$(span("Hello World"))</div>")
    #-> <div><span>Hello World</span></div>

Displaying an object within an attribute...

    #TODO: show how this works here.

So that the scope of objects serialized in this manner is clear, we
don't permit adjacent unquoted values.

    htl"<tag bare=$(true)$(:invalid)"
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

To have a convenient notation, our string macro syntax interpolate
tuples and generated expressions as concatenated output. This is
currently not supported by `@htl` macro (see Julia ticket amp734).

    a = "A"
    b = "B"

    @print htl"$(a,b)"
    #-> AB

    @print htl"$(x for x in (a,b))"
    #-> AB

    @htl("$(x for x in (a,b))")
    #-> ERROR: syntax: invalid interpolation syntax

While assignment operator is permitted in Julia string interpolation, we
exclude it in both string literal and macro forms so to guard against
accidentally forgetting the trailing comma for a 1-tuple.

    @print htl"""<div $(data_value=42,)/>"""
    #-> <div data-value='42'/>

    htl"""<div $(data_value=42)/>"""
    #=>
    ERROR: LoadError: DomainError with data_value = 42:
    assignments are not permitted in an interpolation⋮
    =#

    @htl("<div $(data_value=42)/>")
    #=>
    ERROR: LoadError: DomainError with data_value = 42:
    assignments are not permitted in an interpolation⋮
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

    #? VERSION > v"1.5.0"
    htl"""$("Hello")"""
    #-> htl"$(\"Hello\")"

Alternatively, in Julia v1.6+, one could use the `@htl` macro format for
cases where there are string literals.

    #? VERSION >= v"1.6.0-DEV"
    @htl "$("Hello")"
    #-> @htl "$("Hello")"

Before v1.6, we cannot reliably detect interpolated string literals
using the `@htl` macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

The string literal style is not without its quirks. See `@raw_str` for
exceptional cases where a slash immediately precedes the double quote.
This is one case where the `htl` string macro cannot be made to work in
a manner identical to regular string interpolation.

    @print htl"(\\\")"
    #-> (")

    @print @htl("(\\\")")
    #-> (\")

In Julia, to support regular expressions and other formats, string
literals don't provide regular escaping semantics. This package adds
those semantics.

    htl"Hello\World"
    #-> ERROR: LoadError: ArgumentError: invalid escape sequence⋮

    @htl "Hello\World"
    #-> ERROR: syntax: invalid escape sequence⋮

Escaped strings should just pass-though.

    @print htl"\"\t\\"
    #-> "	\

    @print @htl("\"\t\\")
    #-> "	\

Within attributes, `Vector` objects are serialized as space separated
lists to support attributes such as `class`.

    @print htl"<tag att='$([1,2,3])'/>"
    #-> <tag att='1 2 3'/>

Symbols are also propertly escaped.

    @print htl"""<tag att=$(Symbol("'&"))>$(Symbol("<&"))</tag>"""
    #-> <tag att='&apos;&amp;'>&lt;&amp;</tag>

Interpolation should handle splat operator by concatenating results.

    @print htl"$([x for x in 1:3]...)"
    #-> 123

    @print @htl "$([x for x in 1:3]...)"
    #-> 123

Within element content, we treat a `Vector` as a sequence to be
concatenated.

    @print htl"$([x for x in 1:3])"
    #-> 123

    @print @htl "$([x for x in 1:3])"
    #-> 123

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
    #-> ERROR: "Attribute name must not be empty."

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
    ERROR: LoadError: DomainError with bare=literal:
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

Before Julia v1.6, string literals should not be used within the macro
style since we cannot reliably detect them.

    x = ""

    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &lt;script>alert(&apos;Hello&apos;)&lt;/script>

    #? VERSION >= v"1.6.0-DEV"
    @print htl"""$x$("<script>alert('Hello')</script>")"""
    #-> &lt;script>alert(&apos;Hello&apos;)&lt;/script>

    #? VERSION < v"1.6.0-DEV"
    @print @htl("$x$("<script>alert(\"Hello\")</script>")")
    #-> <script>alert("Hello")</script>

Hence, for a cases where we could detect a string literal, we raise an
error condition to discourage its use. The string macro form works.

    @print htl"""<tag>$("escape&me")</tag>"""
    #-> <tag>escape&amp;me</tag>

    #? VERSION >= v"1.6.0-DEV"
    @print @htl "<tag>$("escape&me")</tag>"
    #-> <tag>escape&amp;me</tag>

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

We are open to suggested improvements. This package is implemented
according to several design criteria.

* Operation of interpolated expressions (`$`) should (mostly) mirror
  what they would do with regular Julia strings, updated with hypertext
  escaping sensibilities including proper escaping.

* With exception of boolean attributes (which must be removed to be
  false), input is treated as-is and not otherwise modified.

* Provide reasonable interpretation for `Dict`, `Vector` and other
  objects as attributes, element content, or attribute values.

* As much processing (e.g. hypertext lexical analysis) should be done
  during macro expansion to reduce runtime and to report errors early.
  Error messages should guide the user towards addressing the problem.

* There should be an extension API that permits custom data types to
  provide their own serialization strategies that are not dependent upon
  the namespace, element name, or attribute name.

* Full coverage of HTML syntax or reporting syntax or semantic errors
  within the HTML content is not a goal.
