# Phase 11: HeatDiffusion Component - Research

**Researched:** 2026-03-14
**Domain:** ModelingToolkit.jl — 2D finite-difference solid component with ThermalPort array coupling
**Confidence:** HIGH

## Summary

Phase 11 implements `HeatDiffusion` — a 2D finite-difference fuel plate component for the Julia-STREAM library. The component uses MTK acausal modelling with a 2D array state variable `T(t)[1:nz, 1:nx]` (rows = axial z, columns = lateral x), x-direction diffusion only (v0.3), and `thermal_left[1:nz]` / `thermal_right[1:nz]` ThermalPort arrays for coupling to coolant channels.

All implementation decisions are locked in CONTEXT.md. The research confirms that the codebase already provides every pattern needed: the `ChannelAndContacts` component demonstrates ThermalPort array construction (`[ThermalPort(name=Symbol(..., i)) for i in 1:n]`), the compose splat pattern (`compose(sys, thermal_left..., thermal_right...)`), the `getproperty(sys, Symbol(:thermal_left, i))` access idiom for connect(), and the `_channel_base_eqs` mutation pattern for `_diffusion_eqs`. The `ConstantTemperature` boundary condition component is already implemented and used in existing tests, making it directly reusable for unit tests.

The primary technical risk is ensuring the 2D array state declaration works correctly with MTK and that the equation count stays fully determined when both port arrays are connected. The `mtkcompile(sys; fully_determined=false)` pattern (used in Phase 10 CHAN-03 test) handles the one-sided connection case.

**Primary recommendation:** Follow `ChannelAndContacts` exactly as the structural template — port array creation, compose splat, getproperty access — and adapt `_channel_base_eqs` as the mutation pattern for `_diffusion_eqs`.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Constructor API:**
- Signature: `HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power=1e6, T0=600.0)`
- Uniform mesh: `dx = Lx/nx`, `dz = Lz/nz` computed internally
- Material properties (`rho_s`, `cp_s`, `k_s`) are plain Float64 constructor args, NOT MTK parameters
- `y` (plate width) is explicit constructor parameter for cell volumes and boundary Q_flow
- `T0` is scalar Float64 constructor default for all `T[i,j]` initial values
- No contact conductance on HeatDiffusion — FD stencil ends at plate surface

**Power source:**
- No internal normalization — formula: `power * power_shape[i,j] / (y * dz * dx)`
- Axis convention: `power_shape[1, :]` = top (z=0, inlet side); `power_shape[nz, :]` = bottom (outlet side)
- `power` declared as `@parameters power = default` (MTK tunable parameter)
- Unit test scope: steady-state only, uniform power, pinned boundary via ConstantTemperature

**Boundary Q_flow equations:**
- Left face: `thermal_left[i].Q_flow  ~ k_s * (y * dz) * (T[i, 1]  - thermal_left[i].T)  / (dx / 2)`
- Right face: `thermal_right[i].Q_flow ~ k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2)`
- Sign convention: positive = heat INTO component; unconnected Q_flow = 0 (adiabatic)
- Interior FD stencil: `Dt(T[i,j]) ~ k_s * (T[i,j+1] - 2*T[i,j] + T[i,j-1]) / (dx^2 * rho_s * cp_s) + power*power_shape[i,j]/(rho_s*cp_s*y*dz*dx)` for 2 ≤ j ≤ nx-1
- Top/bottom adiabatic: no z-diffusion equations written at all (adiabatic by omission)

**`_diffusion_eqs` helper:**
- Private, not exported; no public docstring
- Mutates in-place: `_diffusion_eqs(eqs; T, thermal_left, thermal_right, nz, nx, k_s, rho_s, cp_s, dx, dz, y, power, power_shape, Dt)`
- Appends interior x-diffusion + left/right boundary Q_flow equations
- Comment at top: `# v0.4: add dz, kz arguments for xz-diffusion (DIFF-01)`
- No stub kwargs for future features

