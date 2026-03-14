# Phase 11: HeatDiffusion Component - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `HeatDiffusion` — a 2D finite-difference fuel plate MTK component with:
- State `T(t)[1:nz, 1:nx]` (rows = axial z, cols = lateral x)
- x-direction diffusion only (v0.3; z-diffusion is v0.4+)
- Adiabatic top/bottom boundaries (by omission of z-diffusion term)
- `thermal_left[1:nz]` and `thermal_right[1:nz]` ThermalPort arrays
- `power_shape[1:nz, 1:nx]` (constructor) + `power` (MTK parameter) as volumetric heat source
- Private `_diffusion_eqs` helper structured for future xz extension

Phase 11 is isolation + unit tests only. MTR coupling and validation are Phase 12.

</domain>

<decisions>
## Implementation Decisions

### Constructor API

- Signature: `HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power=1e6, T0=600.0)`
- **Geometry:** Uniform mesh — `dx = Lx/nx`, `dz = Lz/nz` computed internally. No boundary-array API in v0.3.
- **Material properties:** `rho_s`, `cp_s`, `k_s` as plain Float64 constructor args (same as Python STREAM `Solid` dataclass). Not MTK parameters in v0.3 — Phase 12 rebuilds the system if material values change.
- **y (plate width):** Explicit constructor parameter — required for cell volumes (`y * dz * dx`) and boundary Q_flow. Independent geometric dimension, matches Python STREAM `y_length`.
- **T0:** Scalar Float64 constructor default (fills all `T[i,j]` initial values). Phase 12 overrides via `u0` map at solve time — this is just a sensible fallback, not a constraint.
- **No contact conductance on HeatDiffusion:** FD stencil ends at the plate surface. `thermal_left[i].T` IS the plate surface temperature. All surface-to-coolant resistance lives in CAC's `h_tc`. Confirmed architectural split.

### Power source

- **Normalization:** No internal normalization. Formula: `power * power_shape[i,j] / (y * dz * dx)` applied directly. User owns the convention (pre-normalized sum=1.0, or raw shape with `power` absorbing the scale).
- **Axis convention:** `power_shape[1, :]` = top of plate (z=0, inlet side). `power_shape[nz, :]` = bottom (outlet side). Consistent with Channel/CAC: index 1 = inlet-facing cell.
- **`power` as MTK `@parameters`:** Declared as `@parameters power = default`. Tunable via `remake(prob, p=[sys.hd.power => new_val])` without rebuilding. For time-varying transients: use MTK callbacks or `ParameterizedFunction`. For v0.4 PointKinetics acausal coupling: refactor to `ScalarPort` variable — that is a deliberate v0.4 task, not a v0.3 concern.
- **Unit test scope:** Steady-state only — pinned boundary temperatures via `ConstantTemperature`, uniform power. Verify correct T profile and Q_flow signs. No transient unit test in Phase 11.

### Boundary Q_flow equations

- **Explicit Q_flow required** (same lesson as Phase 10 / CAC): MTK acausal does not self-determine Q_flow without an explicit equation.
- Left face: `thermal_left[i].Q_flow  ~ k_s * (y * dz) * (T[i, 1]  - thermal_left[i].T)  / (dx / 2)`
- Right face: `thermal_right[i].Q_flow ~ k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2)`
- Sign convention (positive = heat INTO component): when plate is hotter than coolant, Q_flow < 0 (heat leaves plate). When unconnected: MTK sets Q_flow = 0, which forces surface temperature → interior temperature (adiabatic).
- **Interior FD stencil (uniform dx):** For cell `(i, j)` (1 ≤ i ≤ nz, 2 ≤ j ≤ nx-1):
  `Dt(T[i,j]) ~ k_s * (T[i,j+1] - 2*T[i,j] + T[i,j-1]) / (dx^2 * rho_s * cp_s) + power*power_shape[i,j]/(rho_s*cp_s*y*dz*dx)`
- **Top/bottom adiabatic:** No z-diffusion equations written at all — adiabatic by omission, not by explicit zero-flux terms.

### _diffusion_eqs helper

