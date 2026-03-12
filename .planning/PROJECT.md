# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop (pump → channel → back to pump) validated against Python STREAM to within 1%. The MTK architecture is proven sound: acausal connect(), symbolic fluid properties, mtkcompile, and Sundials IDA all work together correctly on a real thermal-hydraulic system.

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

(None defined — planning v0.2)

### Out of Scope

- Point kinetics — adds neutronics complexity that obscures thermal-hydraulic architecture; validate separately
- HeatDiffusion (2D solid) — independent sub-system; validate in its own milestone
- Subcooled boiling, natural convection — not needed to validate the core loop
- Multiple HTC / friction correlations — one each is enough for v0.1; swappability is a v1.0 concern
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Multi-loop / multi-branch networks — single loop first; Kirchhoff complexity for later
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water only for v0.1

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- MTK architecture validated: acausal connect() + mtkcompile + Sundials IDA replaces Aggregator pattern
- Friction and Gravity are exported components but are not wired into the assembled loop (Friction handled inside Channel; Gravity needs v0.2 design — this is known tech debt)
- Flow reversal: currently uses `ifelse()` in Channel; tanh-smoothing deferred until needed
- Known v0.2 prep items: wire Friction/Gravity into loop, expose g_acc in build_loop API, consider wrapper struct architecture for solver API

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use MTK from day one (not raw DiffEq) | Avoid writing Python-style architecture in Julia; hit MTK learning curve on 30 equations not 300 | ✓ Good — mtkcompile reduced 30 eqs to ~15 unknowns; symbolic Jacobians worked out of the box |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere in equations; ForwardDiff-compatible | ✓ Good — zero plumbing, just call rho_water(T) anywhere |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh if Jacobian issues arise | ✓ Good — no convergence issues at v0.1 scale |
| Single closed loop as v0.1 target | Validates architecture before committing to 10k+ lines of porting | ✓ Good — proved the approach works; v0.2 can port more components |
| Friction handled inside Channel (not as wired component) | Reduces DAE complexity for v0.1 | ⚠ Revisit — Friction+Gravity as orphaned exports is confusing; v0.2 should wire them or document the pattern |
| No Python adapter in early milestones | Avoid complexity that muddies architectural validation | — Pending |

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only for v0.1; other fluids deferred
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it
- **Scope gate**: v0.1 intentionally minimal — nothing added until single-loop proof-of-concept validated

---
*Last updated: 2026-03-13 after v0.1 milestone*
