# Phase 46: Callable Control Reactivity & ReactivityController — Research

**Researched:** 2026-04-04
**Domain:** ModelingToolkit callable parameters + pure-Julia state-machine struct
**Confidence:** HIGH

## Summary

Phase 46 extends the Phase 45 `PointKinetics` MTK component with a time-varying control reactivity, injected via MTK's callable-parameter pattern (`@parameters (rho_c_fn::FType)(..)`). The pattern is already in production in `src/components/pump.jl` (v0.6), so the core MTK mechanics are proven and the risk is low.

Alongside the MTK extension, Phase 46 introduces a pure-Julia `ReactivityController{S,F}` mutable struct that mirrors Python STREAM's `ReactivityController` API (input_reactivity callable, state_machine callable, state/t_state/log/abort_states fields, `worth(ctrl,t)` and `change_state(ctrl,t,power,dPdt)` methods). Making the struct callable (`(ctrl::ReactivityController)(t) = worth(ctrl, t)`) lets users pass it directly as the MTK callable parameter — the user workflow in D-10 depends on this.

No SCRAM callback wiring, no temperature feedback — those are Phases 49 and 47. Phase 46 only constructs the machinery; state transitions must be driven externally in tests via direct `change_state` calls.

**Primary recommendation:** Replicate the Pump callable-parameter pattern 1:1 for the callable-mode `PointKinetics` constructor. Add the `ReactivityController` struct with parametric types `{S,F}` for zero-overhead dispatch on the user's state type and input_reactivity function. Validate step insertion against the prompt-jump analytical formula (rtol=1e-2) and ramp insertion against a numerical-reference tolerance.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**rho Composition (D-01):** Additive composition: `rho_total(t) = rho_val + rho_c_fn(t)`.
- `rho_val` (scalar MTK parameter) stays as the base/bias reactivity (default 0.0 = critical).
- `rho_c_fn(t)` is the control reactivity, an MTK callable parameter, default `t -> 0.0`.
- The ODE P equation becomes: `Dt(P) ~ (rho_val + rho_c_fn(t) - beta_sum) / Lambda_gen * P + precursor_source`
- Extends cleanly to Phase 47: `rho_val + rho_c_fn(t) + alpha_c*(T_c - T_c0) + alpha_f*(T_f - T_f0)`.

**Constructor Design (D-02):** Two constructors via multiple dispatch:
- `PointKinetics(; name, rho=0.0, ...)` — Phase 45 scalar mode, unchanged. No callable param.
- `PointKinetics(rho_c_fn::Any; name, rho_val=0.0, ...)` — Phase 46 callable mode. Positional callable arg enables dispatch on type. Uses `FType = typeof(rho_c_fn)` and `@parameters (rho_c_fn::FType)(..)` per Pump precedent.

**D-03:** The `observed` block's `reactivity` variable is updated to `rho_val + rho_c_fn(t)` in callable mode (was just `rho_val` in Phase 45).

**InputReactivity Signature (D-04):** State-aware: `(state, t_state, t) -> Float64` (matches Python STREAM protocol).
- `state` is the current controller state (any `Enum` or `Symbol`).
- `t_state` is the time the current state was entered.
- `t` is the current simulation time.
- `ReactivityController.worth(ctrl, t)` calls `ctrl.input_reactivity(ctrl.state, ctrl.t_state, t)`.
- Users who don't need state-dependence write: `(state, t_state, t) -> my_function(t)`.

**ReactivityController Struct (D-05):** Pure Julia mutable struct:
```julia
mutable struct ReactivityController{S, F}
    input_reactivity::F        # (state, t_state, t) -> Float64
    state_machine              # (state, t, power, dPdt) -> state (default: identity)
    state::S                   # current state
    t_state::Float64           # time when current state was entered
    log::Vector{Tuple{S, Float64}}  # state transition history
    abort_states::Set          # states that signal the integrator to stop
end
```

