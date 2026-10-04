# Runs the jldoctest examples in the docstrings, so a wrong one fails the suite even when the
# docs are not built. They cover the correlation, property and decay heat values that used to
# be unit tests here.
#
# Documenter is a test-only dependency: `Pkg.test()` (and CI) installs it, but
# `julia --project=. test/runtests.jl` does not see it unless it is in your global environment.
# Run this file alone with `julia --project=docs test/test_doctests.jl`.
using Test
using STREAM

if Base.find_package("Documenter") === nothing
    @warn "Documenter is not installed in this environment, so the doctests are skipped. " *
          "Run them with `julia --project=docs test/test_doctests.jl` or through `Pkg.test()`."
else
    using Documenter
    DocMeta.setdocmeta!(STREAM, :DocTestSetup, :(using STREAM); recursive=true)
    doctest(STREAM; manual=false)
end
