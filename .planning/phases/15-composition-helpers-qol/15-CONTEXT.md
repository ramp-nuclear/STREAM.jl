# Phase 15: Composition Helpers & QoL - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Give users one-call MTR subsystem assembly (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`) and diagnostic introspection (`@observed` Re/Nu/h_tc/T_wall/Pe/velocity/q_wall, `check_gravity_mismatch`, `port` helper). Covers COMP-01–04, QOL-01–03.

Transient validation and new physics correlations are out of scope — Phase 16.

</domain>

<decisions>
## Implementation Decisions

### Composition helper input API

- Helpers take **pre-built component instances**, not kwargs-through:
  ```julia
  cac  = ChannelAndContacts(; name=:ch, n=5, geometry=geom, htc_correlation=rd.htc, ...)
  fuel = HeatDiffusion(;      name=:fuel, nz=5, nx=3, ...)
  sys  = symmetric_plate(cac, fuel; name=:plate)
  ```
- User names their components before passing in — helpers compose them as-is
- Consistent with how `build_loop` and all existing examples work
- Correlation kwargs, geometry choices, n — all caller responsibility

### Composition helper return type

- All helpers return a **raw `ODESystem`** via `compose()`
- User calls `mtkcompile(sys)` themselves, then `solve_steady()` or `solve_transient()`
- No hidden compilation, no magic — same pattern as every existing component
- `build_initializeprob=false` must be the default in any solve helpers called downstream (pre-existing project decision for HeatDiffusion+CAC systems)

### plate() and one_sided_connection() — just wiring

- `plate(ch_left, ch_right, fuel; name)`: connects `ch_left.thermal_right[i] ↔ fuel.thermal_left[i]` and `ch_right.thermal_left[i] ↔ fuel.thermal_right[i]` — nothing else
- `one_sided_connection(channel, fuel, side=:left; name)`: connects the specified side only; other side stays adiabatic (MTK default)
- No n/geometry validation inside helpers — caller ensures matching `n` and `nz`

### compose_systems — thin MTK wrapper

- `compose_systems(sys_a, sys_b, connections; name)` is a convenience wrapper around:
  ```julia
  ODESystem(connections, t, systems=[sys_a, sys_b]; name=name)
  ```
- `connections` is a `Vector{Equation}` — same thing `connect()` returns — no new syntax
- Accepts variadic systems: `compose_systems(a, b, c, connections; name)` via splatted args
- **Important distinction from Python STREAM**: this is NOT analogous to `fg.aggregator + heat_agr`. In MTK there is no need to merge separate hydraulic and thermal aggregators — `ChannelAndContacts` is already a single object with both port types, and `connect()` handles Kirchhoff equations automatically. `compose_systems` is for combining independently-built subsystems (e.g., multiple `symmetric_plate` assemblies) with cross-connections (e.g., hydraulic series wiring between plates)

### @observed variables in ChannelAndContacts

Declare all physically meaningful derived quantities as observed — matching Python STREAM `ChannelVar` coverage where possible:

| Variable | Expression | Notes |
|---|---|---|
| `Re[i]` | `mdot * Dh / (mu_water(T[i]) * A)` | Per-cell Reynolds number |
| `Nu[i]` | `htc_correlation(Re[i], Pr[i])` | Per-cell Nusselt number |
| `h_tc_left[i]` | `Nu[i] * k_water(T[i]) / Dh * heated_parts[1]` | Per-cell left-face HTC |
| `h_tc_right[i]` | `Nu[i] * k_water(T[i]) / Dh * heated_parts[2]` | Per-cell right-face HTC |
| `T_wall_left[i]` | `thermal_left[i].T` | Alias — left wall temperature |
| `T_wall_right[i]` | `thermal_right[i].T` | Alias — right wall temperature |
| `Pe[i]` | `Re[i] * cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])` | Péclet number |
| `velocity[i]` | `mdot / (rho_water(T[i]) * A)` | Per-cell flow velocity |
| `q_wall_left[i]` | heat flux left face per cell | Derived from Q_flow / area |
| `q_wall_right[i]` | heat flux right face per cell | Derived from Q_flow / area |

