"""
    HypertextLiteral

This library provides for a `@htl()` macro and a `htl` string literal,
both implementing interpolation that is aware of hypertext escape
context. The `@htl` macro has the advantage of using Julia's native
string parsing, so that it can handle arbitrarily deep nesting. However,
it is a more verbose than the `htl` string literal and doesn't permit
interpolated string literals. Conversely, the `htl` string literal,
`@htl_str`, uses custom parsing letting it handle string literal
escaping, however, it can only be used two levels deep (using three
quotes for the outer nesting, and a single double quote for the inner).
"""
module HypertextLiteral

export @htl_str, @htl

import Base: show

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
    # it by `$` to find interpolated parts and degating the hard work
    # to `Meta.parse`, treating everything else as a literal string.
    this = Expr(:macrocall, Symbol("@htl_str"), nothing, expr)
    args = Any[]
    vstr = String[]
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
        push!(vstr, unescape_string(SubString(expr, start:finish)))
        start = idx += 1
        if escaped
            escaped = false
            push!(vstr, "\$")
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
        if length(vstr) > 0
            push!(args, join(vstr))
            empty!(vstr)
        end
        push!(args, nest)
    end
    if start <= strlen
        push!(vstr, unescape_string(SubString(expr, start:strlen)))
    end
    if length(vstr) > 0
        push!(args, join(vstr))
        empty!(vstr)
    end
    return interpolate(args, this)
end

"""
    kebab_case(s)

This converts an name in `PascalCase`, `camelCase`, and `snake_case`
into their `kebab-case` equivalent. This will lowercase the name.
This transformation is problematic for SVG attribute names, which
need to be in `camelCase`.
"""
function kebab_case(name::String)
    name = replace(name, r"[A-Z]" => (x -> "-$(lowercase(x))"))
    name = startswith(name, "-") ? name[2:end] : name
    return replace(name, "_" => "-")
end

kebab_case(sym::Symbol) = kebab_case(string(sym))

"""
    Attribute{name}

This parameterized type to represent HTML attributes so that we could
dispatch serialization of custom attributes and data types. This is
modeled upon the `MIME` data type. Values written in this way must be
escaped for single-quoted context (`'` => "&apos;", `&` => "&amp;").
"""
struct Attribute{name} end

function Attribute(name::String)
    if length(name) < 1
        throw(DomainError(name, "Attribute name must not be empty."))
    end
    # We really need Attribute to have the namespace so that SVG
    # attributes are run though `camel_case` instead of `kebab_case`.
    name = kebab_case(name)
    # Attribute names are unquoted and do not have & escaping;
    # the &, % and \ characters don't seem to be prevented by the
    # specification, but they likely signal a programming error.
    for invalid in "/>='<&%\\\"\t\n\f\r\x20\x00"
        if invalid in name
            throw(DomainError(name, "Invalid character ('$invalid') " *
               "found within an attribute name."))
        end
    end
    return Attribute{Symbol(name)}()
end

"""
    stringify(a::Attribute{name})

This provides the serialization of a given normalized attribute so that
camelCase could be preserved on output for elements foreign to HTML,
such as SVG. By default, about 2 dozen SVG attributes are defined.
"""
stringify(::Attribute{name}) where {name} = string(name)

begin
    for svg_attribute in (
        "altGlyphDef", "altGlyphItem", "animateColor", "animateMotion",
        "animateTransform", "clipPath", "feBlend", "feColorMatrix",
        "feComponentTransfer", "feComposite", "feConvolveMatrix",
        "feDiffuseLighting", "feDisplacementMap", "feDistantLight",
        "feDropShadow", "feFlood", "feFuncA", "feFuncB", "feFuncG",
        "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode",
        "feMorphology", "feOffset", "fePointLight", "feSpecularLighting",
        "feSpotLight", "feTile", "feTurbulence", "foreignObject",
        "glyphRef", "linearGradient", "radialGradient", "textPath")
      sym = QuoteNode(Symbol(kebab_case(svg_attribute)))
      eval(:(stringify(::Attribute{$sym}) = $svg_attribute))
    end
end

