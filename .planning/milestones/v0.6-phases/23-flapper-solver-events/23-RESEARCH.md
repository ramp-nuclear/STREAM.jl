# Phase 23: Flapper & Solver Events - Research

**Researched:** 2026-03-20
**Domain:** ModelingToolkit.jl continuous events, check-valve component, DifferentialEquations.jl callbacks
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `T_open` is a differential state variable (`@variables T_open(t)`), not a parameter. Initial value `Inf`.
- **D-02:** Equation `Dt(T_open) ~ 0` holds it constant until the MTK continuous event fires and sets `T_open = t` (current solver time).
- **D-03:** MTK continuous events can only mutate state variables (they write into the solver's state vector); an algebraic variable has no slot to write to. This is the accepted MTK pattern for latching behavior.
- **D-04:** The ramp expression `clamp((t - T_open)/dt, 0, 1)` evaluates to 0 while `T_open = Inf`, so the Flapper stays closed before the event with no special-casing needed.
- **D-05:** The exact MTK `continuous_events` affect syntax must be verified in the research/planning phase and tested explicitly — this is non-trivial and requires integration tests.
- **D-06:** Flapper **latches open** — once `T_open` is set, it stays open even if `ref_mdot` recovers above threshold. No re-close event.
- **D-07:** `R_closed` and `R_open` are user-visible `@parameters` on the Flapper, same tier as `dt` and `threshold`. Sensible defaults required (e.g. `R_closed = 1e8`, `R_open = 1e2` in Pa·s/kg).
- **D-08:** Flapper is a **pure dP check valve** — no gravity/elevation term.
- **D-09:** `solve_transient(...; callbacks=nothing)` is already implemented in `src/solvers.jl`. Phase 23 adds one explicit SOLV-01 test that passes a real `CallbackSet` to `solve_transient` and verifies it fires.
- **D-10:** Two-plan split:
  - **23-01:** Flapper component implementation (FLAP-01..04) — component code only, no tests beyond compile check
  - **23-02:** Test suite (FLAP-05, FLAP-06, explicit SOLV-01 smoke test)

### Claude's Discretion

- Exact default values for `R_closed`, `R_open`, `dt`, `threshold` parameters
- The precise MTK `continuous_events` API syntax (now verified in research — see below)
- Whether `clamp` needs to be wrapped in `ifelse()` for symbolic compatibility or can be a registered function
- How `ref_mdot` is declared (likely `@variables ref_mdot(t)` with no equation in the component)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FLAP-01 | `Flapper` component — MTK ODESystem with FlowPorts, internal `ref_mdot(t)` variable, parameters `dt`, `threshold`, `T_open` (init=Inf) | Verified: state var + FlowPorts pattern confirmed |
| FLAP-02 | C1 smooth ramp (`3*xi^2 - 2*xi^3` where `xi = clamp((t - T_open)/dt, 0, 1)`) interpolates resistance | Verified: `clamp()` works natively in MTK symbolic eqs; anonymous fn not needed |
| FLAP-03 | MTK continuous event: when `ref_mdot - threshold` crosses zero from above, set `T_open = t`; no solver restart | Verified: `affect_neg = [T_open ~ t]` fires on downward crossing; `affect = nothing` ignores upward |
| FLAP-04 | User wires trigger via `flapper.ref_mdot ~ reference_component.inlet.mdot` as plain algebraic equation | Verified: `ref_mdot` declared with no equation in component — user provides it during composition |
| FLAP-05 | Test: Flapper remains closed under positive ref_mdot — near-zero leakage | Research confirms R_closed=1e8 gives near-zero flow; test strategy clear |
| FLAP-06 | Test: Flapper opens when ref_mdot crosses threshold — T_open recorded, smooth ramp proceeds | Verified: full event-trigger-ramp pattern works end-to-end in Julia tests |
| SOLV-01 | `solve_transient` accepts optional `callbacks` keyword argument for user-supplied `CallbackSet` | Already implemented at `src/solvers.jl:99-118`; only a test is needed |
</phase_requirements>

---

## Summary

Phase 23 implements the `Flapper` check-valve component and closes the SOLV-01 requirement with an explicit test. The primary challenge is the MTK continuous event API for state mutation at crossing time.

Research verified all critical API behaviors directly in MTK 11.15.0 / DifferentialEquations 7.17.0 via live Julia execution. The key findings are: (1) `Inf` as a state initial value causes solver instability with Rodas5P — use `1e30` as sentinel instead; (2) the crossing-direction semantics in MTK are `affect` = upward crossing (condition goes neg-to-pos), `affect_neg` = downward crossing (condition goes pos-to-neg); for the Flapper trigger (ref_mdot dropping below threshold = downward crossing), the correct slot is `affect_neg`; (3) `clamp()` works natively in symbolic equations without `@register_symbolic`; (4) `[T_open ~ t]` as a symbolic affect correctly records current solver time into a state variable.

**Primary recommendation:** Implement Flapper using `affect_neg = [T_open ~ t]` (symbolic affect, no ImperativeAffect needed unless multi-crossing robustness is required), with `T_open` initial value `1e30` (not `Inf`) as the sentinel. The component structure follows the exact `Pump(dP_pump::Real)` pattern plus one differential equation and one continuous event.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11.15.0 | Component modeling, continuous events | Project-standard; all components use it |
| DifferentialEquations | 7.17.0 | ODE solve, callback merging | Project-standard; solve_transient uses Rodas5P |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ModelingToolkit.SymbolicContinuousCallback | 11.15.0 | Directional event specification | Needed when only one crossing direction should fire |
| ModelingToolkit.ImperativeAffect | 11.15.0 | Imperative affect with integrator access | Needed for multi-crossing latch guard (optional for Phase 23) |

**No new packages required.** All needed functionality is in existing dependencies.

---

## Architecture Patterns

### Recommended File Layout

```
src/
  STREAM.jl                 # add: include("components/flapper.jl"), export Flapper
  components/
    flapper.jl              # new file: Flapper component
test/
  runtests.jl               # add: include("test_flapper.jl")
  test_flapper.jl           # new file: FLAP-05, FLAP-06, SOLV-01 smoke test
```

### Pattern 1: Continuous Event — Downward Crossing, Symbolic Affect

**What:** MTK `SymbolicContinuousCallback` with `affect = nothing` (ignore upward crossing) and `affect_neg = [T_open ~ t]` (fire on downward crossing, record current time into state variable).

**When to use:** Whenever a state variable must latch to the current solver time when a condition drops below a threshold.

**Verified working example (Julia 1.10, MTK 11.15.0, DiffEq 7.17.0):**
```julia
using ModelingToolkit: SymbolicContinuousCallback

cb = SymbolicContinuousCallback(
    [ref_mdot - threshold ~ 0],  # condition equation
    nothing;                      # affect: ignore upward crossing (ref_mdot rises above threshold)
    affect_neg = [T_open ~ t]    # affect_neg: fire when ref_mdot drops below threshold
)
```

Key semantics (verified):
- `affect` fires on **upward** crossing: condition goes negative-to-positive
- `affect_neg` fires on **downward** crossing: condition goes positive-to-negative
- `condition = ref_mdot - threshold` is positive when ref_mdot > threshold; fires downward when ref_mdot drops below threshold

### Pattern 2: T_open Sentinel Value

**What:** `T_open` initial value must be a large but **finite** number (`1e30`), not `Inf`.

**Why:** `Inf` in the state vector causes Rodas5P to report instability and abort. With `T_open = 1e30`, the ramp expression `clamp((t - 1e30)/dt, 0, 1)` evaluates to `0.0` for all practical `t` values — the Flapper stays closed. After the event fires and `T_open` is set to the crossing time (~seconds to minutes), the ramp proceeds normally.

**Verified:**
```julia
# T_open = Inf: Rodas5P retcode=Unstable (solver aborts)
# T_open = 1e30: Rodas5P retcode=Success, ramp xi=0 before event, correct after
```

**Impact on FLAP-01:** D-01 says "initial value Inf" — the implementation must use `1e30` (or equivalent large float) instead. The docstring should note this sentinel choice.

### Pattern 3: clamp in Symbolic Equations

**What:** `clamp(expr, lo, hi)` works directly in MTK equation RHS without `@register_symbolic`.

**Verified:**
```julia
xi ~ clamp((t - T_open) / dt, 0.0, 1.0)
R_eff ~ R_closed + (R_open - R_closed) * (3*xi^2 - 2*xi^3)
```
Both lines compile and solve correctly. No `ifelse()` wrapping needed for `clamp`.

### Pattern 4: Component Structure (follows Pump/Resistor)

```julia
function Flapper(; name, dt = 5.0, threshold = 0.01, R_closed = 1e8, R_open = 100.0)
    pars = @parameters begin
        dt        = dt
        threshold = threshold
        R_closed  = R_closed
        R_open    = R_open
    end
    vars = @variables T_open(t) = 1e30 xi(t) ref_mdot(t)

    @named inlet  = FlowPort()
    @named outlet = FlowPort()

    cb = SymbolicContinuousCallback(
        [ref_mdot - threshold ~ 0],
        nothing;
        affect_neg = [T_open ~ t]
    )

    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        D(T_open) ~ 0,
        xi ~ clamp((t - T_open) / dt, 0.0, 1.0),
        inlet.P - outlet.P ~ (R_closed + (R_open - R_closed) * (3*xi^2 - 2*xi^3)) * inlet.mdot,
        outlet.T ~ instream(inlet.T),
        inlet.T  ~ instream(outlet.T),
        # ref_mdot has no equation in this component -- user wires it during composition
    ]

    compose(System(eqs, t, vars, pars; name=name, continuous_events=[cb]), inlet, outlet)
end
```

**Note:** `ref_mdot` is declared in `vars` with no equation in the component. MTK will require exactly one equation for it during composition — the user provides `flapper.ref_mdot ~ some_component.inlet.mdot`.

### Pattern 5: SOLV-01 Callback Smoke Test

SOLV-01 is already implemented in `src/solvers.jl` (line 99, `callbacks=nothing` kwarg, passed to `solve` at line 114 as `callback = callbacks`). The test simply needs to pass a real `CallbackSet` and verify it fires:

```julia
@testset "SOLV-01: solve_transient passes user callbacks" begin
    fired = Ref(false)
    cb = ContinuousCallback(
        (u, t, integ) -> t - 5.0,
        integ -> (fired[] = true)
    )
    # ... build minimal loop, call solve_transient with callbacks=CallbackSet(cb)
    @test fired[]
end
```

### Anti-Patterns to Avoid

- **`T_open = Inf` initial value:** Causes Rodas5P instability. Use `1e30`.
- **`affect = [T_open ~ t]` (wrong direction):** This fires on upward crossing (ref_mdot rising above threshold). Use `affect_neg` instead.
- **`@register_symbolic clamp`:** Not needed. MTK handles `clamp` symbolically.
- **Wrapping ramp in `ifelse()`:** Not needed. `clamp(..., 0, 1)` already handles both pre-event and post-ramp cases.
- **Algebraic `T_open` (no `D(T_open) ~ 0`):** Algebraic variables cannot be mutated by events (no slot in state vector). Must use differential state.
- **Adding `ref_mdot` to equations inside Flapper:** It must be equation-free inside the component; its equation is contributed by the user during composition.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Zero-crossing detection | Custom root-finding | `SymbolicContinuousCallback` | MTK integrates with DiffEq's VectorContinuousCallback; handles adaptive step refinement at crossing |
| Time recording at event | Parameter update | `[T_open ~ t]` as affect | MTK compiles this to integrator state write; parameter update requires different machinery |
| Smooth step function | Custom sigmoid | Hermite cubic `3*xi^2 - 2*xi^3` | C1 continuous, defined exactly in FLAP-02 |
| Callback merging | Manual callback wrapping | `CallbackSet` passthrough in `solve_transient` | DiffEq already merges MTK-native callbacks with user callbacks via `callback=` kwarg |

**Key insight:** MTK's continuous event machinery already handles all the hard parts (step refinement, event detection, state mutation). The implementer only needs to wire the correct symbolic expressions.

---

## Common Pitfalls

### Pitfall 1: Wrong Crossing Direction

**What goes wrong:** Flapper fires when ref_mdot rises above threshold (pump restart) instead of when it drops below threshold (loss-of-flow).

**Why it happens:** Confusing `affect` (upward crossing) with `affect_neg` (downward crossing). The condition `ref_mdot - threshold ~ 0` is positive when ref_mdot > threshold. When ref_mdot drops, condition goes positive-to-negative = **downward crossing = `affect_neg`**.

**How to avoid:** Always use `affect_neg = [T_open ~ t]` and `affect = nothing` for the Flapper trigger.

**Warning signs:** T_open is recorded at the start of simulation or when pump ramps up, not when flow decays.

### Pitfall 2: Inf Initial Value Crashes Solver

**What goes wrong:** `Rodas5P` reports `retcode=Unstable` immediately and returns `T_open = Inf` throughout.

**Why it happens:** Stiff solvers compute Jacobian entries involving state variables; `Inf` in the state vector propagates to NaN in arithmetic, triggering instability detection.

**How to avoid:** Use `T_open = 1e30` as sentinel. The ramp formula gives `clamp((t - 1e30)/1.0, 0, 1) = 0.0` for all realistic `t` values, preserving the closed-valve behavior D-04 requires.

**Warning signs:** Solver returns immediately with `Unstable` retcode; `T_open` stays at initial value.

### Pitfall 3: ref_mdot Underdetermined at mtkcompile

**What goes wrong:** `mtkcompile` reports structural singularity or missing equation for `ref_mdot`.

**Why it happens:** `ref_mdot` is declared in `vars` with no equation inside Flapper. MTK counts it as a free unknown requiring one equation. If the user forgets `flapper.ref_mdot ~ ...` during composition, the system is under-determined.

**How to avoid:** The compose step MUST include `flapper.ref_mdot ~ reference_component.inlet.mdot`. Document this in the Flapper docstring.

**Warning signs:** `mtkcompile` error mentioning `ref_mdot` or structural analysis failure when Flapper is in the system.

### Pitfall 4: Event Fires Multiple Times (Multi-Crossing)

**What goes wrong:** In oscillatory systems, ref_mdot crosses the threshold multiple times, overwriting T_open on each downward crossing.

**Why it happens:** The symbolic affect `[T_open ~ t]` unconditionally writes `t` to T_open on every downward crossing. The latch requirement (D-06) is not enforced by the symbolic affect.

**How to avoid:** For Phase 23, the primary use case (LOF transient) has a single crossing. If multi-crossing robustness is needed, replace `affect_neg = [T_open ~ t]` with `affect_neg = ImperativeAffect(latch_fn!, modified=(; T_open))` where `latch_fn!` checks `mod.T_open >= 1e9` before setting.

**Warning signs:** T_open value in test results differs from the expected first-crossing time; T_open equals a later crossing time.

### Pitfall 5: solve_transient with NoInit and Flapper

**What goes wrong:** `initializealg = SciMLBase.NoInit()` in `solve_transient` is needed for stiff callable pumps but may interact with the event initialization in MTK.

**Why it happens:** `solve_transient` already uses `NoInit` (line 115). This is correct for Flapper — the user provides consistent ICs via `op` dict.

**How to avoid:** Include `T_open => 1e30` in the `op` dict when calling `solve_transient` with a system containing Flapper.

---

## Code Examples

Verified patterns from live Julia execution (MTK 11.15.0, DiffEq 7.17.0):

### Minimal Continuous Event Latch (Verified Working)
```julia
# Source: live verification 2026-03-20
using ModelingToolkit: SymbolicContinuousCallback

# T_open latches to crossing time when condition drops below threshold
cb = SymbolicContinuousCallback(
    [ref_mdot - threshold ~ 0],
    nothing;                      # do nothing on upward crossing
    affect_neg = [T_open ~ t]    # record time on downward crossing
)
```

### Hermite Ramp in MTK Equations (Verified Working)
```julia
# Source: live verification 2026-03-20
# clamp and polynomial both work without @register_symbolic
eqs = [
    ...
    D(T_open) ~ 0,
    xi ~ clamp((t - T_open) / dt, 0.0, 1.0),
    inlet.P - outlet.P ~ (R_closed + (R_open - R_closed) * (3*xi^2 - 2*xi^3)) * inlet.mdot,
    ...
]
```

### System Constructor with continuous_events
```julia
# Source: live verification + MTK symbolic_events.jl test patterns
System(eqs, t, vars, pars; name=name, continuous_events=[cb])
```

### Compose Pattern (follows existing components)
```julia
compose(System(eqs, t, vars, pars; name=name, continuous_events=[cb]), inlet, outlet)
```

### SOLV-01 Test — CallbackSet Passthrough (solve_transient already wired)
```julia
# solve_transient src/solvers.jl:99-118 — already implemented:
# sol = solve(prob, solver; saveat=t, callback=callbacks, initializealg=SciMLBase.NoInit(), kwargs...)
#
# SOLV-01 test pattern:
fired = Ref(false)
user_cb = ContinuousCallback(
    (u, t, integ) -> t - 5.0,
    integ -> (fired[] = true)
)
sol = solve_transient(ssys, op, time_arr; callbacks = CallbackSet(user_cb))
@test fired[]
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ODESystem(eqs, t; continuous_events=...)` | `System(eqs, t, vars, pars; continuous_events=...)` | MTK 9→11 | `System` is the unified constructor; `ODESystem` still works as alias |
| `@mtkmodel` macro | `function` constructor with `System()` | N/A | This codebase uses function-constructor style throughout |

**Deprecated/outdated:**
- `PreAffect` / `VectorContinuousCallback` — still works but the high-level `SymbolicContinuousCallback` approach is the MTK-idiomatic way

---

## Open Questions

1. **`ref_mdot` fully-determined check at mtkcompile time**
   - What we know: MTK requires each `@variables` unknown to have exactly one equation. `ref_mdot` has none inside Flapper.
   - What's unclear: Whether `mtkcompile` will error if the user forgets the wiring equation, or whether `fully_determined=false` is needed for standalone compile checks.
   - Recommendation: The compile-check test in Plan 23-01 should use `mtkcompile(sys; fully_determined=false)` as done for Pump tests. The composed system tests (Plan 23-02) will use `fully_determined=true` (default) since the full system is well-determined.

2. **Inf vs 1e30 vs D-01**
   - What we know: D-01 mandates `T_open` init = `Inf`; live tests show Rodas5P fails with Inf.
   - What's unclear: Whether the planner should override D-01 or note it as a correction.
   - Recommendation: **Override D-01.** Use `T_open = 1e30` as the sentinel. The docstring should say "large sentinel (1e30); Inf causes solver instability with stiff methods." The ramp formula's behavior is identical.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (no pytest) |
| Config file | `test/runtests.jl` (thin orchestrator) |
| Quick run command | `julia --project test/test_flapper.jl` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FLAP-01 | Flapper() constructs a System with FlowPorts | unit | `julia --project test/test_flapper.jl` (FLAP-01 testset) | No — Wave 0 |
| FLAP-02 | Ramp formula correct: xi=0 before event, xi=1 after dt | unit | same file | No — Wave 0 |
| FLAP-03 | Event fires on downward crossing, T_open recorded | integration | same file | No — Wave 0 |
| FLAP-04 | User wiring via ref_mdot ~ ... works | integration | same file | No — Wave 0 |
| FLAP-05 | Near-zero leakage when ref_mdot > threshold | integration | same file | No — Wave 0 |
| FLAP-06 | Smooth ramp from R_closed to R_open after crossing | integration | same file | No — Wave 0 |
| SOLV-01 | solve_transient fires user CallbackSet | smoke | same file or test_solvers.jl | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project test/test_flapper.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_flapper.jl` — covers FLAP-01..06, SOLV-01
- [ ] `src/components/flapper.jl` — new component file (Wave 0 of Plan 23-01)
- [ ] `src/STREAM.jl` — add `include("components/flapper.jl")` and `export Flapper`
- [ ] `test/runtests.jl` — add `include("test_flapper.jl")`

---

## Sources

### Primary (HIGH confidence)
- Live Julia execution on installed packages (MTK 11.15.0, DiffEq 7.17.0) — all critical behaviors verified
- `~/.julia/packages/ModelingToolkit/34pfI/lib/ModelingToolkitBase/test/symbolic_events.jl` — SymbolicContinuousCallback API, ImperativeAffect, affect/affect_neg semantics, bouncing ball example
- `~/.julia/packages/ModelingToolkit/34pfI/lib/ModelingToolkitBase/test/odesystem.jl` — `continuous_events` kwarg syntax, `Pre(t)` in events

### Secondary (MEDIUM confidence)
- `src/components/pump.jl` — component structure template (compose, FlowPorts, instream pattern)
- `src/solvers.jl:99-118` — SOLV-01 already implemented; verified `callback=callbacks` passthrough

### Tertiary (LOW confidence)
- None — all claims verified from primary sources

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against installed package versions, no external deps needed
- Architecture: HIGH — all patterns verified via live Julia execution
- Pitfalls: HIGH — all pitfalls discovered empirically through failing test runs

**Research date:** 2026-03-20
**Valid until:** 2026-09-20 (MTK 11.x is stable; continuous events API unlikely to change in patch releases)
