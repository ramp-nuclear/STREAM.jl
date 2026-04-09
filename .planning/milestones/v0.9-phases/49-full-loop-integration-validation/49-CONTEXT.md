# Phase 49: Full Loop Integration + Validation — Context

**Gathered:** 2026-04-08 (updated from 2026-04-06 — Phase 48 complete, scram_callback API fix)
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire `PointKinetics` into the full thermal-hydraulic loop and validate the coupled system
against Python STREAM reference results. Deliverables:

1. `build_loop_pk` in `src/examples.jl` — a complete PK-coupled loop builder
2. Power-to-heat connection equation: `fuel.power ~ pk.P * power_scale`
3. Full integration tests: PK+channel+HeatDiffusion coupled transient
4. SCRAM-in-loop test: verify `scram_callback` terminates correctly in a coupled system
5. Quantitative cross-validation: compare steady-state and transient results against Python STREAM

</domain>

<power_coupling>
## Power-to-Heat Coupling (critical architectural decision)

### Background

`HeatDiffusion` has `power` as an `@variables` (unknown), so it can be driven by a
connection equation:

```julia
rods.fuel.power ~ pk.P * power_scale
```

This is the primary new equation that closes the neutron-thermal feedback loop.
Confirmed in `src/components/heat_diffusion.jl` — `vars = @variables begin ... power(t) = power_init`.

### Connection equation pattern (D-01)

```julia
# Standalone (old pattern — still valid for non-PK use):
fuel.power ~ 1e4          # constant W (pin it to a literal)

# PK-coupled (new in Phase 49):
rods.fuel.power ~ pk.P * power_scale    # W, where power_scale converts P0 to physical watts
```

`power_scale` is a user-supplied real scalar at compose time (NOT an MTK parameter).
Rationale: the ratio P/P0 is dimensionless; `power_scale` is the normalization constant
that converts normalized PK power (P0 = 1.0 default) to physical watts. If the user
initializes `pk.P = 1.0` (normalized), then `power_scale = 1e4` means 10 kW at full power.

### Compose pattern (D-02)

The build_loop_pk function follows the `compose_systems` + `symmetric_plate` pattern
already established in Phase 47 tests. Power coupling requires an explicit equation added
to the composition's equation list:

```julia
@named pk   = PointKinetics(ctrl; temp_worth=..., ref_temp=...)
@named cac  = ChannelAndContacts(...)
@named fuel = HeatDiffusion(...)
@named rods = symmetric_plate(cac, fuel; name=:rods)
@named pump = Pump(dP_pump_fn)
@named bc   = HeatExchanger(T_inlet)

# Feedback equations
fb_eqs = connect_temperature_feedback(pk, [rods.cac, rods.fuel])

# Power coupling
power_coupling = [rods.fuel.power ~ pk.P * power_scale]

connections = [
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out, rods.cac.port_in),
    connect(rods.cac.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
    ...
    fb_eqs...,
    power_coupling...,
]

@named sys = compose(System(connections, t; name=:sys), pump, bc, rods, pk)
ssys = mtkcompile(sys)
```

</power_coupling>

<decisions>
## Implementation Decisions

### build_loop_pk signature (D-03)

```julia
build_loop_pk(ctrl;
    n       = 7,           # channel axial cells
    nz      = 7,           # HeatDiffusion axial cells (must match n)
    nx      = 2,           # HeatDiffusion lateral cells
    T_inlet = 293.15,      # coolant inlet temperature [K]
    dP_pump = 3.0e4,       # pump pressure rise [Pa] (can be callable)
    P0      = 1.0,         # initial normalized PK power [-]
    power_scale = 1e4,     # physical power normalization [W / P_normalized]
    temp_worth  = nothing, # passed to PointKinetics
    ref_temp    = nothing, # passed to PointKinetics
    rho_val     = 0.0,     # base bias reactivity [-]
) -> (ssys, ic)
```

