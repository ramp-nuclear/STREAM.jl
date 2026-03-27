# Phase 23: Flapper & Solver Events - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement the `Flapper` check-valve component as an MTK ODESystem with a continuous event that triggers on ref_mdot threshold crossing, and expose a `callbacks` keyword to `solve_transient` for user-supplied DifferentialEquations.jl callbacks alongside MTK-native events.

</domain>

<decisions>
## Implementation Decisions

### T_open representation
- **D-01:** `T_open` is a differential state variable (`@variables T_open(t)`), not a parameter. Initial value `Inf`.
- **D-02:** Equation `Dt(T_open) ~ 0` holds it constant until the MTK continuous event fires and sets `T_open = t` (current solver time).
- **D-03:** MTK continuous events can only mutate state variables (they write into the solver's state vector); an algebraic variable has no slot to write to. This is the accepted MTK pattern for latching behavior.
- **D-04:** The ramp expression `clamp((t - T_open)/dt, 0, 1)` evaluates to 0 while `T_open = Inf`, so the Flapper stays closed before the event with no special-casing needed.
- **D-05:** The exact MTK `continuous_events` affect syntax must be verified in the research/planning phase and tested explicitly — this is non-trivial and requires integration tests.

### Latch behavior
- **D-06:** Flapper **latches open** — once `T_open` is set, it stays open even if `ref_mdot` recovers above threshold. No re-close event. This matches physical check-valve behavior.

### Resistance parameterization
- **D-07:** `R_closed` and `R_open` are user-visible `@parameters` on the Flapper, same tier as `dt` and `threshold`. Sensible defaults required (e.g. `R_closed = 1e8`, `R_open = 1e2` in Pa·s/kg — exact values Claude's discretion).
- **D-08:** Flapper is a **pure dP check valve** — no gravity/elevation term. The user wires a separate `Gravity` component if elevation matters. Keeps Flapper single-responsibility.

### SOLV-01 status
- **D-09:** `solve_transient(...; callbacks=nothing)` is already implemented in `src/solvers.jl` (done in Phase 22). Phase 23 adds one explicit SOLV-01 test that passes a real `CallbackSet` to `solve_transient` and verifies it fires. Closes the requirement cleanly.

### Plan split
- **D-10:** Keep the two-plan split:
  - **23-01:** Flapper component implementation (FLAP-01..04) — component code only, no tests beyond compile check
  - **23-02:** Test suite (FLAP-05, FLAP-06, explicit SOLV-01 smoke test)

### Claude's Discretion
- Exact default values for `R_closed`, `R_open`, `dt`, `threshold` parameters
- The precise MTK `continuous_events` API syntax (research must verify for the installed MTK version)
- Whether `clamp` needs to be wrapped in `ifelse()` for symbolic compatibility or can be a registered function
- How `ref_mdot` is declared (likely `@variables ref_mdot(t)` with no equation in the component — the user provides it externally via `flapper.ref_mdot ~ other.port_in.mdot`)

</decisions>

<specifics>
## Specific Ideas

- The `clamp((t - T_open)/dt, 0, 1)` smooth ramp with `3*xi^2 - 2*xi^3` Hermite blend is explicitly specified in FLAP-02 — this is locked, not a discretion item.
- User wires trigger via a plain algebraic equation: `flapper.ref_mdot ~ reference_component.port_in.mdot` during system composition (FLAP-04). No special API needed.
- The implementation must be tested "extensively" (user's words) — Plan 23-01 should include a standalone compile+event-trigger smoke test, and Plan 23-02 should have both a closed-state test and an open-transition test with numerical verification of the ramp shape.

</specifics>

<canonical_refs>
## Canonical References

No external specs — requirements are fully captured in decisions above and REQUIREMENTS.md.

### Flapper requirements
- `.planning/REQUIREMENTS.md` §Flapper — FLAP-01..06 full requirement text (exact parameter names, event condition, ramp formula)
- `.planning/REQUIREMENTS.md` §Solver Events — SOLV-01 requirement text

### Prior implementation patterns
- `src/components/pump.jl` — callable parameter pattern (`@parameters (dP_pump_fn::FType)(..)`); Flapper's `ref_mdot` wiring is different (algebraic, not callable parameter) but the file shows existing MTK component structure
- `src/solvers.jl` — SOLV-01 already implemented; callbacks kwarg is at line 101

### MTK event API (research must verify)
- MTK `continuous_events` syntax for state-variable mutation — the researcher must check ModelingToolkit.jl docs or source for the correct `[condition] => [affect]` form and whether `T_open ~ t` or `T_open => t` syntax applies

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FlowPort` connector (`src/connectors.jl`): Flapper needs two FlowPorts, identical to Pump/Resistor pattern
- `Pump(dP_pump::Real)` (`src/components/pump.jl:42`): The scalar pressure-drop equation `port_out.P - port_in.P ~ dP_pump` is the base; Flapper replaces `dP_pump` with `R(t) * port_in.mdot`
- `solve_transient` (`src/solvers.jl:99`): callbacks kwarg already wired at line 114 (`callback = callbacks`)

### Established Patterns
- New component file goes in `src/components/flapper.jl` (CLAUDE.md layout rule)
- `ifelse()` for symbolic conditionals — may be needed for `clamp` in the ramp expression
- `@observed` for diagnostic variables (Re, Nu, etc.) — Flapper may expose `xi` (ramp fraction) as `@observed` for debugging

### Integration Points
- Flapper is inserted into the loop like any other component with FlowPorts; `ref_mdot` is wired to a reference component's port via a plain equation in the composition step
- `solve_transient` receives the Flapper's MTK-native continuous event automatically after `mtkcompile`; user can additionally pass their own `CallbackSet` via `callbacks`

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 23-flapper-solver-events*
*Context gathered: 2026-03-20*
