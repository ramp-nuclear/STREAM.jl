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
@info "Packages: STREAM, ModelingToolkit, Symbolics, QuadGK"
@info "Note: OrdinaryDiffEq and Sundials excluded — their LLVM IR is too large for WSL2 link step"

create_sysimage(
    ["STREAM", "ModelingToolkit", "Symbolics", "QuadGK"];
    sysimage_path = "stream.so",
    project = "."
)

@info "Done! sysimage written to stream.so"
@info "Run tests with: julia --sysimage stream.so --project=. test/runtests.jl"