Returns `(ssys, ic)` where:
- `ssys` is the compiled system
- `ic` is a pre-built initial conditions dict containing PK steady-state ICs
  (from `point_kinetics_steady_state(P0)`) and channel/fuel initial temperatures.

Follows the existing `build_loop`, `build_loop_transient`, `build_loop_vertical` pattern
in `src/examples.jl` — all build and return the compiled system.

### Initial conditions for the coupled system (D-04)

PK ICs: `point_kinetics_steady_state(P0)` gives `(P=P0, C_k=[...])`.
Channel ICs: `T[i] => T_inlet` for all cells (cold start).
HeatDiffusion ICs: `T[i,j] => T_fuel_init` (a reasonable fuel temperature, e.g., 600.0).
HeatDiffusion power: `fuel.power ~ pk.P * power_scale` is an equation, not an IC — no
initial value needed for `power` since it is an algebraic connection to `pk.P`.
Pump callable: `ssys.pump.dP_pump_fn => dP_pump_fn` if pump is time-varying.
PK callable: `ssys.pk.rho_c_fn => ctrl`.

### connect_temperature_feedback updated API (D-05)

Confirmed in `src/composition/helpers.jl:328`:

```julia
connect_temperature_feedback(pk, components) -> Vector{Equation}
```

- `pk`: uncompiled `PointKinetics` system
- `components`: list of **scoped** component refs (e.g., `[rods.cac, rods.fuel]`)
  after `symmetric_plate` composition. Alpha coefficients live in the `PointKinetics`
  constructor `temp_worth` dict — they are not needed here.

The old API (`connect_temperature_feedback(pk, temp_worth_dict; scoped_comps=...)`) is gone.

### Phase 49 test structure (D-06)

**Plan 01 tests (integration):**
- `LOOP-01`: `build_loop_pk` compiles without error; initial conditions are consistent.
- `LOOP-02`: Transient simulation with `ctrl = ReactivityController()` (no reactivity),
  constant pump — power stays at P0 ± 1% for 10 seconds. Validates PK+loop coupling
  compiles and solves without divergence.
- `LOOP-03`: Step reactivity insertion (no SCRAM) — power rises and stabilizes via
  temperature feedback. Assert `P_max > P0` and `P[end] < P_max` (negative feedback acts).
- `LOOP-04`: SCRAM-in-loop — step reactivity + `SCRAM_at_power(1.2)` + `scram_callback`.

  **Exact call pattern (confirmed from Phase 48):**
  ```julia
  cb = scram_callback(ssys, ssys.pk.P, ctrl)
  ```
  `ssys.pk.P` is used because `pk` is nested as a subsystem inside the composed reactor.
  (In standalone PK tests, `ssys.P` is correct; in composed systems, always use the scoped path.)

  Assert `sol.t[end] < tspan[2]` and `ctrl.state == :SCRAM`.

**Plan 02 tests (validation — aligned with Python STREAM tests):**
- `VAL-PK-01`: Steady-state T_cool rises linearly along channel (matches
  `test_channel_point_kinetics` lines 201-267). Assert `diff(T_cool) > 0` and
  `diff(diff(T_cool)) ≈ 0`.
- `VAL-PK-02a`: Negative fuel feedback suppression — negative `temp_worth` on fuel with
  `ref_temp = T_boundary`. At steady state: `P ≈ 0` (or negligibly small). Matches
  `test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary_conditions`
  (lines 352-387).
- `VAL-PK-02b`: Negative coolant feedback suppression — negative `temp_worth` on coolant
  channel with `ref_temp = T_inlet`. At steady state: `P ≈ 0`. Matches
  `test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet` (lines 390-428).
- `VAL-PK-03`: Reactivity observable: `sol[ssys.pk.reactivity, :]` is accessible and
  at steady state matches expected `rho = sum(alpha_i * (T_i - T_ref_i))`.

**Note:** Python STREAM validation tests (lines 352-428) are all steady-state, not transient.
The original VAL-PK-02 "transient trace comparison" is dropped — steady-state suppression
tests are the correct cross-validation target.

