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
mutable struct HTL
    content::Vector
end

HTL() = HTL([])
HTL(xs...) = HTL(xs)
HTL(s::AbstractString) = HTL([s])

function Base.show(io::IO, mime::MIME"text/html", h::HTL)
    for item in h.content
        if item isa AbstractString
            print(io, item)
        else
            Base.show(io, mime, item)
        end
    end
end

Base.show(io::IO, h::HTL) =
    print(io, "HTL(\"$(escape_string(sprint() do io
                  Base.show(io, MIME("text/html"), h) end))\")")

"""
    @htl string-expression

Create a `HTL` object with string interpolation (`\$`) that uses
context-sensitive hypertext escaping. Rather than escaping interpolated
string literals, e.g. `\$("Strunk & White")`, they are treated as errors
since they cannot be reliably detected (see Julia issue #38501).
"""
macro htl(expr)
    if expr isa String
        return interpolate([expr])
    end
    @assert expr isa Expr
    if expr.head != :string
       # TODO: what is going on in this case...
       @assert false
       return interpolate([expr])
    end
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
struct AttributePair <: InterpolatedValue
    name::String
    values::Vector
end

AttributePair(name::Symbol, values::Vector) = 
    AttributePair(camelcase_to_dashes(string(name)), values)

# handle splat operation e.g. htl"$([1,2,3]...)" by concatenating
ElementData(args...) = HTL([ElementData(item) for item in args])

function Base.show(io::IO, mime::MIME"text/html", child::ElementData)
    if showable(MIME("text/html"), child.value)
        show(io, mime, child.value)
    elseif child.value isa AbstractArray{<:HTL}
        for subchild in child.value
            show(io, mime, subchild)
        end
    elseif child.value isa AbstractString
        print(io, replace(child.value, r"[<&]" => entity))
    elseif child.value isa Number || child.value isa Symbol
        print(io, replace(string(child.value), r"[<&]" => entity))
    elseif child.value isa AbstractVector
        throw(DomainError(child.value, """
          Type $(typeof(child.value)) lacks a show method for text/html.
          Perhaps use splatting? e.g. htl"\$([x for x in 1:3]...)
        """))
    else
        throw(DomainError(child.value, """
          Type $(typeof(child.value)) lacks a show method for text/html.
          Alternatively, you can cast the value to a string first.
        """))
    end
end

"""
    htl_render_attribute(v)

Convert a value `v` to a string suitable for inclusion into an attribute
value. Note that escaping is done separately. By default, symbols and
numbers (but not booleans) are automatically converted to strings.
Provide a method implementation of this for custom datatypes.
"""
function htl_render_attribute(v)
    if v isa AbstractString
         return v
    end
    if (v isa Symbol || v isa Number) && !(isa(v, Bool))
         return string(v)
    end
    throw(DomainError(v, """
      Unable to convert $(typeof(v)) to an attribute; either expressly
      convert to a string, or provide an `htl_render_attribute` method
    """))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeDoubleQuoted)
    print(io, replace(htl_render_attribute(x.value), r"[\"&]" => entity))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeSingleQuoted)
    print(io, replace(htl_render_attribute(x.value), r"['&]" => entity))
end

function Base.show(io::IO, mime::MIME"text/html", x::ElementAttributes)
    if x.value isa Dict
        for (key, value) in pairs(x.value)
            show(io, mime, AttributePair(key, [value]))
        end
    elseif x.value isa Pair
        show(io, mime, AttributePair(x.value.first, [x.value.second]))
    elseif x.value isa Tuple{Pair, Vararg{Pair}}
        for (key, value) in x.value
            show(io, mime, AttributePair(key, [value]))
        end
    else
        throw("invalid binding #2 $(typeof(x.value)) $(x.value)")
    end
end

function camelcase_to_dashes(str::String)
    # eg :fontSize => "font-size"
    replace(str, r"[A-Z]" => (x -> "-$(lowercase(x))"))
end

css_value(key, value::Symbol) = string(value)
css_value(key, value::Number) = string(value) # numeric and boolean
css_value(key, value::AbstractString) = value

css_key(key::Symbol) = camelcase_to_dashes(string(key))
css_key(key::String) = key

render_inline_css(styles::Dict) =
    join([render_inline_css(pair) for pair in pairs(styles)])

render_inline_css(styles::Tuple{Pair, Vararg{Pair}}) =
    join([render_inline_css(pair) for pair in styles])

render_inline_css((key, value)::Pair) =
    "$(css_key(key)): $(css_value(key, value));"

