---
phase: 51-julia-startup-performance-reliable-sysimage
plan: 01
subsystem: build-tooling
tags: [sysimage, performance, ttfx, build, documentation]
dependency_graph:
  requires: []
  provides: [TTFX-01, TTFX-02, TTFX-03, TTFX-05, TTFX-06]
  affects: [build_sysimage.sh, test/precompile_exec.jl, CLAUDE.md, time_startup.jl]
tech_stack:
  added: []
  patterns: [pre-flight-memory-gate, mtkcompile-warmup-bake, ttfx-timing-script]
key_files:
  created: [time_startup.jl]
  modified: [test/precompile_exec.jl, build_sysimage.sh, CLAUDE.md]
decisions:
  - "Use PipeGeometry_circular(1.0, 0.01) for warmup — matches test_channel.jl, physically valid L=1m D=0.01m"
  - "THRESHOLD_MB=6144 (6 GB) per D-03 research recommendation — conservative for PackageCompiler link step"
  - "time_startup.jl uses same Pump+Channel n=2 topology as precompile_exec.jl for consistency"
metrics:
  duration_min: 5
  completed_date: "2026-04-10"
  tasks_completed: 2
  files_modified: 4
---

# Phase 51 Plan 01: Sysimage Warmup, Memory Gate, and TTFX Timing Summary

Baked mtkcompile dispatch into the sysimage warmup, added a pre-flight RAM gate to the build
script, and created a timing script for measuring TTFX improvement baseline vs sysimage.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add warmup code to precompile_exec.jl and create time_startup.jl | 4aa2861 | test/precompile_exec.jl, time_startup.jl |
| 2 | Add pre-flight memory check to build_sysimage.sh and update CLAUDE.md | 69de911 | build_sysimage.sh, CLAUDE.md |

## What Was Built

**test/precompile_exec.jl** — Added a minimal `Pump(3.0e4)` + `Channel(n=2)` connected system
warmup that calls `mtkcompile(sys)`. This triggers MTK's symbolic IR dispatch paths (index
reduction, Jacobian sparsity, code generation) so they are baked into `stream.so`. Previously
the file only had `using` imports, which bakes package loading but not method compilation.

**time_startup.jl** — New timing script in repo root. Measures two independent durations:
`t_load` (using STREAM load time) and `t_compile` (mtkcompile wall time on the same 2-node
system). Run without sysimage for baseline (~90s), then with `--sysimage stream.so` for
comparison (~5s expected).

**build_sysimage.sh** — Added pre-flight memory gate: reads `MemAvailable` from `/proc/meminfo`,
compares against `THRESHOLD_MB=6144`, and exits 1 with formatted error + `.wslconfig` fix
instructions if RAM is insufficient. The gate fires before any Julia process starts, so users
get immediate feedback instead of a 15-minute build that crashes silently.

**CLAUDE.md** — Expanded the Performance — Sysimage section with: WSL2 memory requirements,
PowerShell one-liner to check Windows RAM, `.wslconfig` memory= and swap= settings, `wsl
--shutdown` restart step, and `time_startup.jl` usage for TTFX measurement.

## Verification

- `bash -n build_sysimage.sh` exits 0 (syntax clean)
- `grep "mtkcompile(" test/precompile_exec.jl` returns 1 match
- `grep "THRESHOLD_MB=6144" build_sysimage.sh` returns 1 match
- `grep "wslconfig" CLAUDE.md` returns 1 match
- `ls time_startup.jl` confirms file exists
- `grep "NonlinearSolve" test/test_resistors.jl` returns no output (D-06: already clean)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected PipeGeometry_circular call to use two positional args**
- **Found during:** Task 1
- **Issue:** Plan action snippet showed `PipeGeometry_circular(0.01)` (one arg) then
  contradicted itself with `PipeGeometry_circular(0.01, 7.85e-5)`. The actual signature
  is `PipeGeometry_circular(L, D)` requiring two args (L=length, D=diameter).
- **Fix:** Used `PipeGeometry_circular(1.0, 0.01)` (L=1.0m, D=0.01m) matching
  `test/test_channel.jl` exactly — physically valid and consistent with existing tests.
- **Files modified:** test/precompile_exec.jl, time_startup.jl

## Known Stubs

None.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced.
The pre-flight check reads `/proc/meminfo` (kernel virtual file, trusted source) and the
warmup code runs inside PackageCompiler's isolated build environment.

## Self-Check: PASSED

- test/precompile_exec.jl: FOUND
- time_startup.jl: FOUND
- build_sysimage.sh: FOUND (modified)
- CLAUDE.md: FOUND (modified)
- Commit 4aa2861: FOUND
- Commit 69de911: FOUND
