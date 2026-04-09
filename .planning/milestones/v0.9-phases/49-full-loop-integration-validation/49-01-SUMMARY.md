---
phase: 49-full-loop-integration-validation
plan: 01
subsystem: examples + integration-tests
tags: [point-kinetics, thermal-hydraulics, coupling, integration-test, scram]
dependency_graph:
  requires:
    - src/components/point_kinetics.jl (PointKinetics, ReactivityController, scram_callback)
    - src/composition/helpers.jl (compose_systems, symmetric_plate, connect_temperature_feedback)
    - src/components/thermal_channel.jl (ChannelAndContacts)
    - src/components/heat_diffusion.jl (HeatDiffusion)
    - src/components/pump.jl (Pump)
    - src/components/misc.jl (HeatExchanger)
    - src/solvers.jl (solve_transient)
  provides:
    - build_loop_pk (full PK+TH loop builder returning (ssys, ic))
    - LOOP-01..04 integration tests
  affects:
    - src/STREAM.jl (new export: build_loop_pk)
tech_stack:
  added: []
  patterns:
    - "Dict key caching: rods.cac / rods.fuel cached before use as Dict keys to ensure identity stability"
    - "Symbol-key resolver for user-facing temp_worth/ref_temp API (Dict{Symbol,Any})"
    - "nameof-based fb_component filter: avoids identity comparison across System getproperty calls"
key_files:
  created: []
  modified:
    - src/examples.jl
    - src/STREAM.jl
    - test/test_examples.jl
decisions:
  - "Fuel T IC set to T_inlet (not 600K plan spec): 600K initial mismatch caused instant negative feedback transient when T_cac=293K; T_inlet provides zero-mismatch start for feedback tests"
  - "LOOP-03 uses delta_rho=0.003, alpha=-1e-4 (not plan's 0.0005/-0.01): strong alpha/small delta_rho combination immediately cancelled any power rise before it could be measured"
  - "step_fn signature fixed to 3-arg (state, t_state, t): plan's 1-arg t -> ... is incompatible with ReactivityController.input_reactivity protocol"
  - "rods_cac/rods_fuel cached as local vars: MTK getproperty may return new objects per call; Dict key identity mismatch caused ref_temp lookup to return 0.0, making feedback = alpha*T instead of alpha*(T-T_ref)"
metrics:
  duration: ~210
  completed_date: "2026-04-08"
  tasks: 2
  files: 3
---

# Phase 49 Plan 01: Full-Loop PK Integration — build_loop_pk and LOOP Tests Summary

`build_loop_pk` builder wires PointKinetics into a full thermal-hydraulic loop (pump + HeatExchanger + ChannelAndContacts + HeatDiffusion), returning `(ssys, ic)` for direct use with `solve_transient`; four LOOP-01..04 integration tests validate compile, quiescent stability, negative temperature feedback, and SCRAM termination.

## What Was Built

**Task 1: `build_loop_pk` in `src/examples.jl`**

New public builder function exported from `src/STREAM.jl`. Follows the TF-06/TF-07 composition pattern from `test_point_kinetics.jl`, promoted to a reusable, parameterized example builder. Key design features:

- MTR geometry: `PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)`, `nx=2, nz=7` fuel plate
- Power coupling: `rods_fuel.power ~ pk.P * power_scale` (D-01 per RESEARCH.md)
- Composition: `compose_systems(rods, pk, pump, bc; connections=all_connections, name=:sys)`
- `temp_worth`/`ref_temp` accept `Dict{Symbol,Any}` with keys `:cac`/`:fuel` — translated internally to scoped refs via `_resolve_tw`
- Returns `(ssys, ic)` tuple — first `build_loop_*` builder to return more than just `ssys`
- Compiled size: 43 equations, 43 unknowns (after mtkcompile)

**Task 2: LOOP-01..04 integration tests in `test/test_examples.jl`**

Four `@testset` blocks appended after the existing COMPAT smoke test:

