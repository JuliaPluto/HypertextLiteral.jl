# Script Interpolation

Within a `<script>` tag, Julia values are serialized to their equivalent
Javascript.  String literal values are rendered as double-quoted values.

    using HypertextLiteral

    v = """Brown "M&M's"!""";

    @htl "<script>var x = $v</script>"
    #-> <script>var x = "Brown \"M&M's\"!"</script>

Julia tuples and vectors are serialized as Javascript array. Integers,
boolean, and floating point values are handled. As special cases,
`nothing` is represented using `undefined` and `missing` using `null`.

    v = Any[true, 1, 1.0, nothing, missing]

    @htl "<script>var x = $v</script>"
    #-> <script>var x = [true, 1, 1.0, undefined, null]</script>

Julia named tuples and dictionaries are serialized as a Javascript
object. Symbols are converted to string values.

    v = Dict(:min=>1, :max=>8)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = {"max": 8, "min": 1}</script>

## JavaScript

Sometimes you already have content that is valid Javascript. This can be
printed directly, without escaping using a wrapper similar to `HTML`:

    using HypertextLiteral: JavaScript

    expr = JavaScript("""console.log("Hello World")""")

    @htl "<script>$expr</script>"
    #-> <script>console.log("Hello World")</script>

The `JavaScript` wrapper indicates the content should be printed within
a `"text/javascript"` context. Even so, it does help catch content which
is not properly escaped for use within a `<script>` tag.

    expr = """<script>console.log("Hello World")</script>"""

    @htl "<script>$(JavaScript(expr))</script>"
    #-> …ERROR: "Content within a script tag must not contain `</script>`"⋮

Similarly, a comment sequence is also forbidden.

    expr = "<!-- invalid comment -->"

    @htl "<script>$(JavaScript(expr))</script>"
    #-> …ERROR: "Content within a script tag must not contain `<!--`"⋮

## Script Attributes

If a quoted attribute starts with `"on"`, then its interpolation is done
as if it were in a `script` tag, only that the result is additionally
ampersand escaped.

    v = """Brown "M&M's"!""";

    @htl "<div onclick='alert($v)'>"
    #-> <div onclick='alert(&quot;Brown \&quot;M&amp;M&apos;s\&quot;!&quot;)'>

Although strictly unnecessary, slash escaping to prevent `<\script>`
content is still provided.

    v = "<script>nested</script>"

    @htl "<div onclick='alert($v)'>"
    #-> <div onclick='alert(&quot;&lt;\script>nested&lt;\/script>&quot;)'>

The `JavaScript` wrapper can be used to suppress this conversion.

    expr = JavaScript("""console.log("Hello World")""")

    @htl "<div onclick='$expr'>"
    #-> <div onclick='console.log(&quot;Hello World&quot;)'>

This interpolation rule does not apply to unquoted attribute values.
Moreover, special treatment of booleans still applies in this case.

    expr = """console.log("Hello World")"""

    @htl "<div onclick=$expr>"
    #-> <div onclick='console.log(&quot;Hello World&quot;)'>

    @htl "<div onclick=$(nothing)>...</div>"
    #-> <div>...</div>

## Extensions

Within the `script` tag, content is not `"text/html"`, instead, it is
treated as `"text/javascript"`. Custom objects which are `showable` as
`"text/javascript"` can be printed without any escaping in this context.

    struct Log
        data
    end

    function Base.show(io::IO, mime::MIME"text/javascript", c::Log)
        print(io, "console.log(", c.data, ")")
    end

    print(@htl """<script>$(Log("undefined"))</script>""")
    #-> <script>console.log(undefined)</script>

Alternatively, one could implement `print_script` to provide a
representation for this context.

    import HypertextLiteral: print_script

    function print_script(io::IO, c::Log)
        print(io, "console.log(")
        print_script(io, c.data)
        print(io, ")")
    end

    print(@htl """<script>$(Log(nothing))</script>""")
    #-> <script>console.log(undefined)</script>

This content must not only be valid Javascript, but also escaped so that
`<script>`, `</script>`, and `<!--` literal values do not appear. When
using `print_script` this work is performed automatically.

    content = """<script>alert("hello")</script>"""

    print(@htl "<script>$(Log(content))</script>")
    #-> <script>console.log("<\script>alert(\"hello\")<\/script>")</script>

## Edge Cases

Within a `<script>` tag, the script open and close tags are escaped.

    v = "<script>nested</script>"

    @htl "<script>var x = $v</script>"
    #-> <script>var x = "<\script>nested<\/script>"</script>

Within a `<script>` tag, comment start (`<!--`) must also be escaped.
Moreover, capital `<Script>` and permutations are included. We only scan
the first character after the left-than character.

    v = "<!-- <Script> <! 3<4 </ <s !>"

    @htl "<script>var x = $v</script>"
    #-> <script>var x = "<\!-- <\Script> <\! 3<4 <\/ <\s !>"</script>

Within a `<script>` tag, we want to ensure that numbers are properly
converted.

    v = (-Inf, Inf, NaN, 6.02214e23)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = [-Infinity, Infinity, NaN, 6.02214e23]</script>

Besides dictionary objects, we support named tuples.

    v = (min=1, max=8)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = {"min": 1, "max": 8}</script>

Comments should not exist within a script tag.

    @htl("<script><!-- comment --></script>")
    #-> ERROR: LoadError: "script escape or comment is not implemented"⋮