**D-06:** Default constructor: `ReactivityController(input_reactivity=nothing; initial_state=:NORMAL, initial_time=0.0, state_machine=nothing, abort_states=nothing)`. Matches Python STREAM kwarg names.
- `input_reactivity=nothing` → defaults to `(state, t_state, t) -> 0.0`.
- `state_machine=nothing` → defaults to identity (state never changes automatically).
- `abort_states=nothing` → defaults to empty Set.

**D-07:** `worth(ctrl::ReactivityController, t)` — primary output method; calls `ctrl.input_reactivity(ctrl.state, ctrl.t_state, t)`.

**D-08:** `change_state(ctrl::ReactivityController, t, power, dPdt)` — calls `ctrl.state_machine(ctrl.state, t, power, dPdt)` and updates `ctrl.state`, `ctrl.t_state`, appends to `ctrl.log` if state changed.

**D-09:** Make `ReactivityController` callable: `(ctrl::ReactivityController)(t) = worth(ctrl, t)`. Lets users pass `ctrl` directly as the MTK callable parameter.

**MTK Integration Pattern (D-10):** User workflow for callable mode:
```julia
ctrl = ReactivityController((state, t_state, t) -> 0.003 * (t >= 1.0 ? 1.0 : 0.0))
@named pk = PointKinetics(ctrl; rho_val=0.0, ...)  # FType = ReactivityController
ssys = mtkcompile(pk)
op = [ssys.rho_c_fn => ctrl, ssys.P => ic.P, ...]
sol = solve_transient(ssys, op, tspan)
```

**D-11:** When ReactivityController state changes (Phase 49 callback calls `change_state`), subsequent `ctrl(t)` calls automatically see the new state because MTK stores the callable reference, not a value snapshot.

**File Layout (D-12):** `ReactivityController`, `worth`, `change_state` go in `src/components/point_kinetics.jl`. Export from `src/STREAM.jl`.

**D-13:** Tests added to `test/test_point_kinetics.jl`. New `@testset "PK-03: Callable Control Reactivity"` and `@testset "RC-01: ReactivityController"` blocks.

### Claude's Discretion
- Exact type parameter approach for `ReactivityController{S, F}` or simpler `Any`-typed fields
- Whether to expose `worth_history` (Python STREAM has it; defer if not needed for Phase 46 tests)
- Default state type: `:NORMAL` as Symbol or a `OneWayToSCRAM` enum (Symbol is simpler for now)
- Docstring structure (follow existing component patterns)

### Deferred Ideas (OUT OF SCOPE)
- `worth_history(ctrl, t)` — history-aware worth that replays past states (Python STREAM has this; defer to Phase 49)
- SCRAM callback wiring (`SymbolicContinuousCallback` that calls `change_state`) — Phase 49
- `SCRAM_at_power` factory — Phase 49 (RC-03)
- Full `OneWayToSCRAM` enum type — use plain Symbols in Phase 46; typed enum in Phase 49
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PK-03 | Callable control reactivity via `@parameters (rho_c_fn::FType)` pattern (Pump v0.6 precedent); step and ramp insertions validated against analytical solutions | Pump `src/components/pump.jl:56-70` shows the exact pattern; test_pump.jl PUMP-03 shows the op-dict wiring for callable params. Prompt-jump formula `P(0⁺) ≈ β/(β-δρ) · P0` validates step insertion. |
| RC-01 | `ReactivityController` Julia struct — InputReactivity protocol (`worth(ctrl, t)`), StateMachine protocol (`change_state`), state transition log, `abort_states` support for early integrator termination | Python STREAM `point_kinetics.py:83-162` provides the full reference API; translates directly to a parametric Julia mutable struct with `{S,F}` type parameters. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **File layout:** New component code goes in `src/components/point_kinetics.jl` (same file — append after Phase 45 content). Test file `test/test_point_kinetics.jl` mirrors the src file.
- **Exports:** ALL public exports declared in `src/STREAM.jl` only. NEVER add `export` statements inside component files.
- **Argument conventions:** Positional + multiple dispatch when type determines behavior (`PointKinetics(rho_c_fn::Any; ...)` — matches Pump precedent). Keyword-only for many-parameter constructors. `name` is ALWAYS keyword-only (required by `@named`).
- **ASCII variable names:** No Unicode in code — use `rho_val`, `beta_sum`, `Lambda_gen`, not `ρ_val`, `β`, `Λ` (feedback_ascii_variable_names).
- **Docstrings:** Every exported name needs description + `# Arguments` + `# Returns` section.
- **MTK patterns:**
  - `@register_symbolic` for opaque Julia functions used in equations (not needed here — callable params use the `(..)` variadic syntax instead).
  - `mtkcompile(sys)` before every solve.
  - `@observed` for diagnostics never used on RHS of another equation (`reactivity` expression qualifies).
