# Phase 48: SCRAM + Callback Factory Pattern — Context

**Gathered:** 2026-04-08 (updated — unified callback design)
**Status:** Ready for planning

<domain>
## Phase Boundary

Two deliverables in one cohesive phase:

**1. SCRAM support** — `SCRAM_at_power` condition struct and `scram_callback(ssys, ctrl)`
factory returning an external `ContinuousCallback`. Users wire SCRAM in one call and pass
it to `solve_transient`.

**2. Flapper callback refactor** — Remove `SymbolicContinuousCallback` from inside the
`Flapper` component. Replace with `flapper_callback(ssys; threshold)` external factory
following the same pattern as `scram_callback`.

These are one phase because both are about establishing a **single callback factory
pattern** for event-driven components in STREAM.jl. The pattern: every component whose
behavior changes based on a threshold event exposes a `_callback(ssys, ...)` factory
function that returns an external `ContinuousCallback`, passed by the user to
`solve_transient(...; callbacks=cb)`.

**In scope:** `SCRAM_at_power`, `scram_callback`, `flapper_callback`, Flapper component
simplification, unit tests, integration test on standalone PK (no full loop — Phase 49).

**Out of scope:** full loop coupling, `build_loop_pk`, Python STREAM cross-validation.

</domain>

<decisions>
## Implementation Decisions

### The unified callback factory pattern (D-01)

All event-driven components in STREAM.jl follow one pattern:

1. The component itself is a **pure equation system** — no callbacks inside it.
2. A `_callback(ssys, ...)` factory function (public, exported) returns an external
   `DifferentialEquations.ContinuousCallback` (zero-crossing detection).
3. The user passes it to `solve_transient` via `callbacks=`.

```julia
# Same mental model for every event-driven component:
cb_flapper = flapper_callback(ssys; threshold=0.01)
cb_scram   = scram_callback(ssys, ctrl)
sol = solve_transient(ssys, op, t; callbacks=CallbackSet(cb_flapper, cb_scram))
```

**Why `ContinuousCallback` everywhere (not `DiscreteCallback`):**
- `ContinuousCallback` detects zero-crossings via rootfinding — gives the exact event time
  by interpolation, not just "at the next accepted step."
- Every existing external callback in the codebase already uses `ContinuousCallback`
  (LOF-02 bypass test, SOLV-01 test).
- `DiscreteCallback` would be the only one of its type — introducing it for SCRAM adds a
  second mental model with no benefit.

**Why external (not internal to component):**
- `SymbolicContinuousCallback` inside a component fails with `UnsolvableCallbackError` in
  parallel topologies with inertia terms — already observed in Flapper + bypass topology.
- External `ContinuousCallback` always works regardless of topology.
- Explicit wiring is better than silent magic: users see what events are active at solve time.

### SCRAM_at_power — struct, not bare function (D-02)

`SCRAM_at_power(power_limit)` returns a `SCRAMCondition` struct:

```julia
struct SCRAMCondition
    power_limit::Float64
end
SCRAM_at_power(power_limit) = SCRAMCondition(Float64(power_limit))
# Callable as state_machine: (state, t, P, dPdt) -> new_state
(s::SCRAMCondition)(state, t, P, dPdt) = P > s.power_limit ? :SCRAM : state
```

Making it a struct (not a bare closure) lets `scram_callback` read `power_limit` directly
from `ctrl.state_machine.power_limit` — single source of truth. User writes `1.5` once:

```julia
ctrl = ReactivityController(scram_ir;
    initial_state  = :NORMAL,
    state_machine  = SCRAM_at_power(1.5),   # power_limit stored here
    abort_states   = Set([:SCRAM]))

cb = scram_callback(ssys, ctrl)   # reads power_limit from ctrl.state_machine
```

`SCRAMCondition` lives in `src/components/point_kinetics.jl`.

### scram_callback — ContinuousCallback with terminate! (D-03)

`scram_callback(p_sym, ctrl)` returns a `ContinuousCallback`:

```julia
function scram_callback(p_sym::Num, ctrl; terminate=true)
    plimit = ctrl.state_machine.power_limit        # from SCRAMCondition

    condition = (u, t, integrator) -> integrator[p_sym] - plimit

    affect! = function(integrator)
        P     = integrator[p_sym]
        p_idx = variable_index(integrator, p_sym)  # lazy — integrator implements SymbolicIndexingInterface
        dP    = integrator.du[p_idx]
        change_state(ctrl, integrator.t, P, dP)    # transitions ctrl.state → :SCRAM
        terminate && terminate!(integrator)         # stop solver early (optional)
    end

    ContinuousCallback(condition, affect!)  # fires on upward crossing: P rises above limit
end
```

**Key points:**
- First argument is the power symbolic directly — no `ssys` needed.
  `ssys.P` for standalone PK (root system), `ssys.pk.P` for nested PK.
