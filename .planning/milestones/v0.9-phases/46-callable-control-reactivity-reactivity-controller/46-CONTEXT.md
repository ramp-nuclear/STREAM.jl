# Phase 46: Callable Control Reactivity & ReactivityController — Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `PointKinetics` so that control reactivity can vary with time via a callable MTK parameter `rho_c_fn(t)`. Add a `ReactivityController` Julia struct (pure Julia, not MTK) that encapsulates a user-defined reactivity function, tracks state transitions, and provides `worth(ctrl, t)` as the callable interface. No SCRAM callback yet (Phase 49), no temperature feedback (Phase 47). The state machine struct is constructed and can have its state changed externally, but no callback wires it to the integrator in this phase.

</domain>

<decisions>
## Implementation Decisions

### rho Composition (D-01) — G1 resolved
- **D-01:** Additive composition: `rho_total(t) = rho_val + rho_c_fn(t)`.
  - `rho_val` (scalar MTK parameter) stays as the base/bias reactivity (default 0.0 = critical).
  - `rho_c_fn(t)` is the control reactivity, an MTK callable parameter, default `t -> 0.0`.
  - The ODE P equation becomes: `Dt(P) ~ (rho_val + rho_c_fn(t) - beta_sum) / Lambda_gen * P + precursor_source`
  - This extends cleanly to Phase 47: `rho_val + rho_c_fn(t) + alpha_c*(T_c - T_c0) + alpha_f*(T_f - T_f0)`.

### Constructor Design (D-02) — multiple dispatch
- **D-02:** Two constructors via multiple dispatch (Pump precedent, CLAUDE.md rule):
  - `PointKinetics(; name, rho=0.0, ...)` — Phase 45 scalar mode, unchanged. No callable param.
  - `PointKinetics(rho_c_fn::Any; name, rho_val=0.0, ...)` — Phase 46 callable mode. Positional callable arg enables dispatch on type. Uses `FType = typeof(rho_c_fn)` and `@parameters (rho_c_fn::FType)(..)` per Pump precedent.
- **D-03:** The `observed` block's `reactivity` variable is updated to `rho_val + rho_c_fn(t)` in callable mode (was just `rho_val` in Phase 45).

### InputReactivity Signature (D-04) — G2 resolved
- **D-04:** State-aware: `(state, t_state, t) -> Float64` (matches Python STREAM `InputReactivity` protocol).
  - `state` is the current controller state (any `Enum` or `Symbol`).
  - `t_state` is the time the current state was entered.
  - `t` is the current simulation time.
  - `ReactivityController.worth(ctrl, t)` calls `ctrl.input_reactivity(ctrl.state, ctrl.t_state, t)`.
  - Users who don't need state-dependence write: `(state, t_state, t) -> my_function(t)` (ignores first two args).

### ReactivityController Struct (D-05)
- **D-05:** Pure Julia mutable struct matching Python STREAM API:
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
- **D-06:** Default constructor: `ReactivityController(input_reactivity=nothing; initial_state=:NORMAL, initial_time=0.0, state_machine=nothing, abort_states=nothing)`. Matches Python STREAM kwarg names.
  - `input_reactivity=nothing` → defaults to `(state, t_state, t) -> 0.0`.
  - `state_machine=nothing` → defaults to identity (state never changes automatically).
  - `abort_states=nothing` → defaults to empty Set.
- **D-07:** `worth(ctrl::ReactivityController, t)` — the primary output method; calls `ctrl.input_reactivity(ctrl.state, ctrl.t_state, t)`.
- **D-08:** `change_state(ctrl::ReactivityController, t, power, dPdt)` — calls `ctrl.state_machine(ctrl.state, t, power, dPdt)` and updates `ctrl.state`, `ctrl.t_state`, appends to `ctrl.log` if state changed.
- **D-09:** Make `ReactivityController` callable: `(ctrl::ReactivityController)(t) = worth(ctrl, t)`. This lets users pass `ctrl` directly as the MTK callable parameter (`FType = typeof(ctrl)`), avoiding the `t -> worth(ctrl, t)` wrapper.

