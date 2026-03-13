# Architecture Research

**Domain:** MTK-based thermal-hydraulics library — HeatDiffusion + two-sided ChannelAndContacts
**Researched:** 2026-03-13
**Confidence:** HIGH (based on direct code inspection of existing codebase + Python STREAM reference + MTK documentation)

---

## Standard Architecture

### System Overview

```
┌────────────────────────────────────────────────────────────────────┐
│                         User Assembly Layer                         │
│  connect(hd.thermal_left[i], ch_left.thermal_left[i])               │
│  connect(hd.thermal_right[i], ch_right.thermal_right[i])            │
│  compose(System(...), pump, bc, ch_left, ch_right, hd)              │
└────────────┬──────────────────────┬──────────────────────┬──────────┘
             │                      │                      │
┌────────────▼────────┐  ┌──────────▼──────────┐  ┌───────▼──────────┐
│  ChannelAndContacts │  │   HeatDiffusion      │  │  ChannelAndContacts│
│  (left side)        │  │   (new, v0.3)        │  │  (right side)    │
│                     │  │                      │  │                  │
│  port_in  port_out  │  │  T[1:nx, 1:nz](t)    │  │  port_in port_out│
│  thermal_left[1:n]  │  │  thermal_left[1:nz]  │  │  thermal_left[1:n│
│  thermal_right[1:n] │  │  thermal_right[1:nz] │  │  thermal_right[1:n│
└────────────────────┘  └──────────────────────┘  └──────────────────┘
             │                      │                      │
┌────────────▼──────────────────────▼──────────────────────▼──────────┐
│                      MTK acausal connect() layer                     │
│  ThermalPort: T (across), Q_flow (flow, sum=0 at junction)          │
│  FlowPort:    P (across), mdot (flow), T (stream)                   │
└─────────────────────────────────────────────────────────────────────┘
             │
┌────────────▼──────────────────────────────────────────────────────┐
│            mtkcompile() → structural_simplify → Sundials IDA        │
│            SteadyStateProblem / ODEProblem                          │
└───────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | File | Responsibility | Status |
|-----------|------|----------------|--------|
| `HeatDiffusion` | `src/heat_diffusion.jl` (new) | 2D FD fuel plate; T[1:nx,1:nz](t); exposes thermal_left[1:nz] + thermal_right[1:nz] | NEW in v0.3 |
| `ChannelAndContacts` | `src/components.jl` (modify) | n-cell heated channel; thermal_ports[1:n] → thermal_left[1:n] + thermal_right[1:n] | MODIFIED in v0.3 |
| `ThermalPort` | `src/connectors.jl` (unchanged) | Acausal connector: T across, Q_flow flow | unchanged |
| `FlowPort` | `src/connectors.jl` (unchanged) | Acausal connector: P across, mdot flow, T stream | unchanged |
| `_channel_base_eqs` | `src/components.jl` (unchanged) | Shared hydraulic base equations helper | unchanged |
| `Channel` | `src/components.jl` (unchanged) | Simple heated channel with single ThermalPort | unchanged |
| `ChannelHeatFlux` | `src/components.jl` (unchanged) | Channel with scalar T_wall parameter (no ports) | unchanged |
| Fluid properties | `src/fluids.jl` (unchanged) | rho/cp/mu/k_water with @register_symbolic | unchanged |
| Solvers | `src/solvers.jl` (new build helpers) | build_mtr_loop (new); existing helpers unchanged | new helper added |

---

## Recommended Project Structure

```
src/
├── STREAM.jl               # module root; add HeatDiffusion to exports
├── fluids.jl               # unchanged
├── connectors.jl           # unchanged
├── components.jl           # ChannelAndContacts modified (breaking change)
├── heat_diffusion.jl       # NEW — HeatDiffusion component
└── solvers.jl              # add build_mtr_loop() helper

