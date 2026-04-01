# STREAM.jl

## What This Is

STREAM.jl is a Julia rewrite of the Python package STREAM (System Thermohydraulics for Reactor Evaluation, Analysis & Modeling) — a nuclear reactor thermal-hydraulics simulation code. It models heat evacuation in reactor systems through coupled differential-algebraic equations, using ModelingToolkit.jl (MTK) as the core symbolic modeling engine instead of the hand-rolled Aggregator+DAE approach used in Python STREAM.

v0.1 shipped a single forced-convection coolant loop validated against Python STREAM within 1%. v0.2 extended the architecture to multi-branch networks, gravity in vertical loops, flow inertia, public HeatExchanger, and ChannelAndContacts as the per-cell thermal interface for fuel-plate coupling. v0.3 delivered HeatDiffusion — a 2D finite-difference fuel plate that couples to ChannelAndContacts on both sides — and validated the full MTR fuel assembly geometry against Python STREAM within 1%. v0.4 corrected MTR physics (hydraulic diameter 10 mm → 2.5 mm), added pluggable HTC/friction correlations with laminar regime support, and introduced MTK composition helpers that collapse 10-20 line manual wiring sequences into single calls. v0.5 reorganized the codebase to the canonical CLAUDE.md file layout, split the monolithic test file into 13 focused modules, added Julia docstrings to all 28 exported names, and expanded CLAUDE.md with rationale and MTK patterns. v0.6 delivered flow reversal systems: sign-safe channel components with ifelse() upwinding, thermal expansion coefficient and Elenbaas natural convection HTC, time-varying Pump callable dispatch, Flapper check-valve with MTK continuous events, and a validated loss-of-flow transient with physically correct 4-node bypass topology covering forced flow, pump coastdown, flow reversal, Flapper opening, and established natural circulation. v0.7 delivered the full safety physics and pressure field suite: per-cell absolute pressure P[i]/dp[i], sat_temperature @register_symbolic, T_sat[i]/T_ONB[i] observables, distributed momentum ODE in all channel variants, subcooled boiling (McAdams + Bergles-Rohsenow + in-loop SCB correction), nuclear safety threshold analysis framework (8 physics functions + ChannelState + threshold_analysis dispatcher + chfr factory), and complete HTC/friction correlation library (Marco-Han, developing/fully-developed laminar factories, maximal_htc combinator, Colebrook-White turbulent friction, viscosity correction) with htc/ + friction/ subdirectory split.

## Next Milestone: v0.8 (TBD)

**Previous milestone:** v0.7 Safety Physics & Pressure Field — shipped 2026-04-01

