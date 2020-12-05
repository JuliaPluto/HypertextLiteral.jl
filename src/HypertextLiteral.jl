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

export HTL, @htl_str, @htl

"""
`HTL(s)`: Create an array of objects that render as html.

    HTL("<div>foo</div>")

This is similar `HTML{Vector}` with a few exceptions. First, the
contents of the vector are concatenated. Second, direct rendering is
limited to `AbstractString`, others are delegated to `show`. Third, the
splat constructor converts arguments to the `HTL` vector.

Finally, regular display of the value to the terminal renders the
objects and produces the equivalent string representation (unwise?).
"""
struct HTL
    content::Vector

    function HTL(obj)
        function check(item)
            if item isa AbstractString || showable(MIME("text/html"), item)
               return item
            end
            throw(DomainError(item, "Elements must be strings or " *
                              """objects showable as "text/html"."""))
        end
        if obj isa AbstractVector || obj isa Tuple
            return new([check(item) for item in obj])
        end
        return new([check(obj)])
    end
end

HTL(xs...) = HTL(xs)

function Base.show(io::IO, mime::MIME"text/html", h::HTL)
    for item in h.content
        if item isa AbstractString
            print(io, item)
        else
            Base.show(io, mime, item)
        end
    end
end

function Base.show(io::IO, mime::MIME"text/html", v::Vector{HTL})
    for item in v
        Base.show(io, mime, item)
    end
end

Base.show(io::IO, h::HTL) =
    print(io, "HTL(\"$(escape_string(sprint() do io
                  Base.show(io, MIME("text/html"), h) end))\")")

"""
    @htl string-expression

Create a `HTL` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Before Julia 1.6, interpolated
string literals, e.g. `\$("Strunk & White")`, are treated as errors
since they cannot be reliably detected (see Julia issue #38501).
"""
macro htl(expr)
    if expr isa String
        return interpolate([expr])
    end
    if expr.head != :string
       # TODO: what is going on in this case...
       @assert false
       return interpolate([expr])
    end
    @assert expr isa Expr
    if VERSION < v"1.6"
        # Find cases where we may have an interpolated string literal and
        # raise an exception (till Julia issue #38501 is addressed)
        if length(expr.args) == 1 && expr.args[1] isa String
            throw("interpolated string literals are not supported")
        end
        for idx in 2:length(expr.args)
            if expr.args[idx] isa String && expr.args[idx-1] isa String
                throw("interpolated string literals are not supported")
            end
        end
    end
    return interpolate(expr.args)
end

"""
    @htl_str -> Base.Docs.HTML{String}

Create a `HTL` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Escape sequences should work
identically to Julia strings, except in cases where a slash immediately
precedes the double quote (see `@raw_str` and Julia issue #22926).
"""
macro htl_str(expr::String)
    # This implementation emulates Julia's string interpolation behavior
    # as close as possible to produce an expression vector similar to
    # what would be produced by the `@htl` macro. Unlike most text
    # literals, we unescape content here. This logic also directly
    # handles interpolated literals, with contextual escaping.
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
            throw("invalid interpolation syntax")
        end
        start = idx
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
    return interpolate(args)
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

struct ElementData <: InterpolatedValue value end
struct ElementAttributes <: InterpolatedValue value end
struct AttributeDoubleQuoted <: InterpolatedValue value end
struct AttributeSingleQuoted <: InterpolatedValue value end

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

Base.show(io::IO, mime::MIME"text/html", wrapper::RawText) =
    print(io, wrapper.value)

"""
    HTLAttribute{name}

This parameterized type to represent HTML attributes so that we could
dispatch serialization of custom attributes and data types. This is
modeled upon the `MIME` data type.
"""
struct HTLAttribute{name} end

HTLAttribute(name) = HTLAttribute{Symbol(s)}()

"""
    htl_stringify_value(value)::String

Convert a `value`` to a string suitable to inclusion as a quoted attribute.
Escaping (according to quoting style) is done after this step. By default,
strings are treated as-is; symbols and numbers (but not booleans) are
automatically converted to strings.
"""
function htl_stringify_value(value)
    if value isa AbstractString
         return value
    end
    if (value isa Symbol || value isa Number) && !(isa(value, Bool))
         return string(value)
    end
    throw(DomainError(value, """
      Unable to convert $(typeof(value)) for use as an attribute value;
      convert to a string or, for a specific attribute, implement a
      `Base.show` method using `HTLAttribute` (and `htl_escape`)
    """))
