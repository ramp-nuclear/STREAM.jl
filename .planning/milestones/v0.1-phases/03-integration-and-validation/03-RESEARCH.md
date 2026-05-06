# Phase 3: Integration and Validation - Research

**Researched:** 2026-03-12
**Domain:** MTK closed-loop assembly, SteadyStateProblem/ODEProblem solving, Python STREAM reference generation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Loop assembly**: Manual wiring — user calls `connect(pump.outlet, friction.inlet)`, etc., then `compose()` and `mtkcompile()`. No convenience constructor.
- **Reference topology**: Pump → Friction → Channel → back to Pump (closed forced-convection loop)
- **Solver return values**: Return raw MTK solution (`ODESolution` / steady-state solution) from both `solve_steady()` and `solve_transient()`. MTK symbolic indexing (`sol[sys.channel.T_out]`) is sufficient for v0.1.
- **Steady-state solver**: `SteadyStateProblem` + `SSRootfind()` + KINSOL (Sundials)
- **Initial guess helper**: `steady_state_guess(; T_inlet, Q_wall, mdot_guess, n)` utility function
- **Transient solver**: `ODEProblem` + Sundials IDA
- **Validation reference parameters**:
  - Channel: n=10, L=0.6m, D_h=0.01m, A=7.85e-5 m² (circular tube, D=1cm)
  - Friction: L=0.3m, D=0.01m, A=7.85e-5 m²
  - Pump: dP_pump = 3.0e4 Pa (30 kPa)
  - Q_wall = 10,000 W (10 kW uniform over 10 cells)
  - T_inlet = 313.15 K (40°C)
- **Reference value generation**: Write `test/generate_reference.py` — runs Python STREAM, prints T_outlet and mdot — then hardcode in `runtests.jl` with `rtol=0.01`
- **Transient validation**: Step change Q_wall: 10kW → 20kW at t=10s; qualitative check only
- **Test structure**: Append `@testset "STREAM Phase 3 Tests"` to existing `test/runtests.jl`
- **Compile-time benchmark**: `@info "mtkcompile time: $(t_compile)s"` — report only, no assertion
- **Deferred**: Thin solution wrapper (`SteadySolution`/`TransientSolution`) — v0.2

### Claude's Discretion
- Exact solver tolerances for SSRootfind/KINSOL (abstol, reltol)
- How to express the time-varying Q_wall step in the transient problem (callback vs. time-dependent parameter)
- Whether to put `solve_steady` / `solve_transient` as free functions in `STREAM` module or in a new `src/solvers.jl`
- Absolute pressure reference constraint for the closed loop (MTK needs one pressure pinned to remove gauge degree of freedom — e.g., `pump.inlet.P = 1e5`)

### Deferred Ideas (OUT OF SCOPE)
- Thin solution wrapper (`SteadySolution` / `TransientSolution`) — deferred to v0.2
- `STREAM.Fluids` sub-module namespace — explicitly deferred from Phase 1 discussion
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SYS-01 | Single closed loop (Pump → Friction → Channel → back to Pump) assembles, connects, and compiles with `mtkcompile` without errors | MTK `connect()` + `compose()` + `mtkcompile(sys; fully_determined=true)` pattern; pressure gauge-freedom fix via pinning `pump.inlet.P ~ 1e5` |
| SYS-02 | Clean user-facing API: construct components, connect them, set initial conditions, solve | `solve_steady` / `solve_transient` free functions in `src/solvers.jl`; `steady_state_guess` utility; `SteadyStateProblem(ssys, op)` + `solve(prob, SSRootfind(KINSOL()))` |
| SOLV-01 | Steady-state solver: run closed loop to steady state, return named output variables (T per cell, mass flow, pressures) | `SteadyStateProblem` + `SSRootfind(KINSOL())` from DifferentialEquations v7; caller gets raw `SteadyStateSolution` with symbolic indexing |
| SOLV-02 | Transient solver: simulate step change in channel power, return time-series solution | `ODEProblem(ssys, op, tspan)` + `solve(prob, IDA())`; `PresetTimeCallback` to flip Q_wall parameter at t=10s via `setp` |
| VAL-01 | Steady-state T_outlet and mass flow match Python STREAM within 1% on identical inputs | `test/generate_reference.py` generates hardcoded values; `@test isapprox(sol[...], ref; rtol=0.01)` in test suite |
| VAL-02 | Transient temperature response qualitatively matches Python STREAM | Check T_outlet[end] > T_outlet[1] and solver doesn't diverge; no numerical comparison needed |
| VAL-03 | Test suite runs Python STREAM reference cases automatically | `@testset "STREAM Phase 3 Tests"` appended to `test/runtests.jl`; `julia --project -e "using Pkg; Pkg.test()"` runs all |
</phase_requirements>

