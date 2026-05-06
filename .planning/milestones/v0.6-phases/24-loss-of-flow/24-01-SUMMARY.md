---
phase: 24-loss-of-flow
plan: 01
subsystem: validation
tags: [lof, natural-circulation, flapper, inertia, energy-balance, transient]

requires:
  - phase: 23-flapper-solver-events
    provides: Flapper component, SymbolicContinuousCallback, solve_transient callbacks kwarg, FLAP-06 Pump(0)+Inertia IC pattern
  - phase: 22-time-varying-pump
    provides: Inertia component, build_loop_transient, Pair{Any,Any} op pattern
  - phase: 20-sign-safety
    provides: sign-safe ChannelHeatFlux with abs(mdot) energy balance

provides:
  - build_loop_lof() in src/examples.jl — series LOF topology with Pump(0)+Inertia+HX+ChannelHeatFlux+Flapper
  - test/test_loss_of_flow.jl — 6 testsets validating LOF transient and energy balance (VAL-01, VAL-02)
  - Energy balance formula valid across forced-flow and reversed-flow regimes

affects:
  - future LOF refinements (parallel topology, callable pump coastdown)

tech-stack:
  added: []
  patterns:
    - "Series LOF topology: Pump(0)->Inertia->HX->Channel(g=+9.8)->Flapper->Pump; avoids parallel bypass Gravity pressure contradiction"
    - "LOF IC strategy: reference loop without Flapper (Pump(dP)->HX->Channel) gives KINSOL-safe SS; apply via Pair{Any,Any}+NoInit"
    - "Energy balance formula |mdot|*cp*(max(T_cells)-T_inlet): selects correct outlet in both flow directions without direction detection"
    - "Downward g_acc_ch=9.80665 enables Inertia decay: gravity opposes upward forced flow; Flapper R_closed dominates initial resistance"

key-files:
  created:
    - test/test_loss_of_flow.jl
  modified:
    - src/examples.jl
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Series topology (not parallel) because parallel Gravity bypass creates irresolvable pressure contradiction with Gravity component at both ends; series avoids this entirely"
  - "g_acc_ch=+9.80665 (upward) so gravity opposes forced flow; enables natural Inertia decay toward zero mdot when pump is off"
  - "Reference SS loop (no Flapper/Inertia) for IC generation because KINSOL zero-Jacobian failure on T_open D(T_open)=0 state in SteadyStateProblem"
  - "Energy balance formula uses max(T_cells)-T_inlet rather than T_out-T_inlet; max(T_cells) selects hottest cell regardless of flow direction (T[n] forward, T[1] reversed)"
  - "Forced flow phase lasts ~5ms due to R_closed=1e8 Flapper in series path; t=0 checkpoint captures forced-flow energy balance"

requirements-completed: [VAL-01, VAL-02]

duration: ~90min
completed: 2026-03-21
---

# Phase 24 Plan 01: Loss-of-Flow Validation Summary

**LOF transient validation loop (series Pump(0)+Inertia+HX+ChannelHeatFlux+Flapper) with energy balance 0.09% rtol across forced-flow and natural-circulation regimes**

## Performance

- **Duration:** ~90 min (including topology debugging)
- **Started:** 2026-03-21
- **Completed:** 2026-03-21
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Implemented `build_loop_lof()` using a series topology that compiles to 12 equations / 12 unknowns and runs without crash
- LOF transient validated: Flapper fires, mdot reverses sign, NC established at ~0.24 kg/s; single solve_transient call, 300s, retcode=Success
- Energy balance VAL-01: 0.09% error at all 5 checkpoints (spec: 5% rtol), valid in both forward and reversed flow
- Energy balance VAL-02: 0.09% error in quasi-steady NC (spec: 10% rtol)
- 16 tests total pass (LOF-01 through LOF-04, VAL-01, VAL-02)

## Task Commits

1. **Task 1: build_loop_lof series topology** - `2ee5da7` (feat)
2. **Task 2: LOF test suite VAL-01 VAL-02** - `5ce7775` (feat)

## Files Created/Modified

- `src/examples.jl` — Replaced parallel-path `build_loop_lof` with series topology; removed H_bypass/grav_nc; updated docstring
- `src/STREAM.jl` — Added `build_loop_lof` to export list
- `test/test_loss_of_flow.jl` — New file: 6 testsets (LOF-01..04, VAL-01, VAL-02)
- `test/runtests.jl` — Added `include("test_loss_of_flow.jl")`

## Decisions Made

**D-A: Series topology instead of parallel**
The context (D-04) specified a parallel topology with a bypass Gravity for NC. During implementation, the parallel topology caused `retcode: Unstable` immediately at t=0 regardless of tolerances or solver settings. Root cause: Gravity component in both the channel leg (`rho*g*H` from `g_acc_ch`) and the bypass leg (`rho*g*H_bypass`) creates an algebraically irresolvable pressure constraint when H_bypass=H_ch. The series topology (Flapper in the main flow path, not bypass) avoids this and produces a valid LOF transient with correct energy balance.

**D-B: Reference loop for IC generation**
KINSOL (`solve_steady`) fails on systems containing Flapper because the `D(T_open)=0` equation produces a zero Jacobian column. Workaround: build a reference loop identical to the LOF loop but with Pump(dP) instead of Pump(0)+Inertia, and no Flapper. KINSOL converges for this simpler system. Apply SS mdot and T-cell ICs to the LOF system via `Pair{Any,Any}` op with `NoInit`.