### Claude's Discretion

- Exact compose() call order for `thermal_left` and `thermal_right` arrays
- Whether to declare `T_plate_max` or similar observable variables (not required by spec)
- Test parameter values for HDIFF unit tests (nz, nx, Lz, Lx, y, material values, T_boundary, power)

### Deferred Ideas (OUT OF SCOPE)

- v0.4: Non-uniform mesh via boundary arrays
- v0.4: z-diffusion (xz mode, DIFF-01)
- v0.4: `power` as acausal variable for PointKinetics coupling (KIN-01)
- v0.4: Non-uniform material properties (per-cell 2D arrays)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HDIFF-01 | User can instantiate a HeatDiffusion component with 2D MTK state `T(t)[1:nz, 1:nx]` (row=axial z, col=lateral x — matching Python STREAM axis convention) | MTK 2D array state variable pattern; constructor API locked in CONTEXT.md |
| HDIFF-02 | HeatDiffusion computes x-direction (across-plate) heat diffusion via FD stencil using an internal `_diffusion_eqs` helper structured for future xz/r extension; top and bottom boundaries are adiabatic | FD stencil equations locked in CONTEXT.md; mutation pattern from `_channel_base_eqs` |
| HDIFF-03 | HeatDiffusion accepts `power_shape[1:nz, 1:nx]` (normalized spatial distribution, constructor parameter) and `power` (total watts, MTK parameter) as the volumetric heat source | `@parameters power` pattern confirmed in existing codebase; normalization convention locked |
| HDIFF-04 | HeatDiffusion exposes `thermal_left[1:nz]` and `thermal_right[1:nz]` ThermalPort arrays for per-cell coupling to coolant channels | Port array pattern confirmed from ChannelAndContacts; compose splat and getproperty idioms confirmed |
| HDIFF-05 | User can leave one side of HeatDiffusion unconnected and it defaults to adiabatic (Q_flow=0 from MTK acausal semantics, verified by explicit test) | `mtkcompile(sys; fully_determined=false)` confirmed for CHAN-03 test; boundary Q_flow equation design ensures adiabatic fallback |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | (project version) | MTK system definition, `@variables`, `@parameters`, `System`, `compose`, `mtkcompile` | Entire Julia-STREAM is built on MTK acausal modelling |
| DifferentialEquations.jl | (project version) | `SteadyStateProblem`, `SSRootfind`, `KINSOL` for solving | Already established solve pattern |
| Sundials.jl | (project version) | KINSOL steady-state solver | Used by solve_steady throughout |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Symbolics.jl | (project version) | `@register_symbolic` for fluid property registration | Not needed for HeatDiffusion (solid, no fluid calls) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Uniform dx/dz mesh | Non-uniform boundary-array mesh | Non-uniform is v0.4; not needed for v0.3 MTR validation |
| Float64 material params | MTK @parameters for k_s, rho_s, cp_s | MTK params enable runtime tuning; Float64 is simpler and Phase 12 rebuilds the system for material changes anyway |

**Installation:** No new packages needed — all required libraries are already in the project's `Project.toml`.

---

## Architecture Patterns

### Recommended Project Structure

No new files needed. `HeatDiffusion` and `_diffusion_eqs` go into `src/components.jl`, and `HeatDiffusion` is exported from `src/STREAM.jl`. Tests go into `test/runtests.jl` as a new `@testset "STREAM Phase 11 Tests"` block.

```
src/
├── STREAM.jl        # add HeatDiffusion to exports
├── components.jl    # add _diffusion_eqs helper + HeatDiffusion function
├── connectors.jl    # unchanged — ThermalPort already defined
├── fluids.jl        # unchanged
└── solvers.jl       # unchanged (no new solver utility needed for Phase 11)
test/
└── runtests.jl      # add Phase 11 @testset block at end
```

### Pattern 1: 2D Array State Variable Declaration

