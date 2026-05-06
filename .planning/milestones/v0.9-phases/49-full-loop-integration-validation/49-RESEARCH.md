# Phase 49: Full Loop Integration + Validation — Research

**Researched:** 2026-04-08
**Domain:** MTK coupled PK+thermal-hydraulic loop composition, validation against Python STREAM
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 (power coupling equation):**
`rods.fuel.power ~ pk.P * power_scale` — drives HeatDiffusion from normalized PK power.
`power_scale` is a plain Julia scalar at compose time, not an MTK parameter.

**D-02 (compose pattern):**
`compose_systems` + `symmetric_plate` + explicit `fb_eqs` + `power_coupling` equations merged
into the top-level connection list. `@named sys = compose(System(connections, t; name=:sys), pump, bc, rods, pk)`.

**D-03 (build_loop_pk signature):**
```julia
build_loop_pk(ctrl;
    n=7, nz=7, nx=2, T_inlet=293.15, dP_pump=3.0e4,
    P0=1.0, power_scale=1e4,
    temp_worth=nothing, ref_temp=nothing, rho_val=0.0
) -> (ssys, ic)
```
Returns `(ssys, ic)` dict-based initial conditions (not just `ssys`).

**D-04 (initial conditions):**
- PK ICs: `point_kinetics_steady_state(P0)` → `(P=P0, C_k=[...])`
- Channel ICs: `T[i] => T_inlet` for all cells
- HeatDiffusion ICs: `T[i,j] => T_fuel_init` (e.g. 600.0 K)
- `power` is an algebraic connection equation, NOT an IC
- Callable bindings: `ssys.pk.rho_c_fn => ctrl`

**D-05 (connect_temperature_feedback API):**
```julia
connect_temperature_feedback(pk, [rods.cac, rods.fuel]) -> Vector{Equation}
```
Pass scoped refs (post `symmetric_plate`). No alpha args here — alphas live in `PointKinetics` constructor.

**D-06 (test structure):**
- Plan 01: `LOOP-01..04` → `test/test_examples.jl`
- Plan 02: `VAL-PK-01..03` → `test/test_validation.jl`

**D-07 (Python STREAM reference):**
`~/projects/STREAM/tests/test_general/test_integrations.py`
- Lines 201-267: `test_channel_point_kinetics` (VAL-PK-01)
- Lines 352-387: `test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary_conditions` (VAL-PK-02a)
- Lines 390-428: `test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet` (VAL-PK-02b)

**D-08 (file placement):**
- `build_loop_pk` → `src/examples.jl`
- Integration tests → `test/test_examples.jl`
- Validation tests → `test/test_validation.jl`

**D-09 (solver settings):**
`Rodas5P()`, `abstol=1e-8`, `reltol=1e-6`, `tstops` at step insertion, `maxiters=1_000_000`.

### Claude's Discretion

No explicit discretion areas — all major decisions are locked.

### Deferred Ideas (OUT OF SCOPE)

