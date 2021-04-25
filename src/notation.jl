"""
    @htl_str -> Result

Create a `Result` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Unlike the `@htl` macro, this
string literal does not include escaping feature [1]. To include `\$`
within user content one must write `&#36;`. Observe that `&quot;` and
any other HTML ampersand escape sequence can be used as appropriate.

In this syntax, interpolation is extended beyond regular Julia strings
to handle three additional cases: tuples, named tuples (for attributes),
and generators. See Julia #38734 for the feature request so that this
could also work within the `@htl` macro syntax.

[1] There are also a few edge cases, see `@raw_str` documentation and
Julia #22926 for more detail.
"""
macro htl_str(expr::String)
    # Essentially this is an ad-hoc scanner of the string, splitting
    # it by `$` to find interpolated parts and delegating the hard work
    # to `Meta.parse`, treating everything else as a literal string.
    this = Expr(:macrocall, Symbol("@htl_str"), nothing, expr)
    args = Any[]
    start = idx = 1
    strlen = lastindex(expr)
    while true
        idx = findnext(isequal('$'), expr, start)
        if idx == nothing
           chunk = expr[start:strlen]
           push!(args, expr[start:strlen])
           break
        end
        push!(args, expr[start:prevind(expr, idx)])
        start = nextind(expr, idx)
        (nest, tail) = Meta.parse(expr, start; greedy=false)
        @assert nest != nothing
        if !(expr[start] == '(' || nest isa Symbol)
            throw(DomainError(nest,
             "interpolations must be symbols or parenthesized"))
        end
        if Meta.isexpr(nest, :(=))
            throw(DomainError(nest,
             "assignments are not permitted in an interpolation"))
        end
        if nest isa String
            # this is an interpolated string literal
            nest = Expr(:string, nest)
        end
        push!(args, nest)
        start = tail
    end
    return interpolate(args, this)
end
