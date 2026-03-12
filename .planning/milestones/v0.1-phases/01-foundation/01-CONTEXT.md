# Phase 1: Foundation - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Package scaffold, fluid property functions (ρ, cp, μ, k for light water), and MTK connectors (FlowPort, ThermalPort) that Phase 2 components depend on. Solver integration, component equations, and loop assembly are out of scope for this phase.

</domain>

<decisions>
## Implementation Decisions

### Fluid property source
- Port the Simantov correlations verbatim from Python STREAM's `light_water.py`
- Same coefficients, same formulas — ensures any Phase 3 discrepancy is architectural, not property-level
- Temperature unit: **Kelvin internally** (convert from Celsius in Python STREAM formulas by substituting T_C = T_K - 273.15)
- No temperature range guards — ForwardDiff calls these at arbitrary T during Jacobian evaluation; guards would break symbolic differentiation

### Fluid property scope
- Phase 1 registers only: `rho_water(T)`, `cp_water(T)`, `mu_water(T)`, `k_water(T)`
- β, T_sat, h_fg, σ, ρ_vapor are out of scope (not needed for v0.1 components)

### Package structure
- Submodules from the start: `src/STREAM.jl` (entry point) + `src/fluids.jl` + `src/connectors.jl`
- Phase 2 adds `src/components.jl` without restructuring
- Export only public API: `FlowPort`, `ThermalPort`, `rho_water`, `cp_water`, `mu_water`, `k_water`
- Fluid functions exported flat from STREAM for now (no sub-module namespace in v0.1). **Noted:** user wants a `STREAM.Fluids` sub-module in a future refactor — structure the file so the refactor is a simple `module Fluids ... end` wrapper around `fluids.jl` content

### Function naming
- ASCII names: `rho_water`, `cp_water`, `mu_water`, `k_water`
- Matches Python STREAM naming convention, avoids Unicode input friction

### MTK version
- Target **MTK v11.x** (latest stable)
- v11's improved initialization system (guess semantics) eliminates the Tikhonov regularization hack from Python STREAM
- Pin to specific v11.x in Project.toml to prevent surprise breakage from v12

### FlowPort connector design
- Variables: `P(t)` (pressure, across), `mdot(t)` (mass flow, through), `T(t)` (temperature, stream variable)
- **T is an MTK stream variable** — temperature follows flow direction (upwinding). Correct thermal advection semantics for multi-cell Channel in Phase 2
- Mass flow sign convention: **positive = into port** (MTK Kirchhoff convention; sum at junction = 0)
- Primary flow variable: **mass flow mdot (kg/s)** — conservation of mass is the fundamental constraint; volumetric flow depends on density

### ThermalPort connector design
- Variables: `T(t)` (temperature, across), `Q_flow(t)` (heat flow rate in Watts, through)
- Heat flow in **Watts total** — component internally converts to flux using its geometry; geometry does not belong in the port definition

### Testing scope
- **Substantive unit tests** in `test/runtests.jl`
- Fluid property spot-checks: compare Julia values against hardcoded Python STREAM reference values at 3 temperatures (T = 300K, 350K, 400K) for each of ρ, cp, μ, k
- Reference values: run Python STREAM once to extract, hardcode in test — no Python runtime dependency in Julia CI
- Connector tests: verify FlowPort and ThermalPort instantiate, expose correct variable names, correct MTK types (across vs through vs stream)
- **MTK smoke test**: write a minimal 2-3 equation MTK system that calls `rho_water(T)` symbolically and verify `mtkcompile()` runs without error — catches `@register_symbolic` issues before Phase 2

### Claude's Discretion
- Exact Project.toml version bounds for DifferentialEquations.jl and Sundials.jl
- Whether to use `@register_symbolic` macro or the newer MTK v11 equivalent if the API changed
- Internal helper functions within fluids.jl (e.g., Fahrenheit conversion needed by density formula)
- Test tolerance for fluid property numerical comparisons

</decisions>

<specifics>
## Specific Ideas

- The density formula in Python STREAM converts to Fahrenheit internally (`to_Fahrenheit(T_C)`) — this is a quirk of the Simantov correlation. The Julia port should handle this transparently inside `rho_water`, not expose it to callers.
- The flat-export / sub-module decision: structure `fluids.jl` so that a future refactor to `module Fluids ... end` is trivial (no circular imports, no cross-file dependencies within fluids).

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- Python STREAM `light_water.py`: Direct source for all 4 property correlations (coefficients, formulas). Located at `~/projects/STREAM/stream/substances/light_water.py`.
- Python STREAM uses `@njit` (numba) decorators — these have no equivalent in Julia (not needed; Julia JIT compiles natively).

### Established Patterns
- No existing Julia code — greenfield project. Pattern decisions made here establish the conventions for Phases 2 and 3.
- Python STREAM connector analog: `FlowGraph` + `flow_edge` → replaced by MTK `connect()` with FlowPort/ThermalPort

### Integration Points
- `src/STREAM.jl` will `include("fluids.jl")` and `include("connectors.jl")`, then `export` public symbols
- Phase 2 (`src/components.jl`) will call `rho_water`, `cp_water`, etc. directly in `@mtkmodel` equations — no injection
- Test suite will import Python STREAM hardcoded values — get these by running Python STREAM once before writing tests

</code_context>

<deferred>
## Deferred Ideas

- `STREAM.Fluids` sub-module namespace — user explicitly wants this in a future refactor after v0.1
- Additional fluid properties (β, T_sat, h_fg, σ, ρ_vapor) — needed for boiling/natural convection in v0.2
- Heavy water, sodium fluid properties — v2 requirements (FLUID-01, FLUID-02)

</deferred>

---

*Phase: 01-foundation*
*Context gathered: 2026-03-12*