end

"""
    htl_escape(s)

Perform extensive escaping needed for a string to be used as an
unquoted attribute. This can also be used for quoted values or
within element content (although it's overkill).
"""
htl_escape(value::AbstractString) =
    replace(value, r"[\"\s<>&'`=]" => entity)

struct AttributePair <: InterpolatedValue
    name::String
    values::Vector

    function AttributePair(name::String, values::Vector)
        if length(name) < 1
            throw(DomainError(name, "Attribute name must not be empty."))
        end
        # Attribute names are unquoted and do not have & escaping;
        # the &, % and \ characters are not expressly prevented by the
        # specification, but they likely signal a programming error.
        for invalid in "/>='<&%\\\"\t\n\f\r\x20\x00"
            if invalid in name
                throw(DomainError(name, "Invalid character ('$invalid') " *
                   "found within an attribute name."))
            end
        end
        return new(name, values)
    end
end

AttributePair(name::Symbol, values::Vector) =
    AttributePair(camelcase_to_dashes(string(name)), values)

# handle splat operation e.g. htl"$([1,2,3]...)" by concatenating
ElementData(args...) = HTL([ElementData(item) for item in args])

function Base.show(io::IO, mime::MIME"text/html", child::ElementData)
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
    if value isa Base.Generator
        # support `$(x for x in [...])`
        value = collect(value)
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

function Base.show(io::IO, ::MIME"text/html", x::AttributeDoubleQuoted)
    print(io, replace(htl_stringify_value(x.value), r"[\"&]" => entity))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeSingleQuoted)
    print(io, replace(htl_stringify_value(x.value), r"['&]" => entity))
end

function Base.show(io::IO, mime::MIME"text/html", x::ElementAttributes)
    value = x.value
    if value isa Pair
        show(io, mime, AttributePair(value.first, [value.second]))
    elseif value isa Dict || value isa NamedTuple
        for (k, v) in pairs(value)
            show(io, mime, AttributePair(k, [v]))
        end
    elseif value isa Tuple{Pair, Vararg{Pair}}
        for (k, v) in value
            show(io, mime, AttributePair(k, [v]))
        end
    else
        throw(DomainError(value, """
          Unable to convert $(typeof(value)) to an attribute name/value pair.
          Did you forget the trailing "," in a 1-element named tuple?
        """))
    end
end

function camelcase_to_dashes(str::String)
    # eg :fontSize => "font-size"
    replace(str, r"[A-Z]" => (x -> "-$(lowercase(x))"))
end

css_value(key, value::Symbol) = string(value)
css_value(key, value::Number) = string(value) # includes boolean
css_value(key, value::AbstractString) = value

css_key(key::Symbol) = camelcase_to_dashes(string(key))
css_key(key::String) = key

Base.show(io::IO, at::HTLAttribute{:style}, value::Dict) =
    for pair in pairs(value)
       show(io, at, pair)
    end

Base.show(io::IO, at::HTLAttribute{:style}, value::NamedTuple) =
    for pair in pairs(value)
       show(io, at, pair)
    end

Base.show(io::IO, at::HTLAttribute{:style}, value::Tuple{Pair, Vararg{Pair}}) =
    for item in value
       show(io, at, item)
    end

Base.show(io::IO, at::HTLAttribute{:style}, (key, value)::Pair) =
    print(io, htl_escape("$(css_key(key)): $(css_value(key, value));"))

Base.show(io::IO, at::HTLAttribute{name}, value) where {name} =
    print(io, htl_escape(htl_stringify_value(value)))

function show_iterable(io::IO, at, value, delimiter)
    previous = false
    for item in value
       if previous
           print(io, "&#32;")
       end
       show(io, at, item)
       previous = true
    end
end

Base.show(io::IO, at::HTLAttribute{:class}, value::AbstractVector) =
    show_iterable(io, at, value, " ")

Base.show(io::IO, at::HTLAttribute{:class}, value::Tuple{Any, Vararg{Any}}) =
    show_iterable(io, at, value, " ")

function Base.show(io::IO, mime::MIME"text/html", pair::AttributePair)
    first = pair.values[1]
    if first === nothing || first === false || first === true
        if length(pair.values) > 1
          throw("Too many values for boolean attribute `$(pair.name)`")
        end
        if first == true
            print(io, " $(pair.name)=''")
        end
        return
    end
    print(io, " $(pair.name)=")
    attribute = HTLAttribute{Symbol(lowercase(pair.name))}()
    for value in pair.values
        show(io, attribute, value)
    end
