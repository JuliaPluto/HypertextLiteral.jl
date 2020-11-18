module HypertextLiteral

export @htl_str htl_escape

"""
    @html_str -> Docs.HTML

Create an `HTML` object with string interpolation. The dollar-sign
character may be escaped by doubling it.
"""
macro htl_str(expr::String)
    if !occursin("\$", expr)
        return Expr(:call, :HTML, expr)
    end
    return Expr(:call, :HTML, htl_str(expr, :content, Symbol[]))
end

function htl_str(expr::String, cntx::Symbol, locals::Vector{Symbol})::Expr
    start = 1
    mixed = false
    args = []
    while start <= length(expr)
        next = findnext("\$", expr, start)
        if next == nothing
            push!(args, expr[start:end])
            break
        end
        next = next[end]
        if next > start
            push!(args, expr[start:next-1])
        end
        start = next + 1
        if start > length(expr)
            throw("incomplete interpolation")
        end
        if expr[start] == '$'
            push!(args, "\$")
            start += 1
            continue
        end
        (nest, start) = Meta.parse(expr, start;
                            greedy=false, raise=true, depwarn=true)
        if isa(nest, String)
            @assert !occursin("\$", nest) # permit regular interpolation?
            push!(args, htl_escape(nest, cntx))
            continue
        end
        mixed = true
        if isa(nest, Symbol)
            if !in(nest, locals)
                nest = esc(nest)
            end
            push!(args, Expr(:call, :htl_escape, nest))
            continue
        end
        push!(args, htl_str(nest, cntx, locals))
    end
    if mixed
        return Expr(:call, :string, args...)
    end
    return Expr(:call, :string, join(args))
end

function htl_str(expr::Expr, cntx::Symbol, locals::Vector{Symbol})::Expr
    if expr.head == :string
        #TODO: this is duplicate, can it be removed?
        for (idx, arg) in enumerate(expr.args)
            if isa(arg, String)
                continue
            elseif isa(arg, Symbol)
                if !in(arg, locals)
                    arg = esc(arg)
                end
                expr.args[idx] = Expr(:call, :htl_escape, arg)
            elseif isa(arg, Expr)
                expr.args[idx] = htl_str(arg, cntx, locals)
            else
                @assert false # this shouldn't happen
            end
        end
        return expr
    end

    #  htl"""<ul>$(map([1,2]) do x "<li>$x</li>" end)</ul>"""
    if expr.head == :do
       @assert expr.args[2].head == Symbol("->")
       scope = expr.args[2].args[1]
       @assert scope.head == :tuple
       @assert length(scope.args) == 1
       nested_locals = [scope.args[1], locals...]
       block = expr.args[2].args[2]
       @assert block.head == :block
       @assert length(block.args) == 2
       block.args[2] = htl_str(block.args[2], cntx, nested_locals)
       return Expr(:call, :join, expr)
    end

    # TODO: improve translation to handle local variables
    if expr.head == :call && length(locals) == 0
        return Expr(:call, :htl_escape, esc(expr))
    end

    if expr.head == :macrocall && expr.args[1] == Symbol("@htl_str")
        return htl_str(expr.args[3], cntx, locals)
    end

    # so this is basically when we have failed to parse...
    if expr.head == :incomplete
        throw(ErrorException("unable to handle escape sequences"))
    end

    # unless it is well defined, let's not translate it
    throw(DomainError(expr, "undefined interpolation"))
end

function htl_escape(var, ctx::Symbol=:content)::String
    if isa(var, HTML{String})
        return var.content
    elseif isa(var, AbstractString)
        return replace(replace(var, "&" => "&amp;"), "<" => "&lt;")
    elseif isa(var, Number)
        return string(var)
    else
        throw(DomainError(var, "unescapable type $(typeof(var))"))
    end
end

end
