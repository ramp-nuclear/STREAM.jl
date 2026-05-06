# Phase 12: MTR Validation - Research

**Researched:** 2026-03-14
**Domain:** MTK coupled system assembly (HeatDiffusion + two ChannelAndContacts), Python STREAM MTR reference script authorship, steady-state solve of a two-loop system
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- New file: `test/generate_mtr_reference.py` (separate from `generate_reference.py`)
- Python API: Uses `plate(channel_l, channel_r, fuel)` from `stream.composition.mtr_geometry`
- Output: Prints hardcodable constants to stdout (same convention as `generate_reference.py`). Run once manually, copy into `runtests.jl`.
- Scope: All three scenarios in one script — symmetric (VAL-01), asymmetric (VAL-02), one-sided (VAL-03)
- Gravity: `g=0` in both channels (same as existing `generate_reference.py`; horizontal flow)
- Plate model: Single uniform `HeatDiffusion` — no cladding/meat differentiation in v0.3
- Plate dimensions: `nz=10, nx=3, Lz=0.6m, Lx=0.00127m (1.27mm), y=0.07m`
- Plate material (aluminum cladding): `rho_s=2700.0, cp_s=900.0, k_s=200.0`
- Power: `power=1e4` W (10 kW) for all validation cases
- `power_shape`: Uniform `fill(1.0/(nz*nx), nz, nx)` for VAL-01/02/03
- `nz=10 matches Channel n=10`: 1:1 axial cell coupling, no interpolation needed
- Both channels: identical geometry — `D=0.01m, L=0.6m, n=10, dP=30kPa`
- Topology: Two independent loops, one per channel: `Pump → HeatExchanger → ChannelAndContacts → Pump`
- HeatExchanger pins inlet temperature (same role as TempBC in existing VAL-01)
- Gravity: `g_acc=0` in both Julia `ChannelAndContacts` components
- T_inlet (symmetric): `313.15 K (40°C)` on both sides
- VAL-02: Left channel HeatExchanger outlet: `313.15 K`; Right: `363.15 K` (+50 K)
- VAL-03: `HeatDiffusion.thermal_left[i]` connected to channel; `thermal_right` unconnected (adiabatic)
- Python VAL-03 reference: `one_sided_connection(channel, fuel, fuel_side="left")`
- Outputs compared (within 1%): T_outlet, mdot for connected channels; T_plate center cell
- Non-uniform power_shape test: `nz=1, nx=3`, `power_shape = [0.5, 0.0, 0.5]` (zero center), pinned BCs via ConstantTemperature
- Test location: New `@testset "STREAM Phase 12 Tests"` block in `test/runtests.jl`, following Phase 11 block
- Reference constants hardcoded from `generate_mtr_reference.py` output

### Claude's Discretion

- Exact initial condition (`u0`) guess values for the coupled system solve
- Whether to use `mtkcompile(sys; fully_determined=true)` or `false` for the coupled system
- Variable access pattern for `T_outlet` (ChannelAndContacts cell temperature indexing)
- Order of connect() calls for assembling the two-loop MTR topology

### Deferred Ideas (OUT OF SCOPE)

- `symmetric_plate(channel, fuel)` Julia convenience function — v0.4
- Composable subsystem assembly — v0.4
- Multi-material `HeatDiffusion` — past v0.4
- Cosine axial `power_shape` — future
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VAL-01 | Coupled HeatDiffusion + two ChannelAndContacts in MTR geometry produces steady-state T_outlet and T_plate matching Python STREAM reference within 1% | Python `plate()` API documented; Julia wiring pattern established from THERM-03 and Phase 11; initial condition strategy identified |
| VAL-02 | Asymmetric left/right heating produces correct non-symmetric plate temperature profile | Same MTK system; only HeatExchanger T_bc parameter differs; Python `plate()` run with different inlet T values |
| VAL-03 | One-sided coupling solves correctly with unconnected face adiabatic | Python `one_sided_connection(channel, fuel, fuel_side="left")` API documented; Julia: connect only thermal_left[i] ports, leave thermal_right unconnected — HDIFF-05 already validates this mechanically |
</phase_requirements>