- **Private, not exported:** Underscore prefix, no docstring for public API. Same convention as `_channel_base_eqs`.
- **Mutates in-place:** `_diffusion_eqs(eqs; T, thermal_left, thermal_right, nz, nx, k_s, rho_s, cp_s, dx, dz, y, power, power_shape, Dt)` — appends equations to `eqs`. No `!` suffix, consistent with `_channel_base_eqs`.
- **x-only for v0.3:** Handles interior x-diffusion + left/right boundary Q_flow equations only. Clear comment at top: `# v0.4: add dz, kz arguments for xz-diffusion (DIFF-01)`.
- **No stub kwargs:** Don't add `dz_val`, `kz` stubs now — add them when xz mode is actually implemented.

### Claude's Discretion

- Exact compose() call order for `thermal_left` and `thermal_right` arrays
- Whether to declare `T_plate_max` or similar observable variables (not required by spec)
- Test parameter values for HDIFF unit tests (nz, nx, Lz, Lx, y, material values, T_boundary, power)

</decisions>

<specifics>
## Specific Ideas

- Python STREAM `Fuel` uses `wall_temperature()` function to compute T_wall from T_extraneous + h_to_wall. Julia HeatDiffusion skips this entirely — `thermal_left[i].T` IS the wall temperature (set by MTK connect). Much simpler.
- When `thermal_right` is unconnected and `thermal_left` is connected to a channel: the plate is one-sided. Right face Q_flow = 0, which constrains right-face T via the boundary equation. This is the HDIFF-05 / VAL-03 scenario.
- Python STREAM's `Fuel.indices()` exposes `T_left`/`T_right` with a left↔right swap (`T_left = _vars["T_wall_right"]`). This swap is a Python STREAM artifact — Julia HeatDiffusion uses direct naming with no swap needed.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets

- `ThermalPort` connector: unchanged — `T` (across) + `Q_flow` (flow). Instantiate arrays same as CAC.
- `ConstantTemperature` component (added in Phase 10): pins `thermal.T = T_bc`. Used directly in Phase 11 unit tests to pin boundary temperatures on `thermal_left[i]` / `thermal_right[i]`.
- `_channel_base_eqs`: provides the exact mutation pattern to follow for `_diffusion_eqs`.

### Established Patterns

- Port array creation: `[ThermalPort(name=Symbol(:thermal_left, i)) for i in 1:nz]`
- compose() splat: `compose(sys, thermal_left..., thermal_right...)`
- MTK array port access in connect(): `getproperty(sys, Symbol(:thermal_left, i))` — `sys.thermal_left[i]` fails in connect() calls
- `@parameters` for tunable scalar inputs (power, dP_pump, etc.)
- `mtkcompile(sys; fully_determined=false)` when ports are not all connected (Phase 11 unit tests will use this)

### Integration Points

- `src/STREAM.jl`: export `HeatDiffusion` (and `Solid` struct if introduced)
- Phase 12 will call `connect(hd.thermal_left[i], cac.thermal_left[i])` for i in 1:nz — this is why the port naming must match exactly

</code_context>

<deferred>
## Deferred Ideas

- **v0.4: Non-uniform mesh via boundary arrays** — Replace `(nz, nx, Lz, Lx)` uniform constructor with `(z_boundaries, x_boundaries, y)` style (like Python STREAM `Fuel`). Requires changing FD stencil to use per-cell `dx[j]` and `dz[i]` instead of uniform `dx`/`dz`. **Must revisit in v0.4 planning.**

- **v0.4: z-diffusion (xz mode, DIFF-01)** — Add axial conduction to `_diffusion_eqs` by extending helper signature with `dz`, `kz` args and writing z-direction FD terms for all cells. Top/bottom boundaries become explicit (adiabatic or pinned). **Must revisit in v0.4 planning.**

- **v0.4: `power` as acausal variable for PointKinetics coupling (KIN-01)** — Refactor `power` from `@parameters` to a `ScalarPort` connector variable driven by PointKinetics. In v0.3, MTK `@parameters` + `remake()`/callbacks covers all use cases. **Must revisit when PointKinetics is scoped.**

- **v0.4: Non-uniform material properties** — Allow `rho_s`, `cp_s`, `k_s` as 2D arrays (per-cell) for multi-material plates (e.g., fuel meat + cladding). Python STREAM `Solid.from_array()` supports this. **Defer — uniform material sufficient for MTR validation.**

</deferred>

---

*Phase: 11-heatdiffusion-component*
*Context gathered: 2026-03-14*
