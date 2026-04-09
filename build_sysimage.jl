# build_sysimage.jl — Build a custom Julia sysimage for STREAM.jl
#
# DO NOT run this file directly with plain `julia --project=. build_sysimage.jl`.
# Use the wrapper instead, which sets WSL-safe memory and thread limits:
#
#   ./build_sysimage.sh
#
# Output: stream.so in the repo root (git-ignored, platform-specific).
# Rebuild whenever Manifest.toml changes (new/updated packages).
#
# After building, use the sysimage for fast startup:
#   julia --sysimage stream.so --project=. test/runtests.jl
#
# Build time: ~5-15 minutes. Subsequent julia invocations: ~5s instead of ~90s.

using PackageCompiler

@info "Building STREAM.jl sysimage → stream.so"
@info "Packages: STREAM, ModelingToolkit, OrdinaryDiffEq, Symbolics, QuadGK, Sundials"

create_sysimage(
    ["STREAM", "ModelingToolkit", "OrdinaryDiffEq", "Symbolics", "QuadGK", "Sundials"];
    sysimage_path = "stream.so",
    precompile_execution_file = "test/precompile_exec.jl",
    project = "."
)

@info "Done! sysimage written to stream.so"
@info "Run tests with: julia --sysimage stream.so --project=. test/runtests.jl"
