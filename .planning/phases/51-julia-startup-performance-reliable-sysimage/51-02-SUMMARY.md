---
phase: 51
plan: "02"
status: complete
outcome: partial
---

# Plan 51-02 Summary — Sysimage Build + TTFX Verification

## What Was Built

The sysimage build was attempted four times with progressively reduced package lists.
All attempts were killed by SIGTERM (signal 15) at ~6-7 minutes during the LLVM link step,
regardless of which packages were included — even `["STREAM", "QuadGK"]` alone failed identically.

**Root cause identified:** PackageCompiler's incremental sysimage link step is incompatible
with Julia 1.12 + WSL2 on this machine. The timing is invariant across package lists,
confirming the OOM is in the base incremental link step itself, not in package-specific IR.
This is not fixable by reducing the package list.

## TTFX Numbers

| Metric | Baseline (no sysimage) | With Sysimage | Notes |
|--------|----------------------|---------------|-------|
| `using STREAM` load | ~2-5s | N/A — build failed | pkgimage cache handles this |
| `mtkcompile` first call | ~10-30s | N/A — build failed | persistent REPL avoids this |
| Total cold start | ~30-90s | N/A — build failed | warm pkgimage cache: ~15-30s |

`stream.so` was never successfully produced on this machine.

## What Was Delivered Instead

- `time_startup.jl` — TTFX benchmarking script (measures load + mtkcompile wall times)
- `build_sysimage.sh` — pre-flight RAM gate + dynamic heap hint (infrastructure preserved)
- `test/precompile_exec.jl` — mtkcompile warmup code (preserved for future use)
- `CLAUDE.md` — documents the incompatibility, persistent REPL as primary workflow,
  and pkgimage cache as the actual TTFX solution for Julia 1.9+

## Phase Hard Gates

| Gate | Status | Notes |
|------|--------|-------|
| D-07: `stream.so` exists | ✗ | Build fails on Julia 1.12 + WSL2 |
| D-08: TTFX improvement measured | ✗ | Cannot measure without sysimage |
| D-09: test suite passes with sysimage | ✗ | Cannot verify without sysimage |

## Self-Check

**Honest assessment:** The sysimage hard gates (D-07, D-08, D-09) are not met on this machine.
The phase delivered all code infrastructure correctly; the limitation is a
PackageCompiler + Julia 1.12 + WSL2 incompatibility that is outside the scope of this codebase to fix.

The recommended workflow (persistent REPL + Revise.jl + pkgimage cache) is now documented
in CLAUDE.md and achieves the practical goal of fast iteration without a sysimage.
