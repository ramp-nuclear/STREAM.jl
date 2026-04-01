# Phase 29: Threshold Analysis - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Standalone threshold physics functions (THRS-01..08) covering ONB, boiling onset power,
OFI, OSV, and three CHF correlations, plus a `twall_limit` utility — all as plain Julia
functions. Plus `threshold_analysis()` (THRS-09): a post-processor that extracts MTK
solution data into a `ChannelState` bundle and dispatches user-specified analysis
functions, returning a NamedTuple of results including CHFR and other safety ratios.

Correlations for HTC (Marco-Han, developing laminar, maximal_htc) and friction
(Colebrook-White, viscosity correction) are Phase 30 — not this phase.

</domain>

<decisions>
## Implementation Decisions

### File Organization (two-file split)
- **D-01:** Physics functions (THRS-01..08) go in `src/physical_models/threshold_analysis.jl` — plain Julia arithmetic, no MTK, no solution knowledge. Same design pattern as `subcooled_boiling.jl`.
- **D-02:** Post-processing layer goes in a new `src/analysis.jl` — contains `ChannelState` struct, `_extract_channel_state` private helper, pre-built analysis wrappers, `chfr()` helper, and `threshold_analysis()` (THRS-09). Mirrors Python STREAM's `analysis/thresholds.py` separation.

### THRS-01 Promotion
- **D-03:** `Bergles_Rohsenow_T_ONB(pressure, q_wall, T_sat) → T_sat + _bergles_rohsenow_dT_ONB(pressure, q_wall)`. The private `_bergles_rohsenow_dT_ONB` stays in `correlations.jl` (used by ChannelAndContacts T_ONB observable). No duplicate logic — the public function is a thin wrapper. Both functions coexist.

### ChannelState Bundle (THRS-09 supporting type)
- **D-04:** `ChannelState` is a struct (not a NamedTuple) containing all pre-extracted MTK solution fields:
  ```
  n::Int
  T_bulk::AbstractVector         # T[i] [K] per cell
  T_wall::AbstractVector         # max(T_wall_left, T_wall_right) per cell [K]
  T_wall_left::AbstractVector    # left face wall temperature [K]
  T_wall_right::AbstractVector   # right face wall temperature [K]
  T_sat::AbstractVector          # T_sat[i] [K] (from @observed)
  T_ONB::AbstractVector          # T_ONB[i] [K] (from @observed)
  T_inlet::Float64               # port_in.T [K]
  P::AbstractVector              # P[i] [Pa]
  q_flux::AbstractVector         # max(q_flux_left, q_flux_right) [W/m²] — conservative default
  q_flux_left::AbstractVector    # left face heat flux [W/m²]
  q_flux_right::AbstractVector   # right face heat flux [W/m²]
  mdot::Float64                  # port_in.mdot [kg/s]
  velocity::AbstractVector       # velocity[i] [m/s] (absolute)
  pipe::Union{PipeGeometry, Nothing}
  gravity::Float64
  ```
- **D-05:** `q_flux_left[i]` = `q_wall_left[i] / (pipe.heated_parts[1] * dz)` [W/m²]. Similarly for right. When `pipe` is `nothing`, `q_flux_*` fields are filled with zeros (and `q_flux` too) — `chfr()` will return `Inf` for all cells in that case (no pipe = no flux = no boiling risk from geometry perspective). `dz = pipe.L / n`.
- **D-06:** For **transient** solutions: each `AbstractVector` field becomes `AbstractMatrix` with shape `[n_times, n_cells]`. Analysis wrappers using broadcasting (`.`) handle both steady and transient transparently without special-casing.

### threshold_analysis() API (THRS-09)
- **D-07:** Signature: `threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...) → NamedTuple`. Each kwarg is `name = fn::ChannelState -> AbstractArray`. Calls `_extract_channel_state`, then `fn(state)` for each kwarg. Returns `NamedTuple{keys(kwargs)}(fn(state) for fn in values(kwargs))`.
- **D-08:** `pipe` and `gravity` are top-level kwargs (not just captured by closures) because `_extract_channel_state` needs them to compute `q_flux_left/right` and to populate `state.pipe` and `state.gravity` for pre-built wrappers.

