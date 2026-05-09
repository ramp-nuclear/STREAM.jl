# Phase 57: HTC film-temperature evaluation - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Change Julia STREAM's heat-transfer-coefficient (HTC) pipeline so that the coolant fluid properties feeding the HTC formula are evaluated at the **film temperature** `T_film = (T_cool + T_wall) / 2` instead of at bulk `T[i]`. Match Python STREAM, which evaluates the full coolant property bundle at `T_film` before computing `Re`, `Pr`, and the leading `k` in `h = Nu(Re,Pr) · k / Dh` (see `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/__init__.py:208-209`).

Phase 56's parity harness (`test/data/parity_report.csv`) currently shows ~19% rtol on every `h_tc_left[i]` / `h_tc_right[i]` row in the `simple_loop` scenario, all FAIL-tier, all annotated `Gap #2 candidate (HTC film-T vs bulk-T)`. Switching the eval point to `T_film` is the targeted fix for that gap.

**In scope:**
- The HTC pipeline inside `Channel` and `ChannelAndContacts` (`src/components/channels.jl:653-656,660-663`): switch `Re_i`, `Pr_i`, and the dimensional `k_water(...)` outside `Nu` to use `T_film`.
- Docstring updates on the HTC correlation interface (`src/physical_models/htc/correlations.jl`) clarifying that callers pass film-T-evaluated `Re`/`Pr`.
- Test coverage: re-run the Phase 56 parity harness; verify `h_tc_*[i]` rows move out of FAIL into CLEAN/GRAY; commit the regenerated `test/data/parity_report.csv`.

**Out of scope (stays at bulk T):**
- Friction `Re_i_for_friction` (channels.jl:139) and the friction correlation pipeline. Python evaluates friction at bulk; this is a bulk-flow phenomenon.
- The natural-convection `Gr/Re²` regime check inside `regime_dependent` (correlations.jl:144-146) and the Elenbaas `elenbaas_htc` factory's `beta_water` / `mu_water` evaluations (correlations.jl:212-213). NC driving force is fundamentally a bulk-vs-wall ΔT phenomenon; Python evaluates β,ν at bulk for this purpose.
- The `cp_face` face-averaged `cp_water` in the energy balance (channels.jl:73,123,134). That is an integrated-over-cell quantity and a separate gap class from the HTC eval point.
- Phase 58's MTK-determinacy work — MTR scenarios in `parity_report.csv` will continue to emit `solver_error` sentinel rows until Phase 58 ships. Phase 57's success bar is checked only on `simple_loop` scenario rows.

**Out of scope as new capabilities:**
- New HTC correlations.
- A `coolant_funcs.to_properties(T_film, P)` property-bundle abstraction (rejected as premature — STREAM.jl has no other consumer for it).
- Fluid-property AbstractFluid refactor (deferred to v0.6+ per `project_fluids_longterm.md` memory).

</domain>

<decisions>
## Implementation Decisions

### Eval site (where film-T property evaluation lives)