- Multi-channel PK loop (parallel channels with different alpha weights) — v1.0
- Decay heat source term (`PointKineticsWInput`) — v1.0
- Spatial flux shape variation — v1.0
- Time-varying pump wired to SCRAM (pump rundown after SCRAM) — possible Phase 49 extension or separate phase
- GUI integration for PK parameters — v1.0 (Phase 50+)
- Transient power trace cross-validation against Python STREAM — deferred

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOOP-01 | `build_loop_pk(ctrl; ...)` compiles without error; returns `(ssys, ic)` with consistent ICs | Composition pattern verified in TF-06/TF-07 tests; `point_kinetics_steady_state` API confirmed |
| LOOP-02 | Quiescent stability: `P(t) ≈ P0 ± 1%` over 10 s with zero reactivity | Established pattern from SCRAM-02 test; `rho_val=0.0`, zero ctrl |
| LOOP-03 | Step reactivity `Δρ=0.0005` at t=0.5s; `P_max > P0` and `P[end] < P_max` | TF-07 test template; uses `tstops=[t_step]` for clean discontinuity |
| LOOP-04 | SCRAM-in-loop: `scram_callback(ssys, ssys.pk.P, ctrl)` terminates when `P > 1.2*P0` | SCRAM-02 test template; `ssys.pk.P` path confirmed for nested PK |
| VAL-PK-01 | Steady-state linear T_cool rise: `diff(T_cool) > 0` and `diff(diff(T_cool)) ≈ 0` | Python STREAM lines 201-267; uses `solve_steady` (KINSOL) not transient |
| VAL-PK-02a | Negative fuel feedback suppresses power to near zero at steady state | Python STREAM lines 352-387; `temp_worth` on fuel, `ref_temp = T_boundary` |
| VAL-PK-02b | Negative coolant feedback suppresses power to near zero at steady state | Python STREAM lines 390-428; `temp_worth` on cac, `ref_temp = T_inlet` |
| VAL-PK-03 | `sol[ssys.pk.reactivity, :]` accessible; at steady state matches `sum(alpha_i*(T_i - T_ref_i))` | `reactivity` is `@observed` in `PointKinetics`; confirmed accessible post-solve in TF-06 |

</phase_requirements>

---

## Summary

Phase 49 wires `PointKinetics` into the full thermal-hydraulic loop and validates the coupled system against Python STREAM reference results. This is primarily an integration and testing phase — no new source components are required. All building blocks exist: `symmetric_plate`, `connect_temperature_feedback`, `compose_systems`, `scram_callback`, `point_kinetics_steady_state`, and `solve_transient`.

The primary deliverable is `build_loop_pk` in `src/examples.jl`, following the exact pattern of `build_loop_transient` but adding PK coupling. The function must return `(ssys, ic)` — an ic dict is returned alongside ssys, unlike the existing `build_loop_*` functions which return only `ssys`. This is the one structural difference to watch.

Plan 01 writes integration tests (LOOP-01..04) in `test/test_examples.jl`. Plan 02 writes quantitative validation tests (VAL-PK-01..03) in `test/test_validation.jl`. The VAL tests mirror Python STREAM steady-state test patterns and use `solve_steady` (KINSOL), not transient solve.

**Primary recommendation:** Follow TF-06 (reactivity observable test) and TF-07 (negative feedback bounds power test) from `test/test_point_kinetics.jl` as direct composition templates for `build_loop_pk` — they demonstrate the exact pattern needed.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | project Manifest | MTK system composition, `compose`, `mtkcompile` | Entire codebase is MTK-based |
| DifferentialEquations | project Manifest | `Rodas5P`, `ContinuousCallback`, `terminate!` | Used throughout for transient solve |
| Sundials | project Manifest | `KINSOL` for `solve_steady` | Required for steady-state non-linear solve |

[VERIFIED: codebase — Manifest.toml + solvers.jl usage]

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| STREAM internal | — | `build_loop_pk`, `compose_systems`, `symmetric_plate` | All composition via internal helpers |
| STREAM internal | — | `point_kinetics_steady_state` | PK ICs at construction |
| STREAM internal | — | `connect_temperature_feedback` | PK↔thermal binding equations |
| STREAM internal | — | `scram_callback`, `SCRAM_at_power` | LOOP-04 SCRAM-in-loop test |

**Installation:** No new dependencies. All required packages are already in the project environment.

---

## Architecture Patterns

### build_loop_pk Composition Pattern

[VERIFIED: src/examples.jl, src/composition/helpers.jl, test/test_point_kinetics.jl TF-06/TF-07]

The composition follows three distinct stages:

**Stage 1 — Component construction:**
```julia
@named cac  = ChannelAndContacts(n=n, geometry=...,
                                  htc_correlation=..., friction_correlation=...)
@named fuel = HeatDiffusion(nz=nz, nx=nx, Lz=..., Lx=..., y=...,
                             rho_s=..., cp_s=..., k_s=..., power_shape=...)
rods = symmetric_plate(cac, fuel; name=:rods)   # scoped rods.cac, rods.fuel
```

