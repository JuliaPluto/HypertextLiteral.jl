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

Quotes and slash characters survive this translation.

    htl"\"\\" == html"\"\\"
    #-> true

Interpolation of variables works.
 
    var = 3
    htl"$var"
    #-> HTML{String}("3")

Strings are escaped. In the default `:content` context only less-than
(`<`) and amperstand (`&`) need conversion.

    var = "3<4 & 5>4"
    htl"$var"
    #-> HTML{String}("3&lt;4 &amp; 5>4")

Strings within subordinate expressions are also escaped.

    htl"Look, Ma, $("<i>automatic escaping</i>")!"
    #-> HTML("Look, Ma, $("&lt;i>automatic escaping&lt;/i>")!")

If a variable is already a `HTML` string used in the default `:content`
context, it is not escaped.

    var = html"<span>no-escape</span>"
    htl"$var"
    #-> HTML{String}("<span>no-escape</span>")

Of course, more than one variable can be interpolated.

    s = "World"
    n = 42

    htl"Hello $s, $n"
    #-> HTML{String}("Hello World, 42")

