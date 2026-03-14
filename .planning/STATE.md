---
gsd_state_version: 1.0
milestone: v0.4
milestone_name: Composability & Physics
status: completed
stopped_at: Completed 14-02-PLAN.md
last_updated: "2026-03-15T09:35:00Z"
last_activity: 2026-03-15 — Phase 14 Plan 02 complete; channel components accept pluggable correlations; PHY-02/03/04 integration tests pass
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
  percent: 100
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-14)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 13 — Physics Foundation
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 14 of 16 (Laminar Correlations) — COMPLETE
Plan: 02 of 02 complete
Status: Phase 14 Complete — Both plans done; correlations wired and tested
Last activity: 2026-03-15 — Phase 14 Plan 02 complete; channel components accept pluggable correlations; PHY-02/03/04 integration tests pass

Progress: [██████████] 100%

---

## Performance Metrics

**v0.3 velocity reference:** 8 plans; avg ~24 min/plan

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 Channel Upgrade | 2 | 28 min | 14 min |
| 11 HeatDiffusion | 2 | 28 min | 14 min |
| 12 MTR Validation | 2 | 125 min | 63 min |
| 12.1 PipeGeometry | 2 | 26 min | 13 min |
| 13 Physics Foundation P01 | 1 | 11 min | 11 min |
| 13 Physics Foundation P02 | 1 | 25 min | 25 min |
| 14 Laminar Correlations P01 | 1 | 18 min | 18 min |
| 14 Laminar Correlations P02 | 1 | 11 min | 11 min |

*Updated after each plan completion*

## Accumulated Context

### Key Decisions (carry-forward from v0.3)

| Decision | Rationale |
|----------|-----------|
| PHY-01 must precede new validation tests | wet_perimeter Dh fix shifts Re/HTC reference constants; all VAL constants must be regenerated after |
| build_initializeprob=false mandatory for coupled HeatDiffusion+CAC | MTK init system corrupts u0; bypass ensures KINSOL starts from user-provided guess |
| MTR mdot initial guess: +0.250 kg/s (positive, rectangular geometry) | Old +0.600 kg/s was for circular D=0.01; Dh≈2.495mm gives ~0.25 kg/s at dP=30 kPa |
| MTK port array access: getproperty(sys, Symbol(:thermal_left, i)) | sys.thermal_left[i] fails in connect(); named subsystem access is the correct pattern |
| HeatDiffusion Q_flow sign: both faces give Q_flow < 0 when plate hotter than BC | MTK convention positive=into component; fixed Phase 12 Plan 02 |
| VAL-03 T_plate_center must use analytical reference, not Python STREAM | Python one_sided_connection gives 318.48 K (physically wrong); Julia gives 323.64 K (correct) |
| regime_dependent switching must use ifelse() not a hard branch | Solver discontinuity risk; same pattern as flow reversal smoothing |
| No @register_symbolic on correlation functions | Plain arithmetic; MTK traces symbolically (unlike spline fluid props which need opaque registration) |
| laminar_friction aspect_ratio kwarg required (no default) | Callers must be explicit about geometry — prevents accidental rectangular K_R applied to circular case |
| Re_transition converted to Float64 in regime_dependent | Avoids Int/Symbolics.Num type-promotion error at system build time |
| PipeGeometry_rectangular: Dh = 4*area/wet_perimeter (~2.5 mm for MTR) | Old 10 mm circular approximation was incorrect; correct Dh shifts Re/HTC/VAL constants |
| Old sentinel-kwargs PipeGeometry constructor deleted (no shim) | MethodError on old calls forces migration; factory functions are the only API |
| Fixed-flow Pump (mdot0) has no pressure equation | Caller must anchor pressure; only 4 eqs: mass balance, mdot constraint, 2 T streams |
| VAL-03 T_out assertion removed (Python one_sided_connection wrong) | Python distributes heat to both faces even for one-sided; Julia correct; energy balance is truth |
| PHY-03 test pairs laminar_friction with constant_Nusselt (not dittus_boelter) | Keeps system well-conditioned at low Re where Dittus-Boelter extrapolates poorly |
| Pr_i computed inline as symbolic expression cp*mu/k in channel components | NOT a new MTK variable — passed directly as closure argument to htc_correlation |

### Pending Todos

None.

### Blockers/Concerns

None at roadmap creation. PHY-01 (Dh fix) may require updating hardcoded reference constants in existing tests — expected, not a blocker.

---

## Session Continuity

**Last session:** 2026-03-14T23:17:53.774Z
**Stopped at:** Completed 14-02-PLAN.md
**Next action:** Execute Phase 14 (next v0.4 phase per ROADMAP.md)
**Resume file:** None

---

*Last updated: 2026-03-14 — v0.4 roadmap created; 4 phases (13-16) covering 16 requirements*
