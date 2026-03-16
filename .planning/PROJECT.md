# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop validated against Python STREAM within 1%. v0.2 extended the architecture to multi-branch networks, gravity in vertical loops, flow inertia, public HeatExchanger, and ChannelAndContacts as the per-cell thermal interface for fuel-plate coupling. v0.3 delivered HeatDiffusion — a 2D finite-difference fuel plate that couples to ChannelAndContacts on both sides — and validated the full MTR fuel assembly geometry against Python STREAM within 1%. v0.4 corrected MTR physics (hydraulic diameter 10 mm → 2.5 mm), added pluggable HTC/friction correlations with laminar regime support, and introduced MTK composition helpers that collapse 10-20 line manual wiring sequences into single calls. v0.5 reorganized the codebase to the canonical CLAUDE.md file layout, split the monolithic test file into 13 focused modules, added Julia docstrings to all 28 exported names, and expanded CLAUDE.md with rationale and MTK patterns.

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
- ✓ PipeGeometry redesigned with `wet_perimeter` field; Dh = 4A/wet_perimeter; MTR hydraulic diameter corrected 10 mm → 2.5 mm — v0.4
- ✓ Pump dual-mode dispatch: `Pump(mdot0=...)` for fixed-flow, `Pump(dP_pump=...)` for fixed-pressure — v0.4
- ✓ Six pluggable correlation functions: `constant_Nusselt`, `dittus_boelter`, `laminar_friction`, `blasius_friction`, `rectangular_laminar_correction`, `regime_dependent` — v0.4
- ✓ ChannelAndContacts 10 MTK `@observed` variables: Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right — v0.4
- ✓ `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems` composition helpers in `src/helpers.jl` — v0.4
- ✓ `port(sys, :thermal_left, i)` and `check_gravity_mismatch(sys)` QoL helpers — v0.4
- ✓ Transient HeatDiffusion validated against Fourier series analytical solution (≤1% rtol, 4 time checkpoints) — v0.4
- ✓ Two-plate one-channel topology (both thermal_left + thermal_right active) solved and energy-balanced — v0.4
- ✓ One-sided T_max assertion from analytical energy balance (VAL-03; Python bug documented) — v0.4
- ✓ Source reorganized to canonical layout: `geometry.jl`, `src/components/` (6 files), `src/physical_models/`, `src/composition/`, `src/examples.jl` — v0.5
- ✓ Monolithic `runtests.jl` split into 13 self-contained `test_*.jl` files matching CLAUDE.md layout — v0.5
- ✓ `solve_transient` converted to keyword-only signature; all exported solvers now keyword-only — v0.5
- ✓ All 28 exported names have structured Julia docstrings (`# Arguments`, `# Ports`, `# Returns`) — v0.5
- ✓ CLAUDE.md rewritten with **Why:** rationale after every rule and MTK Patterns reference section — v0.5
- ✓ `Project.toml` bumped to `0.5.0`; `ChannelHeatFlux` and `ConstantTemperature` confirmed exported, tested, documented — v0.5

### Active

<!-- v0.6+ — next milestone features go here -->

### Out of Scope

- Point kinetics — thermal-hydraulic architecture now proven through v0.5; defer to v0.6+
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water sufficient
- Wrapper struct for solver API (SteadySolution, TransientSolution) — ODESolution is sufficient
- Subcooled boiling, natural convection — not needed for current validation targets
- `channel_outputs()` helper — `@observed` makes `sol[sys.ch.Re, :]` work directly

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- **v0.2 shipped** 2026-03-13 — 818 src LOC, 545 test LOC, 86 tests, 4 phases, 7 plans
- **v0.3 shipped** 2026-03-14 — ~1,003 Julia LOC, 161 tests, 4 phases (10-12.1), 8 plans
- **v0.4 shipped** 2026-03-16 — ~3,268 Julia LOC, 4 phases (13-16), 7 plans; 15 requirements complete
- **v0.5 shipped** 2026-03-16 — ~3,750 Julia LOC (src + test), 3 phases (17-19), 6 plans; 15 requirements complete; canonical file layout, full docstrings, 13-file test suite
- Python STREAM lives at ~/projects/STREAM and is the reference implementation for all validation
- MTK architecture validated through five milestones: acausal connect() + mtkcompile + Sundials IDA replaces Aggregator pattern
- Friction is handled inside Channel (Darcy-Weisbach inline) — no separate Friction component in loop
- Gravity: g_acc parameter in Channel + standalone Gravity on return leg (reversed-port convention)
- Multi-branch networks use MTK variadic connect() for junctions — no Junction component needed
- PipeGeometry struct encapsulates L, Dh, A, wet_perimeter, heated_parts; Dh = 4A/wet_perimeter
- HeatDiffusion axis convention: rows=axial (z), cols=lateral (x) — matching Python STREAM
- Correlation functions are plain Julia closures (not @register_symbolic) — MTK traces them symbolically
- Composition helpers: `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems` in src/composition/helpers.jl
- **File structure standard** fully in effect as of v0.5 — see CLAUDE.md for canonical layout
- **v1.0 target** — first public release; ~85–100% of Python STREAM capabilities
- **Long-term fluid design** — AbstractFluid + multiple dispatch for v0.6+ multi-fluid support; keep @register_symbolic globals until then

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
| PipeGeometry_rectangular/PipeGeometry_circular factory functions; old sentinel-kwargs constructor deleted | MethodError forces migration; no shim needed | ✓ Good — clean API; all call sites migrated with no backward-compat debt |
| Correlation functions as plain Julia closures (not @register_symbolic) | MTK traces arithmetic symbolically; @register_symbolic is only for opaque functions | ✓ Good — cleaner API, works for all correlation types |
| `regime_dependent` uses `ifelse()` for Re-based switching | Hard if-branch would create solver discontinuity | ✓ Good — same pattern as flow reversal; no convergence issues |
| Re/Nu/velocity/Pe moved to `@observed`; h_tc stays as MTK unknown | h_tc is referenced in energy balance equations; Re/Nu/v are diagnostic-only | ✓ Good — solver unknown vector shrinks; diagnostics still accessible post-solve |
| Fixed-flow Pump has no pressure equation; caller anchors P | Mass flow constraint + pressure anchor is exactly determined | ✓ Good — PHY-05 pattern works; forced-flow scenarios now ergonomic |
| VAL-03 T_out assertion removed; energy balance is truth | Python `one_sided_connection` distributes heat to both faces (bug); Julia correct | ✓ Good — Julia energy balance confirmed analytically |
| Composition helpers infer `n` from CAC thermal_left subsystem count | Safe without explicit parameter inspection; fails early if CAC compiled | ✓ Good — ergonomic; no need to pass n explicitly to helpers |
| Split test suite: one `test_*.jl` per source area | Each file has independent `using` blocks and runs in isolation; mirrors src/ layout | ✓ Good — TEST-01 confirmed; CLAUDE.md layout now fully mirrored |
| CLAUDE.md includes **Why:** rationale for every rule | Rules without context get ignored or broken; rationale enables judgment at edge cases | ✓ Good — QOL-03 complete; MTK Patterns section added as reference |
| `solve_transient` keyword-only aligns with project-wide convention | Consistent API: no function mixes positional and keyword arguments | ✓ Good — QOL-01 complete; MethodError guard now enforced |

## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only through v0.4; other fluids deferred
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it

---
*Last updated: 2026-03-16 after v0.5 milestone*