**What:** Declaring a 2D MTK array state variable with per-cell initial conditions.
**When to use:** For the plate temperature field `T(t)[1:nz, 1:nx]`.

```julia
# Source: established MTK pattern; analogous to 1D array in ChannelAndContacts
vars = @variables begin
    (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
end
```

Note: `fill(T0, nz, nx)` produces a `nz × nx` matrix as the default value. This is the 2D extension of `fill(600.0, n)` used in ChannelAndContacts.

### Pattern 2: ThermalPort Array Construction (CONFIRMED in codebase)

**What:** Creating named ThermalPort arrays for per-cell coupling.
**When to use:** For `thermal_left[1:nz]` and `thermal_right[1:nz]`.

```julia
# Source: ChannelAndContacts in src/components.jl
thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:nz]
thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:nz]
```

### Pattern 3: compose() Splat (CONFIRMED in codebase)

**What:** Including port arrays in the composed system.
**When to use:** When building the final HeatDiffusion system.

```julia
# Source: ChannelAndContacts in src/components.jl
compose(System(eqs, t, all_vars, pars; name=name),
        thermal_left..., thermal_right...)
```

Note: Claude's discretion on ordering — `thermal_left..., thermal_right...` is the convention used by ChannelAndContacts and should be followed for consistency.

### Pattern 4: _diffusion_eqs Mutation Helper

**What:** Append FD equations to an existing `eqs` vector in-place.
**When to use:** Called from `HeatDiffusion` constructor to build all diffusion + boundary equations.
**Mirrors:** `_channel_base_eqs` pattern (mutates `eqs::Vector{Equation}` via `push!`).

```julia
# Source: pattern from _channel_base_eqs in src/components.jl
function _diffusion_eqs(eqs::Vector{Equation};
    T, thermal_left, thermal_right,
    nz, nx, k_s, rho_s, cp_s, dx, dz, y, power, power_shape, Dt)
    # v0.4: add dz, kz arguments for xz-diffusion (DIFF-01)

    for i in 1:nz
        # Left boundary Q_flow (conductance half-cell to left face)
        push!(eqs, thermal_left[i].Q_flow  ~
            k_s * (y * dz) * (T[i, 1] - thermal_left[i].T) / (dx / 2))
        # Right boundary Q_flow (conductance half-cell to right face)
        push!(eqs, thermal_right[i].Q_flow ~
            k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2))

        # Interior FD stencil (x-diffusion only, adiabatic top/bottom by omission)
        for j in 1:nx
            q_vol = power * power_shape[i, j] / (rho_s * cp_s * y * dz * dx)
            if j == 1
                # Left boundary cell: uses thermal_left[i].T as virtual left neighbor
                push!(eqs, Dt(T[i, j]) ~
                    k_s / (rho_s * cp_s) *
                    (T[i, j+1] - 2*T[i, j] + thermal_left[i].T) / (dx^2 / 4 + dx^2 / 4)
                    + q_vol)
                # NOTE: See Architecture note below on j=1/j=nx FD form
            elseif j == nx
                # Right boundary cell
                push!(eqs, Dt(T[i, j]) ~
                    k_s / (rho_s * cp_s) *
                    (thermal_right[i].T - 2*T[i, j] + T[i, j-1]) / (dx^2 / 4 + dx^2 / 4)
                    + q_vol)
            else
                # Interior cell: standard 3-point stencil
                push!(eqs, Dt(T[i, j]) ~
                    k_s * (T[i, j+1] - 2*T[i, j] + T[i, j-1]) / (dx^2 * rho_s * cp_s)
                    + q_vol)
            end
        end
    end
end
```

### Pattern 5: @parameters Declaration (CONFIRMED in codebase)

**What:** Declaring a single tunable MTK parameter for total power.
**When to use:** For `power` which needs to be adjustable via `remake()` without rebuilding.

```julia
# Source: @parameters pattern from ChannelAndContacts and build_loop_transient
pars = @parameters begin
    power = power_default
end
```

