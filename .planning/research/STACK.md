# Stack Research

**Domain:** 2D finite-difference fuel plate (HeatDiffusion) + two-sided ChannelAndContacts coupling in Julia/MTK
**Researched:** 2026-03-13
**Confidence:** HIGH

## Summary

No new packages are required for v0.3. The existing stack (ModelingToolkit v11, Symbolics v7, Sundials v5, DifferentialEquations v7) already supports everything HeatDiffusion needs. The 2D indexed variable pattern `(T(t))[1:nx, 1:nz]` is the same mechanism as the existing `(T(t))[1:n]` in Channel — same Symbolics.jl symbolic array infrastructure, same MTK scalarization. The two-sided ChannelAndContacts upgrade is a direct extension of the proven `thermal_ports[1:n]` splat pattern.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| ModelingToolkit.jl | 11.15.0 (current), compat = "11" | Symbolic equation system, mtkcompile, compose(), connect() | Already validated for acausal thermal-hydraulic modeling; v11 handles symbolic arrays via Symbolics.jl 7 |
| Symbolics.jl | 7.15.3 (current), compat = "5, 6, 7" | Symbolic array variable declaration `(T(t))[1:nx, 1:nz]` | Provides the 2D indexed variable syntax; `@variables (T(t))[1:nx, 1:nz]` is legal and works identically to 1D arrays |
| Sundials.jl | 5.1.0 | IDA DAE solver backend | HeatDiffusion adds ODE states but does not change DAE structure; IDA continues to be the correct solver |
| DifferentialEquations.jl | 7.17.0 | Solver dispatch, ODEProblem/DAEProblem construction | No change needed |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| LinearAlgebra (stdlib) | Julia 1.10+ | `vec()` to flatten 2D symbolic arrays for `System()` state var list | Use `vec(collect(T))` to pass 2D symbolic array as flat 1D state list to `System(eqs, t, all_vars, pars; name=name)` |

No new packages need to be added to Project.toml.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Julia 1.10+ (current: 1.12.5) | Language runtime | No change; `compat julia = "1.10"` remains correct |

## Installation

No changes to Project.toml. Existing dependencies cover all v0.3 needs.

```toml
# Project.toml remains unchanged:
[deps]
DifferentialEquations = "0c46a032-eb83-5123-abaf-570d42b7fbaa"
ModelingToolkit = "961ee093-0014-501f-94e3-6117800e7a78"
Sundials = "c3572dad-4567-51f8-b174-8c6c989267f4"
Symbolics = "0c5d862f-8b57-4792-8d23-62f2024744c7"

[compat]
DifferentialEquations = "7"
ModelingToolkit = "11"
Sundials = "5"
Symbolics = "5, 6, 7"
julia = "1.10"
```

## Integration Patterns for New Features

### 2D Array Variables in HeatDiffusion

The syntax is identical to the 1D pattern already in Channel, extended to two dimensions:

```julia
# Existing 1D pattern (Channel, ChannelAndContacts):
vars = @variables begin
    (T(t))[1:n] = fill(600.0, n)
end
all_vars = [collect(T); ...]
# Uses T[i] in equations

# 2D extension for HeatDiffusion:
vars = @variables begin
    (T(t))[1:nx, 1:nz] = fill(700.0, nx, nz)
end
all_vars = [vec(collect(T)); ...]
# Uses T[ix, iz] in equations
```

The critical difference: `collect(T)` on a 2D symbolic array returns a Matrix; `vec(collect(T))` flattens it to the 1D Vector that `System()` expects for state variables.

### Equation Generation for FD Stencil

Use nested `for` loops with `push!` — same pattern as Channel's energy balance loop, extended to 2D:

```julia
eqs = Equation[]
for ix in 1:nx, iz in 1:nz
    # interior: 5-point stencil
    T_left  = (ix == 1)  ? T_bc_left  : T[ix-1, iz]
    T_right = (ix == nx) ? T_bc_right : T[ix+1, iz]
    T_down  = (iz == 1)  ? T_bc_bot   : T[ix, iz-1]
    T_up    = (iz == nz) ? T_bc_top   : T[ix, iz+1]
    push!(eqs, Dt(T[ix, iz]) ~ ...)
end
```

This mirrors the tether simulation pattern from the Discourse community (confirmed working with MTK v11): iterate over indices, build boundary-aware stencil, push scalar equations.

### Two-Sided ThermalPort Arrays

This is a direct extension of the existing `thermal_ports[1:n]` splat pattern in ChannelAndContacts. Two independent port arrays instead of one:

```julia
# Existing single-sided (ChannelAndContacts v0.2):
thermal_ports = [ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]
compose(System(...), port_in, port_out, thermal_ports...)

# Two-sided extension (ChannelAndContacts v0.3):
thermal_left  = [ThermalPort(name=Symbol(:thermal_left,  i)) for i in 1:n]
thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]
compose(System(...), port_in, port_out, thermal_left..., thermal_right...)
```

MTK's `connect()` and acausal semantics handle unconnected ports naturally — a ThermalPort not wired to anything will have `Q_flow = 0` by the flow conservation law, giving adiabatic behavior without any explicit flag.

### Initial Conditions (Critical Pattern)

For 2D array variables, use Dict syntax — not manually constructed u0 vectors. MTK state ordering can change between patch releases:

```julia
# Correct:
u0 = Dict(hd.T => fill(700.0, nx, nz))

# Wrong (order-sensitive, breaks silently):
u0 = vec(collect(...))  # manually ordered
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Manual `for ix, iz` loop + `push!` equations | MethodOfLines.jl for symbolic PDE discretization | Use MethodOfLines only if you need automatic PDE-to-ODE conversion from symbolic PDEs; for HeatDiffusion the FD stencil is hand-written and fixed — MethodOfLines adds complexity without benefit |
| `vec(collect(T))` to flatten 2D for `System()` | `scalarize(T)` | `scalarize` works but produces a symbolic expression that may not behave identically to a concrete Vector in `System()`; `vec(collect(T))` is the pattern proven by Channel's 1D `collect(T)` |
| `Dict(T => fill(...))` for u0/p0 | Manual u0 vector | Never use manual u0 — MTK state ordering changes between patch releases (confirmed in community discourse) |
| Two separate `thermal_left[1:n]` + `thermal_right[1:n]` arrays | Single `thermal_ports[1:2n]` with even/odd convention | Separate named arrays are explicit and match how HeatDiffusion exposes ports; 2n single array would require index arithmetic to identify left vs right |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| MethodOfLines.jl | Adds a new heavy dependency for PDE discretization; HeatDiffusion's FD stencil is a fixed 5-point scheme that doesn't benefit from symbolic PDE machinery | Manual nested for-loop with push! equations |
| Manual u0/p0 vector construction for 2D states | MTK state ordering is not guaranteed to be stable across patch releases; manual indexing silently produces wrong results | `Dict(component.T => fill(700.0, nx, nz))` syntax |
| Adding MTK version constraint tighter than "11" | v11.15.0 → v11.16.0 transition shows active development but no breaking changes for array vars; tighter pin would prevent bugfix adoption | Keep `ModelingToolkit = "11"` in compat |
| `@mtkmodel` / `@mtkbuild` macros | These are the newer declarative DSL for MTK; the project uses the functional `compose(System(...), ...)` API which is fully supported in v11 and matches the existing codebase style | Keep using `compose(System(...), ...)` functional API |

## Stack Patterns by Variant

**For HeatDiffusion interior cells:**
- Use `T[ix, iz]` direct indexing in push!-appended equations
- Boundary conditions expressed inline (no separate BC system)
- `Dt(T[ix, iz]) ~` left-hand side requires `Differential(t)` operator declared once at top of component function

**For ChannelAndContacts two-sided upgrade:**
- Replace `thermal_ports[1:n]` with `thermal_left[1:n]` + `thermal_right[1:n]`
- Energy balance: `h_tc[i] * (...) * (thermal_left[i].T - T[i]) + h_tc[i] * (...) * (thermal_right[i].T - T[i])`
- `Q_wall_total ~ sum(thermal_left[i].Q_flow + thermal_right[i].Q_flow for i in 1:n)`
- Splat both arrays into `compose()`

**For HeatDiffusion ThermalPort arrays (`thermal_left[1:nz]`, `thermal_right[1:nz]`):**
- Same `[ThermalPort(name=Symbol(:thermal_left, i)) for i in 1:nz]` pattern
- Boundary condition equations: `T[1, iz] ~ thermal_left[iz].T` (left wall tied to port temperature)
- `Q_flow` equations derived from Fourier's law at the boundary cell

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| ModelingToolkit 11.15.0 | Symbolics 7.15.3 | Both installed; MTK v11 requires Symbolics v5+ (compat already covers this) |
| Sundials 5.1.0 | DifferentialEquations 7.17.0 | No change; IDA solver path unchanged by HeatDiffusion |
| Julia 1.12.5 | All packages above | Runtime version; compat lower-bounds at 1.10 which is fine |

MTK v11.16.0 is the current release as of 2026-03-13 (released 2025-03-12). The `compat = "11"` bound in Project.toml already allows it. No manual version pin update needed — `Pkg.update()` will pick it up if desired, but the project's patch-level stability has been fine on 11.15.0 through v0.1 and v0.2.

## Sources

- Existing codebase: `/home/itay/projects/Julia-STREAM/src/components.jl` — confirmed `(T(t))[1:n]` 1D symbolic array pattern + `collect(T)` flatten + for-loop `push!` already in production use (HIGH confidence)
- [Symbolics.jl Arrays Documentation](https://symbolics.juliasymbolics.org/dev/manual/arrays/) — `@variables A[1:5, 1:3]` 2D array syntax; `scalarize()` and `collect()` semantics (HIGH confidence)
- [MTK Language Documentation](https://docs.sciml.ai/ModelingToolkit/stable/basics/MTKLanguage/) — `(v_array(t))[1:N, 1:M]` syntax with `@structural_parameters` for sizing (HIGH confidence)
- [Julia Discourse: 2D Arrays with ModelingToolkit](https://discourse.julialang.org/t/2d-arrays-with-modelingtoolkit/107448) — Community confirmation `@variables pos(t)[1:3, 1:segments+1]` works; `vcat`/`push!` loop patterns; Dict u0 requirement (MEDIUM confidence — community source, aligns with official docs)
- [MTK GitHub Releases](https://github.com/SciML/ModelingToolkit.jl/releases) — v11.16.0 is latest as of 2026-03-13 (HIGH confidence)
- Installed package manifest (`julia --project -e "import Pkg; ..."`) — exact versions 11.15.0 / 7.15.3 / 5.1.0 / 7.17.0 (HIGH confidence)

---
*Stack research for: HeatDiffusion (2D FD fuel plate) + two-sided ChannelAndContacts, Julia-STREAM v0.3*
*Researched: 2026-03-13*