- **Internal helpers prefixed with `_`** and not exported.

## Standard Stack

### Core (already in use, no new dependencies)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | existing | Callable parameter pattern `@parameters (fn::FType)(..)` | Only MTK mechanism for time-varying callable parameters; proven in Pump v0.6 [VERIFIED: src/components/pump.jl] |
| DifferentialEquations.jl | existing | `solve_transient` accepts op-dict with `ssys.rho_c_fn => callable` | [VERIFIED: test/test_pump.jl PUMP-03] |

### Supporting
No new libraries required. `ReactivityController` is pure Julia — uses only `Set`, `Vector`, `Tuple` from Base.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@parameters (rho_c_fn::FType)(..)` | `@register_symbolic` + plain Julia function | `@register_symbolic` creates a module-level binding; cannot rebind per-system. The `(..)` variadic pattern allows per-instance substitution through the op-dict, which is what we need [VERIFIED: test_pump.jl line 136]. |
| Parametric `{S,F}` struct | `Any`-typed fields | Parametric types give zero-overhead dispatch; `F` avoids closure-capture cost at every `worth` call. Field `state_machine` is left untyped (`Any`) because it may be swapped at runtime. |
| Plain Symbols for state | `@enum OneWayToSCRAM` | Symbols are simpler for Phase 46 (`:NORMAL`, `:SCRAM`). Enum typed in Phase 49 when more states are needed. Matches D-06. |

**Installation:** None — existing Project.toml covers all dependencies.

**Version verification:** Not applicable (no new packages).

## Architecture Patterns

### Recommended Project Structure (no changes)
```
src/
├── components/
│   └── point_kinetics.jl     # Phase 45 content + Phase 46 callable constructor + ReactivityController
└── STREAM.jl                 # Add exports: ReactivityController, worth, change_state
test/
└── test_point_kinetics.jl    # Add @testset "PK-03" and @testset "RC-01"
```

### Pattern 1: MTK Callable Parameter (Pump precedent)

**What:** Register a time-varying external function as an MTK parameter that can be evaluated at each timestep.

**When to use:** When the parameter value depends on simulation time and/or runtime state not expressible in symbolic equations.

**Example:**
```julia
# Source: src/components/pump.jl:56-70 [VERIFIED]
function Pump(dP_pump::Any; name)
    FType = typeof(dP_pump)                           # capture concrete type at construction
    pars = @parameters (dP_pump_fn::FType)(..)        # variadic (..), NOT (t)
    # ... equations use dP_pump_fn(t) ...
    port_out.P - port_in.P ~ dP_pump_fn(t)
end

# Caller passes the callable via op-dict:
op = [ssys.pump.dP_pump_fn => dP_fn, ...]             # test_pump.jl:136 [VERIFIED]
```

**Critical syntax notes:**
- Use `(..)` variadic — NOT `(t)`. The `(..)` signals to MTK that this is a callable whose arity is deferred.
- `FType = typeof(x)` captures the CONCRETE type of the callable at construction time. Every unique callable produces a distinct `FType`, so each `PointKinetics(ctrl;...)` call builds a system parametrized by `typeof(ctrl)`.
- Must pass the callable in the op-dict when calling `ODEProblem` / `solve_transient` — MTK does NOT bake a default at compile time.

### Pattern 2: Making a Struct Callable

**What:** Define `(x::MyStruct)(args...)` to make instances behave like functions.

**When to use:** When a struct wraps state + a function-like operation. Enables passing the struct directly as a callable.

**Example:**
```julia
# D-09 pattern:
mutable struct ReactivityController{S, F}
    input_reactivity::F
    state::S
    t_state::Float64
    # ...