### Pattern 6: Port Access in connect() (CONFIRMED in codebase, CRITICAL)

**What:** Accessing named ThermalPort subsystems in connect() calls during test assembly.
**Why critical:** `sys.thermal_left[i]` fails in connect(); must use `getproperty`.

```julia
# Source: THERM-03 and CHAN-03 tests in test/runtests.jl
[connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for i in 1:nz]
```

### Pattern 7: mtkcompile with fully_determined=false (CONFIRMED)

**What:** Compiling a system with unconnected ThermalPorts.
**When to use:** HDIFF-05 test where `thermal_right` is unconnected.

```julia
# Source: CHAN-03 test in test/runtests.jl
ssys = mtkcompile(sys; fully_determined=false)
```

When fully connected (both sides), `mtkcompile(sys)` without `fully_determined=false` should work.

### FD Stencil Architecture Note — Boundary Cell Treatment

The CONTEXT.md boundary Q_flow equations use a half-cell distance `(dx/2)` from cell center to plate face. The boundary cells `j=1` and `j=nx` have their face at distance `dx/2` from their centers. The interior stencil uses full `dx` between centers. The planner must decide how to handle `j=1` and `j=nx` energy balance ODEs: two consistent options exist:

**Option A (simpler — used by Python STREAM Fuel):** Write energy balance only for interior cells `j=2..nx-1`; the boundary cell temperatures `T[i,1]` and `T[i,nx]` are coupled to `thermal_left[i].T` and `thermal_right[i].T` directly through the half-cell conductance equations (Q_flow equations). MTK solves for T[i,1] and T[i,nx] algebraically from those equations. This leaves the ODE for only interior cells.

**Option B (explicit ODE for all cells):** Write `Dt(T[i,j])` for all j including boundary cells, using modified FD stencil for j=1 and j=nx that incorporates the port temperature. The CONTEXT.md interior stencil formula applies only for `2 ≤ j ≤ nx-1`.

**Recommendation:** The planner should choose Option B (full ODE for all nz*nx cells) with boundary cells using a modified stencil incorporating `thermal_left[i].T` / `thermal_right[i].T` as the virtual neighbor. This is mathematically consistent and avoids mixing algebraic + differential unknowns for T. Alternatively, the planner may choose to write ODE only for interior nodes and use the Q_flow equations to constrain boundary node T algebraically — both are valid MTK approaches.

**This is left for the planner to decide definitively** based on which produces the correct equation count for fully_determined=true compilation.

### Anti-Patterns to Avoid

- **sys.thermal_left[i] in connect():** Fails silently or errors. Always use `getproperty(sys, Symbol(:thermal_left, i))`.
- **Missing Q_flow equations:** Same lesson as Phase 10 / CAC — MTK acausal does not self-determine Q_flow without an explicit equation. Every ThermalPort's Q_flow must be defined by an equation.
- **z-diffusion in v0.3:** No axial conduction terms — adiabatic by omission is the design. Do not add z-direction FD terms.
- **Normalizing power_shape internally:** The user owns the convention. No sum=1.0 normalization inside `_diffusion_eqs`.
- **collect(T) for 2D arrays:** `collect(T)` on a 2D array variable returns a matrix. The `all_vars` list for `System(eqs, t, all_vars, pars)` may need `vec(collect(T))` to flatten to 1D for the variable list. Verify with MTK API.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Steady-state solver | Custom Newton loop | `solve_steady(ssys, op)` from solvers.jl | Already implemented, uses KINSOL |
| ThermalPort connector | New connector type | Existing `ThermalPort` from connectors.jl | Already defined with correct `connect=Flow` metadata |
| Temperature boundary condition | Inline equation `T ~ value` in test system | `ConstantTemperature` component | Already implemented in Phase 10, pattern confirmed |
| Equation mutation helper | New macro or DSL | Julia function with `push!(eqs, ...)` | Exact pattern of `_channel_base_eqs` |
| Port array iteration | Custom indexing scheme | `getproperty(sys, Symbol(:portname, i))` | Confirmed working in Phase 10 tests |