- **D-01: Compute `Re`, `Pr`, `k_film` at the Channel core call site, not inside the HTC closure.** The Channel computes `T_film_i = (T[i] + T_w_i) / 2` per cell, then evaluates `Re_i = abs(mdot)*Dh/(A*mu_water(T_film_i))`, `Pr_i = cp_water(T_film_i)*mu_water(T_film_i)/k_water(T_film_i)`, and `k_film_i = k_water(T_film_i)`, and assembles `h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_film_i / Dh`. The HTC correlation interface signature `(Re, Pr, T_bulk, T_wall) -> Nu` stays exactly as-is. The meaning of the `Re`/`Pr` arguments shifts from "bulk-evaluated" to "film-evaluated", but the type and arity are unchanged.

  *Rejected: changing the HTC closure signature to `(mdot, Dh, A, T_cool, T_wall) -> Nu` and computing properties inside each closure. Touches every factory (`dittus_boelter`, `regime_dependent`, `constant_Nusselt`, `Marco_Han_Nusselt`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`, `elenbaas_htc`) plus every test in `test_correlations.jl` plus all call sites. Smallest blast radius wins.*

  *Rejected: a `WaterProps@T_film` property-bundle abstraction. New abstraction with no other STREAM.jl consumer; defer until heavy-water / multi-fluid work needs it.*

### Scope of T_film usage (which terms switch)

- **D-02: All three HTC-pipeline property evaluations switch to T_film: `Re`, `Pr`, AND the leading `k_water` outside `Nu`.** This is the full match to Python's `coolant_funcs.to_properties(T_film, pressure)` — every fluid-property eval that feeds `h = Nu(Re,Pr) · k / Dh` uses the same T_film. Partial fixes (Re-only, or Re+Pr without k) would leave residual GRAY drift and miss the point of the phase.

  Concrete edits in `src/components/channels.jl`:
  - Lines 653-656 (`_channel_core` SPL branch): replace `mu_water(T[i])`, `cp_water(T[i])`, `k_water(T[i])` (in Re_i and Pr_i and the trailing `* k_water(T[i]) / Dh`) with `T_film_i`-evaluated equivalents.
  - Lines 660-663 (`_channel_core` SCB branch, `h_spl_i` computation): same substitution.
  - The Channel's friction-side `Re_i_for_friction` at line 139 stays at `mu_water(T[i])` — see D-03.

### Friction Re and NC Gr/Re² (what stays at bulk)

- **D-03: Friction `Re_i_for_friction` and `regime_dependent` NC Gr stay at bulk T, with a single anchored explanatory comment in `_channel_core`.** Friction is a bulk-flow quantity; Python evaluates friction Re at bulk. NC is a bulk-vs-wall ΔT phenomenon; Python evaluates β,ν for Gr at bulk. Both are correct; this is not an oversight to "fix later".

  **Cleanliness directive (the user's framing — "make it look as clean as possible"):** Do NOT sprinkle ad-hoc bulk-vs-film picks across helper expressions. The implementation should read as a single principled split:
  - HTC pipeline → `T_film_i` → one named local in `_channel_core` (e.g., `T_film_i = (T[i] + T_w_i) / 2`) used by `Re_i`, `Pr_i`, and `k_film_i`.
  - Friction Re → bulk `T[i]` (existing line 139, unchanged).
  - NC Gr inside `regime_dependent` → bulk `T_bulk` (existing closure body, unchanged).

  A single block comment in `_channel_core` documents WHY the HTC side uses film and the friction/NC sides do not — citing Python STREAM as the matching reference. No defensive comments scattered at every property eval.

### HTC correlation interface (signature, docstrings)

- **D-04: HTC correlation signature `(Re, Pr, T_bulk, T_wall) -> Nu` stays unchanged. Docstrings updated to document the eval-point convention.** Every existing correlation (`dittus_boelter`, `constant_Nusselt`, `Marco_Han_Nusselt`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`, `elenbaas_htc`) keeps its current arity and types. Update the module-header comment in `src/physical_models/htc/correlations.jl` and each `(Re, Pr, T_bulk, T_wall)`-arity docstring to state: *"Callers should pass `Re` and `Pr` evaluated at `T_film = (T_bulk + T_wall)/2`. The Channel core in `src/components/channels.jl` does this."*

  `elenbaas_htc` is the lone exception that internally calls `beta_water(T_bulk)` / `mu_water(T_bulk) / rho_water(T_bulk)`. That stays at bulk per D-03. Its docstring gets a one-line note that NC fluid-property eval is at bulk by convention (Python match).

### Testing & success bar

- **D-05: Success = `simple_loop` `h_tc_left/right[i]` and downstream `q_density_*[i]` rows drop from FAIL into CLEAN or GRAY in the regenerated `test/data/parity_report.csv`.** Hard ceiling per Phase 56 D-04 = 0.02 rtol. Concrete:
  - All 20 `h_tc_left[1..10]` + `h_tc_right[1..10]` simple_loop rows: `tier ∈ {CLEAN, GRAY}` (was FAIL ~0.18-0.20 rtol).
  - All 30 `q_density_left/right/total[i]` simple_loop rows: `tier ∈ {CLEAN, GRAY}` (was FAIL).
  - No NEW FAIL rows introduced anywhere in the CSV (catches an accidental regression on T_out, T[i], mdot, T_wall, dP_loop).
  - MTR scenario rows continue to emit `solver_error` sentinels until Phase 58 ships — not Phase 57's job.

  *Rejected: stricter "h_tc rows must reach CLEAN (≤1e-6)" bar — aspirational but unreachable while residual `cp(T)` face-averaging differences and discretization differences sit in the pipeline. Setting that bar would leave Phase 57 unshippable.*

  *Rejected: explicit bar that T_out/T[i] rtol does not regress vs the Phase 56 baseline. The "no new FAIL rows" clause covers regression risk; a tighter "no GRAY-row rtol increases" assertion is overly mechanical given that film-T is expected to slightly perturb downstream T values (energy balance is correct but property-eval-point shift propagates).*