function Base.show(io::IO, mime::MIME"text/html", attribute::AttributePair)
    first = attribute.values[1]
    if first === nothing || first === false || first === true
        if length(attribute.values) > 1
          throw("Too many values for boolean attribute `$(attribute.name)`")
        end
        if first == true
            print(io, " $(attribute.name)=''")
        end
        return
    end
    print(io, " $(attribute.name)=")
    for value in attribute.values
        if attribute.name == "style" &&
           hasmethod(render_inline_css, Tuple{typeof(value)})
            value = render_inline_css(value)
        else
            value = htl_render_attribute(value)
        end
        print(io, replace(value, r"[\"\s<>&'`=]" => entity))
    end
end

function entity(str::AbstractString)
    @assert length(str) == 1
    entity(str[1])
end

entity(ch::Char) = "&#$(Int(ch));"

@enum HtlParserState STATE_DATA STATE_TAG_OPEN STATE_END_TAG_OPEN STATE_TAG_NAME STATE_BOGUS_COMMENT STATE_BEFORE_ATTRIBUTE_NAME STATE_AFTER_ATTRIBUTE_NAME STATE_ATTRIBUTE_NAME STATE_BEFORE_ATTRIBUTE_VALUE STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED STATE_ATTRIBUTE_VALUE_UNQUOTED STATE_AFTER_ATTRIBUTE_VALUE_QUOTED STATE_SELF_CLOSING_START_TAG STATE_COMMENT_START STATE_COMMENT_START_DASH STATE_COMMENT STATE_COMMENT_LESS_THAN_SIGN STATE_COMMENT_LESS_THAN_SIGN_BANG STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH STATE_COMMENT_END_DASH STATE_COMMENT_END STATE_COMMENT_END_BANG STATE_MARKUP_DECLARATION_OPEN

begin
    const CODE_TAB = 9
    const CODE_LF = 10
    const CODE_FF = 12
    const CODE_CR = 13
    const CODE_SPACE = 32
    const CODE_UPPER_A = 65
    const CODE_UPPER_Z = 90
    const CODE_LOWER_A = 97
    const CODE_LOWER_Z = 122
    const CODE_LT = 60
    const CODE_GT = 62
    const CODE_SLASH = 47
    const CODE_DASH = 45
    const CODE_BANG = 33
    const CODE_EQ = 61
    const CODE_DQUOTE = 34
    const CODE_SQUOTE = 39
    const CODE_QUESTION = 63
end

function isAsciiAlphaCode(code::Int)::Bool
  return (
        CODE_UPPER_A <= code
        && code <= CODE_UPPER_Z
    ) || (
        CODE_LOWER_A <= code
        && code <= CODE_LOWER_Z
    )
end

function isSpaceCode(code)
  return ( code === CODE_TAB
        || code === CODE_LF
        || code === CODE_FF
        || code === CODE_SPACE
        || code === CODE_CR
    ) # normalize newlines
end

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

