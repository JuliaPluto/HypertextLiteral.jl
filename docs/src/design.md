# Design

This package is implemented according to several design criteria.

* Operation of interpolated expressions (`$`) should (mostly) mirror
  what they would do with regular Julia strings, updated with hypertext
  escaping sensibilities including proper escaping.

* Speed of construction is critically important. This library is
  intended to be used deep within systems that generate extensive
  number of very large reports, interactively or in batch.

* With exception of boolean attributes (which must be removed to be
  false), input is treated as-is and not otherwise modified.

* Provide reasonable interpretation for `Dict`, `Vector` and other
  objects as element content, attributes, and attribute values; to
  ensure the library is predictable, these interpretations should
  not depend upon namespace, element name, or the attribute name.

* Since the `style` and `class` attributes are so important in HTML
  construction, universal interpretations of Julia constructs
  should make sense to aid these CSS attributes.

* There should be a discoverable and well documented extension API that
  permits custom data types to provide their own serialization
  strategies based upon syntactical context.

* By default, use of unknown objects is an error. However, it should
  be trivial to permit their usage via Julia method implementation.

* As much processing (e.g. hypertext lexical analysis) should be done
  during macro expansion to reduce runtime and to report errors early.
  We'll be slightly slower on interactive use to be fast in batch.

* Full coverage of HTML syntax or reporting syntax or semantic errors
  within the HTML content is not a goal.

To discuss the design in more depth, let's restart our environment.

    using HypertextLiteral

    macro print(expr)
        :(display("text/html", $expr))
    end

## Specific Design Decisions

Objects created by `@htl` are lazily constructed. What do we show on the
REPL? We decided to parrot back the macro expression.

    x = "Hello World"
    "Hello World"

    @htl("<span>$x</span>")
    #-> @htl "<span>$(x)</span>"

You could use the `print` command to evaluate the expression, showing
the `"text/html"` results.

    x = "Hello World"
    "Hello World"

    print(@htl("<span>$x</span>"))
    #-> <span>Hello World</span>

So that the scope of objects serialized in this manner is clear, we
don't permit adjacent unquoted values.

    htl"<tag bare=$(true)$(:invalid)"
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

While assignment operator is permitted in Julia string interpolation, we
exclude it in both notation and macro forms so to guard against
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

Symbols and Numeric values are properly escaped. While it is perhaps
faster to assume all `Symbol` and `Number` objects could never
contain invalid characters, we don't make this assumption.

    @print htl"""<tag att=$(Symbol("'&"))>$(Symbol("<&"))</tag>"""
    #-> <tag att='&apos;&amp;'>&lt;&amp;</tag>

Julia's regular interpolation stringifies everything. We don't do that
we treat a `Vector` as a sequence to be concatenated. Moreover, we let
the interpretation be customized though an extensive API.

    @print htl"$([x for x in 1:3])"
    #-> 123

    @print @htl "$([x for x in 1:3])"
    #-> 123

Since Julia's regular string interpolation works with the splat
operator, we implement this as well, by concatenating results.

    @print htl"$([x for x in 1:3]...)"
    #-> 123

    @print @htl "$([x for x in 1:3]...)"
    #-> 123

The `script` and `style` tags use a "raw text" encoding where all
content up-to the end tag is not escaped using ampersands.

    book = "Strunk & White"
    @print htl"""<script>var book = "$book"</script>"""
    #-> <script>var book = "Strunk & White"</script>

We throw an error if the end tag is accidently included. It is possible
to improve the public API to let this be customized.

    bad = "</style>"

    htl"""<style>$bad</style>"""
    #=>
    ERROR: DomainError with "</style>":
      Content of <style> cannot contain the end tag (`</style>`).
    =#

## String Macro Notes

We've designed to implement both the `@htl` macro and a `htl` string
syntax. For the most part, we've tried to keep them equivalent. The
`@htl` macro has significant advantages, so this is promoted.

* It can nest arbitrarily deep.
* It has syntax highlighting support.
* It has a robust implementation.

On the other hand, we implemented a string macro as well, for one
important reason -- it's more succinct for simple use cases. Further,
till Julia ticket #38734 is addressed, it'll be much nicer for named
tuples within attributes.

    @print htl"<tag $(att=:value,)/>"
    #-> <tag att='value'/>

    @print @htl("<tag $(att=:value,)/>")
    #-> ERROR: syntax: invalid interpolation syntax

This same ticket should also improve use of tuples and generators,
however, we can use the syntax macro till then.

    a = "A"
    b = "B"

    @print htl"$(a,b)"
    #-> AB

    @print htl"$(x for x in (a,b))"
    #-> AB

    @htl("$(x for x in (a,b))")
    #-> ERROR: syntax: invalid interpolation syntax

Before v1.6, we cannot reliably detect string literals using the `@htl`
macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

In particular, there are edge cases with the macro syntax where
unescaped string literal content can leak.

    x = ""

    #? VERSION < v"1.6.0-DEV"
    @print @htl("$x$("<script>alert(\"Hello\")</script>")")
    #-> <script>alert("Hello")</script>

The notation style is not without its quirks. See `@raw_str` for
exceptional cases where a slash immediately precedes the double quote.
This is one case where the `htl` notation cannot be made to work in a
manner identical to regular string interpolation.

    @print htl"(\\\")"
    #-> (")

    @print @htl("(\\\")")
    #-> (\")

This has tangible effect on the interpretation of expressions. This
cannot be fixed.

    print(@htl("$(("<'", "\"&"))"))
    #-> &lt;&apos;&quot;&amp;

    print(htl"""$(("<'", "\\"&"))""")
    #-> &lt;&apos;&quot;&amp;

Unlike macros, string macro format doesn't nest nicely.

    htl"$("Hello")"
    #-> ERROR: syntax: cannot juxtapose string literal

The above expression is seen by Julia as 3 tokens, `htl"$("`, followed
by `Hello`, and then `")`. This combination is a syntax error. One might
correct this using triple strings.

    @print htl"""$("Hello")"""
    #-> Hello

Finally, since the string macro includes its own top-level parser,
there's a chance of additional bugs. For example, we've manually
implemented traditional escaping.

## Regression Test Cases

Following are some edge cases we want to test.

    htl"Hello\World"
    #-> ERROR: LoadError: ArgumentError: invalid escape sequence⋮

    @htl "Hello\World"
    #-> ERROR: syntax: invalid escape sequence⋮

Escaped strings should just pass-though.

    @print htl"\"\t\\"
    #-> "	\

    @print @htl("\"\t\\")
    #-> "	\

Attribute names should be non-empty and not in a list of excluded
characters.

    @print @htl("<tag $("" => "value")/>")
    #-> ERROR: LoadError: "Attribute name must not be empty."⋮

    @print @htl("<tag $("&att" => "value")/>")
    #=>
    ERROR: LoadError: DomainError with &att:
    Invalid character ('&') found within an attribute name.⋮
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