"""
    is_boolean(attribute::Attribute)

This function returns true if the given attribute is boolean. In in such
case, `false` or `nothing` means the attribute should be removed from
the produced output. Note that there are some HTML attributes which may
take a boolean value but that produce `on` or `off`, or something else.
Those attributes are not considered boolean.
"""
is_boolean(::Attribute{name}) where {name} =
    name in (:allowfullscreen, :allowpaymentrequest, :async, :autofocus,
      :autoplay, :checked, :controls, :default, :disabled,
      :formnovalidate, :hidden, :ismap, :itemscope, :loop, :multiple,
      :muted, :nomodule, :novalidate, :open, :playsinline, :readonly,
      :required, :reversed, :selected, :truespeed)

"""
    htl_escape_value(s)

Perform extensive escaping needed for a string to be used as an unquoted
attribute. This can also be used for quoted values or within element
content (although it's overkill in those contexts).
"""
htl_escape_value(value::AbstractString) =
    replace(value, r"[\"\s<>&'`=]" => entity)

function entity(str::AbstractString)
    @assert length(str) == 1
    entity(str[1])
end

entity(ch::Char) = "&#$(Int(ch));"

"""
    stringify(attribute::Attribute, value)

Convert an attribute `value`` to a `String` suitable for inclusion into
the given attribute's value. The value returned will then be escaped
depending upon the particular context, single/double or unquoted.

* `String` values are returned as-is
* `Number` and `Symbol` values are converted to a `String`
* `Bool` values of known boolean attributes produce an error.
* `Nothing` becomes an empty string (unless for boolean attribute).

There is no general fallback, hence, a `MethodError` will result when
attempting to stringify most data types. If your application would like
to stringify all attribute values, you could register this fallback.

    stringify(::Attribute, value) = string(value)

"""
stringify(::Attribute, value::AbstractString) = value
stringify(::Attribute, value::Number) = string(value)
stringify(::Attribute, value::Symbol) = string(value)

function stringify(attr::Attribute{name}, value::Bool) where {name}
    if is_boolean(attr)
         throw(DomainError(repr(value), "The attribute '$(string(name))' " *
             "is boolean, use unquoted attribute form."))
    end
    return string(value)
end

function stringify(attr::Attribute{name}, value::Nothing) where {name}
    if is_boolean(attr)
         throw(DomainError(repr(value), "The attribute '$(string(name))' " *
             "is boolean, use unquoted attribute form."))
    end
    return ""
end

"""
Interpolated Value

This abstract type represents a value that must be escaped. The various
subclasses provide the context for the escaping. They include:

  ElementData            Values expanded as element content, including
                         text nodes and/or subordinate HTML fragments
  ElementAttributes      Values to be expanded as attribute/value pairs
  AttributePair          Unquoted name/value pair for attributes; handles
                         special cases of boolean attributes
  AttributeDoubleQuoted  Value serialized within double quoted attribute
  AttributeSingleQuoted  Value serialized within single quoted attribute

The string interpolation is here is conservative. To provide express
data type conversions for `ElementData`, override `show` `"text/html"`.
"""
abstract type InterpolatedValue end

#-------------------------------------------------------------------------
struct ElementData <: InterpolatedValue value end

ElementData(args...) = [ElementData(item) for item in args]

function show(io::IO, mime::MIME"text/html", child::ElementData)
    value = child.value
    if value isa AbstractString
        return print(io, replace(child.value, r"[<&]" => entity))
    end
    if value isa Number || child.value isa Symbol
        return print(io, replace(string(child.value), r"[<&]" => entity))
    end
    if showable(MIME("text/html"), value)
        return show(io, mime, value)
    end
    if value isa Base.Generator || value isa Tuple
        value = collect(value)
        if eltype(value) <: AbstractString ||
           eltype(value) <: Number ||
           eltype(value) <: Symbol
            for item in value
                print(io, replace(string(item), r"[<&]" => entity))
            end
            return
        end
    end
    if value isa AbstractVector
        if hasmethod(show, Tuple{IO, typeof(mime), eltype(value)})
            for item in value
                show(io, mime, item)
            end
            return
        end
        throw(DomainError(value, """
          Type $(typeof(value)) lacks a show method for text/html.
          Perhaps use splatting? e.g. htl"\$([x for x in 1:3]...)
        """))
    end
    throw(DomainError(value, """
      Type $(typeof(value)) lacks a show method for text/html.
      Alternatively, you can cast the value to a string first.
    """))
