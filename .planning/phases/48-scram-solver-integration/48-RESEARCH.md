# Phase 48: SCRAM + Callback Factory Pattern — Research

**Researched:** 2026-04-08
**Domain:** ModelingToolkit ContinuousCallback, Julia struct/callable patterns, DifferentialEquations integrator API
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Unified callback factory pattern**
All event-driven components expose a `_callback(ssys, ...)` factory returning an external `DifferentialEquations.ContinuousCallback`. Users pass it to `solve_transient` via `callbacks=`. `ContinuousCallback` everywhere — no `DiscreteCallback`. No callbacks embedded inside components.

**D-02: SCRAM_at_power — struct, not bare function**
`SCRAM_at_power(power_limit)` returns a `SCRAMCondition` struct (not a closure). `scram_callback` reads `.power_limit` directly from `ctrl.state_machine`.

**D-03: scram_callback — ContinuousCallback with terminate!**
Condition: `integrator[p_sym] - plimit`. Affect: `change_state(ctrl, integrator.t, P, dP)` + optional `terminate!(integrator)`. `terminate=true` default.

**D-04: dPdt via integrator.du, NOT variable_index on dPdt**
`dPdt` is `@observed` — not in ODE state vector. Use `p_idx = variable_index(ssys, p_sym)` then `integrator.du[p_idx]` for dPdt. Use `integrator[p_sym]` for P value.

**D-05: Flapper refactor — remove SymbolicContinuousCallback**
Remove `use_callback`, `threshold` from Flapper constructor. Remove `SymbolicContinuousCallback` import. Always emit pure equation system.

**D-06: flapper_callback factory**
`flapper_callback(ssys; threshold=0.01)` returns `ContinuousCallback` with downward-crossing affect `integrator.u[T_open_idx] = integrator.t`.

**D-07: Test updates**
FLAP-05 updated to use external `flapper_callback`. LOF-02 simplified to use `flapper_callback`. New SCRAM-01 and SCRAM-02 testsets in `test/test_point_kinetics.jl`.

**D-08: File placement and exports**
`SCRAMCondition`, `SCRAM_at_power`, `scram_callback` in `src/components/point_kinetics.jl`.
`flapper_callback` in `src/components/flapper.jl`.
Remove `SymbolicContinuousCallback` import from `flapper.jl`.
Exports added to `src/STREAM.jl`: `scram_callback`, `flapper_callback`, `SCRAMCondition`.

**D-09: terminate! is optional**
`terminate=true` default (saves compute). Pass `terminate=false` to simulate full post-SCRAM shutdown transient.

### Claude's Discretion

None specified — all decisions are locked.

### Deferred Ideas (OUT OF SCOPE)

- Power-to-heat coupling (`fuel.power ~ pk.P * scale`) — Phase 49
- `build_loop_pk` example — Phase 49
- Python STREAM cross-validation — Phase 49
- Multiple simultaneous SCRAM conditions — document `CallbackSet(cb1, cb2)` pattern but don't implement new types
- `flapper_callback(ssys, flapper_sys; threshold)` with explicit component arg — future
- Automatic `change_state` wiring in `solve_transient` — future convenience
</user_constraints>

---

## Summary

Phase 48 establishes a unified callback factory pattern for event-driven components in STREAM.jl. Every component whose behavior changes based on a threshold event exposes a `_callback(ssys, ...)` factory that returns an external `DifferentialEquations.ContinuousCallback` passed to `solve_transient`. The two deliverables are: (1) SCRAM support via `SCRAMCondition` struct, `SCRAM_at_power` constructor, and `scram_callback(ssys, ctrl)` factory; (2) Flapper refactor removing the internal `SymbolicContinuousCallback` and replacing it with a `flapper_callback(ssys; threshold)` factory.

The design is fully locked in CONTEXT.md with all technical details resolved (including the dPdt-is-observed correction from the discussion log). The research below verifies that the locked design is implementable against the actual codebase state and documents the precise implementation knowledge needed for the planner.

**Primary recommendation:** Implement exactly as specified in CONTEXT.md D-01 through D-09. All patterns are established in the codebase — this is formalization, not invention.

---

## Standard Stack