end

(ctrl::ReactivityController)(t) = worth(ctrl, t)      # makes ctrl(t) work

# Enables D-10 user workflow:
ctrl = ReactivityController(my_fn)
@named pk = PointKinetics(ctrl; rho_val=0.0)          # FType = ReactivityController{Symbol, typeof(my_fn)}
op = [ssys.pk.rho_c_fn => ctrl, ...]                  # pass ctrl directly, no wrapper
```

### Pattern 3: Parametric Mutable Struct with Default Constructor

**What:** Mutable struct with type parameters + a kwarg constructor providing sensible defaults.

**Example:**
```julia
mutable struct ReactivityController{S, F}
    input_reactivity::F
    state_machine                              # untyped — may be swapped
    state::S
    t_state::Float64
    log::Vector{Tuple{S, Float64}}
    abort_states::Set
end

function ReactivityController(input_reactivity=nothing;
                              initial_state=:NORMAL,
                              initial_time=0.0,
                              state_machine=nothing,
                              abort_states=nothing)
    ir = input_reactivity === nothing ? ((s, ts, t) -> 0.0) : input_reactivity
    sm = state_machine === nothing ? ((s, t, p, dp) -> s) : state_machine
    ab = abort_states === nothing ? Set() : abort_states
    S = typeof(initial_state)
    F = typeof(ir)
    ReactivityController{S,F}(ir, sm, initial_state, Float64(initial_time),
                              Tuple{S,Float64}[(initial_state, Float64(initial_time))], ab)
