---
gsd_state_version: 1.0
milestone: v0.4
milestone_name: Composability & Physics
status: planning
stopped_at: Phase 13 context gathered
last_updated: "2026-03-14T18:49:49.453Z"
last_activity: 2026-03-14 — v0.4 roadmap created; Phase 13 is next
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
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

Phase: 13 of 16 (Physics Foundation)
Plan: — (not yet planned)
Status: Ready to plan
Last activity: 2026-03-14 — v0.4 roadmap created; Phase 13 is next

Progress: [░░░░░░░░░░] 0%

---

## Performance Metrics

**v0.3 velocity reference:** 8 plans; avg ~24 min/plan

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 10 Channel Upgrade | 2 | 28 min | 14 min |
| 11 HeatDiffusion | 2 | 28 min | 14 min |
| 12 MTR Validation | 2 | 125 min | 63 min |
| 12.1 PipeGeometry | 2 | 26 min | 13 min |

*Updated after each plan completion*

---

## Accumulated Context

### Key Decisions (carry-forward from v0.3)

| Decision | Rationale |
|----------|-----------|
| PHY-01 must precede new validation tests | wet_perimeter Dh fix shifts Re/HTC reference constants; all VAL constants must be regenerated after |
| build_initializeprob=false mandatory for coupled HeatDiffusion+CAC | MTK init system corrupts u0; bypass ensures KINSOL starts from user-provided guess |
| MTR mdot initial guess: +0.600 kg/s (positive) | Negative guess causes 51 kPa pressure residual → KINSOL diverges to NaN |
| MTK port array access: getproperty(sys, Symbol(:thermal_left, i)) | sys.thermal_left[i] fails in connect(); named subsystem access is the correct pattern |
| HeatDiffusion Q_flow sign: both faces give Q_flow < 0 when plate hotter than BC | MTK convention positive=into component; fixed Phase 12 Plan 02 |
| VAL-03 T_plate_center must use analytical reference, not Python STREAM | Python one_sided_connection gives 318.48 K (physically wrong); Julia gives 323.64 K (correct) |
| regime_dependent switching must use ifelse() not a hard branch | Solver discontinuity risk; same pattern as flow reversal smoothing |

### Pending Todos

None.

### Blockers/Concerns

None at roadmap creation. PHY-01 (Dh fix) may require updating hardcoded reference constants in existing tests — expected, not a blocker.

---

## Session Continuity

**Last session:** 2026-03-14T18:49:49.449Z
**Stopped at:** Phase 13 context gathered
**Next action:** Run `/gsd:plan-phase 13`
**Resume file:** .planning/phases/13-physics-foundation/13-CONTEXT.md

---

*Last updated: 2026-03-14 — v0.4 roadmap created; 4 phases (13-16) covering 16 requirements*
