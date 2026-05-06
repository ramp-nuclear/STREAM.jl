# Phase 2: Components - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement four standalone MTK components (Channel, Pump, Friction, Gravity) that can be instantiated and compiled in isolation with `mtkcompile`. No loop assembly, no solving, no cross-component connections in this phase — those are Phase 3.

</domain>

<decisions>
## Implementation Decisions

### ThermalPort topology for Channel
- **Single ThermalPort** carrying total Q_wall (W) — one connection from heat source to Channel
- Internally, Channel introduces a `q_wall[i]` per-cell array: `q_wall[i] = thermal_port.Q_flow / n` (uniform distribution)
- All energy balance equations use `q_wall[i]` — never `Q_flow / n` directly
- **Reason for indirection:** When a heated plate with z/x-axis heat generation is added later, the refactor changes only port topology (1 port → n ports, `q_wall[i] = thermal_ports[i].Q_flow`). The energy balance equations are untouched.

### Channel temperature advection
- Use `inStream(port_in.T)` for the inlet temperature (cell 1's upstream boundary)
- Cell-to-cell: `T_in[i] = T[i-1]` for cells 2..n (direct variable reference, first-order upwind)
- Same first-order upwind finite-volume discretization as Python STREAM's `coolant_first_order_upwind_dTdt`
- MTK computes the Jacobian symbolically; physics and discretization scheme are identical to Python STREAM

### Intermediate observable variables
**Channel** (all per-cell, exposed as MTK `@variables` so they appear in `observed(compiled_sys)`):
- `Re[i]` — Reynolds number per cell (for verifying turbulent regime / Dittus-Boelter validity)
- `Nu[i]` — Nusselt number per cell (Dittus-Boelter intermediate)
- `h_tc[i]` — heat transfer coefficient per cell (W/m²K), the key HTC quantity
- `v[i]` — coolant velocity per cell (m/s)
- `T_out` — outlet temperature alias (= T[n], mirrors Python STREAM's `ChannelVar.tout`)
- `dP` — pressure drop across Channel (mirrors Python STREAM's `ChannelVar.pressure_drop`)

**Friction**:
- `Re` — Reynolds number
- `f` — Blasius friction factor

**Pump, Gravity**: no additional observables beyond port variables

### mtkcompile isolation test
- Each component test: instantiate → `mtkcompile` → assert no errors
- Channel additionally: assert pre-compile equation list contains exactly `n` energy balance equations (structural correctness of discretization)
- No solving in Phase 2 — numerical correctness is Phase 3's job

### Component parameters
- **No default parameter values** — all geometry/physics parameters are required at instantiation
  - Channel: `n`, `L` (m), `D` (hydraulic diameter, m), `A` (flow area, m²)
  - Pump: `dP` (Pa)
  - Friction: `L` (m), `D` (m), `A` (m²)
  - Gravity: `H` (m), `A` (m²)
- **Variable initial guesses**: components carry physics-based defaults in `@variables` declarations
  - `T = 600.0` (K) — hot coolant starting point
  - `P = 1.0e5` (Pa) — 1 bar reference
  - `mdot = 1.0` (kg/s) — light PWR-like flow
- Algebraic variables (Re, Nu, h_tc, v, dP, f) need **no initial guesses** — MTK's initialization solves these from T and mdot at t=0
- Phase 3 uses `unknowns(compiled_sys)` to discover exactly which variables need `u0` — will be only the T[i] array

### Claude's Discretion
- Exact Dittus-Boelter form (standard: Nu = 0.023 Re^0.8 Pr^0.4 for heating)
- Prandtl number computation (Pr = cp * mu / k using registered fluid property functions)
- Blasius friction factor form (f = 0.316 Re^(-0.25) for Re < 100000)
- How to declare array variables in MTK v11 (scalarize vs array variable approach)
- Whether `dP` on Channel is a single scalar or per-cell cumulative pressure

</decisions>

<specifics>
## Specific Ideas

- Python STREAM's `ChannelVar` enum tracks: `tbulk`, `pressure_drop`, `re`, `mass_flow`, `tin`, `tout`, `velocity`, `absolute_pressure`, `static_pressure`. Phase 2 should cover the non-pressure-profile subset (absolute pressure per cell is a Phase 3 concern once the loop has a known reference pressure).
- The `q_wall[i]` indirection is the key design decision for future heated-plate coupling. Document this in a comment in the component source.
- When refactoring to per-cell ThermalPorts later: only the port declaration and `q_wall[i]` binding line changes. The energy balance loop `D(T[i]) ~ ...` is untouched.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FlowPort` (src/connectors.jl): P(t) across, mdot(t) flow, T(t) stream variable. Mass flow positive into port.
- `ThermalPort` (src/connectors.jl): T(t) across, Q_flow(t) flow variable in Watts.
- `rho_water`, `cp_water`, `mu_water`, `k_water` (src/fluids.jl): All `@register_symbolic`, callable in MTK equations. Temperature in Kelvin.
- Package entry point `src/STREAM.jl`: `include("components.jl")` and export new public symbols here.

### Established Patterns
- `@connector function Name(; name)` — MTK v11 connector pattern (not DSL block syntax)
- Temperature in Kelvin everywhere; no range guards on fluid properties (ForwardDiff compatibility)
- `mdot` positive = into port (Kirchhoff convention)
- MTK v11: `System(Equation[], t, sts, []; name = name)` for connector construction

### Integration Points
- New file: `src/components.jl` — added alongside fluids.jl and connectors.jl, no restructuring
- `src/STREAM.jl`: add `include("components.jl")` and export `Channel`, `Pump`, `Friction`, `Gravity`
- `test/runtests.jl`: add component isolation tests (mtkcompile + equation count checks)

</code_context>

<deferred>
## Deferred Ideas

- Per-cell ThermalPorts for Channel — needed when coupling a heated plate with z/x-axis heat generation; refactor is isolated to port topology due to `q_wall[i]` indirection
- Absolute pressure per cell (cumulative ΔP from loop reference) — Phase 3 concern once reference pressure is known from loop assembly
- Pr[i] as an observable — computable from Re and Nu if needed, not worth exposing separately

</deferred>

---

*Phase: 02-components*
*Context gathered: 2026-03-12*
