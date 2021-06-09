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
    parts = Union{String,Expr}[]
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
            if state == STATE_DATA || state == STATE_COMMENT
                push!(parts, :(content($(esc(input)))))
            elseif state == STATE_RAWTEXT
                if :script === element_tag
                    push!(parts, :(Script($(esc(input)))))
                elseif :style === element_tag
                    push!(parts, :(Style($(esc(input)))))
                else
                    throw(DomainError(element_tag,
                      "Only script and style rawtext tags are supported."))
                end
            elseif state == STATE_BEFORE_ATTRIBUTE_VALUE
                state = STATE_ATTRIBUTE_VALUE_UNQUOTED
                # rewrite previous string to remove ` attname=`
                @assert parts[end] isa String
                name = parts[end][attribute_start:attribute_end]
                parts[end] = parts[end][1:(attribute_start-2)]
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
            elseif state == STATE_ATTRIBUTE_VALUE_SINGLE_QUOTED ||
                   state == STATE_ATTRIBUTE_VALUE_DOUBLE_QUOTED
                @assert parts[end] isa String
                name = parts[end][attribute_start:attribute_end]
                if match(r"^on"i, name) !== nothing
                    push!(parts, :(script_attribute_value($(esc(input)))))
                else
                    push!(parts, :(attribute_value($(esc(input)))))
                end
            elseif state == STATE_BEFORE_ATTRIBUTE_NAME ||
                   state == STATE_AFTER_ATTRIBUTE_NAME
                # strip space before interpolated element pairs
                if parts[end] isa String
                    if parts[end][end] == ' '
                       parts[end] = parts[end][1:length(parts[end])-1]
                    end
                end
                # ensure a space between this and next attribute
                if j < length(args)
                    next = args[j+1]
                    if next isa String && !occursin(r"^[\s+\/>]", next)
                        args[j+1] = " " * next
                    end
                end
                append!(parts, rewrite_inside_tag(input))
            else
                throw("unexpected binding $(state)")
            end
        else
            input = normalize(input)
            inputlength = lastindex(input)
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
                        i = prevind(input, i)
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
                        i = prevind(input, i)
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
                        i = prevind(input, i)
                    elseif ch in  '='
                        throw(DomainError(nearby(input, i-1),
                          "unexpected equals sign before attribute name"))
                    else
                        state = STATE_ATTRIBUTE_NAME
                        attribute_start = i
                        attribute_end = nothing
                        i = prevind(input, i)
                    end

                elseif state == STATE_ATTRIBUTE_NAME
                    if is_space(ch) || ch === '/' || ch === '>'
                        state = STATE_AFTER_ATTRIBUTE_NAME
                        i = prevind(input, i)
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
                        i = prevind(input, i)
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
                        i = prevind(input, i)
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
                        i = nextind(input, i)
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
                        i = prevind(input, i)
                    end

                elseif state == STATE_COMMENT_START_DASH
                    if ch === '-'
                        state = STATE_COMMENT_END
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "abrupt closing of empty comment"))
                    else
                        state = STATE_COMMENT
                        i = prevind(input, i)
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
                        i = prevind(input, i)
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG
                    if ch == '-'
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    else
                        state = STATE_COMMENT
                        i = prevind(input, i)
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH
                    if ch == '-'
                        state = STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    else
                        state = STATE_COMMENT_END
                        i = prevind(input, i)
                    end

                elseif state == STATE_COMMENT_LESS_THAN_SIGN_BANG_DASH_DASH
                    if ch == '>'
                        state = STATE_COMMENT_END
                        i = prevind(input, i)
                    else
                        throw(DomainError(nearby(input, i-1),
                          "nested comment"))
                    end

                elseif state == STATE_COMMENT_END_DASH
                    if ch === '-'
                        state = STATE_COMMENT_END
                    else
                        state = STATE_COMMENT
                        i = prevind(input, i)
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
                        i = prevind(input, i)
                    end

                elseif state == STATE_COMMENT_END_BANG
                    if ch === '-'
                        state = STATE_COMMENT_END_DASH
                    elseif ch === '>'
                        throw(DomainError(nearby(input, i-1),
                          "nested comment"))
                    else
                        state = STATE_COMMENT
                        i = prevind(input, i)
                    end

                elseif state == STATE_RAWTEXT_LESS_THAN_SIGN
                    if ch === '/'
                        state = STATE_RAWTEXT_END_TAG_OPEN
                    elseif ch === '!' && element_tag == :script
                        # RAWTEXT differs from SCRIPT here
                        throw("script escape or comment is not implemented")
                    else
                        state = STATE_RAWTEXT
                        # do not "reconsume", even though spec says so
                    end

                elseif state == STATE_RAWTEXT_END_TAG_OPEN
                    if is_alpha(ch)
                        state = STATE_RAWTEXT_END_TAG_NAME
                        buffer_start = i
                        i = prevind(input, i)
                    else
                        state = STATE_RAWTEXT
                        i = prevind(input, i)
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
                    throw("unhandled state transition")
                end

                i = nextind(input, i)
            end
            push!(parts, input)
        end
    end
    parts = Expr[(x isa String ? :(Bypass($x)) : x) for x in parts]
    return Expr(:call, :Result, QuoteNode(this), parts...)
end
