"""
    ScriptProxy(io)

This is a transparent proxy that ensures neither `<!--` nor `</script>`
occur in the output stream.

# Examples
```julia-repl
julia> gp = ScriptProxy(stdout);
julia> print(gp, "valid");
valid
julia> print(gp, "</script>")
<tag/>
```
"""
mutable struct ScriptProxy{T<:IO} <: IO where {T}
    io::T
    index::Int

    ScriptProxy(io::T) where T = new{T}(io::T, 0)
end


"""
    Script(data)

This object prints `data` unescaped within a `<script>` tag, wrapped in
a `ScriptProxy` that guards against invalid script content.
"""
struct Script
    content
end

Base.print(ep::EscapeProxy, x::Script) =
    print_script_lower(ScriptProxy(ep.io), x.content)

"""
    print_script_lower(io, value)

Provides a hook to override `print_script` for custom Javascript
runtimes, such as `Pluto.jl`, to provide their own value marshalling.
"""
print_script_lower(io::IO, value) =
   print_script(io, value)


"""
    JavaScript(js) - shows `js` as `"text/javascript"`
"""
struct JavaScript
    content
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
`"text/javascript"`. The `Javascript` wrapper will take any string
and let it be printed in this way.
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

function Base.write(sp::ScriptProxy, octet::UInt8)
    if 0 == sp.index
        if octet == Int('<')
            sp.index = 1
        end
        write(sp.io, octet)
        return
    end
    if 1 == sp.index
        sp.index = octet == Int('!') ? 12 :
                   octet == Int('/') ? 2 : 0
    elseif 2 == sp.index
        sp.index = (octet == Int('S') || octet == Int('s')) ? 3 : 0
    elseif 3 == sp.index
        sp.index = (octet == Int('C') || octet == Int('c')) ? 4 : 0
    elseif 4 == sp.index
        sp.index = (octet == Int('R') || octet == Int('r')) ? 5 : 0
    elseif 5 == sp.index
        sp.index = (octet == Int('I') || octet == Int('i')) ? 6 : 0
    elseif 6 == sp.index
        sp.index = (octet == Int('P') || octet == Int('p')) ? 7 : 0
    elseif 7 == sp.index
        sp.index = (octet == Int('T') || octet == Int('t')) ? 8 : 0
    elseif 8 == sp.index
        sp.index = 0
        if octet == Int('>')
            throw("Content within a script tag must not contain `</script>`")
        end
    elseif 12 == sp.index
        sp.index = octet == Int('-') ? 13 : 0
    elseif 13 == sp.index
        sp.index = 0
        if octet == Int('-')
            throw("Content within a script tag must not contain `<!--`")
        end
    end
    write(sp.io, octet)
end

function Base.unsafe_write(sp::ScriptProxy, input::Ptr{UInt8}, nbytes::UInt)
    written = 0
    last = cursor = input
    final = input + nbytes
    while cursor < final
        ch = unsafe_load(cursor)
        if ch == Int('<') || sp.index != 0
            written += unsafe_write(sp.io, last, cursor - last)
            write(sp, ch)
            written += 1
            cursor += 1
            last = cursor
            continue
        end
        cursor += 1
    end
    if last < final
        written += unsafe_write(sp.io, last, final - last)
    end
    return written
end
