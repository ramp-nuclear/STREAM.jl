# Python-parity validation (WV)

Living tracker for proving STREAM.jl reproduces Python STREAM. The bar: Itay, Aviv, and
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
| 4 | `test_channel_stable_state_with_uniform_heating_increases_linearly` | ✅ | B | ConstantFluid cp=1; Tc linear + h-weighted wall temp (computed h) |
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
and needs nx ≥ 2 (Python nx = 1); `ChannelAndContacts` computes its HTC from a water-based
correlation (Python prescribes mock h — #4 reads Julia's computed `h_tc` into the same
wall-temperature balance); `PointKinetics` is fixed 6-group (Python #8 uses 1 group).
`ConstantFluid()` = Python's `mock_liquid_funcs` (all properties 1.0).

## New components to build (decided: implement, for true 1:1)

- ✅ `VolumetricFlowResistor` — quadratic `dP = k·Q·|Q| + klow·Q` resistor (unblocks #18, #20).
  Commit `cd4ab8f`. Its callable-`k` path **is** the transistor pattern below.
- ✅ closure-resistor / `Transistor` pattern — folded into `VolumetricFlowResistor`: pass `k`
  as a callable `(t) -> k` (MTK callable-parameter idiom) for a time-varying resistance
  (unblocks #19). Commit `cd4ab8f`.
- ✅ mock-fluid path — `AbstractFluid` / `Water()` / `ConstantFluid`; channels take a `fluid`
  kwarg threaded into `_channel_core`. `Water()` stays byte-identical (parity 526 CLEAN);
  `ConstantFluid` = Python's `mock_liquid_funcs`. Mock solid needs no work — `HeatDiffusion`
  already takes `k_s`/`cp_s`/`rho_s`. Commit `c36e2fc`. (Tier B: #4, #5.)
- ✅ `LocalPressureDrop` — Idelchik sudden expansion/contraction minor loss `(A1,A2)`, a
  `@register_symbolic` table lookup inside the MTK drop equation (unblocks #21). Commit `8f4c379`.
- network `signify` — **no new component.** In Python `signify` is a Kirchhoff junction-weight;
  it does not map to a mass-conserving MTK element (a single in-line flow-gain breaks KCL at the
  other junction). The faithful MTK expression of "edge counts `N` times" is `N` parallel
  branches (integer, #12's own construction) or, equivalently, scaling the resistance — a single
  resistor of `r/N` carries the bundle flow `N·m1` with the per-copy drop `r·m1`, giving the
  same `m1 = p/(r1 + N·r2)`. Handled in Phase 3 as a "re-express against MTK port variables"
  case (#11, #12); the per-copy flow is `bundle / N`.

Each real component gets its own unit tests in the file mirroring its source, plus the
integration test that uses it.

## `one_sided_connection` split (precedes the port; clears `mtr_one_sided` parity) — ✅ DONE

Julia's `one_sided_connection` couples one fuel face (the other adiabatic) — truthful
one-sided; kept as-is. Python's `one_sided_connection` is an edge-channel reduced model:
the channel is heated on its connected face only, but the fuel plate is cooled on BOTH
faces — the far face by the *connected-side* h (Python's `_other_if_none` copies it) into
an unmodelled equivalent twin. The old parity code treated this as a "Python bug" and
diverged, which was the entire 20 FAIL / 72 GRAY.

Shipped:
- `ConvectiveBoundary(; name, area)` (src/components/sources.jl) — one-way convective sink
  `Q_flow = h·area·(T_wall − T_fluid)`, fed by externally-bound `h` and `T_fluid`.
- `single_channel_connection(channel, fuel, geometry; fuel_side, name)`
  (src/composition/helpers.jl) — near face conjugate-connected, far face cooled by a
  per-cell `ConvectiveBoundary` bound to the channel's connected-side `h_tc` and coolant `T`.
- Switched the `mtr_one_sided` parity build to it; removed every widened tolerance, KNOWN-GAP
  note, and the skip-logic. Fixed the mislabeled "Python bug" comments in
  test/test_validation.jl and test/generate_mtr_reference.py.

Result: `mtr_one_sided`'s 20 FAIL + 72 GRAY → all CLEAN (plate-T matches Python bit-on and
is laterally symmetric, the both-faces signature). Parity harness 549/549, suite green.
Unit tests: `ConvectiveBoundary` in test_misc.jl, `single_channel_connection` in
test_composition.jl.

## Strict 1:1 — disposition of former Julia-only tests in `test_integration.jl` — ✅ DONE

`test_integration.jl` now holds exactly the 21 Python mirrors and nothing else. Every
Julia-only testset moved to the file mirroring its source; the full suite stayed green.

| Julia testset(s) | Disposition |
|---|---|
| `Builders smokes` (build_loop/vertical/transient/cube/lof/pk) | MOVED → `test_examples.jl` |
| `steady_state_guess monotonically increasing` | MOVED → `test_solvers.jl` |
| `Solver wrappers` (solve_steady / solve_transient) | MOVED → `test_solvers.jl` |
| `Loss-of-flow transient` | MOVED → `test_examples.jl` |
| `Subcooled-boiling integration (ISCB)` | MOVED → `test_channels.jl` |
| `Point-kinetics + thermal-feedback loops` | MOVED → `test_point_kinetics.jl` |
| `COMPAT: Pkg.test()` smoke | DELETED (vacuous; `runtests.jl` already orchestrates every file) |

Three tests were deleted as vacuous or fully subsumed by a stronger test: the
`build_loop_pk` return-shape smoke (subsumed by the builders' compile-and-solve smoke),
the `build_loop_transient compiles` `isa`-check (subsumed by its compile-and-solve smoke),
and the COMPAT `STREAM isa Module` marker. No real coverage was lost.