test/
└── runtests.jl             # add Phase 10 testsets (HDIFF-01..04, THERM-04, VAL-03)
```

### Structure Rationale

- **`heat_diffusion.jl` as new file:** Keeps components.jl focused on fluid components. Heat diffusion is a distinct physics domain (solid conduction vs. fluid convection). Python STREAM also separates `heat_diffusion.py` from channel calculations.
- **`ChannelAndContacts` stays in `components.jl`:** It is a fluid component that happens to have thermal ports. Moving it would break the established pattern.
- **Exports in `STREAM.jl`:** Add `HeatDiffusion` to the export list. No other export changes needed.

---

## Architectural Patterns

### Pattern 1: MTK 2D Indexed Variables via `@variables T[1:nx, 1:nz](t)`

**What:** MTK supports `@variables T[1:nx, 1:nz](t)` for 2D array-valued symbolic variables. The result is a symbolic array; individual elements are accessed as `T[i, j]`. This is the same mechanism used by the existing codebase for 1D arrays: `@variables (T(t))[1:n]` (existing syntax used in Channel/ChannelAndContacts).

**When to use:** Whenever the physics requires a 2D grid of state variables — the HeatDiffusion plate interior temperatures T[1:nx, 1:nz].

**Trade-offs:**
- Straightforward declaration; MTK handles symbolic indexing consistently.
- `collect(T)` is needed to flatten a symbolic array into a `Vector{Num}` for `all_vars`.
- For a 2D array, use `collect(T)` which gives a `nx × nz` matrix; flatten further with `vec(collect(T))` to get a `Vector{Num}` for `all_vars`.
- mtkcompile compile time scales with `nx * nz` equations. For typical MTR plate discretizations (nx=3..10, nz=10..20), this is 30–200 ODE equations — well within the observed practical range (< 1,000 is fast; > 10,000 starts to slow).

**Example (matching existing codebase style):**

```julia
function HeatDiffusion(; name, nx::Int, nz::Int, ...)
    vars = @variables begin
        (T(t))[1:nx, 1:nz]  = fill(600.0, nx, nz)
        ...
    end

    eqs = Equation[]
    for i in 1:nx
        for j in 1:nz
            push!(eqs, Dt(T[i,j]) ~ ...)
        end
    end

    all_vars = [vec(collect(T)); ...]
    compose(System(eqs, t, all_vars, pars; name=name), thermal_left..., thermal_right...)
end
```

**Confidence:** HIGH — the existing codebase already uses `(T(t))[1:n]` (1D) and `collect(T)` in Channel and ChannelAndContacts. The 2D extension `(T(t))[1:nx, 1:nz]` follows the same MTK symbolic array mechanics.

---

### Pattern 2: ThermalPort Arrays via Splat Compose

**What:** Arrays of ThermalPorts are declared as Julia arrays of MTK subsystems, then splatted into `compose()`. This is already proven by ChannelAndContacts.

**When to use:** Any component that has a variable-length array of thermal coupling points — both HeatDiffusion's two sides and the upgraded ChannelAndContacts.

**Trade-offs:**
- Works correctly in MTK: `compose(sys, port_in, port_out, thermal_ports...)` handles array splatting.
- Named with `Symbol(:thermalL, i)` / `Symbol(:thermalR, i)` pattern — consistent with existing `Symbol(:thermal, i)`.
- `connect(hd.thermal_left[i], ch.thermal_left[i])` wiring in user assembly is clean and explicit.

**Example (HeatDiffusion left/right ports):**

```julia
thermal_left  = [ThermalPort(name=Symbol(:thermalL, j)) for j in 1:nz]
thermal_right = [ThermalPort(name=Symbol(:thermalR, j)) for j in 1:nz]

# Boundary condition equations (left face of plate → left channel cell)
for j in 1:nz
    push!(eqs, thermal_left[j].T  ~ T_wall_left[j])   # wall temp = surface temp
    push!(eqs, thermal_left[j].Q_flow ~ q_left[j])     # heat flowing to left channel
end

compose(System(eqs, t, all_vars, pars; name=name),
        thermal_left..., thermal_right...)
```

**Confidence:** HIGH — identical pattern confirmed working in ChannelAndContacts (Phase 9).

---

### Pattern 3: ChannelAndContacts Two-Sided Thermal Port Upgrade

**What:** Replace the single `thermal_ports[1:n]` array with two separate arrays `thermal_left[1:n]` and `thermal_right[1:n]`. The energy balance for cell `i` uses both.

**When to use:** When a channel can be heated from both sides (fuel plate on left, fuel plate on right, or one side adiabatic).

**MTK adiabatic default:** MTK's acausal semantics guarantee that an unconnected ThermalPort with `Q_flow` as a flow variable defaults to `Q_flow = 0` (no connections means the Kirchhoff sum at that port is zero). This means leaving one side unconnected naturally gives adiabatic behavior — no explicit `if` flag required.

**Trade-offs:**
- Breaking change: all existing tests that wire `thermal_ports[i]` must be updated to `thermal_left[i]`.
- Clean break is preferred over deprecation: there are no external users yet; maintaining both interfaces would complicate the energy balance equations.
- The energy balance gains one additional term but the structure is the same.

**New energy balance:**

```julia
# Per-cell energy balance with two-sided coupling
Dt(T[i]) ~ (mdot * cp_water(T[i]) * (T_up - T[i])
            + h_tc[i] * (π * Dh/2) * dz * (thermal_left[i].T  - T[i])
            + h_tc[i] * (π * Dh/2) * dz * (thermal_right[i].T - T[i]))
           / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