**Stage 2 — PK construction (MUST use scoped refs as keys):**
```julia
# temp_worth keys must be scoped (rods.cac, rods.fuel), not originals (cac, fuel)
@named pk = PointKinetics(ctrl; rho_val=rho_val,
                           temp_worth=Dict(rods.cac => alpha_cac, rods.fuel => alpha_fuel),
                           ref_temp=Dict(rods.cac => T_inlet, rods.fuel => T_fuel_ref))
```

**Stage 3 — Connections and compose:**
```julia
fb_eqs       = connect_temperature_feedback(pk, [rods.cac, rods.fuel])
power_eqs    = [rods.fuel.power ~ pk.P * power_scale]
@named pump  = Pump(dP_pump)
@named bc    = HeatExchanger(T_inlet)

all_connections = [
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out, rods.cac.port_in),
    connect(rods.cac.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,       # pressure anchor (required)
    fb_eqs...,
    power_eqs...,
]

full = compose_systems(rods, pk, pump, bc;
                        connections=all_connections, name=:sys)
ssys = mtkcompile(full)
```

**Critical:** `compose_systems` (not bare `compose`) wraps the `System(connections, t)` creation. See `src/composition/helpers.jl:285-287`. [VERIFIED: codebase]

### IC Dict Pattern

[VERIFIED: test/test_point_kinetics.jl TF-06 lines 442-455]

```julia
ic7 = point_kinetics_steady_state(P0)
op = Pair{Any,Any}[
    ssys.pk.rho_c_fn => ctrl,         # callable parameter — MUST be Pair{Any,Any}
    ssys.pk.P        => ic7.P,
    ssys.pk.C_1      => ic7.C_k[1],
    # ... C_2 through C_6 ...
    ssys.rods.cac.port_in.mdot => 0.2,
    [ssys.rods.cac.T[i]     => T_inlet  for i in 1:n]...,
    [ssys.rods.fuel.T[i, j] => T_fuel_0 for i in 1:nz for j in 1:nx]...,
]
```

Key insight: `ssys` IS the composed root system after `mtkcompile` — no extra prefix needed. `ssys.pk.P` not `ssys.sys.pk.P`. [VERIFIED: STATE.md TF-02 decision + TF-06 test]

### Steady-State Solve for VAL Tests

[VERIFIED: test/test_validation.jl pattern + src/solvers.jl]

VAL-PK-01 uses `solve_steady` (KINSOL), not `solve_transient`. The Python STREAM reference
(`test_channel_point_kinetics`) calls `agr.solve_steady(...)`. Matching this approach
requires an operating point guess that gives KINSOL something reasonable to start from.
Initial guess strategy: `T_cool[i] => T_inlet`, `T_fuel[i,j] => T_fuel_0`, `mdot => 0.2`,
PK at `point_kinetics_steady_state(P0)`.

VAL-PK-02a/b use either `solve_steady` with strong feedback IC (power starting high to
let KINSOL find the zero) or a long `solve_transient` to reach steady state. Python STREAM
uses `agr.solve_steady(y0)` where `y0` has `power=1e5` and `ck=1e3` as large initial
guesses — the strong negative feedback drives KINSOL to `P ≈ 0`. The Julia equivalent
should also use `solve_steady` with a large initial power guess.

### scram_callback in Nested PK

[VERIFIED: src/components/point_kinetics.jl lines 490-513, CONTEXT.md D-06]

```julia
# PK nested as :pk subsystem (Phase 49 LOOP-04)
cb = scram_callback(ssys, ssys.pk.P, ctrl)
# NOT: scram_callback(ssys, ssys.P, ctrl)   — that's standalone PK only
```

`scram_callback` resolves `variable_index(ssys, p_sym)` eagerly at construction time.
After `mtkcompile`, `ssys.pk.P` is the correct symbolic path when PK is a subsystem named `:pk`. [VERIFIED: SCRAM-02 test comment + scram_callback docstring]