---

## Summary

Phase 3 wires the four complete components (Pump, Friction, Channel, Gravity) into a closed MTK loop, exposes a clean solver API, and validates numerically against Python STREAM. No new physics — the work is entirely about MTK system assembly, solver plumbing, and reference comparison.

The key technical finding is that the steady-state solver stack is fully available in the installed packages: `DifferentialEquations v7.17.0` exports `SSRootfind` and `DynamicSS`; `Sundials v5.1.0` exports `KINSOL` and `IDA`; `ModelingToolkit v11.15.0` provides `SteadyStateProblem` and `ODEProblem` that both accept an `op` (operating point) dict as their combined u0+p argument. The MTK v11 preferred API for constructing problems from compiled systems uses `SteadyStateProblem(ssys, op)` where `op` is a `Vector{Pair}` or `Dict` containing initial conditions for state variables and parameter overrides.

The most consequential open question is the **pressure gauge freedom**: a closed hydraulic loop has no absolute pressure reference, so the compiled MTK system will have a structural singularity unless one pressure is pinned as an additional algebraic constraint (`pump.inlet.P ~ 1e5`). This must be handled before `mtkcompile` succeeds with `fully_determined=true`. The `steady_state_guess` helper requires physics-based estimates of both temperature (linear rise) and mass flow (from 30 kPa drive vs. Blasius friction estimate).

**Primary recommendation:** Implement in four sequential waves: (1) closed-loop assembly and `mtkcompile` smoke test, (2) `solve_steady` with `SSRootfind(KINSOL())` and initial guess helper, (3) `solve_transient` with `PresetTimeCallback` step change, (4) Python STREAM reference generation and tolerance comparison.

---

## Standard Stack

### Core (all already in Project.toml)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11.15.0 | Symbolic DAE compilation, `connect()`/`compose()`, `SteadyStateProblem`, `ODEProblem` | Project foundation |
| DifferentialEquations | 7.17.0 | `SSRootfind`, `DynamicSS`, `IDA`, `PresetTimeCallback`, `CallbackSet` | Umbrella package for all solvers |
| Sundials | 5.1.0 | `KINSOL` (nonlinear solver for SS), `IDA` (DAE integrator for transient) | Mirrors Python STREAM's `scipy.optimize.root` + `scikits.odes.dae("ida")` |

### Key API Confirmed Present
| Name | Package | Verified |
|------|---------|---------|
| `SSRootfind` | DifferentialEquations | `isdefined(DifferentialEquations, :SSRootfind) == true` |
| `SSRootfind(KINSOL())` | DifferentialEquations + Sundials | `typeof(SSRootfind(KINSOL())) == SSRootfind{KINSOL{:Dense}}` |
| `DynamicSS` | DifferentialEquations | `isdefined(DifferentialEquations, :DynamicSS) == true` |
| `IDA` | DifferentialEquations (via Sundials) | `isdefined(DifferentialEquations, :IDA) == true` |
| `SteadyStateProblem(sys, op)` | ModelingToolkit | Method exists; `op` is combined u0+p dict |
| `ODEProblem(sys, op, tspan)` | ModelingToolkit | Method exists; same `op` pattern |
| `PresetTimeCallback` | DifferentialEquations | `isdefined(DifferentialEquations, :PresetTimeCallback) == true` |
| `setp` | ModelingToolkit | `isdefined(ModelingToolkit, :setp) == true` — for modifying parameters in callbacks |

