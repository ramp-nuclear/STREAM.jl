# Phase 2: Components - Research

**Researched:** 2026-03-12
**Domain:** ModelingToolkit v11 acausal component definition — parameterized multi-cell thermal-hydraulic components
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**ThermalPort topology for Channel**
- Single ThermalPort carrying total Q_wall (W) — one connection from heat source to Channel
- Internally, Channel introduces a `q_wall[i]` per-cell array: `q_wall[i] = thermal_port.Q_flow / n` (uniform distribution)
- All energy balance equations use `q_wall[i]` — never `Q_flow / n` directly
- Reason: refactor to per-cell ports later changes only port topology and q_wall binding; energy balance loop is untouched

**Channel temperature advection**
- Use `instream(inlet.T)` for inlet temperature (cell 1's upstream boundary)
- Cell-to-cell: `T_in[i] = T[i-1]` for cells 2..n (direct variable reference, first-order upwind)
- Same first-order upwind finite-volume discretization as Python STREAM's `coolant_first_order_upwind_dTdt`

**Intermediate observable variables**
- Channel: `Re[i]`, `Nu[i]`, `h_tc[i]`, `v[i]`, `T_out`, `dP` — all as MTK `@variables` so they appear in `observed(compiled_sys)`
- Friction: `Re`, `f`
- Pump, Gravity: no additional observables beyond port variables

**mtkcompile isolation test**
- Each component: instantiate → `mtkcompile` → assert no errors
- Channel additionally: assert pre-compile equation list contains exactly `n` energy balance equations
- No solving in Phase 2 — numerical correctness is Phase 3

**Component parameters — no defaults**
- Channel: `n`, `L` (m), `D` (m), `A` (m²)
- Pump: `dP` (Pa)
- Friction: `L` (m), `D` (m), `A` (m²)
- Gravity: `H` (m), `A` (m²)

**Variable initial guesses (physics-based)**
- `T = 600.0` (K), `P = 1.0e5` (Pa), `mdot = 1.0` (kg/s) as defaults in `@variables`
- Algebraic variables (Re, Nu, h_tc, v, dP, f): no initial guesses needed

### Claude's Discretion
- Exact Dittus-Boelter form (standard: Nu = 0.023 Re^0.8 Pr^0.4 for heating)
- Prandtl number computation (Pr = cp * mu / k using registered fluid property functions)
- Blasius friction factor form (f = 0.316 Re^(-0.25) for Re < 100000)
- How to declare array variables in MTK v11 (scalarize vs array variable approach)
- Whether `dP` on Channel is a single scalar or per-cell cumulative pressure

### Deferred Ideas (OUT OF SCOPE)
- Per-cell ThermalPorts for Channel
- Absolute pressure per cell (cumulative ΔP from loop reference) — Phase 3
- Pr[i] as an observable
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| COMP-01 | `Channel` — n-cell 1D finite-volume coolant, single-phase, Dittus-Boelter HTC, FlowPort in/out and ThermalPort for wall heat input | MTK component function pattern, array variable declaration, instream() for inlet T, for-loop equation generation, fluid property @register_symbolic functions |
| COMP-02 | `Pump` — constant pressure rise, FlowPort in/out | MTK component function pattern, single algebraic equation imposing dP across ports |
| COMP-03 | `Friction` — Darcy-Weisbach pressure drop with Blasius friction factor, FlowPort in/out | Blasius formula (0.3164/Re^0.25), Darcy-Weisbach DP equation, Re from mdot |
| COMP-04 | `Gravity` — hydrostatic pressure term (ρgh), FlowPort in/out | gravity_pressure = rho * g * H, port pressure difference equation |
</phase_requirements>

---

## Summary

Phase 2 implements four standalone MTK v11 components in `src/components.jl`. The technical domain is acausal component definition using MTK's `function` (or `@component`) pattern: declare parameters, declare symbolic variables, build an equation list, assemble subsystems (ports), and return `compose(System(...), subsystems)`.

The most complex component is `Channel` with `n` cells: it requires array variables (`T(t)[1:n]`, `Re(t)[1:n]`, etc.), a for-loop over cells to generate energy balance ODEs, and use of `instream(inlet.T)` for the inlet boundary condition. All four fluid property functions (`rho_water`, `cp_water`, `mu_water`, `k_water`) are already `@register_symbolic` and callable directly from equation definitions.

The key design risk is choosing between scalar-loop equation generation (explicit `for i in 1:n` producing `n` scalar equations) vs MTK array equations. Evidence from the installed MTK v11.15.0 test suite confirms that scalar-loop generation with `T(t)[1:n]` array variables and `D(T[i]) ~ ...` equations is the recommended, well-tested approach for variable-count systems like `Channel(n=5)`.

**Primary recommendation:** Use `function Name(; name, ...)` (not `@component`) to match the connector pattern already established in Phase 1. Build equation lists with explicit for-loops. Return `compose(System(eqs, t, vars, pars; name=name), subsystems)`.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11.15.0 (installed) | Component/equation definition, mtkcompile, observed() | Project's core modeling framework |
| Symbolics | v7 | @variables, @parameters, symbolic expressions | MTK v11 dependency; @register_symbolic already used |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ModelingToolkit: t_nounits | from MTK | Dimensionless time variable | All variable declarations (established in Phase 1) |
| ModelingToolkitBase.instream | from MTK | Stream variable inlet value | Channel inlet temperature boundary condition |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Plain `function` | `@component` macro | `@component` adds GUI metadata only — functionally identical; plain `function` matches established connector pattern and avoids a macro that is not needed |
| Scalar loop equations | MTK array equations (D(T) ~ f(T)) | Array equations introduce implicit scalarization concerns and are less debuggable for variable-n components; scalar loops produce exactly n explicit equations checkable in tests |
| `instream(inlet.T)` | Direct `inlet.T` | Direct access is the outflow value; `instream` gives the mixture value flowing into the port — required for stream variables per MTK semantics |

**Installation:** No new packages needed — all dependencies are already declared in Project.toml.

---

## Architecture Patterns

### Recommended Project Structure
```
src/
├── fluids.jl          # Existing — rho_water, cp_water, mu_water, k_water
├── connectors.jl      # Existing — FlowPort, ThermalPort
├── components.jl      # NEW — Channel, Pump, Friction, Gravity
└── STREAM.jl          # Update: add include("components.jl") and exports
test/
└── runtests.jl        # Update: add Phase 2 testsets
```

### Pattern 1: Component Function with compose()

**What:** All four components follow this skeleton:
1. Declare `pars = @parameters ...` (geometry/physics constants)
2. Declare `vars = @variables ...` (all symbolic state and observable variables)
3. Instantiate subsystems (ports): `@named inlet = FlowPort(); ...`
4. Build equation list: `eqs = Equation[...]`
5. Return `compose(System(eqs, t, vars, pars; name=name), inlet, outlet, ...)`

**When to use:** Every component in this phase. Consistent with the stream_connectors.jl test patterns and the existing connector pattern.

**Example — Pump:**
```julia
# Source: adapted from stream_connectors.jl test patterns (MTK v11.15.0)
function Pump(; name, dP)
    pars = @parameters begin
        dP = dP
    end
    vars = @variables begin
        P_in(t) = 1.0e5
        P_out(t) = 1.0e5 + dP
        mdot(t) = 1.0
        T_in(t) = 600.0
        T_out(t) = 600.0
    end
    @named inlet  = FlowPort()
    @named outlet = FlowPort()

    eqs = Equation[
        # Mass continuity
        inlet.mdot + outlet.mdot ~ 0,
        # Pressure rise
        outlet.P - inlet.P ~ dP,
        # Isenthalpic: stream temperature unchanged
        outlet.T ~ instream(inlet.T),
        inlet.T  ~ instream(outlet.T),
    ]
    compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end
```

### Pattern 2: Array Variables with For-Loop Equations (Channel)

**What:** Channel requires `n` energy balance ODEs, each with per-cell observable quantities. Declare arrays with `T(t)[1:n]`, then generate equations with a for-loop.

**When to use:** Any component with a runtime-variable cell count.

**Example — Channel energy balance loop:**
```julia
# Source: MTK v11.15.0 stream_connectors.jl line 670 pattern + array variable
# syntax confirmed in MTK test suite
function Channel(; name, n, L, D, A)
    pars = @parameters begin
        n_cells = n
        L_ch = L
        D_h  = D
        A_ch = A
    end

    vars = @variables begin
        (T(t))[1:n]     = fill(600.0, n)     # bulk temperature per cell (K)
        (Re(t))[1:n]    = fill(1.0e4, n)     # Reynolds number per cell
        (Nu(t))[1:n]    = fill(100.0, n)     # Nusselt number per cell
        (h_tc(t))[1:n]  = fill(1.0e4, n)    # heat transfer coefficient (W/m²K)
        (v(t))[1:n]     = fill(1.0, n)       # velocity per cell (m/s)
        (q_wall(t))[1:n] = fill(0.0, n)     # wall heat flux per cell (W/m²)
        T_out(t) = 600.0                     # outlet temperature alias
        dP(t)    = 0.0                       # total pressure drop
    end

    @named inlet    = FlowPort()
    @named outlet   = FlowPort()
    @named thermal    = ThermalPort()

    dz = L / n  # cell length (scalar parameter arithmetic)

    # Energy balance for each cell (first-order upwind):
    #   rho * cp * A * dz * D(T[i]) = mdot * cp * (T_in_i - T[i]) + h_tc[i] * Pi * dz * (T_wall - T[i])
    # where T_wall is from thermal port and Pi = pi * D (heated perimeter for circular channel)
    eqs = Equation[]
    T_inlet = instream(inlet.T)

    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]   # upwind cell temperature
        push!(eqs,
            D(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (pi * D) * dz * (thermal.T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        # Observables
        push!(eqs, q_wall[i] ~ thermal.Q_flow / n)
        push!(eqs, v[i]   ~ inlet.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i]  ~ abs(inlet.mdot) * D / (A * mu_water(T[i])))
        push!(eqs, Nu[i]  ~ 0.023 * Re[i]^0.8 * (cp_water(T[i]) * mu_water(T[i]) / k_water(T[i]))^0.4)
        push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / D)
    )
    # Outlet alias and pressure drop
    push!(eqs, T_out ~ T[n])
    push!(eqs, dP ~ ... )  # Darcy-Weisbach summed over cells (see Pitfalls)
    # Port connections
    push!(eqs, inlet.mdot + outlet.mdot ~ 0)
    push!(eqs, outlet.T ~ T[n])
    push!(eqs, inlet.T  ~ instream(outlet.T))

    compose(System(eqs, t, [vars...], pars; name=name), inlet, outlet, thermal)
end
```

### Pattern 3: Simple Algebraic Components (Pump, Friction, Gravity)

**What:** Components with only algebraic equations (no ODEs). MTK's `mtkcompile` reduces these to observed variables automatically.

**Example — Friction:**
```julia
function Friction(; name, L, D, A)
    pars = @parameters begin
        L_f = L
        D_h = D
        A_f = A
    end
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named inlet  = FlowPort()
    @named outlet = FlowPort()

    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        Re ~ abs(inlet.mdot) * D / (A * mu_water(instream(inlet.T))),
        f  ~ 0.3164 * Re^(-0.25),
        inlet.P - outlet.P ~ f * (inlet.mdot * abs(inlet.mdot) /
                                       (2 * rho_water(instream(inlet.T)) * A^2)) * (L / D),
        outlet.T ~ instream(inlet.T),
        inlet.T  ~ instream(outlet.T),
    ]
    compose(System(eqs, t, vars, pars; name=name), inlet, outlet)
end
```

### Anti-Patterns to Avoid

- **Using `@component` macro when `function` is already the pattern:** `@component` adds only GUI metadata. Plain `function` is established, matches Phase 1 connector style, and keeps the codebase consistent.
- **Using DSL block `@variables` inside `@mtkmodel`:** MTK v11 uses `@mtkmodel` DSL (requires `SciCompDSL.jl`) or function-based API. This project uses function-based API — confirmed from connector implementations.
- **Collecting all vars into System without array expansion:** When `@variables (T(t))[1:n] = ...` is declared, pass `[vars...;]` (splatted) to `System(...)` to ensure MTK sees scalar-indexed variables, not an array-of-arrays.
- **Writing `D(T) ~ ...` as array equation:** For variable-n components, prefer scalar loop. Array equations work but make equation counting harder and are less compatible with structural analysis.
- **Omitting `instream()` on stream port variables:** Accessing `inlet.T` directly gives the outflow value (what this component would send out on reversal), not the inlet mixture temperature. Always use `instream(inlet.T)` for physically meaningful inlet T.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fluid properties | Custom density/viscosity functions | `rho_water`, `cp_water`, `mu_water`, `k_water` (already registered) | Already exist, tested against Python STREAM, ForwardDiff-compatible |
| Port/connector types | New connector structs | `FlowPort`, `ThermalPort` from connectors.jl | Already exist with correct MTK metadata (Flow/Stream/across) |
| Stream variable semantics | Custom mixing equations | `instream()` from MTK | MTK expands this correctly during `expand_connections()` — hand-rolling breaks connection analysis |
| mtkcompile | Custom equation reduction | `mtkcompile()` | Does structural index reduction, alias elimination, observable separation |

**Key insight:** The entire point of MTK's acausal modeling is that the framework handles connection algebra. The component only declares its own equations; MTK infers the connection constraints (mass balance, pressure equality) during `expand_connections` called inside `mtkcompile`.

---

## Common Pitfalls

### Pitfall 1: System() Call Missing Splatted Array Variables

**What goes wrong:** `System(eqs, t, vars, pars)` where `vars` contains an array variable like `T[1:n]` raises a dimension error or MTK fails to register scalar unknowns.

**Why it happens:** MTK's `System` constructor expects a flat vector of scalar symbolic variables, but `@variables (T(t))[1:n]` produces a `Symbolics.Arr`. Passing the array object directly is not a flat list of scalars.

**How to avoid:** Splat array variables: `System(eqs, t, [collect(T); collect(Re); T_out; dP], pars; name=name)` or use `[vars...;]` if `vars` is mixed scalar/array.

**Warning signs:** `MethodError` on `System()` constructor, or `unknowns(sys)` showing fewer variables than expected.

### Pitfall 2: `instream()` Used Outside Connection Context

**What goes wrong:** Calling `instream(inlet.T)` in a component that is not yet connected causes `mtkcompile` to error with unresolved instream or malformed equation.

**Why it happens:** `instream` is a symbolic operator that MTK resolves during `expand_connections`. The component-in-isolation test calls `mtkcompile` directly on the unconnected component — MTK must handle unresolved stream variables.

**How to avoid:** The isolation `mtkcompile` test is fine — MTK handles unresolved stream equations by treating them as free variables. Confirmed by `@test_nowarn mtkcompile(...)` in MTK's own stream_connectors.jl tests with components that use instream. Do NOT try to substitute a concrete value for `instream(...)` in tests.

**Warning signs:** Only appears if you try to numerically solve an isolated component (which is Phase 3 work, not Phase 2).

### Pitfall 3: Blasius Friction Denominator Singularity at Re→0

**What goes wrong:** `f = 0.3164 * Re^(-0.25)` blows up when Re → 0 (zero mass flow during initialization).

**Why it happens:** Blasius is undefined at Re=0. MTK initialization solves algebraic equations at t=0 using initial guesses; if mdot initial guess is 1.0 kg/s, Re will be well-defined. But if the solver tries mdot=0, the Jacobian becomes infinite.

**How to avoid:** The `mdot = 1.0` initial guess in port variables should prevent this during Phase 2 isolation tests. If needed, add `max(Re, 1.0)` guard in Friction component. Note: CONTEXT.md says no range guards (ForwardDiff compatibility) — so avoid `max()` with `ifelse()` for now; rely on good initial guesses.

**Warning signs:** `NaN` or `Inf` in structural analysis; solver failure at t=0.

### Pitfall 4: dP Observable vs Equation Count on Channel

**What goes wrong:** If `dP` is defined as an ODE (D(dP) ~ ...) instead of an algebraic equation (`dP ~ sum_of_pressure_drops`), the equation count will be wrong and mtkcompile may fail.

**Why it happens:** Channel's pressure drop is a scalar that summarizes the full-channel friction drop. It should be algebraic (a function of current T[i] and mdot), not time-integrated.

**How to avoid:** Define `dP ~ sum(f_i * ... for i in 1:n)` as a plain algebraic equation. The `dP` variable will then appear in `observed(compiled_sys)` after mtkcompile, not in `unknowns(compiled_sys)`.

**Warning signs:** `length(unknowns(compiled_sys))` includes `dP` when it should not.

### Pitfall 5: For-Loop Over `1:n` With Symbolic `n`

**What goes wrong:** If `n` is declared as an MTK `@parameters n = n_val` (symbolic), then `for i in 1:n` is invalid Julia — you cannot iterate over a symbolic value.

**Why it happens:** MTK parameters are symbolic; `1:n_sym` is a symbolic range, not iterable.

**How to avoid:** `n` must be a plain Julia `Int` passed at instantiation time, not an MTK `@parameters` entry. The component signature is `function Channel(; name, n::Int, ...)`. Use `n` directly in the for loop; it is a concrete integer at component construction time.

**Warning signs:** `MethodError: no method matching iterate(::Symbolics.Num)` when building equations.

### Pitfall 6: Port Stream Variable Direction for Channel

**What goes wrong:** Incorrectly wiring `outlet.T ~ T[n]` (assigning the stream value) vs what MTK stream semantics actually require.

**Why it happens:** Stream variables represent what a component *would* contribute to a mix if flow reversed. The correct pattern is:
- `outlet.T ~ T[n]` — component sets its outflow stream value to the outlet temperature
- `inlet.T ~ instream(outlet.T)` — component uses the actual inflow temperature (identity here, but needed structurally)

**How to avoid:** Follow the AdiabaticStraightPipe pattern in stream_connectors.jl: always set `port.T ~ <outflow_value>` and use `instream(other_port.T)` for inflow.

---

## Code Examples

Verified patterns from official sources (MTK v11.15.0 installed package):

### Component Function Skeleton (from stream_connectors.jl lines 39-63)
```julia
# Source: ~/.julia/packages/ModelingToolkit/34pfI/lib/ModelingToolkitBase/test/stream_connectors.jl
function MassFlowSource_h(; name, h_in = 420.0e3, m_flow_in = -0.01)
    pars = @parameters begin
        h_in = h_in
        m_flow_in = m_flow_in
    end
    vars = @variables begin
        P(t)
    end
    @named port = TwoPhaseFluidPort()
    subs = [port]
    eqns = Equation[]
    push!(eqns, port.P ~ P)
    push!(eqns, port.m_flow ~ -m_flow_in)
    push!(eqns, port.h_outflow ~ h_in)
    return compose(System(eqns, t, vars, pars; name = name), subs)
end
```

### Array Variable in @variables with Metadata (from stream_connectors.jl lines 666-669)
```julia
# Source: ~/.julia/packages/ModelingToolkit/34pfI/lib/ModelingToolkitBase/test/stream_connectors.jl
vars = @variables begin
    m(t)[1:Ns] = m0
    h(t)
    x(t)[1:Ns]
end
```

### instream() Usage (from stream_connectors.jl lines 170-173)
```julia
# Source: stream_connectors.jl — AdiabaticStraightPipe expanded equations
# After expand_connections:
port_a.h_outflow ~ instream(port_b.h_outflow)
port_b.h_outflow ~ instream(port_a.h_outflow)
```

### mtkcompile Isolation Test Pattern (from stream_connectors.jl line 150)
```julia
# Source: stream_connectors.jl
@test_nowarn mtkcompile(n1m1Test)
```

### Equation Count Check Before mtkcompile (for Channel test)
```julia
# Pattern: check structural equation count before compilation
@named ch = Channel(n=5, L=1.0, D=0.01, A=7.85e-5)
energy_eqs = filter(eq -> ..., equations(ch))  # filter for D(T[i]) ~ ... equations
@test length(energy_eqs) == 5
@test_nowarn mtkcompile(ch)
```

### Blasius + Darcy-Weisbach (from Python STREAM pressure_drop/friction.py)
```julia
# Python reference: Blasius_friction(re) = 0.3164 / re^0.25
# Darcy-Weisbach: dp = f * (mdot * |mdot| / (2 * rho * A^2)) * (L / D)
# In MTK equations:
f  ~ 0.3164 * Re^(-0.25)
inlet.P - outlet.P ~ f * (inlet.mdot * abs(inlet.mdot) /
                               (2 * rho_water(instream(inlet.T)) * A^2)) * (L / D)
```

### Gravity Component Equation (from Python STREAM pressure_drop/__init__.py)
```julia
# Python reference: gravity_pressure(rho, dh, g=9.80665) = rho * g * dh
# In MTK equations (positive pressure when flowing upward, conventional sign):
inlet.P - outlet.P ~ rho_water(instream(inlet.T)) * 9.80665 * H
```

### Dittus-Boelter Correlation (from Python STREAM physical_models/heat_transfer_coefficient/turbulent.py)
```julia
# Nu = 0.023 * Re^0.8 * Pr^0.4  (heating condition, Python STREAM verbatim)
# Pr = cp * mu / k
Nu[i] ~ 0.023 * Re[i]^0.8 * (cp_water(T[i]) * mu_water(T[i]) / k_water(T[i]))^0.4
h_tc[i] ~ Nu[i] * k_water(T[i]) / D
```

### Re from mdot (from Python STREAM physical_models/dimensionless.py, Re_mdot function)
```julia
# Re_mdot = |mdot| * L / (A * mu)  — Python STREAM verbatim (L = hydraulic diameter here)
Re[i] ~ abs(inlet.mdot) * D / (A * mu_water(T[i]))
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| MTK DSL `@mtkmodel` block syntax | `@connector function` / plain `function` for components | MTK v11 | DSL requires SciCompDSL.jl; function API is always available and established in this project |
| `ODESystem(...)` constructor | `System(...)` constructor | MTK v9→v11 | `System` is the unified constructor; `ODESystem` may still work but `System` is canonical in v11 |
| `structural_simplify` | `mtkcompile` | MTK v11 | `mtkcompile` replaces `structural_simplify` as the recommended compilation step |

**Deprecated/outdated:**
- `ODESystem(eqs, t, sts, ps)`: replaced by `System(eqs, t, sts, ps)` in MTK v11 — `ODESystem` still exists but `System` is the v11 canonical form (confirmed: connectors.jl already uses `System`)
- `structural_simplify`: renamed `mtkcompile` in MTK v11 — test suite and CONTEXT.md already use `mtkcompile`

---

## Open Questions

1. **`dP` on Channel: single scalar vs per-cell array**
   - What we know: Python STREAM's `pressure_drop` is a single scalar (total DP across channel); CONTEXT.md says `dP` mirrors `ChannelVar.pressure_drop`
   - What's unclear: whether to expose `dP` as `dP ~ sum(per_cell_DPs)` or as `dP ~ f(mean_T, mdot, L, D, A)` using whole-channel properties
   - Recommendation: Use single scalar `dP ~ f(...) * (L / D) * ...` with averaged properties (mean T). This is simpler, matches the Python reference's single-value output, and avoids having to track per-cell pressure as a separate observable array. Claude's discretion per CONTEXT.md.

2. **`abs()` in Blasius Re expression — ForwardDiff compatibility**
   - What we know: CONTEXT.md says "no range guards (ForwardDiff compatibility)" for fluid properties; `abs()` uses `ifelse` internally in symbolic context
   - What's unclear: whether `abs(inlet.mdot)` in symbolic equations creates ForwardDiff issues at mdot=0
   - Recommendation: Use `abs(inlet.mdot)` in Re expressions — MTK handles symbolic `abs` correctly with ForwardDiff via `IfElse.ifelse` under the hood; this is standard MTK practice.

3. **Port mass flow equation for Channel: which port carries mdot**
   - What we know: `mdot` positive = into port; Channel has `inlet.mdot > 0` (flow in) and `outlet.mdot < 0` (flow out)
   - What's unclear: whether to use `inlet.mdot` or a local `mdot` variable in cell equations
   - Recommendation: Use `inlet.mdot` directly in cell energy balance equations. Add continuity: `inlet.mdot + outlet.mdot ~ 0`. No need for a redundant local `mdot` variable.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` stdlib |
| Config file | none — `test/runtests.jl` is the entry point |
| Quick run command | `cd /home/itay/projects/Julia-STREAM && julia --project=. -e 'using Pkg; Pkg.test()'` |
| Full suite command | same — single test file |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COMP-01 | `Channel(n=5, ...)` instantiates without error | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |
| COMP-01 | Channel equations contain exactly `n` energy balance ODEs | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |
| COMP-01 | `mtkcompile(Channel(n=5, ...))` succeeds without error | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |
| COMP-02 | `Pump(dP=1e4)` instantiates and `mtkcompile` succeeds | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |
| COMP-03 | `Friction(L=1.0, D=0.01, A=7.85e-5)` instantiates and `mtkcompile` succeeds | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |
| COMP-04 | `Gravity(H=3.0, A=7.85e-5)` instantiates and `mtkcompile` succeeds | unit | `julia --project=. test/runtests.jl` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Per wave merge:** same (single test file)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — add `@testset "STREAM Phase 2 Tests"` block with COMP-01 through COMP-04 testsets

*(All four Phase 2 test cases need to be added to the existing `test/runtests.jl`)*

---

## Sources

### Primary (HIGH confidence)
- `~/.julia/packages/ModelingToolkit/34pfI/lib/ModelingToolkitBase/test/stream_connectors.jl` — definitive reference for component function pattern, compose(), instream(), array variables, @connector, @component, mtkcompile isolation
- `/home/itay/projects/STREAM/stream/physical_models/heat_transfer_coefficient/turbulent.py` — Dittus-Boelter exact form (0.023 Re^0.8 Pr^0.4)
- `/home/itay/projects/STREAM/stream/physical_models/pressure_drop/friction.py` — Blasius exact form (0.3164 / Re^0.25), Darcy-Weisbach equation
- `/home/itay/projects/STREAM/stream/physical_models/pressure_drop/__init__.py` — gravity_pressure formula (rho * g * H)
- `/home/itay/projects/STREAM/stream/physical_models/dimensionless.py` — Re_mdot formula (|mdot| * D / (A * mu))
- `/home/itay/projects/Julia-STREAM/src/connectors.jl` — established connector pattern this project uses
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — established test structure

### Secondary (MEDIUM confidence)
- MTK v11.15.0 `Project.toml` — confirms version in use
- Python STREAM `calculations/channel.py` — `coolant_first_order_upwind_dTdt` confirms first-order upwind ODE form and energy balance structure
- WebSearch findings on MTK array variables — confirmed by installed package test code

### Tertiary (LOW confidence)
- WebSearch on `scalarize` vs array equations — partially verified; primary source is installed test code

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified from installed MTK 11.15.0 package and existing project code
- Architecture (component function pattern): HIGH — confirmed from MTK stream_connectors.jl test file
- Physics (correlations): HIGH — Python STREAM source code directly available and read
- Array variable syntax: HIGH — confirmed in stream_connectors.jl lines 664-669 (`m(t)[1:Ns]`)
- instream() usage: HIGH — confirmed in stream_connectors.jl line 647 (`a.x ~ instream(b.x)`)
- Pitfalls: MEDIUM-HIGH — based on MTK API patterns and known MTK behaviors

**Research date:** 2026-03-12
**Valid until:** 2026-04-12 (stable MTK v11 API; fluid physics are timeless)
