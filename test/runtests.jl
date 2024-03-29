#!/usr/bin/env julia

using Documenter, Logging, NarrativeTest, Test
using HypertextLiteral

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

@testset "HypertextLiteral" begin

    if isempty(ARGS) || "doctest" in ARGS
        @info "Running doctest..."
        DocMeta.setdocmeta!(
            HypertextLiteral,
            :DocTestSetup,
            quote
                using HypertextLiteral:
                    HypertextLiteral, @htl, @htl_str,
                    Reprint, Render, Bypass, EscapeProxy,
                    attribute_value, content, attribute_pair,
                    inside_tag
                using Dates
            end)
        with_logger(Logging.ConsoleLogger(stderr, Logging.Warn)) do
            doctest(HypertextLiteral)
        end
    end

    if isempty(ARGS)
        @info "Running narrative tests..."
        NarrativeTest.testset(; default=default, subs=subs)
    else
        filter!(!=("doctest"), ARGS)
        if !isempty(ARGS)
            @info "Running narrative tests..."
            NarrativeTest.testset(ARGS; subs=subs)
        end
    end
end

@static if VERSION >= v"1.3"
    
    struct Foo end
    
    @testset "invalidation" begin 
        @test HypertextLiteral.content(Foo()) isa HypertextLiteral.Reprint # fallback

        # Now define a html printing type 
        @eval Base.show(io::IO, ::MIME"text/html", ::Foo) = "Foo"

        # Previously this would not have worked because content is a generated function depending on hasmethod in the generator
        @test repr(Base.invokelatest(HypertextLiteral.content, Foo())) == "HypertextLiteral.Render{Foo}(Foo())"
    end
end