end

#-------------------------------------------------------------------------
struct ElementAttributes <: InterpolatedValue value end

function show(io::IO, mime::MIME"text/html", x::ElementAttributes)
    value = x.value
    if value isa Pair
        show(io, mime, AttributePair(value.first, value.second))
    elseif value isa Dict || value isa NamedTuple
        for (k, v) in pairs(value)
            show(io, mime, AttributePair(k, v))
        end
    elseif value isa Tuple{Pair, Vararg{Pair}}
        for (k, v) in value
            show(io, mime, AttributePair(k, v))
        end
    else
        throw(DomainError(value, """
          Unable to convert $(typeof(value)) to an attribute name/value pair.
          Did you forget the trailing "," in a 1-element named tuple?
        """))
    end
end

#-------------------------------------------------------------------------
struct RawText <: InterpolatedValue
    value::String

    function RawText(value::String, element::Symbol)
        if occursin("</$element>", lowercase(value))
            throw(DomainError(repr(value), "  Content of <$element> cannot " *
                "contain the end tag (`</$element>`)."))
        end
        if element == :script && occursin("<!--", value)
            # this could be slightly more nuanced
            throw(DomainError(repr(value), "  Content of <$element> should " *
                "not contain a comment block (`<!--`) "))
        end
        new(value)
    end
end

show(io::IO, mime::MIME"text/html", wrapper::RawText) =
    print(io, wrapper.value)


"""
    css_value(val)

Convert a native Julia object into a string suitable for use as a CSS
value. This is useful for adding support for `cssunits` or other tools
that build CSS fragments.
"""
css_value(value::Symbol) = string(value)
css_value(value::Number) = string(value) # includes boolean
css_value(value::AbstractString) = value

css_key(key::Symbol) = kebab_case(string(key))
css_key(key::String) = key

stringify(at::Attribute{:style}, value::Dict) =
    join(stringify(at, pair) for pair in pairs(value))

stringify(at::Attribute{:style}, value::NamedTuple) =
    join(stringify(at, pair) for pair in pairs(value))

stringify(at::Attribute{:style}, value::Tuple{Pair, Vararg{Pair}}) =
    join(stringify(at, pair) for pair in value)

stringify(at::Attribute{:style}, (key, value)::Pair) =
    "$(css_key(key)): $(css_value(value));"

# space separate class attribute items

stringify(at::Attribute{:class}, value::AbstractVector) =
    join([stringify(at, item) for item in value], " ")

stringify(at::Attribute{:class}, value::Tuple{Any, Vararg{Any}}) =
    join([stringify(at, item) for item in value], " ")

#-------------------------------------------------------------------------
"""
    attribute_pair(attribute, value)

Wrap and escape attribute name and pair within a single-quoted context
so that it is `showable("text/html")`. This uses `stringify` to do the
actual conversion of the attribute to a usable string value. If an
attribute `is_boolean` it is given special treatment, for `true` values,
the attribute is printed with an empty string, else it is omitted.
Moreover, attributes with value of `nothing` are coalesced to the empty
string (unless they are boolean, in which case they are omitted).
"""
function attribute_pair(attribute, value)
    value = escape_single_quote(stringify(attribute, value))
    return HTML(" $(stringify(attribute))='$(value)'")
end

function attribute_pair(attr::Attribute{name}, value::Bool) where {name}
    if is_boolean(attr)
        if value == false
            return HTML("")
        end
        return HTML(" $(stringify(attribute))=''")
    end
    value = escape_single_quote(stringify(attribute, value))
    return HTML(" $(stringify(attribute))='$(value)'")
end

function attribute_pair(attr::Attribute{name}, value::Nothing) where {name}
    if is_boolean(attr)
        return HTML("")
    end
    value = escape_single_quote(stringify(attribute, value))
    return HTML(" $(stringify(attribute))='$(value)'")
