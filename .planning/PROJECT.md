# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop validated against Python STREAM within 1%. v0.2 extended the architecture to multi-branch networks, gravity in vertical loops, flow inertia, public HeatExchanger, and ChannelAndContacts as the per-cell thermal interface for fuel-plate coupling. v0.3 delivered HeatDiffusion — a 2D finite-difference fuel plate that couples to ChannelAndContacts on both sides — and validated the full MTR fuel assembly geometry against Python STREAM within 1%.

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
- ✓ ChannelAndContacts upgraded: thermal_left[1:n] + thermal_right[1:n] dual ports; q_wall[i] = left + right; adiabatic default verified — v0.3
- ✓ v0.2 tech debt cleared: t_inlet removed from _channel_base_eqs, THERM-03 direct assertion, DEBT-03 doc fix — v0.3
- ✓ HeatDiffusion component: 2D FD fuel plate with T(t)[1:nz, 1:nx] MTK state, _diffusion_eqs helper, dual ThermalPort arrays, power_shape + power source — v0.3
- ✓ HeatDiffusion one-sided adiabatic default: unconnected thermal_right.Q_flow == 0 (MTK acausal semantics) — v0.3
- ✓ MTR fuel assembly validated: HeatDiffusion + 2× ChannelAndContacts symmetric/asymmetric/one-sided, ≤1% rtol vs Python STREAM — v0.3
- ✓ PipeGeometry struct with circular and rectangular outer constructors; Channel/ChannelHeatFlux/ChannelAndContacts accept PipeGeometry — v0.3

### Active

- [ ] Transient HeatDiffusion validated against analytical 1D slab solution
- [ ] Two HeatDiffusion instances connected to one ChannelAndContacts (thermal_left + thermal_right both active)
- [ ] One-sided connection quantitative T_plate_center assertion (analytical energy balance)
- [ ] `symmetric_plate(channel, fuel)` — pre-wired symmetric MTR subsystem
- [ ] `plate(ch_left, ch_right, fuel)` — two-channel plate assembly
- [ ] `one_sided_connection(channel, fuel, side=:left)` — single-side connection helper
- [ ] `compose_systems(sys_a, sys_b, connections)` — composable subsystem assembly
- [ ] `wet_perimeter` field in PipeGeometry; Dh = 4A/wet_perimeter
- [ ] `constant_Nusselt`, `laminar_friction`, `regime_dependent` correlation pluggables
- [ ] `Pump(mdot0=...)` fixed-flow boundary condition mode

- [ ] `@observed` Re, Nu, h_tc, T_wall in ChannelAndContacts
- [ ] `check_gravity_mismatch(sys)` helper
- [ ] `port(sys, :thermal_left, i)` helper

### Out of Scope

- Point kinetics — v0.4+ after thermal-hydraulic architecture is fully established
- Additional HTC correlations (laminar, Marco-Han, etc.) — v0.4+; minimal rewrite when added
- Additional friction correlations (Colebrook, regime-dependent) — v0.4+
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water only through v0.3
- Wrapper struct for solver API (SteadySolution, TransientSolution) — ODESolution is sufficient
- Subcooled boiling, natural convection — not needed for current validation targets

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- **v0.2 shipped** 2026-03-13 — 818 src LOC, 545 test LOC, 86 tests, 4 phases, 7 plans
- **v0.3 shipped** 2026-03-14 — ~1,003 Julia LOC, 161 tests, 4 phases (10-12.1), 8 plans
- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- MTK architecture validated through three milestones: acausal connect() + mtkcompile + Sundials IDA replaces Aggregator pattern
- Friction is handled inside Channel (Darcy-Weisbach inline) — no separate Friction component in loop
- Gravity: g_acc parameter in Channel + standalone Gravity on return leg (reversed-port convention)
- Multi-branch networks use MTK variadic connect() for junctions — no Junction component needed
- PipeGeometry struct encapsulates L, Dh, A, heated_parts; rectangular MTR geometry uses `2·y` not `π·Dh/2`
- HeatDiffusion axis convention: rows=axial (z), cols=lateral (x) — matching Python STREAM

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use MTK from day one (not raw DiffEq) | Avoid writing Python-style architecture in Julia; hit MTK learning curve on 30 equations not 300 | ✓ Good — mtkcompile reduced 30 eqs to ~15 unknowns; symbolic Jacobians worked out of the box |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere in equations; ForwardDiff-compatible | ✓ Good — zero plumbing, just call rho_water(T) anywhere |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh if Jacobian issues arise | ✓ Good — no convergence issues at v0.3 scale |
| Single closed loop as v0.1 target | Validates architecture before committing to 10k+ lines of porting | ✓ Good — proved the approach works |
| Friction handled inside Channel (not as wired component) | Reduces DAE complexity; friction is part of Channel's dP equation | ✓ Good — confirmed across all milestones |
| Gravity: g_acc parameter in Channel + standalone Gravity on return leg | Natural MTK approach; no special loop architecture needed | ✓ Good — reversed-port wiring convention established and documented |
| build_loop is a test example, not the primary API | MTK connect()/compose() is expressive enough; no FlowGraph wrapper needed | ✓ Good — users use connect()/compose() directly |
| No Python adapter in early milestones | Avoid complexity that muddies architectural validation | — Pending |
| MTK variadic connect(a,b,c) is the junction — no Junction component needed | MTK generates Kirchhoff equations automatically; simpler topology | ✓ Good — Cube (12 Resistors, 8 nodes) proved it works at scale |
| Pressure anchor pump.port_in.P ~ 1.0e5 in multi-branch networks | Kirchhoff system leaves absolute pressure underdetermined without it | ✓ Good — required for any multi-branch network |
| Inertia uses vars=[] — MTK auto-promotes port_in.mdot as differential state | Explicit mdot state var would create overconstrained system | ✓ Good — MTK infers state from Dt(port_in.mdot) correctly |
| ChannelAndContacts thermal_left[1:n] + thermal_right[1:n] dual ports | Each side is an independent ThermalPort array; unconnected side defaults adiabatic via MTK | ✓ Good — HeatDiffusion connects symmetrically to both sides |
| PipeGeometry struct with heated_parts::NTuple{2,Float64} | Rectangular MTR geometry uses `2·y` heated perimeter, not `π·Dh/2`; struct makes this explicit | ✓ Good — fixed 4.46× error; geometry is now caller-specified not hardcoded |
| Hardcode Python STREAM reference constants in Julia tests | Avoids test-time Python dependency; constants stable once geometry is locked | ✓ Good — VAL-01/02/03 are pure Julia tests with 1% rtol assertions |

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only for v0.1-v0.3; other fluids deferred to v0.4+
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it
- **Scope gate**: v0.4 is point kinetics + additional correlations + composable subsystem assembly

## Current Milestone: v0.4 Composability & Physics

**Goal:** Make Julia STREAM ergonomic for real reactor assembly workflows and physically correct for the full MTR operating envelope (including laminar flow).

**Target features:**
- Composition helpers: `symmetric_plate()`, `plate()`, `one_sided_connection()`, `compose_systems()`
- Physics accuracy: `wet_perimeter` Dh fix, laminar correlations, fixed-flow Pump
- Validation: transient HeatDiffusion, two-plate CAC, one-sided quantitative assertion
- Developer QoL: `@observed` variables, `check_gravity_mismatch()`, `port()` helper

---
*Last updated: 2026-03-14 after v0.4 milestone start*
