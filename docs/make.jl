#!/usr/bin/env julia
using Documenter
using HypertextLiteral

# Setup for doctests embedded in docstrings.
DocMeta.setdocmeta!(HypertextLiteral, :DocTestSetup, :(using HypertextLiteral))

# Highlight indented code blocks as Julia code.
using Documenter.Expanders: ExpanderPipeline, Selectors, Markdown, iscode
abstract type DefaultLanguage <: ExpanderPipeline end
Selectors.order(::Type{DefaultLanguage}) = 99.0
Selectors.matcher(::Type{DefaultLanguage}, node, page, doc) =
    iscode(node, "")
Selectors.runner(::Type{DefaultLanguage}, node, page, doc) =
    page.mapping[node] = Markdown.Code("julia", node.code)

custom_footer = """
Powered by [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl),
[NarrativeTest.jl](https://github.com/MechanicalRabbit/NarrativeTest.jl),
and the [Julia Programming Language](https://julialang.org/).
"""

makedocs(
    sitename = "HypertextLiteral.jl",
    format = Documenter.HTML(prettyurls=(get(ENV, "CI", nothing) == "true"),
                             footer=custom_footer),
    pages = [
        "Overview" => "index.md",
        "Element Content" => "content.md",
        "Attributes & Style" => "attribute.md",
        "Script Interpolation" => "script.md",
        "Design Rationale" => "design.md",
        "The `htl` Notation" => "notation.md",
        "Escaping Primitives" => "primitives.md",
        "Package Reference" => "reference.md",
    ],
    modules = [HypertextLiteral])

deploydocs(
    repo = "github.com/MechanicalRabbit/HypertextLiteral.jl.git",
)
