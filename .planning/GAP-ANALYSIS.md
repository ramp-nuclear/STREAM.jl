# Python STREAM → Julia STREAM: Feature Gap Analysis

**Compiled:** 2026-03-16
**Julia STREAM version at time of analysis:** v0.5.0
**Python STREAM reference:** ~/projects/STREAM

This document is the authoritative gap list for planning v0.6 through v1.0.
When a feature is implemented, update its row from ❌ to ✅ and note the version.

Legend: ✅ = fully implemented | ⚠️ = partially implemented | ❌ = missing

---

## Table 1 — Components / Calculations

| Python Component | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `Channel` | `Channel` | ✅ v0.1 | |
| `ChannelAndContacts` | `ChannelAndContacts` | ✅ v0.2 | |
| `ChannelHeatFlux` | `ChannelHeatFlux` | ✅ v0.3 | |
| `Pump` (fixed-dP + fixed-mdot) | `Pump` | ✅ v0.4 | |
| `Friction` | `Friction` | ✅ v0.1 | |
| `Gravity` | `Gravity` | ✅ v0.1 | |
| `Resistor` | `Resistor` | ✅ v0.2 | |
| `Inertia` | `Inertia` | ✅ v0.2 | |
| `HeatExchanger` | `HeatExchanger` | ✅ v0.2 | |
| `Fuel` — x_diffusion (1D Cartesian plate) | `HeatDiffusion` | ⚠️ v0.3 | Julia only implements lateral x-diffusion; no axial z-diffusion |
| `Fuel` — xz_diffusion (2D Cartesian) | — | ❌ | Full 2D axial+lateral diffusion not yet implemented |
| `Fuel` — r_diffusion (1D cylindrical radial) | — | ❌ | Cylindrical radial diffusion missing |
| `Fuel` — rz_diffusion (2D cylindrical radial-axial) | — | ❌ | 2D cylindrical diffusion missing |
| `Fuel` — heterogeneous `Solid.from_array()` materials | — | ❌ | Per-cell material assignment (agreed v0.6+ scope) |
| `Fuel` — gap conductance (`x_contacts`, `z_contacts`) | — | ❌ | Fuel-cladding gap conductance missing |
| `Fuel` — axial BCs (`T_top`, `T_bottom`, `h_top`, `h_bottom`) | — | ❌ | Top/bottom boundary conditions on HeatDiffusion missing |
| `Fuel` — `meat_indices` fissile region tracking | — | ❌ | No fissile vs. structural material distinction |
| `LocalPressureDrop` | — | ❌ | Local loss coefficient K component missing |
| `Bend` | — | ❌ | Elbow/bend pressure drop component missing |
| `Screen` | — | ❌ | Flow blockage component missing |
| `RegimeDependentFriction` (standalone component) | `regime_dependent` (correlation only) | ⚠️ v0.4 | Python has it as a first-class `LumpedComponent`; Julia exposes it only as a pluggable correlation factory |
| `VolumetricFlowResistor` | — | ❌ | K·(Q/A)² volumetric resistance missing |
| `Flapper` | — | ❌ | Passive relief valve / natural circulation initiator — major missing component; requires event-restart solver support |
| `Junction` | implicit via MTK `connect()` | ✅ | Not needed in Julia; MTK generates KCL equations automatically |
| `Kirchhoff` / `KirchhoffWDerivatives` | implicit via MTK | ✅ | MTK compiler handles this structurally |
| `PointKinetics` | — | ❌ | Point reactor kinetics with delayed neutron precursor groups |
| `PointKineticsWInput` | — | ❌ | PointKinetics with external power input |
| `ReactivityController` + `StateMachine` | — | ❌ | Reactor protection system / reactivity control logic |

---

## Table 2 — HTC Correlations

