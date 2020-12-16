# Design

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

To discuss the design in more depth, let's restart our environment.

    using HypertextLiteral

    macro print(expr)
        :(display("text/html", $expr))
    end

## Implementation Notes

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

This has tangible effect on expressions.

    print(@htl("$(("<'", "\"&"))"))
    #-> &lt;&apos;&quot;&amp;

    print(htl"""$(("<'", "\\"&"))""")
    #-> &lt;&apos;&quot;&amp;

## Regression Tests

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

Here's something that perhaps should work... but fails currently.

    # htl"<div $(:dataValue=>42, "data-style"=>:green)/>

