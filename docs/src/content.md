# Element Content

Hypertext literal provides interpolation via `$`. Within element
content, the ampersand (`&`), less-than (`<`), single-quote (`'`) and
double-quote (`"`) are escaped.

    using HypertextLiteral

    book = "Strunk & White"

    @htl "<span>Today's Reading: $book</span>"
    #-> <span>Today's Reading: Strunk &amp; White</span>

Julia expressions can be interpolated using the `$(expr)` notation.

    @htl "2+2 = $(2+2)"
    #-> 2+2 = 4

To include `$` in the output, use `\$`. Other escape sequences, such as
`\"` also work.

    @htl "They said, \"your total is \$42.50\"."
    #-> They said, "your total is $42.50".

Within tripled double-quotes, single double-quoted strings can go
unescaped, however, we still need to escape the dollar sign (`$`).

    @htl """They said, "your total is \$42.50"."""
    #-> They said, "your total is $42.50".

In this document, we discuss interpolation within regular tagged
content. Interpolation within attribute values and within `<script>` or
`<style>` tags is treated differently.

## Strings & Numbers

Strings, symbols, integers, booleans, and floating point values are
reproduced with their standard `print()` representation. Output produced
in this way is properly escaped.

    @htl "<enabled>$(false)</enabled><color>$(:blue)</color>"
    #-> <enabled>false</enabled><color>blue</color>

    @htl "<int>$(42)</int><float>$(6.02214076e23)</float>"
    #-> <int>42</int><float>6.02214076e23</float>

We include `AbstractString` for the performant serialization of
`SubString` and other string-like objects.

    @htl "<slice>$(SubString("12345", 2:4))</slice>"
    #-> <slice>234</slice>

All other types, such as `Irrational`, have special treatment. Explicit
conversion to a `String` is a simple way to avoid the remaining rules.

    #? VERSION >= v"1.3.0-DEV"
    @htl "<value>$(string(π))</value>"
    #-> <value>π</value>

## HTML Values

Since values translated by the `@htl` macro are `"text/html"`, they can
be used in a nested manner, permitting us to build template functions.

    sq(x) = @htl("<span>$(x*x)</span>")

    @htl "<div>3^2 is $(sq(3))</div>"
    #-> <div>3^2 is <span>9</span></div>

Values `showable` as `"text/html"` will bypass ampersand escaping.

    @htl "<div>$(HTML("<span>unescaped 'literal'</span>"))</div>"
    #-> <div><span>unescaped 'literal'</span></div>

Custom datatypes can provide their own representation by implementing
`show` for `"text/html"`.

    struct Showable data::String end

    function Base.show(io::IO, mime::MIME"text/html", c::Showable)
        value = replace(replace(c.data, "&"=>"&amp;"), "<"=>"&lt;")
        print(io, "<showable>$(value)</showable>")
    end

    print(@htl "<span>$(Showable("a&b"))</span>")
    #-> <span><showable>a&amp;b</showable></span>

HypertextLiteral trusts that `"text/html"` content is properly escaped.

## Nothing

Within element content, `nothing` is simply omitted.

    @htl "<span>$nothing</span>"
    #-> <span></span>

Use `something()` to provide an alternative representation.

    @htl "<span>$(something(nothing, "N/A"))</span>"
    #-> <span>N/A</span>

This design supports template functions that return `nothing`.

    choice(x) = x ? @htl("<span>yes</span>") : nothing

    @htl "<div>$(choice(true))$(choice(false))</div>"
    #-> <div><span>yes</span></div>

Note that `missing` has default treatment, see below.

## Vectors & Tuples

Within element content, vector and tuple elements are concatenated (with no delimiter).

    @htl "<tag>$([1,2,3])</tag>"
    #-> <tag>123</tag>

    @htl "<tag>$((1,2,3))</tag>"
    #-> <tag>123</tag>

This interpretation enables nesting of templates.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @htl "<ul>$([@htl("<li>$b") for b in books])</ul>"
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

The splat operator (`...`) is supported as a noop.

    @htl "$([x for x in 1:3]...)"
    #-> 123

Generators are also treated in this manner.

    print(@htl "<ul>$((@htl("<li>$b") for b in books))</ul>")
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

The `map(container) do item; … ;end` construct works and is performant.

    @htl "<ul>$(map(books) do b @htl("<li>$b") end)</ul>"
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

## General Case

Within element content, values are wrapped in a `<span>` tag.

    @htl """<div>$missing</div>"""
    #-> <div><span class="Base-Missing">missing</span></div>

This wrapping lets CSS style output. The following renders `missing` as
`"N/A"`.

```HTML
    <style>
    span.Base-Missing {visibility: collapse;}
    span.Base-Missing::before {content: "N/A"; visibility: visible;}
    </style>
```

The `<span>` tag's `class` attribute includes the module and type name.

    using Dates

    @htl "<div>$(Date("2021-07-28"))</div>"
    #-> <div><span class="Dates-Date">2021-07-28</span></div>