---

## Summary

Phase 12 is a pure validation phase. All components (`HeatDiffusion`, `ChannelAndContacts`, `Pump`, `HeatExchanger`) are already implemented and tested individually. The work is: (1) write a Python STREAM MTR reference script for three scenarios, (2) assemble the Julia two-loop coupled system, (3) solve it and compare against the reference constants, and (4) add the non-uniform `power_shape` behavioral test that closes the HDIFF-03 coverage gap.

The Python STREAM MTR reference script uses `plate(channel_l, channel_r, fuel)` from `stream.composition.mtr_geometry` and follows the same pattern as the existing `generate_reference.py`. The `Fuel` class from `stream.calculations.heat_diffusion` accepts `z_boundaries`, `x_boundaries`, `material` (Solid), `y_length`, and `power_shape`. The `FlowGraph` wraps each channel in its own loop with a Pump and HeatExchanger.

The Julia assembly pattern is a direct extension of the THERM-03 two-sided coupling test. The two independent hydraulic loops are each `Pump → HeatExchanger → ChannelAndContacts → Pump`. The plate is connected axially: `connect(hd.thermal_left[i], cac_l.thermal_left[i])` and `connect(hd.thermal_right[i], cac_r.thermal_left[i])` for `i in 1:nz`, using the established `getproperty(sys, Symbol(:thermal_left, i))` pattern.

**Primary recommendation:** Build the reference script first (run it, copy constants), then write the Julia test — this prevents iteration on both sides simultaneously.

---

## Standard Stack

### Core (already present in project — no new installs)

| Component | Version | Purpose | Source |
|-----------|---------|---------|--------|
| ModelingToolkit.jl | current | Acausal ODE system assembly | Julia-STREAM src/ |
| DifferentialEquations.jl | current | SSRootfind + KINSOL for steady-state | Julia-STREAM solvers.jl |
| Sundials.jl | current | KINSOL nonlinear solver | Julia-STREAM solvers.jl |
| Python STREAM | local ~/projects/STREAM | MTR reference: plate(), one_sided_connection(), Fuel, FlowGraph | STREAM codebase |

### Python STREAM Key Imports for generate_mtr_reference.py

```python
from stream.calculations import Pump, HeatExchanger
from stream.calculations.channel import ChannelAndContacts
from stream.calculations.heat_diffusion import Fuel, Solid, x_diffusion
from stream.composition.mtr_geometry import plate, one_sided_connection
from stream.composition.cycle import FlowGraph, flow_edge
from stream.pipe_geometry import EffectivePipe
from stream.substances import light_water
from stream.jacobians import ALG_jacobian
from stream.physical_models.pressure_drop import pressure_diff
from functools import partial
import numpy as np
```

---

## Architecture Patterns

### Pattern 1: Two-Loop MTR Assembly in Julia

The two-channel MTR topology uses two completely independent `FlowGraph`-like loops (Pump + HX + CAC), both feeding into a single shared `HeatDiffusion`. This is the Julia analog of the Python `plate()` function.

```
Loop L: pump_l → hx_l → cac_l → pump_l (closed)
Loop R: pump_r → hx_r → cac_r → pump_r (closed)
Plate connections: hd.thermal_left[i]  ↔ cac_l.thermal_left[i]   (i=1:nz)
                  hd.thermal_right[i]  ↔ cac_r.thermal_left[i]   (i=1:nz)
```

Note: `cac_r` (right channel) exposes its `thermal_left[i]` face toward the plate, which connects to `hd.thermal_right[i]`. This is correct because from the right channel's perspective, the plate is on its "left" side.