end
```

### Anti-Patterns to Avoid

- **Using `(t)` instead of `(..)` in `@parameters`:** The arity-specific form breaks MTK symbolic traversal in some versions. Always use `(..)` per Pump precedent.
- **Hand-rolling a closure wrapper `t -> worth(ctrl, t)`:** Makes `FType` opaque and harder to reason about. Use D-09 (callable struct) instead.
- **Unicode identifiers:** `ρ_c_fn` or `β_sum` break CLAUDE.md's ASCII rule. Use `rho_c_fn`, `beta_sum`.
- **Baking `input_reactivity` default as a capture of `just(0.0)`:** Python STREAM uses `curry(just)(0.0)`; Julia just uses a plain anonymous function `(s, ts, t) -> 0.0`.
- **Exporting from component file:** CLAUDE.md forbids this. All exports in `src/STREAM.jl` only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Time-varying MTK parameter | Custom callback that mutates a scalar parameter per-step | `@parameters (fn::FType)(..)` pattern | MTK's built-in pattern integrates with symbolic Jacobian generation; mutation breaks sensitivity analysis. [VERIFIED: Pump v0.6] |
| State transition log | Hand-written logging inside state_machine | `push!(ctrl.log, (s, t))` inside `change_state` | Single responsibility: state_machine is pure; ReactivityController owns history. |
| Abort detection | Ad-hoc integrator interruption | `should_continue(ctrl, t)` returning bool; call sites gate on it | Matches Python STREAM API, keeps policy in one place, Phase 49 will wire to a callback. |

**Key insight:** MTK's callable-parameter pattern is the *only* correct way to inject time-varying external functions into a symbolic ODE system. Any alternative (mutable parameters, callbacks that reassign) breaks either the symbolic Jacobian or the referential transparency MTK relies on.

## Runtime State Inventory

Not applicable — Phase 46 is greenfield additive code (new constructor + new struct), not a rename/refactor. No existing runtime state is changed:
- **Stored data:** None — no databases or datastores involved.
- **Live service config:** None — pure code.
- **OS-registered state:** None.
- **Secrets/env vars:** None.
- **Build artifacts:** None — Julia has no egg-info equivalent; `include` picks up source changes automatically.

## Common Pitfalls

### Pitfall 1: `ssys.rho_c_fn` vs `ssys.pk.rho_c_fn` in op-dict

**What goes wrong:** If tests create a standalone `PointKinetics` (no outer composition), the parameter is `ssys.rho_c_fn`. If composed inside an outer system, it's `ssys.pk.rho_c_fn`. Tests that guess wrong get "parameter not found" errors.

**Why it happens:** MTK parameter names are path-prefixed by `compose`/`@named`.

**How to avoid:** For bare-component tests (D-10 workflow), `mtkcompile(pk)` keeps the top level as `pk` — so the fully qualified path is `ssys.rho_c_fn` (no `pk.` prefix since the compiled system's namespace IS the component). Verify by `println(parameters(ssys))` if debugging.

**Warning signs:** `ArgumentError: Cannot find variable rho_c_fn` or symbolic substitution returning the raw symbol unchanged.

### Pitfall 2: FType must be concrete, not abstract

**What goes wrong:** If you write `FType = Function` or `FType = Any`, MTK cannot generate an efficient dispatch and may error at codegen.

**Why it happens:** `@parameters (fn::FType)(..)` must resolve to a concrete callable signature at macro expansion time.

**How to avoid:** Always `FType = typeof(rho_c_fn)` — `typeof` always returns a concrete type.

**Warning signs:** MTK error about "parameter type not concrete" or codegen errors about unreachable branches.

### Pitfall 3: Step-insertion tests need sharp-but-smooth steps

**What goes wrong:** A hard step `t >= 1.0 ? 0.003 : 0.0` creates a discontinuity that adaptive ODE solvers handle poorly without tstops — the step may be missed entirely, causing test flakiness.

**Why it happens:** Adaptive solvers take large steps; they interpolate *through* a discontinuity rather than stopping at it unless told to.

**How to avoid:** Either (a) pass `tstops=[1.0]` to `solve_transient`, (b) use a `tanh`-smoothed step, or (c) split the test into two solve segments (t=0..1 with rho=0, restart with rho=0.003 at t=1). The prompt-jump formula is evaluated just after the step, so accuracy matters.

**Warning signs:** Test passes sometimes and fails other times depending on solver step size.

### Pitfall 4: Prompt-jump formula validity region

**What goes wrong:** The prompt-jump approximation `P(0⁺)/P0 = β/(β - δρ)` only holds for `|δρ| << β` (sub-prompt-critical). Using `δρ = 0.005` when `β = 0.006502` gives relative errors too large for `rtol=1e-2`.

**Why it happens:** Near prompt-criticality, the approximation breaks down because the prompt-neutron population takes over.

**How to avoid:** Use `δρ <= β/3` (e.g., `δρ = 0.002` with `β ≈ 0.0065`). Test the jump at a time long enough after the step for precursor pool to be quasi-stationary but short compared to `1/min(lambda_k) ≈ 4.3s`. Sampling at `t_step + 0.1s` is typical.

**Warning signs:** Test fails with `rtol=1e-2` but passes at `rtol=0.1` — formula regime violation.

### Pitfall 5: Mutable `log` aliasing

**What goes wrong:** If `abort_states=nothing` is swapped for `abort_states=Set()` via a module-level shared default, mutations leak across controllers.

**Why it happens:** Julia's default-arg shared-state footgun (similar to Python's mutable default arg).

**How to avoid:** Use `=nothing` sentinel and construct a fresh `Set()` / `Vector` inside the body. The D-06 constructor already follows this pattern.

### Pitfall 6: `log` tuple type stability

**What goes wrong:** `Vector{Tuple{S, Float64}}` where `S` is inferred at construction. If the first `push!` has wrong element types, the vector gets abstract-typed silently.

**How to avoid:** Parameterize the log: `log::Vector{Tuple{S, Float64}}` with `S` from the struct parameter. Initialize with `Tuple{S,Float64}[(initial_state, Float64(initial_time))]` — note the `Float64(...)` conversion.

## Code Examples

Verified patterns extracted from the repo:

### Callable Constructor (extend Phase 45)

```julia
# Pattern: src/components/pump.jl:56-70 [VERIFIED]
# Applied to PointKinetics — add this alongside existing scalar constructor:
function PointKinetics(rho_c_fn::Any; name,
                       rho_val = 0.0,
                       Lambda = U235_LAMBDA,
                       beta_k = U235_BETA_K,
                       lambda_k = U235_LAMBDA_K)
    Dt = Differential(t)
    FType = typeof(rho_c_fn)
    pars = @parameters begin
        rho_val = rho_val
        Lambda_gen = Lambda
        beta_1 = beta_k[1]
        # ... beta_2..6, lambda_1..6 as in Phase 45 ...
        (rho_c_fn::FType)(..)
    end
    # @variables block identical to Phase 45
    # equations: replace (rho_val - beta_sum) with (rho_val + rho_c_fn(t) - beta_sum)
    # observed: reactivity ~ rho_val + rho_c_fn(t)