end

"""
    single_quoted(attribute, value)

Wrap and escape a single-quoted attribute value so that it is
`showable("text/html")`. This uses `stringify` to do the actual
conversion of the attribute to a usable string value.
"""
single_quoted(attribute, value) =
    HTML(escape_single_quote(stringify(attribute, value)))

function escape_single_quote(value)
    if '&' in value
        value = replace(value, "&" => "&amp;")
    end
    if '\'' in value
        value = replace(value, "'" => "&apos;")
    end
    return value
end

"""
    double_quoted(attribute, value)

Wrap and escape a double-quoted attribute value so that it is
`showable("text/html")`. This uses `stringify` to do the actual
conversion of the attribute to a usable string value.
"""
double_quoted(attribute, value) =
    HTML(escape_double_quote(stringify(attribute, value)))

function escape_double_quote(value)
    if '&' in value
        value = replace(value, "&" => "&amp;")
    end
    if '"' in value
        value = replace(value, "\"" => "&quot;")
    end
    return value
end

#-------------------------------------------------------------------------
"""
    escape_content(value)

Escape a string value for use within HTML content, this includes
replacing `&` with `&amp;` and `<` with `&lt;`. We're not further
escaping quotes within content since benchmarking shows us that it
adds about 10% on the runtime for each character escaped.
"""
function escape_content(value)
    if '&' in value
        value = replace(value, "&" => "&amp;")
    end
    if '<' in value
        value = replace(value, "<" => "&lt;")
    end
    return value
end

"""
    content(value)

Wrap and escape content so that it is `showable("text/html")`. By
default, we handle strings, numbers and symbols by escaping them.
Tuples, arrays and generators are wrapped by concatenating their
elements. As a fallback, we assume the value has implemented `show()`
for `MIME"text/html"`, if not, a `MethodError` will result.
"""
content(x) = x
content(x::AbstractString) = HTML(escape_content(x))
content(x::Number) = HTML(escape_content(string(x)))
content(x::Symbol) = HTML(escape_content(string(x)))
content(xs...) = content(xs)
for concrete in (Int, Float64, Bool)
   eval(:(content(x::$concrete) = HTML(x)))
end

function content(xs::Union{Tuple, AbstractArray, Base.Generator})
    HTML{Function}() do io
      for x in xs
        show(io, MIME"text/html"(), content(x))
      end
    end
end

@enum HtlParserState STATE_DATA STATE_TAG_OPEN STATE_END_TAG_OPEN STATE_TAG_NAME STATE_BEFORE_ATTRIBUTE_NAME STATE_AFTER_ATTRIBUTE_NAME STATE_ATTRIBUTE_NAME STATE_BEFORE_ATTRIBUTE_VALUE STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED STATE_ATTRIBUTE_VALUE_UNQUOTED STATE_AFTER_ATTRIBUTE_VALUE_QUOTED STATE_SELF_CLOSING_START_TAG STATE_COMMENT_START STATE_COMMENT_START_DASH STATE_COMMENT STATE_COMMENT_LESS_THAN_SIGN STATE_COMMENT_LESS_THAN_SIGN_BANG STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH STATE_COMMENT_END_DASH STATE_COMMENT_END STATE_COMMENT_END_BANG STATE_MARKUP_DECLARATION_OPEN STATE_RAWTEXT STATE_RAWTEXT_LESS_THAN_SIGN STATE_RAWTEXT_END_TAG_OPEN STATE_RAWTEXT_END_TAG_NAME

is_alpha(ch) = 'A' <= ch <= 'Z' || 'a' <= ch <= 'z'
is_space(ch) = ch in ('\t', '\n', '\f', ' ')
normalize(s) = replace(replace(s, "\r\n" => "\n"), "\r" => "\n")
nearby(x,i) = i+10>length(x) ? x[i:end] : x[i:i+8] * "…"

