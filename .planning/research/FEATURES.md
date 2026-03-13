# Feature Landscape

**Domain:** 2D finite-difference fuel plate + two-sided channel coupling for nuclear thermal-hydraulics (MTR reactor geometry)
**Researched:** 2026-03-13
**Sources:** Python STREAM `heat_diffusion.py`, `channel.py`, `mtr_geometry.py`, `test_heat.py`, `test_integrations.py`, Julia-STREAM `components.jl`, `PROJECT.md`

---

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| HeatDiffusion: 2D indexed MTK state `T(t)[1:nx, 1:nz]` | Core of v0.3; without this there is no fuel plate | High | MTK indexed vars over 2D grid; this is the new MTK pattern for this codebase |
| x-direction diffusion (across plate thickness) | Dominant heat path in flat fuel plate; without it plate is isothermal in x | Medium | Standard FVM cell-face flux: `(T[i,j+1] - T[i,j]) / (dx[j]/2k + dx[j+1]/2k)` |
| z-direction diffusion (axial, along channel) | Required for correct axial temperature distribution; becomes significant at coarse mesh | Medium | Same FVM pattern; already present in Python `xz_diffusion` |
| Uniform volumetric power source `q_gen` | Needed to drive temperature field; without it plate is passive | Low | Scalar or array per-cell; uniform is simplest and sufficient for MTR reference case |
| `thermal_left[1:nz]` ThermalPort array | Interface contract to left channel; required for coupling | High | Per-cell port array, same pattern as existing `ChannelAndContacts.thermal_ports[1:n]` |
| `thermal_right[1:nz]` ThermalPort array | Interface contract to right channel; required for MTR (two-sided) | High | Symmetric to left; MTK acausal semantics handle unconnected side automatically |
| ChannelAndContacts upgraded to `thermal_left[1:n]` + `thermal_right[1:n]` | Existing single-port design only supports one-sided coupling; MTR requires two-sided | Medium | Replace `thermal_ports[1:n]` with two arrays; `q_wall[i] = thermal_left[i].Q_flow + thermal_right[i].Q_flow` |
| Adiabatic default for unconnected ThermalPort | One-sided test cases (channel on only one side) must work without explicit flags | Low | MTK acausal semantics: unconnected port has Q_flow=0 by default; no code needed |
| MTR reference case: HeatDiffusion + ChannelAndContacts matches Python STREAM | Validation is the milestone exit criterion | High | Geometry: cladding + fuel meat + cladding; light water channels on both sides |

---

## Differentiators

Features that set this product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| MTK symbolic Jacobian for 2D PDE | Sundials IDA can use analytical Jacobian, dramatically improving convergence on stiff fuel-coolant problems | Medium | MTK generates Jacobian automatically via mtkcompile; no extra user effort |
| Asymmetric left/right heating | Two independent channels with different BCs on each side of a plate; not possible with single-port design | Low | Emerges automatically from two-port design; no extra equations needed |
| Uniform grid + non-uniform grid support | Non-uniform x-spacing allows fine mesh at clad-meat interface without blowing up cell count | Medium | Python STREAM supports this; `dx[j]` varies per cell in resistance formula |
| Multi-layer material (cladding + meat) | Realistic MTR geometry has different conductivity in clad vs meat; single-material model gives wrong peak temperature | Medium | Implemented as per-cell `k[i,j]`; harmonic mean of conductivities at cell face |

---

## Anti-Features

