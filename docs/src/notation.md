# The `htl` notation (non-standard string literal macro)

This package additionally provides the `@htl_str` notation which has the
advantage of being more succinct than `@htl` macro.

    using HypertextLiteral: @htl_str

    macro print(expr) :(display("text/html", $expr)); end

```julia
name = "World"

htl"<span>Hello $name</span>"
#-> htl"<span>Hello $name</span>"
```

Strings prefixed by `htl` are processed by `@htl_str`.

    name = "World"

    @print htl"<span>Hello $name</span>"
    #-> <span>Hello World</span>

    @print @htl_str("<span>Hello \$name</span>")
    #-> <span>Hello World</span>

Other than a handful of exceptions, `htl"<tag/>"` and `@htl("<tag/>")`
are otherwise identical in behavior.

## Notable Differences

Unlike `@htl`, `htl` uses `@raw_str` escaping rules. In particular, so
long as a double-quote character does not come before a slash, the slash
itself need not be escaped.

    @print htl"<span>\some\path</span>"
    #-> <span>\some\path</span>

To represent the dollar-sign, use use HTML character entity `#&36;`.

    amount = 42

    @print htl"<span>They paid &#36;$amount</span>"
    #-> <span>They paid &#36;42</span>

Unlike macros, this syntax does not nest.

    @print htl"Hello $(htl"World")"
    #-> ERROR: syntax: cannot juxtapose string literal

Triple double-quoted syntax can be used as a work around.

    @print htl"""Hello $(htl"World")"""
    #-> Hello World

However, this trick works only one level deep. Hence, there are some
significant downsides to using this format, which are explored in detail
at Julia #38948.

## Marginal Benefits

Since the implementers of the notation have some control over the
parsing, there are some benefits. First, we can reliably detect string
literals (Julia #38501) before v1.6. This is fixed in Julia 1.6+

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

Beyond these differences, this could just be a matter of preference; or
which form of syntax highlighting works best.

## Nesting via Paired Unicode Delimiter

We include an _experimental_ prototype for use of paired delimiters to
permit nesting of `htl` notations as described in Julia #38948.

    @print htl"Hello $(htl⟪World⟫)"
    #-> Hello World

Either single or triple double quotes are still needed for the outermost
query. As long as content uses paired delimiters, there is no problem
including them verbatim.

    @print htl"Hello ⟪World⟫"
    #-> Hello ⟪World⟫

    @print htl"Hello ⟪World⟫ $(htl⟪!⟫)"
    #-> Hello ⟪World⟫ !

The dollar sign is still used to mark interpolation, if it is omitted,
and we discover an `htl⟪...⟫` pair, then we report it as an error.

    htl"Hello htl⟪World⟫"
    #=>
    ERROR: LoadError: "`htl⟪⟫` notation discovered outside interpolation"⋮
    =#

To use the `⟪` in an unpaired way, it could be included in HTML content
using a character entity.

    @print htl"Hello ⟪"
    #-> ERROR: LoadError: "unmatched ⟪ delimiter"⋮

    @print htl"Hello ⟫"
    #-> ERROR: LoadError: "unmatched ⟫ delimiter"⋮

    @print htl"<span>nested literals start with &#10218;</span>"
    #-> <span>nested literals start with &#10218;</span>

If this feature gains support we might keep this notation.

## Quirks & Notes

Due to `@raw_str` escaping, string literal forms are a bit quirky. Use
the triple double-quoted form if your content has a double quote. Avoid
slashes preceding a double quote, instead use the `&#47;` HTML entity.

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
