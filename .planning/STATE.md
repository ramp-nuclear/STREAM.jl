---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Component & Network Expansion
status: completed
stopped_at: Completed 09-channelandcontacts-02-PLAN.md
last_updated: "2026-03-13T19:03:40.391Z"
last_activity: 2026-03-13 — Phase 9 plan 02 executed (ChannelAndContacts + ChannelHeatFlux GREEN, 86 tests passing)
progress:
  total_phases: 4
  completed_phases: 4
  total_plans: 7
  completed_plans: 7
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

Phase: 9 of 9 (ChannelAndContacts) — fourth v0.2 phase — COMPLETE
Plan: 02 (complete — GREEN implementation)
Status: v0.2 milestone complete. All 10 requirements (GRAV-01/02, NET-01/02/03, COMP-01/02, THERM-01/02/03) satisfied.
Last activity: 2026-03-13 — Phase 9 plan 02 executed (ChannelAndContacts + ChannelHeatFlux GREEN, 86 tests passing)

Progress: [██████████] 100% (Phase 9 plan 02 of 2 complete — v0.2 done)

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
| Phase 07 P02 | 3 | 1 tasks | 3 files |
| Phase 08-inertia-and-heatexchanger P01 | 19 | 2 tasks | 3 files |
| Phase 08-inertia-and-heatexchanger P02 | 4 | 1 tasks | 3 files |
| Phase 09-channelandcontacts P01 | 8 | 2 tasks | 3 files |
| Phase 09-channelandcontacts P02 | 7 | 2 tasks | 1 files |

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
| MTK variadic connect(a,b,c) is the junction — no Junction component needed | MTK generates Kirchhoff equations automatically; simpler topology |
| Pressure anchor pump.port_in.P ~ 1.0e5 required for cube network | Body-diagonal Kirchhoff system leaves absolute pressure underdetermined |
| Initial guess mdot_guess = mdot_analytical/3 sufficient for KINSOL | Source branch symmetry: each of 3 branches from corner 0 carries one-third |

### Key Decisions (v0.2 Phase 8 Plan 01)

| Decision | Rationale |
|----------|-----------|
| Inertia uses vars=[] — MTK auto-promotes port_in.mdot as differential state | Explicit mdot state var would create overconstrained system; MTK infers state from Dt(port_in.mdot) appearance |
| Pure pressure RL circuit: fully_determined=false + check_length=false + T ICs | T stream vars are free (no heat exchange); ODEProblem requires all unknowns have ICs even if T equations absent |

### Key Decisions (v0.2 Phase 8 Plan 02)

| Decision | Rationale |
|----------|-----------|
| HeatExchanger is exact rename of _make_temp_bc — no behavior change | Component already correct; goal is public API exposure, not reimplementation |
| Local variable `bc` unchanged in build_loop call sites | Connections reference bc.port_in/bc.port_out — only constructor name changes |

### Key Decisions (v0.2 Phase 9 Plan 01)

| Decision | Rationale |
|----------|-----------|
| RED stub: minimal FlowPort-only System sufficient for callable/mtkcompile pass | compose(System(eqs, t, [], []; name=name), port_in, port_out) passes structural tests while correctly failing behavioral assertions |
| THERM-03 uses build_loop as Channel reference + inline compose() for ChannelHeatFlux | No new build_ helper needed; inline wiring is the intended Pattern for ChannelHeatFlux usage |
| build_loop signature confirmed to accept n, L_ch, D_ch, A_ch, dP_pump, T_inlet, T_wall | THERM-03 test can call build_loop directly without any workarounds |

### Key Decisions (v0.2 Phase 9 Plan 02)

| Decision | Rationale |
|----------|-----------|
| _channel_base_eqs accepts concrete g_acc=g (Float64) not MTK symbolic | dP is algebraic so concrete value works; avoids pars[4] indexing complexity |
| q_wall[i] ~ thermal_ports[i].Q_flow (1:1 mapping, not /n) | Each ThermalPort covers exactly one cell — interface contract for HeatDiffusion v0.3 |
| Q_wall_total observable sums all thermal_ports[i].Q_flow | Convenient total for diagnostics and downstream coupling |
| ChannelHeatFlux q_wall[i] uses direct formula h_tc*pi*Dh*dz*(T_wall_p - T[i]) | No ThermalPorts in this variant; formula is algebraically equivalent |
| v0.2 milestone complete — all 10 requirements (GRAV, NET, COMP, THERM) satisfied | ChannelAndContacts defines the per-cell interface for HeatDiffusion (v0.3) |

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

**Last session:** 2026-03-13T18:59:46.045Z
**Stopped at:** Completed 09-channelandcontacts-02-PLAN.md
**Next action:** v0.2 milestone complete. All 10 requirements satisfied. Begin v0.3 planning: HeatDiffusion (2D fuel plate + ChannelAndContacts coupling). ChannelAndContacts.thermal1..thermalN is the ready interface.

---

*Last updated: 2026-03-13 — v0.2 roadmap created*