### Anti-Patterns to Avoid

- **Using original (unscoped) `cac`/`fuel` as temp_worth keys after symmetric_plate:** After `rods = symmetric_plate(cac, fuel; name=:rods)`, use `rods.cac` and `rods.fuel` as keys, not the original `cac`/`fuel` variables.
- **Extra prefix in IC dict:** `ssys` IS the root after `mtkcompile`. `ssys.rods.cac.T[i]` is correct; `ssys.sys.rods.cac.T[i]` is wrong and causes `KeyError`. [VERIFIED: STATE.md TF-02]
- **`power` as IC:** `rods.fuel.power ~ pk.P * power_scale` is an equation (algebraic connection), not an initial condition. Do not include `ssys.rods.fuel.power => ...` in op dict.
- **Using bare `Pair[]` instead of `Pair{Any,Any}[]`:** MTK callable parameters require `Pair{Any,Any}` for the op dict to avoid type inference failures. [VERIFIED: STATE.md PK-06]
- **`ssys.P` instead of `ssys.pk.P` for nested PK:** Wrong symbolic path in composed system causes `variable_index` to fail in `scram_callback`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PK initial conditions | Custom C_k formula | `point_kinetics_steady_state(P0)` | Exact criticality formula already implemented |
| Temperature feedback binding | Manual equation loop | `connect_temperature_feedback(pk, comps)` | Handles 1D/2D flattening, row-major order |
| Channel-fuel plate wiring | Manual `connect()` loops | `symmetric_plate(cac, fuel; name)` | Standard connection pattern |
| Multi-system composition | Bare MTK `compose` | `compose_systems(systems...; connections, name)` | Thin wrapper that keeps connection list clean |
| Stiff ODE solve | Custom integrator | `solve_transient(ssys, op, t; tstops, callbacks)` | Already wired for `NoInit`, `saveat`, callback forwarding |
| SCRAM event detection | Manual ODE callback | `scram_callback(ssys, p_sym, ctrl)` | Correctly uses `u[p_idx]` not `integrator[sym]` to avoid sign-change blindness |

---

## Common Pitfalls

### Pitfall 1: scoped vs unscoped component refs in temp_worth dict

**What goes wrong:** `PointKinetics(ctrl; temp_worth=Dict(cac => alpha))` — using original `cac` as key. After `symmetric_plate`, PK's T_source variable is named `T_source_cac`, but the unscoped `cac` symbolic has the wrong namespace, causing the binding equations to reference wrong symbolics.

**Why it happens:** `symmetric_plate` rescopes all symbols under `rods.cac.*`. The original `cac` variable still points to the unscoped namespace.

**How to avoid:** Always build `rods = symmetric_plate(cac, fuel; name=:rods)` FIRST, then pass `rods.cac` and `rods.fuel` as keys to `PointKinetics`.

**Warning signs:** `KeyError` or wrong equation count from `connect_temperature_feedback`.

[VERIFIED: STATE.md TF-01 decision; TF-06 test uses `Dict(rods.cac => ...)` pattern]

### Pitfall 2: power variable in op dict causes overdetermination

**What goes wrong:** Including `ssys.rods.fuel.power => some_value` in the IC dict alongside `rods.fuel.power ~ pk.P * power_scale`. MTK sees two constraints for `power` and either errors or ignores one silently.

**Why it happens:** `power(t)` is declared as `@variables power(t) = power_init` in HeatDiffusion — it's an unknown, not a parameter. The connection equation `rods.fuel.power ~ pk.P * power_scale` algebraically ties it to `pk.P`. No initial condition is needed; the initial value is determined by `pk.P` at t=0.

**How to avoid:** Omit `fuel.power` from op dict entirely. [VERIFIED: CONTEXT.md D-04; heat_diffusion.jl lines 111-113]

### Pitfall 3: Wrong symbolic path after mtkcompile

**What goes wrong:** `ssys.core.rods.cac.T[i]` or `ssys.sys.pk.P` causes `KeyError`.