See `.planning/MILESTONES.md` for full v0.7 details.

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
- ✓ `regime_dependent` extended with NC detection: Gr/Re² > 1 switches to `htc_natural`; `Gr_over_Re2[i]` observable added to `ChannelAndContacts` and `ChannelHeatFlux`; `build_loop_lof_bypass` wires Elenbaas NC HTC — v0.6
- ✓ VAL-02 NC temperature-rise assertion passes; NC dT matches Elenbaas analytical estimate within 30% rtol (actual ratio 0.997) — v0.6
- ✓ All channel types (Channel, ChannelAndContacts, ChannelHeatFlux) sign-safe: ifelse() upwinding selects upstream T by mdot sign; abs(mdot) in Re; port_in.T ~ T[1] stream equation corrected — v0.6
- ✓ `beta_water(T)` thermal expansion coefficient, @register_symbolic, validated at 3 reference temperatures — v0.6
- ✓ `Gr`, `Ra` dimensionless number utilities; 4-arg HTC interface (Re, Pr, T_bulk, T_wall) extended to all correlations and channel components — v0.6
- ✓ `elenbaas_nusselt(Ra, b, L)` Elenbaas 1942 parallel-plate natural convection; `elenbaas_htc(; b, L, Dh, g)` factory returning pluggable 4-arg closure — v0.6
- ✓ `Pump(dP_pump::Any; name)` callable dispatch via MTK `@parameters (dP_pump_fn::FType)(..)` pattern; `solve_transient` redesigned to positional API matching Python STREAM — v0.6
- ✓ `Flapper` check-valve: C1 smooth ramp (Hermite cubic), MTK SymbolicContinuousCallback latch (T_open=1e30 sentinel, affect_neg fires on downward crossing), wired via plain algebraic equation — v0.6
- ✓ `solve_transient` accepts optional `callbacks` keyword for user-supplied DifferentialEquations.jl events alongside MTK-native Flapper events — v0.6
- ✓ Loss-of-flow transient validated end-to-end via `build_loop_lof_bypass`: 4-node bypass topology (real junctions, parallel channel/Flapper paths, standalone Inertia), energy balance <0.09% rtol, natural circulation established — v0.6
- ✓ All public functions migrated from keyword-only to positional + multiple dispatch where argument types differ (6 signatures: Resistor, Gravity, Inertia, HeatExchanger, ConstantTemperature, laminar_friction) — v0.6
- ✓ Per-cell absolute pressure P[i] as observed variables in all channel variants; dP refactored to exact per-cell sum — v0.7
- ✓ sat_temperature(P) @register_symbolic fluid function (Simantov equation) — v0.7
- ✓ T_sat[i], T_ONB[i] as @observed in ChannelAndContacts and ChannelHeatFlux — v0.7
- ✓ Distributed momentum ODE (L/A)*Dt(mdot) in all three channel variants; P[i] with inertia correction; PRES-05..12 transient tests passing — v0.7
- ✓ McAdams and Bergles-Rohsenow subcooled boiling heat flux correlations; partial_SCB_correction and regime_dependent_q_scb factory — v0.7
- ✓ In-loop SCB correction in ChannelAndContacts (ifelse on T_wall >= T_ONB); backward compatible with skip_htc kwarg in _channel_base_eqs — v0.7
- ✓ Nuclear safety threshold analysis: 8 physics functions (Bergles-Rohsenow T_ONB, q_OFI Whittle-Forgan, q_OSV Saha-Zuber, q_CHF Sudo-Kaminaga/Mirshak/Fabrega, twall_limit) — v0.7
- ✓ ChannelState struct + threshold_analysis() dispatcher + chfr() factory + 8 pre-built analysis wrappers; _extract_channel_state with ArgumentError precondition guard — v0.7
- ✓ Marco_Han_Nusselt rectangular duct laminar Nu; fully_developed_laminar_h_spl and developing_laminar_h_spl HTC factories; maximal_htc combinator — v0.7
- ✓ turbulent_friction(Re, epsilon) Colebrook-White; viscosity_correction(heat_wet_ratio, mu_ratio); correlations.jl split into htc/ + friction/ subdirs — v0.7

### Active

<!-- v0.7 requirements — now validated -->

> **Gap analysis available:** `.planning/GAP-ANALYSIS.md` contains a full feature-by-feature comparison of Python STREAM vs Julia STREAM (compiled 2026-03-16, v0.5.0). ~80 items missing; Priority 1 (9 items) covers the non-negotiable core for real reactor simulations.

### Out of Scope

- Point kinetics — dedicated milestone after v0.7
- Decay heat — irrelevant without neutronics
- Uncertainty Quantification — post-validation concern
- Python adapter (juliacall) — if Julia-STREAM is good, it should be used from Julia
- Heavy water, sodium, or any non-light-water fluid — light water sufficient
- Wrapper struct for solver API (SteadySolution, TransientSolution) — ODESolution is sufficient
- ~~Subcooled boiling~~ — delivered in v0.7 Phase 28 (McAdams, Bergles-Rohsenow, in-loop correction)
- Natural convection as a standalone loop mode (Elenbaas added in v0.6 as HTC correlation only, not a full natural-convection-loop solver)
- `channel_outputs()` helper — `@observed` makes `sol[sys.ch.Re, :]` work directly

## Context

