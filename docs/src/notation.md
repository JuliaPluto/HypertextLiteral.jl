# The `htl` Notation (non-standard string literal macro)

The `HypertextLiteral` package additionally provides for an `htl`
notation, which has the advantage of can be more succinct.

    using HypertextLiteral
    macro print(expr) :(display("text/html", $expr)); end

```julia
name = "World"

htl"<span>Hello $name</span>"
#-> htl"<span>Hello $name</span>"
```

Julia uses a string literal prefix, in our case `htl`, to indicate that
the string hould be be processed by a macro, such as `@htl_str`.

    name = "World"

    @print htl"<span>Hello $name</span>"
    #-> <span>Hello World</span>

    @print @htl_str("<span>Hello \$name</span>")
    #-> <span>Hello World</span>

This format has the advantage of being more succinct than the equivalent
macro, `htl"<tag/>"` vs `@htl("<tag/>")`.

## Notable Differences

Unlike regular macros, strings passed in this way do not go though
regular interpolation and unescaping. See `@raw_str` for more detail.
In particular, so long as a double-quote character does not come before
a slash, the slash itself need not be escaped.

    @print htl"<span>\some\path</span>"
    #-> <span>\some\path</span>

Hence, to represent the dollar-sign within this syntax, one would need
to use HTML character entities rather than `\$`.

    amount = 42

    @print htl"<span>They paid &#36;$amount</span>"
    #-> <span>They paid &#36;42</span>

With this technique, one could also render the double-quote.

    @print htl"<span>She said: &quot;Hello&quot;</span>"
    #-> <span>She said: &quot;Hello&quot;</span>

Moreover, unlike macros, this format doesn't nest nicely.

    @print @htl("Hello $(@htl("World"))")
    #-> Hello World

    @print htl"Hello $(htl"World")"
    #-> ERROR: syntax: cannot juxtapose string literal

The above expression is seen by Julia as 3 parts, `htl" Hello $(htl"`,
followed by `World`,  and then `")"`; and this is a syntax error.  One
might correct this using triple strings.

    @print htl"""Hello $(htl"World")"""
    #-> Hello World

However, this trick works only one level deep. Hence, there are some
significant downsides to using this format, which are explored in detail
with Julia #38948.

## Marginal Benefits

Since the implementers of the notation have some control over the
parsing, there are some additional benefits. First, we can reliably
detect string literals (Julia #38501) before v1.6.

    @print htl"""<span>$("A&B")</span>"""
    #-> <span>A&amp;B</span>

Second, there is one less round of parenthesis needed for tuples, named
tuples and generators (Julia #38734). This is especially useful when
building attributes.

    name = "Hello"

    @print htl"<tag $(user=name,)/>"
    #-> <tag user='Hello'/>

    @print htl"<span>$(n for n in 1:3)</span>"
    #-> <span>123</span>

## Quirks & Notes

Due to `@raw_str` escaping, string literal forms are quirky.

    @print htl"\"\t\\"
    #-> "\t\

    @print htl"(\\\")"
    #-> (\")

Even though we could permit interpretation of arrays notation, we stick
with keeping this an error for consistency with the macro form.

    htl"$[1,2,3]"
    #=>
    ERROR: LoadError: DomainError with [1, 2, 3]:
    interpolations must be symbols or parenthesized⋮
    =#

    @htl("$[1,2,3]")
    #=>
    ERROR: syntax: invalid interpolation syntax: "$["⋮
    =#