```

Note: the hydraulic perimeter split (π * Dh/2 per side vs. π * Dh total) depends on whether the channel geometry is a flat plate (two flat faces) vs. a round tube. For MTR flat plate channels, the wall area per side is `W * dz` (width × cell height). The exact geometry constants will be confirmed against Python STREAM Fuel/ChannelAndContacts geometry during implementation.

**Confidence:** HIGH for the pattern; MEDIUM for the exact perimeter split (needs validation against Python STREAM MTR reference).

---

### Pattern 4: FD Stencil Equations in a Double Loop

**What:** Generate all interior and boundary FD equations by iterating over the 2D grid in a nested `for i in 1:nx, j in 1:nz` loop. Push each equation to the `eqs` vector. Boundary conditions at the plate surfaces couple to the ThermalPort arrays.

**When to use:** For HeatDiffusion interior — this is how Python STREAM's `x_diffusion`/`xz_diffusion` functions are structured (loop over cells, apply stencil).

**The FD stencil for uniform grid (x-only diffusion, matching Python STREAM default):**

```
rho * cp * V_ij * dT[i,j]/dt = k * A_left  * (T[i,j-1] - T[i,j]) / dx
                                + k * A_right * (T[i,j+1] - T[i,j]) / dx
                                + P[i,j]   (power source)
```

Where boundary cells replace T[i,j-1] / T[i,j+1] with the wall temperature from the thermal port.

**Indexing convention (matches Python STREAM):**
- i = x-index (lateral, 1 = leftmost, nx = rightmost)
- j = z-index (axial, 1 = bottom/inlet, nz = top/outlet)
- thermal_left[j] couples to plate face at i=1, axial cell j
- thermal_right[j] couples to plate face at i=nx, axial cell j

**Confidence:** HIGH for the loop structure; MEDIUM for exact stencil coefficients for multi-layer plates with contact conductance (needs Python STREAM `_resistances()` logic review).

---

## Data Flow

### Coupled HeatDiffusion + ChannelAndContacts (Steady State)

```
Pump → HeatExchanger(T_bc) → ChannelAndContacts(left) → Pump (closed loop)
                                         |
                              thermal_left[1:nz]
                                         |
                              HeatDiffusion (plate)
                                         |
                              thermal_right[1:nz]
                                         |
                              ChannelAndContacts(right) → (optional second loop)
```

At each ThermalPort junction:
- MTK `connect(hd.thermal_left[j], ch_left.thermal_left[j])` generates:
  - `hd.thermal_left[j].T = ch_left.thermal_left[j].T` (temperature equality)
  - `hd.thermal_left[j].Q_flow + ch_left.thermal_left[j].Q_flow = 0` (energy balance at junction)

This means: what the plate "gives" at its left surface equals what the left channel "receives" at its left wall.

### State Variable Coupling

At steady state (mtkcompile removes time derivatives):

```
HeatDiffusion variables (ODEs become algebraic at SS):
  T[i,j]              — plate interior temperatures (nx * nz unknowns)
  T_wall_left[j]      — left surface temperatures (nz unknowns, algebraic)
  T_wall_right[j]     — right surface temperatures (nz unknowns, algebraic)
  q_left[j]           — left surface heat flux (nz unknowns)
  q_right[j]          — right surface heat flux (nz unknowns)

ChannelAndContacts(left) variables:
  T_cool_left[j]      — coolant temperatures (nz ODEs)
  h_tc_left[j]        — HTC (nz algebraic)
  thermal_left[j].T   — wall temperature seen by channel (= hd.thermal_left[j].T)
  thermal_left[j].Q_flow — heat entering channel from wall
```

### Key Data Flows

1. **Plate-to-channel heat:** `HeatDiffusion.q_left[j]` drives `ChannelAndContacts.thermal_left[j].Q_flow`. MTK's connect() enforces energy continuity.
2. **Channel-to-plate feedback:** `ChannelAndContacts.thermal_left[j].T` (coolant-side wall temperature) is the boundary condition for the leftmost plate cell row.
3. **Power source:** Volumetric power in the plate fuel meat drives `T[i,j]` upward; heat conducts laterally to both surfaces and into both channels.

---

## New Component: HeatDiffusion

### Interface Contract

```
HeatDiffusion(; name, nx, nz, Lx, Lz, Ly, rho_s, cp_s, k_s, power_total)