- **v0.1 shipped** 2026-03-13 — 763 Julia LOC, 54 tests, 5 phases, 12 plans
- **v0.2 shipped** 2026-03-13 — 818 src LOC, 545 test LOC, 86 tests, 4 phases, 7 plans
- **v0.3 shipped** 2026-03-14 — ~1,003 Julia LOC, 161 tests, 4 phases (10-12.1), 8 plans
- **v0.4 shipped** 2026-03-16 — ~3,268 Julia LOC, 4 phases (13-16), 7 plans; 15 requirements complete
- **v0.5 shipped** 2026-03-16 — ~3,750 Julia LOC (src + test), 3 phases (17-19), 6 plans; 15 requirements complete; canonical file layout, full docstrings, 13-file test suite
- **v0.6 shipped** 2026-03-27 — 2,373 src LOC, 8 phases (20-26 incl. 24.1), 14 plans; 21 requirements complete; flow reversal, Flapper, Elenbaas NC, LOF transient validated
- **v0.7 shipped** 2026-04-01 — 7,715 Julia LOC (src + test), 7 phases (27, 27.1, 28, 29, 30, 31, 32), 13 plans; 34 requirements (33 complete + 1 deferred); full safety physics and pressure field suite: pressure observables, momentum ODE, SCB, threshold analysis, complete HTC/friction library
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
| Series-loop LOF topology replaced by 4-node bypass | Series topology had no real junctions; couldn't model parallel channel/Flapper paths or correct gravity signs per branch | ✓ Good — bypass topology is physically correct; NC established at expected mdot magnitude |
| Channel momentum inertia reverted from Channel component; standalone Inertia used | `(L/A)*Dt(port_in.mdot)` in Channel breaks parallel topologies (current-source conflict at junctions); standalone Inertia in series is exact and composable | ✓ Good — all 5 bypass LOF tests pass; Inertia component handles this correctly |
| Channel carries distributed inertia `(L/A)*Dt(mdot)` via momentum ODE (Phase 27.1 reversal) | Pressure field implementation requires inertia in P[i] formula; series-only topologies (no parallel branches) are safe; Channel+Inertia in series compilation-only (two competing Dt(mdot) ODEs — physical over-specification) | ✓ Good — PRES-05..12 all pass; PRES-11 correctly scoped to compilation-only |
| max(dT, 0.0) inside ifelse() for SCB exponentiation | Julia ifelse() evaluates both branches eagerly; negative dT causes DomainError in power law without the max guard | ✓ Good — SCB-01..04 pass; same pattern applies to all power-law correlations with ifelse() |
| SCB in-loop correction via skip_htc kwarg + caller-provided h_tc equations | Cleanest extension point; doesn't modify _channel_base_eqs control flow; caller inserts the ifelse(T_wall>=T_ONB, h_scb, h_spl) equation | ✓ Good — ISCB-01/02 pass; backward compatible (scb_correction=nothing default) |
| threshold_analysis takes sol + channel_sys; ChannelState is internal bridge | Post-process API mirrors Python STREAM; ChannelState bundles MTK solution extraction for clean function boundaries | ✓ Good — THRS-09 E2E test passes; chfr() factory provides ergonomic CHFR computation |
| _extract_channel_state requires ChannelAndContacts (ArgumentError guard) | ChannelHeatFlux/Channel lack T_wall_left/right observables; hasproperty guard gives clear error instead of silent failure | ✓ Good — guard test passes; precondition documented in docstring |
| _nusselt_coefficient_developing uses ifelse() (not if/else) | MTK traces through closures symbolically at mtkcompile time; if/else on Num throws TypeError at trace time | ✓ Good — Phase 30 smoke test passes; closures with ifelse() are MTK-compatible |
| correlations.jl split into htc/ and friction/ subdirs when > 300 lines | CLAUDE.md threshold; prevents monolithic file; enables independent evolution of HTC and friction suites | ✓ Good — Phase 30-01 split done cleanly; STREAM.jl includes updated |
| Flapper sentinel T_open=1e30 (not Inf) | MTK parameter Inf causes domain errors in arithmetic (t - Inf = -Inf → xi clamp → NaN); sentinel 1e30 keeps `t - T_open < 0` until event fires | ✓ Good — FLAP-05/06 pass cleanly; sentinel pattern is the right MTK idiom |
| Pump callable via `@parameters (dP_pump_fn::FType)(..)` | Captured Julia closure as typed MTK parameter; alternative (@register_symbolic) would be opaque and not accept closures | ✓ Good — PUMP-01/02/03 all pass; callable captured correctly in symbolic graph |
| NC detection in `regime_dependent` via `Gr/Re²>1` with `ifelse()` | Hard if-branch creates solver discontinuity; ifelse() emits symbolic conditional same as Re-regime switching | ✓ Good — NC temperature rise matches Elenbaas within 0.3% (ratio 0.997) |
| `solve_transient` redesigned to positional API `(ssys, op, t; ...)` | Mirrors Python STREAM API; keyword-only was inconsistent since v0.6 broke the "all keyword" convention by adding callable Pump | ✓ Good — cleaner call sites; 23 Pump call sites migrated; no regressions |
## Constraints

- **Tech stack**: Julia + ModelingToolkit.jl + DifferentialEquations.jl + Sundials.jl
- **Fluid**: Light water only through v0.4; other fluids deferred
- **Validation**: All results compared against Python STREAM on identical inputs. <1% steady-state; qualitative transient match
- **Architecture**: No Python-style Aggregator pattern. MTK compose() + connect() + mtkcompile() replaces it

---
*Last updated: 2026-04-01 after v0.7 milestone — Safety Physics & Pressure Field shipped: pressure field, momentum ODE, subcooled boiling, threshold analysis, HTC/friction completions.*
