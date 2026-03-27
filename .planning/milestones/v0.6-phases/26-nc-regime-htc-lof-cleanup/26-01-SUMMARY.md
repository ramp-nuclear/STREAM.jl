---
phase: 26-nc-regime-htc-lof-cleanup
plan: "01"
subsystem: correlations, thermal-channel, examples
tags: [natural-convection, regime-dependent, NC-detection, Gr-over-Re2, elenbaas]
dependency_graph:
  requires: []
  provides: [NATCONV-01]
  affects: [ChannelAndContacts, ChannelHeatFlux, build_loop_lof_bypass]
tech_stack:
  added: []
  patterns: [Gr/Re^2 NC criterion, ifelse symbolic switching, @observed diagnostics]
key_files:
  created: []
  modified:
    - src/physical_models/correlations.jl
    - src/components/thermal_channel.jl
    - src/examples.jl
    - test/test_correlations.jl
decisions:
  - "NC detection uses Gr/Re^2>1 criterion (matching Python STREAM convention)"
  - "htc_natural/Dh/g are all-or-nothing: partial supply throws ArgumentError"
  - "Gr_over_Re2 is @observed in ChannelAndContacts (not in all_vars)"
  - "Gr_over_Re2 is a plain unknown equation in ChannelHeatFlux (in all_vars)"
  - "ret Channel in build_loop_lof_bypass stays unwired (adiabatic, Gr=0 always)"
metrics:
  duration_minutes: 10
  completed_date: "2026-03-27"
  tasks_completed: 2
  files_modified: 4
---

# Phase 26 Plan 01: NC regime detection in regime_dependent — Summary

**One-liner:** Extended `regime_dependent` with Gr/Re^2>1 NC switching via `htc_natural`/`Dh`/`g` kwargs, added `Gr_over_Re2[i]` diagnostic to both channel components, and wired `elenbaas_htc` into `build_loop_lof_bypass`.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Extend regime_dependent with NC detection + add Gr_over_Re2 to channel components | a266f88 | correlations.jl, thermal_channel.jl |
| 2 | Wire NC into build_loop_lof_bypass + add unit tests for NC kwargs | 85ddf36 | examples.jl, test_correlations.jl |

## What Was Built

### correlations.jl — regime_dependent NC extension

Added three optional kwargs to `regime_dependent`:
- `htc_natural = nothing` — NC HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu`
- `Dh = nothing` — hydraulic diameter for Grashof computation
- `g = nothing` — gravitational acceleration for Grashof computation

When all three are provided, the returned `htc` closure computes `Gr = beta*g*dT*Dh^3/nu^2` and uses `ifelse(Gr/Re^2 > 1, htc_natural(...), htc_forced(...))`. Guards:
- ArgumentError if `htc_natural` given without both `Dh` and `g`
- `@warn` if `Dh`/`g` given without `htc_natural`

### thermal_channel.jl — Gr_over_Re2 observables

**ChannelAndContacts:** Added `(Gr_over_Re2(t))[1:n]` to `@variables` block and pushed `Gr_over_Re2[i] ~ Gr_i / Re_i^2` into the `obs` vector (not `all_vars`). Uses `thermal_left[i].T` as wall temperature.

**ChannelHeatFlux:** Added `(Gr_over_Re2(t))[1:n]` to `@variables` block, pushed `Gr_over_Re2[i] ~ Gr(...)  / Re[i]^2` into `eqs`, and added `collect(Gr_over_Re2)` to `all_vars`. Uses `T_wall_p` parameter as wall temperature.

### examples.jl — build_loop_lof_bypass NC wiring

Replaced bare `ChannelHeatFlux` construction with a `regime_dependent` call that wires `elenbaas_htc(b=D_ch, L=L_ch, Dh=D_ch, g=g_acc)` as `htc_natural`. The `ret` Channel remains unchanged (adiabatic return leg; Gr=0 always active there).

### test_correlations.jl — NATCONV-01 tests

Added 7-test `@testset "NATCONV-01: regime_dependent NC detection"`:
1. NC branch selected when Gr/Re^2 > 1 (Re=10, large dT)
2. Turbulent forced branch when Re^2 >> Gr (Re=5000)
3. Laminar forced branch when small dT, Re=100
4. Friction unaffected by NC kwargs
5. Backward compatibility (no NC kwargs)
6. ArgumentError on `htc_natural` without `g`
7. `@warn` on `Dh`/`g` without `htc_natural`

## Verification Results

All 48 correlation tests pass:
- PHY-02/03/04: Correlation Library — 17/17
- PHY-02/03/04: Integration Tests — 11/11
- NATCONV-01/02: Elenbaas Natural Convection — 11/11
- NATCONV-01: regime_dependent NC detection — 9/9 (includes @warn test = 2 pass entries)

`using STREAM` loads without error.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

Files verified:
- `src/physical_models/correlations.jl` — FOUND
- `src/components/thermal_channel.jl` — FOUND
- `src/examples.jl` — FOUND
- `test/test_correlations.jl` — FOUND

Commits verified:
- `a266f88` — FOUND
- `85ddf36` — FOUND
