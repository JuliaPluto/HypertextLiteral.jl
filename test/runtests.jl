#!/usr/bin/env julia

using HypertextLiteral
using NarrativeTest

subs = NarrativeTest.common_subs()

# Ignore the difference in the output of `print(Int)` between 32-bit and 64-bit platforms.
push!(subs, r"Int64" => s"Int(32|64)")

# Normalize printing of vector types.
if VERSION < v"1.6.0-DEV"
    Base.show_datatype(io::IO, x::Type{Vector{T}}) where {T} = print(io, "Vector{$T}")
end

# Normalize printing of type parameters.
if VERSION < v"1.6.0-DEV"
    function Base.show_datatype(io::IO, x::DataType)
        istuple = x.name === Tuple.name
        if (!isempty(x.parameters) || istuple) && x !== Tuple
            n = length(x.parameters)::Int
            if istuple && n > 3 && all(i -> (x.parameters[1] === i), x.parameters)
                print(io, "NTuple{", n, ", ", x.parameters[1], "}")
            else
                Base.show_type_name(io, x.name)
                print(io, '{')
                for (i, p) in enumerate(x.parameters)
                    show(io, p)
                    i < n && print(io, ", ")
                end
                print(io, '}')
            end
        else
            Base.show_type_name(io, x.name)
        end
    end
end

# Ignore line ending differences for Windows targets.
push!(subs, r"\r\n" => "\n")

# Set the width to 72 so that MD->PDF via pandoc fits the page.
ENV["COLUMNS"] = "72"

package_path(x) = relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "..", x))
default = package_path.(["README.md", "docs/src"])
runtests(; default=default, subs=subs)
