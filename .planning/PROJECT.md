# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop validated against Python STREAM to within 1%. v0.2 extended the architecture to multi-branch networks (Cube problem), gravity in vertical loops, flow inertia, public HeatExchanger, and ChannelAndContacts as the per-cell thermal interface for fuel-plate coupling. v0.3 will deliver HeatDiffusion: a 2D finite-difference fuel plate that couples to ChannelAndContacts on both sides.

## Core Value

A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.

## Requirements

### Validated

- ✓ Julia package skeleton (Project.toml, src/, test/) with MTK, DiffEq, Sundials — v0.1
- ✓ Light water fluid properties (@register_symbolic) callable from any MTK equation — v0.1
- ✓ FlowPort and ThermalPort connectors with correct MTK acausal semantics — v0.1
- ✓ Channel component: n-cell 1D FVM, Dittus-Boelter HTC, Darcy-Weisbach dP — v0.1
- ✓ Pump component: constant pressure rise across FlowPorts — v0.1
- ✓ Friction component: Darcy-Weisbach with Blasius factor (standalone, not in loop) — v0.1
- ✓ Gravity component: hydrostatic pressure term (standalone, not in loop) — v0.1
- ✓ Single closed loop assembles, compiles with mtkcompile, and runs — v0.1
- ✓ Steady-state T_out and ṁ match Python STREAM within 1% — v0.1 (T_out=327.79 K, ṁ=0.609 kg/s)
- ✓ Transient solver with step-change in wall temperature — v0.1
- ✓ Automated test suite comparing against Python STREAM reference outputs — v0.1
- ✓ Gravity term validated in a vertical closed loop (Channel g_acc + Gravity on return leg) — v0.2
- ✓ Multi-branch network (Cube problem: 12 Resistors via MTK connect()) solves with correct flow distribution — v0.2
- ✓ Resistor component: linear hydraulic resistor dP = R·ṁ — v0.2
- ✓ Inertia component: dp ~ (L/A)·D(ṁ), validated against Python STREAM RL-decay transient — v0.2
- ✓ HeatExchanger public component (fixed outlet temperature, no pressure drop) — v0.2
- ✓ ChannelAndContacts: n-cell ThermalPort array for per-cell wall temperature coupling — v0.2

### Active

- [ ] HeatDiffusion component: 2D (x-z) finite-difference fuel plate with T(t)[1:nx, 1:nz] indexed MTK variables
- [ ] HeatDiffusion exposes thermal_left[1:nz] and thermal_right[1:nz] ThermalPort arrays for per-cell coupling
- [ ] ChannelAndContacts upgraded: thermal_ports[1:n] replaced by thermal_left[1:n] + thermal_right[1:n]; q_wall[i] = left + right contributions
- [ ] Unconnected ThermalPort sides default to adiabatic (Q_flow=0 from MTK acausal semantics — no explicit flag needed)
- [ ] Coupled HeatDiffusion + ChannelAndContacts system solves and matches Python STREAM MTR reference case
- [ ] Asymmetric left/right heating (two independent channels on either side of a plate) works without model changes
- [ ] v0.2 tech debt: remove dead t_inlet parameter from _channel_base_eqs, add direct THERM-03 assertion, fix doc cosmetic in 09-01-SUMMARY.md

### Out of Scope