end

function entity(str::AbstractString)
    @assert length(str) == 1
    entity(str[1])
end

entity(ch::Char) = "&#$(Int(ch));"

@enum HtlParserState STATE_DATA STATE_TAG_OPEN STATE_END_TAG_OPEN STATE_TAG_NAME STATE_BEFORE_ATTRIBUTE_NAME STATE_AFTER_ATTRIBUTE_NAME STATE_ATTRIBUTE_NAME STATE_BEFORE_ATTRIBUTE_VALUE STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED STATE_ATTRIBUTE_VALUE_UNQUOTED STATE_AFTER_ATTRIBUTE_VALUE_QUOTED STATE_SELF_CLOSING_START_TAG STATE_COMMENT_START STATE_COMMENT_START_DASH STATE_COMMENT STATE_COMMENT_LESS_THAN_SIGN STATE_COMMENT_LESS_THAN_SIGN_BANG STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH STATE_COMMENT_END_DASH STATE_COMMENT_END STATE_COMMENT_END_BANG STATE_MARKUP_DECLARATION_OPEN STATE_RAWTEXT STATE_RAWTEXT_LESS_THAN_SIGN STATE_RAWTEXT_END_TAG_OPEN STATE_RAWTEXT_END_TAG_NAME

"""
    interpolate(args):Expr

Take an interweaved set of Julia expressions and strings, tokenize the
strings according to the HTML specification [1], wrapping the
expressions with wrappers based upon the escaping context, and returning
an expression that combines the result with an `HTL` wrapper.

For these purposes, a `Symbol` is treated as an expression to be
resolved; while a `String` is treated as a literal string that won't be
escaped. Critically, interpolated strings to be escaped are represented
as an `Expr` with `head` of `:string`.

There are tags, "script" and "style" which are rawtext, in these cases
there is no escaping, and instead raise an exception if the appropriate
ending tag is in substituted content.

[1] https://html.spec.whatwg.org/multipage/parsing.html#tokenization
"""
function interpolate(args)
    state = STATE_DATA
    parts = Union{String, Expr}[]
    attribute_start = attribute_end = 0
    element_start = element_end = 0
    buffer_start = buffer_end = 0
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

    is_alpha(ch) = 'A' <= ch <= 'Z' || 'a' <= ch <= 'z'
    is_space(ch) = ch in ('\t', '\n', '\f', ' ')
    normalize(s) = replace(replace(s, "\r\n" => "\n"), "\r" => "\n")
    nearby(x,i) = i+10>length(x) ? x[i:end] : x[i:i+8] * "…"

    for j in 1:length(args)
        input = args[j]
        if !isa(input, String)
            input = esc(input)
            if state == STATE_DATA
                push!(parts, :(ElementData($input)))
            elseif state == STATE_RAWTEXT
                push!(parts, :(RawText($input, $(QuoteNode(element_tag)))))
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous text string to remove `attname=`
                name = parts[end][attribute_start:attribute_end]
                parts[end] = parts[end][begin:attribute_start - 2]
                push!(parts, :(AttributePair($name, Any[$input])))
            elseif state == STATE_ATTRIBUTE_VALUE_UNQUOTED
                @assert length(parts) > 1 && parts[end] isa Expr
                @assert parts[end].args[1] == :AttributePair
                push!(parts[end].args[3].args, input)
            elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                push!(parts, :(AttributeSingleQuoted($input)))
            elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                push!(parts, :(AttributeDoubleQuoted($input)))
            elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                # this is interpolated element pairs; strip space before
                # and ensure there is a space afterward
                if parts[end] isa String && parts[end][end] == ' '
                     parts[end] = parts[end][begin:length(parts[end])-1]
                end
                push!(parts, :(ElementAttributes($input)))
                if j < length(args)
                    next = args[j+1]
                    if next isa String && !startswith(next, r"[\s+\/>]")
                        args[j+1] = " " * next
                    end
                end
            elseif state == STATE_COMMENT || true
                throw("invalid binding #1 $(state)")
            end
        else
            inputlength = length(input)
            if inputlength < 1
                continue
            end
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
                        state = STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                    elseif ch === '\''
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
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                    if ch === '\''
                        state = STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
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
            push!(parts, input)
        end
    end

    return Expr(:call, :HTL, Expr(:vect, parts...))
end

end