Features to explicitly NOT build in v0.3.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Point kinetics coupling | Fully out of scope for v0.3; adds neutronics complexity before thermal-hydraulic architecture is proven | Keep in v0.4+ backlog |
| Polar / cylindrical geometry (rz_diffusion) | MTR fuel plates are flat Cartesian; cylindrical is for pin-type fuel; adds complexity with no validation target | Defer; Python STREAM already has it as a model |
| Additional HTC correlations (laminar, Marco-Han) | Dittus-Boelter is validated and sufficient for MTR turbulent regime | Add in v0.4+ with the correlation library |
| Z-direction adiabatic wall BCs as explicit parameters | Top/bottom adiabatic is always the assumption for MTR plates; explicit flag adds API surface with no current need | Adiabatic is implicit: no axial ThermalPorts declared |
| Power shape profiling (cosine, non-uniform) | Uniform q_gen is sufficient for reference case validation; profiling is a display feature | Defer to v0.4+; add as optional power_shape array |
| Wrapper struct for solution (SteadySolution, TransientSolution) | ODESolution is sufficient; PROJECT.md explicitly defers this | Do not add |
| Subcooled boiling, natural convection | Not in scope through v0.3; no validation target | Out of scope |

---

## Feature Dependencies

```
thermal_left[1:nz] + thermal_right[1:nz] on HeatDiffusion
    → thermal_left[1:n] + thermal_right[1:n] on ChannelAndContacts (must be upgraded first or together)

ChannelAndContacts two-sided upgrade
    → depends on existing thermal_ports[1:n] pattern (already built in v0.2)
    → q_wall[i] = thermal_left[i].Q_flow + thermal_right[i].Q_flow replaces q_wall[i] ~ thermal_ports[i].Q_flow

HeatDiffusion x-diffusion
    → requires per-cell conductivity k[i,j] (scalar or 2D array parameter)
    → requires cell boundary geometry dx[1:nx], dz[1:nz]

HeatDiffusion z-diffusion
    → depends on x-diffusion infrastructure; adds z-face fluxes on top

MTR reference case validation
    → depends on HeatDiffusion (both x and z diffusion)
    → depends on ChannelAndContacts two-sided upgrade
    → depends on Python STREAM MTR reference outputs (generate_reference.py)

v0.2 tech debt cleanup
    → independent of HeatDiffusion; can be done in any phase order
    → items: dead t_inlet parameter, THERM-03 direct assertion, doc cosmetic
```

---

## MVP Recommendation

The minimum that delivers a complete, validated v0.3:

1. **ChannelAndContacts two-sided upgrade** — Replace `thermal_ports[1:n]` with `thermal_left[1:n]` + `thermal_right[1:n]`. This is the interface contract. All downstream work depends on it.

