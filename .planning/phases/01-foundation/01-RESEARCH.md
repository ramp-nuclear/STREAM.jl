# Phase 1: Foundation - Research

**Researched:** 2026-03-12
**Domain:** Julia package scaffolding, ModelingToolkit v11 connectors, Symbolics.jl function registration, fluid property polynomials
**Confidence:** HIGH (core MTK API verified against official docs; reference values computed from Python STREAM source)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Fluid property source:** Port the Simantov correlations verbatim from Python STREAM's `light_water.py`. Same coefficients, same formulas. Temperature unit: Kelvin internally (convert to Celsius inside each function via `T_C = T_K - 273.15`).
- **No temperature range guards** — ForwardDiff calls these at arbitrary T during Jacobian evaluation; guards would break symbolic differentiation.
- **Fluid property scope:** Phase 1 registers only `rho_water(T)`, `cp_water(T)`, `mu_water(T)`, `k_water(T)`. β, T_sat, h_fg, σ, ρ_vapor are out of scope.
- **Package structure:** Submodules from the start: `src/STREAM.jl` (entry point) + `src/fluids.jl` + `src/connectors.jl`. Phase 2 adds `src/components.jl` without restructuring.
- **Export only public API:** `FlowPort`, `ThermalPort`, `rho_water`, `cp_water`, `mu_water`, `k_water`.
- **Fluid functions exported flat from STREAM** (no sub-module namespace in v0.1). Structure `fluids.jl` so future refactor to `module Fluids ... end` wrapper is trivial.
- **Function naming:** ASCII names: `rho_water`, `cp_water`, `mu_water`, `k_water`.
- **MTK version:** Target MTK v11.x (latest stable, currently v11.14.0). Pin to specific v11.x in Project.toml.
- **FlowPort variables:** `P(t)` (pressure, across), `mdot(t)` (mass flow, through/Flow), `T(t)` (temperature, Stream variable). Positive mass flow = into port (Kirchhoff convention).
- **ThermalPort variables:** `T(t)` (temperature, across), `Q_flow(t)` (heat flow in Watts, through/Flow).
- **Testing:** Substantive unit tests in `test/runtests.jl`. Fluid property spot-checks at 300 K, 350 K, 400 K. Connector instantiation tests. MTK smoke test calling `rho_water(T)` symbolically.

### Claude's Discretion

- Exact Project.toml version bounds for DifferentialEquations.jl and Sundials.jl
- Whether to use `@register_symbolic` macro or the newer MTK v11 equivalent if the API changed
- Internal helper functions within fluids.jl (e.g., Fahrenheit conversion needed by density formula)
- Test tolerance for fluid property numerical comparisons

### Deferred Ideas (OUT OF SCOPE)

- `STREAM.Fluids` sub-module namespace — post v0.1 refactor
- Additional fluid properties (β, T_sat, h_fg, σ, ρ_vapor) — v0.2
- Heavy water, sodium fluid properties — v2 (FLUID-01, FLUID-02)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOUND-01 | Julia package skeleton (Project.toml, src/, test/) with MTK, DifferentialEquations, Sundials as dependencies | Julia Pkg.generate standard pattern; Project.toml compat section documented |
| FOUND-02 | Light water fluid properties (ρ, cp, μ, k) as polynomial functions of T, registered via `@register_symbolic`, callable from any component without injection | `@register_symbolic` from Symbolics.jl must be called at module top-level; ForwardDiff compatibility confirmed when no guard branches present |
| CONN-01 | `FlowPort` connector with pressure (across), mass flow (through/Flow), and temperature (Stream) variables | `@connector` macro syntax verified; `[connect = Flow]` and `[connect = Stream]` metadata confirmed in current MTK docs; `instream()` behavior documented |
| CONN-02 | `ThermalPort` connector with temperature (across) and heat flow (through/Flow) variables | HeatPort pattern from ModelingToolkitStandardLibrary verified: T (across) + Q_flow (Flow); directly mirrors standard library design |
</phase_requirements>

---

## Summary

