#!/usr/bin/env julia

using HypertextLiteral
using NarrativeTest

subs = NarrativeTest.common_subs()

# Ignore the difference in the output of `print(Int)` between 32-bit and 64-bit platforms.
push!(subs, r"Int64" => s"Int(32|64)")

# Set the width to 72 so that MD->PDF via pandoc fits the page.
ENV["COLUMNS"] = "72"

package_path(x) = relpath(joinpath(dirname(abspath(PROGRAM_FILE)), "..", x))
default = package_path.(["README.md"])
runtests(; default=default, subs=subs)
