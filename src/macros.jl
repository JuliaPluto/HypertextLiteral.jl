"""
    @htl string-expression

Create a `Result` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Before Julia 1.6, interpolated
string literals, e.g. `\$("Strunk & White")`, are treated as errors
since they cannot be reliably detected (see Julia issue #38501).
"""
macro htl(expr)
    this = Expr(:macrocall, Symbol("@htl"), nothing, expr)
    if !Meta.isexpr(expr, :string)
        return interpolate([expr], this)
    end
    args = expr.args
    if length(args) == 0
        return interpolate([], this)
    end
    for part in expr.args
        if Meta.isexpr(part, :(=))
            throw(DomainError(part,
             "assignments are not permitted in an interpolation"))
        end
    end
    if VERSION < v"1.6.0-DEV"
        # Find cases where we may have an interpolated string literal and
        # raise an exception (till Julia issue #38501 is addressed)
        if length(args) == 1 && args[1] isa String
            throw("interpolated string literals are not supported")
        end
        for idx in 2:length(args)
            if args[idx] isa String && args[idx-1] isa String
                throw("interpolated string literals are not supported")
            end
        end
    end
    return interpolate(expr.args, this)
end

"""
    @htl_str -> Result

Create a `Result` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escape sequences should work
identically to Julia strings, except in cases where a slash immediately
precedes the double quote (see `@raw_str` and Julia issue #22926).

Interpolation is extended beyond regular Julia strings to handle three
additional cases: tuples, named tuples (for attributes), and generators.
See Julia #38734 for the feature request so that this could also work
within the `@htl` macro syntax.
"""
macro htl_str(expr::String)
    # Essentially this is an ad-hoc scanner of the string, splitting
    # it by `$` to find interpolated parts and delegating the hard work
    # to `Meta.parse`, treating everything else as a literal string.
    this = Expr(:macrocall, Symbol("@htl_str"), nothing, expr)
    args = Any[]
    start = idx = 1
    strlen = length(expr)
    escaped = false
    while idx <= strlen
        c = expr[idx]
        if c == '\\'
            escaped = !escaped
            idx += 1
            continue
        end
        if c != '$'
            escaped = false
            idx += 1
            continue
        end
        finish = idx - (escaped ? 2 : 1)
        push!(args, unescape_string(SubString(expr, start:finish)))
        start = idx += 1
        if escaped
            escaped = false
            push!(args, "\$")
            continue
        end
        (nest, idx) = Meta.parse(expr, start; greedy=false)
        if nest == nothing
            throw("missing interpolation expression")
        end
        if !(expr[start] == '(' || nest isa Symbol)
            throw(DomainError(nest,
             "interpolations must be symbols or parenthesized"))
        end
        start = idx
        if Meta.isexpr(nest, :(=))
            throw(DomainError(nest,
             "assignments are not permitted in an interpolation"))
        end
        if nest isa String
            # this is an interpolated string literal
            nest = Expr(:string, nest)
        end
        push!(args, nest)
    end
    if start <= strlen
        push!(args, unescape_string(SubString(expr, start:strlen)))
    end
    return interpolate(args, this)
end

"""
    Result(expr, unwrap)

Address display modalities by showing the macro expression that
generated the results when shown on the REPL. However, when used with
`print()` show the results. This object is also showable to any IO
stream via `"text/html"`.
"""
struct Result
    content::Function
    expr::Expr
end

function Result(expr::Expr, xs...)
    Result(expr) do io::IO
        for x in xs
            print(io, x)
        end
    end
end

Base.show(io::IO, m::MIME"text/html", h::Result) = h.content(EscapeProxy(io))
Base.print(io::IO, h::Result) = h.content(EscapeProxy(io))
Base.show(io::IO, h::Result) = print(io, h.expr)