Phase 1 establishes a Julia package named `STREAM` with three deliverables: a valid package skeleton (Project.toml + src/ + test/), four registered fluid property functions for light water, and two MTK connectors (FlowPort and ThermalPort). All three are greenfield — no existing Julia code in the repository.

The core technical challenge is getting `@register_symbolic` right. This macro from Symbolics.jl must be called at the module top-level (not inside functions or `begin` blocks nested in functions). It treats the registered function as an opaque symbolic node, which is exactly what fluid properties need: MTK can form equations referencing `rho_water(T)` without needing to algebraically expand the polynomial. ForwardDiff-compatible Jacobians are computed by the underlying C Sundials library, not by symbolic differentiation of the polynomial, so no derivative registration is needed.

The connector design has one nuanced element: FlowPort's temperature variable is a stream variable (`[connect = Stream]`), not a plain across variable. This is the correct Modelica/MTK semantic for thermal advection — temperature follows mass flow direction (upwinding). Components consuming the upstream temperature must use `instream(port.T)` rather than `port.T` directly. There is a known open issue (#3416) where stream connector variables are not always accessible from the solution object after `mtkcompile`; the workaround is to define an observable local variable `T_in ~ instream(inlet.T)` inside the component, which then appears in the solved system.

**Primary recommendation:** Use `@connector` macro for both ports, `@register_symbolic` at module top-level for all four fluid functions, and `Pkg.generate("STREAM")` for the package skeleton. Follow ModelingToolkitStandardLibrary's HeatPort pattern verbatim for ThermalPort.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | v11.14.0 (pin `"11"` compat) | Acausal modeling, connector algebra, symbolic compilation | Required — the entire architecture is MTK-native |
| Symbolics.jl | v6.x (transitive via MTK) | `@register_symbolic` macro, symbolic variable definition | Provides the function registration mechanism |
| DifferentialEquations.jl | v7.x (see compat note) | High-level solver interface wrapping ODE/DAE solvers | Used in Phase 3; declare now as dependency |
| Sundials.jl | v5.1.0 (pin `"5"` compat) | IDA DAE solver for steady-state and transient | Required for Phase 3 validation; declare as dependency now |

**Compat note for discretion areas:**
- `DifferentialEquations = "7"` — v7.17 is current stable as of early 2026; v8 was planned to narrow dependencies (DAEs may move to sub-packages), so pinning `"7"` is safe for v0.1
- `Sundials = "5"` — v5.0 (Sep 2024) updated underlying SUNDIALS C library from v5 to v7 with breaking API changes; v5.1 is current; pin `"5"` to avoid v4 regressions

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Test (stdlib) | Julia stdlib | Unit test macros `@test`, `@testset` | test/runtests.jl |
| ModelingToolkitStandardLibrary.jl | v2.25+ | Reference for connector patterns | Copy-verify ThermalPort pattern; do NOT add as dependency |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@register_symbolic` | Inline polynomial expressions | Inline breaks symbolic cleanliness; entire equation becomes one large Symbolics expression, harder to debug |
| `@connector` macro | Function-based connector (old API) | Old API (pre-v9): `sys = @set sys.connector_type = connector_type(sys)` — verbose, not the current recommended pattern |
| `[connect = Stream]` for T | `[connect = Flow]` for T | Flow requires T to sum to zero at junctions, which is wrong physics; Stream = upwinding, correct for advection |

**Installation:**

```bash
# From Julia REPL, after Pkg.generate("STREAM"):
using Pkg
Pkg.add([
    "ModelingToolkit",
    "DifferentialEquations",
    "Sundials"
])
```

---

## Architecture Patterns

### Recommended Project Structure

```
STREAM/
├── Project.toml         # [name], [uuid], [compat] — generated by Pkg.generate
├── src/
│   ├── STREAM.jl        # module STREAM; include + export
│   ├── fluids.jl        # @register_symbolic + 4 property functions
│   └── connectors.jl    # @connector FlowPort, @connector ThermalPort
└── test/
    └── runtests.jl      # @testset with fluid spot-checks + connector tests + smoke test