**Key insight from CONTEXT.md (confirmed in THERM-03):** The established port access pattern is:
```julia
connect(getproperty(hd, Symbol(:thermal_left, i)),
        getproperty(cac_l, Symbol(:thermal_left, i)))
```
The `sys.thermal_left[i]` syntax fails in `connect()` calls — only `getproperty` works.

### Pattern 2: Full MTR System Composition

```julia
@named pump_l  = Pump(dP_pump=3.0e4)
@named hx_l    = HeatExchanger(T_bc=313.15)
@named cac_l   = ChannelAndContacts(n=10, L=0.6, D=0.01, A=7.85e-5)
@named pump_r  = Pump(dP_pump=3.0e4)
@named hx_r    = HeatExchanger(T_bc=313.15)   # 363.15 for VAL-02
@named cac_r   = ChannelAndContacts(n=10, L=0.6, D=0.01, A=7.85e-5)
ps = fill(1.0 / (nz * nx), nz, nx)
@named hd      = HeatDiffusion(nz=10, nx=3, Lz=0.6, Lx=0.00127, y=0.07,
                                rho_s=2700.0, cp_s=900.0, k_s=200.0,
                                power_shape=ps, power=1e4)

conns = [
    # Left loop
    connect(pump_l.outlet, hx_l.inlet),
    connect(hx_l.outlet, cac_l.inlet),
    connect(cac_l.outlet, pump_l.inlet),
    pump_l.inlet.P ~ 1.0e5,
    cac_l.inlet.T ~ 313.15,
    # Right loop
    connect(pump_r.outlet, hx_r.inlet),
    connect(hx_r.outlet, cac_r.inlet),
    connect(cac_r.outlet, pump_r.inlet),
    pump_r.inlet.P ~ 1.0e5,
    cac_r.inlet.T ~ 313.15,   # 363.15 for VAL-02
    # Plate-channel coupling
    [connect(getproperty(hd, Symbol(:thermal_left,  i)),
             getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
    [connect(getproperty(hd, Symbol(:thermal_right, i)),
             getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
]
@named sys = compose(System(conns, t; name=:mtr_sys),
                     pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
ssys = mtkcompile(sys; fully_determined=false)
```

### Pattern 3: Python STREAM MTR Reference Script Structure

Following the style of the existing `generate_reference.py`:

```python
# --- Geometry ---
nz, nx = 10, 3
Lz, Lx, y = 0.6, 0.00127, 0.07
z_bounds = np.linspace(0, Lz, nz + 1)
x_bounds = np.linspace(0, Lx, nx + 1)

material = Solid(density=2700.0, specific_heat=900.0, conductivity=200.0)
power_shape = np.ones((nz, nx)) / (nz * nx)   # uniform, normalized

fuel = Fuel(
    z_boundaries=z_bounds,
    x_boundaries=x_bounds,
    material=material,
    y_length=y,
    power_shape=power_shape,
    name="Fuel",
)

pipe_ch = EffectivePipe.circular(length=Lz, diameter=0.01)
channel_l = ChannelAndContacts(
    z_boundaries=z_bounds,
    fluid=light_water,
    pipe=pipe_ch,
    pressure_func=partial(pressure_diff, g=0),
    name="ChannelL",
)
channel_r = ChannelAndContacts(  # identical geometry
    z_boundaries=z_bounds,
    fluid=light_water,
    pipe=pipe_ch,
    pressure_func=partial(pressure_diff, g=0),
    name="ChannelR",
)

pump_l = Pump(pressure=3.0e4)
pump_r = Pump(pressure=3.0e4)
hx_l = HeatExchanger(outlet=40.0, name="HX_L")   # 40°C (VAL-01); 90°C for right in VAL-02
hx_r = HeatExchanger(outlet=40.0, name="HX_R")

# --- VAL-01: Symmetric coupling via plate() ---
cg = plate(channel_l, channel_r, fuel)
fg = FlowGraph(
    flow_edge(("A_L", "B_L"), pump_l, hx_l),
    flow_edge(("B_L", "A_L"), channel_l),
    flow_edge(("A_R", "B_R"), pump_r, hx_r),
    flow_edge(("B_R", "A_R"), channel_r),
    # Thermal coupling provided via cg (CalculationGraph) — see FlowGraph docs
    funcs={fuel: dict(power=1e4), ...},
    reference_node=("A_L", 1e5),
    abs_pressure_comps=[channel_l, channel_r],
)
```