**IMPORTANT:** `SSRootfind` is NOT in `ModelingToolkit` — it is in `DifferentialEquations`. The solver call requires `using DifferentialEquations` (or `using SteadyStateDiffEq` which is re-exported). `src/solvers.jl` must `using DifferentialEquations, Sundials`.

**Installation:** No new packages needed. All required libraries are already in `Project.toml`.

---

## Architecture Patterns

### Recommended Project Structure Addition
```
src/
├── fluids.jl          # existing
├── connectors.jl      # existing
├── components.jl      # existing
├── solvers.jl         # NEW: solve_steady, solve_transient, steady_state_guess
└── STREAM.jl          # add: include("solvers.jl"), export new functions
test/
├── runtests.jl        # add: @testset "STREAM Phase 3 Tests"
└── generate_reference.py  # NEW: Python script to produce reference values
```

### Pattern 1: Closed-Loop Assembly with Pressure Pin

**What:** Wire four components into a closed loop using `connect()` + additional pressure constraint + `compose()` + `mtkcompile()`.

**When to use:** Assembling any complete closed hydraulic loop where all ports are connected (no dangling ports).

**Critical issue — pressure gauge freedom:** A fully-connected closed loop has no absolute pressure reference. MTK will report a structural singularity (underdetermined system) without an explicit pressure pin. The fix is to add an equation `pump.inlet.P ~ 1.0e5` to the equation list before calling `compose()`.

```julia
# Source: MTK v11 connect()/compose() pattern established in Phase 2
@named pump    = Pump(dP_pump = 3.0e4)
@named fr      = Friction(L = 0.3, D = 0.01, A = 7.85e-5)
@named ch      = Channel(n = 10, L = 0.6, D = 0.01, A = 7.85e-5)

# Thermal boundary: create a ThermalPort source or set Q_wall as a parameter
# Option: add a heat source component, or directly constrain thermal.T and thermal.Q_flow
# Simplest: add equations that set Q_wall = 1e4 at the channel thermal port
#   ch.thermal.Q_flow ~ 1.0e4   (in the top-level compose equations)

connections = [
    connect(pump.outlet, fr.inlet),
    connect(fr.outlet, ch.inlet),
    connect(ch.outlet, pump.inlet),
    pump.inlet.P ~ 1.0e5,    # pressure gauge freedom fix
    ch.thermal.Q_flow ~ 1.0e4, # wall heat input (10 kW)
]

@named sys = compose(System(connections, t; name=:sys), pump, fr, ch)
ssys = mtkcompile(sys)  # fully_determined=true (default) should work now
```

**Note:** The `ch.thermal.T` variable is left unconstrained by `connect()` — the Channel uses `thermal.Q_flow` as input and `thermal.T` appears in the HTC equation as wall temperature. For Phase 3 (uniform heat flux, not wall-temperature coupling), the simplest approach is to pin `ch.thermal.T ~ some_value` (e.g., 373.15 K) so the equation count closes, OR restructure the Channel to make thermal.T an observable computed from the HTC equation. This is a discretion area — the planner should attempt the simplest closure first and fall back to a two-port thermal setup if mtkcompile rejects it.

### Pattern 2: SteadyStateProblem with SSRootfind(KINSOL())

**What:** Solve the compiled MTK system for steady state by driving all `dT/dt` terms to zero.

**When to use:** Any steady-state solve on a compiled MTK system.