```

### Pattern 1: Package Entry Point

**What:** `src/STREAM.jl` is the single file Julia loads when `using STREAM` is called. It includes subfiles and re-exports the public API.

**When to use:** Always — standard Julia package pattern.

```julia
# Source: https://pkgdocs.julialang.org/v1/creating-packages/
module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t

include("fluids.jl")
include("connectors.jl")

export rho_water, cp_water, mu_water, k_water
export FlowPort, ThermalPort

end  # module STREAM
```

**Note on `t`:** MTK v11 uses `ModelingToolkit.t_nounits` (the independent variable without units). Import it as `t` for convenience. Do not use `@variables t` — that creates a new variable, not MTK's canonical time variable.

### Pattern 2: `@register_symbolic` for Fluid Properties

**What:** Registers a plain Julia function as an opaque symbolic node. MTK can include it in equations, form the Jacobian numerically, but never expands the polynomial symbolically.

**When to use:** Any pure Julia function (no conditional branches, no array returns) that should be callable inside MTK equations.

**Critical constraint:** Must be called at module top-level, not inside any function or closure. The macro dispatches on the function name at parse time.

```julia
# Source: https://docs.sciml.ai/Symbolics/stable/manual/functions/
# In src/fluids.jl, at top level of the file (inside module STREAM):

using Symbolics: @register_symbolic

# Internal helper — not exported, not registered
_to_fahrenheit(T_C) = 1.8 * T_C + 32.0

# Plain Julia functions — T in Kelvin
function rho_water(T_K::Real)
    T_C = T_K - 273.15
    T_F = _to_fahrenheit(T_C)
    A = 1004.789042; B = -0.046283; C = -7.9738e-4
    return abs(A + B * T_F + C * T_F^2)
end

function cp_water(T_K::Real)
    T_C = abs(T_K - 273.15)  # abs matches Python STREAM's np.abs(T)
    A = 17.48908904; B = -1.67507e-3; C = -0.03189591; D = -2.8748e-6
    return sqrt((A + C * T_C) / (1 + B * T_C + D * T_C^2)) * 1000.0
end

function mu_water(T_K::Real)
    T_C = T_K - 273.15
    A = -6.325203964; B = 8.705317e-3; C = -0.088832314; D = -9.657e-7
    return exp((A + C * T_C) / (1 + B * T_C + D * T_C^2))
end

function k_water(T_K::Real)
    T_C = T_K - 273.15
    A = 0.5677829144; B = 1.8774171e-3; C = -8.1790e-6; D = 5.66294775e-9
    return abs(A + B * T_C + C * T_C^2 + D * T_C^3)
end

# Registration — must be at top level of module, after function definitions
@register_symbolic rho_water(T::Real)
@register_symbolic cp_water(T::Real)
@register_symbolic mu_water(T::Real)
@register_symbolic k_water(T::Real)
```

### Pattern 3: `@connector` for Ports

**What:** Defines a named connector type with across and through variables. `[connect = Flow]` variables sum to zero at junctions. `[connect = Stream]` variables use upwinding at junctions.

**When to use:** Both FlowPort and ThermalPort use this pattern.

```julia
# Source: https://docs.sciml.ai/ModelingToolkit/stable/basics/MTKLanguage/
# In src/connectors.jl:

using ModelingToolkit
using ModelingToolkit: t_nounits as t

@connector FlowPort begin
    P(t) = 1.0e5, [description = "Pressure (Pa), across variable"]
    mdot(t) = 0.0, [connect = Flow, description = "Mass flow rate (kg/s), positive = into port"]
    T(t) = 300.0, [connect = Stream, description = "Temperature (K), stream variable"]
end

@connector ThermalPort begin
    T(t) = 300.0, [description = "Temperature (K), across variable"]
    Q_flow(t) = 0.0, [connect = Flow, description = "Heat flow rate (W), positive = into component"]
