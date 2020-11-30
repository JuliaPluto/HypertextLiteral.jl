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
contents of the vector are concatinated. Second, direct rendering is
limited to `AbstractString`, others are delegated to `show`. Third, the
splat constructor converts arguments to the `HTL` vector.

Finally, regular display of the value to the terminal renders the
objects and produces the equivalent string representation (unwise?).
"""
mutable struct HTL
    content::Vector
end

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
        return hypertext([expr])
    end
    # Find cases where we may have an interpolated string literal and
    # raise an exception (till Julia issue #38501 is addressed)
    @assert expr isa Expr
    @assert expr.head == :string
    if length(expr.args) == 1 && expr.args[1] isa String
        throw("interpolated string literals are not supported")
    end
    for idx in 2:length(expr.args)
        if expr.args[idx] isa String && expr.args[idx-1] isa String
            throw("interpolated string literals are not supported")
        end
    end
    return hypertext([ex isa String ? ex : esc(ex) for ex in expr.args])
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
    return hypertext([ex isa String ? ex : esc(ex) for ex in args])
end

abstract type InterpolatedValue end

struct AttributeValue <: InterpolatedValue
    name::String
    value
end

struct Javascript
    content
end

Base.show(io::IO, mime::MIME"application/javascript", js::Javascript) =
    print(io, js.content)

struct ElementContent <: InterpolatedValue value end
struct AttributeUnquoted <: InterpolatedValue value end
struct AttributeDoubleQuoted <: InterpolatedValue value end
struct AttributeSingleQuoted <: InterpolatedValue value end
struct BeforeAttributeName <: InterpolatedValue value end

ElementContent(args...) = HTL([ElementContent(item) for item in args])

function Base.show(io::IO, mime::MIME"text/html", x::BeforeAttributeName)
    if x.value isa Dict
        for (key, value) in pairs(x.value)
            show(io, mime, AttributeValue(name=key, value=value))
            print(io, " ")
        end
    elseif x.value isa Pair
        show(io, mime, AttributeValue(name=x.value.first, value=x.value.second))
        print(io, " ")
    else
        throw("invalid binding #2 $(typeof(x.value)) $(x.value)")
    end
end

function entity(str::AbstractString)
    @assert length(str) == 1
    entity(str[1])
end

entity(ch::Char) = begin
    if ch == '&'
        "&amp;"
    elseif ch == '<'
        "&lt;"
    elseif ch == '>'
        "&gt;"
    elseif ch == '"'
        "&quot;"
    elseif ch == '\''
        "&apos;"
    else
        "&#$(Int(ch));"
    end
end

function Base.show(io::IO, mime::MIME"text/html", child::ElementContent)
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

function render_attribute(v)
    if v isa AbstractString
         return v
    end
    if v isa Symbol || v isa Number
         return string(v)
    end
    throw(DomainError(v, """
      Unable to convert $(typeof(v)) to an attribute, either
      expressly cast as a string, or provide an `render_attribute`
    """))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeUnquoted)
    print(io, replace(render_attribute(x.value), r"[\s>&]" => entity))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeDoubleQuoted)
    print(io, replace(render_attribute(x.value), r"[\"&]" => entity))
end

function Base.show(io::IO, ::MIME"text/html", x::AttributeSingleQuoted)
    print(io, replace(render_attribute(x.value), r"['&]" => entity))
end

function isObjectLiteral(value)
    typeof(value) == Dict
end

function camelcase_to_dashes(str::String)
    # eg :fontSize => "font-size"
    replace(str, r"[A-Z]" => (x -> "-$(lowercase(x))"))
end

css_value(key, value) = string(value)
css_value(key, value::Real) = "$(value)px"
css_value(key, value::AbstractString) = value

css_key(key::Symbol) = camelcase_to_dashes(string(key))
css_key(key::String) = key

function render_inline_css(styles::Dict)
    result = ""
    for (key, value) in pairs(styles)
        result *= render_inline_css(key => value)
    end
    result
end

function render_inline_css(style::Tuple{Pair})
    result = ""
    for (key, value) in styles
        result *= render_inline_css(key => value)
    end
    result
end

function render_inline_css((key, value)::Pair)
    "$(css_key(key)): $(css_value(key, value));"
end

function Base.show(io::IO, mime::MIME"text/html", attribute::AttributeValue)
    value = attribute.value
    if value === nothing || value === false
        return
    end
    print(io, " $(attribute.name)=")
    if value === true
        print(io, "''")
        return
    end
    if attribute.name == "style" &&
       hasmethod(render_inline_css, Tuple{typeof(value)})
        value = render_inline_css(value)
    else
        value = render_attribute(value)
    end
    print(io, replace(value, r"^['\"]|[\s>&]" => entity))
end

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


function hypertext(args)
    state = STATE_DATA
    parts = Union{String, Expr}[]
    nameStart = 0
    nameEnd = 0

    for j in 1:length(args)
        input = args[j]
        if input isa Expr
            if state == STATE_DATA
                push!(parts, :(ElementContent($input)))
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous text string to remove `attname=`
                name = parts[end][nameStart:nameEnd]
                parts[end] = parts[end][begin:nameStart - 2]
                push!(parts, :(AttributeValue($name, $input)))
            elseif state == STATE_ATTRIBUTE_VALUE_UNQUOTED
                push!(parts, :(AttributeUnquoted($input)))
            elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED
                push!(parts, :(AttributeSingleQuoted($input)))
            elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                push!(parts, :(AttributeDoubleQuoted($input)))
            elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                push!(parts, :(BeforeAttributeName($input)))
            elseif state == STATE_COMMENT || true
                throw("invalid binding #1 $(state)")
            end
        else
            @assert input isa String
            inputlength = length(input)
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

end