```julia
# Source: DifferentialEquations v7 + ModelingToolkit v11 confirmed interface
# op = operating point: combined u0 + parameter overrides
op = [
    ch.T[1] => 313.15 + 5.0,   # initial guess: T slightly above inlet per cell
    ch.T[2] => 313.15 + 10.0,
    # ... (steady_state_guess generates this)
    pump.inlet.P => 1.0e5,
]
prob = SteadyStateProblem(ssys, op)
sol = solve(prob, SSRootfind(KINSOL()))

# Access results via symbolic indexing
T_outlet = sol[ch.T_out]
mdot     = sol[pump.inlet.mdot]
```

### Pattern 3: ODEProblem + IDA for Transient

**What:** Simulate the DAE system over time using Sundials IDA.

**When to use:** Any transient simulation of the compiled MTK loop.

```julia
# Source: DifferentialEquations v7 + ModelingToolkit v11
tspan = (0.0, 60.0)
prob = ODEProblem(ssys, op, tspan)

# Step change: Q_wall: 1e4 → 2e4 at t=10s
# PresetTimeCallback fires at t=10, uses setp to modify Q_wall parameter
Q_wall_setter = setp(ssys, ch.thermal.Q_flow)  # or the parameter version
step_cb = PresetTimeCallback([10.0], integrator -> Q_wall_setter(integrator, 2.0e4))

sol = solve(prob, IDA(); callback = step_cb)

# Time-series access
T_outlet_ts = sol[ch.T_out, :]   # T_out at all time points
```

**Note on step change approach:** The `PresetTimeCallback` + `setp` pattern works when `Q_wall` is a free parameter in the compiled system. If `ch.thermal.Q_flow` was hard-wired as a literal equation in the connection list rather than as a parameter, `setp` cannot modify it at runtime. The planner must decide: (a) make `Q_wall` a `@parameters Q_wall` in the top-level system and refer to it in the connection equation `ch.thermal.Q_flow ~ Q_wall`, or (b) use a time-dependent function approach where `Q_wall(t) = t < 10 ? 1e4 : 2e4`. Both are valid; option (a) is cleaner for `PresetTimeCallback`; option (b) avoids the callback entirely.

### Pattern 4: steady_state_guess Helper

**What:** Physics-based initial guess for steady-state solver.

```julia
# Based on Python STREAM's symmetric_plate_steady_state pattern
function steady_state_guess(; T_inlet, Q_wall, mdot_guess, n)
    cp = cp_water(T_inlet)
    T_cells = [T_inlet + i * Q_wall / (n * mdot_guess * cp) for i in 1:n]
    return T_cells, mdot_guess
end
```

### Anti-Patterns to Avoid

- **`fully_determined=false` on the closed loop**: Only correct for isolated components in Phase 2. The closed loop MUST compile with `fully_determined=true` (the default). If it fails, the issue is an unresolved gauge freedom or missing equation, not a "use `fully_determined=false` as a workaround" situation.
- **Separate u0 + p arguments to problem constructors**: MTK v11's primary interface is the `op` (operating point) pattern — a single `Vector{Pair}` containing both initial conditions and parameter values. The old `(u0, p)` two-argument form is marked deprecated in `ModelingToolkitBase/src/deprecations.jl` (confirmed by inspection). Use `SteadyStateProblem(ssys, op)` and `ODEProblem(ssys, op, tspan)`.
- **`using ModelingToolkit` to access `SSRootfind`**: `SSRootfind` is NOT exported by ModelingToolkit — it lives in `DifferentialEquations` / `SteadyStateDiffEq`. Always `using DifferentialEquations` (or `using SteadyStateDiffEq`) in `src/solvers.jl`.
- **Attempting to index MTK solution with string keys**: Use symbolic indexing (`sol[sys.channel.T_out]`), not string-based access. MTK symbolic indexing is the v11 standard.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Nonlinear algebraic solve for steady state | Custom Newton iteration | `SSRootfind(KINSOL())` | KINSOL has line search, scaling, and dense/sparse Jacobian — handles the stiff nonlinear fluid property functions |
| DAE integration | Custom BDF/trapezoidal scheme | `IDA()` from Sundials | IDA is variable-order BDF with consistent initial condition computation — exactly what Python STREAM uses (same library, different binding) |
| Symbolic result indexing | Custom variable-name-to-index mapping | MTK symbolic indexing (`sol[sym]`) | MTK maintains the symbol-to-state mapping; any custom mapping will be fragile to `mtkcompile` equation reordering |
| Step change at a fixed time | Manual time-split + restart | `PresetTimeCallback` + `setp` | Single-problem approach, no state copying, callback is zero-overhead between events |

