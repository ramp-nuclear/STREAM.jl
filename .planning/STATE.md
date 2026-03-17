---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Flow Reversal Systems
status: planning
stopped_at: Completed 20-sign-safety-01-PLAN.md
last_updated: "2026-03-17T13:07:14.568Z"
last_activity: 2026-03-17 — v0.6 roadmap created
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
  percent: 0
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 20 — Sign Safety (v0.6 start)
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 20 of 24 (Sign Safety)
Plan: 01 complete, 02 next
Status: In progress
Last activity: 2026-03-17 — 20-01 channel sign-safety source fixes complete

Progress: [█████░░░░░] 50% (1 of 2 phase plans complete)

---

## Performance Metrics

**v0.5 velocity reference:** 6 plans completed

| Phase | Plans | Avg/Plan |
|-------|-------|----------|
| 17 File Structure Reorganization | 2 | ~24 min |
| 18 Test Split and API Cleanup | 2 | ~9 min |
| 19 Docstrings, CLAUDE.md, Final Polish | 2 | ~6 min |

*Updated after each plan completion*

---
| Phase 20-sign-safety P01 | 2 | 2 tasks | 2 files |

## Accumulated Context

### Key Decisions (carry-forward for v0.6)

- [v0.5]: solve_transient is now keyword-only — SOLV-01 must preserve this convention when adding `callbacks` kwarg
- [v0.4]: ifelse() used for flow reversal and regime switching — SIGN-01..03 may need to audit all ifelse() sign usages
- [v0.4]: Correlation functions are plain Julia closures (not @register_symbolic) — elenbaas_nusselt follows the same pattern
- [v0.4]: Re/Nu/velocity/Pe are @observed (not unknowns) — SIGN-02 must ensure these stay @observed and sign-correct
- [v0.3]: Flapper is a new component file — goes to src/components/ per CLAUDE.md layout
- [v0.6 SIGN]: ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev) per-cell upwinding — T_inlet_fwd/rev declared before loop, selection inside loop
- [v0.6 SIGN]: port_in.T ~ T[1] is correct MTK outflow equation (T[1] is outflow temp through port_in under reverse flow)
- [v0.6 SIGN]: velocity[i] (unsigned speed) and v[i] (signed) are distinct observables in ChannelAndContacts

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes.
- PUMP-01 requires @register_symbolic for a callable — implementation strategy (wrapping f(t) as symbolic) needs prototyping in plan.

---

## Session Continuity

**Last session:** 2026-03-17T13:07:14.566Z
**Stopped at:** Completed 20-sign-safety-01-PLAN.md
**Next action:** `/gsd:plan-phase 20`
**Resume file:** None

---

*Last updated: 2026-03-17 — v0.6 roadmap created; 5 phases (20-24), 8 planned plans, 21 requirements mapped*
