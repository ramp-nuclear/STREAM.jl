# Phase 54: Variant Rewrites & File Consolidation - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewrite the three public channel-family variants on top of `_channel_core` (built in Phase 53) and consolidate `src/components/channel.jl` + `src/components/thermal_channel.jl` into a single `src/components/channels.jl`. Update `src/STREAM.jl` `include` line and `CLAUDE.md` File Structure Standard accordingly. Add per-variant integration smoke tests for each rewritten variant on a *real* closed loop (not a stub system).

This phase walks back one Phase 52 deliverable: `WallPort` is removed from `src/connectors.jl` (and its tests from `test/test_connectors.jl`) because a 2-across-1-flow connector cannot deliver automatic adiabatic-when-unconnected via IC defaults or `[input = true]` (verified by `/tmp/spike_input_true.jl`, 2026-05-07). The new `Channel` consumes per-cell `T_wall` via the existing `ThermalPort` arrays and takes `h_left` / `h_right` as Channel constructor kwargs (default `0.0`). `HeatFluxPort` survives unchanged — `q_flux` + `Q_flow` is structurally 1-across-1-flow and adiabatic-by-default works automatically there.

**Architectural rule (locked, see `feedback_channel_hd_connection_rule.md`):** `HeatDiffusion` connects ONLY to `ChannelAndContacts`. `Channel` and `ChannelHeatFlux` never wire to `HeatDiffusion` — not in production code, examples, or tests. ROADMAP success criterion 6 (a) and (b), and REQUIREMENTS.md VAR-01 wording, were updated in this discuss phase to reflect the rule.

</domain>

<decisions>
## Implementation Decisions

### Connector architecture pivot (Area 1 — bridge)

- **D-01: WallPort is deleted in Phase 54.** Move `Channel` onto the existing `ThermalPort` (1 across `T` + 1 Flow `Q_flow`). Reasoning: a spike (`/tmp/spike_input_true.jl`, 2026-05-07) confirmed that 2-across-1-flow connectors cannot achieve automatic adiabatic-when-unconnected via IC defaults — MTK detects unset inputs but does NOT auto-anchor them, raising `ExtraVariablesSystemException` even with `[input = true]` metadata. Reducing WallPort to 1-across-1-flow makes it identical to ThermalPort modulo renaming, so reuse ThermalPort directly. Concretely: `src/connectors.jl` `@connector function WallPort(...)` is deleted; `src/STREAM.jl` exports drop `WallPort`; `test/test_connectors.jl` WallPort-specific tests (incl. `_StubWallDriver` and the `port_type=:wall` branches of `_StubRecipient`) are removed.

- **D-02: `Channel` constructor signature.**
  ```julia
  Channel(;
      name,
      n::Int,
      geometry::PipeGeometry,
      g=0.0,
      h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
      h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
      friction_correlation = blasius_friction,
  )
  ```
  No `htc_correlation`. h is purely external (kwarg). Per-side independence (`h_left`, `h_right`) so left-only / right-only / two-sided heating all just work without flags. Mirrors Python STREAM `Channel.calculate(T_left=None, T_right=None, h_left=0.0, h_right=0.0, ...)` defaults exactly.

- **D-03: `h_left` / `h_right` value semantics.**
  - **`Real`** → broadcast to all `n` cells (uniform per-side h).
  - **`AbstractVector{<:Real}` of length `n`** → per-cell static h (e.g. axial profile).
  - **`Function` / callable** → time-varying via the MTK callable-parameter pattern from v0.9 PointKinetics: `FType=typeof(fn)` captured at construction, `@parameters (h_left::FType)(..)` variadic. Used in equations as `h_left(t)` (or whatever args are appropriate). Reuses the proven PK pattern, not a new mechanism.
  *Default `0.0` (scalar)*: `h=0` ⇒ q=0 regardless of `T_wall`; combined with ThermalPort's Flow rule (Q_flow auto-zeros when port dangles, forcing `T_wall = T`), the channel is automatically adiabatic when nothing is connected and the kwarg is at its default. This is the user's explicit UX requirement: "do nothing → adiabatic; provide h → heated."

