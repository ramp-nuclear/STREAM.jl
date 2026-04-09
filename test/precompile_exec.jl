# precompile_exec.jl — PackageCompiler warmup script
#
# Goal: trigger enough method compilation to bake the slow TTFX paths into
# stream.so, WITHOUT running heavy solves that spike memory during the build.
#
# Run via: ./build_sysimage.sh   (never run this file directly as a test)

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq
using Sundials
using Symbolics
using QuadGK
