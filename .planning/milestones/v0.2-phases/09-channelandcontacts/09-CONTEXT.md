# Phase 9: ChannelAndContacts - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement `ChannelAndContacts` (n per-cell ThermalPorts for HeatDiffusion coupling) and `ChannelHeatFlux` (T_wall as parameter, for testing and simple simulations). Extract `_channel_base_eqs` shared helper. `Channel` is untouched. This phase delivers the interface contract that HeatDiffusion (v0.3) will connect to.

</domain>

<decisions>
## Implementation Decisions

### Component scope (Phase 9 delivers three things)
- `ChannelAndContacts` — n ThermalPorts (one per axial cell), for proper HeatDiffusion coupling (THERM-01)
- `ChannelHeatFlux` — T_wall as parameter (scalar or per-cell array), for testing and simple simulations; no ThermalPorts
- `_channel_base_eqs` — private shared helper called by both; holds the ~5 equations common to all channel variants (pressure drop, velocity, Re, Nu, HTC, upwind energy balance skeleton)
- `Channel` stays completely untouched (THERM-02)

### Semantic split (mirrors Python STREAM)
- `Channel` = unheated hydraulic component (flow pipes, hot-inlet columns, gravity/friction loops)
- `ChannelAndContacts` = heated channel wired cell-by-cell to HeatDiffusion via ThermalPorts; production coupling
- `ChannelHeatFlux` = simplified heated channel with T_wall as parameter; testing and standalone simulations only

### ChannelAndContacts port layout
- One `thermal[i]` ThermalPort per axial cell (not left+right per cell)
- Left/right wall distinction deferred to v0.3 when HeatDiffusion geometry is clearer
- `thermal[i].Q_flow` = per-cell heat flow in watts (positive = into component), consistent with ThermalPort semantics
- Expose `Q_wall_total` observable: `Q_wall_total ~ sum(thermal[i].Q_flow for i in 1:n)`

### ChannelHeatFlux parameter API
- `ChannelHeatFlux(; name, n, L, D, A, g=0.0, T_wall)` — same shape as Channel
- `T_wall` can be a scalar (same temperature for all cells) or a per-cell array of length n
- No ThermalPorts — T_wall is baked into the equations directly

### THERM-03 test wiring
- Use `ChannelHeatFlux(T_wall=T_uniform)` for the validation test — cleaner than wiring n HeatExchanger instances
- Tests inline `connect()`/`compose()` — no `build_loop_contacts` helper

### No build_loop helper
- `ChannelAndContacts` and `ChannelHeatFlux` are tested with inline `connect()`/`compose()` in the test file
- `build_loop` family is a test/example utility; no new variants added

### Implementation pattern (no Julia inheritance)
- Julia has no class inheritance; abstract types can't carry fields or equations
- Idiomatic pattern: extract `_channel_base_eqs(vars, pars, ports, n, Dh, dz)` as a private function
- Both `ChannelAndContacts` and `ChannelHeatFlux` call `_channel_base_eqs` and append their own thermal coupling equations

### Claude's Discretion
- Exact signature of `_channel_base_eqs` (what it accepts/returns)
- Whether `T_wall` array is a Julia parameter array or a vector of MTK parameters
- ODE solver and time span for any transient validation tests

</decisions>

<specifics>
## Specific Ideas

- Python STREAM reference: `ChannelAndContacts` in `stream/calculations/channel.py` lines 452–707; `ChannelHeatFlux` is the analog of passing scalar `T_left`/`T_right` to `Channel.calculate()`
- Python semantic split confirmed: Channel = unheated, ChannelAndContacts = HeatDiffusion-coupled, ChannelHeatFlux = testing shorthand
- When HeatDiffusion arrives in v0.3: replace `ChannelHeatFlux` usage with `ChannelAndContacts` + HeatDiffusion connections — same connect() wiring pattern, different source

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ThermalPort()` connector in `src/connectors.jl`: `T` (across) + `Q_flow` (flow, positive = into component) — existing, ready to use as array
- `Channel` in `src/components.jl:14–83`: full energy balance loop + design note explicitly says "q_wall indirection exists so per-cell ThermalPort refactor only changes port declaration and q_wall binding" — energy balance body transplants directly
- `HeatExchanger` in `src/components.jl`: available for wiring in any tests that need it, but THERM-03 uses `ChannelHeatFlux` instead

### Established Patterns
- All components: `compose(System(eqs, t, vars, pars; name=name), inlet, outlet, ...ports...)`
- `mtkcompile(sys; fully_determined=false)` for standalone tests (established Phase 7)
- TDD: RED stubs first, then GREEN implementation
- Per-cell array variables: `(T(t))[1:n]` syntax already used in `Channel`

### Integration Points
- `src/components.jl`: add `ChannelAndContacts`, `ChannelHeatFlux`, extract `_channel_base_eqs`
- `src/STREAM.jl`: export both new components
- `test/runtests.jl`: add Phase 9 testset with THERM-01 (ChannelAndContacts standalone), THERM-02 (regression — no changes needed), THERM-03 (ChannelHeatFlux cross-validates against Channel)

</code_context>

<deferred>
## Deferred Ideas

- Left/right ThermalPort distinction per cell (thermal_left[i] + thermal_right[i]) — deferred to v0.3 when HeatDiffusion geometry drives the requirement
- ChannelHeatFlux with per-cell h_wall (not just T_wall) — deferred; not needed until contact resistance modeling

</deferred>

---

*Phase: 09-channelandcontacts*
*Context gathered: 2026-03-13*