Ports:
  thermal_left[1:nz]   ThermalPort — left surface, axial cells 1..nz
  thermal_right[1:nz]  ThermalPort — right surface, axial cells 1..nz
  (no FlowPorts — solid component, no fluid flow)

Variables:
  T[1:nx, 1:nz](t)          — plate bulk temperatures (K)
  T_wall_left[1:nz](t)      — left surface temperatures (K), algebraic
  T_wall_right[1:nz](t)     — right surface temperatures (K), algebraic
  q_left[1:nz](t)           — left surface heat flux (W), observable
  q_right[1:nz](t)          — right surface heat flux (W), observable
  Q_total(t)                — total power deposited (W), observable

Parameters:
  nx, nz        — discretization (compile-time, not MTK parameters)
  Lx, Lz, Ly   — plate geometry (m)
  rho_s         — solid density (kg/m³)
  cp_s          — specific heat (J/kg/K)
  k_s           — thermal conductivity (W/m/K)
  power_total   — total power (W); uniform distribution default
```

### Wall Temperature Equation

The left surface temperature is related to the bulk temperature and the convective boundary condition via harmonic resistance (matching Python STREAM `h_to_wall` pattern):

```
T_wall_left[j] = (h_left[j] * thermal_left[j].T + k_s/(dx/2) * T[1,j])
                 / (h_left[j] + k_s/(dx/2))