- Point kinetics — v0.4+ after thermal-hydraulic architecture is fully established
- Additional HTC correlations (laminar, Marco-Han, etc.) — v0.4+; minimal rewrite when added
- Additional friction correlations (Colebrook, regime-dependent) — v0.4+; same as HTC
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water only through v0.3
- Wrapper struct for solver API (SteadySolution, TransientSolution) — ODESolution is sufficient; defer unless usage patterns demand it
- Subcooled boiling, natural convection — not needed for current validation targets

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- **v0.2 shipped** 2026-03-13 — 818 src LOC, 545 test LOC, 86 tests, 4 phases, 7 plans
- **v0.3 starting** — HeatDiffusion (2D fuel plate + ChannelAndContacts coupling)
- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- MTK architecture validated through two milestones: acausal connect() + mtkcompile + Sundials IDA replaces Aggregator pattern
- Friction is handled inside Channel (Darcy-Weisbach inline) — no separate Friction component in loop
- Gravity is a standalone component; for vertical loops, set g_acc in Channel + wire Gravity on return leg (reversed from flow direction)
- Multi-branch networks use MTK variadic connect() for junctions — no Junction component needed; Kirchhoff equations generated automatically
- ChannelAndContacts (per-cell ThermalPorts) is the interface contract that HeatDiffusion (v0.3) will connect to
- Tech debt from v0.2: `_channel_base_eqs` accepts dead `t_inlet` parameter (no correctness impact); THERM-03 validated via proxy; cosmetic doc issue in 09-01-SUMMARY.md

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use MTK from day one (not raw DiffEq) | Avoid writing Python-style architecture in Julia; hit MTK learning curve on 30 equations not 300 | ✓ Good — mtkcompile reduced 30 eqs to ~15 unknowns; symbolic Jacobians worked out of the box |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere in equations; ForwardDiff-compatible | ✓ Good — zero plumbing, just call rho_water(T) anywhere |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh if Jacobian issues arise | ✓ Good — no convergence issues at v0.2 scale |
| Single closed loop as v0.1 target | Validates architecture before committing to 10k+ lines of porting | ✓ Good — proved the approach works; v0.2 ported more components |
| Friction handled inside Channel (not as wired component) | Reduces DAE complexity; friction is part of Channel's dP equation | ✓ Good — confirmed across both milestones; standalone Friction component exists for edge cases |
| Gravity: g_acc parameter in Channel + standalone Gravity on return leg | Natural MTK approach; no special loop architecture needed | ✓ Good — reversed-port wiring convention established and documented |
| build_loop is a test example, not the primary API | MTK connect()/compose() is expressive enough; no FlowGraph wrapper needed | ✓ Good — users use connect()/compose() directly |
| No Python adapter in early milestones | Avoid complexity that muddies architectural validation | — Pending |
| MTK variadic connect(a,b,c) is the junction — no Junction component needed | MTK generates Kirchhoff equations automatically; simpler topology | ✓ Good — Cube (12 Resistors, 8 nodes) proved it works at scale |
| Pressure anchor pump.port_in.P ~ 1.0e5 in multi-branch networks | Kirchhoff system leaves absolute pressure underdetermined without it | ✓ Good — required for any multi-branch network |
| Inertia uses vars=[] — MTK auto-promotes port_in.mdot as differential state | Explicit mdot state var would create overconstrained system | ✓ Good — MTK infers state from Dt(port_in.mdot) correctly |
| _channel_base_eqs accepts concrete g_acc (Float64) not MTK symbolic | dP is algebraic so concrete value works; avoids pars indexing complexity | ✓ Good — simpler than symbolic parameter passing |
| ChannelAndContacts q_wall[i] ~ thermal_ports[i].Q_flow (1:1 mapping) | Each ThermalPort covers exactly one cell — interface contract for HeatDiffusion | ✓ Good — defines the v0.3 coupling contract |

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only for v0.1-v0.3; other fluids deferred to v0.4+
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it
- **Scope gate**: v0.3 is exclusively HeatDiffusion (2D fuel plate + ChannelAndContacts coupling); PointKinetics and correlations are v0.4+

## Current Milestone: v0.3 HeatDiffusion

**Goal:** Implement the 2D finite-difference fuel plate (HeatDiffusion) and upgrade ChannelAndContacts to two-sided thermal coupling, validated against the Python STREAM MTR reference case.

**Target features:**
- HeatDiffusion: 2D (x-z) FD fuel plate with indexed MTK variables and two-sided ThermalPort arrays
- ChannelAndContacts: upgraded to thermal_left + thermal_right (one or both sides, adiabatic default via MTK)
- MTR reference case validation: coupled HeatDiffusion + ChannelAndContacts matches Python STREAM
- v0.2 tech debt cleanup

---
*Last updated: 2026-03-13 after v0.3 milestone start*