### Pre-built Analysis Wrappers (uniform `(state::ChannelState) -> AbstractArray`)
- **D-09:** Ship one analysis wrapper per THRS-02..08 correlation. These extract from `state` and call the physics functions. Naming: physics function `q_CHF_sudo_kaminaga` → wrapper `Sudo_Kaminaga_CHF`. Wrappers live in `src/analysis.jl`.
- **D-10:** Full wrapper set:
  - `ONB_temperature(state)` → `Bergles_Rohsenow_T_ONB.(state.P, state.q_flux, state.T_sat)`
  - `boiling_onset_power(state)` → `q_boiling_onset.(state.mdot, state.T_sat, state.T_inlet, cp_water.(state.T_bulk))`
  - `OFI_power(state)` → `q_OFI_whittle_forgan.(state.mdot, state.T_sat, state.T_inlet, state.pipe)`
  - `OSV_flux(state)` → `q_OSV_saha_zuber.(state.T_inlet, state.mdot, state.pipe)`
  - `Sudo_Kaminaga_CHF(state)` → `q_CHF_sudo_kaminaga.(state.T_bulk, state.mdot, state.pipe, state.gravity)`
  - `Mirshak_CHF(state)` → `q_CHF_mirshak.(state.T_bulk, state.T_sat, state.P, state.velocity)`
  - `Fabrega_CHF(state)` → `q_CHF_fabrega.(state.T_inlet, state.T_sat, state.pipe)`
  - `twall_limit(state; inhomogeneity_factor=1.0)` → `twall_limit.(state.T_wall, inhomogeneity_factor)` (takes extra kwarg, so not directly passable as bare name — user wraps: `s -> twall_limit(s; inhomogeneity_factor=1.1)`)

### chfr() Helper — Safety Ratios
- **D-11:** `chfr(chf_fn; direction=:max)` returns `(state::ChannelState) -> AbstractArray`.
  - `direction` values: `:left`, `:right`, `:max` (default — conservative), `:total`
  - `:max` = `max.(state.q_flux_left, state.q_flux_right)`
  - `:total` = `state.q_flux` (which is the same as `:max` per D-04 — but user may override this concept)
  - **Guard:** `q_i ≤ 0` → `Inf` (wall is being cooled by coolant — no boiling risk, infinite margin). Never return negative CHFR.
  - Implementation: `[q_i > 0 ? c_i / q_i : Inf for (c_i, q_i) in zip(chf_fn(state), q)]`
- **D-12:** `chfr` is the primary safety ratio helper. Other ratios (e.g., ONB margin = `state.T_ONB - state.T_bulk`) users compute as closures directly — only CHF ratio has a dedicated helper because of the directional complexity.

### Claude's Discretion
- Exact formula coefficients for THRS-02..07 — match Python STREAM `physical_models/thresholds.py` exactly (formulas are fixed physics)
- Whether `ChannelState` is a `struct` or `@kwdef struct` (prefer `@kwdef` for convenience)
- How to handle `n` for transient extraction (can get from solution time series length)
- Whether `_extract_channel_state` uses `sol[ssys.comp.variable]` style or a helper
- Test file name: `test_analysis.jl` (new file following test placement rule)
- Export list: add all public names to `src/STREAM.jl` following existing pattern

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §THRS-01..09 — exact function signatures, input/output units, all 9 requirements

### Existing infrastructure to reuse/extend
- `src/physical_models/correlations.jl` — `_bergles_rohsenow_dT_ONB` private helper (THRS-01 calls this); `regime_dependent` factory pattern
- `src/physical_models/subcooled_boiling.jl` — file structure pattern to follow for `threshold_analysis.jl`
- `src/components/thermal_channel.jl` — @observed variables available in ChannelAndContacts solution: `T_sat[i]`, `T_ONB[i]`, `P[i]`, `T_wall_left[i]`, `T_wall_right[i]`, `q_wall_left[i]`, `q_wall_right[i]`, `velocity[i]`; port variables `port_in.T`, `port_in.mdot`; state var `T[i]`
- `src/solvers.jl` — `solve_steady` / `solve_transient` return types; how to query solution via `sol[ssys.comp.var]`
- `src/geometry.jl` — `PipeGeometry` fields: `L`, `Dh`, `A`, `heated_perimeter`, `wet_perimeter`, `heated_parts` (NTuple{2,Float64}), `width`, `depth`