```

Where `h_left[j]` is the HTC at the left wall face, obtained from `thermal_left[j].Q_flow / ((T_wall_left[j] - thermal_left[j].T) * A_face_j)`.

In practice for MTK: since `thermal_left[j].T` (the coolant-side wall temperature) is the MTK boundary condition, and `thermal_left[j].Q_flow` is the flow variable, the boundary equation for the outermost cell becomes:

```
q_left[j] ~ k_s * (T[1,j] - T_wall_left[j]) / (dx/2) * A_face_j
q_left[j] ~ -thermal_left[j].Q_flow   (energy balance at port)
T_wall_left[j] ~ thermal_left[j].T    (temperature equality via connect())
```

The exact form will be confirmed during implementation to match Python STREAM `wall_temperature()` function behavior.

---

## Modified Component: ChannelAndContacts (Breaking Change)

### Change Summary

| Before (v0.2) | After (v0.3) |
|---------------|--------------|
| `thermal_ports[1:n]` | `thermal_left[1:n]` + `thermal_right[1:n]` |
| Single-sided energy balance | Two-sided energy balance |
| `q_wall[i] ~ thermal_ports[i].Q_flow` | `q_wall_left[i] ~ thermal_left[i].Q_flow` + `q_wall_right[i] ~ thermal_right[i].Q_flow` |
| Named `thermal1..thermalN` | Named `thermalL1..thermalLN` + `thermalR1..thermalRN` |

### Migration Impact

All tests in Phase 9 (THERM-01) that access `ch.thermal1`, etc., must be updated. There are no external consumers yet. Clean break is the right choice.

### Adiabatic Default

Leaving `thermal_right[i]` unconnected → `thermal_right[i].Q_flow = 0` by MTK flow variable semantics. No model change needed for one-sided heating. This is tested by single-channel cases.

---

## Integration Points

### New Component → Existing Infrastructure

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `HeatDiffusion.thermal_left[j]` ↔ `ChannelAndContacts.thermal_left[j]` | MTK `connect()` acausal | Core v0.3 coupling; j = axial cell index (1..nz = 1..n, must match) |
| `HeatDiffusion.thermal_right[j]` ↔ `ChannelAndContacts.thermal_right[j]` | MTK `connect()` acausal | Second channel coupling; unconnected = adiabatic |
| `HeatDiffusion` internal T[i,j] | Self-contained FD stencil | No ports for interior cells; only surfaces exposed |
| `ChannelAndContacts.thermal_left[j].T` | ThermalPort across variable | Acts as Dirichlet BC for leftmost plate cell row |

### File Inclusion Order in STREAM.jl

The current `STREAM.jl` includes:
```
fluids.jl → connectors.jl → components.jl → solvers.jl
```

The new file must be included after `connectors.jl` (needs ThermalPort) and before `solvers.jl` (build helpers may reference HeatDiffusion):

```
fluids.jl → connectors.jl → components.jl → heat_diffusion.jl → solvers.jl
```

---

## Build Order

The dependencies between v0.3 work items, and the recommended phase sequence:

### Phase 10: Tech Debt + ChannelAndContacts Upgrade

**Step 1 — v0.2 tech debt (no dependencies):**
- Remove dead `t_inlet` parameter from `_channel_base_eqs`
- Add direct THERM-03 assertion
- Fix cosmetic doc issue

**Step 2 — ChannelAndContacts breaking change:**
- Replace `thermal_ports[1:n]` with `thermal_left[1:n]` + `thermal_right[1:n]`
- Update energy balance equation
- Update `all_vars` and `compose()` call
- Update THERM-01 tests
- Verify single-channel adiabatic behavior (unconnected side = zero Q_flow)

Rationale: Do this before HeatDiffusion. Getting the interface right on the channel side means HeatDiffusion can be written against a stable port contract. Reversing the order forces HeatDiffusion to be revised if channel ports change.

### Phase 11: HeatDiffusion Component (x-only diffusion, uniform plate)

**Step 1 — `src/heat_diffusion.jl` skeleton:**
- HeatDiffusion function with thermal_left/right port arrays
- 1D x-diffusion stencil only (no z-diffusion initially — matches Python STREAM `x_diffusion` default)
- Uniform power distribution; uniform material properties
- Compile check: `mtkcompile(hd; fully_determined=false)`

**Step 2 — HDIFF tests:**
- HDIFF-01: callable, mtkcompile passes
- HDIFF-02: port count (2 * nz ThermalPort subsystems)
- HDIFF-03: energy balance check (total power in = sum of surface Q_flow at steady state)
- HDIFF-04: symmetric uniform plate, both sides connected to same T_wall → T_center symmetric

Rationale: 1D x-diffusion first because (a) it is the Python STREAM default, (b) it tests the port coupling independently of z-diffusion complexity, (c) it's sufficient for the MTR validation case.

### Phase 12: Coupled System + MTR Validation

**Step 1 — `build_mtr_loop` helper in `solvers.jl`:**
- Wires: Pump → HeatExchanger(T_bc) → ChannelAndContacts (left) → Pump
- Wires: ChannelAndContacts (left) thermal_left ↔ HeatDiffusion thermal_left
- Optional right channel

**Step 2 — VAL-03 validation:**
- Solve coupled system to steady state
- Compare T_wall_left, T_wall_right, T_center, T_outlet against Python STREAM MTR reference
- Tolerance: <1% for temperatures (consistent with VAL-01, VAL-02)

**Step 3 — Asymmetric test:**
- Different T_inlet or mdot on left vs. right channel
- Verifies asymmetric heat split works without model changes

### Phase 13: xz-Diffusion (Optional, if MTR case requires it)

Add z-direction diffusion to HeatDiffusion if the MTR validation shows discrepancy attributable to axial conduction. Python STREAM supports `xz_diffusion` but uses `x_diffusion` as the default for flat plates where axial conduction is negligible. Defer until Phase 12 validation results are available.

---

## Anti-Patterns

### Anti-Pattern 1: Single `thermal_ports[1:n]` for Two-Sided Coupling

**What people do:** Try to add a second set of ports named `thermal_ports_right[1:n]` while keeping the existing `thermal_ports[1:n]` for backward compatibility.

**Why it's wrong:** Creates ambiguity about what "thermal_ports" means. Tests written against the old interface will pass but be testing the wrong behavior. The existing `thermal_ports` array already covers only one side; keeping both creates a confusing asymmetry.

**Do this instead:** Make a clean break. Rename both arrays to `thermal_left` and `thermal_right`. Update all test references in one commit. The codebase has no external consumers.

---

### Anti-Pattern 2: Storing Material Properties as MTK Parameters in HeatDiffusion

**What people do:** Declare `rho_s`, `cp_s`, `k_s` as MTK `@parameters` so they appear in the compiled system.

**Why it's wrong:** Solid material properties are never time-varying and never need to be swept via MTK's parameter interface. Making them MTK parameters adds symbolic overhead during mtkcompile for no benefit. Python STREAM's `Solid` dataclass stores them as plain scalars for the same reason.

**Do this instead:** Pass as plain Julia `Float64` arguments to the HeatDiffusion constructor. Compute `dx`, `dz`, `A_face`, `V_cell`, `rho_cp_V` as concrete values inside the function. Only embed them into equations as numeric literals.

---

### Anti-Pattern 3: Generating FD Stencil with ifelse() for Boundary Detection

**What people do:** Write a single loop `for i in 1:nx, j in 1:nz` that uses `ifelse(i==1, thermal_left[j].T, T[i-1,j])` to select boundary vs. interior cells.

**Why it's wrong:** MTK's symbolic `ifelse()` inside equations creates non-smooth Jacobian entries that can degrade IDA solver convergence. It also makes the structure less transparent to `structural_simplify`.

**Do this instead:** Use explicit loop bounds: handle the left boundary (`i == 1`) separately, the interior (`2 <= i <= nx-1`) in a nested loop, and the right boundary (`i == nx`) separately. Three separate code blocks — clear and solver-friendly.

---

### Anti-Pattern 4: Flattening 2D Variables to 1D with Manual Index Arithmetic

**What people do:** Declare `(T(t))[1:nx*nz]` and compute 2D indices as `T[j + (i-1)*nz]`.

**Why it's wrong:** The existing codebase uses `(T(t))[1:n]` for 1D and MTK supports `(T(t))[1:nx, 1:nz]` for 2D. Manual flattening makes the equation loop harder to read and error-prone (row-major vs column-major confusion).

**Do this instead:** Use `(T(t))[1:nx, 1:nz]` natively. Use `vec(collect(T))` to flatten for `all_vars`. Access as `T[i,j]` in equations.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| nx=3, nz=10 (typical MTR) | 30 plate ODEs + 20 channel ODEs = ~50 total differential states; mtkcompile < 5s expected |
| nx=10, nz=20 | 200 plate ODEs + 40 channel ODEs = ~240 states; still fast; Jacobian is sparse tridiagonal |
| nx=50, nz=100 | 5,000 plate ODEs; mtkcompile may reach 60-120s; use `sparse=true` in ODEProblem |
| nx>100, nz>100 | 10,000+ equations; MTK compile time becomes a bottleneck; consider MethodOfLines.jl or handwritten Jacobian |

For v0.3 (MTR validation), nx=3 (cladding/meat/cladding) and nz=10–20 is sufficient. This is well within the comfortable MTK range.

**Sparse Jacobian:** MTK can generate sparse analytical Jacobians automatically. For FD systems with banded structure, enabling sparse Jacobian in the ODEProblem is a straightforward optimization if needed: `ODEProblem(ssys, op, tspan; jac=true, sparse=true)`.

---

## Sources

- Direct code inspection: `/home/itay/projects/Julia-STREAM/src/components.jl` — ChannelAndContacts pattern (ThermalPort array splat into compose, per-cell energy balance loop, `collect(T)` in all_vars)
- Direct code inspection: `/home/itay/projects/Julia-STREAM/src/connectors.jl` — ThermalPort Q_flow as Flow variable (acausal semantics, sum=0 at junction)
- Direct code inspection: `/home/itay/projects/STREAM/stream/calculations/heat_diffusion.py` — Python STREAM Fuel class (x_diffusion default, wall temperature equations, T_wall_left/T_wall_right variables, power_shape)
- Direct code inspection: `/home/itay/projects/STREAM/.claude/skills/stream-developer/architecture.md` — Fuel internal structure (Variables: T[0:m*n], T_wall_left, T_wall_right; length = (2 + n_cols) * n_rows)
- MTK documentation: [FAQ — Array Variables](https://docs.sciml.ai/ModelingToolkit/stable/basics/FAQ/) — `@parameters p[1:n, 1:m]::T` syntax confirmed; same applies to variables
- MTK documentation: [ODE Modeling Tutorial](https://docs.sciml.ai/ModelingToolkit/stable/tutorials/ode_modeling/) — notes array variables are possible but "cleaner treatment is still a work in progress"
- Julia Discourse: [Different ways to access array of variables](https://discourse.julialang.org/t/modelingtoolkit-different-ways-to-access-array-of-variables/59939) — `@variables x[1:N](t)` confirmed syntax; array overhaul merged by mid-2021
- SciML Discourse: [MTK performance for large models](https://discourse.julialang.org/t/modelingtoolkit-jl-performance-for-large-models-with-similar-components/82442) — comfortable up to ~10,000 DAEs; compile time is the bottleneck at scale

---

*Architecture research for: HeatDiffusion + two-sided ChannelAndContacts integration in STREAM.jl v0.3*
*Researched: 2026-03-13*
