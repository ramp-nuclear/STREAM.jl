# Phase 3: Integration and Validation - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the four built components (Pump, Friction, Channel, Gravity) into a closed forced-convection loop using MTK's `connect()` + `compose()` + `mtkcompile()`, expose a clean solver API (`solve_steady` / `solve_transient`), and validate results against Python STREAM within tolerance. No new components, no new physics — this phase proves the architecture works end-to-end.

</domain>

<decisions>
## Implementation Decisions

### Loop assembly API (SYS-01, SYS-02)
- **Manual wiring** — user calls `connect(pump.port_out, friction.port_in)`, etc., then `compose()` and `mtkcompile()`. No convenience constructor (would hide the MTK structure this project is trying to validate)
- The closed loop (Pump → Friction → Channel → back to Pump) is the reference topology

### Solver return values (SOLV-01, SOLV-02)
- **Return raw MTK solution** (`ODESolution` / steady-state solution) from both `solve_steady()` and `solve_transient()`
- MTK solutions already support symbolic indexing: `sol[sys.channel.T_out]`, `sol[sys.pump.port_in.P]` — this is sufficient for v0.1
- **Deferred:** a thin `SteadySolution(sol, sys)` / `TransientSolution(sol, sys)` wrapper that adds named property accessors (like Python STREAM's `Solution` object) — the right design will be clearer once the raw solution is in use. Document the idea in a code comment so it's not lost.

### Steady-state solver strategy (SOLV-01)
- Use **`SteadyStateProblem` + `SSRootfind()` + KINSOL** (Sundials)
- Conceptually: set all `dT[i]/dt = 0`, solve the resulting algebraic system directly (same logic as Python STREAM's `scipy.optimize.root`)
- Fast — no time integration overhead; MTK reduces equations via `mtkcompile` before the solve
- **Initial guess (`u0`)**: caller provides explicit `u0` dict keyed on symbolic variables (e.g., `Dict(sys.channel.T => fill(313.0, n), ...)`)
- Physics-based helper for `u0` (energy-balance: `T_guess[i] = T_inlet + i * Q_wall/(n*mdot_guess*cp(T_inlet))`) — implement as a utility function `steady_state_guess(T_inlet, Q_wall, mdot_guess, n)` so callers don't have to derive it manually

### Transient solver strategy (SOLV-02)
- Use MTK's standard `ODEProblem` + Sundials IDA (DAE solver, already a dependency)
- Step change applied as a time-dependent parameter or callback in the problem definition
- Returns the full `ODESolution` (time-series)

### Validation reference case (VAL-01, VAL-02, VAL-03)
**Steady-state parameters (MTR-like):**
- Channel: `n=10`, `L=0.6m`, `D_h=0.01m`, `A=7.85e-5 m²` (circular tube, D=1cm — same geometry as Phase 2 tests)
- Friction: `L=0.3m`, `D=0.01m`, `A=7.85e-5 m²`
- Pump: `dP_pump = 3.0e4 Pa` (30 kPa)
- `Q_wall = 10,000 W` (10 kW uniform over 10 cells)
- `T_inlet = 313.15 K` (40°C)

**Reference value generation:**
- Write `test/generate_reference.py` — runs Python STREAM's components on the same inputs, prints `T_outlet` and `mdot`
- User confirms numbers are physically sensible before hardcoding
- Hardcode in `runtests.jl` with `rtol=0.01` (1% tolerance for VAL-01)

**Transient validation (VAL-02):**
- Step change: `Q_wall: 10kW → 20kW` at `t=10s`
- Expected: `T_outlet` rises and settles to a new steady state
- Qualitative check only: temperature goes up, stabilizes, no solver divergence

### Test suite structure (VAL-03)
- Continue in `test/runtests.jl` — add `@testset "STREAM Phase 3 Tests"` block (consistent with Phase 1+2 pattern)
- `julia --project -e "using Pkg; Pkg.test()"` runs everything
- **Compile-time benchmark**: time `mtkcompile` on the full closed loop, report with `@info` but do NOT assert on it — answers the open question from STATE.md without making CI fragile

### Claude's Discretion
- Exact solver tolerances for SSRootfind/KINSOL (abstol, reltol)
- How to express the time-varying Q_wall step in the transient problem (callback vs. time-dependent parameter)
- Whether to put `solve_steady` / `solve_transient` as free functions in `STREAM` module or in a new `src/solvers.jl`
- Absolute pressure reference constraint for the closed loop (MTK needs one pressure pinned to remove the gauge degree of freedom — e.g., `pump.port_in.P = 1e5`)

</decisions>

<specifics>
## Specific Ideas

- Python STREAM's `symmetric_plate_steady_state` generates a temperature initial guess as: `T_cool[i] = T_inlet + cumsum(P_z / (mdot * cp))`. The equivalent for our simpler loop: `T_guess[i] = T_inlet + i * Q_wall / (n * mdot_guess * cp_water(T_inlet))`. Implement this as `steady_state_guess(; T_inlet, Q_wall, mdot_guess, n)`.
- The thin solution wrapper idea (for future reference): `SteadySolution` wraps the MTK solution and exposes fields like `T_outlet`, `mdot`, `P_inlet` as named properties. Python STREAM does this with its `State` + `save()` pattern. In Julia-STREAM v0.2, this would wrap `ODESolution` + the compiled `sys` to provide `sol.T_outlet` instead of `sol[sys.channel.T_out]`.
- MTK compile time benchmark: `@info "mtkcompile time: $(t_compile)s" n_equations n_unknowns`. This answers the open question from STATE.md about compile time on ~30-equation systems.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Pump(; name, dP_pump)` — FlowPort in/out, sets `port_out.P - port_in.P ~ dP_pump`. Ready to use.
- `Friction(; name, L, D, A)` — Darcy-Weisbach with Blasius. Ready to use.
- `Channel(; name, n, L, D, A)` — n-cell FV with Dittus-Boelter. Has `T_out` and `dP` observables. Ready to use.
- `Gravity(; name, H, A_grav)` — hydrostatic dP. Ready to use (include if loop has vertical section).
- All components use `instream(port.T)` for temperature advection — correct for closed-loop MTK stream semantics.
- Phase 2 tests already use: `n=5, L=1.0, D=0.01, A=7.85e-5` — Phase 3 reference case uses same D and A (n=10, L=0.6 for channel).

### Established Patterns
- `compose(System(...), port_in, port_out)` — how components are constructed (Phase 2 pattern)
- `connect(a.port_out, b.port_in)` — MTK acausal connection syntax
- `mtkcompile(sys; fully_determined=false)` for isolated components; Phase 3 full loop should compile with `fully_determined=true` (once pressure gauge freedom is fixed)
- Temperature in Kelvin everywhere; no range guards on fluid properties
- `import STREAM: Channel` needed in test files to resolve Base.Channel ambiguity (Phase 2 pattern)

### Integration Points
- `src/STREAM.jl`: add `include("solvers.jl")` and export `solve_steady`, `solve_transient`, `steady_state_guess`
- `test/runtests.jl`: add `@testset "STREAM Phase 3 Tests"` at end of file
- `test/generate_reference.py`: new Python script to extract reference values from Python STREAM

</code_context>

<deferred>
## Deferred Ideas

- Thin solution wrapper (`SteadySolution` / `TransientSolution`) — deferred to v0.2 once the raw MTK solution usage patterns are clear
- `STREAM.Fluids` sub-module namespace — explicitly deferred from Phase 1 discussion

</deferred>

---

*Phase: 03-integration-and-validation*
*Context gathered: 2026-03-12*
