"""
    Script(data) - object printed as text/javascript
"""
struct Script
    content
end

Base.print(ep::EscapeProxy, x::Script) =
    print_script(ep.io, x.content)

"""
    print_script(io, value)

Show `value` as `"text/javascript"` to the given `io`, this provides
some baseline functionality for built-in data types.

    - `nothing` becomes `undefined`
    - `missing` becomes `null`
    - `Symbol` becomes an unquoted name; no escaping
    - `Bool` values are printed directly, as `true` or `false`
    - `AbstractString` becomes a double-quoted string
    - `AbstractVector` and `Tuple` become an array
    - `Dict` and `NamedTuple` become a Javascript object.

Numbers are simply printed, with a special case for Javascript's
`Infinity` object; note that `NaN` is handled transparently.
"""
print_script(io::IO, value) =
    show(io, MIME"text/javascript"(), value)
print_script(io::IO, ::Nothing) =
    print(io, "undefined")
print_script(io::IO, ::Missing) =
    print(io, "null")
print_script(io::IO, value::Union{Bool, Symbol}) =
    print(io, value)

function print_script(io::IO, value::Union{NamedTuple, AbstractDict})
    print(io, '{')
    first = true
    for (k,v) in pairs(value)
        if !first
            print(io, ", ")
        end
        print_script(io, k)
        print(io, ": ")
        print_script(io, v)
        first = false
    end
    print(io, '}')
end

function print_script(io::IO, value::Union{Tuple, AbstractVector})
    print(io, '[')
    first = true
    for item in value
        if !first
            print(io, ", ")
        end
        print_script(io, item)
        first = false
    end
    print(io, ']')
end

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
        print(io, SubString(value, last, i - 1))
        last = nextind(value, i)
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