[1] https://html.spec.whatwg.org/multipage/parsing.html#tokenization
"""
function interpolate(args)
    state = STATE_DATA
    parts = Union{String, Expr}[]
    nameStart = 0
    nameEnd = 0

    for j in 1:length(args)
        input = args[j]
        if !isa(input, String)
            input = esc(input)
            if state == STATE_DATA
                push!(parts, :(ElementData($input)))
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous text string to remove `attname=`
                name = parts[end][nameStart:nameEnd]
                parts[end] = parts[end][begin:nameStart - 2]
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
            i = 1
            while i <= inputlength
                code = Int(input[i])

                if state == STATE_DATA
                    if code === CODE_LT
                        state = STATE_TAG_OPEN
                    end

                elseif state == STATE_TAG_OPEN
                    if code === CODE_BANG
                        state = STATE_MARKUP_DECLARATION_OPEN
                    elseif code === CODE_SLASH
                        state = STATE_END_TAG_OPEN
                    elseif isAsciiAlphaCode(code)
                        state = STATE_TAG_NAME
                        i -= 1
                    elseif code === CODE_QUESTION
                        state = STATE_BOGUS_COMMENT
                        i -= 1
                    else
                        state = STATE_DATA
                        i -= 1
                    end

                elseif state == STATE_END_TAG_OPEN
                    if isAsciiAlphaCode(code)
                        state = STATE_TAG_NAME
                        i -= 1
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_BOGUS_COMMENT
                        i -= 1
                    end

                elseif state == STATE_TAG_NAME
                    if isSpaceCode(code)
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                    elseif code === CODE_SLASH
                        state = STATE_SELF_CLOSING_START_TAG
                    elseif code === CODE_GT
                        state = STATE_DATA
                    end

                elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                    if isSpaceCode(code)
                        nothing
                    elseif code === CODE_SLASH || code === CODE_GT
                        state = STATE_AFTER_ATTRIBUTE_NAME
                        i -= 1
                    elseif code === CODE_EQ
                        state = STATE_ATTRIBUTE_NAME
                        nameStart = i + 1
                        nameEnd = nothing
                    else
                        state = STATE_ATTRIBUTE_NAME
                        i -= 1
                        nameStart = i + 1
                        nameEnd = nothing
                    end

                elseif state == STATE_ATTRIBUTE_NAME
                    if isSpaceCode(code) || code === CODE_SLASH || code === CODE_GT
                        state = STATE_AFTER_ATTRIBUTE_NAME
                        nameEnd = i - 1
                        i -= 1
                    elseif code === CODE_EQ
                        state = STATE_BEFORE_ATTRIBUTE_VALUE
                        nameEnd = i - 1
                    end

                elseif state == STATE_AFTER_ATTRIBUTE_NAME
                    if isSpaceCode(code)
                        # ignore
                    elseif code === CODE_SLASH
                        state = STATE_SELF_CLOSING_START_TAG
                    elseif code === CODE_EQ
                        state = STATE_BEFORE_ATTRIBUTE_VALUE
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_ATTRIBUTE_NAME
                        i -= 1
                        nameStart = i + 1
                        nameEnd = nothing
                    end

                elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                    if isSpaceCode(code)
                        # continue
                    elseif code === CODE_DQUOTE
                        state = STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                    elseif code === CODE_SQUOTE
                        state = STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                        i -= 1
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                    if code === CODE_DQUOTE
                        state = STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                    if code === CODE_SQUOTE
                        state = STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                    end

                elseif state == STATE_ATTRIBUTE_VALUE_UNQUOTED
                    if isSpaceCode(code)
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                    elseif code === CODE_GT
                        state = STATE_DATA
                    end

                elseif state == STATE_AFTER_ATTRIBUTE_VALUE_QUOTED
                    if isSpaceCode(code)
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                    elseif code === CODE_SLASH
                        state = STATE_SELF_CLOSING_START_TAG
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                        i -= 1
                    end

                elseif state == STATE_SELF_CLOSING_START_TAG
                    if code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_BEFORE_ATTRIBUTE_NAME
                        i -= 1
                    end

                elseif state == STATE_BOGUS_COMMENT
                    if code === CODE_GT
                        state = STATE_DATA
                    end

                elseif state == STATE_COMMENT_START
                    if code === CODE_DASH
                        state = STATE_COMMENT_START_DASH
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_START_DASH
                    if code === CODE_DASH
                        state = STATE_COMMENT_END
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT
                    if code === CODE_LT
                        state = STATE_COMMENT_LESS_THAN_SIGN
                    elseif code === CODE_DASH
                        state = STATE_COMMENT_END_DASH
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN
                    if code === CODE_BANG
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG
                    elseif code !== CODE_LT
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG
                    if code === CODE_DASH
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    if code === CODE_DASH
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    else
                        state = STATE_COMMENT_END
                        i -= 1
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    state = STATE_COMMENT_END
                        i -= 1

                elseif state == STATE_COMMENT_END_DASH
                    if code === CODE_DASH
                        state = STATE_COMMENT_END
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_END
                    if code === CODE_GT
                        state = STATE_DATA
                    elseif code === CODE_BANG
                        state = STATE_COMMENT_END_BANG
                    elseif code !== CODE_DASH
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_COMMENT_END_BANG
                    if code === CODE_DASH
                        state = STATE_COMMENT_END_DASH
                    elseif code === CODE_GT
                        state = STATE_DATA
                    else
                        state = STATE_COMMENT
                        i -= 1
                    end

                elseif state == STATE_MARKUP_DECLARATION_OPEN
                    if code === CODE_DASH && Int(input[i + 1]) == CODE_DASH
                        state = STATE_COMMENT_START
                        i += 1
                    else # Note: CDATA and DOCTYPE unsupported!
                        state = STATE_BOGUS_COMMENT
                        i -= 1
                    end
                else
                    state = nothing
                end

                i = i + 1
            end
            push!(parts, input)
        end
    end

    return Expr(:call, :HTL, Expr(:vect, parts...))
end

# TODO: is this even a good idea? you often want to `join` HTL...
#join(strings) = sprint(join, strings)
#join(strings, delim) = sprint(join, strings, delim)
#join(strings, delim, last) = sprint(join, strings, delim, last)
function Base.join(strings::Vector{HTL})::HTL
     retval = HTL()
     for part in strings
         append!(retval.content, part.content)
     end
     return retval
end

end
