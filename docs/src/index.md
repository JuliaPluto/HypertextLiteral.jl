## Introduction

This package provides a Julia macro, `@htl`, that constructs an object
which could be rendered to `MIME"text/html"` displays. This macro
supports interpolation sensible to the needs of HTML generation.

    using HypertextLiteral

When displayed to the console (via `show`), the output of this macro
reproduces the expression that generated them.

```julia
name = "World"

@htl("<span>Hello $name</span>")
#-> @htl "<span>Hello $(name)</span>"
```

When displayed to `"text/html"` or printed, the template is evaluated.

    name = "World"

    display("text/html", @htl("<span>Hello $name</span>"))
    #-> <span>Hello World</span>

    print(@htl("<span>Hello $name</span>"))
    #-> <span>Hello World</span>

We use `NarrativeTest.jl` to ensure our examples are correct. After each
command is a comment with the expected output.

## Content Interpolation

Hypertext literal provides interpolation via `$`. Within content, the
ampersand (`&`), less-than (`<`), single-quote (`'`) and double-quote
(`"`) are escaped.

    book = "Strunk & White"

    print(@htl("<span>Today's Reading: $book</span>"))
    #-> <span>Today's Reading: Strunk &amp; White</span>

To include `$` in the output, use `\$` as one would in a regular Julia
string. Other escape sequences, such as `\"` also work.

    print(@htl("They said, \"your total is \$42.50\"."))
    #-> They said, "your total is $42.50".

Within tripled double-quotes, single double-quoted strings can go
unescaped, however, we still need to escape the dollar sign (`$`).

    print(@htl("""They said, "your total is \$42.50"."""))
    #-> They said, "your total is $42.50".

Julia results can be interpolated using the `$(expr)` notation.
Strings, numeric values (including `Bool`) and symbols are supported.

    print(@htl("2+2 = $(2+2)"))
    #-> 2+2 = 4

    print(@htl("<bool>$(false)</bool><sym>$(:sym)</sym>"))
    #-> <bool>false</bool><sym>sym</sym>

Objects created by the `@htl` macro are not further escaped, permitting
us to build reusable HTML templates.

    sq(x) = @htl("<span>$(x*x)</span>")

    print(@htl("<div>3^2 is $(sq(3))</div>"))
    #-> <div>3^2 is <span>9</span></div>

Within element content, `nothing` is simply omitted. One could use the
`something` function to provide an alternative representation.

    print(@htl("<span>$nothing</span>"))
    #-> <span></span>

    print(@htl("<span>$(something(nothing, "N/A"))</span>"))
    #-> <span>N/A</span>

Within element content, tuples and vectors are simply concatenated.

    print(@htl("<tag>$([1,2,3])</tag>"))
    #-> <tag>123</tag>

This is done so that nesting of templates produces intuitive output.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    print(@htl("<ul>$([@htl("<li>$b") for b in books])</ul>"))
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

    print(@htl("<ul>$((@htl("<li>$b") for b in books))</ul>"))
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

The `map(container) do item; … ;end` construct works and is performant.

    print(@htl("<ul>$(map(books) do b @htl("<li>$b") end)</ul>"))
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

Within element content, other data types, such as `missing` are wrapped
in a `<span>` tag with with a `class` attribute including the module.

    print(@htl("""<div>$missing</div>"""))
    #-> <div><span class="Base-Missing">missing</span></div>

This automatic wrapping into a `<span>` permits CSS to be used to style
output. The following style will display `missing` as `"N/A"`.

```HTML
    <style>
    span.Base-Missing {visibility: collapse;}
    span.Base-Missing::before {content: "N/A"; visibility: visible;}
    </style>
```

## Attribute Interpolation

Interpolation within single and double quoted attribute values are
supported. Regardless of context, all four characters are escaped.

    qval = "\"&'"

    print(@htl("""<tag double="$qval" single='$qval' />"""))
    #-> <tag double="&quot;&amp;&apos;" single='&quot;&amp;&apos;' />