**Why it happens:** `compose_systems(..., name=:sys)` names the intermediate system `:sys`, but `mtkcompile` produces a flat compiled system where `ssys` IS `:sys` — the name prefix is stripped.

**How to avoid:** Always use `ssys.rods.cac.T[i]` (one level of prefix for the `rods` subsystem, then `cac` inside it). Check TF-06 test for the exact pattern. [VERIFIED: STATE.md TF-02; TF-06 op dict]

### Pitfall 4: KINSOL for VAL-PK-02a/b needs large initial power guess

**What goes wrong:** Starting KINSOL at `pk.P => 1.0` (the "correct" steady-state guess for normal operation) with strong negative feedback. KINSOL finds the trivial `P=0` solution because the Jacobian is nearly zero at low power with negative feedback.

**Why it happens:** Python STREAM's test explicitly starts with `y0[power]=1e5` and `y0[ck]=1e3` — large values that force KINSOL away from the trivial zero. Without this, KINSOL may converge to `P=0` but with non-physical state, or fail to converge.

**How to avoid:** For VAL-PK-02a/b, set `pk.P => 1e3` (or similarly large) in the op dict; KINSOL will find the stable `P ≈ 0` solution driven by negative feedback. Alternatively, use `solve_transient` with a long tspan and read the final state.

**Warning signs:** `sol.retcode != :Success` or `sol[ssys.pk.P]` returning the initial large value unchanged.

[VERIFIED: Python STREAM test_integrations.py lines 379-386]

### Pitfall 5: tstops required for clean step reactivity insertion

**What goes wrong:** Without `tstops=[t_step]`, the integrator may step over the discontinuity in `rho_c_fn`, causing the step to be "smeared" across multiple solver steps, producing inaccurate power traces or false failures in `P_max > P0` assertions.

**Why it happens:** Adaptive step-size ODE solvers choose step sizes based on smoothness. A jump discontinuity in a forcing function is not smooth.

**How to avoid:** Always pass `tstops=[t_step]` to `solve_transient` when inserting a step reactivity. [VERIFIED: CONTEXT.md D-09; TF-07 uses `tstops=[t_step]`]

### Pitfall 6: build_loop_pk returns (ssys, ic) not just ssys

**What goes wrong:** Planner or test code expects `ssys = build_loop_pk(ctrl)` (single return). But the function returns `(ssys, ic)`.

**Why it happens:** Unlike the existing `build_loop_*` functions (which return only `ssys`), `build_loop_pk` also computes and returns the IC dict to make caller code simpler.

**How to avoid:** Document clearly in docstring. Tests must unpack: `ssys, ic = build_loop_pk(ctrl; ...)`. [VERIFIED: CONTEXT.md D-03]

---

## Code Examples

### Minimal build_loop_pk skeleton (from TF-06/TF-07 patterns)

[VERIFIED: src/components/point_kinetics.jl, src/composition/helpers.jl, test/test_point_kinetics.jl TF-06]

