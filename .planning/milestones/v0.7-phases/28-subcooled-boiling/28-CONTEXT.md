# Phase 28: Subcooled Boiling - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

McAdams and Bergles-Rohsenow subcooled boiling heat flux correlations available as standalone
Julia functions, plus an optional in-loop SCB correction in ChannelAndContacts that activates
when T_wall[i] ≥ T_ONB[i]. Creating/exposing posts (Phase 29 threshold analysis) are a separate phase.

</domain>

<decisions>
## Implementation Decisions

### File Placement
- **D-01:** All SCB correlation functions go in a new `src/physical_models/subcooled_boiling.jl` file (per REQUIREMENTS.md). Not added to the existing correlations.jl.

### SCB Standalone Functions (SCB-01..03)
- **D-02:** `McAdams_SCB_heat_flux(T_sat, T_wall)` — standalone function returning W/m²; signature matches REQUIREMENTS.md exactly.
- **D-03:** `Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure; h_fg=..., sigma=...)` — h_fg and sigma are **optional keyword arguments with light-water defaults** at ~100°C (h_fg ≈ 2257 kJ/kg, sigma ≈ 0.059 N/m). Callers can override for non-standard conditions.
- **D-04:** `partial_SCB_correction(q_spl, q_scb, q_scb_inc)` — dimensionless factor; Bergles-Rohsenow smooth SPL↔SCB blend. Returns 1.0 when q_spl ≥ q_scb (no correction needed outside boiling regime).

### regime_dependent_q_scb (SCB-04)
- **D-05:** `regime_dependent_q_scb(T_wall, T_sat, Re; Re_transition=2300)` — **sharp cutoff** (no interpolation zone); McAdams for Re ≥ Re_transition, Bergles-Rohsenow for Re < Re_transition. Consistent with existing `regime_dependent` pattern. The `re_bounds` name from REQUIREMENTS.md maps to a single `Re_transition` kwarg (not a tuple — linear interpolation zone not needed).

### In-loop SCB Correction (ISCB-01)
- **D-06:** `ChannelAndContacts` gains an optional `scb_correction` kwarg (`nothing` by default). When provided, it is a **q-flux closure** `(T_wall, T_sat, Re) → q_scb [W/m²]` (e.g. a `regime_dependent_q_scb` call with appropriate re_bounds).
- **D-07:** ChannelAndContacts calls the closure **twice** per cell — once at T_wall[i] to get q_scb and once at T_ONB[i] to get q_scb_inc — then calls `partial_SCB_correction(q_spl, q_scb, q_scb_inc)` internally to compute the factor.
- **D-08:** Modified h_tc[i] equation (per ISCB-01): `ifelse(T_wall[i] >= T_ONB[i], h_spl[i] * partial_scb_factor, h_spl[i])` — uses the established `ifelse()` MTK pattern. This replaces the existing `h_tc[i] ~ ...` equation in the energy balance.
- **D-09:** When `scb_correction` is `nothing` (default), ChannelAndContacts behavior is **identical** to the current implementation — no performance impact, no new equations.

### Claude's Discretion
- Exact McAdams coefficient and exponent (match Python STREAM physical_models exactly)
- Exact Bergles-Rohsenow formula variant and coefficient (match Python STREAM temperatures.py / heat_transfer.py)
- Whether `scb_correction` wiring goes through `_channel_base_eqs` or directly in the ChannelAndContacts constructor (whichever avoids observed_mode complexity)
- Light-water default values for h_fg and sigma (verify against Python STREAM or standard water tables)
- Export names in STREAM.jl (follow existing export pattern; `_private` prefix for internal helpers)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing SCB infrastructure (Phase 27)
- `.planning/REQUIREMENTS.md` §SCB-01..04, ISCB-01..02 — exact function signatures, Out of Scope table, test acceptance criteria
- `src/physical_models/correlations.jl` — `_bergles_rohsenow_dT_ONB` private helper (Phase 29 will promote this); `regime_dependent` factory as pattern for SCB-04
- `src/components/thermal_channel.jl` — ChannelAndContacts full implementation; h_tc energy balance equations (lines ~106-122); observed block (lines ~129-155); h_tc[i] is an MTK unknown (not @observed) because it appears on RHS of energy balance

### Phase context
- `.planning/phases/27-pressure-field/27-CONTEXT.md` — T_ONB[i] and T_sat[i] observables (D-05, D-06); q_spl computed from q_wall[i]
- `.planning/phases/27.1-channel-momentum-inertia/27.1-CONTEXT.md` — P[i] formula with inertia correction (feeds T_ONB via sat_temperature)

### Python STREAM reference
- `~/projects/STREAM` — Python STREAM reference implementation (NOTE: path may not exist; if unavailable, use published correlation formulas from literature)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` in `src/physical_models/correlations.jl` (private) — already computes T_ONB offset; Bergles-Rohsenow SCB heat flux is a related but distinct formula
- `regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent, Re_transition=2300)` — factory pattern to follow for `regime_dependent_q_scb`
- `ifelse()` switching in ChannelAndContacts energy balance (line ~110) — established pattern for T_wall >= T_ONB SCB switching
- `q_wall[i]` MTK unknown in ChannelAndContacts is the total per-cell heat transfer rate; `q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)` is how q_spl is computed (line ~153 in observed block)

### Established Patterns
- Correlation functions are **plain Julia closures**, not `@register_symbolic` — MTK traces arithmetic symbolically
- `h_tc[i]` is an **MTK unknown** (not @observed) because it appears in the energy balance RHS; any modification (like SCB factor) must stay as an MTK equation
- Factory pattern: construction-time scalars captured in closure, symbolic Re/Pr/T_wall at equation time
- `ifelse()` emits a symbolic conditional node — same pattern needed for `T_wall[i] >= T_ONB[i]` in ISCB-01

### Integration Points
- `ChannelAndContacts` constructor: add `scb_correction=nothing` kwarg; conditionally modify `h_tc[i]` equations when non-nothing
- `src/physical_models/subcooled_boiling.jl` → new file; `include` in `src/STREAM.jl` after `correlations.jl`
- Exports in `src/STREAM.jl`: add `McAdams_SCB_heat_flux`, `Bergles_Rohsenow_SCB_heat_flux`, `partial_SCB_correction`, `regime_dependent_q_scb`

</code_context>

<specifics>
## Specific Ideas

No specific references — open to standard approaches matching Python STREAM formulas.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 28-subcooled-boiling*
*Context gathered: 2026-03-29*