- Condition is a pure Float64 expression — no side effects, clean zero-crossing.
- `change_state` called in `affect!` (not condition) — fires exactly once at the crossing.
- `p_idx` computed lazily via `variable_index(integrator, p_sym)` inside affect! — called
  once at event time, not every step. The integrator implements SymbolicIndexingInterface.
- `terminate=true` by default: stops solver early. Pass `terminate=false` to simulate
  the full post-SCRAM shutdown transient driven by negative control reactivity.

**Usage:**
```julia
# Standalone PK (root system):
cb = scram_callback(ssys.P, ctrl)

# Full loop (PK nested as :pk subsystem — Phase 49):
cb = scram_callback(ssys.pk.P, ctrl)

sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```

### dPdt via integrator.du (D-04)

`dPdt` is `@observed` — NOT in the ODE state vector. Cannot use `variable_index` on it.

Instead: `p_idx = variable_index(ssys, p_sym)` for `P` (which IS a state), then
`integrator.du[p_idx]` gives the ODE derivative of P = dPdt by formulation.

dPdt is passed to `change_state` even though `SCRAMCondition` ignores it — for future
extensibility (e.g. `SCRAM_at_dPdt`, combined power+rate state machines).

### Flapper refactor — remove SymbolicContinuousCallback (D-05)

`src/components/flapper.jl` changes:

1. **Remove** `using ModelingToolkit: SymbolicContinuousCallback` import.
2. **Remove** `use_callback` parameter from constructor.
3. **Remove** `threshold` from `@parameters` — it is only needed for the callback condition,
   which is now external. No equation inside Flapper uses `threshold`.
4. **Remove** the `if use_callback ... else ... end` branch — always emit:
   ```julia
   compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
   ```
5. Keep all other behavior: `T_open`, `xi`, `ref_mdot`, resistance equation, `Dt(T_open) ~ 0`.

Result: Flapper is a clean equation system with one latching state (`T_open`) and no
embedded event logic.

### flapper_callback factory (D-06)

New function in `src/components/flapper.jl`:

```julia
function flapper_callback(ssys; threshold=0.01)
    T_open_idx = variable_index(ssys, ssys.flapper.T_open)

    # ref_mdot may be algebraic (substituted away by mtkcompile).
    # Use integrator[sym] (symbolic indexing via SymbolicIndexingInterface) which
    # follows the substitution chain correctly — safer than variable_index for
    # potentially-algebraic variables.
    ref_mdot_sym = ssys.flapper.ref_mdot

    condition = (u, t, integrator) -> integrator[ref_mdot_sym] - threshold
    affect!   = (integrator) -> (integrator.u[T_open_idx] = integrator.t)

    ContinuousCallback(
        condition,
        nothing,   # ignore upward crossing (flow returns above threshold — valve stays open)
        affect!    # downward crossing: latch T_open = current solver time
    )
end
```

`threshold` kwarg with default `0.01` — same as the previous `@parameters threshold = 0.01`
default. Users who need a different threshold pass it explicitly.

**Note on subsystem namespace:** `ssys.flapper.T_open` and `ssys.flapper.ref_mdot` assume
the Flapper is a subsystem named `:flapper`. If composed with a different name, the caller
adjusts the symbolic path and passes it. Future improvement: `flapper_callback(ssys, flapper_sys; threshold)`.

### Test updates (D-07)

`test/test_flapper.jl`:
- FLAP-05 test currently relies on internal `SymbolicContinuousCallback`. Update to pass
  `flapper_callback(ssys; threshold=threshold_val)` via `callbacks=`.
- SOLV-01: uses a custom `ContinuousCallback`, unaffected.

`test/test_loss_of_flow.jl`:
- LOF-02 already uses an external `ContinuousCallback` with manual `variable_index`. This
  test was a workaround for the topology issue. After the refactor, it can be simplified to
  use `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)`.

`test/test_point_kinetics.jl`:
- New `@testset "SCRAM-01: SCRAM_at_power"` — tests SCRAMCondition struct, callable semantics.
- New `@testset "SCRAM-02: scram_callback"` — standalone PK, step reactivity drives P above
  1.5; asserts solver terminates before tspan end, `ctrl.state == :SCRAM`,
  `ctrl.log` contains `(:SCRAM, t_scram)`, `t_scram > 0.1` (fires after step insertion).

### File placement and exports (D-08)

- `SCRAMCondition`, `SCRAM_at_power`, `scram_callback` → `src/components/point_kinetics.jl`
- `flapper_callback` → `src/components/flapper.jl`
- Remove `SymbolicContinuousCallback` import from `flapper.jl`
- `src/STREAM.jl` exports: add `scram_callback`, `flapper_callback`
- `src/STREAM.jl` exports: `SCRAMCondition` also exported (users need the type for dispatch)

### terminate! is optional (D-09)

`terminate!(integrator)` stops the ODE solver early. Without it, the simulation continues
and the reactor shuts down correctly via the `input_reactivity` callable returning large
negative reactivity after `ctrl.state == :SCRAM`. `terminate!` is a compute optimization.