### Core (already in Project.toml)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | v11 | MTK symbolic system + `variable_index` | Project foundation |
| DifferentialEquations | current | `ContinuousCallback`, `CallbackSet`, `terminate!` | Already used in codebase |
| OrdinaryDiffEq | v6.109+ | `Rodas5P` solver, `integrator.du`, `integrator.u` | Already used |

[VERIFIED: src/STREAM.jl imports, test/test_flapper.jl line 4, test/test_loss_of_flow.jl line 4]

No new dependencies. All required types (`ContinuousCallback`, `CallbackSet`, `variable_index`, `terminate!`) are already available.

### No Installation Required

Phase 48 adds no new packages. The DifferentialEquations package already provides:
- `ContinuousCallback(condition, affect_pos!, affect_neg!)` — [VERIFIED: test/test_flapper.jl:143, test/test_loss_of_flow.jl:119]
- `CallbackSet(cb1, cb2, ...)` — [VERIFIED: test/test_flapper.jl:149]
- `terminate!(integrator)` — [ASSUMED: standard DiffEq API, not yet used in codebase]
- `ModelingToolkit.variable_index(ssys, sym)` — [VERIFIED: test/test_loss_of_flow.jl:117-118]

---

## Architecture Patterns

### Current Codebase State (pre-Phase 48)

**`src/components/point_kinetics.jl`** [VERIFIED: file read]

Existing exports available to Phase 48:
- `ReactivityController{S,F}` mutable struct with fields: `input_reactivity`, `state_machine`, `state`, `t_state`, `log`, `abort_states`
- `change_state(ctrl, t_now, power, dPdt)` — transitions state, appends to log when state changes
- `worth(ctrl, t_now)` — returns `input_reactivity(state, t_state, t_now)`
- `(ctrl::ReactivityController)(t)` — callable, forwards to `worth`
- `PointKinetics(rho_c_fn::Any; name, ...)` — callable mode with P, C_1..C_6 as ODE state vars
- `P` is an ODE state variable (can use `variable_index`); `dPdt` is `@observed` (CANNOT use `variable_index`)

**`src/components/flapper.jl`** [VERIFIED: file read]

Current state (to be modified in Phase 48):
- Line 3: `using ModelingToolkit: SymbolicContinuousCallback` — REMOVE this import
- Constructor has `use_callback=true`, `threshold` as `@parameters` — REMOVE both
- Lines 76-88: conditional `if use_callback ... SymbolicContinuousCallback ... end` branch — REMOVE, always emit `compose(System(eqs, t, vars, pars; name=name), port_in, port_out)`
- `T_open`, `xi`, `ref_mdot`, `D(T_open) ~ 0`, resistance equation — ALL UNCHANGED

**`src/solvers.jl`** [VERIFIED: lines 99-117]

`solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...)` — `callback = callbacks` forwarded to DiffEq `solve`. No changes needed.

**`src/STREAM.jl`** [VERIFIED: file read]

Current exports include `ReactivityController, worth, change_state`. Need to add: `SCRAMCondition`, `scram_callback`, `flapper_callback`.

### The External ContinuousCallback Pattern (Established)

The exact pattern Phase 48 formalizes is already proven in `test/test_loss_of_flow.jl:113-125` [VERIFIED]:

```julia
# LOF-02: established pattern that flapper_callback formalizes
i_T_open   = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
i_ine_mdot = ModelingToolkit.variable_index(ssys, ssys.ine.port_in.mdot)
cb = ContinuousCallback(
    (u, t, integrator) -> u[i_ine_mdot] - BYPASS_THRESHOLD,
    nothing,                                         # ignore upward crossing
    (integrator) -> (integrator.u[i_T_open] = integrator.t),  # downward: latch T_open
)
sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```

And user-supplied callbacks already pass through to DiffEq in `test/test_flapper.jl:134-153` [VERIFIED]:
```julia
user_cb = ContinuousCallback(
    (u, t_val, integ) -> t_val - 5.0,
    integ -> (fired[] = true)
)
sol = solve_transient(ssys, op, t_arr; callbacks=CallbackSet(user_cb))
```

### Pattern 1: SCRAMCondition Struct (D-02)

**What:** A callable struct encapsulating `power_limit` so `scram_callback` can read it without the user duplicating the threshold value.

**Implementation:**

