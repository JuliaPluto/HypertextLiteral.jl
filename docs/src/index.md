# HypertextLiteral Overview

This package provides a Julia macro, `@htl`, that constructs an object
which could be rendered to `MIME"text/html"` displays. This macro
supports interpolation sensible to the needs of HTML generation.

    using HypertextLiteral

Template substitution works just as regular string interpolation, only
that the results are properly escaped.

    v = """Brown "M&M's"!""";

    @htl "<span>$v</span>"
    #-> <span>Brown &quot;M&amp;M&apos;s&quot;!</span>

Within a `<script>` tag, where ampersand escaping is not indicated, this
same variable is provided a translation to Javascript.

    @htl "<script>v = $v</script>"
    #-> <script>v = "Brown \"M&M's\"!"</script>

Within attributes starting with `on`, values are translated to
Javascript and then ampersand escaped.

    @htl "<button onclick='alert($v)'>\nLook in the bowl...</button>"
    #=>
    <button onclick='alert(&quot;Brown \&quot;M&amp;M&apos;s\&quot;!&quot;)'>
    Look in the bowl...</button>
    =#

Boolean attributes are supported.

    @htl "<input type='checkbox' selected=$(false) disabled=$(true)></input>"
    #-> <input type='checkbox' disabled=''></input>

Templates can be nested.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @htl "<ul>$(map(books) do b @htl("<li>$b") end)</ul>"
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

Dictionaries are translated CSS style within attributes and the
`<style>` tag. In this case, `snake_case` symbols become `kebab-case`.

    style = Dict(:padding_left => "2em", :width => "20px")

    @htl("<div style='font-size: 25px; $style'>...</div>")
    #-> <div style='font-size: 25px; padding-left: 2em; width: 20px;'>...</div>

    @htl "<style>input {$style}</style>"
    #-> <style>input {padding-left: 2em; width: 20px;}</style>

## Interpolation Summary

| Native Julia         | Script Context     | Attribute Value | Element Content |
|:-------------------- |:------------------ |:--------------- |:--------------- |
| `"\"M&M\"'s"`        | `"\"M&M\"'s"`      | M&amp;M&apos;s  | M&amp;M&apos;s  |
| `Inf`                | `Infinity`         | Inf             | Inf             |
| `NaN`                | `NaN`              | NaN             | NaN             |
| `[1, 2]`             | `[1, 2]`           | 1 2             | 12              |
| `nothing`            | `undefined`        |                 |                 |
| `missing`            | `null`             | missing         | <span class="Base-Missing">missing</span> |
| `(a = 1, b = 2)`     | `{"a": 1, "b": 2}` | a: 1; b: 2;     | <span class="Core-NamedTuple">(a = 1, b = 2)</span> |

The automatic wrapping permits CSS to be used to style output. The
following style will display `missing` as `"N/A"`.

```HTML
    <style>
    span.Base-Missing {visibility: collapse;}
    span.Base-Missing::before {content: "N/A"; visibility: visible;}
    </style>
```

If this default behavior is inconvenient:

* `coalesce()` can be used to provide an alternative for `missing`;
* `something()` provides a substitution for `nothing`; and
* `string()` will bypass these type translations altogether.

## Table of Contents

```@contents
Pages = ["content.md", "attribute.md", "script.md"]
Depth = 3
```

```@contents
Pages = ["design.md", "notation.md", "primitives.md", "reference.md"]
Depth = 1
```