### Python STREAM reference for validation (D-07)

```
~/projects/STREAM/tests/test_general/test_integrations.py
```
- Lines 201-267: `test_channel_point_kinetics` — 10-channel loop with PK, steady-state,
  linear temperature rise. This is the primary cross-validation target.
- Lines 352-387: `test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary_conditions`
  — negative fuel feedback drives power to near zero at steady state.
- Lines 390-428: `test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet`
  — negative coolant feedback drives power to near zero at steady state.

Python STREAM uses normalized power (P0 = 1.0 default). Use the same normalization in
`build_loop_pk` for direct comparison.

### File placement (D-08)
- `build_loop_pk` → `src/examples.jl` (alongside `build_loop_transient`)
- Integration tests → `test/test_examples.jl` (LOOP-01 through LOOP-04)
- Validation tests → `test/test_validation.jl` (VAL-PK-01, VAL-PK-02a/b, VAL-PK-03)
  (either new entries or a new `@testset "PointKinetics validation"` block)
- No new source files required

### solve_transient tspan for coupled system (D-09)

The coupled system has both fast PK timescales (prompt neutrons: ~1e-4 s) and slow
thermal timescales (~10-100 s). Use `Rodas5P()` with tight tolerances:
- `abstol = 1e-8`, `reltol = 1e-6` (default `solve_transient` tolerances)
- `tstops` at the reactivity step time for clean step insertion (same as Phase 47 pattern)
- `maxiters = 1_000_000` for long simulations

</decisions>

<requirements>
## Phase 49 Requirements

### LOOP-01: build_loop_pk compilation
`build_loop_pk(ctrl; ...)` compiles without error. Returns `(ssys, ic)` with consistent
initial conditions dictionary. `mtkcompile` produces a structurally correct system.

### LOOP-02: Quiescent stability
Transient with zero reactivity insertion: `P(t) ≈ P0` within 1% tolerance over 10 s.
Validates that PK+thermal coupling does not introduce spurious drift.

### LOOP-03: Temperature-limited power excursion
Step reactivity `Δρ = 0.0005` at t=0.5 s. With negative temperature feedback:
- `P_max > P0` (power rises after step)
- `P[end] < P_max` (feedback damps the excursion)
- Simulation completes without integrator failure.

### LOOP-04: SCRAM terminates the loop
`SCRAM_at_power(1.2)` + `scram_callback(ssys, ssys.pk.P, ctrl)` terminates the integrator
when `P > 1.2 * P0`. Assert `sol.t[end] < tspan[end]` and `ctrl.state == :SCRAM`.

### VAL-PK-01: Steady-state linear temperature rise
At steady state with constant power, coolant temperature rises linearly along channel.
`diff(T_cool) > 0` and `diff(diff(T_cool)) ≈ 0` (within numerical tolerance).
Matches Python STREAM `test_channel_point_kinetics`.

### VAL-PK-02a: Negative fuel feedback suppresses power
Negative `temp_worth` on fuel with `ref_temp = T_boundary`. Steady-state `P < tolerance`
(negligible). Matches Python STREAM `test_power_is_negligible_for_negative_Tfuel_feedback...`.

### VAL-PK-02b: Negative coolant feedback suppresses power
Negative `temp_worth` on coolant with `ref_temp = T_inlet`. Steady-state `P < tolerance`.
Matches Python STREAM `test_power_is_negligible_for_negative_Tcool_feedback...`.

### VAL-PK-03: Reactivity observable is accessible and correct
`sol[ssys.pk.reactivity, :]` is accessible post-solve. At steady state matches
expected `rho = sum(alpha_i * (T_i - T_ref_i))` within 1%.

</requirements>

<canonical_refs>
## Canonical References

**Must read before planning:**

- `src/examples.jl` — existing `build_loop`, `build_loop_transient`, `build_loop_vertical`
  builders; `build_loop_pk` follows the same pattern
