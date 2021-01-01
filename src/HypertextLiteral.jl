"""
    HypertextLiteral

This library provides a `@htl()` macro and a `@htl_str` non-standard
string literal, both implementing interpolation that is aware of
hypertext escape context. The `@htl` macro has the advantage of using
Julia's native string parsing and has familar look and feel. Conversely,
the `htl` literal, `@htl_str`, takes a less standard approach.
"""
module HypertextLiteral
export @htl_str, @htl

include("primitives.jl") # Wrap, Unwrap, EscapeProxy
include("macro.jl")      # @htl macro and `Result` object
include("notation.jl")   # @htl_str non-standard string literal
include("convert.jl")    # runtime conversion of objects
include("lexer.jl")      # interpolate string to macro expression
include("rewrite.jl")    # macro optimizations called by interpolate

end
