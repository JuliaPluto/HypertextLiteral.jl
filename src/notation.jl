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
Julia #22926 for more detail. See Julia #38948 for a feature request
that would provide a paired unicode syntax.
"""
macro htl_str(expr::String)
    # Essentially this is an ad-hoc scanner of the string, splitting
    # it by `$` to find interpolated parts and delegating the hard work
    # to `Meta.parse`, treating everything else as a literal string.
    this = Expr(:macrocall, Symbol("@htl_str"), nothing, expr)
    (expr, notations) = extract_notation(expr)
    args = Any[]
    start = idx = 1
    strlen = lastindex(expr)
    while true
        idx = findnext(isequal('$'), expr, start)
        if idx == nothing
           chunk = expr[start:strlen]
           if occursin("htl_sentinel_htl_hack", chunk)
               throw("`htl⟪⟫` notation discovered outside interpolation")
           end
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
        if nest isa Expr
            inject_notation!(nest, notations)
        end
        push!(args, nest)
        start = tail
    end
    return interpolate(args, this)
end

#
# These functions implement Julia #38948 by discovering the notation,
# doing a temporary substitution so that Julia.parse can work, and then
# reinject the subordinate macro application.
#

function extract_notation(expr)::Tuple{String, Vector{String}}
    start = 1
    notations = String[]
    while true
        open_idx = findnext(isequal('⟪'), expr, start)
        done_idx = findnext(isequal('⟫'), expr, start)
        if done_idx != nothing
            if open_idx == nothing || done_idx < open_idx
                throw("unmatched ⟫ delimiter")
            end
        end
        if open_idx == nothing
            return (expr, notations)
        end
        done_idx = notation_extent(expr, open_idx)
        if open_idx < 3 || "htl" !=
           expr[prevind(expr,open_idx,3):prevind(expr,open_idx,1)]
            # this is content, so just move along
            start = nextind(expr, done_idx)
            continue
        end
        push!(notations, expr[nextind(expr,open_idx):prevind(expr,done_idx)])
        swap = "_sentinel_htl_hack($(length(notations)))"
        head = expr[1:prevind(expr,open_idx)]
        tail = expr[nextind(expr, done_idx):end]
        expr = head * swap * tail
        start = open_idx + length(swap)
    end
end

function notation_extent(chunk, idx)
    depth = 0
    strlen = lastindex(chunk)
    while idx <= strlen
        ch = chunk[idx]
        if ch == '⟪'
            depth += 1
        elseif ch == '⟫'
            depth -= 1
        end
        if depth == 0
            return idx
        end
        idx = nextind(chunk, idx)
    end
    throw("unmatched ⟪ delimiter")
end

function inject_notation!(expr::Expr, notations::Vector{String})
    if Meta.isexpr(expr, :call, 2) && expr.args[1] == :htl_sentinel_htl_hack
        content = notations[expr.args[2]]
        expr.head = :macrocall
        expr.args = :(htl"").args
        expr.args[3] = content
        return
    end
    for arg in expr.args
        if arg isa Expr
            inject_notation!(arg, notations)
        end
    end
end