```julia
# Source: CONTEXT.md D-02
struct SCRAMCondition
    power_limit::Float64
end
SCRAM_at_power(power_limit) = SCRAMCondition(Float64(power_limit))
# Callable as state_machine: (state, t, P, dPdt) -> new_state
(s::SCRAMCondition)(state, t, P, dPdt) = P > s.power_limit ? :SCRAM : state
```

The callable signature `(state, t, P, dPdt) -> new_state` matches the `state_machine` field contract in `ReactivityController` (which calls `ctrl.state_machine(ctrl.state, t_now, power, dPdt)` in `change_state`). [VERIFIED: src/components/point_kinetics.jl:401]

### Pattern 2: scram_callback Factory (D-03, D-04)

**What:** Returns a `ContinuousCallback` that fires when P exceeds power_limit (upward zero-crossing of `P - plimit`).

**Key implementation detail — dPdt access:**

`dPdt` is `@observed` in `point_kinetics.jl:104-105`. `variable_index` only works for ODE state variables. The correct approach [VERIFIED from DISCUSSION-LOG.md]:
1. `p_sym = ssys.pk.P` (or `ssys.P` if PK is root)
2. `p_idx = variable_index(ssys, p_sym)` — index of P in ODE state vector u
3. In affect!: `integrator[p_sym]` for P value (symbolic indexing, clean)
4. In affect!: `integrator.du[p_idx]` for dPdt (ODE derivative of P = dPdt by formulation)

```julia
# Source: CONTEXT.md D-03 + D-04 corrections from DISCUSSION-LOG.md
function scram_callback(ssys, ctrl; terminate=true)
    p_sym  = ssys.pk.P
    p_idx  = variable_index(ssys, p_sym)          # for du access (dPdt)
    plimit = ctrl.state_machine.power_limit        # from SCRAMCondition

    condition = (u, t, integrator) -> integrator[p_sym] - plimit

    affect! = function(integrator)
        P  = integrator[p_sym]
        dP = integrator.du[p_idx]
        change_state(ctrl, integrator.t, P, dP)   # transitions ctrl.state -> :SCRAM
        terminate && terminate!(integrator)
    end

    ContinuousCallback(condition, affect!)  # fires on upward crossing
end
```

**Note on namespace:** `ssys.pk.P` assumes the PK subsystem is named `:pk`. If PK is the root system (e.g., `@named pk = PointKinetics(...); ssys = mtkcompile(pk)`), use `ssys.P`. The test will use the root namespace pattern for standalone PK testing.

### Pattern 3: flapper_callback Factory (D-06)

**What:** Returns a `ContinuousCallback` for downward-crossing of `ref_mdot - threshold`, latching `T_open = integrator.t`.

```julia
# Source: CONTEXT.md D-06
function flapper_callback(ssys; threshold=0.01)
    T_open_idx   = variable_index(ssys, ssys.flapper.T_open)
    ref_mdot_sym = ssys.flapper.ref_mdot

    condition = (u, t, integrator) -> integrator[ref_mdot_sym] - threshold
    affect!   = (integrator) -> (integrator.u[T_open_idx] = integrator.t)

    ContinuousCallback(
        condition,
        nothing,   # ignore upward crossing
        affect!    # downward crossing: latch T_open
    )
end
```

**Key note:** `ref_mdot_sym` uses `integrator[sym]` (symbolic indexing via SymbolicIndexingInterface) rather than `variable_index` because `ref_mdot` may be an algebraic variable (substituted away by `mtkcompile`). Symbolic indexing follows substitution chains correctly. [VERIFIED: LOF-02 uses `u[i_ine_mdot]` for direct u-index access but CONTEXT.md D-06 specifies symbolic indexing for ref_mdot for safety.]

### Pattern 4: Flapper Component Simplification (D-05)

Remove from `src/components/flapper.jl`:
1. Line 3: `using ModelingToolkit: SymbolicContinuousCallback`
2. `use_callback=true` from constructor signature
3. `threshold=0.01` from constructor signature (moves to flapper_callback kwarg)
4. `threshold` from `@parameters` block
5. The `if use_callback ... else ... end` branch — replace with single `compose(...)` call

Result: Flapper is a pure equation system. Tests that previously passed `Flapper(; use_callback=false)` or relied on `use_callback=true` must be updated.

### Anti-Patterns to Avoid

