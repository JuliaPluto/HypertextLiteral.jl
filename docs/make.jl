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

makedocs(
    sitename = "HypertextLiteral.jl",
    format = Documenter.HTML(prettyurls=(get(ENV, "CI", nothing) == "true")),
    pages = [
        "Usage" => "index.md",
        "Extend" => "extend.md",
        "Design" => "design.md",
        "Notation" => "notation.md",
        "Primitives" => "primitives.md",
        "Reference" => "reference.md",
    ],
    modules = [HypertextLiteral])

deploydocs(
    repo = "github.com/MechanicalRabbit/HypertextLiteral.jl.git",
)