end
```

### Pattern 4: Using `instream()` in Components (Phase 2 Preview)

**What:** When a component reads the upstream temperature from a FlowPort, it must call `instream(port.T)` not `port.T`. This is required for any stream variable.

**When to use:** Any component equation that references the upstream temperature carried by mass flow.

```julia
# In a Phase 2 @mtkmodel Channel — preview for awareness, not Phase 1 work:
@mtkmodel Channel begin
    @components begin
        inlet  = FlowPort()
        outlet = FlowPort()
    end
    @variables begin
        T_in(t) = 300.0   # observable — captures upstream T, accessible from solution
    end
    @equations begin
        T_in ~ instream(inlet.T)
        # ... channel energy balance using T_in ...
    end
end
```

**Why the observable:** MTK issue #3416 — `sol[channel.inlet.T]` does not work post-solve for stream variables. `sol[channel.T_in]` works. Introduce the observable in Phase 2 components, not in the connector itself.

### Pattern 5: MTK Smoke Test

**What:** A minimal MTK system that uses `rho_water(T)` symbolically, compiled with `mtkcompile`. Catches `@register_symbolic` failures before Phase 2.

```julia
# In test/runtests.jl:
using ModelingToolkit, ModelingToolkit: t_nounits as t
using STREAM

@testset "MTK smoke test: rho_water in equation" begin
    @variables T_var(t) = 300.0
    @variables rho_var(t) = 1000.0
    eqs = [rho_var ~ rho_water(T_var)]
    @named sys = System(eqs, t)
    compiled = mtkcompile(sys)
    @test compiled isa ModelingToolkit.AbstractSystem
end
```

### Anti-Patterns to Avoid

- **`@register_symbolic` inside a function or conditional block:** Causes a "method not found" error at runtime, not compile time. Must be at top level of the module.
- **Using `@variables t` in connectors/fluids:** Creates a new independent variable shadowing MTK's canonical `t`. Import `ModelingToolkit.t_nounits as t` instead.
- **`structural_simplify()` instead of `mtkcompile()`:** `structural_simplify` was renamed to `mtkcompile` starting in MTK v10. In v11, `structural_simplify` may still work as a compatibility alias but `mtkcompile` is the current API.
- **`@mtkbuild` instead of `@mtkcompile`:** Same rename — `@mtkbuild` is the old spelling.
- **`port.T` for stream variable inside component equations:** Must use `instream(port.T)`. Using `port.T` directly in an advection equation is a semantic error (gives the "mixed" value, not upstream).
- **`abs()` guard on density computation:** Python STREAM uses `np.abs(...)` on the final result of density and conductivity to handle numerical artifacts. Port these as `abs(...)` in Julia — this is a simple arithmetic operation, not a conditional branch, so ForwardDiff handles it correctly.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Symbolic function registration | Custom dispatch mechanism | `@register_symbolic` from Symbolics.jl | MTK's integration with AD backends depends on this specific registration pathway |
| Connector variable semantics | Manual Kirchhoff equations at every junction | `@connector` + `connect()` | MTK generates the sum-to-zero equations automatically; manual is error-prone and defeats the acausal paradigm |
| Stream upwinding logic | `if mdot > 0 ... else ...` in equations | `instream()` | `ifelse()` breaks Jacobian smoothness; `instream()` is the MTK-native semantic with correct linear algebra |
| Package scaffold | Manual file creation | `Pkg.generate("STREAM")` in Julia REPL | Generates valid UUID, correct Project.toml structure, and git-ready layout |

**Key insight:** The entire value proposition of MTK is that connector semantics (Kirchhoff, upwinding) are handled by the framework. Reimplementing these manually negates structural simplification and introduces subtle sign errors.

---

## Common Pitfalls

### Pitfall 1: `@register_symbolic` at Wrong Scope

**What goes wrong:** `ERROR: MethodError: no method matching rho_water(::Num)` when using `rho_water` in a component equation.

**Why it happens:** `@register_symbolic` was placed inside an `if __init__` block, a `begin` block inside a function, or similar. The macro needs to be parsed at module load time.

**How to avoid:** Place all four `@register_symbolic` calls at module top-level in `fluids.jl`, directly after the function definitions, with no enclosing scope.

**Warning signs:** The fluid functions work fine with Float64 inputs but fail with `Num` (symbolic) inputs.

### Pitfall 2: Duplicate `define_promotion` Registration

**What goes wrong:** `MethodError: ambiguous` on multiple registrations of the same function.

**Why it happens:** If `rho_water` is registered twice (e.g., once in development and once after a module reload), the second call to `@register_symbolic` with `define_promotion = true` (the default) creates a conflicting promotion rule.

**How to avoid:** Each function is registered exactly once. If iterating in the REPL, restart Julia before re-running module loading.

**Warning signs:** Error mentions "promotion" or "ambiguous method."

### Pitfall 3: Wrong Temperature Units in Fluid Functions

**What goes wrong:** Density at 300 K returns ~988 instead of ~995, or viscosity is off by an order of magnitude.

**Why it happens:** Forgetting to convert from Kelvin to Celsius before applying the Simantov correlation. Python STREAM's functions take Celsius; Julia-STREAM's functions take Kelvin but convert internally.

**How to avoid:** Every function body's first line: `T_C = T_K - 273.15`. Include the specific heat's `abs()`: `T_C = abs(T_K - 273.15)` (mirroring Python's `np.abs(T)`). Run reference value tests at 300 K, 350 K, 400 K immediately.

**Warning signs:** The spot-check tests fail on the first run.

### Pitfall 4: Stream Connector Variable Not in Solution

**What goes wrong:** `KeyError` or `BoundsError` when accessing `sol[component.port.T]` after solving a system with FlowPort.

**Why it happens:** MTK issue #3416 — stream variables are eliminated during `mtkcompile` and are not tracked as observables.

**How to avoid:** Components (Phase 2) define a local variable `T_in ~ instream(inlet.T)` to create an observable. This is a Phase 2 concern but the Phase 1 connector design should not try to work around it by changing the connector definition.

**Warning signs:** The smoke test passes (it does not query stream variables post-solve), but Phase 2 component tests fail on `sol[...]`.

### Pitfall 5: MTK `t` Variable Conflicts

**What goes wrong:** `MethodError` or connector variable equations reference the wrong time variable.

**Why it happens:** Different files independently declare `@variables t` creating multiple independent variable instances. MTK requires all systems in a `connect()` graph to share the same `t`.

**How to avoid:** In every file: `using ModelingToolkit: t_nounits as t` (or `using ModelingToolkit` and reference `ModelingToolkit.t_nounits`). Never write `@variables t` or `@parameters t`.

---

## Code Examples

### Complete fluids.jl

```julia
# Source: Simantov correlations from ~/projects/STREAM/stream/substances/light_water.py
# Reference values verified 2026-03-12

