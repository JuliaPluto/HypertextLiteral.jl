"""
    Script(data) - print `data` unescaped within a `<script>` tag
"""
struct Script
    content
end

Base.print(ep::EscapeProxy, x::Script) =
    print_script_lower(ep.io, x.content)

"""
    print_script_lower(io, value)

Provides a hook to override `print_script` for custom Javascript
runtimes, such as `Pluto.jl`, to provide their own value marshalling.
"""
print_script_lower(io::IO, value) =
   print_script(io, value)


INVALID_SCRIPT_CONTENT = r"(<!--)|(<script>)|(</script)"i

"""
    JavaScript(js) - shows `js` as `"text/javascript"`
"""
struct JavaScript
    content

    JavaScript(s::AbstractString) =
        if nothing == match(INVALID_SCRIPT_CONTENT, s)
            new(s)
        else
            throw("JavaScript content is not propertly escaped")
        end

     JavaScript(content) = new(content)
end

Base.show(io::IO, ::MIME"text/javascript", js::JavaScript) =
    print(io, js.content)

"""
    print_script(io, value)

Show `value` as `"text/javascript"` to the given `io`, this provides
some baseline functionality for built-in data types.

    - `nothing` becomes `undefined`
    - `missing` becomes `null`
    - `Bool` values are printed as `true` or `false`
    - `AbstractString` and `Symbol` become a double-quoted string
    - `AbstractVector` and `Tuple` become an array
    - `Dict` and `NamedTuple` become a Javascript object, with
       keys converted to string values
    - `AbstractFloat` and `Integer` are printed directly, where
      `NaN` remains `NaN` but `Inf` is printed as `Infinity`

The fallback behavior of `print_script` is to show the object as
`"text/javascript"`.
"""
print_script(io::IO, value) =
    show(io, MIME"text/javascript"(), value)
print_script(io::IO, ::Nothing) =
    print(io, "undefined")
print_script(io::IO, ::Missing) =
    print(io, "null")
print_script(io::IO, value::Bool) =
    print(io, value)
print_script(io::IO, value::Symbol) =
    print_script(io, string(value))

function print_script(io::IO, value::Union{NamedTuple, AbstractDict})
    print(io, '{')
    first = true
    for (k,v) in pairs(value)
        if !first
            print(io, ", ")
        end
        print_script(io, string(k))
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