- **Using `variable_index` on `@observed` variables:** `dPdt`, `beta_total`, `reactivity` are all `@observed` in PointKinetics. `variable_index` returns `nothing` for these. Use `integrator.du[p_idx]` (where `p_idx` is the index of P) to access dPdt.
- **Calling `change_state` in the condition function:** The condition is evaluated many times per step (rootfinding). Side effects in condition cause multiple state transitions. Only call `change_state` in `affect!`.
- **Using `DiscreteCallback` instead of `ContinuousCallback`:** `DiscreteCallback` fires at accepted steps only, giving imprecise event timing. `ContinuousCallback` uses rootfinding to find the exact zero-crossing time. Codebase convention is `ContinuousCallback` throughout.
- **Putting callbacks inside components:** `SymbolicContinuousCallback` inside Flapper already failed with `UnsolvableCallbackError` in parallel bypass topology. External callbacks always work.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Precise event time detection | Custom step-size control | `ContinuousCallback` | Rootfinding gives exact crossing time via interpolation |
| Integrator early termination | Manual flag + if-check | `terminate!(integrator)` | Built-in DiffEq API, propagates cleanly |
| Symbolic variable indexing | Raw array index arithmetic | `integrator[sym]` | Handles structural simplification transparently |

---

## Common Pitfalls

### Pitfall 1: variable_index on @observed variables

**What goes wrong:** `variable_index(ssys, ssys.pk.dPdt)` returns `nothing`. Using it as an array index throws `BoundsError` or `MethodError`.

**Why it happens:** `dPdt`, `beta_total`, `reactivity` are declared in the `observed=obs` argument of the MTK `System` constructor — they are not ODE state variables and have no index in `u` or `du`.

**How to avoid:** Use `variable_index(ssys, ssys.pk.P)` to get P's index, then `integrator.du[p_idx]` is dPdt by ODE formulation (`Dt(P) ~ ...`).

**Warning signs:** `variable_index` returning `nothing`, `BoundsError` accessing `integrator.du[nothing]`.

### Pitfall 2: Condition function with side effects

**What goes wrong:** Calling `change_state` inside the condition function causes multiple premature state transitions (condition is evaluated at every rootfinding step).

**Why it happens:** `ContinuousCallback` condition is called many times during the rootfinding interpolation bracket, not just once at the final event time.

**How to avoid:** Condition is pure `Float64` arithmetic only (`integrator[p_sym] - plimit`). All mutations (`change_state`, `terminate!`) go in `affect!`.

### Pitfall 3: Flapper tests using use_callback=true expecting old behavior

**What goes wrong:** After removing `use_callback` from Flapper, any test calling `Flapper(; use_callback=true)` or `Flapper(; use_callback=false)` will throw a `MethodError` (unknown keyword argument).

**Why it happens:** The constructor signature changes. FLAP-05 in `test/test_flapper.jl` uses `_build_flapper_scalar_loop` which currently relies on the internal callback for the event.

**How to avoid:** FLAP-05 must be updated to use `flapper_callback(ssys; threshold=...)` via `callbacks=`. LOF-02 must be updated to call `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)` instead of the manual `variable_index` pattern.

### Pitfall 4: ssys.pk.P namespace vs ssys.P

**What goes wrong:** `scram_callback` uses `ssys.pk.P` — this only works when the compiled system has a subsystem named `:pk`. In SCRAM-02 test, PK is compiled standalone (`@named pk = ...; ssys = mtkcompile(pk)`), so the symbolic is `ssys.P`, not `ssys.pk.P`.

**Why it happens:** When PK is the root system, there is no extra namespace layer.

**How to avoid:** In `scram_callback`, document that the caller must pass the correct symbolic path. For the standalone test (SCRAM-02), pass `p_sym = ssys.P` by accessing it before calling `scram_callback`, or the test builds the system with PK as a named subsystem.

### Pitfall 5: ContinuousCallback fires on upward AND downward crossings by default

**What goes wrong:** `ContinuousCallback(condition, affect!)` with a single affect function fires on both crossings. For SCRAM (fires when P exceeds limit — upward crossing), this is correct. For Flapper (fires when mdot drops below threshold — downward crossing), using a single affect would also fire when mdot recovers.

**Why it happens:** The two-argument `ContinuousCallback(cond, affect_pos!)` fires on upward zero-crossing. The three-argument `ContinuousCallback(cond, affect_pos!, affect_neg!)` allows independent handling.