Default: `terminate=true` (saves compute). Pass `terminate=false` to simulate the full
post-SCRAM shutdown transient (e.g., for validating the shutdown kinetics).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Files being modified
- `src/components/flapper.jl` — full file; remove SymbolicContinuousCallback, use_callback,
  threshold parameter; add flapper_callback function
- `src/components/point_kinetics.jl` — add SCRAMCondition struct, SCRAM_at_power, scram_callback
- `src/STREAM.jl` — add exports for flapper_callback, scram_callback, SCRAMCondition
- `test/test_flapper.jl` — update FLAP-05 to pass external flapper_callback
- `test/test_loss_of_flow.jl` — simplify LOF-02 to use flapper_callback

### Existing external callback reference (the established pattern)
- `test/test_loss_of_flow.jl` lines 113–125 — LOF-02 manual ContinuousCallback using
  `variable_index` + `integrator.u[idx]` direct write. This is exactly the pattern
  `flapper_callback` formalizes.
- `test/test_flapper.jl` lines 134–153 — SOLV-01 user-supplied ContinuousCallback passing;
  confirms `solve_transient` forwards callbacks correctly.

### solve_transient
- `src/solvers.jl` line 99 — `callbacks` kwarg confirmed present, forwarded to DiffEq
  `solve` as `callback = callbacks`. No changes needed.

### Python STREAM reference
- `~/projects/STREAM/stream/calculations/point_kinetics.py` — `SCRAM_at_power` (line 372),
  `ReactivityController.change_state` (~line 155). Study for semantic alignment.

</canonical_refs>

<code_context>
## Existing Code Insights

### Pattern being formalized
LOF-02 (`test_loss_of_flow.jl:113`) already uses the exact external `ContinuousCallback`
pattern that Phase 48 formalizes for Flapper:
```julia
i_T_open   = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
i_ine_mdot = ModelingToolkit.variable_index(ssys, ssys.ine.port_in.mdot)
cb = ContinuousCallback(
    (u, t, integrator) -> u[i_ine_mdot] - BYPASS_THRESHOLD,
    nothing,
    (integrator) -> (integrator.u[i_T_open] = integrator.t),
)
```
`flapper_callback` wraps this pattern behind a clean API. LOF-02 can be simplified to use it.

### Flapper component current state
- `src/components/flapper.jl` has `use_callback=true` parameter and conditional
  `SymbolicContinuousCallback` + `continuous_events=[cb]` branch — both removed in Phase 48.
- `threshold` is currently `@parameters threshold = 0.01`. After refactor: removed from
  component, becomes a kwarg to `flapper_callback`.
- `T_open`, `xi`, `ref_mdot`, resistance equation, `Dt(T_open) ~ 0` — all unchanged.

### ReactivityController readiness
- `abort_states`, `change_state`, `worth`, `log` — all implemented (Phase 46). No changes.
- `state_machine` field is currently untyped (`Any`). After D-02, when `SCRAM_at_power` is
  used, `ctrl.state_machine` is a `SCRAMCondition` and `scram_callback` reads `.power_limit`
  from it. No change to `ReactivityController` struct needed.

### `@observed` constraint
`dPdt`, `beta_total`, `reactivity` in PointKinetics are `@observed` — NOT in ODE `u` vector.
`variable_index` on observed vars returns nothing. Phase 48 avoids this: uses
`variable_index(ssys, ssys.pk.P)` (state var) for `du` index, never on `dPdt` directly.

</code_context>

<specifics>
## Specific Ideas

- User wants ONE mental model for callbacks: `_callback(ssys, ...)` factories, always
  `ContinuousCallback`, always passed externally. No hidden magic inside components.
- Flapper should "make sense for the user" — the current `use_callback=true/false` flag
  with its topology-dependent failure mode is confusing. Remove it entirely.
- `terminate!` is optional in `scram_callback` — keyword arg `terminate=true` default.
  Allows simulating full post-SCRAM shutdown when needed.

</specifics>

<deferred>
## Deferred Ideas

- Power-to-heat coupling (`fuel.power ~ pk.P * scale`) — Phase 49
- `build_loop_pk` example — Phase 49
- Python STREAM cross-validation — Phase 49
- Multiple simultaneous SCRAM conditions (T_outlet > limit AND/OR P > limit) —
  use `CallbackSet(cb1, cb2)`; document pattern but don't implement in Phase 48
- `flapper_callback(ssys, flapper_sys; threshold)` with explicit component arg for
  non-standard subsystem names — future improvement if needed
- Automatic `change_state` wiring in `solve_transient` (so users don't need to pass
  scram_callback manually) — future convenience; keep explicit for Phase 48

</deferred>

---

*Phase: 48-scram-solver-integration*
*Context gathered: 2026-04-08 (major update — unified ContinuousCallback factory pattern)*