- **D-04: `_channel_core` q-expression construction inside `Channel`.** Per cell `i`, after evaluating `h_left`/`h_right` to a per-cell scalar value `hL_i` / `hR_i`:
  ```julia
  q_left_expr[i]  = hL_i * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
  q_right_expr[i] = hR_i * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
  ```
  And the channel-side Q_flow eqn for each port (so the system closes when connected):
  ```julia
  thermal_left[i].Q_flow  ~ q_left_expr[i]
  thermal_right[i].Q_flow ~ q_right_expr[i]
  ```
  When the port dangles (no `connect`, no binding eqn): MTK Flow rule auto-zeros `Q_flow ~ 0`. Combined with the channel-side eqn `Q_flow ~ h*A*(T_wall - T)`, this forces either `h = 0` (its default IC) or `T_wall = T` — both produce zero heat. Adiabatic ✓.

### `ChannelHeatFlux` (Area 4 — signature minimization, Areas 1+3 — connector retention)

- **D-05: `HeatFluxPort` is kept as-is** (1 across `q_flux` + 1 Flow `Q_flow`). HeatFluxPort is structurally 1-across-1-flow — adiabatic-by-default via IC `q_flux = 0.0` + Flow rule already works automatically. No reason to walk it back.

- **D-06: `ChannelHeatFlux` constructor signature (minimal).**
  ```julia
  ChannelHeatFlux(;
      name,
      n::Int,
      geometry::PipeGeometry,
      g=0.0,
      friction_correlation = blasius_friction,
  )
  ```
  Both `T_wall` and `htc_correlation` are removed entirely. q is purely external via `HeatFluxPort` arrays (per-cell binding equations or `connect()` to an external flux driver). No internal `h_tc` is computed; no `Nu` observable. Variant is a true passive recipient of prescribed heat flux.

- **D-07: `_channel_core` q-expression construction inside `ChannelHeatFlux`.** Per cell `i`:
  ```julia
  q_left_expr[i]  = thermal_left[i].q_flux  * geometry.heated_parts[1] * dz
  q_right_expr[i] = thermal_right[i].q_flux * geometry.heated_parts[2] * dz
  ```
  And the channel-side Q_flow eqn:
  ```julia
  thermal_left[i].Q_flow  ~ q_left_expr[i]
  thermal_right[i].Q_flow ~ q_right_expr[i]
  ```
  Dangling port → Flow rule `Q_flow=0` → `q_flux*heated*dz = 0` → `q_flux=0` (its IC default). Adiabatic ✓.

### `ChannelAndContacts` (carry-forward — no architectural change)

- **D-08: CAC keeps existing `ThermalPort` arrays unchanged** (CONN-03 carry-forward from Phase 52). Constructor signature stays as-is per ROADMAP/REQUIREMENTS:
  ```julia
  ChannelAndContacts(;
      name,
      n::Int,
      geometry::PipeGeometry,
      g=0.0,
      htc_correlation = dittus_boelter,
      friction_correlation = blasius_friction,
      scb_correction = nothing,
  )
  ```
  Internal h-correlation (variant-internal per Phase 53 D-03/D-04). Optional SCB augmentation. CAC is the ONLY variant that connects to `HeatDiffusion`.

- **D-09: CAC's q-expression construction onto `_channel_core`.** Per cell `i` (with optional SCB factor folded into `h_tc[i]`):
  ```julia
  q_left_expr[i]  = h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
  q_right_expr[i] = h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
  ```
  CAC declares its `h_tc[i]` as an unknown variable with its own equation (correlation-driven, with optional SCB ifelse) — variant-internal, exactly as today. The variant emits the channel-side `Q_flow ~ q_left_expr[i]` / `Q_flow ~ q_right_expr[i]` for ThermalPort closure under connect/dangling, same pattern as Channel and CHF.

### File consolidation (VAR-04)

- **D-10: New file structure.** Create `src/components/channels.jl` (plural). Move `Channel`, `ChannelHeatFlux`, `ChannelAndContacts`, and `_channel_core` (currently in `src/components/channel.jl`) into the new file. Delete `src/components/channel.jl` and `src/components/thermal_channel.jl`. Update `src/STREAM.jl` `include("components/channel.jl")` and `include("components/thermal_channel.jl")` lines to a single `include("components/channels.jl")` (preserving the include order — must precede `composition/helpers.jl` and any builder file that uses the variants).

