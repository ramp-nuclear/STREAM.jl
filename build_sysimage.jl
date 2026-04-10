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
@info "Packages: STREAM, QuadGK"
@info "Note: ModelingToolkit/Symbolics/OrdinaryDiffEq/Sundials are excluded."
@info "Their LLVM IR is too large for PackageCompiler's link step even on 32 GB machines."
@info "MTK load time is handled by Julia's automatic pkgimage cache (~/.julia/compiled/)."
@info "For fast mtkcompile: keep a persistent Julia REPL open with Revise.jl."

create_sysimage(
    ["STREAM", "QuadGK"];
    sysimage_path = "stream.so",
    project = "."
)

@info "Done! sysimage written to stream.so"
@info "Run tests with: julia --sysimage stream.so --project=. test/runtests.jl"