**How to avoid:**
- `scram_callback`: `ContinuousCallback(condition, affect!)` — fires when P - plimit goes from negative to positive (P rises above limit). Correct.
- `flapper_callback`: `ContinuousCallback(condition, nothing, affect!)` — fires only on downward crossing (mdot drops below threshold). `nothing` for upward means "do nothing when mdot recovers." [VERIFIED: LOF-02 pattern at test/test_loss_of_flow.jl:119]

---

## Code Examples

### Verified LOF-02 Pattern (the template for flapper_callback)

```julia
# Source: test/test_loss_of_flow.jl lines 117-123 [VERIFIED]
i_T_open   = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
i_ine_mdot = ModelingToolkit.variable_index(ssys, ssys.ine.port_in.mdot)
cb = ContinuousCallback(
    (u, t, integrator) -> u[i_ine_mdot] - BYPASS_THRESHOLD,
    nothing,
    (integrator) -> (integrator.u[i_T_open] = integrator.t),
)
```

### Verified solve_transient with CallbackSet

```julia
# Source: test/test_flapper.jl line 149 [VERIFIED]
sol = solve_transient(ssys, op, t_arr; callbacks=CallbackSet(user_cb))
```

### Existing change_state API

```julia
# Source: src/components/point_kinetics.jl lines 400-408 [VERIFIED]
function change_state(ctrl::ReactivityController, t_now, power, dPdt)
    new_state = ctrl.state_machine(ctrl.state, t_now, power, dPdt)
    if new_state != ctrl.state
        ctrl.state = new_state
        ctrl.t_state = Float64(t_now)
        push!(ctrl.log, (new_state, Float64(t_now)))
    end
    return new_state
end
```

### SCRAM usage pattern (target user API)

```julia
# Source: CONTEXT.md D-01 through D-03 [VERIFIED against codebase compatibility]
scram_ir = (state, t_state, t) -> state == :SCRAM ? -0.02 : 0.0

ctrl = ReactivityController(scram_ir;
    initial_state  = :NORMAL,
    state_machine  = SCRAM_at_power(1.5),
    abort_states   = Set([:SCRAM]))

@named pk = PointKinetics(ctrl; rho_val=0.0)
ssys = mtkcompile(pk)

p_sym  = ssys.P      # PK is root system in standalone test
p_idx  = variable_index(ssys, p_sym)
plimit = ctrl.state_machine.power_limit

cb = scram_callback(ssys, ctrl)  # or pass p_sym explicitly for non-:pk namespace

op = Pair{Any,Any}[ssys.rho_c_fn => ctrl, ssys.P => ic.P, ...]
sol = solve_transient(ssys, op, t_arr; tstops=[t_step], callbacks=cb)
```

---

## Python STREAM Reference

[VERIFIED: ~/projects/STREAM/stream/calculations/point_kinetics.py, lines 372-373]

```python
def SCRAM_at_power(power_limit: Watt, power: Watt, **kwargs):
    return power > power_limit
```

The Python `SCRAM_at_power` is a plain function (not a struct). The Julia design uses a `SCRAMCondition` struct instead to allow `scram_callback` to read `power_limit` from `ctrl.state_machine.power_limit` without user duplication. This is a Julia-idiomatic improvement over the Python API.

The Python `ReactivityController` uses `should_continue(t)` for abort detection rather than an external callback. The Julia design uses a `ContinuousCallback` + `terminate!` instead — more aligned with the DifferentialEquations.jl ecosystem.

---