- **D-11: `CLAUDE.md` File Structure Standard.** Update the `src/components/` tree comment (currently lists `channel.jl`, `thermal_channel.jl`, `heat_diffusion.jl`) to list `channels.jl` (plural) and `heat_diffusion.jl`. Update the prose description that mentions `channel.jl` / `thermal_channel.jl` separately. Mechanical edit; no decision content.

- **D-12: Atomicity / commit granularity is a planning concern.** Planner picks the commit shape (single big commit vs. extract→consolidate→delete sequence vs. some other ordering) based on what gives the cleanest atomic commits while keeping the test suite functional at every commit boundary. Constraint: until VAR-01..03 land, `_channel_base_eqs` was already removed in Phase 53 — current `Channel` / `CHF` / `CAC` already inline their physics, so there is no helper to keep alive across commits. The planner's ordering need only ensure each commit either (a) the old variants still work as written, or (b) the new variants are in place and tests are updated. The existing `test/test_channel.jl` will FAIL across most of Phase 54 (its API references will be stale until Phase 55 rewrites it under TEST-01); this is **expected and accepted** for Phase 54. The new `test/test_channels.jl` is the only test required to pass at Phase 54 close.

### Per-variant integration smoke (success criterion 6, rewritten)

- **D-13: Smoke tests live in a new `test/test_channels.jl`.** Matches CLAUDE.md test-mirrors-src rule. Phase 54 closes when all three smokes inside `test_channels.jl` pass (`bin/jl test/test_channels.jl` standalone). The full test suite (`bin/jl test/runtests.jl`) is NOT required to pass at Phase 54 close — `test/test_channel.jl` will be stale (API mismatch) until Phase 55's TEST-01 rewrite.