# Internal helper
_to_fahrenheit(T_C::Real) = 1.8 * T_C + 32.0

"""
    rho_water(T_K) -> kg/m3

Saturated liquid water density (Simantov correlation).
T_K: temperature in Kelvin.
"""
function rho_water(T_K::Real)
    T_C = T_K - 273.15
    T_F = _to_fahrenheit(T_C)
    A = 1004.789042; B = -0.046283; C = -7.9738e-4
    return abs(A + B * T_F + C * T_F^2)
end

"""
    cp_water(T_K) -> J/(kg K)

Specific heat of saturated liquid water (Simantov correlation).
T_K: temperature in Kelvin.
"""
function cp_water(T_K::Real)
    T_C = abs(T_K - 273.15)
    A = 17.48908904; B = -1.67507e-3; C = -0.03189591; D = -2.8748e-6
    return sqrt((A + C * T_C) / (1 + B * T_C + D * T_C^2)) * 1000.0
end

"""
    mu_water(T_K) -> Pa s

Dynamic viscosity of saturated liquid water (Simantov correlation).
T_K: temperature in Kelvin.
"""
function mu_water(T_K::Real)
    T_C = T_K - 273.15
    A = -6.325203964; B = 8.705317e-3; C = -0.088832314; D = -9.657e-7
    return exp((A + C * T_C) / (1 + B * T_C + D * T_C^2))
end

"""
    k_water(T_K) -> W/(m K)

Thermal conductivity of saturated liquid water (Simantov correlation).
T_K: temperature in Kelvin.
"""
function k_water(T_K::Real)
    T_C = T_K - 273.15
    A = 0.5677829144; B = 1.8774171e-3; C = -8.1790e-6; D = 5.66294775e-9
    return abs(A + B * T_C + C * T_C^2 + D * T_C^3)