| Python Correlation | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `Dittus_Boelter_h_spl` | `dittus_boelter` | ✅ v0.1 | |
| `constant_Nusselt_h_spl` | `constant_Nusselt` | ✅ v0.4 | |
| `laminar_friction` + `rectangular_laminar_correction` | same names | ✅ v0.4 | |
| `regime_dependent_h_spl` | `regime_dependent` | ✅ v0.4 | |
| `Marco_Han_Nusselt(aspect_ratio)` | — | ❌ | Analytical rectangular duct Nu (more accurate than constant_Nusselt) |
| `two_sided_heating_nusselt(aspect_ratio, nu0)` | — | ❌ | Two-sided heating Nu correction for rectangular ducts |
| `fully_developed_laminar_h_spl(aspect_ratio)` | — | ❌ | Fully-developed laminar HTC via Marco & Han |
| `developing_laminar_h_spl()` | — | ❌ | Developing-flow HTC via Shah & London interpolation |
| `maximal_h_spl()` | — | ❌ | max(SPL, natural convection) master HTC selector |
| `Elenbaas_h_spl()` | — | ❌ | Parallel-plate natural convection HTC correlation |
| `wall_heat_transfer_coeff()` (master function) | — | ❌ | Master HTC combining SPL + boiling + natural convection; protocol-based |
| `Bergles_Rohsenow_q_scb` | — | ❌ | Subcooled boiling (SCB) heat flux correlation |
| `McAdams_q_scb` | — | ❌ | SCB heat flux (alternative correlation) |
| `Bergles_Rohsenhow_partial_SCB` | — | ❌ | Smooth SPL↔SCB blending function |

---

## Table 3 — Friction / Pressure Drop Correlations

| Python Correlation | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `Blasius_friction` | `blasius_friction` | ✅ v0.1 | |
| `regime_dependent_friction` | `regime_dependent` | ✅ v0.4 | |
| `turbulent_friction` (Colebrook-White) | — | ❌ | More accurate turbulent friction than Blasius; accounts for surface roughness |
| `viscosity_correction()` | — | ❌ | Temperature-dependent viscosity scaling for friction |
| `local_pressure_by_mdot` / `local_pressure_factor` | — | ❌ | Generic K-factor local loss calculations |
| `contraction_factor` / `expansion_factor` | — | ❌ | Idelchik sudden area change correlations |
| `bend_factor` | — | ❌ | Elbow/bend loss correlation |
| `mdot_by_local_pressure` | — | ❌ | Inverse: compute mdot from known local pressure drop |
| `pressure_diff` (master function) | — | ❌ | Master combining friction + gravity + inertia + acceleration |

---

## Table 4 — Safety Thresholds & CHF

| Python Function | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `Bergles_Rohsenow_T_ONB` | — | ❌ | Onset of Nucleate Boiling temperature |
| `boiling_power` | — | ❌ | Power at ONB threshold |
| `Whittle_Forgan_OFI` | — | ❌ | Onset of Flow Instability power limit |
| `Saha_Zuber_OSV` | — | ❌ | Onset of Significant Void (Pe-dependent, iterative) |
| `Sudo_Kaminaga_CHF` | — | ❌ | Critical Heat Flux for plate-type fuels |
| `Mirshak_CHF` | — | ❌ | CHF for rapid flows (v > 1.5 m/s) |
| `Fabrega_CHF` | — | ❌ | CHF for slow flows |
| `twall_limit` | — | ❌ | Wall temperature safety limit with inhomogeneity factor |
| `threshold_analysis` | — | ❌ | Steady-state safety margin computation for a full system |
| `transient_threshold_analysis` | — | ❌ | Time-dependent safety threshold tracking over a transient |

---

## Table 5 — Decay Heat

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| ANS14 standard data + API | — | ❌ | Fission products, actinides, activation, delayed fissions |
| ANS73 standard data + API | — | ❌ | Same source categories, different standard |
| JAERI91 standard data + API (beta + gamma separated) | — | ❌ | Most detailed; beta/gamma contributions separate |
| `contribution(standard, source)` → DecayHeatFunction | — | ❌ | Unified lookup API across all standards |
| `DecayHeatFunction` protocol (power vs. time callable) | — | ❌ | Interface type for decay heat callables |

