---
gsd_state_version: 1.0
milestone: v0.3
milestone_name: HeatDiffusion
status: completed
stopped_at: Completed 12-mtr-validation-01-PLAN.md — reference constants obtained
last_updated: "2026-03-14T02:53:57.201Z"
last_activity: 2026-03-14 — Phase 12 Plan 01 complete; MTR reference script + HDIFF-03-gap test
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 6
  completed_plans: 5
  percent: 83
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-13)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 12 — MTR Validation
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 12 of 12 (MTR Validation)
Plan: 01 COMPLETE (Phase 12 Plan 01 done; awaiting checkpoint)
Status: Phase 12 Plan 01 complete; generate_mtr_reference.py written, HDIFF-03-gap test passing
Last activity: 2026-03-14 — Phase 12 Plan 01 complete; MTR reference script + HDIFF-03-gap test

Progress: [████████░░] 83% (5/6 plans complete)

---

## Performance Metrics

**v0.2 velocity reference:** 7 plans; avg ~8 min/plan; total ~55 min execution

| Phase | Plans | Total Time | Avg/Plan |
|-------|-------|------------|----------|
| 06 Gravity | 1 | 9 min | 9 min |
| 07 Network | 2 | 8 min | 4 min |
| 08 Inertia+HX | 2 | 23 min | 12 min |
| 09 Channel | 2 | 15 min | 8 min |

**v0.3 (active):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 Channel Upgrade | 1+ | 6 min | 6 min |
| 11 HeatDiffusion | 1+ | 7 min | 7 min |
| 12 MTR Validation | TBD | - | - |

*Updated after each plan completion*
| Phase 10 P02 | 22 | 2 tasks | 2 files |
| Phase 11 P01 | 7 | 2 tasks | 2 files |
| Phase 11 P02 | 21 | 2 tasks | 1 files |
| Phase 12-mtr-validation P01 | 30 | 2 tasks | 2 files |
| Phase 12-mtr-validation P01 | 35 | 3 tasks | 2 files |

## Accumulated Context

### Key Decisions (carry-forward from v0.2)

| Decision | Rationale |
|----------|-----------|
| q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow | Two-sided heating: each side uses pi*Dh/2; sum recovers pi*Dh — Phase 10 interface contract |
| _channel_base_eqs accepts concrete g_acc (Float64) | dP is algebraic; avoids symbolic pars indexing |
| MTK variadic connect() is the junction — no Junction component | Kirchhoff equations auto-generated |
| build_loop is test/example utility, not primary API | MTK connect()/compose() is expressive enough |
| THERM-03 uses two-sided CAC vs CHF (same D=0.01) | D_cac=2*D_chf fails 0.1% tolerance: h_tc depends on Dh via Re/Nu; same D ensures identical h_tc |
| ChannelAndContacts requires explicit thermal.Q_flow equations | Acausal MTK: port Q_flow must be defined via h_tc*(pi*Dh/2)*dz*deltaT; missing eqs leave system underdetermined |
| MTK port array access: getproperty(sys, Symbol(:thermal_left, i)) | sys.thermal_left[i] fails in connect(); named subsystem access is the correct pattern |
| HeatDiffusion: rho_s/cp_s/k_s as Float64, power as MTK @parameters | Material props fixed in v0.3; power tunable via remake() without recompile |
| HeatDiffusion boundary cells: half-cell flux scheme (Option B) | Consistent FD: boundary cell uses thermal_port.T as virtual neighbor at dx/2 distance |
| vec(collect(T)) flattens 2D MTK state for System() constructor | Required pattern for 2D array states in MTK; see RESEARCH.md Pitfall 2 |
| HeatDiffusion Q_flow sign asymmetric: thermal_left.Q_flow > 0 (heat out left), thermal_right.Q_flow < 0 (heat out right) | Left eq: k*(T_plate - T_bc)/(dx/2); right eq: k*(T_bc - T_plate)/(dx/2) — asymmetry from half-cell scheme |
| ChannelAndContacts one-sided solve needs Re/Nu/h_tc guesses + fully_determined=false | Without explicit algebraic var guesses, MTK initialization system hits cyclic dependency error |
| plate() CalculationGraph has empty funcs; fuel power via CalculationGraph.from_decoupled | Python STREAM plate() / one_sided_connection() produce funcs-less CG; power must be injected separately |
| HDIFF-03-gap test: power_shape [0.0,1.0,0.0] not [0.5,0.0,0.5] | Symmetric outer sources: Laplacian=0 forces T_center=T_outer; center-sourced shape correctly tests per-cell power_shape |

### Pending Todos

None.

### Blockers/Concerns

- [Phase 12 checkpoint]: `generate_mtr_reference.py` written; user must run it in Python STREAM env to obtain VAL-01/02/03 reference constants for Plan 02.
- [Phase 10 RESOLVED]: MTK array port access syntax: `getproperty(sys, Symbol(:thermal_left, i))` confirmed working; `sys.thermal_left[i]` fails in connect() calls.
- [Phase 10 RESOLVED]: ChannelAndContacts port Q_flow equations required for proper acausal wiring — added in Plan 02.

---

## Session Continuity

**Last session:** 2026-03-14T02:53:57.199Z
**Stopped at:** Completed 12-mtr-validation-01-PLAN.md — reference constants obtained
**Next action:** User runs generate_mtr_reference.py → resume Plan 02 with reference constants
**Resume file:** None

---

*Last updated: 2026-03-14 — Phase 12 Plan 01 complete; MTR reference script + HDIFF-03-gap test*
