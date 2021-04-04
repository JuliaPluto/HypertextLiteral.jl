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

    @htl("<tag bare=$(true)$(:invalid)")
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

While assignment operator is permitted in Julia string interpolation, we
exclude it to guard it against accidently forgetting a comma.

    @print @htl("<div $((data_value=42,))/>")
    #-> <div data-value='42'/>

    @htl("<div $((data_value=42))/>")
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

    @print @htl("""<tag att=$(Symbol("'&"))>$(Symbol("<&"))</tag>""")
    #-> <tag att='&apos;&amp;'>&lt;&amp;</tag>

Julia's regular interpolation stringifies everything. We don't do that
we treat a `Vector` as a sequence to be concatenated. Moreover, we let
the interpretation be customized though an extensive API.

    @print @htl "$([x for x in 1:3])"
    #-> 123

Since Julia's regular string interpolation works with the splat
operator, we implement this as well, by concatenating results.

    @print @htl "$([x for x in 1:3]...)"
    #-> 123

Observe that `map()` is currently the most performant way to loop.

    @print @htl "$(map(1:3) do x; x; end)"
    #-> 123

The `script` and `style` tags use a "raw text" encoding where all
content up-to the end tag is not escaped using ampersands.

    book = "Strunk & White"
    @print @htl("""<script>var book = "$book"</script>""")
    #-> <script>var book = "Strunk & White"</script>

We throw an error if the end tag is accidently included. It is possible
to improve the public API to let this be customized.

    bad = "</style>"

    @htl("""<style>$bad</style>""")
    #=>
    ERROR: DomainError with "</style>":
      Content of <style> cannot contain the end tag (`</style>`).
    =#

## Detection of String Literals

Before v1.6, we cannot reliably detect string literals using the `@htl`
macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @print @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

In particular, there are edge cases where unescaped string literal
content can leak.

    x = ""

    #? VERSION < v"1.6.0-DEV"
    @print @htl("$x$("<script>alert(\"Hello\")</script>")")
    #-> <script>alert("Hello")</script>

Julia #38501 was fixed in v1.6.

    #? VERSION >= v"1.6.0-DEV"
    @print @htl "<tag>$("escape&me")</tag>"
    #-> <tag>escape&amp;me</tag>

## Regression Tests

Escaped strings are handled by `@htl` as one might expect.

    @print @htl("\"\t\\")
    #-> "	\

    @print @htl("(\\\")")
    #-> (\")

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

    @htl("<tag bare=literal$(:invalid)")
    #=>
    ERROR: LoadError: DomainError with :invalid:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

    @htl("<tag bare=$(invalid)literal")
    #=>
    ERROR: LoadError: DomainError with bare=literal:
    Unquoted attribute interpolation is limited to a single component⋮
    =#

String interpolation is limited to symbols or parenthesized expressions.
For more details on this see Julia #37817.

    @htl("$[1,2,3]")
    #=>
    ERROR: syntax: invalid interpolation syntax: "$["⋮
    =#

Literal content can contain Unicode values.

    x = "Hello"

    @print @htl("⁅$(x)⁆")
    #-> ⁅Hello⁆

Escaped content may also contain Unicode.

    x = "⁅Hello⁆"

    @print @htl("<tag>$x</tag>")
    #-> <tag>⁅Hello⁆</tag>

Ensure that dictionary style objects are serialized. See issue #7.

    let
        h = @htl("<div style=$(Dict("color" => "red"))>asdf</div>")
        repr(MIME"text/html"(), h)
    end
    #-> "<div style='color: red;'>asdf</div>"

Let's ensure that attribute values in a dictionary are escaped.

    @print @htl("<tag escaped=$(Dict(:esc=>"'&\"<"))/>")
    #-> <tag escaped='esc: &apos;&amp;&quot;&lt;;'/>

Let's ensure that attribute values in a dictionary are escaped.

    @print @htl("<tag escaped=$(Dict(:esc=>"'&\"<"))/>")
    #-> <tag escaped='esc: &apos;&amp;&quot;&lt;;'/>

Nothing within an attribute value within a quoted value or within
element content is treated as an empty string.

    @print @htl("<tag attribute='$(nothing)'>$(nothing)</tag>")
    #-> <tag attribute=''></tag>

Nothing as an attribute value omits the attribute just like `false`.
Nothing inside a tag is omitted as well.

    @print @htl("<tag omit=$(nothing) $(nothing)/>")
    #-> <tag/>

A `Pair` inside a tag is treated as an attribute.

    @print @htl("<tag $(:att => :value)/>")
    #-> <tag att='value'/>

A string or symbol inside a tag are treated as empty string attributes.

    @print @htl("<tag $(String(:one)) $(:two)/>")
    #-> <tag one='' two=''/>

A `Dict` inside a tag is treated as an attribute.

    @print @htl("<tag $(Dict(:att => :value))/>")
    #-> <tag att='value'/>

We don't handle comments within a script tag.

    @print @htl("<script><!-- comment --></script>")
    #-> ERROR: LoadError: "script escape or comment is not implemented"⋮

We do handle values within comments. Comments don't stop processing.

    @print @htl("<!-- $(:hello) --><tag>$(:world)</tag>")
    #-> <!-- hello --><tag>world</tag>

When we normalize attribute names, we strip leading underscores.

    @print @htl("<tag $(:__att => :value)/>")
    #-> <tag att='value'/>

## Dynamic Expansion

The macro attempts to expand attributes inside a tag. To ensure the
runtime dispatch also works, let's do a few things once indirect.

    hello = "Hello"
    defer(x) = x

Let's test that deferred attribute values work.

    @print @htl("<tag $(defer(:att => hello))/>")
    #-> <tag att='Hello'/>

    @print @htl("<tag $(:att => defer(hello))/>")
    #-> <tag att='Hello'/>

    @print @htl("<tag $(defer(:att) => hello)/>")
    #-> <tag att='Hello'/>
