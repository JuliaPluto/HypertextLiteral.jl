"""
    HypertextLiteral

This library provides a `@htl` macro which implements interopolation
that is aware of hypertext escape context.
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