This handwork is accomplished with a generated function when an object
is not `showable` as `"text/html"`. If the datatype's module is `Main`
then it is not included in the `class`.

    struct Custom data::String; end

    Base.print(io::IO, c::Custom) = print(io, c.data)

    print(@htl "<div>$(Custom("a&b"))</div>")
    #-> <div><span class="Custom">a&amp;b</span></div>

Bypassing `<span>` wrapping can be accomplished with `string()`.

    print(@htl "<div>$(string(Custom("a&b")))</div>")
    #-> <div>a&amp;b</div>

## Extensions

Sometimes it's useful to extend `@htl` so that it knows how to print
your object without constructing this `<span>` wrapper. This can be done
by implementing a method of the `content()` function.

    struct Custom data::String end

    HypertextLiteral.content(c::Custom) =
        "They said: '$(c.data)'"

    @htl "<div>$(Custom("Hello"))</div>"
    #-> <div>They said: &apos;Hello&apos;</div>

You can use `@htl` to produce tagged content.

    HypertextLiteral.content(c::Custom) =
        @htl("<custom>$(c.data)</custom>")

    @htl "<div>$(Custom("a&b"))</div>"
    #-> <div><custom>a&amp;b</custom></div>

With our primitives, you could have even more control. If your datatype
builds its own tagged content, you can `Bypass` ampersand escaping.

    HypertextLiteral.content(c::Custom) =
        HypertextLiteral.Bypass("<custom>$(c.data)</custom>")

    @htl "<div>$(Custom("Hello"))</div>"
    #-> <div><custom>Hello</custom></div>

Unfortunately, this won't escape the content of your custom object.

    @htl "<div>$(Custom("<script>alert('whoops!);"))</div>"
    #-> <div><custom><script>alert('whoops!);</custom></div>

The `Reprint` primitive can help with composite templates.

    using HypertextLiteral: Bypass, Reprint

    HypertextLiteral.content(c::Custom) =
        Reprint(io::IO -> begin
            print(io, Bypass("<custom>"))
            print(io, c.data)
            print(io, Bypass("</custom>"))
        end)

    print(@htl "<div>$(Custom("a&b"))</div>")
    #-> <div><custom>a&amp;b</custom></div>

In fact, the `@htl` macro produces exactly this translation.

    HypertextLiteral.content(c::Custom) =
        @htl("<custom>$(c.data)</custom>")

    print(@htl "<div>$(Custom("a&b"))</div>")
    #-> <div><custom>a&amp;b</custom></div>

## Edge Cases

Within element content, even though it isn't strictly necessary, we
ampersand escape the single and double quotes.

    v = "<'\"&"

    @htl "<span>$v</span>"
    #-> <span>&lt;&apos;&quot;&amp;</span>

Symbols are likewise escaped.

    v = Symbol("<'\"&")

    @htl "<span>$v</span>"
    #-> <span>&lt;&apos;&quot;&amp;</span>

Interpolation within the `xmp`, `iframe`, `noembed`, `noframes`, and
`noscript` tags are not supported.

    @htl "<iframe>$var</iframe>"
    #=>
    ERROR: LoadError: DomainError with iframe:
    Only script and style rawtext tags are supported.⋮
    =#

String escaping by `@htl` is handled by Julia itself.

    @htl "\"\t\\"
    #-> "	\

    @htl "(\\\")"
    #-> (\")

Literal content can contain Unicode values.

    x = "Hello"

    @htl "⁅$(x)⁆"
    #-> ⁅Hello⁆

Escaped content may also contain Unicode.

    x = "⁅Hello⁆"

    @htl "<tag>$x</tag>"
    #-> <tag>⁅Hello⁆</tag>

String interpolation is limited to symbols or parenthesized expressions
(see Julia #37817).

    @htl("$[1,2,3]")
    #=>
    ERROR: syntax: invalid interpolation syntax: "$["⋮
    =#

    @htl("$(1,2,3)")
    #=>
    ERROR: syntax: invalid interpolation syntax⋮
    =#

Before v1.6, we cannot reliably detect string literals using the `@htl`
macro, so they are errors (when we can detect them).

    #? VERSION < v"1.6.0-DEV"
    @htl "Look, Ma, $("<i>automatic escaping</i>")!"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

    #? VERSION < v"1.6.0-DEV"
    @htl "$("even if they are the only content")"
    #-> ERROR: LoadError: "interpolated string literals are not supported"⋮

However, you can fix by wrapping a value in a `string` function.

    @htl "Look, Ma, $(string("<i>automatic escaping</i>"))!"
    #-> Look, Ma, &lt;i>automatic escaping&lt;/i>!

In particular, before v1.6, there are edge cases where unescaped string
literal is undetectable and content can leak.

    x = ""

    #? VERSION < v"1.6.0-DEV"
    @htl "$x$("<script>alert(\"Hello\")</script>")"
    #-> <script>alert("Hello")</script>

Julia #38501 was fixed in v1.6.

    #? VERSION >= v"1.6.0-DEV"
    @htl "<tag>$("escape&me")</tag>"
    #-> <tag>escape&amp;me</tag>