- **D-14: Channel smoke topology** (replaces ROADMAP 6(a)'s now-corrected wording). Closed `Pump → Channel → Pump` loop with:
  - `n` small (e.g. 4–7), `geometry = PipeGeometry_circular(L_ch, D_ch)` or rectangular
  - `Channel(; n, geometry, h_left=fill(5000.0, n), h_right=0.0)` — left side heated, right side adiabatic by default
  - Per-cell binding equations: `[ch.thermal_left[i].T ~ T_wall_value for i in 1:n]...`
  - `ch.thermal_right` arrays left dangling (right side adiabatic via Flow rule)
  - Pressure anchor: `pump.port_in.P ~ 1.0e5`
  - `mtkcompile`, then `solve_transient(t = 0.0..0.5)` (or similar brief horizon)
  - Assertions: solve retcode `Success`; per-cell `q_wall_left[i]` finite and signed-correctly (positive when `T_wall > T`, negative under reversed `dT`); `q_wall_right[i] ≈ 0` (adiabatic side); `T_out` drifts upward from inlet `T_in`

- **D-15: ChannelHeatFlux smoke topology** (replaces ROADMAP 6(b)'s now-corrected wording). Closed `Pump → ChannelHeatFlux → Pump` loop with:
  - `ChannelHeatFlux(; n, geometry)` — minimal signature
  - Per-cell binding equations on left only: `[chf.thermal_left[i].q_flux ~ q_value for i in 1:n]...`
  - `chf.thermal_right` arrays left dangling (right side adiabatic via Flow rule + IC `q_flux=0`)
  - Pressure anchor: `pump.port_in.P ~ 1.0e5`
  - `mtkcompile`, `solve_transient`
  - Assertions: solve retcode `Success`; per-cell `q_wall_left[i]` matches supplied `q_flux × heated_parts[1] × dz`; `q_wall_right[i] ≈ 0`; `T_out` drifts upward

- **D-16: ChannelAndContacts ↔ HeatDiffusion smoke topology** (CONN-03 regression check, ROADMAP 6(c) unchanged). Closed loop with `symmetric_plate(cac, fuel; name=:rods)` (existing Phase 11/15 helper, unchanged):
  - Small dimensions: `n=4`, `nz=4`, `nx=2`, `Lx ≈ 0.0025`, modest power
  - `Pump → cac → Pump` loop with `rods` composed
  - `mtkcompile` (note: Phase 11 / `build_initializeprob=false` handling may apply — planner handles)
  - `solve_transient` brief horizon
  - Assertions: solve retcode `Success`; `T` evolves; `q_wall[i]` observable finite and consistent with `Q_wall_total ≈ sum(q_wall[i])`

### Doc fixes already committed during this discuss phase

- **D-17: `.planning/ROADMAP.md` Phase 54 success criterion 6** rewritten in this discuss phase: removed "Channel ↔ HeatDiffusion over WallPort arrays" wording (violated the locked architectural rule); replaced with kwarg-driven Channel and binding-equation-driven ChannelHeatFlux smoke specs.
- **D-18: `.planning/REQUIREMENTS.md` VAR-01** wording updated in this discuss phase: removed "via the CONN-01 connector" (CONN-01 = WallPort, deleted in Phase 54); replaced with the ThermalPort + h-kwarg description and a walk-back note pointing to `feedback_channel_hd_connection_rule.md` and the `[input = true]` spike.
- Both edits should be included in the same commit as `54-CONTEXT.md` and `54-DISCUSSION-LOG.md`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 54: Variant Rewrites & File Consolidation" — phase goal, dependencies, 6 success criteria (note: criterion 6 was rewritten 2026-05-07 to align with the architectural rule)
- `.planning/REQUIREMENTS.md` §"Variants" — VAR-01..04 (note: VAR-01 wording updated 2026-05-07 to drop the WallPort/CONN-01 reference)
- `.planning/PROJECT.md` §"Current Milestone: v1.1 Final Channel-Family Redesign" — milestone goal, "never need touching again" mandate

### Prior decisions to honor
- `.planning/STATE.md` §"Key Decisions (carry-forward)" — v1.1 phasing rationale, Phase 52 connector spike (now partially superseded by Phase 54 WallPort removal — array-of-scalar vs vector-form decision still holds for CAC's ThermalPort and CHF's HeatFluxPort)
- `.planning/phases/52-channel-connectors/52-CONTEXT.md` — full Phase 52 connector contract; D-02 (WallPort definition) is walked back in Phase 54; D-03 (HeatFluxPort) and D-04 (ThermalPort retained for CAC) are honored unchanged
- `.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md` — `_channel_core` API D-01..D-14, especially D-02 (`q_left_expr` / `q_right_expr` are length-n `Vector{Num}` inputs the variant builds); Phase 54 D-04, D-07, D-09 specify the per-variant q construction that feeds into core
- `CLAUDE.md` §"File Structure Standard" — `src/components/channels.jl` (plural) is the new home; `channel.jl` and `thermal_channel.jl` are deleted; the standard text needs updating in this phase (D-11)
- `CLAUDE.md` §"MTK Patterns" — `ifelse()` for any conditional inside MTK equations; `mtkcompile` before solve; `@register_symbolic` for fluid functions; `@observed` vs unknowns distinction
- `CLAUDE.md` §"Component authoring conventions" — `name` keyword-only; underscore-prefix for internal helpers (`_channel_core` is private, not exported); positional args only when type dispatch enables it (none of the new variant signatures use multiple dispatch — keyword-only is correct here per the `feedback_keyword_only_rule` memory)
- `CLAUDE.md` §"Branching Policy" — work continues on `channels-redesign`; do not create new branches; do not commit to `main`

### Architectural rules (MANDATORY)
- `/home/itay/.claude/projects/-home-itay-projects-Julia-STREAM/memory/feedback_channel_hd_connection_rule.md` — **HeatDiffusion connects ONLY to ChannelAndContacts**; Channel and ChannelHeatFlux NEVER wire to HeatDiffusion; never relax this rule

### Existing code (read before extending)
- `src/components/channel.jl` — current `Channel` (lines 26-144) and `_channel_core` (lines 162-305); `_channel_core` is reused unchanged from Phase 53; current `Channel` is deleted and rewritten in `channels.jl`
- `src/components/thermal_channel.jl` — current `ChannelAndContacts` (lines 48-246) and `ChannelHeatFlux` (lines 278-405); both rewritten onto `_channel_core` and consolidated into `channels.jl`. Existing CAC h_tc/SCB equations (lines 105-165) are preserved structurally — they migrate as `q_left_expr`/`q_right_expr` builders inside the new CAC body
- `src/connectors.jl` — `ThermalPort` (kept, used by Channel and CAC), `HeatFluxPort` (kept, used by CHF), `FlowPort` (kept), `WallPort` (DELETED in Phase 54)
- `src/components/heat_diffusion.jl` — `HeatDiffusion` exposes ThermalPort arrays; this phase does NOT touch HeatDiffusion (per Phase 54 boundary and the architectural rule, only CAC connects to HD; HD is read-only here)
- `src/composition/helpers.jl` — `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`, `port` accessor; UNCHANGED in Phase 54 (Phase 55 TEST-03 updates them, although since CAC keeps ThermalPort and Channel/CHF never touch HD, no helper change may actually be required — Phase 55 will assess)
- `src/STREAM.jl` — current `include` order and exports; Phase 54 changes: drop `WallPort` from the `export FlowPort, ThermalPort, WallPort, HeatFluxPort` line; replace the two `include("components/channel.jl")` / `include("components/thermal_channel.jl")` lines with a single `include("components/channels.jl")` (preserving include order before `pump.jl` / `flapper.jl` / `resistors.jl` / `misc.jl` / `heat_diffusion.jl` / `point_kinetics.jl`)
- `src/fluids.jl` — `cp_water`, `rho_water`, `mu_water`, `k_water` `@register_symbolic` functions used inside `_channel_core`'s energy balance and friction expressions
- `src/physical_models/htc/correlations.jl` — `dittus_boelter` and other htc correlations used by CAC's h_tc equation; unchanged in Phase 54
- `src/physical_models/friction/correlations.jl` — `blasius_friction`, `laminar_friction`, etc.; default `friction_correlation = blasius_friction` for all three variants

### Test references
- `test/test_connectors.jl` — Phase 52 stubs (`_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`); the WallPort branches and `_StubWallDriver` are deleted in Phase 54; HeatFluxPort branches and `_StubFluxDriver` are kept
- `test/test_channel.jl` — current 958-line test file under old API; will FAIL during most of Phase 54 (expected); Phase 55 (TEST-01) rewrites it under the new API and migrates content into `test/test_channels.jl`. Phase 54 does NOT need to keep this passing
- `test/runtests.jl` — orchestrator; Phase 54 adds an `include("test_channels.jl")` line for the new file; the existing `include("test_channel.jl")` line stays (file still exists, just with stale tests) until Phase 55 deletes it
- `test/test_validation.jl` — Python STREAM cross-validation; UNCHANGED in Phase 54 (Phase 56 milestone gate)

### Python STREAM reference (design intent)
- `/home/itay/projects/STREAM/stream/calculations/channel.py` lines 224-238 — `Channel.calculate(*, T_left=None, T_right=None, h_left=0.0, h_right=0.0, Tin, mdot, ...)`. **This is the design source for D-02 / D-03.** The new Julia `Channel` constructor's `h_left=0.0`, `h_right=0.0` defaults and per-side independence mirror this exactly.
- `/home/itay/projects/STREAM/stream/calculations/channel.py` line 384 — `class ChannelHeatFlux(Channel)`. Python flux variant accepts `q_left=0.0`, `q_right=0.0` — Julia equivalent uses HeatFluxPort + binding equations, defaults via IC `q_flux=0.0`.
- `/home/itay/projects/STREAM/stream/calculations/channel.py` line 452 — `class ChannelAndContacts(Channel)`. Python CAC computes `h_left = self.h_wall(T_left, T_cool, ...)` (correlation-driven from wall T); Julia CAC mirrors this with internal `h_tc[i]` correlation equations.

### Verification spike (this discuss phase)
- `/tmp/spike_input_true.jl` — verification that `[input = true]` does NOT auto-close 2-across-1-flow connectors. Test A (unconnected) and Test C (mixed) fail with `ExtraVariablesSystemException`; Test B (fully connected) succeeds; Test D (no `[input=true]`) fails as expected. Conclusion: IC defaults are solver guesses, not equations; MTK has no native auto-anchor mechanism for unconnected across-vars. **This spike justifies D-01.**

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_channel_core` (`src/components/channel.jl:162-305`)** — Phase 53's shared core; consumed by all three variant rewrites in Phase 54 with no changes. Variants build `q_left_expr` / `q_right_expr` per D-04 / D-07 / D-09 and pass them into core. Variants own all `@variables` declarations; core builds equations referencing those symbols.
- **CAC's existing `h_tc` equations (`src/components/thermal_channel.jl:111-117, 138-165`)** — single-phase (`scb_correction === nothing`) and SCB-corrected forms. These migrate verbatim into the new CAC body in `channels.jl`; only the surrounding scaffolding (energy balance loop, port wiring, observables) is replaced by `_channel_core`.
- **`partial_SCB_correction`, `_bergles_rohsenow_dT_ONB`, `sat_temperature` (`src/physical_models/`, `src/fluids.jl`)** — used by core's `T_ONB[i]` observable and by CAC's SCB-corrected `h_tc[i]` equation. No change.
- **Phase 52's `_StubRecipient` drive-aware pattern** — superseded for production code (Channel/CHF use binding equations or kwargs instead). Pattern is retained inside `test/test_connectors.jl` only for the HeatFluxPort-side validation; WallPort-side branches removed.
- **`Pump(dP_pump)` / `Pump(mdot0=...)`** — used as the FlowPort source in all three Phase 54 smoke loops; existing component, no change.
- **`port(sys, face, i)` accessor (`src/composition/helpers.jl:28`)** — canonical way to address indexed thermal port arrays in `connect()`; used by symmetric_plate / plate / one_sided_connection helpers and by the CAC↔HD smoke topology.
- **`build_loop` topology pattern (`src/examples.jl:48-79`)** — minimal `Pump → bc → Channel → Pump` shape with pressure anchor; the Channel and CHF smoke loops adapt this shape, dropping `bc` (HeatExchanger) where T_inlet is set via inlet port stream variable instead.

### Established Patterns
- **Variant declares all `@variables`, `_channel_core` consumes by reference** — Phase 53 D-10. Variant declares `T`, `dp`, plus all observable LHS symbols core references (Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, dP, T_out). Phase 54 variants follow this contract identically.
- **`ifelse(port_in.mdot ≥ 0, T_up_fwd, T_up_rev)` for flow reversal** — already inside `_channel_core`; variants do not add their own `ifelse` for upstream selection.
- **`instream(port_in.T)` / `instream(port_out.T)` for boundary face values** — already inside `_channel_core`; variants do not handle these.
- **MTK callable-parameter pattern (v0.9 PointKinetics)** — `FType=typeof(fn)` captured at construction, `@parameters (fn::FType)(..)` variadic. Reused for time-varying `h_left` / `h_right` callables in `Channel`.
- **Channel-side Q_flow eqn for ThermalPort/HeatFluxPort port closure** — emit `port.Q_flow ~ q_expr` for every port; MTK Flow rule handles connect/dangling cases automatically. This is how CAC currently works (lines 184-187 of `thermal_channel.jl`); Channel and CHF adopt the same pattern.

### Integration Points
- **`src/components/channels.jl`** — NEW file; receives all three variants + the (existing, unchanged) `_channel_core` body. Order inside the file: `_channel_core` first (private helper), then `Channel`, then `ChannelHeatFlux`, then `ChannelAndContacts` (or alphabetical — planner picks).
- **`src/components/channel.jl`** — DELETED at Phase 54's last commit.
- **`src/components/thermal_channel.jl`** — DELETED at Phase 54's last commit.
- **`src/STREAM.jl`** — `include("components/channels.jl")` replaces the two old includes; export line drops `WallPort`.
- **`src/connectors.jl`** — `WallPort` `@connector function` block deleted; `HeatFluxPort` and `ThermalPort` unchanged.
- **`src/composition/helpers.jl`** — UNCHANGED in Phase 54. Phase 55 TEST-03 may decide no change is needed at all (CAC keeps ThermalPort, Channel/CHF never touch HD/CAC-shaped helpers).
- **`test/test_connectors.jl`** — WallPort tests + `_StubWallDriver` deleted; `_StubRecipient` `port_type=:wall` branches removed; `_StubFluxDriver` and HeatFluxPort branches kept.
- **`test/test_channels.jl`** — NEW file; Phase 54's three integration smokes (Channel, CHF, CAC↔HD) live here. Wired into `test/runtests.jl`.
- **`test/runtests.jl`** — adds `include("test_channels.jl")`; keeps `include("test_channel.jl")` (still imports OK, just runs failing testsets) until Phase 55 deletes it.
- **`CLAUDE.md` File Structure Standard** — text update reflecting `channels.jl` plural file replacing the two singular files.

</code_context>

<specifics>
## Specific Ideas

- **User's UX requirement (axiomatic for this phase):** "If the user does not explicitly connect or add a binding equation for the temperature and h, the assumption is that that channel is not heated (adiabatic) and is there just for the flow." Locked. Architecture (D-01..D-04) is built around making this automatic for both Channel (via ThermalPort + h kwarg default 0) and ChannelHeatFlux (via HeatFluxPort + IC q_flux=0).
- **User's MTK idiom expectation:** "Providing values for Channel and CHF for what they need is meant to be through the external funcs … we should have a way of adding custom equations that are just meant for giving a variable of some component whatever values you want." The Julia MTK realization of this is binding equations at compose time (e.g., `[ch.thermal_left[i].T ~ value for i in 1:n]...` inside the parent `connections` vector). This is already used elsewhere in `src/examples.jl` (`pump.port_in.P ~ 1.0e5`, `ch.thermal.T ~ T_wall`) — Phase 54 leans on the same idiom; no new mechanism is invented.
- **Symmetry with Python STREAM Channel.calculate signature** is intentional and explicit. The new `Channel(; h_left=0.0, h_right=0.0)` defaults map 1:1 onto Python's `def calculate(*, h_left: WPerM2K = 0.0, h_right: WPerM2K = 0.0, T_left=None, T_right=None, ...)` (channel.py lines 224-238). When porting between Python and Julia STREAM, callers will see the same kwarg names and the same defaults. This was a deciding factor over the alternative (single `h` kwarg with internal heated_parts handling).
- **`[input = true]` was investigated and rejected based on a concrete spike**, not on opinion. `/tmp/spike_input_true.jl` exercised four configurations (unconnected with `[input=true]`, fully connected with `[input=true]`, mixed connected/dangling, baseline without `[input=true]`); the unconnected and mixed cases failed with `ExtraVariablesSystemException`. This is the empirical basis for D-01.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 55 (TEST-01..03, TEST-05) consequences of WallPort removal:**
  - `test/test_channel.jl` (958 lines) needs a full rewrite under the new API; this is already in scope as TEST-01.
  - All shipped builders that pass `T_wall` or use scalar `ThermalPort` Channel (currently `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_loop_lof_bypass`, `build_loop_pk`'s thermal-coupling pattern) need updates. Already in scope as TEST-02.
  - `composition/helpers.jl` may not need any change at all — CAC keeps ThermalPort; Channel and CHF do not connect to plates. Phase 55 should assess and either confirm "no change" or update under TEST-03.
- **Cross-validation under the new architecture (TEST-04, Phase 56)** — milestone gate. Phase 53's stage-2 hand-computed test was a *local* parity check on `_channel_core`; Phase 56 is the full system-level check.
- **MTK upstream issue for the [input=true] auto-anchor gap** — could be filed against MTK as a feature request ("treat unbound inputs with default values as default-valued constants at mtkcompile time"). Out of v1.1 scope; spike artifact `/tmp/spike_input_true.jl` is reference if the report is ever filed.
- **STATE.md Key Decisions update** — this discuss phase produced material new decisions (WallPort removal, h-kwarg architecture, architectural rule). After Phase 54 close (or sooner), STATE.md "Key Decisions (carry-forward)" section should append the v1.1 Phase 54 entries. Not part of Phase 54 plans; happens in `/gsd:execute-phase` finalization or via `/gsd:extract-learnings`.
- **CONN-01 status in REQUIREMENTS.md** — currently marked Complete (Phase 52 shipped WallPort). The work has been walked back. Whether to retroactively mark CONN-01 as "Superseded by Phase 54 D-01" or leave the audit trail in the VAR-01 footnote is a documentation-hygiene decision for Phase 54 planning or Phase 56 milestone close.

</deferred>

---

*Phase: 54-Variant Rewrites & File Consolidation*
*Context gathered: 2026-05-07*
