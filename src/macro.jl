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
# avoid a show() dispatch for nested results
Base.print(io::EscapeProxy, h::Result) = h.content(io)
content(h::Result) = h