```julia
function build_loop_pk(ctrl;
    n=7, nz=7, nx=2, T_inlet=293.15, dP_pump=3.0e4,
    P0=1.0, power_scale=1e4,
    temp_worth=nothing, ref_temp=nothing, rho_val=0.0,
)
    # Geometry for n-cell rectangular channel (typical MTR fuel plate geometry)
    geom = PipeGeometry_rectangular(...)

    @named cac  = ChannelAndContacts(n=n, geometry=geom, ...)
    @named fuel = HeatDiffusion(nz=nz, nx=nx, ...)
    rods = symmetric_plate(cac, fuel; name=:rods)   # scoped: rods.cac, rods.fuel

    # Build temp_worth/ref_temp dicts with scoped keys (if provided)
    tw = isnothing(temp_worth) ? nothing : ...
    rt = isnothing(ref_temp)   ? nothing : ...

    @named pk   = PointKinetics(ctrl; rho_val=rho_val, temp_worth=tw, ref_temp=rt)
    @named pump = Pump(dP_pump)
    @named bc   = HeatExchanger(T_inlet)

    fb_eqs    = isnothing(temp_worth) ? Equation[] :
                    connect_temperature_feedback(pk, [rods.cac, rods.fuel])
    power_eqs = [rods.fuel.power ~ pk.P * power_scale]

    all_connections = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        fb_eqs...,
        power_eqs...,
    ]
    full = compose_systems(rods, pk, pump, bc;
                            connections=all_connections, name=:sys)
    ssys = mtkcompile(full)

    # Build IC dict
    pk_ic = point_kinetics_steady_state(P0)
    ic = Pair{Any,Any}[
        ssys.pk.rho_c_fn => ctrl,
        ssys.pk.P        => pk_ic.P,
        ssys.pk.C_1      => pk_ic.C_k[1],
        ssys.pk.C_2      => pk_ic.C_k[2],
        ssys.pk.C_3      => pk_ic.C_k[3],
        ssys.pk.C_4      => pk_ic.C_k[4],
        ssys.pk.C_5      => pk_ic.C_k[5],
        ssys.pk.C_6      => pk_ic.C_k[6],
        ssys.rods.cac.port_in.mdot => 0.2,
        [ssys.rods.cac.T[i]     => T_inlet  for i in 1:n]...,
        [ssys.rods.fuel.T[i, j] => 600.0    for i in 1:nz for j in 1:nx]...,
    ]
    return (ssys, ic)
end
```

### LOOP-04 SCRAM-in-loop test pattern

[VERIFIED: SCRAM-02 test in test_point_kinetics.jl lines 586-632; CONTEXT.md D-06]

```julia
scram_ir = (state, t_state, t) -> state == :SCRAM ? -0.05 : (t >= t_step ? delta_rho : 0.0)
ctrl = ReactivityController(scram_ir;
    initial_state = :NORMAL,
    state_machine = SCRAM_at_power(1.2),   # P > 1.2*P0 triggers SCRAM
    abort_states  = Set([:SCRAM]))

ssys, ic = build_loop_pk(ctrl; ...)
# ssys.pk.P — correct path for nested PK (not ssys.P)
cb = scram_callback(ssys, ssys.pk.P, ctrl)

t_arr = range(0.0, 10.0; length=1000)
sol = solve_transient(ssys, ic, t_arr; tstops=[t_step], callbacks=cb)

@test sol.t[end] < 10.0         # terminated early
@test ctrl.state == :SCRAM      # state machine transitioned
```

### VAL-PK-01 steady-state linear temperature rise pattern

[VERIFIED: Python STREAM test_integrations.py lines 201-267; test/test_validation.jl VAL-01 pattern]

```julia
# Build with zero ctrl reactivity (constant-power steady state)
ctrl_zero = ReactivityController()
ssys, ic = build_loop_pk(ctrl_zero; n=7, T_inlet=293.15)

sol = solve_steady(ssys, ic)
T_cool = sol[ssys.rods.cac.T]   # length-n vector

@test all(diff(T_cool) .> 0)                         # strictly rising
@test isapprox(diff(diff(T_cool)), zeros(n-2); atol=1e-3)  # linear (second diff ≈ 0)
```

### VAL-PK-02a/b power suppression pattern

[VERIFIED: Python STREAM test_integrations.py lines 352-428]

