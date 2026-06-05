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
| 1 | `test_pump_resistor_in_series_follows_analytic_solution` | ⬜ | A | Pump+Resistor (have); write analytic assertion |
| 2 | `test_parallel_resistors_with_pump_against_analytic_solution` | ⬜ | A | Resistor (have); query branch flows via MTK ports |
| 3 | `test_resistors_in_series_against_analytic_solution` | ⬜ | A | Resistor (have) |
| 4 | `test_channel_stable_state_with_uniform_heating_increases_linearly` | 🟡 | B | mock-fluid path for exact linear-rise numbers |
| 5 | `test_channel_point_kinetics` | 🟡 | B | mock fluids; per-channel linear-Tc assertion |
| 6 | `test_kirchhoff_with_decaying_pump_eventually_flips_flow_direction_gravity` | ⬜ | A | Pump (callable dP) + Gravity (have) |
| 7 | `test_Tin_jumps_at_resistor_between_two_hxs_at_flow_reversal` | ⬜ | A | HX + Resistor (have) |
| 8 | `test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary_conditions` | 🟡 | B | Fuel+PK (have); steady power→0 assertion |
| 9 | `test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet` | 🟡 | B | has counterpart; align numbers/method |
| 10 | `test_inertia_through_RL_circuit_follows_analytic_solution` | ⬜ | A | Inertia+Resistor (have); `exp(-rt/L)` assertion |
| 11 | `test_kirchhoff_significance_in_two_in_series_resistors` | ⛔ | C | **`signify`** (network multiplicity) |
| 12 | `test_kirchhoff_significance_for_many_parallel_edges` | ⛔ | C | **`signify`** |
| 13 | `test_pump_and_current_source` | ⬜ | A | Pump fixed-dP + fixed-mdot (have) |
| 14 | `test_flapper_opens_with_ref_mdot` | 🟡 | A | Flapper (have); analytic `t_open=log(10)` assertion |
| 15 | `test_flapper_and_pump` | ⬜ | A | Flapper+Pump (have); pre-timed open |
| 16 | `test_pump_coastdown_allows_channels_to_reverse_flow_direction` | 🟡 | A | Channels (have); analytic gravity zero-crossing |
| 17 | `test_inertia_with_friction_in_PCS_coastdown` | ⬜ | A | Inertia+Friction (have); `mdot0/(1+αt)` assertion |
| 18 | `test_inertia_with_flapper_in_PCS_coastdown` | ⛔ | C | **`VolumetricFlowResistor`** |
| 19 | `test_inertia_with_transistor_in_PCS_coastdown` | ⛔ | C | **closure-resistor (`Transistor`)** + VFR |
| 20 | `test_inertia_with_two_parallel_resistors` | ⛔ | C | **`VolumetricFlowResistor`** |
| 21 | `test_local_pressure_with_flow_reversal` | ⛔ | C | **`LocalPressureDrop`** |

Tally: 0 ✅ · 6 🟡 · 8 ⬜ · 5 ⛔ (target: 21 ✅).

## New components to build (decided: implement, for true 1:1)

- `VolumetricFlowResistor` — quadratic `dP ∝ mdot·|mdot|` resistor (unblocks #18, #20).
- `LocalPressureDrop` — area-change minor loss `(A1,A2)` (unblocks #21).
- closure-resistor / `Transistor` pattern — time-dependent resistance via callable parameter (unblocks #19).
- network `signify` — channel-multiplicity weighting on a flow edge (unblocks #11, #12).
- mock-fluid path — injectable cp/k/rho so channel tests hit Python's exact analytic numbers (Tier B).

Each is a real physics component and gets its own unit tests in the file mirroring its source, plus the integration test that uses it.

## `one_sided_connection` split (precedes the port; clears `mtr_one_sided` parity)

Julia's current `one_sided_connection` couples one fuel face (the other adiabatic) —
truthful one-sided. Python's couples the fuel on both faces to one channel. The Julia
parity code currently treats Python's as a bug and diverges, which is the entire 20 FAIL /
72 GRAY. Plan: keep the truthful helper, add a Python-matching both-faces helper, switch the
`mtr_one_sided` parity scenario to it → parity goes clean. (Whether Python's convention is
physically right is a separate ground-truth note, not a blocker for the 1:1 proof.)

## Strict 1:1 — disposition of current Julia-only tests in `test_integration.jl`

These have no Python `test_integrations.py` counterpart. Proposed move/remove, for review.

| Julia testset(s) | Proposed disposition |
|---|---|
| `Builders smokes` (build_loop/vertical/transient/cube/lof/pk compiles+solves) | MOVE → new `test_examples.jl` (they test `src/examples.jl`) |
| `steady_state_guess monotonically increasing` | MOVE → new `test_solvers.jl` (tests `src/solvers.jl`) |
| `Solver wrappers` (solve_steady / solve_transient) | MOVE → `test_solvers.jl` |
| `Loss-of-flow transient` | RECONCILE with Python #16 (pump coastdown); keep the Julia-specific energy-balance gate as a justified extra or move it |
| `Subcooled-boiling integration (ISCB)` | **KEEP-JUSTIFIED?** Julia physics with no Python integration analog — flag for team: move to `test_channels.jl` or keep as a justified Julia-only integration block |
| `Point-kinetics + thermal-feedback loops` | SPLIT: the parts mirroring Python #5/#8/#9 reconcile to the port; SCRAM + cold-IC regression MOVE → `test_point_kinetics.jl` |
| `COMPAT: Pkg.test()` smoke | MOVE → `runtests.jl` or `test_utilities.jl` |

Open question for the team: the strict-1:1 rule says `test_integration.jl` mirrors only
the Python integration file. Julia has real physics (SCB, SCRAM) the Python *integration*
file does not exercise — those belong in the test file mirroring their source, not deleted.
