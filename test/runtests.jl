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

# Ignore line ending differences for Windows targets.
push!(subs, r"\r\n" => "\n")

# Set the width to 72 so that MD->PDF via pandoc fits the page.
ENV["COLUMNS"] = "72"

package_path(x) = relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "..", x))
default = package_path.(["README.md", "docs/src"])
runtests(; default=default, subs=subs)
