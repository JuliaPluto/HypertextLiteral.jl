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

include("utils.jl")

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
    # it by `$` to find interpolated parts and delegating the hard work
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
    normalize_attribute_name(name)::String

For `String` names, this simply verifies that they pass the attribute
name production, but are otherwise untouched.

For `Symbol` names, this converts `snake_case` Symbol objects to their
`kebab-case` equivalent. So that keywords, such as `for` could be used,
we strip leading underscores.
"""
function normalize_attribute_name(name::Symbol)
    name = String(name)
    if '_' in name
       if name[1] == '_'
           name = name[2:end]
       end
       name = replace(name, "_" => "-")
    end
    return normalize_attribute_name(name)
end

function normalize_attribute_name(name::String)
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
    stringify(value)

Convert an attribute `value`` to a `String`. The value returned will
then be escaped depending upon the particular context.

* `String` values are returned as-is
* `Number` and `Symbol` values are converted to a `String`

There is no general fallback, hence, a `MethodError` will result when
attempting to stringify most data types. If your application would like
to stringify all attribute values, you could register this fallback.

    HypertextLiteral.stringify(value) = string(value)

"""
stringify(value::AbstractString) = value
stringify(value::Number) = string(value)
stringify(value::Symbol) = string(value)

# Behaviors helpful to CSS `style` and `class`, applied generally.

nested_value(value::Symbol) = string(value)
nested_value(value::Number) = string(value)
nested_value(value::AbstractString) = value

nested_key(key::Symbol) = normalize_attribute_name(key)
nested_key(key::String) = normalize_attribute_name(key)

stringify(value::Dict) =
    join((stringify(pair) for pair in pairs(value)), " ")

stringify(value::NamedTuple) =
    join((stringify(pair) for pair in pairs(value)), " ")

stringify(value::Tuple{Pair, Vararg{Pair}}) =
    join((stringify(pair) for pair in value), " ")

stringify((key, value)::Pair) =
    "$(nested_key(key)): $(nested_value(value));"

stringify(value::AbstractVector) =
    join((stringify(item) for item in value), " ")

stringify(value::Tuple{Any, Vararg{Any}}) =
    join((stringify(item) for item in value), " ")

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
    return HTML(value)
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
function attribute_pair(name, value)
    value = escape_single_quote(stringify(value))
    return HTML(" $name='$value'")
end

function attribute_pair(name, value::Bool)
    if value == false
        return HTML("")
    end
    return HTML(" $name=''")
end

function attribute_pair(name, value::Nothing)
    return HTML("")
end

"""
    single_quoted(value)

Wrap and escape a single-quoted attribute value so that it is
`showable("text/html")`. This uses `stringify` to do the actual
conversion of the attribute to a usable string value.
"""
single_quoted(value) =
    HTML(escape_single_quote(stringify(value)))

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
    double_quoted(value)

Wrap and escape a double-quoted attribute value so that it is
`showable("text/html")`. This uses `stringify` to do the actual
conversion of the attribute to a usable string value.
"""
double_quoted(value) =
    HTML(escape_double_quote(stringify(value)))

function escape_double_quote(value)
    if '&' in value
        value = replace(value, "&" => "&amp;")
    end
    if '"' in value
        value = replace(value, "\"" => "&quot;")
    end
    return value
end

const g_inner = IOBuffer()
function wrap_content(obj)
    outer -> begin
        @assert g_inner.ptr == 1 && g_inner.size == 0
        print(g_inner, obj)
        next = last = 1
        pref = pointer(g_inner.data) - 1
        data = g_inner.data
        size = g_inner.size
        while next <= size
            @inbounds ch = data[next]
            if ch == Int('<')
                unsafe_write(outer, pref + last, next - last)
                print(outer, "&lt;")
                last = next + 1
            elseif ch ==  Int('&')
                unsafe_write(outer, pref + last, next - last)
                print(outer, "&amp;")
                last = next + 1
            end
            next += 1
        end
        if last <= size
            unsafe_write(outer, pref + last, size - last + 1)
        end
        truncate(g_inner, 0)
    end
end

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

Wrap content so that it is `showable("text/html")`. By default, string
values are escaped with `escape_content`. For performance reasons, we
reproduce `Number` and `Symbol` objects without escaping them. Tuples,
arrays and generators are represented by concatenating their elements.
As a fallback, we assume the value has implemented `show()` for
`MIME"text/html"`, if not, a `MethodError` will result.
"""
content(x) = x
content(x::AbstractString) = HTML(escape_content(x))
#content(x::AbstractString) = HTML{Function}(wrap_content(x))
content(x::Number) = HTML(x)
content(x::Symbol) = HTML(x)
content(x::Nothing) = HTML("")
content(xs...) = content(xs)

