# Phase 8: Inertia and HeatExchanger - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Add two lumped components: `Inertia` (ODE transient pressure-drop component) and `HeatExchanger` (public API for the existing internal `_make_temp_bc`). Both must be exported and accessible. `build_loop` family is updated to use `HeatExchanger` directly.

</domain>

<decisions>
## Implementation Decisions

### Inertia parameter API
- Combined single parameter: `Inertia(; name, L_over_A)` — user pre-computes L/A
- Parameter named `L_over_A` internally (self-documenting, mirrors the formula)
- Equation: `port_in.P - port_out.P ~ L_over_A * Differential(t)(port_in.mdot)`
- No explicit `mdot` state variable — use `port_in.mdot` implicitly (consistent with Resistor/Gravity/Friction)
- Temperature: passthrough (`port_out.T ~ instream(port_in.T)`, `port_in.T ~ instream(port_out.T)`)
- No `KirchhoffWithDerivatives` equivalent needed — MTK handles ODE/DAE structure automatically

### Transient validation test (COMP-01)
- RL-decay circuit: Inertia + Resistor in a closed loop, no pump
- Initial condition: `mdot(t=0) = 1.0` kg/s (pump already off)
- Analytical solution: `mdot(t) = exp(-(R / L_over_A) * t)`
- Test parameters: `R = 1.0`, `L_over_A = 1e3` (tau = 1000s)
- Tolerance: 1% rtol — consistent with GRAV-02 and NET-03
- Mirrors Python STREAM's canonical Inertia RL-circuit test

### HeatExchanger (COMP-02)
- Move `_make_temp_bc` from `solvers.jl` to `components.jl`, rename to `HeatExchanger`
- Identical 4-equation structure: mass balance, no pressure drop, `port_out.T ~ T_bc`, `port_in.T ~ instream(port_out.T)`
- Export `HeatExchanger` from `STREAM.jl`
- Remove `_make_temp_bc` from `solvers.jl`; update all three `build_loop` variants (`build_loop`, `build_loop_vertical`, `build_loop_transient`) to call `HeatExchanger` directly
- No pressure-drop parameter added — COMP-02 explicitly says no pressure drop

### Claude's Discretion
- ODE solver choice for transient test (Rodas5P or similar stiff solver)
- Exact time span for RL-decay validation (enough points to verify exponential shape)
- Whether to add a `build_loop_inertia` helper or just test Inertia as a standalone component

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FlowPort()`: standard port, used by all components
- `Friction`, `Gravity`, `Resistor` in `components.jl`: exact pattern to follow for Inertia (same 4-equation structure, just replace pressure eq with ODE)
- `_make_temp_bc` in `solvers.jl` lines 35-46: already complete 4-equation HeatExchanger implementation — just move and rename
- `build_loop`, `build_loop_vertical`, `build_loop_transient` in `solvers.jl`: all call `_make_temp_bc` and need to be updated to `HeatExchanger`

### Established Patterns
- All components: `compose(System(eqs, t, vars, pars; name=name), port_in, port_out)`
- Differential operator: `Dt = Differential(t)` — already used in `Channel`'s energy balance
- `mtkcompile(system, fully_determined=false)` for standalone component tests (established in Phase 7)
- TDD: write failing test first, then implement

### Integration Points
- `src/components.jl`: add `Inertia` and `HeatExchanger` here
- `src/STREAM.jl`: add both to exports
- `src/solvers.jl`: remove `_make_temp_bc`, update 3 build_loop functions
- `test/runtests.jl`: add Phase 8 testset with COMP-01 (RL-decay) and COMP-02 (HeatExchanger standalone + build_loop regression)

</code_context>

<specifics>
## Specific Ideas

- MTK makes Kirchhoff-with-derivatives trivial: `Differential(t)(port_in.mdot)` is a first-class symbolic expression — no manual derivative tracking needed (confirmed in discussion)
- Python STREAM test reference: `test_inertia_through_RL_circuit_follows_analytic_solution` in `tests/test_general/test_integrations.py` lines 433-466

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 08-inertia-and-heatexchanger*
*Context gathered: 2026-03-13*