**Key insight:** Every Python STREAM solver concept has a direct MTK/SciML counterpart — `scipy.optimize.root` → `SSRootfind(KINSOL())`, `scikits.odes.dae("ida")` → `IDA()`, Python `aggregator.save()` state naming → MTK symbolic indexing. There is nothing to hand-roll.

---

## Common Pitfalls

### Pitfall 1: Thermal Port Equation Count Mismatch
**What goes wrong:** `mtkcompile` reports an overdetermined or underdetermined system involving `ch.thermal.T` and `ch.thermal.Q_flow`.
**Why it happens:** The Channel has a `ThermalPort` with two variables (`T` and `Q_flow`). `connect()` handles FlowPorts but ThermalPort is not connected to anything in the 3-component loop (no solid heat source component). So both `thermal.T` and `thermal.Q_flow` are free variables. The energy balance uses both, leaving the system underdetermined unless constraints are added.
**How to avoid:** In the loop assembly equations, add explicit constraints for the ThermalPort: `ch.thermal.Q_flow ~ Q_wall` (the total wall heat, treated as a fixed parameter) and either `ch.thermal.T ~ T_wall` (if you want to specify wall temperature) or restructure Channel's HTC equation to not require wall temperature (use Q_flow directly in the energy balance). **The Phase 2 Channel equation `h_tc[i] * (π * Dh) * dz * (thermal.T - T[i])` requires `thermal.T` as a wall temperature input** — so for uniform heat flux, the planner must either pin `thermal.T` to a sensible estimate or switch to using `q_wall[i] ~ thermal.Q_flow / n` directly in the energy balance (bypassing HTC). This is the single most complex integration decision.
**Warning signs:** `mtkcompile` error message mentioning `thermal₊T` or `thermal₊Q_flow`, or equation count mismatch.

### Pitfall 2: Pressure Gauge Freedom
**What goes wrong:** `mtkcompile` reports the system is structurally singular or underdetermined.
**Why it happens:** In a fully-closed loop, all pressures are defined relative to each other through pressure-drop equations. There is no absolute pressure anchor. MTK cannot determine the gauge level.
**How to avoid:** Add one absolute pressure pin to the connection equations: `pump.inlet.P ~ 1.0e5`. This is analogous to Python STREAM's approach of fixing an absolute pressure in the aggregator.
**Warning signs:** "structural singularity" or "n_equations ≠ n_unknowns" in `mtkcompile` output.

### Pitfall 3: Temperature Scale Mismatch (Kelvin vs Celsius)
**What goes wrong:** Python STREAM reference values differ from Julia results by ~273 K or produce nonsensical fluid properties.
**Why it happens:** Python STREAM's `light_water.py` functions take Celsius inputs. Julia-STREAM's `fluids.jl` functions take Kelvin. The validation reference script (`generate_reference.py`) must use Celsius (40°C for T_inlet), and the Julia code uses Kelvin (313.15 K). The `generate_reference.py` script must explicitly handle the conversion when comparing.
**How to avoid:** `T_inlet = 313.15 K` in Julia; `T_inlet = 40.0°C` in Python. Document this in `generate_reference.py` with an assertion that `313.15 - 273.15 == 40.0`.
**Warning signs:** T_outlet in Julia ~273 K above the Python value.