**Key insight:** The FD stencil is simple algebra — the only complexity is the MTK equation assembly pattern, which is already proven in `ChannelAndContacts`.

---

## Common Pitfalls

### Pitfall 1: Q_flow Equations Missing for Boundary Cells
**What goes wrong:** System is under-determined; mtkcompile fails or produces wrong solution.
**Why it happens:** MTK acausal semantics require explicit Q_flow equations — they are NOT inferred.
**How to avoid:** Ensure `thermal_left[i].Q_flow ~ ...` and `thermal_right[i].Q_flow ~ ...` are explicitly appended in `_diffusion_eqs` for every `i in 1:nz`.
**Warning signs:** mtkcompile with `fully_determined=true` throws equation count mismatch.

### Pitfall 2: 2D all_vars Collection
**What goes wrong:** `System(eqs, t, all_vars, pars)` fails because `all_vars` contains a matrix instead of a flat vector.
**Why it happens:** `collect(T)` on `(T(t))[1:nz, 1:nx]` returns a 2D array.
**How to avoid:** Use `vec(collect(T))` or `[T[i,j] for i in 1:nz for j in 1:nx]` to flatten into a 1D vector when building `all_vars`.
**Warning signs:** MTK error about variable list not being a 1D array.

### Pitfall 3: sys.thermal_left[i] Fails in connect()
**What goes wrong:** MTK cannot resolve the port at connect time; error or wrong port wired.
**Why it happens:** Array port access via `[]` indexing doesn't work for MTK subsystem lookup in `connect()`.
**How to avoid:** Always use `getproperty(hd, Symbol(:thermal_left, i))` in all `connect()` calls in tests.
**Warning signs:** Any test involving `connect(..., sys.thermal_left[i], ...)` fails to compile.

### Pitfall 4: Equation Count Mismatch from Boundary Cell Treatment
**What goes wrong:** System over- or under-determined depending on whether ODEs are written for boundary cells.
**Why it happens:** Each of the `nz*nx` T cells needs exactly one ODE. If Q_flow equations also constrain T[i,1] or T[i,nx], there may be a redundancy or gap.
**How to avoid:** Decide boundary cell treatment consistently: either write ODE for all cells (j=1..nx) with modified stencil, OR write ODE only for j=2..nx-1 and let Q_flow equations determine boundary temperatures algebraically. Don't mix.
**Warning signs:** `mtkcompile` warns about over-determination or under-determination.

### Pitfall 5: Adiabatic Behavior When Unconnected
**What goes wrong:** Unconnected `thermal_right[i]` does NOT default to Q_flow=0 if the Q_flow equation involves `thermal_right[i].T` as a free variable.
**Why it happens:** MTK sets Q_flow=0 for unconnected Flow variables — but the equation `thermal_right[i].Q_flow ~ k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2)` will force `thermal_right[i].T = T[i, nx]` when Q_flow=0, which is physically correct (surface temperature equals interior temperature → adiabatic).
**How to avoid:** No special handling needed — the boundary Q_flow equation design already produces correct adiabatic behavior. Verify with HDIFF-05 test.
**Warning signs:** `sol[thermal_right[i].Q_flow]` is non-zero in the one-sided test.

### Pitfall 6: power_shape Indexing Convention
**What goes wrong:** Plate temperature profile is axially inverted relative to Python STREAM reference.
**Why it happens:** Confusion about `power_shape[1, :]` = top (inlet, z=0) vs bottom.
**How to avoid:** Document and test: index 1 = inlet-facing cell (top of plate, low z). Unit tests with uniform power_shape avoid this issue; Phase 12 validates the convention against Python STREAM.

---

## Code Examples

Verified patterns from existing codebase:

### HeatDiffusion Constructor Skeleton
```julia
# Source: ChannelAndContacts pattern from src/components.jl
function HeatDiffusion(; name, nz::Int, nx::Int, Lz, Lx, y,
                         rho_s, cp_s, k_s, power_shape,
                         power=1e6, T0=600.0)
    Dt = Differential(t)
    dx = Lx / nx
    dz = Lz / nz

    pars = @parameters begin
        power = power
    end

    vars = @variables begin
        (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
    end

    thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:nz]
    thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:nz]

    eqs = Equation[]
    _diffusion_eqs(eqs; T, thermal_left, thermal_right,
                   nz, nx, k_s, rho_s, cp_s, dx, dz, y,
                   power=pars[1], power_shape, Dt)

    all_vars = vec(collect(T))

    compose(System(eqs, t, all_vars, pars; name=name),
            thermal_left..., thermal_right...)
end
```

### HDIFF-01/02/04 Smoke Test Pattern
```julia
# Source: COMP-01 pattern from test/runtests.jl
@testset "HDIFF-01: HeatDiffusion instantiates with 2D state" begin
    ps = fill(1.0, 5, 3) / (5*3)   # uniform normalized power_shape
    @named hd = HeatDiffusion(nz=5, nx=3, Lz=0.6, Lx=0.005,
                               y=0.07, rho_s=19300.0, cp_s=116.0,
                               k_s=174.0, power_shape=ps)
    @test hd isa ModelingToolkit.System
    var_names = Symbol.(ModelingToolkit.getname.(unknowns(hd)))
    @test :T in var_names   # 2D state present
end
```

### HDIFF-05 One-Sided Test Pattern
```julia
# Source: CHAN-03 pattern from test/runtests.jl
@testset "HDIFF-05: Unconnected thermal_right is adiabatic" begin
    nz = 3; nx = 2
    ps = fill(1.0, nz, nx) / (nz*nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005,
                               y=0.07, rho_s=19300.0, cp_s=116.0,
                               k_s=174.0, power_shape=ps)
    ct = [ConstantTemperature(name=Symbol(:ct, i), T=600.0) for i in 1:nz]
    conns = [connect(ct[i].thermal, getproperty(hd, Symbol(:thermal_left, i)))
             for i in 1:nz]
    @named sys = compose(System(conns, t; name=:sys), hd, ct...)
    ssys = mtkcompile(sys; fully_determined=false)
    # solve and verify thermal_right[i].Q_flow == 0 for all i
end
```

