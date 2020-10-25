# HypertextLiteral.jl 

First, one must import `HypertextLiteral`

    using HypertextLiteral

We can construct a HypertextLiteral using the `htl` string macro.

    htl"<h1>Hello World!</h1>"
    #-> HTL{String}("<h1>Hello World!</h1>")

Two values with equivalent content are equivalent.

    htl"x" == htl"x"
    #-> true

