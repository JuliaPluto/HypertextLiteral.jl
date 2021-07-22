# HypertextLiteral Overview

This package provides a Julia macro, `@htl`, that constructs an object
which could be rendered to `MIME"text/html"` displays. This macro
supports string interpolation sensible to the needs of HTML generation.

    using HypertextLiteral

    v = "<1 Brown \"M&M's\"!";

    @htl "<span>$v</span>"
    #-> <span>&lt;1 Brown &quot;M&amp;M&apos;s&quot;!</span>

An equivalent non-standard string literal, `htl`, is also provided.

    v = "<1 Brown \"M&M's\"!";

    htl"<span>$v</span>"
    #-> <span>&lt;1 Brown &quot;M&amp;M&apos;s&quot;!</span>

Interpolation can use the full expressive power of Julia.

    books = ["Who Gets What & Why", "Switch", "Governing The Commons"]

    @htl "<ul>$(map(books) do b @htl("<li>$b") end)</ul>"
    #=>
    <ul><li>Who Gets What &amp; Why<li>Switch<li>Governing The Commons</ul>
    =#

## Translation Contexts

How a Julia expression is translated depends upon where it is used.

|                     | **Native Julia**         | **Translation**    |
|:------------------- |:-------------------------|:------------------ |
| **Element Content** | `"\"M&M\"'s"`            | `M&amp;M&apos;s`   |
|                     | `:name`                  | `name`             |
|                     | `[1, 2]` *or* `(1, 2)`   | `12`               |
|                     | `nothing`                | *omitted*          |
|                     | `missing`                | `<span class="Base-Missing">missing</span>` |
|                     | `(a = 1, b = 2)`         | `<span class="Core-NamedTuple">(a = 1, b = 2)</span>` |
|                     | `Dict(:a => 1, :b => 2)` | `<span class="Base-Dict">Dict(:a => 1, :b => 2)</span>` |
| **Attribute Value** | `"\"M&M\"'s"`            | `M&amp;M&apos;s`   |
|                     | `:name`                  | `name`             |
|                     | `[1, 2]` *or* `(1, 2)`   | `1 2`              |
|                     | `nothing`                | *omitted*          |
|                     | `missing`                | `missing`          |
|                     | `(a = 1, b = 2)`         | `a: 1; b: 2;`      |
|                     | `Dict(:a => 1, :b => 2)` | `a: 1; b: 2;`      |
| **Script Tag**      | `"\"M&M\"'s"`            | `"\"M&M\"'s"`      |
|                     | `:name`                  | `name`             |
|                     | `[1, 2]` *or* `(1, 2)`   | `[1, 2]`           |
|                     | `nothing`                | `undefined`        |
|                     | `missing`                | `null`             |
|                     | `Inf`                    | `Infinity`         |
|                     | `NaN`                    | `NaN`              |
|                     | `(a = 1, b = 2)`         | `{"a": 1, "b": 2}` |
|                     | `Dict(:a => 1, :b => 2)` | `{"a": 1, "b": 2}` |

If any of these translations are inconvenient:

* `coalesce()` can be used to provide an alternative for `missing`;
* `something()` provides a substitution for `nothing`;
* `string()` will use the string translation instead; and
* `HTML()` can be used to bypass escaping within element content.

## Table of Contents

```@contents
Pages = ["content.md", "attribute.md", "script.md"]
Depth = 3
```

```@contents
Pages = ["design.md", "notation.md", "primitives.md", "reference.md"]
Depth = 1
```
