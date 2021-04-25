"""
    Script(data) - object printed as text/javascript
"""
struct Script{T}
    content::T
end

Base.print(ep::EscapeProxy, x::Script) =
    print_script(ep.io, x.content)

"""
    script(value)

Convert a Julia value into something suitable for use within a
`<script>` tag. By default, this will attempt to render the object
as `"text/javascript"`. See also `print_script`.
"""
script(value) = Script(value)
script(value::AbstractSet) = Script(collect(value))

"""
    print_script(io, value)

Render `value` as `"text/javascript"` to the given `io`.

    - `nothing` becomes `undefined`
    - `missing` becomes `null`
    - `Symbol` becomes an unquoted name; no escaping
    - `AbstractString` becomes a double-quoted string
    - `Bool` values are printed directly, as `true` or `false`

Numbers are simply printed, with a special case for Javascript's
`Infinity` object; note that `NaN` is handled transparently.
"""
print_script(io::IO, ::Nothing) =
    print(io, "undefined")
print_script(io::IO, ::Missing) =
    print(io, "null")
print_script(io::IO, value::Union{Bool, Symbol}) =
    print(io, value)

function print_script(io::IO, value::Union{Integer, AbstractFloat})
    if isfinite(value) || isnan(value)
        print(io, value)
    else
        if value < 0
            print(io, "-")
        end
        print(io, "Infinity")
    end
end

function print_script(io::IO, value::AbstractString)
    final = lastindex(value)
    i = last = 1
    function emit(s::String)
        if i > last
            print(io, SubString(value, last, i - 1))
            last = nextind(value, i)
        end
        print(io, s)
    end
    print(io, "\"")
    while i <= final
        ch = value[i]
        if ch === '\n'
            emit("\\n")
        elseif ch === '\r'
            emit("\\r")
        elseif ch === '\\'
            emit("\\\\")
        elseif ch === '\"'
            emit("\\\"")
        elseif ch === '\u2028'
            emit("\\u2028")
        elseif ch === '\u2029'
            emit("\\u2029")
        elseif ch === '<' && i+1 <= final
            # escape nested script and comment tags
            nc = value[i+1]
            if nc in ('s', 'S', '!', '/')
                emit("<\\")
            end
        end
        i = nextind(value, i)
    end
    print(io, SubString(value, last, final))
    print(io, "\"")
end
