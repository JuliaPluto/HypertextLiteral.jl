"""
    print_value(io, value)

This is the default translation of interpolated values within rawtext
tags, such as `<style>` and attribute values.

* The elements of a `Tuple` or `AbstractArray` object are printed,
  with a space between each item.

* The `Pair`, `NamedTuple`, and `Dict` objects are treated as if
  they are CSS style elements, with a colon between key and value,
  each pair delimited by a semi-colon.

* The `Nothing` object is treated as an empty string.

Otherwise, this method simply uses the standard `print` representation
for the given object.
"""
print_value(io::IO, @nospecialize value) =
    print(io, value)
print_value(io::IO, ::Nothing) =
    nothing

function print_value(io::IO, xs::Union{Tuple, AbstractArray, Base.Generator})
    prior = false
    for x in xs
        if prior
            print(io, " ")
        end
        print_value(io, x)
        prior = true
    end
end

function print_pairs(io, xs)
    prior = false
    for (key, value) in xs
        name = normalize_attribute_name(key)
        if prior
            print(io, "; ")
        end
        print(io, name)
        print(io, ": ")
        print_value(io, value)
        prior = true
    end
    print(io, ";")
end

print_value(io::IO, pair::Pair) = print_pairs(io, (pair,))
print_value(io::IO, items::Dict) = print_pairs(io, items)
print_value(io::IO, items::NamedTuple) = print_pairs(io, pairs(items))
print_value(io::IO, items::Tuple{Pair, Vararg{Pair}}) = print_pairs(io, items)

"""
    attribute_value(x)

This method may be implemented to specify a printed representation
suitable for use within a quoted attribute value.
"""
attribute_value(x::String) = x
attribute_value(x::Number) = x
attribute_value(x::Symbol) = x

mutable struct AttributeValue
    content::Any
end

Base.print(ep::EscapeProxy, x::AttributeValue) =
    print_value(ep, x.content)

attribute_value(@nospecialize x) = AttributeValue(x)

"""
    content(x)

This method may be implemented to specify a printed representation
suitable for `text/html` output. `AbstractString`, `Symbol` and `Number`
(including `Bool`) types are printed, with proper escaping.

A default implementation first looks to see if `typeof(x)` has
implemented a way to show themselves as `text/html`, if so, this is
used. Otherwise, the result is printed within a `<span>` tag, using a
`class` that includes the module and type name. Hence, `missing` is
serialized as: `<span class="Base-Missing">missing</span>`.
"""
@generated function content(x)
     if hasmethod(show, Tuple{IO, MIME{Symbol("text/html")}, x})
         return :(Render(x))
     else
         mod = parentmodule(x)
         cls = string(nameof(x))
         if mod == Core || mod == Base || pathof(mod) !== nothing
             cls = join(fullname(mod), "-") * "-" * cls
         end
         span = """<span class="$cls">"""
         return :(PrintSequence(Bypass($span), x, Bypass("</span>")))
     end
end

content(x::Union{AbstractString, Symbol}) = x
content(x::Nothing) = ""
content(x::Union{AbstractFloat, Bool, Integer}) = x
content(xs...) = content(xs)

function content(xs::Union{Tuple, AbstractArray, Base.Generator})
    PrintSequence((content(x) for x in xs)...)
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

no_content = PrintSequence()

function attribute_pair(name, value)
    PrintSequence(
        " ",
        name,
        Bypass("='"),
        attribute_value(value),
        Bypass("'")
    )
end

function attribute_pair(name, value::Bool)
    if value == false
        return no_content
    end
    PrintSequence(
        " ", 
        name, 
        Bypass("=''")
    )
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

function inside_tag(value::Union{AbstractString, Symbol})
    name = normalize_attribute_name(value)
    return attribute_pair(name, "")
end

function inside_tag(xs::AbstractDict)
    PrintSequence((
        let name = normalize_attribute_name(key)
            attribute_pair(name, value)
        end for (key, value) in xs)...
    )
end

inside_tag(values::NamedTuple) =
    inside_tag(pairs(values))

inside_tag(::Nothing) = no_content

"""
    tag_name(x)

Tag names need to start with `/[a-z]/i`,
and can't contain any spaces, `>` or `/`.
Although technically all other characters would be valid,
we only allow letters, numbers and hyphens for now.
"""

function tag_name(x::String)
    if isempty(x)
        throw("A tag name can not be empty")
    elseif !occursin(r"^[a-z]"i, x)
        throw("A tag name can only start with letters, not `$(x[1])`")
    elseif occursin(r"[^a-z0-9-]", x)
        throw("Content within a tag name can only contain latin letters, numbers or hyphens (`-`)")
    else
        x
    end
end
tag_name(x::Symbol) = tag_name(string(x))
tag_name(x::Any) = throw("Can't use complex objects as tag name")
