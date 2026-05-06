# Phase 10: ChannelAndContacts Two-Sided Upgrade - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Upgrade `ChannelAndContacts` from single `thermal_ports[1:n]` to dual `thermal_left[1:n]` + `thermal_right[1:n]` ThermalPort arrays, update the energy balance for two-sided heating, clear v0.2 tech debt (DEBT-01/02/03), and lock the interface contract that Phase 11 (HeatDiffusion) will be written against.

New capabilities (HeatDiffusion itself, MTR validation, PipeGeometry refactor) are out of scope — they belong in Phases 10.5, 11, 12.

</domain>

<decisions>
## Implementation Decisions

### Energy balance formula (two-sided)
- Use explicit h_tc formula per side: `h_tc[i] * (π*Dh/2) * dz * (thermal_left[i].T - T[i]) + h_tc[i] * (π*Dh/2) * dz * (thermal_right[i].T - T[i])`
- Heated perimeter split: symmetric, each side gets `π*Dh/2` (hardcoded for Phase 10; full geometry refactor deferred to Phase 10.5)
- This matches Python STREAM's convention: each side contributes independently via its own `h_tc * heated_perimeter * dz * ΔT` term
- `q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow` (total per cell)
- `Q_wall_total ~ sum(q_wall[i])` — unchanged semantics, now sums both sides

### Observables
- `q_wall[i]`: total per-cell heat (left + right combined) — no per-side observable arrays
- Per-side Q_flow accessible directly via port if needed: `sys.ch.thermal_left[i].Q_flow`

### Port naming convention
- New arrays: `thermal_left = [ThermalPort(name=Symbol(:thermal_left, i)) for i in 1:n]` and `thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]`
- MTK subsystem names: `thermal_left1, thermal_left2, ..., thermal_leftN` and `thermal_right1, ..., thermal_rightN`
- `thermal_ports` (old name) removed completely from codebase — no alias, no backward compat shim
- `compose(...)` call splats both arrays: `compose(sys, inlet, outlet, thermal_left..., thermal_right...)`

### THERM-01 test update
- Replace `Symbol(:thermal, i) in subsys_names` with `Symbol(:thermal_left, i)` and `Symbol(:thermal_right, i)` checks
- Old thermal1..N assertions removed entirely

### THERM-03 rewrite
- Replace current ChannelHeatFlux-vs-Channel comparison with: one-sided ChannelAndContacts (thermal_left connected to `T_wall`, thermal_right unconnected/adiabatic) compared against ChannelHeatFlux
- To equalize heated perimeters: set `D_cac = 2 * D_chf` so `π*D_cac/2 = π*D_chf` (one-sided cac heats at the same rate as chf)
- Tolerance: 0.1% match on T_outlet
- Boundary condition: `ConstantTemperature` component pins `thermal_left[i].T = T_wall` for each cell
- Phase 10 adds `ConstantTemperature` to components.jl if it doesn't already exist (trivial: `thermal.T ~ T_bc`, single ThermalPort)
- This test also implicitly validates CHAN-03 (adiabatic default): `thermal_right[i].Q_flow == 0` at steady state

### Tech debt cleanup
- DEBT-01: Remove `t_inlet` parameter from `_channel_base_eqs` signature; `T_inlet = instream(inlet.T)` is computed at call site, not passed as argument; update all call sites
- DEBT-02: THERM-03 now directly tests ChannelAndContacts (see above)
- DEBT-03: Fix cosmetic doc issue in `09-01-SUMMARY.md`

### Claude's Discretion
- Exact MTK compose() call order for the two port arrays
- Whether to add `ConstantTemperature` to the public exports in STREAM.jl
- Test parameter values for the new THERM-03 loop (L, D, n, T_inlet, T_wall, dP_pump)

</decisions>

<specifics>
## Specific Ideas

- Python STREAM confirmed: `q_left = h_left * (T_left - T_cool)`, `q_right = h_right * (T_right - T_cool)`, energy balance sums `q_left * heated_parts[0] + q_right * heated_parts[1]` — our h_tc formula per side directly mirrors this
- ConstantTemperature component sketch: `function ConstantTemperature(; name, T); @named thermal = ThermalPort(); compose(System([thermal.T ~ T], t; name=name), thermal); end`
- THERM-03 D relationship: `D_cac = 2 * D_chf` ensures `π*D_cac/2 = π*D_chf` — one-sided cac heated perimeter matches chf

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ThermalPort` connector: already supports `T` and `Q_flow` — no changes needed, just instantiate more of them
- `_channel_base_eqs` helper (line 204): shared hydraulics logic; only the `t_inlet` param is being removed; energy balance equations are added by each channel variant after this call
- `ChannelHeatFlux` (line 305): remains the single-sided reference implementation for THERM-03 comparison; no changes needed

### Established Patterns
- Port array creation: `[ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]` — same pattern, new names
- `compose(..., inlet, outlet, ports...)`: splat syntax supports both arrays by splatting each separately
- `mtkcompile(sys; fully_determined=false)`: already used in THERM-01 — ChannelAndContacts under-determined until thermal ports are connected

### Integration Points
- `src/STREAM.jl` exports: `ChannelAndContacts` name unchanged; `ConstantTemperature` may need to be added to exports
- All existing THERM-01 tests: need port name assertions updated (thermal1..N → thermal_left1..N + thermal_right1..N)
- `build_loop` test helper: does not use ChannelAndContacts — unaffected

</code_context>

<deferred>
## Deferred Ideas

- **Phase 10.5: PipeGeometry struct** — introduce a `PipeGeometry` struct (analogous to Python STREAM's `EffectivePipe`) with fields `L, Dh, A, heated_perimeter, heated_parts::NTuple{2,Float64}` and factory functions `PipeGeometry.rectangular(L, depth, width)` / `PipeGeometry.circular(L, D)`. Full constructor API refactor for all channel components. Insert between Phase 10 and Phase 11 so Phase 11 writes against the clean API. Needed for Phase 12 MTR accuracy (flat channel: π*Dh ≠ actual heated perimeter — 11× error at MTR geometry).

</deferred>

---

*Phase: 10-channelandcontacts-two-sided-upgrade*
*Context gathered: 2026-03-14*