---

## Table 6 — Fluids / Substances

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `light_water` (ρ, cp, μ, k) — Simantov correlations | `rho_water`, `cp_water`, `mu_water`, `k_water` | ✅ v0.1 | Same correlations |
| `heavy_water` (D₂O) | — | ❌ | Agreed v0.6+ scope |
| `LiquidFuncs` protocol (multi-fluid abstraction) | — | ❌ | Agreed v0.6+ as `AbstractFluid` + multiple dispatch |
| `Liquid` evaluated-properties dataclass | — | ❌ | Holds evaluated scalar/array properties for a (T, p) point |
| `sat_temperature(p)` — pressure-dependent saturation T | — | ❌ | Required for boiling threshold calculations |
| `surface_tension(T)` | — | ❌ | Required for ONB / CHF correlations |
| `latent_heat(T)` | — | ❌ | Required for boiling calculations |
| `vapor_density(T)` | — | ❌ | Required for void fraction / SCB |
| `thermal_expansion(T)` | — | ❌ | Required for Grashof / natural convection |
| `mock_liquid_funcs` / `mock_solid` / `constant_LiquidFuncs` | — | ❌ | Test mock utilities |

---

## Table 7 — Dimensionless Number Utilities

| Python Function | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `Re(mdot, rho, A, Dh, mu)` | computed inline in channels | ⚠️ | Not exported as standalone utility function |
| `Re_mdot(mdot, Dh, mu, A)` | — | ❌ | Convenience form of Re |
| `Pr(mu, cp, k)` | computed inline | ⚠️ | Not exported standalone |
| `Nu(h, k, Dh)` | computed inline | ⚠️ | Not exported standalone |
| `Pe(mdot, rho, cp, k, Dh)` | computed in ChannelAndContacts | ⚠️ | Observable in CAC but not an exported utility |
| `Gr(rho, g, beta, dT, L, mu)` | — | ❌ | Grashof number — required for natural convection |
| `Ra(Gr, Pr)` | — | ❌ | Rayleigh number |

---

## Table 8 — Composition Helpers