```julia
# Strong negative feedback: power should converge to near zero
ctrl_zero = ReactivityController()
alpha_neg = -0.1   # large negative worth (same magnitude as Python STREAM 1e-1)
ssys, ic = build_loop_pk(ctrl_zero;
    temp_worth = Dict(:fuel => alpha_neg),  # or :cac for VAL-PK-02b
    ref_temp   = Dict(:fuel => T_boundary), # ref_temp at boundary (VAL-PK-02a)
)

# Start with large power so KINSOL finds the physical P≈0 solution
ic_high_power = copy(ic)
# Override power IC to large value (guides KINSOL away from trivial zero)
# pk.C_k start high too (matching Python STREAM y0[ck]=1e3)
sol = solve_steady(ssys, ic_high_power)
@test sol[ssys.pk.P] < 1e-3     # near-zero power
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Standalone PK (Phase 45) | PK coupled to T-H loop | Phase 49 | Closes neutron↔thermal feedback loop |
| `scram_callback(ssys, ssys.P, ctrl)` | `scram_callback(ssys, ssys.pk.P, ctrl)` | Phase 49 (nested PK) | `p_sym` path depends on whether PK is root or subsystem |
| `build_loop_*` returns `ssys` only | `build_loop_pk` returns `(ssys, ic)` | Phase 49 | IC dict returned pre-built for convenience |

**Deprecated/outdated:**
- `connect_temperature_feedback(pk, temp_worth_dict; scoped_comps=...)` — old API from early Phase 47 design. Current API is `connect_temperature_feedback(pk, components)` with scoped components list. [VERIFIED: src/composition/helpers.jl:328]

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`@testset`, `@test`) |
| Config file | none — Julia test discovery via `test/runtests.jl` |
| Quick run command | `julia --project=. test/runtests.jl` |
| Full suite command | `julia --project=. test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | File | Automated Command |
|--------|----------|-----------|------|-------------------|
| LOOP-01 | `build_loop_pk` compiles, returns `(ssys, ic)` | integration | `test/test_examples.jl` | `julia --project=. test/runtests.jl` |
| LOOP-02 | Quiescent stability: `P ≈ P0 ± 1%` over 10s | integration | `test/test_examples.jl` | same |
| LOOP-03 | Step `Δρ`: `P_max > P0` and `P[end] < P_max` | integration | `test/test_examples.jl` | same |
| LOOP-04 | SCRAM terminates loop; `ctrl.state == :SCRAM` | integration | `test/test_examples.jl` | same |
| VAL-PK-01 | Linear T_cool rise at steady state | validation | `test/test_validation.jl` | same |
| VAL-PK-02a | Negative fuel feedback → `P < 1e-3` at SS | validation | `test/test_validation.jl` | same |
| VAL-PK-02b | Negative coolant feedback → `P < 1e-3` at SS | validation | `test/test_validation.jl` | same |
| VAL-PK-03 | `sol[ssys.pk.reactivity, :]` accessible and correct | validation | `test/test_validation.jl` | same |