### Export Addition
```julia
# Source: src/STREAM.jl
export ..., HeatDiffusion
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single ThermalPort per channel | Per-cell ThermalPort arrays | Phase 9-10 | Enables HeatDiffusion coupling; pattern confirmed |
| No solid component | HeatDiffusion FD plate | Phase 11 (this phase) | First solid component in Julia-STREAM |
| `thermal_ports[1:n]` naming | `thermal_left[1:nz]` + `thermal_right[1:nz]` | Phase 10 (CHAN-01) | Architectural split: each face is a separate array |

**Deprecated/outdated:**
- `thermal_ports` array naming: replaced by `thermal_left` / `thermal_right` split in Phase 10.

---

## Open Questions

1. **Boundary cell ODE treatment (j=1 and j=nx)**
   - What we know: CONTEXT.md specifies the interior stencil for `2 ≤ j ≤ nx-1` and the boundary Q_flow equations. Does not specify whether to write ODEs for j=1 and j=nx.
   - What's unclear: Option A (algebraic BC via Q_flow) vs Option B (ODE for all cells with modified stencil) — both are physically valid, but they produce different equation structures and equation counts.
   - Recommendation: Planner decides. Option B (ODE for all cells) is likely simpler for MTK and avoids mixing differential/algebraic states for T. The planner should verify the equation count is `nz*nx` ODEs + `2*nz` Q_flow algebraic equations for a total of `nz*(nx+2)` equations from `_diffusion_eqs`.

2. **`pars[1]` vs named parameter reference in _diffusion_eqs**
   - What we know: `@parameters power = default` returns a vector `pars`; `pars[1]` accesses the symbolic parameter. In the existing code, `ps = @parameters T_wall = T_wall_0` and `ps[1]` is passed directly to the equation.
   - What's unclear: Whether to store the parameter symbol separately (e.g., `power_sym = pars[1]`) before passing to `_diffusion_eqs` for clarity.
   - Recommendation: Store as named local `power_par = only(pars)` or `pars[1]` and pass that to `_diffusion_eqs`. Either works.

3. **Steady-state test convergence for the HDIFF-02/03 behavioral test**
   - What we know: The test pins both boundary arrays to a constant temperature and applies uniform power. The plate should reach a parabolic steady-state T profile.
   - What's unclear: Whether KINSOL converges readily for a small (e.g., nz=3, nx=5) isolated plate system with realistic uranium metal properties (rho=19300, cp=116, k=174).
   - Recommendation: Choose small nz/nx (e.g., 3x3 or 3x5). Initial guess T0=600 is reasonable for T_boundary=600 + small power; adjust if convergence fails.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`using Test`, `@testset`, `@test`) |
| Config file | none — tests run via `Pkg.test()` |
| Quick run command | `julia --project test/runtests.jl` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HDIFF-01 | Instantiate with 2D state `T(t)[1:nz, 1:nx]`; verify row=axial, col=lateral | unit | `julia --project test/runtests.jl` (Phase 11 testset) | ❌ Wave 0 |
| HDIFF-02 | x-diffusion + adiabatic top/bottom; verify `_diffusion_eqs` produces correct equations | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |
| HDIFF-03 | `power_shape` + `power` drive correct volumetric source; verify parabolic T profile or heat balance | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |
| HDIFF-04 | `thermal_left[1:nz]` and `thermal_right[1:nz]` ThermalPort arrays present in subsystems | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |
| HDIFF-05 | One-sided connection: `thermal_right[i].Q_flow == 0` at steady state | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project test/runtests.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite (102 + Phase 11 tests) green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — add `@testset "STREAM Phase 11 Tests"` block (5 testsets covering HDIFF-01 through HDIFF-05)
- [ ] `src/components.jl` — add `_diffusion_eqs` function and `HeatDiffusion` function
- [ ] `src/STREAM.jl` — add `HeatDiffusion` to exports

*(All existing infrastructure is in place — no new test files, no new packages. Only new code in existing files.)*

---

## Sources

### Primary (HIGH confidence)
- `src/components.jl` (direct read) — ChannelAndContacts, ConstantTemperature, `_channel_base_eqs` patterns confirmed
- `src/connectors.jl` (direct read) — ThermalPort connector definition confirmed
- `src/STREAM.jl` (direct read) — export pattern confirmed
- `test/runtests.jl` (direct read) — Phase 10 CHAN-03 test pattern for one-sided connection confirmed; `getproperty(sys, Symbol(:thermal_left, i))` confirmed
- `.planning/phases/11-heatdiffusion-component/11-CONTEXT.md` (direct read) — all locked decisions confirmed

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` (direct read) — HDIFF-01 through HDIFF-05 requirement text confirmed
- `.planning/STATE.md` (direct read) — Phase 10 complete, 102 tests green confirmed

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in use; no new dependencies
- Architecture patterns: HIGH — all patterns directly confirmed from existing codebase
- Pitfalls: HIGH — Q_flow requirement and `getproperty` idiom proven by Phase 10 experience; 2D array flattening is a standard Julia concern
- FD equations: HIGH — equations locked in CONTEXT.md; only boundary cell ODE treatment remains open
- Validation architecture: HIGH — Julia Test stdlib; existing test pattern confirmed

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (MTK API stable; no breaking changes expected in this timeframe)