end

# Register at module top-level (not inside any function)
@register_symbolic rho_water(T::Real)
@register_symbolic cp_water(T::Real)
@register_symbolic mu_water(T::Real)
@register_symbolic k_water(T::Real)
```

### Reference Values for Tests (computed from Python STREAM, 2026-03-12)

```julia
# Source: computed directly from Simantov coefficients in light_water.py
# Tolerance: use rtol = 1e-6 (formulas are deterministic; any larger diff = unit error)

# T = 300 K (26.85 C)
# rho  = 995.925708  kg/m3
# cp   = 4177.781138 J/(kg K)
# mu   = 8.5524859163e-4  Pa s
# k    = 0.61240475  W/(m K)

# T = 350 K (76.85 C)
# rho  = 973.771824  kg/m3
# cp   = 4195.561824 J/(kg K)
# mu   = 3.6810159678e-4  Pa s
# k    = 0.66632812  W/(m K)

# T = 400 K (126.85 C)
# rho  = 938.700383  kg/m3
# cp   = 4258.577497 J/(kg K)
# mu   = 2.1973269076e-4  Pa s
# k    = 0.68588445  W/(m K)
```

### Project.toml Template

```toml
name = "STREAM"
uuid = "<generated by Pkg.generate>"
authors = ["<author>"]
version = "0.1.0"

[deps]
DifferentialEquations = "<uuid>"
ModelingToolkit = "<uuid>"
Sundials = "<uuid>"

[compat]
DifferentialEquations = "7"
ModelingToolkit = "11"
Sundials = "5"
julia = "1.10"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `structural_simplify(sys)` | `mtkcompile(sys)` | MTK v10 | Old name may still alias but `mtkcompile` is the v11 canonical name |
| `@mtkbuild sys = Model()` | `@mtkcompile sys = Model()` | MTK v10 | Same rename; both macros available in v11 for now |
| `sys = @set sys.connector_type = connector_type(sys)` | `@connector Name begin ... end` | MTK v9 | Old function-based connector API is obsolete; `@connector` macro is current |
| `structural_simplify(sys, (inputs, outputs))` | `mtkcompile(sys; inputs, outputs)` | MTK v10 | Positional → keyword arguments for inputs/outputs |
| `@variables t` in connector files | `using ModelingToolkit: t_nounits as t` | MTK v9 | Independent variable must be shared; do not declare locally |

**Deprecated/outdated:**
- `@mtkbuild`: Still works in v11 as alias but `@mtkcompile` is canonical
- Function-based `Pin(; name)` connector style with `@set`: Replaced by `@connector` macro

---

## Open Questions

1. **`mtkcompile` compile time on the smoke test system**
   - What we know: MTK v11 improved initialization; for a 2-3 equation system, compile time should be negligible
   - What's unclear: First-call TTFX (time-to-first-execution) due to Julia JIT on fresh session may be 10-30s
   - Recommendation: Accept and document; this is a known Julia characteristic, not a bug

2. **`instream()` availability at connector test time**
   - What we know: `instream()` is only meaningful inside a connected system; testing it in isolation may require constructing a minimal 2-component system
   - What's unclear: Whether `@test_throws` or `@test` is more appropriate for the connector-only test
   - Recommendation: Connector tests verify variable names and metadata only; `instream()` is tested in the smoke test via a minimal connected system

