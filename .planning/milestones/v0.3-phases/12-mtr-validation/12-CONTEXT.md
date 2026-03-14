# Phase 12: MTR Validation - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Couple one `HeatDiffusion` + two `ChannelAndContacts` in an MTR-like geometry (plate flanked by two independent coolant channels), run to steady state, and validate outputs against a new Python STREAM reference script within 1%. Three validation scenarios: symmetric (VAL-01), asymmetric left/right inlet temperature (VAL-02), one-sided coupling (VAL-03). Also add one non-uniform `power_shape` spatial distribution test to close the HDIFF-03 coverage gap.

Phase 12 does NOT add new components or architectural capabilities — it is validation-only.

</domain>

<decisions>
## Implementation Decisions

### Python STREAM reference script

- **New file**: `test/generate_mtr_reference.py` (separate from `generate_reference.py`)
- **API**: Uses `plate(channel_l, channel_r, fuel)` from `stream.composition.mtr_geometry`
- **Output**: Prints hardcodable constants to stdout (same convention as `generate_reference.py`). Run once manually, copy into `runtests.jl`.
- **Scope**: All three scenarios in one script — symmetric (VAL-01), asymmetric (VAL-02), one-sided (VAL-03)
- **Gravity**: `g=0` in both channels (same as existing `generate_reference.py`; horizontal flow; gravity already validated in Phase 6)

### Plate geometry & materials

- **Model**: Single uniform `HeatDiffusion` — no cladding/meat differentiation in v0.3
- **Dimensions**: `nz=10, nx=3, Lz=0.6m, Lx=0.00127m (1.27mm), y=0.07m`
- **Material** (aluminum cladding): `rho_s=2700.0, cp_s=900.0, k_s=200.0`
- **Power**: `power=1e4` W (10 kW) for all validation cases
- **power_shape**: Uniform `fill(1.0/(nz*nx), nz, nx)` for VAL-01/02/03
- **nz=10 matches Channel n=10**: 1:1 axial cell coupling, no interpolation needed

### Channel geometry & hydraulic loop

- **Both channels**: identical geometry — `D=0.01m, L=0.6m, n=10, dP=30kPa`
- **Topology**: Two independent loops, one per channel: `Pump → HeatExchanger → ChannelAndContacts → Pump`
- **HeatExchanger** pins inlet temperature (same role as TempBC in existing VAL-01)
- **Gravity**: `g_acc=0` in both Julia `ChannelAndContacts` components
- **T_inlet (symmetric)**: `313.15 K (40°C)` on both sides — matches existing VAL-01 baseline

### VAL-02: Asymmetric case

- Left channel `HeatExchanger` outlet: `313.15 K` (40°C)
- Right channel `HeatExchanger` outlet: `363.15 K` (90°C, +50 K)
- Same geometry and dP_pump on both sides — asymmetry from inlet temperature only
- Expected result: non-symmetric `T_plate` profile (hotter near right face)
- Confirms left/right coupling direction is not swapped

### VAL-03: One-sided coupling

- `HeatDiffusion.thermal_left[i]` connected to `ChannelAndContacts`
- `thermal_right` unconnected → adiabatic (Q_flow=0 from MTK acausal semantics)
- Python reference uses `one_sided_connection(channel, fuel, fuel_side="left")`
- Validates that Phase 11's adiabatic default works in a fully coupled system

### Outputs compared (within 1%)

- **VAL-01**: `T_outlet` and `mdot` for both channels; `T_plate[nz÷2, nx÷2]` (center cell)
- **VAL-02**: `T_plate` profile is non-symmetric (qualitative assertion); center cell T compared to Python reference
- **VAL-03**: `T_outlet` and `mdot` for the connected channel; `T_plate` center cell

### Non-uniform power_shape test (closes HDIFF-03 gap)

- Small plate (e.g. `nz=1, nx=3`) with `power_shape = [0.5, 0.0, 0.5]` (zero center)
- Pinned boundary temperatures via `ConstantTemperature`
- Assert: center cell `T[1,2]` is colder than outer cells `T[1,1]`, `T[1,3]`
- Verifies that spatial variation in `power_shape` is correctly applied per-cell

### Test location

- New `@testset "STREAM Phase 12 Tests"` block in `test/runtests.jl`, following the Phase 11 block
- Reference constants hardcoded from `generate_mtr_reference.py` output (same pattern as existing VAL-01)

### Claude's Discretion

- Exact initial condition (`u0`) guess values for the coupled system solve
- Whether to use `mtkcompile(sys; fully_determined=true)` or `false` for the coupled system
- Variable access pattern for `T_outlet` (ChannelAndContacts cell temperature indexing)
- Order of connect() calls for assembling the two-loop MTR topology

</decisions>

<specifics>
## Specific Ideas

- Python STREAM's `plate()` function topology: `(channel_l → fuel ← channel_r)` with bidirectional thermal exchange. Julia equivalent: `connect(hd.thermal_left[i], cac_l.thermal_left[i])` and `connect(hd.thermal_right[i], cac_r.thermal_right[i])` for i in 1:nz.
- `generate_mtr_reference.py` should mirror `generate_reference.py` style: assertions on sanity bounds, then print constants in a format ready to paste into runtests.jl.
- The asymmetric case (VAL-02) doesn't require model changes — just different `HeatExchanger` outlet temperatures. The MTK system is the same; parameters differ.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets

- `HeatDiffusion`: implemented in Phase 11. Constructor: `HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power=1e6, T0=600.0)`
- `ChannelAndContacts`: upgraded in Phase 10 with `thermal_left[1:n]` + `thermal_right[1:n]`
- `Pump`, `HeatExchanger`, `ConstantTemperature`: all in `src/components.jl`, exported
- `getproperty(sys, Symbol(:thermal_left, i))` pattern: required for port array access in `connect()` calls

### Established Patterns

- Two-loop validation: see existing `VAL-01` build_loop test in runtests.jl for pump+HX+channel assembly pattern
- Phase 11 `ConstantTemperature` + `HeatDiffusion` wiring: direct template for the MTR coupling, but replacing `ConstantTemperature` with live `ChannelAndContacts`
- Python reference: `generate_reference.py` style — hardcoded outputs, single run, print to stdout

### Integration Points

- `HeatDiffusion.thermal_left[i]` ↔ `ChannelAndContacts.thermal_left[i]` for i in 1:nz (left channel)
- `HeatDiffusion.thermal_right[i]` ↔ `ChannelAndContacts.thermal_left[i]` for i in 1:nz (right channel — note: right channel's thermal_left connects to plate's thermal_right)
- `src/STREAM.jl`: no new exports needed — all components already exported

</code_context>

<deferred>
## Deferred Ideas

- **`symmetric_plate(channel, fuel)` Julia convenience function** — analog of Python STREAM's `symmetric_plate()`. Takes one `ChannelAndContacts` + one `HeatDiffusion`, returns pre-wired `ODESystem`. Target: v0.4.
- **Composable subsystem assembly** — analog of Python STREAM `CalculationGraph` addition. Combine hydraulics subsystem + thermal subsystem with automatic interface matching. Target: v0.4.
- **Multi-material `HeatDiffusion`** — `materials[nz, nx]` matrix of per-cell material properties + full-grid `power_shape[nz, nx]` (zeros in cladding cells). Harmonic mean k at material interfaces. Architecture agreed; defer past v0.4.
- **Cosine axial `power_shape`** — not needed for 1% validation at v0.3; add when a cosine-profile reference case is scoped.

</deferred>

---

*Phase: 12-mtr-validation*
*Context gathered: 2026-03-14*