- **D-06: Re-run flow.** Planner's call on the wave shape, but the natural sequence is: (a) edit `_channel_core` per D-01/D-02/D-03, (b) update HTC correlation docstrings per D-04, (c) re-run `bin/jl test/runtests.jl` to regenerate `test/data/parity_report.csv`, (d) verify the CSV against D-05, (e) commit the regenerated CSV. A short MILESTONES.md narrative update for v1.1 close per Phase 56 D-09 is `parity_report.csv`-driven and may stay deferred until milestone close.

### Claude's Discretion

- Exact placement of the explanatory comment in `_channel_core` (D-03 cleanliness directive). Inline near `T_film_i = ...` is the obvious choice; planner picks final wording.
- Exact docstring wording for the eval-point convention note (D-04). Module-header `# htc/correlations.jl — ...` block plus per-correlation docstrings; planner picks the exact phrasing.
- Whether the `T_film_i` named local is a single variable or a Symbolics-friendly expression inlined three times. Both work; one named local is cleaner for the comment to anchor to.
- Wave decomposition (single plan vs split). Phase 57 is small; a single plan is most likely. Planner's call.
- Whether existing `test_correlations.jl` unit tests need any update. Likely none — they call `dittus_boelter(Re, Pr)` etc. with numeric Re/Pr and don't care about the eval point. Planner verifies.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and motivation
- `.planning/ROADMAP.md` §"Phase 57: HTC film-temperature evaluation" — phase entry (currently "[To be planned]"; this CONTEXT.md is the scope anchor).
- Commit `98fdbdc` message — original phase rationale (HTC drift evidence, gating v1.1 close).
- `.planning/phases/56-python-stream-cross-validation/56-CONTEXT.md` §D-01..D-13 — parity harness scope, three-tier verdict (CLEAN/GRAY/FAIL), 0.02 hard ceiling, simple_loop + MTR scenarios.
- `.planning/phases/56-python-stream-cross-validation/56-05-SUMMARY.md` — Phase 56 final harness state, pre-Phase-57 baseline.
- `.planning/phases/56-python-stream-cross-validation/deferred-items.md` D-1 — MTK API mismatch on MTR scenarios (Phase 58's job, not Phase 57's).

### Julia STREAM code (eval-site changes)
- `src/components/channels.jl:139` — friction `Re_i_for_friction` (stays at bulk T per D-03).
- `src/components/channels.jl:147,653-656,660-663` — HTC pipeline `Re_i`, `Pr_i`, `k_water(T[i])` evaluations to switch to `T_film_i` per D-01/D-02.
- `src/physical_models/htc/correlations.jl` — HTC correlation factories; signature stays `(Re, Pr, T_bulk, T_wall) -> Nu`; docstrings updated per D-04.
- `src/components/channels.jl:545-680` — `ChannelAndContacts` constructor + `_channel_core` SPL/SCB branches; the eval-site edits live in `_channel_core`.

### Python STREAM reference (the eval-point pattern being matched)
- `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/__init__.py:166,208-209` — `T_film = film(T_cool=T_cool, T_wall=T_wall)` then `cool = coolant_funcs.to_properties(T_film, pressure)` — this is the canonical "all HTC fluid-property evals at T_film" pattern.
- `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/temperatures.py:109-129` — `film_temperature(*, T_cool, T_wall) = (T_cool + T_wall) / 2`.

### Test artifacts (success bar)
- `test/data/parity_report.csv` — Phase 56 baseline; the regenerated post-Phase-57 version is the success-bar artifact.
- `test/test_validation.jl` §"Python parity: simple_loop" — testset that emits the simple_loop CSV rows; success-bar D-05 is checked here.

