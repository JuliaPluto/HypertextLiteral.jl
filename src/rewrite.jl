"""
    normalize_attribute_name(name)

For `String` names, this simply verifies that they pass the attribute
name production, but are otherwise untouched.

For `Symbol` names, this converts `snake_case` Symbol objects to their
`kebab-case` equivalent. So that keywords, such as `for` could be used,
we strip leading underscores.
"""
function normalize_attribute_name(name::Symbol)
    name = String(name)
    if '_' in name
       while length(name) > 0 && name[1] == '_'
           name = name[2:end]
       end
       name = replace(name, "_" => "-")
    end
    return normalize_attribute_name(name)
end

function normalize_attribute_name(name::AbstractString)
    # Attribute names are unquoted and do not have & escaping;
    # the &, % and \ characters don't seem to be prevented by the
    # specification, but they likely signal a programming error.
    for invalid in "/>='<&%\\\"\t\n\f\r\x20\x00"
        if invalid in name
            throw(DomainError(name, "Invalid character ('$invalid') " *
               "found within an attribute name."))
        end
    end
    if isempty(name)
        throw("Attribute name must not be empty.")
    end
    return name
end

"""
    rewrite_inside_tag(expr)

Attempt to speed up serialization of inside_tag by exploring the
expression tree at macro expansion time.
"""
function rewrite_inside_tag(expr)::Vector{Expr}
    if Meta.isexpr(expr, :tuple)
        args = expr.args
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :Dict
        args = expr.args[2:end]
    elseif Meta.isexpr(expr, :call) && expr.args[1] == :(=>)
        args = [expr]
    elseif expr isa QuoteNode && expr.value isa Symbol
        args = expr.value
    elseif Meta.isexpr(expr, :string, 1) && typeof(expr.args[1]) == String
        args = [expr.args[1]]
    else
        return [:(inside_tag($(esc(expr))))]
    end
    parts = []
    for pair in args
        if pair isa Symbol || pair isa AbstractString
            (name, value) = (pair, "")
        elseif Meta.isexpr(pair, :(=), 2)
            (name, value) = pair.args
        elseif Meta.isexpr(pair, :call, 3) && pair.args[1] == :(=>)
            (_, name, value) = pair.args
            if name isa AbstractString
                nothing
            elseif name isa QuoteNode && name.value isa Symbol
                name = name.value
            else
                return [:(inside_tag($(esc(expr))))]
            end
        else
            # unexpected, use dynamic method
            return [:(inside_tag($(esc(expr))))]
        end
        attribute = normalize_attribute_name(name)
        push!(parts, :(attribute_pair($attribute, $(esc(value)))))
    end
    return parts
end