### Pitfall 4: ifelse() in Blasius Friction Causing Convergence Issues
**What goes wrong:** `SSRootfind(KINSOL())` fails to converge or gives wrong steady-state mass flow.
**Why it happens:** The Channel uses `abs(inlet.mdot)` in Re and friction factor — this has a non-smooth derivative at mdot=0. KINSOL uses Newton iteration with Jacobian — the non-differentiable point at mdot=0 can cause the Jacobian to be ill-conditioned near the initial guess.
**How to avoid:** Provide a physics-based initial guess (from `steady_state_guess`) that puts mdot far from zero (e.g., 0.1 kg/s). With a sensible starting point, the solver stays in the smooth region.
**Warning signs:** KINSOL reporting "maximum iterations exceeded" or convergence to mdot=0.

### Pitfall 5: op Dict Key Must Use Compiled System Symbols
**What goes wrong:** `SteadyStateProblem(ssys, op)` throws a key-not-found or wrong-type error.
**Why it happens:** After `mtkcompile`, the symbolic variables are renamed with subsystem prefixes (e.g., `sys.channel.T[1]` becomes `sys₊channel₊T[1]` in the compiled system). The `op` dict must use symbols from the **compiled** system (`ssys`), not from the pre-compile `sys`.
**How to avoid:** Use `ssys.channel.T[1]` (accessing via the compiled system's property accessor) rather than constructing symbol names manually. Alternatively, use `ModelingToolkit.defaults(ssys)` to verify what symbols are available.
**Warning signs:** `KeyError` or `ArgumentError` when building `SteadyStateProblem`.

### Pitfall 6: Channel `thermal.T` Used in Dittus-Boelter HTC
**What goes wrong:** The energy balance `Dt(T[i]) ~ ... + h_tc[i] * (π * Dh) * dz * (thermal.T - T[i]) / ...` requires a wall temperature input. In a heat-flux-driven scenario (Q_wall fixed), `thermal.T` becomes a free variable.
**Why it happens:** The Channel component was designed with Dittus-Boelter HTC for the standard `Channel + FuelPin` coupling. For Phase 3's simpler "fixed heat flux" scenario, the wall temperature is not prescribed externally.
**How to avoid:** Add a thermal boundary condition. The simplest approach is to add an equation `ch.thermal.T ~ 373.15` (100°C wall assumption) alongside `ch.thermal.Q_flow ~ Q_wall`. Alternatively, the planner may want to explore whether the HTC formulation needs the wall temperature at all if Q_flow is the given input — but this would require modifying the Channel component, which is out of scope for Phase 3. **Recommend: pin thermal.T = a_guess and set thermal.Q_flow = Q_wall.**

---

## Code Examples

### Confirmed: SteadyStateProblem API (MTK v11 + DifferentialEquations v7)
```julia
# Source: verified by method inspection - ModelingToolkitBase none:0 primary method
# SteadyStateProblem(sys::System, op; check_length, check_compatibility, ...)
# where op is a Vector{Pair} containing both u0 and parameter overrides

prob = SteadyStateProblem(ssys, [
    ssys.channel.T[1] => 315.0,
    ssys.channel.T[2] => 317.0,
    # ... all state variables need initial values
    ssys.pump.inlet.P => 1.0e5,  # if P is a state/observable
])
sol = solve(prob, SSRootfind(KINSOL()))
```

### Confirmed: SSRootfind(KINSOL()) construction
```julia
# Source: verified by REPL - typeof(SSRootfind(KINSOL())) == SSRootfind{KINSOL{:Dense}}
using DifferentialEquations, Sundials
alg = SSRootfind(KINSOL())
```

### Confirmed: ODEProblem + IDA
```julia
# Source: verified isdefined(DifferentialEquations, :IDA) == true
prob = ODEProblem(ssys, op, (0.0, 60.0))
sol = solve(prob, IDA())
```

### Confirmed: PresetTimeCallback for step change
```julia
# Source: verified isdefined(DifferentialEquations, :PresetTimeCallback) == true
# and isdefined(ModelingToolkit, :setp) == true
using DifferentialEquations, ModelingToolkit
Q_setter = setp(ssys, Q_wall_param)  # Q_wall_param must be a @parameters symbol
cb = PresetTimeCallback([10.0], integrator -> Q_setter(integrator, 2.0e4))
sol = solve(prob, IDA(); callback = cb)
```

### Python STREAM Reference Script Pattern
```python
# test/generate_reference.py
# IMPORTANT: Python STREAM uses Celsius; Julia-STREAM uses Kelvin
# T_inlet = 40.0°C  ↔  313.15 K

import numpy as np
from stream.substances.light_water import light_water
# ... instantiate Channel, Friction, Pump calculations ...
# ... set up Aggregator with Kirchhoff constraints ...
# ... call agr.solve_steady(y0) ...
# ... print T_outlet (Celsius) and mdot ...
print(f"T_outlet_celsius = {T_outlet}")
print(f"mdot = {mdot}")
# Convert for comparison: T_outlet_kelvin = T_outlet + 273.15
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ODEProblem(sys, u0, tspan, p)` separate u0/p | `ODEProblem(sys, op, tspan)` unified operating point | MTK v11 (confirmed by deprecations.jl) | All problem constructors use single `op` dict; old form still works but generates deprecation warnings |
| `mtkcompile(sys; fully_determined=false)` for all tests | `mtkcompile(sys; fully_determined=false)` only for isolated components; closed loop uses default `fully_determined=true` | MTK design — Phase 2 pattern is correct for isolated; Phase 3 requires fully determined | Must add all missing equations before calling mtkcompile on closed loop |

**Deprecated/outdated:**
- `SteadyStateProblem(sys, u0, p)` three-argument form: still works but deprecated in ModelingToolkitBase — prefer `SteadyStateProblem(sys, op)`.

---

## Open Questions

1. **ThermalPort closure for fixed-Q_wall scenario**
   - What we know: Channel's HTC equation uses `thermal.T` (wall temperature) in `Dt(T[i]) ~ ... h_tc[i] * (π * Dh) * dz * (thermal.T - T[i]) / ...`. For Phase 3, only `Q_wall` is prescribed, not wall temperature.
   - What's unclear: Does MTK allow `thermal.T` to be determined algebraically from the HTC equation + known Q_flow, or must it be explicitly constrained externally?
   - Recommendation: Add `ch.thermal.T ~ 373.15` as a fixed boundary in the connection equations (simplest). If this over-constrains the system, restructure to use `thermal.Q_flow` directly in the energy balance by replacing `h_tc[i] * (π * Dh) * dz * (thermal.T - T[i])` with `thermal.Q_flow / n`.

2. **Q_wall as parameter vs. equation literal for transient step change**
   - What we know: `setp` requires the target to be a declared `@parameters` symbol. If Q_wall is hard-wired as `1.0e4` in the connection equation literal, it cannot be modified at runtime.
   - What's unclear: Whether the planner prefers `@parameters Q_wall` in the top-level system or a time-dependent lambda approach.
   - Recommendation: Use `@parameters Q_wall = 1.0e4` in the top-level `System()` call, reference it in `ch.thermal.Q_flow ~ Q_wall`, and modify with `setp` in the callback. Alternatively, pass `Q_wall(t) = t < 10.0 ? 1.0e4 : 2.0e4` as a Julia function in the ODEProblem's `p` argument — this eliminates the callback entirely but requires MTK parameter-as-function support (less standard).

3. **Gravity component inclusion**
   - What we know: Gravity was built and tested in Phase 2. The reference topology is Pump → Friction → Channel → Pump (no Gravity in the 3-component baseline).
   - What's unclear: Whether Phase 3 should include Gravity to make the loop physically complete.
   - Recommendation: Omit Gravity from the Phase 3 reference loop (horizontal loop assumption). The CONTEXT.md states the reference topology as 3 components.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (no version — built-in) |
| Config file | `Project.toml` `[extras]` + `[targets]` sections already configured |
| Quick run command | `julia --project -e "using Pkg; Pkg.test()"` |
| Full suite command | `julia --project -e "using Pkg; Pkg.test()"` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SYS-01 | Closed loop assembles and compiles without error | unit/smoke | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 (add to runtests.jl) |
| SYS-02 | `solve_steady(sys, op)` returns a solution object | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 |
| SOLV-01 | Steady-state returns T per cell and mass flow as symbolic-indexable values | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 |
| SOLV-02 | Transient returns time-series; T_outlet increases after power step | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 |
| VAL-01 | T_outlet and mdot within 1% of Python STREAM reference | comparison | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 (after generate_reference.py runs) |
| VAL-02 | T_outlet at t=60s > T_outlet at t=0 after power step | qualitative | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 |
| VAL-03 | Full test suite runs automatically | integration | `julia --project -e "using Pkg; Pkg.test()"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project -e "using Pkg; Pkg.test()"` (all tests, ~30 seconds including JIT)
- **Per wave merge:** same command
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — append `@testset "STREAM Phase 3 Tests"` block (file exists, needs new content)
- [ ] `test/generate_reference.py` — create Python reference script; run once manually to get hardcoded values
- [ ] `src/solvers.jl` — create with `solve_steady`, `solve_transient`, `steady_state_guess`
- [ ] `src/STREAM.jl` — add `include("solvers.jl")` and export new functions

---

## Sources

### Primary (HIGH confidence)
- REPL verification (julia --project): `isdefined(DifferentialEquations, :SSRootfind)`, `isdefined(DifferentialEquations, :IDA)`, `typeof(SSRootfind(KINSOL()))`, `isdefined(DifferentialEquations, :PresetTimeCallback)`, `isdefined(ModelingToolkit, :setp)` — all confirmed true
- `methods(SteadyStateProblem)` REPL output — confirmed `SteadyStateProblem(sys::System, op; ...)` primary method in ModelingToolkitBase
- `methods(ODEProblem)` REPL output — confirmed `ODEProblem(sys::System, op, tspan; ...)` primary method; old `(u0, p)` form in `deprecations.jl`
- Installed package versions: MTK 11.15.0, DifferentialEquations 7.17.0, Sundials 5.1.0, Symbolics 7.15.3
- `/home/itay/projects/Julia-STREAM/src/components.jl` — direct inspection of Channel, Pump, Friction, Gravity implementations
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — Phase 1+2 test patterns to continue

### Secondary (MEDIUM confidence)
- Python STREAM `stream/solvers.py` — `algebraic()` uses `scipy.optimize.root` (→ analogous to `SSRootfind`); `differential_algebraic()` uses `scikits.odes.dae("ida")` (→ analogous to `IDA()`)
- Python STREAM `stream/aggregator/aggregator.py` — `solve_steady` pattern; state naming via `agr.save(sol)`
- Python STREAM `stream/calculations/channel.py` — confirms Celsius temperature convention; `ChannelVar.tout` is the outlet temperature key

### Tertiary (LOW confidence)
- MTK documentation on callback/setp pattern for time-varying parameters — inferred from `isdefined` check and SciML ecosystem conventions; exact API for `setp` with MTK compiled systems not directly tested

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all key library methods verified by REPL introspection on installed versions
- Architecture: HIGH — MTK assembly patterns established in Phase 2; SteadyStateProblem/ODEProblem methods confirmed
- Pitfalls: HIGH for ThermalPort/pressure issues (directly derived from component code); MEDIUM for solver convergence pitfalls (based on physics + ecosystem experience)
- Validation architecture: HIGH — test infrastructure already exists; only additions needed

**Research date:** 2026-03-12
**Valid until:** 2026-04-12 (30 days — MTK v11 is stable; DiffEq v7 API is stable)