Unquoted or bare attributes are also supported. These are serialized
using the single quoted style so that spaces and other characters do not
need to be escaped.

    arg = "book='Strunk & White'"

    print(@htl("<tag bare=$arg />"))
    #-> <tag bare='book=&apos;Strunk &amp; White&apos;' />

Within bare attributes, boolean values provide special support for
boolean HTML properties, such as `"disabled"`. When a value is `false`
or `nothing`, the attribute is removed. When the value is `true` then
the attribute is kept, with value being an empty string (`''`).

    print(@htl("<button disabled=$(true)>Disabled</button>"))
    #-> <button disabled=''>Disabled</button>

    print(@htl("<button disabled=$(false)>Clickable</button>"))
    #-> <button>Clickable</button>

    print(@htl("<button disabled=$(nothing)>Clickable</button>"))
    #-> <button>Clickable</button>

Within a quoted attribute there is less magic. Boolean values are
printed and `nothing` is treated as an empty string.

    print(@htl("<input type='text' value='$(true)'>"))
    #-> <input type='text' value='true'>

    print(@htl("<input type='text' value='$(false)'>"))
    #-> <input type='text' value='false'>

    print(@htl("<input type='text' value='$(nothing)'>"))
    #-> <input type='text' value=''>

Within bare and quoted attributes, vectors and tuples are flattened
using the space as a separator. This behavior supports attributes having
name tokens, such as Cascading Style Sheets' `"class"`.

    class = ["text-center", "text-left"]

    print(@htl("<div class=$class>...</div>"))
    #-> <div class='text-center text-left'>...</div>

    print(@htl("<div class='$class'>...</div>"))
    #-> <div class='text-center text-left'>...</div>

    print(@htl("<tag att=$([:one, [:two, "three"]])/>"))
    #-> <tag att='one two three'/>

    print(@htl("<tag att='$((:one, (:two, "three")))'/>"))
    #-> <tag att='one two three'/>

Within bare and quoted attributes, pairs, named tuples and dictionaries
are given treatment to support attributes such as CSS's `"style"`.
For each pair, keys are separated from their value with a colon (`:`).
Adjacent pairs are delimited by the semi-colon (`;`). Moreover, for
`Symbol` keys, `snake_case` values are converted to `kebab-case`.

    style = Dict(:padding_left => "2em", :width => "20px")

    print(@htl("<div style=$style>...</div>"))
    #-> <div style='padding-left: 2em; width: 20px;'>...</div>

    print(@htl("<div style='font-size: 25px; $(:padding_left=>"2em")'/>"))
    #-> <div style='font-size: 25px; padding-left: 2em;'/>

    print(@htl("<div style=$((padding_left="2em", width="20px"))/>"))
    #-> <div style='padding-left: 2em; width: 20px;'/>

Attributes may also be provided by any combination of dictionaries,
named tuples, and pairs. Attribute names are normalized, where
`snake_case` becomes `kebab-case`. We do not convert `camelCase` due to
XML (MathML and SVG) attribute case sensitivity. Moreover, `String`
attribute names are passed along as-is.

    attributes = Dict(:data_style => :green, "data_value" => 42, )

    print(@htl("<div $attributes/>"))
    #-> <div data-style='green' data_value='42'/>

    print(@htl("<div $(:data_style=>:green) $(:dataValue=>42)/>"))
    #-> <div data-style='green' dataValue='42'/>

    print(@htl("<div $((:data_style=>:green, "data_value"=>42))/>"))
    #-> <div data-style='green' data_value='42'/>

    print(@htl("<div $((data_style=:green, dataValue=42))/>"))
    #-> <div data-style='green' dataValue='42'/>

Beyond these rules for booleans, nothing, and collections, the
interpolation of a Julia object within an attribute value is its
printed representation.

    print(@htl("<div att=$((:a_symbol, "string", 42, 3.1415))/>"))
    #-> <div att='a_symbol string 42 3.1415'/>