function content(xs::Union{Tuple, AbstractArray, Base.Generator})
    HTML{Function}() do io
      for x in xs
        show(io, MIME"text/html"(), content(x))
      end
    end
end

"""
    attributes(value)

Convert Julian object into a serialization of attribute pairs,
`showable` via `MIME"text/html"`. The default implementation of this
delegates value construction of each pair to `attribute_pair()`.
"""
attributes(value::Pair) =
    attribute_pair(normalize_attribute_name(value.first), value.second)
attributes(values::Dict) =
    attribute_pairs(pairs(values))
attributes(values::NamedTuple) =
    attribute_pairs(pairs(values))
attributes(values::Tuple{Pair, Vararg{Pair}}) =
    attribute_pairs((item for item in values))
attribute_pairs(pairs) =
    HTML() do io
        for (name, value) in pairs
            show(io, MIME"text/html"(),
               attribute_pair(normalize_attribute_name(name), value))
        end
    end

"""
    interpolate_attributes(element, expr)::Vector{Expr}

Continue conversion of an arbitrary Julia expression within the
attribute section of the given element.
"""
function interpolate_attributes(expr)::Vector{Expr}
    return [:(attributes($(esc(expr))))]
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
                element = QuoteNode(element_tag)
                push!(parts, :(rawtext($element, $(esc(input)))))
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous HTML string to remove ` attname=`
                @assert Meta.isexpr(parts[end], :call, 2)
                previous = parts[end].args
                @assert previous[1] == :HTML
                name = previous[2][attribute_start:attribute_end]
                previous[2] = previous[2][1:(attribute_start-2)]
                attribute = normalize_attribute_name(name)
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
                push!(parts, :(single_quoted($(esc(input)))))
            elseif state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                push!(parts, :(double_quoted($(esc(input)))))
            elseif state == STATE_BEFORE_ATTRIBUTE_NAME
                # strip space before interpolated element pairs
                @assert Meta.isexpr(parts[end], :call, 2)
                previous = parts[end].args
                if previous[1] == :HTML && previous[2] isa String
                    if previous[2][end] == ' '
                        finish = length(previous[2])-1
                        previous[2] = previous[2][1:finish]
                    end
                end
                # move the space to after the element pairs
                if j < length(args)
                    next = args[j+1]
                    if next isa String && !occursin(r"^[\s+\/>]", next)
                        args[j+1] = " " * next
                    end
                end
                append!(parts, interpolate_attributes(input))
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
    return Expr(:call, :Result, QuoteNode(this),
              Expr(:call, :UnwrapHTML, parts...))
end

"""
    Result(expr, unwrap)

Address display modalities by showing the macro expression that
generated the results when shown on the REPL. However, when used with
`print()` show the results. This object is also showable to any IO
stream via `"text/html"`.
"""
struct Result
    expr::Expr
    content::UnwrapHTML
end

Base.show(io::IO, m::MIME"text/html", h::Result) = show(io, m, h.content)
Base.print(io::IO, h::Result) = print(io, h.content)
Base.show(io::IO, h::Result) = print(io, h.expr)

end
