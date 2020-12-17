"""
    attribute_value(x)

This method may be implemented to specify a printed representation
suitable for use within a quoted attribute value. By default, the print
representation of an object is used, and then propertly escaped. There
are a few overrides that we provide.

* The elements of a `Tuple` or `AbstractArray` object are printed,
  with a space between each item.

* The `Pair`, `NamedTuple`, and `Dict` objects are treated as if
  they are CSS style elements, with a colon between key and value,
  each pair delimited by a semi-colon.

* The `Bool` object, which has special treatment for bare inside_tag,
  is an error when used within a quoted attribute.

If an object is wrapped with `HTML` then it is included in the quoted
attribute value as-is, without inspection or escaping.
"""
attribute_value(x::AbstractString) = x
attribute_value(x::Number) = x
attribute_value(x::Symbol) = x
attribute_value(x::Nothing) = ""
attribute_value(x::Bool) =
  throw("Boolean used within a quoted attribute.")

function attribute_value(xs::Union{Tuple, AbstractArray, Base.Generator})
    Reprint() do io::IO
        prior = false
        for x in xs
            if prior
                print(io, " ")
            end
            print(io, attribute_value(x))
            prior = true
        end
    end
end

function attribute_pairs(xs)
    Reprint() do io::IO
        prior = false
        for (key, value) in xs
            name = normalize_attribute_name(key)
            if prior
                print(io, "; ")
            end
            print(io, name)
            print(io, ": ")
            print(attribute_value(value))
            prior = true
        end
        print(io, ";")
    end
end

attribute_value(pair::Pair) = attribute_pairs((pair,))
attribute_value(items::Dict) = attribute_pairs(items)
attribute_value(items::NamedTuple) = attribute_pairs(pairs(items))
attribute_value(items::Tuple{Pair, Vararg{Pair}}) = attribute_pairs(items)

"""
    content(x)

This method may be implemented to specify a printed representation
suitable for `text/html` output. As a special case, if the result is
wrapped with `HTML`, then it is passed along as-is. Otherwise, the
`print` representation of the resulting value is escaped. By default
`AbstractString`, `Number` and `Symbol` values are printed and escaped.
The elements of `Tuple` and `AbstractArray` are concatinated and then
escaped. If a method is not implemented for a given object, then we
attempt to `show` it via `MIME"text/html"`.
"""
content(x) = Render(x)
content(x::AbstractString) = x
content(x::Number) = x
content(x::Symbol) = x
content(x::Nothing) = ""
content(xs...) = content(xs)

function content(xs::Union{Tuple, AbstractArray, Base.Generator})
    Reprint() do io::IO
        for x in xs
            print(io, content(x))
        end
    end
end

#-------------------------------------------------------------------------
"""
    attribute_pair(name, value)

Wrap and escape attribute name and pair within a single-quoted context
so that it is `showable("text/html")`. It's assumed that the attribute
name has already been normalized.

If an attribute value is `Bool` or `Nothing`, then special treatment is
provided. If the value is `false` or `nothing` then the entire pair is
not printed.  If the value is `true` than an empty string is produced.
"""

no_content = Reprint(io::IO -> nothing)

function attribute_pair(name, value)
    Reprint() do io::IO
        print(io, " ")
        print(io, name)
        print(io, Passthru("='"))
        print(io, attribute_value(value))
        print(io, Passthru("'"))
    end
end

function attribute_pair(name, value::Bool)
    if value == false
        return no_content
    end
    Reprint() do io::IO
        print(io, " ")
        print(io, name)
        print(io, Passthru("=''"))
    end
end

attribute_pair(name, value::Nothing) = no_content

"""
    inside_tag(value)

Convert Julian object into a serialization of attribute pairs,
`showable` via `MIME"text/html"`. The default implementation of this
delegates value construction of each pair to `attribute_pair()`.
"""
function inside_tag(value::Pair)
    name = normalize_attribute_name(value.first)
    return attribute_pair(name, value.second)
end

function inside_tag(xs)
    Reprint() do io::IO
        for (key, value) in xs
            name = normalize_attribute_name(key)
            print(io, attribute_pair(name, value))
        end
    end
end

inside_tag(values::NamedTuple) =
    inside_tag(pairs(values))

"""
    rawtext(context, value)

Wrap a string value that occurs with RAWTEXT, SCRIPT and other element
context so that it is `showable("text/html")`. The default
implementation ensures that the given value doesn't contain substrings
illegal for the given context.
"""
function rawtext(context::Symbol, value::AbstractString)
    if occursin("</$context>", lowercase(value))
        throw(DomainError(repr(value), "  Content of <$context> cannot " *
            "contain the end tag (`</$context>`)."))
    end
    if context == :script && occursin("<!--", value)
        # this could be slightly more nuanced
        throw(DomainError(repr(value), "  Content of <$context> should " *
            "not contain a comment block (`<!--`) "))
    end
    return Passthru(value)
end
