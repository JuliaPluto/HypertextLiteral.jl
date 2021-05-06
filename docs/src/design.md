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
  objects as element content, attributes, and attribute value

* Provide direct support for `script` and `style` rawtext elements,
  which have their own interpolation needs.

* Since the `style` and `class` attributes are so important in HTML
  construction, universal interpretations of Julia constructs
  should make sense to aid these CSS attributes.

* There should be a discoverable and well documented extension API that
  permits custom data types to provide their own serialization
  strategies based upon syntactical context.

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

We wrap `missing` and other data types using a `<span>` tag as they are
printed. This permits customized CSS to control their presentation.

    @print @htl("""<tag>$(missing)</tag>""")
    #-> <tag><span class="Base-Missing">missing</span></tag>

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

The `xmp`, `iframe`, `noembed`, `noframes`, and `noscript` tags use "raw
text" encoding where all content up-to the end tag is not escaped using
ampersands.

    book = "Strunk & White"

    @print @htl("""<xmp>$book</xmp>""")
    #-> <xmp>Strunk & White</xmp>

Tags using rawtext are not permitted to include their end tag.

    bad = "content with end-tag: </style>"

    @print @htl("""<style>$bad</style>""")
    #=>
    <style>ERROR: DomainError with "content with end-tag: </style>":
      Content of <style> cannot contain the end tag (`</style>`).
    =#

Rawtext may include not only strings, but numbers, and such.

    @print @htl("<style> $(3) $(true) $(:sym) $(nothing)</style>")
    #-> <style> 3 true sym </style>

## Detection of String Literals

Before v1.6, we cannot reliably detect string literals using the `@htl`
macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
    @print @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮
   g
    #? VERSION < v"1.6.0-DEV"
    @print @htl "$("even if they are the only content")"
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

Nothing within a quoted attribute value, `nothing` is treated as an
empty string. Within element content, it is printed using a `<span>`.

    @print @htl("<tag attribute='$(nothing)'>$(nothing)</tag>")
    #-> <tag attribute=''><span class="Core-Nothing">nothing</span></tag>

Nothing as an attribute value omits the attribute just like `false`.
Nothing inside a tag is omitted as well.

    @print @htl("<tag omit=$(nothing) $(nothing)/>")
    #-> <tag/>

A `Pair` inside a tag is treated as an attribute.

    @print @htl("<tag $(:att => :value)/>")
    #-> <tag att='value'/>

A symbol or string inside a tag are treated as empty attributes.

    @print @htl("<tag $(:att)/>")
    #-> <tag att=''/>

    #? VERSION >= v"1.6.0-DEV"
    @print @htl("<tag $("att")/>")
    #-> <tag att=''/>

A `Dict` inside a tag is treated as an attribute.

    @print @htl("<tag $(Dict(:att => :value))/>")
    #-> <tag att='value'/>

We do handle values within comments. Comments don't stop processing.

    @print @htl("<!-- $(:hello) --><tag>$(:world)</tag>")
    #-> <!-- hello --><tag>world</tag>

When we normalize attribute names, we strip leading underscores.

    @print @htl("<tag $(:__att => :value)/>")
    #-> <tag att='value'/>

We don't expand into attributes things that don't look like attributes.

    @print @htl("<tag $(3)/>")
    #-> ERROR: MethodError: no method matching inside_tag(::Int64)⋮

One can add additional attributes following a bare name.

    @print @htl("<tag bing $(:att)/>")
    #-> <tag bing att=''/>

Inside a tag, tuples can have many kinds of pairs.

    a1 = "a1"
    @print @htl("<tag $((a1,:a2,:a3=3,a4=4))/>")
    #-> <tag a1='' a2='' a3='3' a4='4'/>

The macro attempts to expand attributes inside a tag. To ensure the
runtime dispatch also works, let's do a few things once indirect.

    hello = "Hello"
    defer(x) = x

    @print @htl("<tag $(defer(:att => hello))/>")
    #-> <tag att='Hello'/>

    @print @htl("<tag $(defer((att=hello,)))/>")
    #-> <tag att='Hello'/>

    @print @htl("<tag $(:att => defer(hello))/>")
    #-> <tag att='Hello'/>

    @print @htl("<tag $(defer(:att) => hello)/>")
    #-> <tag att='Hello'/>

Within a `<script>` tag, we want to ensure that numbers are
properly converted.

    v = (-Inf, Inf, NaN, 6.02214e23)

    @print @htl("<script>var x = $v</script>")
    #-> <script>var x = [-Infinity, Infinity, NaN, 6.02214e23]</script>

Besides dictionary objects, we support named tuples.

    v = (min=1, max=8)

    @print @htl("<script>var x = $v</script>")
    #-> <script>var x = {"min": 1, "max": 8}</script>

