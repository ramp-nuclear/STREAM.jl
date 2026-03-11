# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

The initial milestone (v0.1) is a proof-of-concept: a single forced-convection coolant loop (pump → friction → heated channel → back to pump) that validates the MTK architecture, the connector design, and the fluid property system against known Python STREAM results.

## Core Value

A working forced-convection loop in MTK that matches Python STREAM's steady-state and transient results, proving the Julia architecture is sound before any large-scale porting begins.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] FlowPort and ThermalPort connectors defined with correct MTK acausal semantics
- [ ] Light water fluid properties registered as symbolic functions (@register_symbolic), callable from any component
- [ ] Channel component: n-cell 1D finite-volume coolant discretization, single-phase, Dittus-Boelter HTC
- [ ] Pump component: constant pressure rise
- [ ] Friction component: Darcy-Weisbach with Blasius friction factor (turbulent)
- [ ] Gravity component: hydrostatic pressure term
- [ ] Single closed loop assembles and compiles with MTK (pump → friction → channel)
- [ ] Steady-state solution matches Python STREAM within 1%
- [ ] Transient simulation (step change in channel power) qualitatively matches Python STREAM
- [ ] Basic test suite comparing Julia results to Python STREAM reference outputs

### Out of Scope

- Point kinetics — adds neutronics complexity that obscures the thermal-hydraulic architecture; validate separately
- HeatDiffusion (2D solid) — independent sub-system; validate in its own milestone
- Subcooled boiling, natural convection — not needed to validate the core loop
- Multiple HTC / friction correlations — one each is enough for v0.1; swappability is a v1.0 concern
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Multi-loop / multi-branch networks — single loop first; Kirchhoff complexity for later
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water only for v0.1

## Context

- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- Python STREAM uses a hand-rolled DAE system: Calculation protocol + Aggregator orchestrator + DiGraph coupling + SUNDIALS IDA solver
- Key insight driving the rewrite: MTK's mtkcompile reduces 200-equation systems to ~50 actual unknowns via algebraic tearing; symbolic Jacobians replace numerical finite-differencing; acausal connect() replaces the manual external variable routing table in the Aggregator
- Fluid properties are registered once at the package level via @register_symbolic (e.g., ρ_water(T), cp_water(T)). Any component uses them by name in equations — no passing, no injection. MTK differentiates through them via ForwardDiff.
- Flow reversal handling: start with ifelse() (simplest, creates non-smooth Jacobians). Move to tanh-smoothing if solver convergence suffers. This is a known rough edge in Python STREAM too.
- The primary developer has limited Julia experience and no prior MTK experience. Code is written autonomously by Claude and reviewed iteratively.
- MTK compile time for realistic systems is an open question — v0.1 will benchmark this on a ~30-equation system before any large-scale porting

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl. MTK from day one — no raw DiffEq fallback planned.
- **Fluid**: Light water only for v0.1
- **Validation**: All results must be compared against Python STREAM running on identical inputs. <1% deviation for steady state; qualitative match for transients.
- **Architecture**: No Python-style Aggregator pattern. MTK's compose() + connect() + mtkcompile() replaces it entirely.
- **Scope gate**: v0.1 is intentionally minimal. Nothing gets added until the single-loop proof-of-concept is validated and feels good to use.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use MTK from day one (not raw DiffEq) | Avoid writing Python-style architecture in Julia; hit the MTK learning curve on 30 equations not 300; discover compile time issues early | — Pending |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere in equations without injection; ForwardDiff-compatible; fluid-agnostic by design | — Pending |
| Flow reversal: start with ifelse() | Simplest implementation; can migrate to tanh-smoothing if Jacobian issues arise | — Pending |
| Single closed loop as v0.1 target | Validates architecture before committing to 10k+ lines of porting work | — Pending |
| No Python adapter in early milestones | Avoid complexity that muddies the architectural validation; bridge is a post-v1.0 concern | — Pending |

---
*Last updated: 2026-03-12 after initialization*
