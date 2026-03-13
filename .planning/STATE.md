---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Component & Network Expansion
status: completed
stopped_at: Completed 07-network-architecture-01-PLAN.md
last_updated: "2026-03-13T14:43:04.291Z"
last_activity: 2026-03-13 — Phase 6 plan 01 executed (GRAV-01, GRAV-02 validated)
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 3
  completed_plans: 2
  percent: 100
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-13)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 7 — Network Architecture
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 7 of 9 (Network Architecture) — second v0.2 phase — IN PROGRESS
Plan: 01 (complete), 02 (pending)
Status: Phase 7 plan 01 complete (NET-01 satisfied)
Last activity: 2026-03-13 — Phase 7 plan 01 executed (NET-01 Resistor component)

Progress: [███████░░░] 67% (Phase 7 plan 01 of 2 complete)

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| v0.2 phases total | 4 |
| v0.2 phases complete | 1 |
| v0.2 requirements mapped | 10/10 |
| v0.2 plans written | 1 |
| v0.2 plans complete | 1 |

**v0.1 velocity reference:** 12 plans completed; avg ~13 min/plan

| Phase 06-gravity-validation P01 | 9 min | 2 tasks | 3 files |
| Phase 07-network-architecture P01 | 5 min | 1 tasks | 3 files |

## Accumulated Context

### Key Decisions (v0.1, carry-forward)

| Decision | Rationale |
|----------|-----------|
| MTK from day one | Avoid Python-style architecture; hit learning curve on 30 eq not 300 |
| Gravity: g_acc in Channel + standalone Gravity component on return leg | Natural MTK approach; no special loop architecture needed |
| build_loop is test/example utility, not primary API | MTK connect()/compose() is expressive enough |
| Channel Darcy-Weisbach friction is inline (not wired component) | Reduces DAE complexity; confirmed no Friction in loop |
| TempBC pattern for closed-loop T injection | Breaks circular instream() dependency |
| mtkcompile ~12s for 12-eq loop | Acceptable for interactive use |

### Key Decisions (v0.2 Phase 6)

| Decision | Rationale |
|----------|-----------|
| Gravity port wiring reversed from flow direction | port_in.P > port_out.P means port_in is bottom (high-P); for descending return leg connect ch.port_out->grav.port_out and grav.port_in->pump.port_in |
| 1% cancellation tolerance for GRAV-02 | Channel uses rho(T_mid), Gravity uses rho(T_in) — density evaluated at different temperatures, so machine-precision cancellation not achievable |

### Key Decisions (v0.2 Phase 7)

| Decision | Rationale |
|----------|-----------|
| Resistor uses linear pressure drop without abs() | Bidirectional by design; positive mdot = flow in = pressure drop from in to out; matches Python STREAM semantics |
| mtkcompile with fully_determined=false for isolated component tests | Allows testing individual components before wiring into a closed loop |

### Pending Todos

None.

### Blockers/Concerns

- Flow reversal with ifelse() — convergence in multi-branch networks is untested (NET phases may surface issues)

### Notes

- COMP-02 (HeatExchanger public) is trivial: renames/exposes existing _make_temp_bc
- NET-02/NET-03 (Cube problem) require NET-01 (Resistor) to exist first
- ChannelAndContacts (Phase 9) defines the interface contract that HeatDiffusion (v0.3) will connect to

---

## Session Continuity

**Last session:** 2026-03-13T14:43:04.289Z
**Stopped at:** Completed 07-network-architecture-01-PLAN.md
**Next action:** Phase 7 plan 01 complete. Continue with plan 02 (Cube multi-branch network problem).

---

*Last updated: 2026-03-13 — v0.2 roadmap created*