### MTK Integration Pattern (D-10)
- **D-10:** User workflow for callable mode:
  ```julia
  ctrl = ReactivityController((state, t_state, t) -> 0.003 * (t >= 1.0 ? 1.0 : 0.0))
  @named pk = PointKinetics(ctrl; rho_val=0.0, ...)  # FType = ReactivityController
  ssys = mtkcompile(pk)
  op = [ssys.rho_c_fn => ctrl, ssys.P => ic.P, ...]  # pass ctrl as the callable
  sol = solve_transient(ssys, op, tspan)
  ```
- **D-11:** When ReactivityController state changes (Phase 49 callback calls `change_state`), subsequent `ctrl(t)` calls automatically see the new state because MTK stores the callable reference, not a value snapshot.

### File Layout (D-12)
- **D-12:** `ReactivityController` and `worth`, `change_state` go in `src/components/point_kinetics.jl` (same file, appended after Phase 45 content). Export `ReactivityController`, `worth`, `change_state` from `src/STREAM.jl`.
- **D-13:** Tests added to `test/test_point_kinetics.jl`. New `@testset "PK-03: Callable Control Reactivity"` and `@testset "RC-01: ReactivityController"` blocks.

### Claude's Discretion
- Exact type parameter approach for `ReactivityController{S, F}` or simpler `Any`-typed fields
- Whether to expose `worth_history` (Python STREAM has it; defer if not needed for Phase 46 tests)
- Default state type: `:NORMAL` as Symbol or a `OneWayToSCRAM` enum (Symbol is simpler for now)
- Docstring structure (follow existing component patterns)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 45 baseline
- `src/components/point_kinetics.jl` — Existing PointKinetics ODE structure; Phase 46 adds to this file
- `.planning/phases/45-pointkinetics-bare-component-steady-state-ics/45-CONTEXT.md` — D-01 through D-10 decisions that Phase 46 inherits

### MTK callable parameter pattern
- `src/components/pump.jl` — `Pump(dP_pump::Any; name)` dispatch; `@parameters (dP_pump_fn::FType)(..)` syntax; `FType = typeof(callable)` at construction time

### Python STREAM reference
- `~/projects/STREAM/stream/calculations/point_kinetics.py` — `InputReactivity` protocol (line 31), `ReactivityController.__init__` (line 100), `worth(t)` method (line 146), `change_state` (line 133), `should_continue` (line 143)

### Requirements
- `.planning/REQUIREMENTS.md` §PK-03 — step insertion prompt-jump test (rtol=1e-2), ramp insertion test
- `.planning/REQUIREMENTS.md` §RC-01 — ReactivityController struct, state log, abort_states

</canonical_refs>

<code_context>
## Existing Code Insights

### Phase 45 PointKinetics parameters to extend
- Current `pars` block in `PointKinetics(; name, rho=0.0, ...)` uses `rho_val` scalar — the callable constructor adds `rho_c_fn` on top, keeping `rho_val` as a separate scalar parameter.
- The 6 individual beta/lambda scalars pattern (D-01 from Phase 45) continues unchanged.

### Pump callable pattern (exact syntax to replicate)
```julia
FType = typeof(rho_c_fn)
pars = @parameters (rho_c_fn::FType)(..)  # variadic (..) not (t)
# Used in equations as: rho_c_fn(t)
```

### Prompt-jump analytical formula (for test validation)
For a step reactivity insertion δρ at t=0 (using in-hour approximation):
- Immediate power jump ≈ `beta / (beta - delta_rho) * P0` (prompt-jump approximation)
- Valid for |δρ| << β (sub-prompt-critical)

</code_context>

<deferred>
## Deferred Ideas

- `worth_history(ctrl, t)` — history-aware worth that replays past states (Python STREAM has this; not needed for Phase 46 tests; defer to Phase 49 post-SCRAM analysis)
- SCRAM callback wiring (`SymbolicContinuousCallback` that calls `change_state`) — Phase 49
- `SCRAM_at_power` factory — Phase 49 (RC-03)
- Full `OneWayToSCRAM` enum type — can use plain Symbols in Phase 46; typed enum in Phase 49

</deferred>

---

*Phase: 46-callable-control-reactivity-reactivity-controller*
*Context gathered: 2026-04-04*