## Files Being Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `src/components/point_kinetics.jl` | Add | `SCRAMCondition` struct, `SCRAM_at_power`, `scram_callback` |
| `src/components/flapper.jl` | Modify | Remove `SymbolicContinuousCallback`, `use_callback`, `threshold`; add `flapper_callback` |
| `src/STREAM.jl` | Modify | Add exports: `SCRAMCondition`, `scram_callback`, `flapper_callback` |
| `test/test_flapper.jl` | Modify | FLAP-05: pass `flapper_callback(ssys; threshold=...)` via `callbacks=` |
| `test/test_loss_of_flow.jl` | Modify | LOF-02: simplify to use `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)` |
| `test/test_point_kinetics.jl` | Add | SCRAM-01, SCRAM-02 testsets |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`@testset`, `@test`, `@test_throws`) |
| Config file | none — Julia standard test runner |
| Quick run command | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. test/runtests.jl` |
| Full suite command | same (runtests.jl includes all test files) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCRAM-01 | `SCRAMCondition` struct construction and callable semantics | unit | include in `test/test_point_kinetics.jl` SCRAM-01 testset | ❌ Wave 0 |
| SCRAM-02 | `scram_callback` terminates standalone PK solver when P exceeds power_limit | integration | include in `test/test_point_kinetics.jl` SCRAM-02 testset | ❌ Wave 0 |
| FLAP-REF | Flapper constructor no longer accepts `use_callback` kwarg | unit | `@test_throws` MethodError in FLAP-05 update or dedicated test | ❌ Wave 0 (existing FLAP-05 modified) |
| FLAP-CB | `flapper_callback` returns `ContinuousCallback` that latches T_open on downward crossing | integration | FLAP-06 update or new FLAP-07 if needed | ❌ Wave 0 (existing FLAP-06 reused) |
| LOF-REF | LOF-02 simplified to use `flapper_callback` API, still passes | regression | existing LOF-02 testset (content updated) | ✅ exists, needs modification |

### Test Assertions for SCRAM-01

```julia
@testset "SCRAM-01: SCRAM_at_power" begin
    # SCRAMCondition construction
    sc = SCRAM_at_power(1.5)
    @test sc isa SCRAMCondition
    @test sc.power_limit == 1.5

    # Callable semantics: P below limit -> no transition
    @test sc(:NORMAL, 0.0, 1.0, 0.0) == :NORMAL

    # Callable semantics: P above limit -> SCRAM
    @test sc(:NORMAL, 0.0, 2.0, 0.0) == :SCRAM

    # Already in SCRAM: stays SCRAM
    @test sc(:SCRAM, 0.5, 2.0, 0.0) == :SCRAM

    # dPdt is ignored by SCRAMCondition (extensibility parameter)
    @test sc(:NORMAL, 0.0, 2.0, -999.0) == :SCRAM
end
```

### Test Assertions for SCRAM-02

```julia
@testset "SCRAM-02: scram_callback" begin
    # Setup: standalone PK with step reactivity driving P above 1.5
    P0     = 1.0
    plimit = 1.5
    t_step = 0.5
    delta_rho = 0.005  # above beta/3 -> fast prompt jump above plimit

    scram_ir = (state, t_state, t) -> state == :SCRAM ? -0.05 : (t >= t_step) * delta_rho
    ctrl = ReactivityController(scram_ir;
        initial_state = :NORMAL,
        state_machine = SCRAM_at_power(plimit),
        abort_states  = Set([:SCRAM]))

    @named pk = PointKinetics(ctrl; rho_val=0.0)
    ssys = mtkcompile(pk)
    cb = scram_callback(ssys, ctrl)

    ic = point_kinetics_steady_state(P0)
    op = Pair{Any,Any}[ssys.rho_c_fn => ctrl, ssys.P => ic.P, ...]
    t_arr = range(0.0, 10.0, length=1000)
    sol = solve_transient(ssys, op, t_arr; tstops=[t_step], callbacks=cb)

    # Solver terminates early (before tspan end due to terminate! default)
    @test sol.t[end] < 10.0

    # SCRAM fired after step insertion
    @test ctrl.state == :SCRAM

    # Log contains SCRAM transition with positive time
    @test any(entry -> entry[1] == :SCRAM, ctrl.log)
    t_scram = ctrl.log[end][2]
    @test t_scram > t_step  # SCRAM fired after step, not before

    # Power at SCRAM time was above plimit
    # (verified indirectly: callback only fires when P - plimit >= 0)