There is one final set of exceptions. If a *quoted* attribute starts
with `"on"`, then interpolation is done as if were in a `<script>` tag.

## Script Interpolation

Within a `<script>` tag, Julia values are serialized to their equivalent
Javascript.  String literal values are rendered as double-quoted values.

    v = """Brown "M&M's"!""";

    print(@htl("<script>var x = $v</script>"))
    #-> <script>var x = "Brown \"M&M's\"!"</script>

Julia tuples and vectors are serialized as Javascript array. Integers,
boolean, and floating point values are handled. As special cases,
`nothing` is represented using `undefined` and `missing` using `null`.

    v = Any[true, 1, 1.0, nothing, missing]

    print(@htl("<script>var x = $v</script>"))
    #-> <script>var x = [true, 1, 1.0, undefined, null]</script>

Julia named tuples and dictionaries are serialized as a Javascript
object. Symbols are converted to string values.

    v = Dict(:min=>1, :max=>8)

    print(@htl("<script>var x = $v</script>"))
    #-> <script>var x = {"max": 8, "min": 1}</script>

Within a `<script>` tag, comment start, script open, and close tags
are properly escaped.

    v = "<script>nested</script>"

    print(@htl("<script>var x = $v</script>"))
    #-> <script>var x = "<\script>nested<\/script>"</script>

Sometimes you already have content that is valid Javascript. This can be
printed directly, without escaping using a wrapper similar to `HTML`:

    using HypertextLiteral: JavaScript

    expr = JavaScript("""console.log("Hello World")""")

    print(@htl("<script>$expr</script>"))
    #-> <script>console.log("Hello World")</script>

The `JavaScript` wrapper indicates the content should be printed within
a `"text/javascript"` context. Even so, it does help catch content which
is not propertly escaped for use within a `<script>` tag.

    expr = """<script>console.log("Hello World")</script>"""

    print(@htl("<script>$(JavaScript(expr))</script>"))
    #-> …ERROR: "Content within a script tag must not contain `</script>`"⋮

## Script Attributes

If a quoted attribute starts with `"on"`, then its interpolation is done
as if it were in a `script` tag, only that the result is additionally
amperstand escaped.

    v = """Brown "M&M's"!""";

    print(@htl("<div onclick='alert($v)'>"))
    #-> <div onclick='alert(&quot;Brown \&quot;M&amp;M&apos;s\&quot;!&quot;)'>

Although strictly unnecessary, slash escaping to prevent `<\script>`
content is still provided.

    v = "<script>nested</script>"

    print(@htl("<div onclick='alert($v)'>"))
    #-> <div onclick='alert(&quot;&lt;\script>nested&lt;\/script>&quot;)'>

The `JavaScript` wrapper can be used to suppress this conversion.

    expr = JavaScript("""console.log("Hello World")""")

    print(@htl("<div onclick='$expr'>"))
    #-> <div onclick='console.log(&quot;Hello World&quot;)'>

This interpolation rule does not apply to unquoted attribute values.
Moreover, special treatment of booleans still applies in this case.

    expr = """console.log("Hello World")"""

    print(@htl("<div onclick=$expr>"))
    #-> <div onclick='console.log(&quot;Hello World&quot;)'>

    print(@htl("<div onclick=$(nothing)>...</div>"))
    #-> <div>...</div>

## Style Interpolation

Within a `<style>` tag, Julia values are interpolated using the same
rules as they would be if they were encountered within an attribute
value, only that amperstand escaping is not done.

    style = Dict(:padding_left => "2em", :width => "20px")

    print(@htl("""<style>span {$style}</style>"""))
    #-> <style>span {padding-left: 2em; width: 20px;}</style>

In this context, there is no escaping. However, content is validated to
ensure it doesn't contain `"</style>"`.

    expr = """<style>span {display: inline;}</style>"""

    print(@htl("<style>$expr</style>"))
    #-> …ERROR: "Content within a style tag must not contain `</style>`"⋮
