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

This translation attempts to convert numbers properly.

    v = (-Inf, Inf, NaN, 6.02214e23)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = [-Infinity, Infinity, NaN, 6.02214e23]</script>

Dictionaries are serialized as a Javascript object. Symbols are
converted to string values.

    v = Dict(:min=>1, :max=>8)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = {"max": 8, "min": 1}</script>

Besides dictionary objects, we support named tuples.

    v = (min=1, max=8)

    @htl "<script>var x = $v</script>"
    #-> <script>var x = {"min": 1, "max": 8}</script>

String values are escaped to avoid `<script>`, `</script>`, and `<!--`.

    content = """<script>alert("no injection!")</script>"""

    @htl "<script>v = $content</script>"
    #-> <script>v = "<\script>alert(\"no injection!\")<\/script>"</script>

    content = """--><!-- no injection!"""

    @htl "<script>v = $content</script>"
    #-> <script>v = "--><\!-- no injection!"</script>

## JavaScript

Sometimes you already have content that is valid Javascript. This can be
printed directly, without escaping using a wrapper similar to `HTML`:

    using HypertextLiteral: JavaScript

    expr = JavaScript("""console.log("Hello World")""")

    @htl "<script>$expr</script>"
    #-> <script>console.log("Hello World")</script>

The `JavaScript` wrapper indicates the content should be directly
displayed within a `"text/javascript"` context. We try to catch content
which is not properly escaped for use within a `<script>` tag.

    expr = """<script>console.log("Hello World")</script>"""

    @htl "<script>$(JavaScript(expr))</script>"
    #-> …ERROR: "Content within a script tag must not contain `</script>`"⋮

Similarly, a comment sequence is also forbidden.

    expr = "<!-- invalid comment -->"

    @htl "<script>$(JavaScript(expr))</script>"
    #-> …ERROR: "Content within a script tag must not contain `<!--`"⋮

## Script Attributes

Conversion of Julia values to JavaScript can be performed explicitly
within attributes using `js()`, which is not exported by default.

    using HypertextLiteral: js

    v = """Brown "M&M's"!""";

    @htl "<div onclick='alert($(js(v)))'>"
    #-> <div onclick='alert(&quot;Brown \&quot;M&amp;M&apos;s\&quot;!&quot;)'>

The `js()` function can be used independently.

    msg = "alert($(js(v)))"

    @htl "<div onclick=$msg>"
    #-> <div onclick='alert(&quot;Brown \&quot;M&amp;M&apos;s\&quot;!&quot;)'>

Although strictly unnecessary, slash escaping to prevent `<\script>`
content is still provided.

    v = "<script>nested</script>"

    @htl "<div onclick='alert($(js(v)))'>"
    #-> <div onclick='alert(&quot;&lt;\script>nested&lt;\/script>&quot;)'>

## Extensions

If an object is not showable as `"text/javascript"` then you will get
the following exception.

    @htl("<script>$(π)</script>")
    #-> …ERROR: "Irrational{:π} is not showable as text/javascript"⋮

This can be overcome with a `show()` method for `"text/javascript"`,

    struct Log
        data
    end

    function Base.show(io::IO, mime::MIME"text/javascript", c::Log)
        print(io, "console.log(", c.data, ")")
    end

Like the `HTML` wrapper, you take full control of ensuring this content
is relevant to the context.

    print(@htl """<script>$(Log(missing))</script>""")
    #-> <script>console.log(missing)</script>

Alternatively, one could implement `print_script`, recursively calling
this function on datatypes which require further translation.

    import HypertextLiteral: print_script

    function print_script(io::IO, c::Log)
        print(io, "console.log(")
        print_script(io, c.data)
        print(io, ")")
    end

    print(@htl """<script>$(Log(missing))</script>""")
    #-> <script>console.log(null)</script>

This method is how we provide support for datatypes in `Base` without
committing type piracy by implementing `show` for `"text/javascript"`.

## Edge Cases

Within a `<script>` tag, comment start (`<!--`) must also be escaped.
Moreover, capital `<Script>` and permutations are included. We only scan
the first character after the left-than (`<`) symbol, so there may be
strictly unnecessary escaping.

    v = "<!-- <Script> <! 3<4 </ <s !>"

    @htl "<script>var x = $v</script>"
    #-> <script>var x = "<\!-- <\Script> <\! 3<4 <\/ <\s !>"</script>

It's important to handle unicode content properly.

    s = "α\n"

    @htl("<script>alert($(s))</script>")
    #-> <script>alert("α\n")</script>
