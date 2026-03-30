---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Flow Reversal Systems
status: unknown
stopped_at: Completed 28-01-PLAN.md (plan 01 of 02 in phase 28)
last_updated: "2026-03-30T20:38:09Z"
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 5
  completed_plans: 5
  percent: 0
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-27)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 28 — subcooled-boiling
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 28
Plan: 02 (next)

## Performance Metrics

**v0.6 velocity reference:** 14 plans completed

| Phase | Plans | Avg/Plan |
|-------|-------|----------|
| 26 NC Regime HTC + LOF Cleanup | 2 | ~35 min |
| 25 Argument Structure Audit | 1 | ~15 min |
| 24.1 Bypass LOF Topology | 2 | ~33 min |
| 24 Loss-of-Flow Validation | 1 | ~90 min |

*Updated after each plan completion*

---
| Phase 20-sign-safety P01 | 2 | 2 tasks | 2 files |
| Phase 20 P02 | 100 | 2 tasks | 4 files |
| Phase 21 P01 | 27 | 2 tasks | 7 files |
| Phase 21 P02 | 10 | 2 tasks | 2 files |
| Phase 22-time-varying-pump P01 | 7 | 2 tasks | 3 files |
| Phase 22-time-varying-pump P02 | 32 | 2 tasks | 6 files |
| Phase 23-flapper-solver-events P01 | 9 | 2 tasks | 4 files |
| Phase 23 P02 | 21 | 1 tasks | 1 files |
| Phase 24-loss-of-flow P01 | 90 | 2 tasks | 4 files |
| Phase 24.1 P01 | 12 | 2 tasks | 4 files |
| Phase 24.1 P02 | 55 | 2 tasks | 4 files |
| Phase 25 P01 | 15 | 2 tasks | 17 files |
| Phase 26-nc-regime-htc-lof-cleanup P01 | 10 | 2 tasks | 4 files |
| Phase 26 P02 | 60 | 2 tasks | 6 files |
| Phase 28-subcooled-boiling P01 | 5 | 2 tasks | 4 files |

## Accumulated Context

### Key Decisions (carry-forward for v0.7)

- [v0.7 SCB-01]: max(dT, 0.0) inside ifelse() exponentiation prevents DomainError when dT < 0 (Julia ifelse evaluates both branches eagerly)
- [v0.7 SCB-04]: regime_dependent_q_scb is a factory (not direct function) to capture pressure at construction time, matching scb_correction closure contract

- [v0.6]: ifelse() for all conditional switching — use for T_wall >= T_ONB SCB switching (ISCB-01)
- [v0.6]: @register_symbolic for opaque fluid functions — sat_temperature(P) follows same pattern as rho_water(T)
- [v0.6]: Correlation functions are plain Julia closures — HTC-01..04, FRIC-01..02 follow same pattern
- [v0.6]: @observed for diagnostic quantities not on RHS of other equations — P[i], T_sat[i], T_ONB[i] qualify
- [v0.4]: Re/Nu/velocity/Pe are @observed (not unknowns) — pressure observables follow same rule
- [v0.3]: New component files go in src/components/ — subcooled_boiling.jl goes in src/physical_models/
- [v0.6 LOF]: pressure anchor pump.port_in.P ~ 1.0e5 required for multi-branch networks — P[i] absolute values depend on this anchor being present

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes, not expected to affect v0.7.
- Phase 28 depends on Phase 27 (T_ONB[i] observable needed for ISCB-01); Phase 30 is independent of Phase 28/29.

---

## Session Continuity

**Last session:** 2026-03-30T20:38:09Z
**Stopped at:** Completed 28-01-PLAN.md (plan 01 of 02 in phase 28)
**Next action:** Execute 28-02-PLAN.md
**Resume file:** None

---

*Last updated: 2026-03-27 — v0.7 roadmap created*