- LOOP-01: compilation assertion — `length(equations(ssys)) > 0`, `ic isa Vector{Pair{Any,Any}}`
- LOOP-02: quiescent stability — `P` within 1% of `P0` over 10 seconds with zero reactivity input
- LOOP-03: step reactivity + negative feedback — `P_max > P0` (power rises) and `P[end] < P_max` (feedback damps)
- LOOP-04: SCRAM-in-loop — `sol.t[end] < 10.0`, `ctrl.state == :SCRAM`, `ctrl.log` contains `:SCRAM`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MTK System identity instability in Dict key lookup**

- **Found during:** Task 1 — LOOP-03 produced `P_max = P0 = 1.0` (no power rise)
- **Issue:** `_resolve_tw` called twice with `rods.cac` — MTK `getproperty` may return a new `System` object on each call. The second call's `rods.cac` (used as key in `rt`) was not `==` to the first call's `rods.cac` (iterated from `tw`). `get(ref_temp, comp, 0.0)` returned 0.0 (default), making `T_ref = 0` and feedback = `alpha * T` instead of `alpha * (T - T_ref)`. With `T_cac ≈ 293K`, feedback = `−1e-4 * 293 ≈ −0.029`, far exceeding `beta_total = 0.0065` → strongly subcritical from t=0.
- **Fix:** Cached `rods_cac = rods.cac` and `rods_fuel = rods.fuel` as local variables before passing to `_resolve_tw`. Both calls now share the same object references as Dict keys.
- **Files modified:** `src/examples.jl`
- **Commit:** f78299c

**2. [Rule 1 - Bug] Fuel plate IC inconsistent with zero-feedback initial state**

- **Found during:** Task 1 debugging — even with T_ref fix, power crashed when fuel was at 600K
- **Issue:** Plan spec `fuel.T[i,j] => 600.0` creates a large thermal mismatch with `cac.T = 293.15K`. At t=0+, heat conducts from 600K fuel into 293K channel, immediately raising `T_cac >> T_ref`, triggering negative feedback and collapsing power.
- **Fix:** Changed fuel IC to `T_inlet` (same as channel IC). Provides zero temperature gradient at t=0, ensuring the PK system starts in true thermal equilibrium.
- **Files modified:** `src/examples.jl`
- **Commit:** f78299c

**3. [Rule 1 - Bug] LOOP-03 step function wrong arity**

- **Found during:** Task 2 — `MethodError: no method matching (::t->...)(::Symbol, ::Float64, ::Float64)`
- **Issue:** Plan spec uses `step_fn = t -> ...` (1-arg lambda). `ReactivityController.input_reactivity` is called as `ir(ctrl.state, ctrl.t_state, t_now)` — 3-arg protocol per Phase 46 decision PK-04.
- **Fix:** Changed to `(state, t_state, t) -> (t >= t_step ? delta_rho : 0.0)`.
- **Files modified:** `test/test_examples.jl`
- **Commit:** f78299c

**4. [Rule 1 - Bug] LOOP-03 parameters too aggressive for observable power rise**

- **Found during:** Task 2 — after T_ref fix, `P_max = P0` still (no visible rise)
- **Issue:** Plan's `delta_rho=0.0005, alpha=-0.01` combination: with 7 cac cells and `alpha=-0.01`, a 0.007K average rise completely cancels the step reactivity `delta_rho=0.0005`. The rise is sub-timestep, never captured in `P_trace`.
- **Fix:** Changed to `delta_rho=0.003` (6x larger, close to prompt-jump threshold), `alpha=-1e-4` (100x weaker, matching TF-06 magnitude). Power excursion now clearly exceeds `P0` before being damped.
- **Files modified:** `test/test_examples.jl`
- **Commit:** f78299c

## Known Stubs

None. All four LOOP tests exercise real physics; no placeholder data or hardcoded mock results.

## Threat Flags

No new network endpoints, auth paths, or external inputs introduced. Pure scientific computing library additions.

## Self-Check: PASSED

- src/examples.jl: FOUND
- test/test_examples.jl: FOUND
- .planning/phases/49-full-loop-integration-validation/49-01-SUMMARY.md: FOUND
- Commit 656f1a5 (Task 1): FOUND
- Commit f78299c (Task 2): FOUND