2. **HeatDiffusion with x-diffusion only** — Implement the component with `T(t)[1:nx, 1:nz]`, x-direction diffusion, uniform `q_gen`, and two-sided ThermalPort arrays. Start with x-diffusion only (matching Python STREAM's `x_diffusion` default). This is sufficient for the MTR reference case where axial diffusion is secondary.

3. **MTR reference case validation** — Wire HeatDiffusion + two ChannelAndContacts into the MTR geometry (cladding+meat+cladding, two water channels) and compare against Python STREAM outputs within 1% steady-state.

4. **v0.2 tech debt cleanup** — Three small items with no correctness impact; bundle into an early phase to clear the slate.

**Defer in v0.3:** z-direction diffusion is a differentiator but not required for the reference case validation. Implement after the x-only model passes validation, then add z-diffusion and re-validate to confirm the axial contribution is small (as expected for thin plates). This staged approach de-risks the MTK 2D indexed variable implementation.

---

## Boundary Condition Details

Sourced from Python STREAM `Fuel.calculate()` and `generic_2d_diffusion`:

**Left/right walls (x-direction):** Coupled to coolant channels via ThermalPort. Heat flux at boundary cell face:

```
q_face = (T_coolant - T[i, boundary]) / r_boundary
r_boundary = dx_boundary / (2 * k_boundary)  +  1 / h_tc[i]
```

In MTK acausal form: `thermal_left[i].Q_flow` is the total heat flow into cell `(i, 1)` from the left channel. The HTC is carried by the channel's `h_tc[i]` variable and the ThermalPort carries `T` (wall temperature). This is the same contract as the existing single-sided `thermal_ports[i]`.

**Top/bottom walls (z-direction):** Adiabatic — not modeled as ThermalPorts. No flux term added at z=1 and z=nz faces. This is enforced implicitly by having no axial ThermalPort array on HeatDiffusion.

**Internal faces:** Standard FVM: conductance = `2 * k_left * k_right / (k_left * dx_right + k_right * dx_left)` (harmonic mean weighted by cell size). Python STREAM uses `r_{ij,ij+1} = dx[j]/2k[j] + dx[j+1]/2k[j+1]`.

**Multi-material contacts (cladding-meat interface):** Python STREAM supports a `x_contacts` array with HTC at each cell face. For Julia-STREAM v0.3, start with `x_contacts = inf` (perfect thermal contact) — this is the Python STREAM default and is sufficient for validation unless the reference case explicitly tests contact resistance.

---

## Discretization Scheme

Sourced from Python STREAM `heat_diffusion.py` module docstring and `generic_2d_diffusion`:

**Time derivative (ODE form for MTK):**
```
rho * cp * dT[i,j]/dt = (conduction_x_in - conduction_x_out) / V[i,j]
                       + (conduction_z_in - conduction_z_out) / V[i,j]
                       + q_gen[i,j]
```

**Cell volume:** `V[i,j] = dx[j] * dz[i] * y_length` (Cartesian)

**Heat flux at face:** `q_face = dT_across_face / R_face`, where `R_face` is the thermal resistance (sum of half-cell resistances from both sides).

**Boundary flux (left wall, cell j=1):**
```
R_left_boundary = dx[1] / (2 * k[i,1])   # half-cell resistance
# h_tc[i] contributes via ThermalPort coupling in ChannelAndContacts
```

**Indexing convention (following Python STREAM):**
- `i` = axial index (z-direction, 1..nz), matches channel cell index
- `j` = lateral index (x-direction, 1..nx), from left wall to right wall
- `T[i,j]` = MTK indexed variable at cell (i,j)
- `thermal_left[i]` couples to cell `(i, 1)` left face
- `thermal_right[i]` couples to cell `(i, nx)` right face

---

## Validation Pattern

Sourced from Python STREAM `test_heat.py` and `test_integrations.py`:

| Test | What It Checks | Inputs | Expected Outputs |
|------|---------------|--------|-----------------|
| Uniform temperature, zero power → dT/dt = 0 | No spurious fluxes from discretization | T uniform everywhere, power=0 | All derivatives = 0 |
| One cell, known T_left, T_right, k → analytic dT/dt | Stencil correctness | Single cell, infinite HTC walls | `dT = (T_left + T_right - 2*T) * 2k / dx` |
| Steady-state with zero power → T = T_coolant | Adiabatic limit | power=0, T_left=T_right=T_cool | All T converge to T_cool |
| Energy balance: outgoing flux = power | Conservation check | Uniform power, steady state | Sum of wall heat flows = total power |
| MTR reference case vs Python STREAM | End-to-end validation | MTR geometry, light water, known mdot/power | T_coolant, T_wall, T_fuel within 1% |

---

## Sources

- Python STREAM `stream/calculations/heat_diffusion.py` — canonical `Fuel` class; `x_diffusion`, `xz_diffusion`, `generic_2d_diffusion` (HIGH confidence — primary reference implementation)
- Python STREAM `stream/calculations/channel.py` — `ChannelAndContacts` with `h_left/h_right` two-sided design (HIGH confidence)
- Python STREAM `stream/composition/mtr_geometry.py` — `plate()` and `chain_fuels_channels()` show the coupling graph; directed edges carry `T_left/T_right/h_left/h_right` (HIGH confidence)
- Python STREAM `tests/test_calculations/test_heat.py` — validation test patterns (HIGH confidence)
- Python STREAM `tests/test_general/conftest.py` — `MTR_fuel_and_channel` fixture with actual MTR geometry (HIGH confidence)
- Julia-STREAM `src/components.jl` — existing `ChannelAndContacts` implementation to be upgraded (HIGH confidence)
- Julia-STREAM `.planning/PROJECT.md` — v0.3 scope and requirements (HIGH confidence)
