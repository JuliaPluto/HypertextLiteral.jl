# HypertextLiteral.jl 

First, one must import `HypertextLiteral`

    using HypertextLiteral

We can construct a HTML object using the `htl` string macro. We use
Julia's built-in HTML data type to represent string values that should
not be further escaped.

    htl"<h1>Hello World!</h1>"
    #-> HTML{String}("<h1>Hello World!</h1>")

For strings that do not include `$` interpolation, the values are
equivalent as their raw `HTML` equivalent.

    htl"<h1>Hello World!</h1>" == html"<h1>Hello World!</h1>"
    #-> true