**Important:** The Python STREAM FlowGraph integration with a CalculationGraph (for thermal coupling) works differently from pure hydraulic loops. Research below clarifies the exact call pattern.

### Pattern 4: Python `plate()` Integration with FlowGraph

Inspecting `mtr_geometry.py` and `generate_reference.py` patterns, the `plate()` function returns a `CalculationGraph` (thermal DAG). This is combined with the hydraulic `FlowGraph` via the `CalculationGraph` addition protocol (Python STREAM's composability). The aggregator then solves the coupled thermal-hydraulic system.

The exact API to feed power and solve for all three scenarios is documented in `tests/test_general/test_integrations.py` and `stream/composition/constructors.py`. The reference script should use the same pattern as `generate_reference.py` but with a `CalculationGraph` (returned by `plate()`) passed to the aggregator, plus separate power funcs for the fuel.

**Recommended approach for generate_mtr_reference.py:** Look at how the Python STREAM tests construct coupled thermal-hydraulic systems with `plate()`. The simplest approach given time constraints: use the `CalculationGraph` addition `+` operator, which is the documented compositional API.

### Pattern 5: Initial Conditions for Coupled Solve

From Phase 11 experience (HDIFF-02/03 test and CHAN-03 one-sided):

- Channel T cells: `steady_state_guess(T_inlet, Q_wall, mdot_guess, n)` — Q_wall per channel is ~5 kW (half of 10 kW)
- Channel `inlet.mdot`: ~0.490 kg/s (same as all prior tests)
- Channel `Re[i]`, `Nu[i]`, `h_tc[i]`: need explicit guesses for `fully_determined=false` solve
  - Re ~ 3e5, Nu ~ 800, h_tc ~ 2.7e4 (from CHAN-03 experience)
- HeatDiffusion `T[i,j]`: `T_inlet + 5.0` (slightly above coolant inlet)
- For VAL-02 (asymmetric): right-side channel T cells start at `363.15 + delta`

### Anti-Patterns to Avoid

- **Connecting `cac_r.thermal_right[i]` instead of `cac_r.thermal_left[i]`**: The right channel sees the plate on its LEFT side (thermal_left). Connecting thermal_right would reverse the coupling direction — VAL-02 exists precisely to catch this swap.
- **Using `sys.thermal_left[i]` syntax in connect()**: Fails for array-indexed ports in MTK. Must use `getproperty(sys, Symbol(:thermal_left, i))`.
- **Forgetting `inlet.T ~ T_inlet` constraints**: The two-sided CAC system in THERM-03 used `cac.inlet.T ~ T_inlet`. Without this, the circular stream temperature can prevent convergence.
- **Skipping Re/Nu/h_tc guesses in one-sided (VAL-03) solve**: CHAN-03 showed that `fully_determined=false` + one unconnected side requires explicit algebraic var guesses to break the MTK initialization cycle.
- **Running `mtkcompile(sys)` (fully_determined=true) without checking**: The two-loop system may be determined with both sides connected; one-sided (VAL-03) almost certainly requires `fully_determined=false`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MTR reference values | Manual analytical calculation | Python STREAM `plate()` + `FlowGraph` | Python STREAM is the source of truth; manual calc would introduce different discretization |
| Q_flow sign correction | Negation wrapper | MTK acausal connect() | The sign asymmetry (thermal_left Q_flow > 0, thermal_right Q_flow < 0) is already embedded in `_diffusion_eqs`; the channel's `thermal_left[i].Q_flow` equation is also sign-consistent |
| Port array access loop | `sys.thermal_left[i]` | `getproperty(sys, Symbol(:thermal_left, i))` | MTK array port access requires named subsystem lookup, not bracket indexing |
| Initial guess computation | Heuristic per-component | `steady_state_guess()` already in solvers.jl | Proven to work for all prior channel tests |

---

## Common Pitfalls

### Pitfall 1: Right Channel Port Direction

**What goes wrong:** Connecting `hd.thermal_right[i]` to `cac_r.thermal_right[i]` (wrong side) instead of `cac_r.thermal_left[i]`.
**Why it happens:** The naming is counter-intuitive: the right channel's "left" face is adjacent to the plate's "right" face.
**How to avoid:** Mental model — the plate's right boundary connects to the channel that stands to its right; from that channel's perspective, the plate is on its LEFT. So always connect `hd.thermal_right[i]` to `cac_r.thermal_left[i]`.
**Warning signs:** VAL-02 asymmetric test will show wrong sign on temperature asymmetry (hotter side on wrong face).

### Pitfall 2: Pressure Anchor for Two Independent Loops

**What goes wrong:** Forgetting to anchor absolute pressure for the second loop.
**Why it happens:** The existing single-loop tests only need one `pump.inlet.P ~ 1.0e5`. The two-loop system has two independent pressure references.
**How to avoid:** Add `pump_l.inlet.P ~ 1.0e5` AND `pump_r.inlet.P ~ 1.0e5`.

### Pitfall 3: `fully_determined` for the Coupled System

**What goes wrong:** `mtkcompile(sys)` (fully_determined=true) throws a structural singularity error because the thermal port temperatures on unconnected sides are free.
**Why it happens:** For VAL-01/02 (both sides connected), the system may be fully determined. For VAL-03 (one-sided), `thermal_right[i].T` is free. Also, if both loops are thermally coupled, subtle index counts may fail.
**How to avoid:** Use `fully_determined=false` for VAL-03; test VAL-01/02 with true first, fall back to false if needed. The CHAN-03 test shows that `fully_determined=false` + explicit Re/Nu/h_tc guesses solves correctly.

### Pitfall 4: Python STREAM Celsius vs Julia Kelvin

**What goes wrong:** Reference values extracted in Celsius instead of Kelvin.
**Why it happens:** Python STREAM operates entirely in Celsius internally.
**How to avoid:** Follow `generate_reference.py` pattern: `T_outlet_K = T_outlet_C + 273.15` before printing. Assert temperature conversions match expected values (same sanity checks as the existing script).

### Pitfall 5: power_shape Normalization

**What goes wrong:** `power_shape` elements do not sum to 1.0, so total power is wrong.
**Why it happens:** `HeatDiffusion` does NOT normalize `power_shape` internally (documented in HDIFF-03). If `power_shape = fill(1.0, nz, nx)` instead of `fill(1.0/(nz*nx), nz, nx)`, the volumetric heat source is `nz*nx` times too large.
**How to avoid:** Assert `sum(power_shape) ≈ 1.0` before solving. For nz=10, nx=3: each element is `1/30 ≈ 0.03333`.

### Pitfall 6: Non-uniform power_shape Test — Zero-Center Cell

**What goes wrong:** If `power_shape = [0.5, 0.0, 0.5]` but the test checks `T[1,2] < T[1,1]` using `<` (strict), tiny numerical errors could cause failure.
**How to avoid:** The test should check `T[1,2] < T[1,1] - tolerance` or more robustly check `T[1,1] > T[1,2]` and `T[1,3] > T[1,2]`. The center cell has zero source and is sandwiched by hot outer cells — the temperature ordering is physically robust.

### Pitfall 7: VAL-02 "Non-symmetric" Assertion

**What goes wrong:** Testing for non-symmetry numerically is fragile if using absolute comparison.
**How to avoid:** Assert that `T_plate` left face is cooler than right face (hotter right channel → hotter right side of plate). Concrete assertion: `sol[ssys.hd.T[nz÷2, 1]] < sol[ssys.hd.T[nz÷2, nx]]` for the center row. Also assert `T_plate_center_ref` comparison against Python STREAM within 1%.

---

## Code Examples

### Verified Pattern: Port Access for Array Ports (from THERM-03 / runtests.jl)

```julia
# Source: test/runtests.jl — THERM-03 two-sided CAC test
[connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left,  i))) for i in 1:n]...,
[connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
```

### Verified Pattern: One-Sided Solve with Re/Nu/h_tc Guesses (from CHAN-03)

```julia
# Source: test/runtests.jl — CHAN-03 test
ssys2 = mtkcompile(sys2; fully_determined=false)
# Provide explicit algebraic var guesses
append!(op2, [ssys2.cac2.Re[i] => 3e5 for i in 1:n])
append!(op2, [ssys2.cac2.Nu[i] => 800.0 for i in 1:n])
append!(op2, [ssys2.cac2.h_tc[i] => 2.7e4 for i in 1:n])
```

### Verified Pattern: HeatDiffusion with ConstantTemperature (from HDIFF-02/03 test)

```julia
# Source: test/runtests.jl — HDIFF-02/03 test
@named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                           rho_s=2700.0, cp_s=900.0, k_s=200.0,  # Phase 12 uses aluminum
                           power_shape=ps, power=pwr)
op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
sol = solve_steady(ssys, op)
```

### Verified Pattern: Python STREAM Fuel Constructor (from heat_diffusion.py)

```python
# Source: stream/calculations/heat_diffusion.py
from stream.calculations.heat_diffusion import Fuel, Solid
material = Solid(density=2700.0, specific_heat=900.0, conductivity=200.0)
fuel = Fuel(
    z_boundaries=np.linspace(0, 0.6, 11),    # nz=10 cells
    x_boundaries=np.linspace(0, 0.00127, 4), # nx=3 cells
    material=material,
    y_length=0.07,
    power_shape=np.ones((10, 3)) / 30.0,     # uniform
    name="Fuel",
)
```

### Verified Pattern: Python STREAM `plate()` Call (from mtr_geometry.py)

```python
# Source: stream/composition/mtr_geometry.py
from stream.composition.mtr_geometry import plate, one_sided_connection
# Returns CalculationGraph
cg = plate(channel_l, channel_r, fuel)
# For one-sided (VAL-03): fuel's left face connected to channel
cg_onesided = one_sided_connection(channel, fuel, fuel_side="left")
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single ThermalPort per channel (`thermal`) | Dual ThermalPort arrays (`thermal_left[1:n]`, `thermal_right[1:n]`) | Phase 10 | Enables direct plate-channel coupling in Phase 12 |
| No solid heat diffusion component | `HeatDiffusion` with `thermal_left/right[1:nz]` port arrays | Phase 11 | Phase 12 can now directly wire channels to plate |
| `sys.thermal_left[i]` (fails) | `getproperty(sys, Symbol(:thermal_left, i))` | Phase 9/10 discovery | All port array connect() calls use this pattern |

---

## Open Questions

1. **Python STREAM FlowGraph + CalculationGraph integration for `plate()`**
   - What we know: `plate()` returns a `CalculationGraph`; `FlowGraph` handles hydraulics; they are composed via `CalculationGraph` addition protocol
   - What's unclear: The exact API to combine `FlowGraph` and `CalculationGraph` for the solve (the `CalculationGraph.__add__` or similar)
   - Recommendation: Read `tests/test_general/test_integrations.py` and `stream/composition/constructors.py` before writing the reference script. Alternatively, model closely after an existing Python STREAM test that uses `plate()`.

2. **`mtkcompile` fully_determined for fully-coupled MTR (VAL-01/02)**
   - What we know: THERM-03 (two-sided CAC with ConstantTemperature) uses `fully_determined=true` successfully; CHAN-03 (one-sided) requires `false`
   - What's unclear: Whether the HeatDiffusion + two CAC coupled system introduces additional free variables that require `fully_determined=false`
   - Recommendation: Try `fully_determined=true` first for VAL-01/02; fall back to `false` with explicit guesses if needed

3. **T_outlet variable name in the coupled system**
   - What we know: `sol[ssys.cac_l.T_out]` is the canonical pattern from all prior channel tests
   - What's unclear: Whether the compiled system name-mangling affects subsystem access (e.g., `ssys.cac_l` vs `ssys.mtr_sys.cac_l`)
   - Recommendation: Keep the composed system name as `:mtr_sys` and verify via `unknowns(ssys)` inspection if access fails

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`@testset`, `@test`, `@test_nowarn`) |
| Config file | none — standard `test/runtests.jl` |
| Quick run command | `julia --project test/runtests.jl` |
| Full suite command | `julia --project test/runtests.jl` (single file, all phases) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | Coupled HeatDiffusion + two CAC symmetric steady-state matches Python STREAM within 1% | integration | `julia --project test/runtests.jl` | ❌ Wave 0 (test block to be added) |
| VAL-02 | Asymmetric inlet T produces non-symmetric T_plate and matches Python STREAM reference | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| VAL-03 | One-sided coupling (HeatDiffusion left face only) solves; adiabatic right; matches Python STREAM | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| HDIFF-03 gap | Non-uniform power_shape: center cell with zero source is colder than outer cells | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project test/runtests.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/generate_mtr_reference.py` — Python STREAM reference script (run once manually)
- [ ] `test/runtests.jl` — Phase 12 `@testset` block with VAL-01, VAL-02, VAL-03, HDIFF-03 gap test; hardcoded reference constants from generate_mtr_reference.py output

*(Python reference script is a generator, not an automated test — run manually, extract constants, hardcode.)*

---

## Sources

### Primary (HIGH confidence)

- `test/runtests.jl` — THERM-03 two-sided CAC, CHAN-03 one-sided, HDIFF-02/03/05 tests: verified patterns for port access, solve patterns, initial condition structure
- `src/components.jl` — `HeatDiffusion`, `ChannelAndContacts`, `_diffusion_eqs`, `HeatExchanger`: implementation contracts confirmed
- `~/projects/STREAM/stream/composition/mtr_geometry.py` — `plate()`, `one_sided_connection()` Python APIs confirmed
- `~/projects/STREAM/stream/calculations/heat_diffusion.py` — `Fuel`, `Solid` constructors confirmed
- `test/generate_reference.py` — Pattern for reference script style confirmed

### Secondary (MEDIUM confidence)

- `~/projects/STREAM/stream/aggregator/` — CalculationGraph + FlowGraph integration; exact API for `plate()` + FlowGraph combined solve not independently verified in this session
- `~/projects/STREAM/tests/test_general/test_integrations.py` — Should confirm full plate() integration; not read in this session

### Tertiary (LOW confidence)

- State.md note about `generate_reference.py` validation status outstanding — flags that the existing reference script has not been re-validated recently; recommend rerunning before writing Phase 12 reference script

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all Julia components confirmed present and tested in Phase 10/11
- Architecture/wiring patterns: HIGH — direct extension of verified THERM-03 and CHAN-03 patterns
- Python STREAM reference script structure: HIGH for API calls; MEDIUM for exact FlowGraph + CalculationGraph composition call
- Pitfalls: HIGH — drawn from actual Phase 10/11 failure modes documented in STATE.md

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable APIs; MTK/SciML versions fixed by Project.toml)