- **@observed propagates through compose() automatically** — confirmed from MTK source (`abstractsystem.jl:1710-1722`): `observed(sys)` recursively collects from all subsystems and namespaces them. So `sol[sys.ch.Re[i], :]` works even when `ch` is nested inside a `symmetric_plate` composed system.
- Declare using the `observed` keyword in the `ODESystem` constructor inside `ChannelAndContacts`

### check_gravity_mismatch

- **Signature**: `check_gravity_mismatch(sys::ODESystem) -> Symbol`
- **Returns**: `:ok` if balanced, `:mismatch` if not (with a warning message showing the residual)
- **Input**: Any composed ODESystem (pre- or post-`mtkcompile`)
- **Algorithm**: Substitute `mdot=0` into all pressure equations and check whether the resulting linear pressure system is consistent. This correctly handles multi-branch networks — per-loop balance is implicitly verified without needing graph cycle detection
- **Rationale for "solve at zero flow"**: Summing all gravity terms globally is incorrect for multi-branch networks (separate loops with opposing imbalances could cancel). Per-loop detection requires graph traversal. Substituting mdot=0 is topology-agnostic and physically exact.

### port() helper

- `port(sys, :thermal_left, i)` wraps `getproperty(sys, Symbol(:thermal_left, i))`
- Same pattern as existing MTK port array access in tests (established in Phase 12 context)
- Thin — no validation; planner decides exact method signature

### Claude's Discretion

- Exact Julia file organization (new file for helpers vs. append to components.jl or solvers.jl)
- Whether `compose_systems` takes `systems...` as a splatted first argument or a `Vector{ODESystem}`
- Exact expression for `h_tc_left[i]` vs `h_tc_right[i]` (may simplify if `heated_parts[1] == heated_parts[2]` for symmetric case, but keep both for generality)
- Exact residual threshold for `check_gravity_mismatch` `:ok` vs `:mismatch` decision
- Whether `q_wall_left[i]` is `thermal_left[i].Q_flow / cell_area` or derived differently

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `ChannelAndContacts` (`src/components.jl:362`): has `thermal_left[1:n]` and `thermal_right[1:n]` ThermalPort arrays — these are the connection targets for all composition helpers
- `HeatDiffusion` (`src/components.jl:574`): has `thermal_left[1:n]` and `thermal_right[1:n]` — same naming, so `connect(cac.thermal_right[i], hd.thermal_left[i])` is the wiring pattern
- `_channel_base_eqs` (`src/components.jl:312`): already computes Re, Nu, h_tc inline — `@observed` declarations will be added here
- `build_loop`, `build_loop_vertical` (`src/solvers.jl`): examples of the compose-then-solve pattern that helpers should follow

### Established Patterns

- MTK port array access: `getproperty(sys, Symbol(:thermal_left, i))` — `port()` wraps this exactly
- `build_initializeprob=false` for coupled HeatDiffusion+CAC — must propagate into any solve helpers
- `ifelse()` for smooth switching (not needed in composition helpers — setup-time code only)
- Exports in `src/STREAM.jl`: new helpers must be added to the export list

### Integration Points

- `src/STREAM.jl` exports list: add `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`, `check_gravity_mismatch`, `port`
- `ChannelAndContacts` ODESystem constructor: add `observed=[...]` keyword with all derived variables
- Phase 16 depends on these helpers for validation assembly — correct wiring is critical

</code_context>

<specifics>
## Specific Ideas

- The Python analog of `compose_systems` is `fg.aggregator + heat_agr`, but the motivation is different in Julia: Python needs it to merge separately-built hydraulic and thermal DAE aggregators. In Julia, the primary use case is combining multiple per-plate assemblies (each a `symmetric_plate` ODESystem) into a full reactor channel array wired hydraulically in series — cross-subsystem connections.
- Python `ChannelVar` parity is the target for `@observed` coverage — everything derivable in the MTK symbolic context should be exposed.

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope.

</deferred>

---

*Phase: 15-composition-helpers-qol*
*Context gathered: 2026-03-15*