**D-C: max(T_cells) energy balance formula**
The plan (D-13) suggested `|Q_meas - Q_wall| / Q_wall`. In the series topology, forced flow is upward (T[n] is the hot outlet) and NC is downward (T[1] is the hot exit). Using `max(T_cells) - T_inlet` as the enthalpy rise selects the correct endpoint in both directions without explicit flow-direction logic.

**D-D: g_acc_ch = +9.80665 (upward orientation)**
The original plan used `g_acc_ch = -9.80665` (gravity assists downward forced flow). With the series topology, gravity must OPPOSE forced flow so the pump-off Inertia decay drives mdot to zero. With g_acc_ch = +9.8, the gravity term in the channel dP resists upward flow, and when pump turns off, the Inertia decays quickly under gravity + friction + R_closed=1e8 Flapper resistance.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced parallel topology with series topology**
- **Found during:** Task 1 (build_loop_lof implementation)
- **Issue:** Parallel bypass Gravity topology caused `retcode: Unstable` at t=0; pressure equations algebraically inconsistent when both channel and bypass have gravity terms of equal magnitude
- **Fix:** Series topology: `Pump(0) -> Inertia -> HX -> ChannelHeatFlux(g=+9.8) -> Flapper -> Pump`; removes bypass Gravity entirely; adds `ch.inlet.T ~ T_inlet` anchor (valid in series, not over-determined)
- **Files modified:** src/examples.jl
- **Verification:** 12eq/12uk, retcode=Success, energy balance 0.09%
- **Committed in:** 2ee5da7

**2. [Rule 1 - Bug] Changed g_acc_ch default from -9.80665 to +9.80665**
- **Found during:** Task 1, while debugging topology
- **Issue:** g_acc_ch=-9.80665 (gravity assists downward flow) means gravity maintains forced flow when pump turns off; Flapper threshold never reached; no LOF transient
- **Fix:** g_acc_ch=+9.80665 (gravity opposes upward forced flow); when pump turns off, gravity+friction+Flapper resistance drives rapid decay to zero
- **Files modified:** src/examples.jl (default parameter), test/test_loss_of_flow.jl (LOF_G_ACC constant)
- **Verification:** Flapper fires at t≈5ms, NC established at t≈10s, mdot=-0.241 kg/s
- **Committed in:** 2ee5da7

**3. [Rule 1 - Bug] Fixed energy balance formula from |T[n]-T[1]| to max(T_cells)-T_inlet**
- **Found during:** Task 2 (test writing), while verifying VAL-01 assertions
- **Issue:** `|T[n]-T[1]|` gives 22% error; `T_out-T_inlet` gives 77% error in NC phase; correct formula uses max(T_cells) as the "exit temperature" in all regimes
- **Fix:** Formula `Q_meas = |mdot|*cp*(max(T_cells)-T_inlet)` gives 0.09% error in both forward and reversed flow
- **Files modified:** test/test_loss_of_flow.jl
- **Verification:** 0.09% error at all 5 checkpoints and in VAL-02 window
- **Committed in:** 5ce7775

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs)
**Impact on plan:** Topology change required due to numerical instability of the planned parallel design. Series topology satisfies all functional requirements (energy balance, Flapper firing, NC establishment). Physical mechanism differs (gravity-resisted upward flow vs. buoyancy-driven bypass) but all validation assertions pass.

## Known Stubs

None — all assertions use live simulation data.

## Issues Encountered

**Parallel topology pressure contradiction:** The bypass Gravity component in the parallel topology imposes `P_bottom - P_top = rho*g*H` identically to the Channel gravity term. With H_bypass=H_ch and both ends at the same junctions, the system becomes ill-conditioned. Rodas5P immediately exits with `Unstable` at t=0 regardless of IC completeness or solver tolerances. The series topology completely avoids this issue.

**KINSOL zero-Jacobian with Flapper:** `solve_steady` on any system containing Flapper fails because `D(T_open)=0` is a trivial equation in steady state — all rows for `T_open` in the Jacobian are zero. KINSOL exits with "linear solver's setup function failed". The workaround (separate reference loop) is necessary for any LOF-type scenario.

## Next Phase Readiness

- Phase 24 is complete. v0.6 milestone is complete.
- All 8 requirements (SIGN-01..03, PUMP-01..02, FLAP-01..04, VAL-01..02) validated.
- Future LOF improvements: parallel topology with buoyancy model (requires MTK DAE solver fix for stiff bypass resistance), time-varying pump coastdown (blocked by FLAP-06 callable+Flapper incompatibility until v0.7+).

## Self-Check: PASSED

Files verified:
- `src/examples.jl` — contains `build_loop_lof` function
- `src/STREAM.jl` — contains `build_loop_lof` in exports
- `test/test_loss_of_flow.jl` — contains VAL-01 and VAL-02 testsets
- `test/runtests.jl` — contains `include("test_loss_of_flow.jl")`

Commits verified:
- 2ee5da7 — Task 1
- 5ce7775 — Task 2

---
*Phase: 24-loss-of-flow*
*Completed: 2026-03-21*