3. **Exact `Symbolics.jl` import path for `@register_symbolic`**
   - What we know: `@register_symbolic` is from Symbolics.jl, which is a transitive dependency of MTK
   - What's unclear: Whether `using ModelingToolkit` re-exports `@register_symbolic` automatically in v11, or whether `using Symbolics: @register_symbolic` is needed explicitly
   - Recommendation: Be explicit: `using Symbolics: @register_symbolic` to avoid any re-export ambiguity. If Symbolics is not in [deps], add it.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` (no install needed) |
| Config file | none — triggered by `] test` in Pkg REPL mode |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| Full suite command | same (single test file for Phase 1) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | `using STREAM` loads without error | smoke | `julia --project=. -e 'using STREAM'` | Wave 0 |
| FOUND-02 | `rho_water(300.0)` returns 995.925708 within rtol=1e-6 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | Wave 0 |
| FOUND-02 | `cp_water`, `mu_water`, `k_water` spot-checks at 300/350/400 K | unit | same | Wave 0 |
| FOUND-02 | `rho_water(T_sym)` callable with symbolic T inside MTK equation (mtkcompile succeeds) | integration | same | Wave 0 |
| CONN-01 | `FlowPort()` instantiates; has fields `P`, `mdot`, `T` | unit | same | Wave 0 |
| CONN-01 | `mdot` has `[connect = Flow]` metadata | unit | same | Wave 0 |
| CONN-01 | `T` has `[connect = Stream]` metadata | unit | same | Wave 0 |
| CONN-02 | `ThermalPort()` instantiates; has fields `T`, `Q_flow` | unit | same | Wave 0 |
| CONN-02 | `Q_flow` has `[connect = Flow]` metadata | unit | same | Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project=. -e 'using STREAM'` (import smoke test, <5s)
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/runtests.jl` — covers all FOUND-01, FOUND-02, CONN-01, CONN-02 tests above
- [ ] `Project.toml` — package must exist before tests can run (`Pkg.generate` or manual creation)
- [ ] `src/STREAM.jl`, `src/fluids.jl`, `src/connectors.jl` — implementation files

---

## Sources

### Primary (HIGH confidence)

- [Symbolics.jl Function Registration docs](https://docs.sciml.ai/Symbolics/stable/manual/functions/) — `@register_symbolic` syntax, `define_promotion`, derivative registration
- [MTK Language docs (stable)](https://docs.sciml.ai/ModelingToolkit/stable/basics/MTKLanguage/) — `@connector`, `@mtkmodel`, `@mtkcompile` syntax verified
- Python STREAM `light_water.py` at `~/projects/STREAM/stream/substances/light_water.py` — all 4 correlation formulas and coefficients (direct source read)
- Python STREAM `utilities.py` — `to_Fahrenheit(T) = 1.8 * T + 32` formula (direct source read)
- Reference values computed 2026-03-12 by running correlations directly in Python with correct coefficients

### Secondary (MEDIUM confidence)

- [MTK GitHub issue #3416](https://github.com/SciML/ModelingToolkit.jl/issues/3416) — stream variable post-solve access bug; workaround `T_in ~ instream(inlet.T)` observable confirmed by developer
- [ModelingToolkitStandardLibrary Thermal API](https://docs.sciml.ai/ModelingToolkitStandardLibrary/stable/API/thermal/) — HeatPort has T (across) + Q_flow (Flow); directly matches ThermalPort design
- [MTK releases page](https://github.com/SciML/ModelingToolkit.jl/releases) — v11.14.0 confirmed as latest as of 2026-03-06
- [Sundials.jl releases](https://github.com/SciML/Sundials.jl/releases) — v5.1.0 confirmed latest (Oct 2024)
- [Julia Discourse: @register_symbolic inside function](https://discourse.julialang.org/t/how-can-i-use-register-symbolic-inside-of-a-function/101734) — confirmed macro must be top-level

### Tertiary (LOW confidence)

- DifferentialEquations.jl v7 is current stable — not independently verified against a changelog; based on search result aggregation. Verify with `] status DifferentialEquations` after `Pkg.add`.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions verified from official GitHub releases and docs
- Architecture: HIGH — `@connector`, `@register_symbolic`, and `@mtkcompile` syntax verified against official current docs
- Pitfalls: HIGH — `@register_symbolic` scope constraint confirmed by official Symbolics docs and Discourse; stream variable issue confirmed by open GitHub issue; temperature unit trap verified by running Python STREAM
- Reference values: HIGH — computed directly from source correlation coefficients

**Research date:** 2026-03-12
**Valid until:** 2026-06-12 (MTK v11 is stable; v12 not announced; valid for ~90 days)
