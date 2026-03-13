# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop validated against Python STREAM to within 1%. v0.2 extends the architecture to multi-branch networks, gravity in vertical loops, flow inertia, and per-cell thermal coupling (ChannelAndContacts) as the foundation for future HeatDiffusion work.

## Current Milestone: v0.2 Component & Network Expansion

**Goal:** Validate multi-branch hydraulic networks via MTK connect() semantics, add the Inertia and HeatExchanger lumped components, add gravity to vertical loops, and deliver ChannelAndContacts (per-cell ThermalPort array) as the interface contract for future fuel-plate coupling.

**Target features:**
- Gravity in vertical loops (Channel g_acc + Gravity component wired in return leg)
- Junction component + multi-branch network validation (Cube problem)
- ChannelAndContacts: per-cell ThermalPort array replacing single ThermalPort
- Inertia component: dp ~ (L/A) * D(mdot) — only lumped component with an ODE state
- HeatExchanger as a public component (expose existing _make_temp_bc)

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
- ✓ Automated test suite (54 tests) comparing against Python STREAM reference outputs — v0.1

### Active

- [ ] Gravity term validated in a vertical closed loop (Channel g_acc + Gravity on return leg)
- [ ] Junction component (n-port flow splitter/merger) implemented and tested
- [ ] Multi-branch network (Cube problem) solves with correct flow distribution via MTK connect()
- [ ] ChannelAndContacts: n-cell ThermalPort array for per-cell wall temperature coupling
- [ ] Inertia component: dp ~ (L/A) * D(mdot), with test against Python STREAM
- [ ] HeatExchanger public component (fixed outlet temperature, no pressure drop)

### Out of Scope

- Point kinetics — v0.4+ after thermal-hydraulic architecture is fully established
- HeatDiffusion (2D solid fuel plate) — v0.3 milestone exclusively; ChannelAndContacts in v0.2 defines the interface it will use
- Subcooled boiling, natural convection — not needed for current validation targets
- Multiple HTC / friction correlations (laminar, Marco-Han, Colebrook, etc.) — v0.4+; minimal rewrite when added
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water only through v0.3
- Wrapper struct for solver API (SteadySolution, TransientSolution) — ODESolution is sufficient; defer unless usage patterns demand it

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- **v0.2 started** 2026-03-13
- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- MTK architecture validated: acausal connect() + mtkcompile + Sundials IDA replaces Aggregator pattern
- Friction is handled inside Channel (Darcy-Weisbach inline) — no separate Friction component in loop
- Gravity is a standalone component; for vertical loops, set g_acc in Channel + wire Gravity on return leg
- Flow reversal: uses `ifelse()` in Channel; tanh-smoothing deferred
- build_loop is a test/example utility only — not the primary API; users are expected to use connect()/compose() directly
- ChannelAndContacts (per-cell ThermalPorts) is the interface contract that HeatDiffusion (v0.3) will connect to
- Cube problem (12 resistors, 8-node topology) is the canonical multi-branch validation case; analytical solution = 5/6 R equivalent

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use MTK from day one (not raw DiffEq) | Avoid writing Python-style architecture in Julia; hit MTK learning curve on 30 equations not 300 | ✓ Good — mtkcompile reduced 30 eqs to ~15 unknowns; symbolic Jacobians worked out of the box |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere in equations; ForwardDiff-compatible | ✓ Good — zero plumbing, just call rho_water(T) anywhere |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh if Jacobian issues arise | ✓ Good — no convergence issues at v0.1 scale |
| Single closed loop as v0.1 target | Validates architecture before committing to 10k+ lines of porting | ✓ Good — proved the approach works; v0.2 can port more components |
| Friction handled inside Channel (not as wired component) | Reduces DAE complexity; friction is part of Channel's dP equation | ✓ Good — confirmed in v0.2 planning; standalone Friction component exists for other use cases |
| Gravity: g_acc parameter in Channel + standalone Gravity on return leg | Natural MTK approach; no special loop architecture needed | — Pending v0.2 validation |
| build_loop is a test example, not the primary API | MTK connect()/compose() is expressive enough; no FlowGraph wrapper needed | ✓ Good — confirmed in v0.2 planning |
| No Python adapter in early milestones | Avoid complexity that muddies architectural validation | — Pending |

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only for v0.1; other fluids deferred
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it
- **Scope gate**: v0.2 focuses on network architecture + per-cell thermal interface; no HeatDiffusion until v0.3

---
*Last updated: 2026-03-13 after v0.2 milestone start*
