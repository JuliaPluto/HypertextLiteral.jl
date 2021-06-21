"""
    HypertextLiteral

The `HypertextLiteral` module exports the `@htl` macro which implements
interpolation aware of hypertext escape context. It also provides for
escaping of JavaScript within the `<script>` tag and `on` attributes.

```jldoctest
julia> v = "Brown \\\"M&M's\\\"!";

julia> @htl "<span>\$v</span>"
<span>Brown &quot;M&amp;M&apos;s&quot;!</span>

julia> @htl "<script>console.log(\$v)</script>"
<script>console.log("Brown \\\"M&M's\\\"!")</script>

julia> @htl "<div onclick='console.log(\$v)'>\\nLook in the bowl...</div>"
<div onclick='console.log(&quot;Brown \\&quot;M&amp;M&apos;s\\&quot;!&quot;)'>
Look in the bowl...</div>
```

See also: [`@htl_str`](@HypertextLiteral.@htl_str),
          [`JavaScript`](@HypertextLiteral.JavaScript)
"""
module HypertextLiteral

export @htl

include("primitives.jl") # Wrap, Unwrap, EscapeProxy
include("macro.jl")      # @htl macro and `Result` object
include("convert.jl")    # runtime conversion of objects
include("style.jl")      # printing of content within a style tag
include("script.jl")     # printing of content within a script tag
include("lexer.jl")      # interpolate string to macro expression
include("rewrite.jl")    # macro optimizations called by interpolate

end