### Sampling Rate
- **Per task commit:** `julia --project=. test/runtests.jl`
- **Per wave merge:** `julia --project=. test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
The test files exist but are mostly empty or minimal for Phase 49 targets:
- [ ] `test/test_examples.jl` — currently has only a smoke COMPAT test; needs LOOP-01..04 `@testset` blocks
- [ ] `test/test_validation.jl` — has VAL-01/02; needs new `@testset "PointKinetics validation"` block for VAL-PK-01..03

No new test infrastructure (conftest, fixtures) required — existing `using STREAM`, `using Test`, `using DifferentialEquations` pattern suffices.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all tests | yes | 1.12.5 | — |
| stream.so sysimage | fast test runs | no | — | Run without sysimage (slow, ~60-120s TTFX) |
| Python STREAM | reference inspection | yes | ~/projects/STREAM | — |

**Missing dependencies with no fallback:**
- None that block execution.

**Missing sysimage impact:** Tests will run but TTFX will be ~60-120 seconds per fresh Julia invocation. The `check_sysimage_ready.sh` script and `build_sysimage.sh` are available to rebuild if needed. Plan execution should use `test -f stream.so && SYSIMG="--sysimage stream.so" || SYSIMG=""` pattern from CLAUDE.md.

---

## Security Domain

This phase has no external API surfaces, authentication, or user-facing inputs. Security domain is not applicable.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | VAL-PK-02a/b can be validated with `solve_steady` using large initial power | Common Pitfalls #4, Code Examples | If KINSOL fails to converge, fallback is long `solve_transient`; assertion on `sol[end]` |
| A2 | `build_loop_pk` should accept `temp_worth` as a plain dict (component name → alpha) and resolve scoping internally | Architecture Patterns (build_loop_pk skeleton) | If the function signature differs in the plan, the IC scoping logic may be wrong |
| A3 | `rods.cac.port_in.mdot => 0.2` is a reasonable initial mdot for the hydraulic ICs in the coupled system | Code Examples | Convergence failures if mdot IC is too far from the physical solution; might need tuning |

**Note on A3:** TF-06 and TF-07 use `0.2 kg/s` successfully for the channel-fuel assembly with `dP_pump=3.0e4`. Phase 49 uses the same geometry/pump, so this should transfer directly.

---

## Open Questions

1. **VAL-PK-02a/b: solve_steady vs. solve_transient**
   - What we know: Python STREAM uses `agr.solve_steady(y0)` with `y0[power]=1e5, y0[ck]=1e3`
   - What's unclear: Whether KINSOL converges for the coupled PK+T-H system with strong negative feedback when starting from large power. TF-07 used `solve_transient` for the analogous test.
   - Recommendation: Plan should first attempt `solve_steady` with large IC; if KINSOL fails, fall back to long `solve_transient` (e.g. tspan=100s) and assert on `sol[ssys.pk.P, end]`.

2. **`build_loop_pk` temp_worth interface design**
   - What we know: `temp_worth` keys must be scoped post-`symmetric_plate`. The function signature takes `temp_worth=nothing`.
   - What's unclear: How should the user pass `temp_worth` to `build_loop_pk` when the scoped refs don't exist until inside the function? The planner needs to decide whether to use internal component names (`:cac`, `:fuel`) as keys and resolve scoping inside the function, or expose the limitation in the signature.
   - Recommendation: Use `Symbol` keys (`:cac`, `:fuel`) in the external API and resolve to scoped refs inside `build_loop_pk`. This is simpler for the caller.

3. **VAL-PK-01: `solve_steady` convergence for fully-coupled PK+loop**
   - What we know: Python STREAM asserts linear T_cool rise; uses 10 channels with random alphas.
   - What's unclear: Whether KINSOL converges for the fully-coupled system at steady state with feedback active. Phase 47 TF-07 used transient not steady-state.
   - Recommendation: Attempt `solve_steady` first. If KINSOL fails, use `solve_transient` with large tspan and assert on final-state T_cool.

---

## Sources

### Primary (HIGH confidence)
- `src/examples.jl` — `build_loop`, `build_loop_transient`, `build_loop_vertical` patterns
- `src/components/point_kinetics.jl` — `PointKinetics`, `scram_callback`, `SCRAM_at_power`, `point_kinetics_steady_state`
- `src/composition/helpers.jl:285-348` — `compose_systems`, `connect_temperature_feedback`
- `src/components/heat_diffusion.jl` — `power(t)` as `@variables`, `HeatDiffusion` constructor
- `test/test_point_kinetics.jl:400-546` — TF-06 (reactivity observable), TF-07 (negative feedback bounds power), SCRAM-02 (scram_callback)
- `test/test_validation.jl` — VAL-01/02 patterns for solve_steady usage
- `src/solvers.jl` — `solve_transient`, `solve_steady` API

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — accumulated decisions TF-01, TF-02, TF-03, PK-06
- `.planning/phases/49-full-loop-integration-validation/49-CONTEXT.md` — all design decisions D-01..D-09

### Tertiary (LOW confidence)
- `~/projects/STREAM/tests/test_general/test_integrations.py:201-428` — Python STREAM reference (verified existence, read lines 201-428)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all verified from codebase
- Architecture patterns: HIGH — direct transcription from TF-06/TF-07 working tests
- Pitfalls: HIGH — all verified from STATE.md decisions or test code comments
- VAL test convergence strategy: MEDIUM — based on Python STREAM pattern, not yet run in Julia

**Research date:** 2026-04-08
**Valid until:** 2026-05-08 (stable Julia/MTK codebase, no external dependencies)
