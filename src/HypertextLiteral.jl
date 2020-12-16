"""
    HypertextLiteral

This library provides for a `@htl()` macro and a `htl` string literal,
both implementing interpolation that is aware of hypertext escape
context. The `@htl` macro has the advantage of using Julia's native
string parsing, so that it can handle arbitrarily deep nesting. However,
it is a more verbose than the `htl` string literal and doesn't permit
interpolated string literals. Conversely, the `htl` string literal,
`@htl_str`, uses custom parsing letting it handle string literal
escaping, however, it can only be used two levels deep (using three
quotes for the outer nesting, and a single double quote for the inner).
"""
module HypertextLiteral
export @htl_str, @htl

include("macros.jl")   # @htl and @htl_str
include("utils.jl")    # UnwrapHTML, EscapeProxy
include("convert.jl")  # runtime conversion of objects
include("lexer.jl")    # interpolate string to macro expression
include("rewrite.jl")  # macro optimizations called by interpolate

end