Within a `<script>` tag, comment start (`<!--`) must also be escaped.
Moreover, capital `<Script>` and permutations are included. We only scan
the first character after the left-than character.

    v = "<!-- <Script> <! 3<4 </ <s !>"

    @print @htl("<script>var x = $v</script>")
    #-> <script>var x = "<\!-- <\Script> <\! 3<4 <\/ <\s !>"</script>

## Lexer Testing

There are several HTML syntax errors that we can detect as part of our
parser. For example, you shouldn't put comments within a script tag.

    @htl("<script><!-- comment --></script>")
    #-> ERROR: LoadError: "script escape or comment is not implemented"⋮

Our lexer currently doesn't bother with processor instructions or
doctype declarations. You could prepend these before your content.

    @htl("<?xml version='1.0'?>")
    #=>
    ERROR: LoadError: DomainError with <?xml ver…:
    unexpected question mark instead of tag name⋮
    =#

    @htl("<!DOCTYPE html>")
    #-> ERROR: LoadError: "DOCTYPE not supported"⋮

    @htl("<![CDATA[No <b>CDATA</b> either.]]>")
    #-> ERROR: LoadError: "CDATA not supported"⋮

It's a lexing error to have an attribute lacking a name.

    @print @htl("<tag =value/>")
    #=>
    ERROR: LoadError: DomainError with  =value/>:
    unexpected equals sign before attribute name⋮
    =#

It's a lexing error to have an attribute lacking a value.

    @print @htl("<tag att=>")
    #=>
    ERROR: LoadError: DomainError with =>:
    missing attribute value⋮
    =#

Tags can be ended using SGML ending.

    @print @htl("<tag></>")
    #-> <tag></>

We add an extra space to ensure adjacent values parse properly.

    @print @htl("<tag $((:one))two=''/>")
    #-> <tag one='' two=''/>

    @print @htl("<tag $((:one))$((:two))/>")
    #-> <tag one='' two=''/>

Attribute names and values can be spaced out.

    @print @htl("<tag one two = value />")
    #-> <tag one two = value />

Invalid attribute names are reported.

    @print @htl("<tag at<ribute='val'/>")
    #=>
    ERROR: LoadError: DomainError with t<ribute=…
    unexpected character in attribute name⋮
    =#

Rawtext has a few interesting lexical cases.

    @print @htl("""<style> </s </> </style>""")
    #-> <style> </s </> </style>

    @print @htl("<style> </s </style/")
    #=>
    ERROR: LoadError: DomainError with e/:
    unexpected solidus in tag⋮
    =#

    @print @htl("<style></style <")
    #=>
    ERROR: LoadError: DomainError with  <:
    unexpected character in attribute name⋮
    =#

Comments can contain interpolated values.

    content = "<!-- a&b -->"

    @print @htl("<!-- $content -->")
    #-> <!-- &lt;!-- a&amp;b --> -->

Empty comments are permitted.

    @print @htl("<!---->")
    #-> <!---->

Comments need to be well formed.

    @htl("<!-> ")
    #=>
    ERROR: LoadError: DomainError with !-> :
    incorrectly opened comment⋮
    =#

    @htl("<!--> ")
    #=>
    ERROR: LoadError: DomainError with -> :
    abrupt closing of empty comment⋮
    =#

    @htl("<!---> ")
    #=>
    ERROR: LoadError: DomainError with -> :
    abrupt closing of empty comment⋮
    =#

Comments cannot contain a nested comment.

    @print @htl("<!-- <!-- nested --> -->")
    #=>
    ERROR: LoadError: DomainError with - nested …:
    nested comment⋮
    =#

Comments can contain content that is similar to a comment block, but
the recognition of these valid states is rather involved.

    @print @htl("<!-- <!-->")
    #-> <!-- <!-->

    @print @htl("<!--<x-->")
    #-> <!--<x-->

    @print @htl("<!--<!x!>-->")
    #-> <!--<!x!>-->

    @print @htl("<!--<!-x-->")
    #-> <!--<!-x-->

    @print @htl("<!---x-->")
    #-> <!---x-->

    @print @htl("<!--<<x-->")
    #-> <!--<<x-->

    @print @htl("<!-- - --! --- --!- -->")
    #-> <!-- - --! --- --!- -->

Not so sure about this lexical production... perhaps it's a
transcription error from the specification?

    @print @htl("<!----!>")
    #=>
    ERROR: LoadError: DomainError with !>:
    nested comment⋮
    =#

Even though actual content may be permitted in these odd spots, we don't
generally permit interpolation.

    @print @htl("<!--<$(:x)")
    #=>
    ERROR: LoadError: "unexpected binding STATE_COMMENT_LESS_THAN_SIGN"⋮
    =#

Of course, we could have pure content lacking interpolation, this also
goes though the lexer.

    @print @htl("<div>Hello<b>World</b>!</div>")
    #-> <div>Hello<b>World</b>!</div>

That's it.