### Python STREAM reference implementations
- `/home/itayb/projects/STREAM/stream/physical_models/thresholds.py` — physics layer for THRS-02..07 exact formulas
- `/home/itayb/projects/STREAM/stream/analysis/thresholds.py` — analysis wrapper pattern; `ThresholdFunction` protocol; `threshold_analysis` factory; `twall_limit`
- `/home/itayb/projects/STREAM/stream/physical_models/heat_transfer_coefficient/temperatures.py` — `Bergles_Rohsenow_T_ONB` and `Bergles_Rohsenow_dT_ONB` reference formulas (THRS-01)

### Prior phase context
- `.planning/phases/28-subcooled-boiling/28-CONTEXT.md` — D-05 `regime_dependent_q_scb` (THRS-04 references re_transition); subcooled_boiling.jl file structure
- `.planning/phases/27-pressure-field/27-CONTEXT.md` — T_ONB/T_sat observables; P[i] formula

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` in `src/physical_models/correlations.jl` — THRS-01 calls this directly; don't duplicate logic
- `rho_water`, `cp_water`, `mu_water`, `k_water`, `sat_temperature` — global fluid property functions; `boiling_onset_power` wrapper needs `cp_water(T_bulk)` from these
- `regime_dependent_q_scb` (Phase 28) — THRS-04 (OSV Saha-Zuber) may reference `Re_transition` pattern; OSV is self-consistent so needs its own implementation
- Query pattern from tests: `sol[ssys.cac.T_sat[i]]`, `sol[ssys.cac.T_wall_left[i]]`, `sol[ssys.cac.port_in.mdot]`, `sol[ssys.cac.velocity[i]]`, `sol[ssys.cac.P[i]]`

### Established Patterns
- Correlation functions are **plain Julia closures**, not `@register_symbolic`
- Factory pattern: `chfr(fn; direction)` captures args at construction, returns closure
- `ifelse()` for symbolic conditionals — but threshold functions are POST-PROCESS (not in MTK equations), so plain `if`/`ternary` is fine here
- File structure: new physics file in `src/physical_models/`, included in `src/STREAM.jl` via `include()`
- Export all public names in `src/STREAM.jl` only (never in component files)

### Integration Points
- `src/STREAM.jl`: add `include("physical_models/threshold_analysis.jl")` and `include("analysis.jl")`; add exports for all public names (THRS-01..08 physics + analysis wrappers + `chfr` + `threshold_analysis` + `ChannelState`)
- `src/physical_models/threshold_analysis.jl`: new file alongside `subcooled_boiling.jl`
- `src/analysis.jl`: new file at `src/` level (not inside `physical_models/`)
- `test/test_analysis.jl`: new test file; added to `test/runtests.jl` as `@testset include()`

</code_context>

<specifics>
## Specific Ideas

- Python STREAM uses `functools.partial(Bergles_Rohsenow_T_ONB, direction=Direction.left)` for directional wrappers. Julia equivalent: `s -> ONB_temperature_left(s)` or a `direction` kwarg on the wrapper itself.
- `chfr` helper must guard `q_flux ≤ 0 → Inf` — covers both zero-flux (adiabatic face) and negative-flux (coolant heating wall) cases. Negative CHFR is physically meaningless and would be a dangerous silent bug.
- Python STREAM `Sudo_Kaminaga_CHF` uses channel **width** (not heated perimeter) per Mishima experimental basis — verify from `pipe_geometry.py` and use `pipe.width` not `pipe.heated_perimeter / 2`.
- Transient uniformity: `AbstractVector` in `ChannelState` docstring should note it becomes `AbstractMatrix[n_times, n_cells]` for transient. Broadcasting in wrappers handles both.

</specifics>

<deferred>
## Deferred Ideas

- Marco-Han Nusselt, fully-developed and developing laminar HTC, maximal_htc, turbulent_friction, viscosity_correction → Phase 30
- Direction-specific ONB wrappers (`ONB_left`, `ONB_right` like Python STREAM) — user can write these as closures; not blocking for Phase 29
- Uncertainty/inhomogeneity factors for ONB (`onb_factor`, `inhomogeneity_factor`) — THRS-08 (`twall_limit`) handles inhomogeneity; ONB uncertainty factor is a Phase 30+ consideration

</deferred>

---

*Phase: 29-threshold-analysis*
*Context gathered: 2026-03-31*
