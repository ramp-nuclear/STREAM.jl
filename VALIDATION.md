# Python-parity validation

How we show that STREAM.jl reproduces Python STREAM. The bar: Itay, Aviv, and
Eshed agree 100% that Julia solves the same systems and gives the same numbers.

**North star:** `test/test_integration.jl` is a **strict 1:1 port** of Python
`~/projects/STREAM/tests/test_general/test_integrations.py`. Same systems, same numbers,
same methods, both passing. Strict means: every Python test has exactly one Julia
counterpart, and **no test lives in `test_integration.jl` without a Python counterpart** —
Julia-only tests move to the file that mirrors their source, or are removed.

Python's integration tests assert against closed-form analytic solutions, so a faithful
port validates the physics, not just code-to-code agreement.

Status legend: ✅ ported & passing · 🟡 partial/divergent counterpart · ⬜ missing ·
⛔ blocked on a missing component (build it first).

## 1:1 correspondence — Python `test_integrations.py` (21 tests)

| # | Python test | Status | Tier | Needs |
|---|---|---|---|---|
| 1 | `test_pump_resistor_in_series_follows_analytic_solution` | ✅ | A | Pump+Resistor (have); write analytic assertion |
| 2 | `test_parallel_resistors_with_pump_against_analytic_solution` | ✅ | A | Resistor (have); query branch flows via MTK ports |
| 3 | `test_resistors_in_series_against_analytic_solution` | ✅ | A | Resistor (have) |
| 4 | `test_channel_stable_state_with_uniform_heating_increases_linearly` | ✅ | B | Liquid cₚ=1; Tc linear + h-weighted wall temp (computed h) |
| 5 | `test_channel_point_kinetics` | ✅ | B | CAC+Fuel+critical PK; per-channel Tc strictly linear |
| 6 | `test_kirchhoff_with_decaying_pump_eventually_flips_flow_direction_gravity` | ✅ | A | quasi-static per-t solve_steady; HX-pinned leg temps; reverses |
| 7 | `test_Tin_jumps_at_resistor_between_two_hxs_at_flow_reversal` | ✅ | A | HX + Resistor (have) |
| 8 | `test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary_conditions` | ✅ | B | Fuel+PK, bath=ref; solve_steady power→0, T→T0 |
| 9 | `test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet` | ✅ | B | CAC+Fuel+PK, ref=inlet; solve_steady power→0, T_cool→T0 |
| 10 | `test_inertia_through_RL_circuit_follows_analytic_solution` | ✅ | A | Inertia+Resistor (have); `exp(-rt/L)` assertion |
| 11 | `test_kirchhoff_significance_in_two_in_series_resistors` | ✅ | C | re-expressed: resistance scaling r1/s |
| 12 | `test_kirchhoff_significance_for_many_parallel_edges` | ✅ | C | re-expressed: native parallel topology |
| 13 | `test_pump_and_current_source` | ✅ | A | Pump fixed-dP + fixed-mdot (have) |
| 14 | `test_flapper_opens_with_ref_mdot` | ✅ | A | Flapper reworked to Python semantics; `t_open=log(10)` |
| 15 | `test_flapper_and_pump` | ✅ | A | Flapper+Pump; pre-timed open |
| 16 | `test_pump_coastdown_allows_channels_to_reverse_flow_direction` | ✅ | A | quasi-static per-t DynamicSS; crossing at L·g·Δρ; reverses |
| 17 | `test_inertia_with_friction_in_PCS_coastdown` | ✅ | A | Inertia+Friction (have); `mdot0/(1+αt)` assertion |
| 18 | `test_inertia_with_flapper_in_PCS_coastdown` | ✅ | C | VFR + reworked Flapper |
| 19 | `test_inertia_with_transistor_in_PCS_coastdown` | ✅ | C | callable-k VFR (transistor) |
| 20 | `test_inertia_with_two_parallel_resistors` | ✅ | C | `VolumetricFlowResistor` (have) |
| 21 | `test_local_pressure_with_flow_reversal` | ✅ | C | `LocalPressureDrop` (have); quasi-static per-t |

Tally: 21 ✅ · 0 🟡 · 0 ⬜ · 0 ⛔ (target: 21 ✅ — **MET**).

**Tier-B note (#4, #5, #8, #9):** these assert Python's closed-form analytic results
(linear coolant rise, h-weighted wall temperature, power driven negligible by negative
feedback), not byte-identical numbers. Julia's models differ from Python's mocks in ways
immaterial to those results: `HeatDiffusion` is single-material (Python MTR is meat+clad)
and needs nx ≥ 2 (Python nx = 1); `ChannelAndContacts` computes its HTC from a coolant-based
correlation (Python prescribes mock h — #4 reads Julia's computed `h_tc` into the same
wall-temperature balance); `PointKinetics` is fixed 6-group (Python #8 uses 1 group).
`Liquid()` = Python's `mock_liquid_funcs` (all properties 1.0).