end
```

### Passing the callable in op-dict

```julia
# Pattern: test/test_pump.jl:134-137 [VERIFIED]
ctrl = ReactivityController((s, ts, t) -> 0.002 * (t >= 1.0))
@named pk = PointKinetics(ctrl; rho_val=0.0)
ssys = mtkcompile(pk)
ic = point_kinetics_steady_state(1.0)
op = Pair{Any,Any}[
    ssys.rho_c_fn => ctrl,
    ssys.P => ic.P,
    ssys.C_1 => ic.C_k[1], ssys.C_2 => ic.C_k[2], ssys.C_3 => ic.C_k[3],
    ssys.C_4 => ic.C_k[4], ssys.C_5 => ic.C_k[5], ssys.C_6 => ic.C_k[6],
]
t_arr = range(0.0, 5.0, length=500)
sol = solve_transient(ssys, op, t_arr; tstops=[1.0])
```

### ReactivityController struct + methods (D-05 through D-09)

```julia
mutable struct ReactivityController{S, F}
    input_reactivity::F
    state_machine
    state::S
    t_state::Float64
    log::Vector{Tuple{S, Float64}}
    abort_states::Set
end

function ReactivityController(input_reactivity=nothing;
                              initial_state=:NORMAL,
                              initial_time=0.0,
                              state_machine=nothing,
                              abort_states=nothing)
    ir = input_reactivity === nothing ? ((s, ts, t) -> 0.0) : input_reactivity
    sm = state_machine === nothing ? ((s, t, p, dp) -> s) : state_machine
    ab = abort_states === nothing ? Set() : abort_states
    S_t = typeof(initial_state)
    F_t = typeof(ir)
    t0 = Float64(initial_time)
    ReactivityController{S_t, F_t}(ir, sm, initial_state, t0,
                                    Tuple{S_t, Float64}[(initial_state, t0)], ab)
end

worth(ctrl::ReactivityController, t_now) =
    ctrl.input_reactivity(ctrl.state, ctrl.t_state, t_now)

function change_state(ctrl::ReactivityController, t_now, power, dPdt)
    new_state = ctrl.state_machine(ctrl.state, t_now, power, dPdt)
    if new_state != ctrl.state
        ctrl.state = new_state
        ctrl.t_state = t_now
        push!(ctrl.log, (new_state, t_now))
    end
    return new_state
end