| Python Helper | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `symmetric_plate(cac, fuel)` | `symmetric_plate` | ✅ v0.4 | |
| `plate(ch_left, ch_right, fuel)` | `plate` | ✅ v0.4 | |
| `one_sided_connection(channel, fuel)` | `one_sided_connection` | ✅ v0.4 | |
| `compose_systems(...)` | `compose_systems` | ✅ v0.4 | |
| `port(sys, face, i)` | `port` | ✅ v0.4 | |
| `check_gravity_mismatch` | `check_gravity_mismatch` | ✅ v0.4 | |
| `chain_fuels_channels(channels, fuels)` | — | ❌ | C-F-C-F-C interleaving pattern helper |
| `rod(channel, n_channels, fuel, n_plates)` | — | ❌ | Parallel unit replication helper |
| `in_series(*comps, cyclic=False)` | — | ❌ | Series connection topology builder |
| `in_parallel(start, end, *paths)` | — | ❌ | Parallel paths topology builder |
| `FlowGraph(flow_edge(s), ...)` | — | ❌ | High-level graph builder (Python's primary user-facing API) |
| `flow_edge(u, v, *comps, signify, ref_mdot_for)` | — | ❌ | Component-chain edge spec with Flapper wiring support |
| `maximally_coupled(...)` | — | ❌ | Auto-wiring by parameter name matching |
| `Calculation_factory(calculate, mass_vector, variables)` | — | ❌ | Dynamic component class creation |
| `ResistorFromKnownPoint(dp, mdot, behavior)` | — | ❌ | Resistor parameterized from a known operating point |
| `x_boundaries(...)` | — | ❌ | MTR plate x-grid discretization helper |
| `uniform_x_power_shape(...)` | — | ❌ | Flat uniform axial power shape utility |
| `cosine_shape(x, ppf)` | — | ❌ | Normalized cosine axial power shape |
| `cosine_shape_by_zero_endpoints(xi, xe, x)` | — | ❌ | Cosine shape bounded between two endpoints |

---

## Table 9 — Initial Guessing / Steady-State Setup

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `steady_state_guess(T_inlet, Q_wall, mdot_guess, n)` — linear ramp | `steady_state_guess` | ✅ v0.1 | |
| `symmetric_plate_steady_state(c, f, mdot, ...)` | — | ❌ | Iterative coupled channel+plate initial guess |
| `guess_hydraulic_steady_state(K, mdots, ...)` | — | ❌ | Pressure field computation from known flow distribution |
| `point_kinetics_steady_state(pk, power, ...)` | — | ❌ | Critical equilibrium state for neutronics initialization |
| `FlowGraph.guess_steady_state(mdots, temperature)` | — | ❌ | High-level guess builder on the flow graph |

---

## Table 10 — Solvers

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `algebraic(F, y0)` — scipy root | `solve_steady` via KINSOL | ✅ v0.1 | Different backend, same purpose |
| `differential(F, y0, time)` — ODE via scipy | `solve_transient` via Rodas5P | ✅ v0.1 | |
| `differential_algebraic(F, mass, y0, time)` — SUNDIALS IDA | `solve_transient` (Rodas5P handles stiff DAEs) | ⚠️ | Julia uses stiff ODE; explicit true DAE backend (IDA) not yet exposed to the user |
| `continuous=True` event restart (for Flapper opening) | — | ❌ | Required to support Flapper opening discontinuity |
| Sequential quasi-static algebraic over time points | — | ❌ | Stepping through quasi-static scenarios (power ramp, coastdown) |
| `TransientRuntimeError` with partial solution on failure | — | ❌ | Partial timeseries preserved when transient solve fails mid-run |

---

## Table 11 — Analysis & Debugging Tools

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `debug_derivatives(agr, guess)` | — | ❌ | Print all F(y,t) residuals at a candidate guess point |
| `debug_guess_variables(...)` | — | ❌ | Residual inspection for specific variables |
| `debug_guess_pressures(...)` | — | ❌ | Pressure-specific residual debugging |
| `report(agr)` | — | ❌ | System summary: variable counts, missing externals, Calculation listing |
| `UQModel` | — | ❌ | Systematic + statistical uncertainty propagation |
| `DASKUQModel` | — | ❌ | Distributed UQ via Dask |
| `Uncertainty(systematic_relative, statistical_absolute)` | — | ❌ | Uncertainty descriptor type |
| `power_perturbations` | — | ❌ | Sensitivity analysis for power shape variations |

---

## Table 12 — State & Solution Management

| Python Feature | Julia Equivalent | Status | Notes |
|---|---|---|---|
| `State` dict — `merge`, `uniform`, `filter_*` methods | basic `sol[sym]` access | ⚠️ | Julia uses SciML `ODESolution`; no structured named-state dict |
| `State.to_dataframe()` / `from_dataframe()` | — | ❌ | DataFrame I/O for results |
| `State.dump(file)` / `load(file)` (YAML) | — | ❌ | Persistent state serialization for restarts |
| `Solution` class (`.time`, `.data`) | `ODESolution` (SciML) | ✅ | SciML provides equivalent via `sol.t`, `sol[sym, :]` |
| `Aggregator.draw()` | — | ❌ | matplotlib component graph visualization |

---

## Priority Summary

### Priority 1 — Core Physics (blocks real reactor simulations)

| # | Feature | Why Critical |
|---|---|---|
| 1 | `Flapper` component | Required for loss-of-flow and natural-circulation accident scenarios |
| 2 | `PointKinetics` + `PointKineticsWInput` + `ReactivityController` | Neutronics is a core STREAM capability — no accident analysis without it |
| 3 | Decay heat (`ANS14`, `ANS73`, `JAERI91`) | Required for any post-shutdown transient |
| 4 | Subcooled boiling HTC (`Bergles_Rohsenow`, `McAdams`, partial SCB blend) | Required for high-power normal operation and accident analysis |
| 5 | CHF correlations (`Sudo_Kaminaga`, `Mirshak`, `Fabrega`) | Safety margin calculation for fuel integrity |
| 6 | Full threshold analysis suite (`ONB`, `OFI`, `OSV`, `CHF`, `twall_limit`, `threshold_analysis`) | Produces the actual safety numbers the user cares about |
| 7 | Natural convection HTC (`Elenbaas`) + `Gr` / `Ra` dimensionless numbers | Required for natural circulation loops (loss-of-pump scenarios) |
| 8 | `heavy_water` fluid + `AbstractFluid` multi-fluid abstraction | D₂O reactors are a primary STREAM use case |
| 9 | `HeatDiffusion` — xz_diffusion (2D Cartesian) + r_diffusion / rz_diffusion (cylindrical) | Cylindrical geometry is needed for rod-type fuels; 2D Cartesian for axial conduction |

### Priority 2 — Important Physics & API Completeness

| # | Feature |
|---|---|
| 10 | `LocalPressureDrop`, `Bend`, `Screen` (local loss components) |
| 11 | `fully_developed_laminar_h_spl` + `developing_laminar_h_spl` (complete laminar HTC suite) |
| 12 | `Marco_Han_Nusselt` + `two_sided_heating_nusselt` (analytical rectangular duct Nu) |
| 13 | Colebrook-White turbulent friction (more accurate than Blasius for rough surfaces) |
| 14 | Local pressure drop correlations (`contraction_factor`, `expansion_factor`, `bend_factor`) |
| 15 | `HeatDiffusion` gap conductance (`x_contacts`, `z_contacts`) |
| 16 | Heterogeneous materials (`Solid.from_array()`) |
| 17 | Fluid saturation/boiling properties: `sat_temperature(p)`, `surface_tension`, `latent_heat`, `vapor_density`, `thermal_expansion` |

### Priority 3 — Composition & Workflow

| # | Feature |
|---|---|
| 18 | `chain_fuels_channels` + `rod` assembly helpers |
| 19 | `cosine_shape` / `cosine_shape_by_zero_endpoints` power shape utilities |
| 20 | `symmetric_plate_steady_state` + `guess_hydraulic_steady_state` improved initial guessing |
| 21 | `ResistorFromKnownPoint` |
| 22 | `x_boundaries` + `uniform_x_power_shape` (MTR geometry helpers) |
| 23 | `in_series` / `in_parallel` topology helpers |
| 24 | `point_kinetics_steady_state` |

### Priority 4 — Analysis, Debugging & QoL

| # | Feature |
|---|---|
| 25 | `UQModel` + `Uncertainty` (uncertainty quantification) |
| 26 | `debug_derivatives` / `report()` (system introspection) |
| 27 | `State` serialization (`dump`/`load`, `to_dataframe`) |
| 28 | Standalone dimensionless number utilities (`Gr`, `Ra`, `Re_mdot`, `Pr`, `Pe`, `Nu` exported) |
| 29 | `Aggregator.draw()` component graph visualization |
| 30 | `TransientRuntimeError` with partial solution recovery |
| 31 | Mock utilities (`mock_liquid_funcs`, `mock_solid`, `constant_LiquidFuncs`) |

---

## Rough Count

- ✅ Implemented: ~30 items
- ⚠️ Partial: ~8 items
- ❌ Missing: ~80 distinct items

**To reach 90–100% Python STREAM parity, Priority 1 (9 items) and Priority 2 (8 items) are the non-negotiable core.**