"""
    interpolate(args, this)::Expr

Take an interweaved set of Julia expressions and strings, tokenize the
strings according to the HTML specification [1], wrapping the
expressions with wrappers based upon the escaping context, and returning
an expression that combines the result with an `Result` wrapper.

For these purposes, a `Symbol` is treated as an expression to be
resolved; while a `String` is treated as a literal string that won't be
escaped. Critically, interpolated strings to be escaped are represented
as an `Expr` with `head` of `:string`.

There are tags, "script" and "style" which are rawtext, in these cases
there is no escaping, and instead raise an exception if the appropriate
ending tag is in substituted content.

[1] https://html.spec.whatwg.org/multipage/parsing.html#tokenization
"""
function interpolate(args, this)
    state = STATE_DATA
    parts = Expr[]
    attribute_start = attribute_end = 0
    element_start = element_end = 0
    buffer_start = buffer_end = 0
    attribute_tag = nothing
    element_tag = nothing
    state_tag_is_open = false

    function choose_tokenizer()
        if state_tag_is_open
            if element_tag in (:style, :xmp, :iframe, :noembed,
                               :noframes, :noscript, :script)
                return STATE_RAWTEXT
            end
        end
        return STATE_DATA
    end

    args = [a for a in args if a != ""]

    for j in 1:length(args)
        input = args[j]
        if !isa(input, String)
            if state == STATE_DATA
                push!(parts, :(content($(esc(input)))))
            elseif state == STATE_RAWTEXT
                push!(parts, :(RawText($input, $(QuoteNode(element_tag)))))
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous HTML string to remove ` attname=`
                @assert Meta.isexpr(parts[end], :call, 2)
                expr_args = parts[end].args
                @assert expr_args[1] == :HTML
                name = expr_args[2][attribute_start:attribute_end]
                expr_args[2] = expr_args[2][1:(attribute_start-2)]
                attribute = Attribute(name)
                push!(parts, :(attribute_pair($attribute, $(esc(input)))))
                # peek ahead to ensure we have a delimiter
                if j < length(args)
                    next = args[j+1]
                    if next isa String && !occursin(r"^[\s+\/>]", next)
                        msg = "$(name)=$(nearby(next,1))"
                        throw(DomainError(msg, "Unquoted attribute " *
                          "interpolation is limited to a single component"))
                    end
                end
            elseif state == STATE_ATTRIBUTE_VALUE_UNQUOTED
                throw(DomainError(input, "Unquoted attribute " *
                  "interpolation is limited to a single component"))
            elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                attribute = Attribute(attribute_tag)
                push!(parts, :(single_quoted($attribute, $(esc(input)))))
            elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                attribute = Attribute(attribute_tag)
                push!(parts, :(double_quoted($attribute, $(esc(input)))))
            elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                # strip space before interpolated element pairs
                if parts[end] isa String && parts[end][end] == ' '
                    finish = length(parts[end])-1
                    parts[end] = parts[end][1:finish]
                end
                # TODO: resolve attribute names early if possible
                push!(parts, :(ElementAttributes($input)))
                # move the space to after the element pairs
                if j < length(args)
                    next = args[j+1]
                    if next isa String && !occursin(r"^[\s+\/>]", next)
                        args[j+1] = " " * next
                    end
                end
            elseif state == STATE_COMMENT || true
                throw("invalid binding #1 $(state)")
            end
        else
            inputlength = length(input)
            input = normalize(input)
            i = 1
            while i <= inputlength
                ch = input[i]

                if state == STATE_DATA
                    if ch === '<'
                        state = STATE_TAG_OPEN
                    end

                elseif state == STATE_RAWTEXT
                    if ch === '<'
                        state = STATE_RAWTEXT_LESS_THAN_SIGN
                    end

                elseif state == STATE_TAG_OPEN
                    if ch === '!'
                        state = STATE_MARKUP_DECLARATION_OPEN
                    elseif ch === '/'
                        state = STATE_END_TAG_OPEN
                    elseif is_alpha(ch)
                        state = STATE_TAG_NAME
                        state_tag_is_open = true
                        element_start = i
                        i -= 1
                    elseif ch === '?'
                        # this is an XML processing instruction, with
                        # recovery production called "bogus comment"
                        throw(DomainError(nearby(input, i-1),
                          "unexpected question mark instead of tag name"))
                    else
                        throw(DomainError(nearby(input, i-1),
                          "invalid first character of tag name"))
                    end

                elseif state == STATE_END_TAG_OPEN
                    @assert !state_tag_is_open
                    if is_alpha(ch)
                        state = STATE_TAG_NAME
                        i -= 1
                    elseif ch === '>'
                        state = STATE_DATA
                    else
                        throw(DomainError(nearby(input, i-1),
                          "invalid first character of tag name"))
                    end

                elseif state == STATE_TAG_NAME
                    if isspace(ch) || ch === '/' || ch === '>'
                        if state_tag_is_open
                            element_tag = Symbol(lowercase(
                                            input[element_start:element_end]))
                            element_start = element_end = 0
                        end
                        if isspace(ch)
                            state = STATE_BEFORE_ATTRIBUTE_NAME
                            # subordinate states use state_tag_is_open flag
                        elseif ch === '/'
                            state = STATE_SELF_CLOSING_START_TAG
                            state_tag_is_open = false
                        elseif ch === '>'
                            state = choose_tokenizer()
                            state_tag_is_open = false
                        end
                    else
                        if state_tag_is_open
                            element_end = i
                        end
                    end

                elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                    if is_space(ch)
                        nothing
                    elseif ch === '/' || ch === '>'
                        state = STATE_AFTER_ATTRIBUTE_NAME
                        i -= 1
                    elseif ch in  '='
                        throw(DomainError(nearby(input, i-1),
                          "unexpected equals sign before attribute name"))
                    else
                        state = STATE_ATTRIBUTE_NAME
                        attribute_start = i
                        attribute_end = nothing
                        i -= 1
                    end

                elseif state == STATE_ATTRIBUTE_NAME
                    if is_space(ch) || ch === '/' || ch === '>'
                        state = STATE_AFTER_ATTRIBUTE_NAME
                        i -= 1
                    elseif ch === '='
                        state = STATE_BEFORE_ATTRIBUTE_VALUE
                    elseif ch in ('"', '\"', '<')
                        throw(DomainError(nearby(input, i-1),
                          "unexpected character in attribute name"))
                    else
                        attribute_end = i
                    end

                elseif state == STATE_AFTER_ATTRIBUTE_NAME
                    if is_space(ch)
                        nothing
                    elseif ch === '/'
                        state = STATE_SELF_CLOSING_START_TAG
                    elseif ch === '='
                        state = STATE_BEFORE_ATTRIBUTE_VALUE
                    elseif ch === '>'
                        state = choose_tokenizer()
                        state_tag_is_open = false
                    else
                        state = STATE_ATTRIBUTE_NAME
                        attribute_start = i
                        attribute_end = nothing
                        i -= 1
                    end

                elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                    if is_space(ch)
                        nothing
                    elseif ch === '"'
                        attribute_tag = input[attribute_start:attribute_end]
                        state = STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                    elseif ch === '\''
                        attribute_tag = input[attribute_start:attribute_end]
                        state = STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "missing attribute value"))
                    else
                        state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                        i -= 1
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                    if ch === '"'
                        state = STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                        attribute_tag = nothing
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                    if ch === '\''
                        state = STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                        attribute_tag = nothing
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_UNQUOTED
                    if is_space(ch)
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                    elseif ch === '>'
                        state = choose_tokenizer()
                        state_tag_is_open = false
                    elseif ch in ('"', '\'', "<", "=", '`')
                        throw(DomainError(nearby(input, i-1),
                          "unexpected character in unquoted attribute value"))
                    end

                elseif state == STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                    if is_space(ch)
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                    elseif ch === '/'
                        state = STATE_SELF_CLOSING_START_TAG
                    elseif ch === '>'
                        state = choose_tokenizer()
                        state_tag_is_open = false
                    else
                        throw(DomainError(nearby(input, i-1),
                          "missing whitespace between attributes"))
                    end

                elseif state == STATE_SELF_CLOSING_START_TAG
                    if ch === '>'
                        state = STATE_DATA
                    else
                        throw(DomainError(nearby(input, i-1),
                          "unexpected solidus in tag"))
                    end

                elseif state == STATE_MARKUP_DECLARATION_OPEN
                    if ch === '-' && input[i + 1] == '-'
                        state = STATE_COMMENT_START
                        i += 1
                    elseif startswith(input[i:end], "DOCTYPE")
                        throw("DOCTYPE not supported")
                    elseif startswith(input[i:end], "[CDATA[")
                        throw("CDATA not supported")
                    else
                        throw(DomainError(nearby(input, i-1),
                          "incorrectly opened comment"))
                    end

                elseif state == STATE_COMMENT_START
                    if ch === '-'
                        state = STATE_COMMENT_START_DASH
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "abrupt closing of empty comment"))
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_START_DASH
                    if ch === '-'
                        state = STATE_COMMENT_END
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "abrupt closing of empty comment"))
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT
                    if ch === '<'
                        state = STATE_COMMENT_LESS_THAN_SIGN
                    elseif ch === '-'
                        state = STATE_COMMENT_END_DASH
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN
                    if ch === '!'
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG
                    elseif ch === '<'
                        nothing
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG
                    if ch == "-"
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    if ch == "-"
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    else
                        state = STATE_COMMENT_END
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    if ch == ">"
                        state = STATE_COMMENT_END
                        i -= 1
                    else
                        throw(DomainError(nearby(input, i-1),
                          "nested comment"))
                    end

                elseif state == STATE_COMMENT_END_DASH
                    if ch === '-'
                        state = STATE_COMMENT_END
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_END
                    if ch === '>'
                        state = STATE_DATA
                    elseif ch === '!'
                        state = STATE_COMMENT_END_BANG
                    elseif ch === '-'
                        nothing
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_END_BANG
                    if ch === '-'
                        state = STATE_COMMENT_END_DASH
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "nested comment"))
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_RAWTEXT_LESS_THAN_SIGN
                    if ch === '/'
                        state = STATE_RAWTEXT_END_TAG_OPEN
                    elseif ch === '!' && element_tag == :script
                        # RAWTEXT differs from SCRIPT here
                        throw("script data escape is not implemented")
                    else
                        state = STATE_RAWTEXT
                        # do not "reconsume", even though spec says so
                    end

                elseif state == STATE_RAWTEXT_END_TAG_OPEN
                    if is_alpha(ch)
                        state = STATE_RAWTEXT_END_TAG_NAME
                        buffer_start = i
                        i -= 1
                    else
                        state = STATE_RAWTEXT
                        i -= 1
                    end

                elseif state == STATE_RAWTEXT_END_TAG_NAME
                    if is_alpha(ch)
                        buffer_end = i
                    elseif ch in ('/', '>') || is_space(ch)
                        # test for "appropriate end tag token"
                        current = input[buffer_start:buffer_end]
                        if Symbol(lowercase(current)) == element_tag
                            if ch === '/'
                                state = STATE_SELF_CLOSING_START_TAG
                            elseif ch === '>'
                                state = STATE_DATA
                            else
                                state = STATE_BEFORE_ATTRIBUTE_NAME
                            end
                            continue
                        else
                            state = STATE_RAWTEXT
                        end
                    else
                        state = STATE_RAWTEXT
                    end

                else
                    @assert "unhandled state transition"
                end

                i = i + 1
            end
            push!(parts, Expr(:call, :HTML, input))
        end
    end
    return Expr(:call, :Result, QuoteNode(this), parts...)
end

"""
    Result(expr, xs...)

Create an object that is `showable` to "text/html" created from
arguments that are also showable. Leaf entries can be created using
`HTML`. This expression additionally has an expression which is used
when displaying the object to the REPL. Calling `print` will produce
rendered output.
"""
struct Result
    content::Function
    this::Expr
end

function Result(s::String)
    Result(io -> print(io, s), Expr(:call, :HTL, s))
end

function Result(this::Expr, xs...)
    Result(this) do io
      for x in xs
        show(io, MIME"text/html"(), x)
      end
    end
end

Base.show(io::IO, ::MIME"text/html", h::Result) = h.content(io)
Base.print(io::IO, h::Result) = h.content(io)
Base.show(io::IO, h::Result) = print(io, h.this)

end
