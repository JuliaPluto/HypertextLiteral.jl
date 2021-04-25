"""
    HypertextLiteral

This library provides a `@htl()` macro which implements interopolation
that is aware of hypertext escape context.
"""
module HypertextLiteral
export @htl

include("primitives.jl") # Wrap, Unwrap, EscapeProxy
include("macro.jl")      # @htl macro and `Result` object
include("notation.jl")   # @htl_str non-standard string literal
include("convert.jl")    # runtime conversion of objects
include("lexer.jl")      # interpolate string to macro expression
include("rewrite.jl")    # macro optimizations called by interpolate
include("script.jl")     # handling of script and style tags

end