end
```

### Sampling Rate

- **Per task commit:** Run `test/test_point_kinetics.jl` and `test/test_flapper.jl` in isolation
- **Per wave merge:** Full `test/runtests.jl` (all 1380+ tests)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] SCRAM-01 testset in `test/test_point_kinetics.jl` — covers `SCRAMCondition` struct + callable
- [ ] SCRAM-02 testset in `test/test_point_kinetics.jl` — covers `scram_callback` + solver termination
- [ ] FLAP-05 update in `test/test_flapper.jl` — passes `flapper_callback(ssys; threshold=...)` via `callbacks=`
- [ ] LOF-02 update in `test/test_loss_of_flow.jl` — simplify to `flapper_callback` API

---

## Open Questions

1. **Standalone PK namespace in scram_callback**
   - What we know: `scram_callback` uses `ssys.pk.P` per CONTEXT.md D-03. Standalone test (SCRAM-02) has PK as root.
   - What's unclear: Should `scram_callback` accept an explicit `p_sym` parameter, or should SCRAM-02 build a composite system with PK as `:pk` subsystem?
   - Recommendation: Simplest approach is to have SCRAM-02 compile as `@named pk = PointKinetics(ctrl); ssys = mtkcompile(pk)` and then `scram_callback` builds the p_sym as `ssys.P` (not `ssys.pk.P`). Document in docstring that caller must pass the right compiled system where `ssys.pk` is the PK subsystem, OR have `scram_callback` take the P symbolic explicitly. The plan should decide.

2. **FLAP-05 test re-design**
   - What we know: FLAP-05 currently tests "flapper stays closed under positive ref_mdot." It relies on the scalar pump loop WITHOUT an inertia-decay decay. Without `use_callback`, there is no embedded callback, and the test just verifies the Flapper component compiles and T_open stays at 1e30. The flapper_callback needs to be wired but never fires (since mdot stays above threshold).
   - What's unclear: Does FLAP-05 need a `callbacks=flapper_callback(...)` to be meaningful, or is testing "no callback fires" useful as-is?
   - Recommendation: FLAP-05 should pass `callbacks=flapper_callback(ssys; threshold=1e-6)` to `solve_transient` and verify T_open stays at 1e30 (callback never fires). This tests both the callback factory and the "no-fire" path.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 48 is purely Julia source code changes. No external tools, services, or databases required. DifferentialEquations.jl with `ContinuousCallback` and `terminate!` is already loaded as a transitive dependency.

---

## Security Domain

Not applicable — this phase implements numerical solver callbacks and struct patterns with no I/O, network, authentication, or user input.

---

## Sources

### Primary (HIGH confidence)

- `src/components/point_kinetics.jl` — Full file read. ReactivityController struct, change_state, @observed dPdt confirmed.
- `src/components/flapper.jl` — Full file read. SymbolicContinuousCallback, use_callback, threshold confirmed for removal.
- `src/solvers.jl` — Full file read. `callbacks` kwarg at line 99, forwarded as `callback = callbacks`.
- `src/STREAM.jl` — Full file read. Current exports confirmed, missing new exports identified.
- `test/test_loss_of_flow.jl` — Lines 113-125. LOF-02 manual ContinuousCallback pattern — the exact template for `flapper_callback`.
- `test/test_flapper.jl` — Full file. FLAP-05, FLAP-06, SOLV-01 test patterns confirmed.
- `test/test_point_kinetics.jl` — Full file. All existing PK tests confirmed, SCRAM tests absent.
- `.planning/phases/48-scram-solver-integration/48-CONTEXT.md` — All decisions D-01 through D-09 read.
- `.planning/phases/48-scram-solver-integration/48-DISCUSSION-LOG.md` — dPdt correction confirmed.

### Secondary (MEDIUM confidence)

- `~/projects/STREAM/stream/calculations/point_kinetics.py` — Python SCRAM_at_power confirmed as bare function at line 372-373. Confirms Julia struct design is intentional improvement.

### Tertiary (LOW confidence)

- `terminate!(integrator)` behavior — [ASSUMED: standard DifferentialEquations.jl API, not yet called in STREAM.jl codebase but standard in DiffEq ecosystem]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `terminate!(integrator)` from DifferentialEquations stops the ODE solver and sets retcode to Terminated | Pattern 2 / SCRAM-02 test assertions | SCRAM-02 test assertion `sol.t[end] < 10.0` would fail if terminate! behaves differently; low risk as this is standard DiffEq API |
| A2 | `integrator.du[p_idx]` gives the ODE derivative of P at the current solver step | Pattern 2 | dPdt value passed to change_state would be wrong; extensibility concern only (SCRAMCondition ignores dPdt) |

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — all dependencies verified in existing source files
- Architecture: HIGH — exact patterns verified in codebase (LOF-02, SOLV-01)
- Pitfalls: HIGH — dPdt pitfall documented from discussion log, others from direct code inspection

**Research date:** 2026-04-08
**Valid until:** 2026-05-08 (stable MTK/DiffEq APIs, 30-day window)