- `src/components/heat_diffusion.jl` — `power` is `@variables power(t) = power_init`;
  connection equation `fuel.power ~ pk.P * scale` is how it's driven
- `src/composition/helpers.jl:290-348` — `connect_temperature_feedback(pk, components)` API;
  confirmed signature, read before writing any composition code
- `src/components/point_kinetics.jl:415-514` — `SCRAMCondition`, `SCRAM_at_power`,
  `scram_callback(ssys, p_sym, ctrl; terminate=true)` — note 3 positional args
- `.planning/phases/48-scram-solver-integration/48-CONTEXT.md` — SCRAM_at_power and
  scram_callback design decisions
- `test/test_point_kinetics.jl` — SCRAM-02 test (lines ~585-634) shows exact scram_callback
  usage pattern for standalone PK; Phase 49 LOOP-04 uses `ssys.pk.P` instead of `ssys.P`

**Python STREAM references:**
- `~/projects/STREAM/tests/test_general/test_integrations.py` lines 201-267:
  `test_channel_point_kinetics` — primary steady-state validation target
- `~/projects/STREAM/tests/test_general/test_integrations.py` lines 352-428:
  two steady-state power suppression tests (negative feedback → power ≈ 0)
- `~/projects/STREAM/stream/calculations/point_kinetics.py` — Python PointKinetics
  `calculate()` method for understanding the reference computation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `point_kinetics_steady_state(P0)` in `src/components/point_kinetics.jl` — produces PK ICs
- `symmetric_plate(cac, fuel; name)` in `src/composition/helpers.jl` — creates scoped rod assembly
- `connect_temperature_feedback(pk, components)` — generates binding equations, one per cell
- `solve_transient(ssys, op, t_arr; tstops, callbacks)` in `src/solvers.jl` — handles `tstops` and `callbacks` kwargs
- `build_loop_transient` in `src/examples.jl` — closest template for `build_loop_pk`

### Established Patterns
- All `build_loop_*` functions return `(ssys, ic)` dict-based initial conditions
- `ReactivityController` callables are passed via `ssys.pk.rho_c_fn => ctrl` in the op dict
- `tstops` at step insertion time ensures clean discontinuity handling
- SCRAM-02 in `test_point_kinetics.jl` is the template for LOOP-04

### Integration Points
- `build_loop_pk` connects to: `src/examples.jl` (new function), `test/test_examples.jl` (LOOP tests), `test/test_validation.jl` (VAL tests)
- Power coupling closes the neutronics↔thermal loop via `rods.fuel.power ~ pk.P * power_scale`
- Temperature feedback closes via `connect_temperature_feedback(pk, [rods.cac, rods.fuel])`

</code_context>

<specifics>
## Specific Ideas

- Use `ssys.pk.P` (not `ssys.P`) as `p_sym` in `scram_callback` when pk is nested inside a composed system
- VAL-PK-02a/b mirror the Python STREAM steady-state suppression tests exactly — same alpha magnitude (~0.1), same ref_temp = boundary condition pattern
- Python STREAM `test_channel_point_kinetics` uses 10 channels and random alphas — Julia validation can use a simpler single-channel version as long as the steady-state T_cool linearity assertion holds

</specifics>

<deferred>
## Deferred Ideas

- Multi-channel PK loop (parallel channels with different alpha weights) — v1.0
- Decay heat source term (`PointKineticsWInput`) — v1.0
- Spatial flux shape variation across the core — v1.0
- Time-varying pump wired to SCRAM (pump rundown after SCRAM) — could be Phase 49 extension
  or a separate phase; flag as a follow-on during planning
- GUI integration for PK parameters in STREAM Composer — v1.0 (Phase 50+)
- Transient power trace cross-validation against Python STREAM — deferred (Python STREAM
  doesn't have a transient PK+loop test; would require creating a new Python reference first)

</deferred>

---

*Phase: 49-full-loop-integration-validation*
*Context gathered: 2026-04-08 (updated)*