# D-09: make the controller callable
(ctrl::ReactivityController)(t_now) = worth(ctrl, t_now)
```

### Prompt-jump analytical validation (PK-03 test skeleton)

```julia
# Step reactivity insertion at t=1s, jump sampled at t=1.1s
@testset "PK-03: step insertion prompt-jump" begin
    delta_rho = 0.002                  # << beta=0.006502 (sub-prompt-critical)
    t_step = 1.0
    rho_c_fn = (s, ts, t) -> (t >= t_step) * delta_rho
    ctrl = ReactivityController(rho_c_fn)

    @named pk = PointKinetics(ctrl; rho_val=0.0)
    ssys = mtkcompile(pk)
    ic = point_kinetics_steady_state(1.0)
    op = Pair{Any,Any}[ssys.rho_c_fn => ctrl, ssys.P => ic.P,
                       ssys.C_1 => ic.C_k[1], ssys.C_2 => ic.C_k[2],
                       ssys.C_3 => ic.C_k[3], ssys.C_4 => ic.C_k[4],
                       ssys.C_5 => ic.C_k[5], ssys.C_6 => ic.C_k[6]]
    t_arr = range(0.0, 1.1, length=500)
    sol = solve_transient(ssys, op, t_arr; tstops=[t_step])

    beta_total = sum(U235_BETA_K)
    P_jump_expected = beta_total / (beta_total - delta_rho) * ic.P
    @test isapprox(sol[ssys.P, end], P_jump_expected; rtol=1e-2)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@register_symbolic` wrapping a function | `@parameters (fn::FType)(..)` callable parameters | Pump v0.6 refactor (Phase 22) | Enables per-instance callable substitution via op-dict, no module-level binding [VERIFIED: src/components/pump.jl] |
| Scalar-only `rho` parameter | Dual-mode constructor: `rho` scalar OR `rho_c_fn` callable | Phase 46 (this) | User chooses scalar or time-varying per call site via multiple dispatch |

**Deprecated/outdated:** None — Phase 45 scalar constructor stays unchanged.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` stdlib (built-in) |
| Config file | `test/runtests.jl` (orchestrator with `@testset` per include) |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 \| head -80` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PK-03 | Callable mode constructor compiles; dispatch selects callable over scalar | unit | `julia --project=. -e 'include("test/runtests.jl")' -- PointKinetics` | ✅ (add @testset PK-03 to existing file) |
| PK-03 | Step insertion: `P(t_step⁺)/P0 ≈ β/(β-δρ)` within rtol=1e-2 | integration (analytical) | same | ✅ |
| PK-03 | Ramp insertion: linear ρ(t) from 0 to δρ_max; monitored P(t) trajectory matches numerical reference (looser rtol, e.g. 5e-2, OR compare to Python STREAM reference values) | integration | same | ✅ |
| RC-01 | `ReactivityController()` default constructor: `worth(ctrl, t) == 0.0` for all t | unit | same | ✅ |
| RC-01 | `ReactivityController(fn)` stores callable; `worth(ctrl, t)` returns `fn(:NORMAL, 0.0, t)` | unit | same | ✅ |
| RC-01 | `change_state` updates state, t_state, appends to log when state changes | unit | same | ✅ |
| RC-01 | `change_state` no-op (no log append) when state_machine returns same state | unit | same | ✅ |
| RC-01 | `abort_states` field stores user-provided set correctly | unit | same | ✅ |
| RC-01 | `(ctrl::ReactivityController)(t)` callable form returns same as `worth(ctrl, t)` | unit | same | ✅ |
| RC-01 | End-to-end: construct ctrl with state machine that flips at t=1s (via manual `change_state` call); verify worth returns different values before/after | unit | same | ✅ |

### Sampling Rate
- **Per task commit:** `julia --project=. -e 'include("test/test_point_kinetics.jl")'`
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. `test/test_point_kinetics.jl` exists from Phase 45; add `@testset "PK-03: ..."` and `@testset "RC-01: ..."` blocks. No new test framework, no new fixtures, no new helpers needed.

## Security Domain

Not applicable for this phase. Phase 46 is pure in-process Julia code — no authentication, sessions, access control, external input validation, cryptography, or network I/O. No ASVS categories apply. Confirmed by reviewing phase scope: extending an MTK component and adding a Julia struct with in-memory state.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Prompt-jump formula `β/(β-δρ)` valid for `|δρ| <= β/3` at rtol=1e-2 | Common Pitfalls, Code Examples | Test may fail; relax rtol or reduce δρ further. Mitigated by comparing against numerical reference from a trusted reactor-physics reference at 2-3 points. [ASSUMED] |
| A2 | `ssys.rho_c_fn` (no `pk.` prefix) is the correct op-dict path when `mtkcompile(pk)` is called on the bare component | Pitfalls, Code Examples | Tests may need `ssys.pk.rho_c_fn` instead — easy to fix at test time by printing `parameters(ssys)`. [ASSUMED] |
| A3 | Ramp-insertion analytical validation — no closed-form exists for linear ρ(t), so validation must use (a) small-δρ linearization, (b) Python STREAM numerical reference, or (c) energy-conservation sanity. | Test Map | Planner must choose a validation strategy; step test is unambiguous, ramp test may need Python STREAM cross-check. [ASSUMED] |
| A4 | Julia mutable struct with `Set` (untyped) and `Vector{Tuple{S,Float64}}` (parametric) is type-stable enough for tests; performance is not a concern in Phase 46. | Patterns | If hot-path perf matters in later phases, may need `Set{S}` typed. Not a blocker for Phase 46. [ASSUMED] |

## Open Questions

1. **Should `worth_history` be included in Phase 46?**
   - What we know: D-07 only requires `worth`; CONTEXT.md Claude's Discretion says "defer if not needed for Phase 46 tests"; Deferred Ideas explicitly says "defer to Phase 49".
   - What's unclear: Whether any PK-03 or RC-01 test needs it.
   - Recommendation: **Defer.** Add in Phase 49 when SCRAM post-analysis needs history replay. Tests in Phase 46 exercise `worth` (current state only) + manual `change_state` calls.

2. **Ramp insertion test — what analytical reference?**
   - What we know: PK-03 says "ramp insertions validated against analytical solutions".
   - What's unclear: No closed-form solution exists for `ρ(t) = a·t` in the full 7-equation point-kinetics system.
   - Recommendation: Use (a) small-ramp linearization OR (b) comparison against Python STREAM at 3 time points (using the same U235 constants). Planner should decide at plan-writing time and document the chosen reference values.

3. **`:NORMAL` Symbol vs `OneWayToSCRAM` enum as default `initial_state`?**
   - What we know: D-06 says `initial_state=:NORMAL` (Symbol). Deferred Ideas says "typed enum in Phase 49".
   - What's unclear: None — use Symbol per D-06.
   - Recommendation: `initial_state=:NORMAL`. Phase 49 introduces the enum.

## Sources

### Primary (HIGH confidence)
- `/home/itay/projects/Julia-STREAM/src/components/pump.jl` — Callable parameter MTK pattern (`FType = typeof(...)`, `@parameters (fn::FType)(..)`)
- `/home/itay/projects/Julia-STREAM/test/test_pump.jl` (lines 90-172) — Callable parameter op-dict wiring, analytical validation pattern
- `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a4bf8b18/src/components/point_kinetics.jl` — Phase 45 PointKinetics implementation being extended
- `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a4bf8b18/test/test_point_kinetics.jl` — Phase 45 test file (append target)
- `/home/itay/projects/STREAM/stream/calculations/point_kinetics.py` (lines 31-162) — Python STREAM `InputReactivity` protocol, `ReactivityController` API reference
- `/home/itay/projects/Julia-STREAM/CLAUDE.md` — Argument conventions, file layout, MTK patterns, export rules

### Secondary (MEDIUM confidence)
- `.planning/phases/46-callable-control-reactivity-reactivity-controller/46-CONTEXT.md` — All D-01 through D-13 decisions

### Tertiary (LOW confidence)
None — all findings sourced from local repo or official reference implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — pattern already in production (Pump v0.6), verified in code and tests
- Architecture: HIGH — struct design is direct translation of Python STREAM reference; callable-struct idiom is standard Julia
- Pitfalls: HIGH for #1, #2, #5, #6 (Julia/MTK fundamentals); MEDIUM for #3, #4 (prompt-jump numerics — validated via assumption, needs empirical test)

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (30 days — stable, no fast-moving dependencies)