### Project conventions (constraints)
- `.planning/PROJECT.md` §"Current Milestone: v1.1" — Phases 57+58 gate v1.1 close; Phase 56 Plan 06 paused until both ship.
- `CLAUDE.md` §"MTK Patterns" — `ifelse()` for symbolic branches, `@register_symbolic` for fluid props, `mtkcompile` before solve. The eval-site edits stay inside the existing MTK-traced arithmetic; no new register-symbolic calls expected.
- `CLAUDE.md` §"Branching Policy" — single working branch `channels-redesign`; do NOT create a new branch for Phase 57.
- `CLAUDE.md` §"Performance — Daemon dev loop" — use `bin/jl test/runtests.jl` to re-run the parity harness; struct edits would force a daemon restart but Phase 57 only edits expressions, so Revise will hot-reload.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`mu_water`, `cp_water`, `k_water`, `rho_water`** (`src/fluids.jl`, `@register_symbolic`-wrapped): already MTK-compatible, accept symbolic `Num` arguments. Calling them with `T_film_i` (a symbolic expression) traces correctly — no new registration needed.
- **`_channel_core`** (`src/components/channels.jl:91-153`): the single shared private core consumed by `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts` (Phase 55 D-17 unification). Editing it once propagates to all three variants. Re/Pr are observed there (lines 147-149); the HTC pipeline lives in the variants (e.g., CAC's `_channel_core` invocation passes h_tc through).
- **HTC correlation 4-arg interface `(Re, Pr, T_bulk, T_wall) -> Nu`**: every existing correlation already conforms (verified via grep). No factory changes needed; only Re/Pr evaluation sites change.

### Established Patterns
- **Property eval site = call site convention** (existing in friction Re at channels.jl:139): the Channel body computes `Re_i = abs(mdot)*Dh/(A*mu_water(T[i]))` inline rather than asking the friction closure to do it. D-01 extends this same pattern to the HTC side — symmetric, no new convention introduced.
- **Single named local for repeated subexpression** (existing in `_channel_core` `cp_face`, `Re_i_for_friction`): keeps MTK trace small and readable. `T_film_i = (T[i] + T_w_i) / 2` follows this pattern.
- **MTK-traced arithmetic only, no `@register_symbolic` on derived quantities**: `T_film_i` is a plain arithmetic expression on symbolic `T[i]` and `T_w_i`; MTK traces through it transparently. No registration needed.
- **Phase 55 `_channel_core` change-once-propagate-everywhere**: edit in `_channel_core` lifts the eval point for `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts` simultaneously. Tests in `test_channels.jl` cover all three.

### Integration Points
- `_channel_core` SPL branch (channels.jl:653-656) — primary edit site (single-phase `h_tc[i]` equation).
- `_channel_core` SCB branch (channels.jl:660-663) — same edit, replicated. The `h_spl_i` lead expression mirrors SPL.
- Test re-run touchpoint: `bin/jl test/runtests.jl` regenerates `test/data/parity_report.csv` as a side-effect of the `Python parity: simple_loop` testset (Phase 56 wiring).
- No new files; no new exports; no changes to `STREAM.jl` module entry.

</code_context>

<specifics>
## Specific Ideas

- **User framing on D-03 cleanliness:** "Do option 1 here because it is identical to what happens in Python STREAM. But try to do this cleanly. Make it look as clean as possible." → Implementation must read as a single principled split (HTC=film, friction+NC=bulk) anchored by ONE explanatory comment, not as scattered ad-hoc per-call-site decisions. Planner: do not add `# bulk per Python` comments at every property eval; one block comment in `_channel_core` is the right shape.
- **Direct Python reference**: the canonical pattern to match is `T_film = film(T_cool=T_cool, T_wall=T_wall)` followed by `cool = coolant_funcs.to_properties(T_film, pressure)` at `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/__init__.py:208-209`. Read this before planning if there's any ambiguity about which properties film-T applies to.

</specifics>

<deferred>
## Deferred Ideas

- **`WaterProps@T_film` property-bundle abstraction** (mirror of Python's `coolant_funcs.to_properties(T_film, pressure)`). Rejected for Phase 57 as premature — no other STREAM.jl consumer. Revisit if/when AbstractFluid + multi-fluid work lands (v0.6+ per `project_fluids_longterm.md` memory).
- **HTC closure signature change to `(mdot, Dh, A, T_cool, T_wall) -> Nu`**. Would match Python's "h_spl owns the property eval" shape more literally. Defer; current 4-arg interface plus call-site eval is cleaner under D-01.
- **Friction Re film-T evaluation**. Diverges from Python; would introduce a new dP drift source. Not on any roadmap.
- **NC Gr/Re² film-T evaluation**. β,ν at bulk is the Python convention; not on any roadmap.
- **Stricter CLEAN-tier (≤1e-6) bar on h_tc rows**. Aspirational; blocked by upstream cp(T) face-averaging differences. Revisit if a future "exact same DAE" parity push lands.
- **MILESTONES.md v1.1 narrative entry update** with refreshed worst-drift number after Phase 57's CSV regeneration. Owned by Phase 56 D-09 / milestone-close cleanup, not Phase 57.

</deferred>

---

*Phase: 57-htc-film-temperature-evaluation*
*Context gathered: 2026-05-08*
