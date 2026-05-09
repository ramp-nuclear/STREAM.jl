# Phase 56: Python STREAM Cross-Validation - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase rebuilds Julia STREAM's Python-parity validation harness from scratch as a thorough one-to-one comparison between the two codes — not as a "diagnose VAL-01's 1.75% mdot drift" exercise. The deliverable is a per-quantity, per-cell comparison that establishes how close (or far) the Julia and Python steady-state results are, with a tiered verdict (clean ≤1e-6 / gray-zone reports drift / hard fail >1-2%).

**Two scenarios are seeded as the canonical Python↔Julia parity targets:**

1. **Canonical simple loop** — `Pump → HeatExchanger → ChannelAndContacts → Pump` (matches `test/generate_reference.py` topology). Cheapest one-to-one and the most-cited test.
2. **MTR plate (HD + 2× CAC)** — symmetric, asymmetric, and one-sided variants from `test/generate_mtr_reference.py`. The CAC↔HeatDiffusion connection is the v1.1 "main use case" per the user's foundational frame in Phase 55: "the main driver of what STREAM is and what people will use STREAM for revolves around the CAC and HeatDiffusion connection."

**Out of scope for the Python-parity rewrite (but other test_validation.jl content is kept):**
- LOF transient (`build_loop_lof_bypass`) full trajectory parity vs Python — deferred (future work copies Python integration tests one-to-one).
- PK + thermal feedback (`build_loop_pk`) full trajectory parity vs Python — already covered by v0.9 VAL-PK-01..03; not extended in v1.1.
- Existing `test_validation.jl` testsets that are NOT simple-loop or MTR (VAL-02 transient T_wall step, VAL-01 HeatDiffusion Fourier, VAL-02 two-plate one-channel, PointKinetics validation) — kept as-is, **not** rewritten.

**Frame shift (the central decision of this discuss):** the user explicitly does NOT want a "diagnose-and-accept" approach to the Phase 55 1.75% mdot drift. The drift is a curiosity, not the deliverable. The deliverable is a thorough one-to-one harness that *will tell us* what the drift is on every quantity, and where it comes from, without prejudging whether it's manifest-drift or enthalpy-form physics. Future work will copy Python integration examples and tests one-to-one and expect identical results — Phase 56 establishes the mechanism and the bar.

**Solver-floor truth (the aspirational claim):** "If we solve the same exact system in two codes, the result should be within solvers' tols." The harness aims for this; reality probably falls short on some quantities; the test reports the gap rather than burying it under a single `rtol=1%` `@test`.

</domain>

<decisions>
## Implementation Decisions

### Frame & scope

- **D-01: Rewrite, not diagnose.** Phase 56 is NOT scoped as "investigate the Phase 55 VAL-01 1.75% mdot drift." Phase 55 left that drift open as a known-open question, and the user explicitly reframed the phase: "We can worry a little less about [diagnosing manifest vs enthalpy]. The best thing to do is to rewrite the python and Julia reference and comparison, and make sure EVERYTHING is exactly one-to-one." The diagnostic answer falls out of the rewrite, not a separate manifest-bisect or per-cell-decomposition step.

- **D-02: Two parity scenarios in v1.1, not four.** The harness covers **(a) canonical simple loop** (Pump → HeatExchanger → ChannelAndContacts → Pump, matching `test/generate_reference.py`) and **(b) MTR plate via plate()/symmetric_plate()** (HeatDiffusion + 2× ChannelAndContacts, matching `test/generate_mtr_reference.py` symmetric / asymmetric / one-sided variants). Channel and ChannelHeatFlux variants are NOT seeded as parity targets — they're simplified-model fixtures and concept demos per the Phase 55 user frame. LOF transient and PK + feedback trajectories are explicitly out for v1.1 (future work copies Python integration tests one-to-one).

### Tolerance verdict tiers (D-03 is the central decision)

- **D-03: Three-tier verdict, not pass/fail.** Per-quantity rtol against the Python reference is binned:
  - **`rtol ≤ 1e-6` → CLEAN PASS.** Within solver convergence noise. The aspirational "same system in two codes" target.
  - **`1e-6 < rtol < ~1%` → GRAY ZONE.** Reported, not test-failed. The harness emits the per-quantity rtol value and a "GRAY" verdict; the milestone is allowed to close while drift sits in this band, *provided* the report is committed (D-08).
  - **`rtol > 1-2%` → HARD FAIL.** Test fails the suite. "Anything above this means something is obviously really wrong" — user's words. Concrete threshold: planner picks 1% or 2% per quantity; suggested default is 2% as the global hard floor (matches existing TEST-04 wording "≤1% rtol" with 2% slack for the hard ceiling).

  The middle band is where the existing 1.75% mdot drift sits. The test reports it as GRAY and shows the magnitude rather than failing or hiding it.

- **D-04: The hard ceiling is one number per quantity, not a global default.** Planner picks per-quantity hard ceilings: scalars (T_out, mdot, dP_loop) and per-cell coolant T[i] hard-fail at 2% rtol; per-cell wall T_wall[i] / h_tc[i] / q[i] and plate-side T(z,x) hard-fail at 2% rtol unless physics motivates a different threshold (e.g., HTC has known correlation-formulation sensitivity — could justify a wider band with documented rationale). Document the per-quantity threshold + rationale in `test_validation.jl` testset header comments and in `MILESTONES.md`'s v1.1 close note.

### Reference-value generation & sync

- **D-05: Both generators rewritten, current "regenerate-and-paste" pattern retained.** `test/generate_reference.py` and `test/generate_mtr_reference.py` are rewritten to emit ready-to-paste Julia const blocks that include all per-quantity references (not just `T_out` + `mdot`). The sync model stays: Python is run once at reference-update time, output is pasted into the Julia test file (or into a Julia-side data file under `test/data/`), CI runs Julia only. Zero Python runtime dependency in CI. This is the same pattern Phase 53's `stage2_reference.py` already uses — proven approach.

- **D-06: Python runtime is NOT added to CI.** Cross-import paths (PyCall / juliacall) were considered and rejected — adding Python to CI is explicitly out of scope per project decisions and would expand v1.1's surface area beyond what the milestone gate justifies. Drift detection across Python STREAM commits is handled out-of-band: the developer re-runs the generators when the upstream Python physics changes, pastes the new constants, and the harness's per-quantity drift report makes it obvious if anything moved.

### Quantities compared (parity surface)

- **D-07: All four tiers of quantities are compared — full coverage.** For each parity scenario, the harness compares ALL of the following:

  | Tier | Quantities | Scope |
  |---|---|---|
  | (a) Inlet/outlet scalars | `T_out`, `mdot`, `dP_loop` | Both scenarios |
  | (b) Per-cell coolant | `T[i]` for `i in 1:n` | Both scenarios |
  | (c) Per-cell wall (CAC-only) | `T_wall_left[i]`, `T_wall_right[i]`, `h_tc_left[i]`, `h_tc_right[i]`, `q_wall_left[i]`, `q_wall_right[i]` | MTR (CAC has these observables; simple-loop CAC also exposes them) |
  | (d) Plate-side | `T(z,x)` for `z in 1:nz`, `x in 1:nx` | MTR only |

  Tier (b) reveals whether enthalpy-form face-averaged cp matches Python's `pair_mean_1d` cell-by-cell (the central physics question Phase 53 introduced). Tier (c) reveals whether Dittus-Boelter HTC and the heat-transfer terms match Python's. Tier (d) reveals whether the 2D HD plate physics matches Python's plate calculation.

### Reporting (drift visibility)

- **D-08: Both reporting channels — printed table AND committed CSV.** The harness emits BOTH:
  - **Stdout drift table** during test execution: per-quantity rtol value + verdict (CLEAN / GRAY / FAIL). Picked up by `bin/jl test/runtests.jl` log; visible to the developer at every test run.
  - **Committed CSV artifact** at `test/data/parity_report.csv` (or similar — planner picks the exact path): per-quantity rtol values for both scenarios, gitted. Diffable across milestones — future regressions are visible in `git diff`.

  The CSV is the auditable record; the printed table is the live developer signal. Same data, two surfaces.

- **D-09: MILESTONES.md narrative entry on v1.1 close.** When v1.1 closes, MILESTONES.md gains a "v1.1 closed: parity drift = X% on Y" entry that names the worst per-quantity drift in the gray zone with sign and magnitude. Per ROADMAP success criterion 3 ("Any drift introduced strictly by the enthalpy-form switch is documented in MILESTONES.md with sign and magnitude").

### Equivalence checklist (the "same system" foundation)

- **D-10: Explicit equivalence checklist + test-time asserts.** Before the parity check runs, the harness asserts that Python and Julia are solving the same problem. Failure aborts before the parity check (so a false-positive parity pass can't happen because we accidentally compared apples and oranges). Concrete checklist items, all asserted at test setup:

  - **Fluid properties at three reference T values** (e.g., 313.15 K / 343.15 K / 373.15 K): `rho_water`, `cp_water`, `mu_water`, `k_water` Julia values match Python `light_water` correlations within 1e-12 rtol. (Same approach as Phase 53 stage2_reference.py byte-for-byte verification.)
  - **Dittus-Boelter coefficients** (0.023, 0.8, 0.4) match.
  - **Blasius friction coefficients** (0.316, 0.25 exponent) match.
  - **Geometry** for each scenario: `Dh`, `A`, `wet_perimeter`, `heated_parts` — Julia values match Python equivalents.
  - **Solver tolerances**: Sundials KINSOL `atol`, `rtol` on Julia side documented; Python solver tols documented; if they're different, that's documented as a known equivalence gap (not a hard fail).
  - **IC anchors**: pump inlet pressure anchor (`pump.port_in.P ~ 1.0e5`) matches Python's absolute-pressure reference.

  Document the checklist in `test_validation.jl` docstring or a sibling helper file (`test/parity_helpers.jl` — planner picks). Each assert prints what it checked on stdout; the equivalence verdict is part of the parity report.

- **D-11: Document known equivalence gaps explicitly.** If a checklist item can't be made identical (e.g., Sundials KINSOL atol/rtol vs Python's solver), document the gap with magnitude and rationale. The drift report references the documented gap when interpreting per-quantity rtol values. This converts "we don't know why drift is X" into "drift is X; here are the documented equivalence gaps that may contribute, in order of likely magnitude."

### Milestone close gate

- **D-12: Hard-floor pass + drift report committed = milestone closes.** Milestone close requires:
  1. Hard `@test` (per-quantity 1-2% rtol ceiling, D-04) green across all parity scenarios.
  2. Drift report (`test/data/parity_report.csv`) committed with the milestone-close commit.
  3. `MILESTONES.md` "v1.1 closed: parity drift = X% on Y" entry added (D-09).
  4. Existing test_validation.jl content (D-13) still green where it was green pre-Phase-56.
  5. Branch `channels-redesign` clean; full local test suite has no NEW failures vs the v1.1-end baseline (carries the Phase 55 D-22 framing forward — no new regressions, pre-existing flakies tolerated).
  6. `_channel_base_eqs` / `observed_mode` / `skip_htc` references absent from the codebase (ROADMAP success criterion 4 explicit grep).

  Gray-zone drifts are documented, NOT blocking. Strict-tier (≤1e-6) achievement is the aspirational target, not a milestone gate.

### Existing test_validation.jl disposition

- **D-13: Existing testsets kept; only simple-loop + MTR Python-parity sections rewritten.** `test/test_validation.jl` currently has 8 testsets across 759 lines:
  - `VAL-01: Steady-state matches Python STREAM within 1%` (simple loop) — **REPLACED** by the new one-to-one harness for tiers (a)+(b).
  - `VAL-02: Transient T_outlet rises after T_wall step` — **KEPT** as-is. Not a Python-parity test (qualitative `T_ts[end] > T_ts[1]` assertion).
  - `VAL-01: Symmetric MTR — HeatDiffusion + two ChannelAndContacts` — **REPLACED** by the new harness for tiers (a)+(b)+(c)+(d).
  - `VAL-02: Asymmetric MTR — right channel at 363.15 K inlet` — **REPLACED**.
  - `VAL-03: One-sided MTR — left channel only, thermal_right adiabatic` — **REPLACED**.
  - `VAL-01: HeatDiffusion transient — Fourier series validation` — **KEPT** as-is. Pre-existing flaky per Phase 55 D-22 (numerical baseline drift), tolerated.
  - `VAL-02: Two-plate one-channel topology — both faces active` — **KEPT** as-is. Energy-balance assertion, not Python-parity.
  - `PointKinetics validation` — **KEPT** as-is. v0.9 VAL-PK-01..03 quantitative assertions vs Python — already validated.

  The replaced testsets become a new section structure (planner picks naming, e.g., `Python parity: simple loop` / `Python parity: MTR symmetric` / `Python parity: MTR asymmetric` / `Python parity: MTR one-sided`).

### File structure

- **D-14: `test/test_validation.jl` stays the home — single-file.** No split into `test_validation_simple.jl` + `test_validation_mtr.jl` etc. Phase 55 D-22 already named `test_validation.jl` as the parity home. Keep it one file. Section comments + helper functions organize it internally.

- **D-15: `test/parity_helpers.jl` (NEW, optional) for harness machinery.** Planner picks: either inline the equivalence checklist + drift-report machinery in `test_validation.jl`, or factor into a sibling `test/parity_helpers.jl` that's `include`-d by `test_validation.jl`. The latter is cleaner if the machinery exceeds ~100 lines. NOT included in `runtests.jl` directly (it's a helper, not a testset).

- **D-16: `test/data/parity_report.csv` (NEW) — committed artifact.** Per D-08. Planner picks the exact format (long vs wide, scenario column scheme).

- **D-17: `test/generate_reference.py` and `test/generate_mtr_reference.py` rewritten.** Both files emit per-quantity references covering all four tiers from D-07 (not just T_out + mdot). The output format is "ready-to-paste Julia const block" matching the Phase 53 `stage2_reference.py` pattern. Planner decides whether the Python output goes into `test_validation.jl` directly (current pattern) or into a sibling `test/data/python_parity_reference.jl` data file that `test_validation.jl` includes (cleaner separation if the const blocks are large).

### Claude's Discretion

- **Per-quantity hard-ceiling threshold.** Default 2% rtol globally; planner can widen specific quantities (e.g., HTC with documented correlation-formulation sensitivity) with rationale.
- **Stdout drift-table format.** Aligned ASCII table is the default; planner picks columns and row order.
- **CSV schema** at `test/data/parity_report.csv` — long vs wide, exact column names. As long as it's diffable in `git diff` and human-readable.
- **Equivalence checklist exact items** — the D-10 list is the seed; planner adds items as discovered (e.g., specific HTC-correlation regime params, pump-side anchor conventions).
- **Whether `parity_helpers.jl` is a new file (D-15)** — based on machinery size.
- **Whether new Julia-side reference data lives inline in `test_validation.jl` or in `test/data/python_parity_reference.jl`** (D-17).
- **MILESTONES.md narrative wording** for the v1.1 close entry (D-09).
- **Wave / plan decomposition.** Planner's call. Suggested shape: (a) rewrite generators to emit per-quantity reference; (b) regenerate Python references against current Python STREAM HEAD; (c) build `parity_helpers.jl` with equivalence checklist + drift-report machinery; (d) rewrite the four parity testsets in `test_validation.jl`; (e) commit `parity_report.csv` and update `MILESTONES.md`; (f) milestone-close cleanup grep + branch verification. Atomic per-wave commits.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 56: Python STREAM Cross-Validation" — phase goal, dependencies, four success criteria. Note: criterion 1 wording ("≤1% rtol") is preserved in spirit but reinterpreted via the D-03 three-tier verdict (≤1e-6 clean / gray-zone / >2% hard fail).
- `.planning/REQUIREMENTS.md` §"Tests, Examples, Composition" — TEST-04 (the sole Phase 56 requirement). Pending.
- `.planning/PROJECT.md` §"Current Milestone: v1.1 Final Channel-Family Redesign" — milestone goal, "Cross-validation against Python STREAM passes within existing tolerances after the enthalpy-form switch."
- `.planning/STATE.md` §"Current Position" — Phase 56 ready-to-plan; v1.1 single-PR delivery on `channels-redesign` branch.

### Prior phase decisions to honor
- `.planning/phases/55-composition-helpers-examples-test-suite/55-CONTEXT.md` — Phase 55 D-17 (`test_channels.jl` rewritten under new design), D-22 (TEST-05 close gate; pre-existing flakies tolerated baseline). The 14-file test layout is locked; `test_validation.jl` is the parity home.
- `.planning/phases/55-composition-helpers-examples-test-suite/55-VERIFICATION.md` — VAL-01 1.75% mdot drift documented as "manifest-drift tolerated flaky pending Phase 56 deeper investigation"; Phase 56 reframes that investigation as a from-scratch parity-harness rewrite (D-01).
- `.planning/phases/55-composition-helpers-examples-test-suite/55-HUMAN-UAT.md` — entry #1 explicitly defers VAL-01 numerical investigation to Phase 56 TEST-04.
- `.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md` — enthalpy-form energy balance D-01..D-14; Stage-2 Python parity G2 byte-for-byte pattern (the model for the equivalence checklist in D-10).

### The drift question (background, NOT prescriptive)
- Phase 55's `55-VERIFICATION.md` lines on VAL-01 — frames the open question as "manifest-drift vs enthalpy-form." Phase 56 explicitly does NOT take this framing as the deliverable; the deliverable is the harness rewrite (D-01). The drift falls out of the rewrite.

### Existing code (read before extending)
- `test/test_validation.jl` (759 lines, 8 testsets) — the file being modified. Simple-loop + MTR Python-parity testsets (5 of 8) are REPLACED by the new harness (D-13); the other 3 testsets are KEPT as-is (VAL-02 transient step, HD Fourier, two-plate one-channel, PK validation).
- `test/generate_reference.py` — Python-side reference generator for the simple loop. REWRITTEN per D-17 to emit per-quantity references covering all D-07 tiers.
- `test/generate_mtr_reference.py` — Python-side reference generator for MTR symmetric / asymmetric / one-sided. REWRITTEN per D-17 to emit per-quantity references covering all D-07 tiers (including plate-side `T(z,x)` for tier (d)).
- `test/data/stage2_reference.py` — Phase 53's byte-for-byte reference generator. **Pattern source** for D-10 (equivalence checklist with 1e-12 rtol assertions on fluid properties + correlation coefficients).
- `src/components/channels.jl` — `_channel_core` (line 84+) is where enthalpy-form face-averaged cp lives; ChannelAndContacts (lines 533-717) exposes the per-cell observables (`T_wall_left[i]`, `h_tc_left[i]`, `q_wall_left[i]`, etc.) that tier (c) compares.
- `src/composition/helpers.jl` — `symmetric_plate`, `plate`, `one_sided_connection` for the MTR scenarios.
- `src/examples.jl` — `build_loop` (simple loop scenario builder; lines 56+) is what the simple-loop parity testset constructs against.
- `src/fluids.jl` — `rho_water`, `cp_water`, `mu_water`, `k_water` `@register_symbolic` correlations. Tier (a) of the equivalence checklist asserts these match Python's `light_water` at three reference T values within 1e-12 rtol.
- `src/physical_models/htc/correlations.jl` — Dittus-Boelter coefficients. Equivalence checklist asserts the 0.023, 0.8, 0.4 constants match Python.
- `src/physical_models/friction/correlations.jl` — Blasius friction coefficients. Equivalence checklist asserts the 0.316, 0.25 exponent match Python.

### Python STREAM reference
- `~/projects/STREAM/stream/calculations/channel.py` — Python `Channel.calculate(...)` and `ChannelAndContacts.calculate(...)`. The `pair_mean_1d` averaging is the Python-side enthalpy-form analog Julia's `_channel_core` mirrors.
- `~/projects/STREAM/stream/substances/light_water.py` — Python fluid-property correlations. Equivalence checklist asserts byte-for-byte parity at three reference T values.
- `~/projects/STREAM/stream/utilities.py` `pair_mean_1d` — Python's face-averaged cp helper. The Julia enthalpy-form energy balance in `_channel_core` mirrors this.

### Existing memory references
- `feedback_channel_hd_connection_rule.md` — HeatDiffusion connects ONLY to ChannelAndContacts. The MTR scenarios in D-02 honor this rule (CAC↔HD via plate/symmetric_plate/one_sided_connection).
- `project_v1_goal.md` — v1.0 goal "complete MTR plate-fuel safety analysis (not full Python STREAM parity)." v1.1's closing milestone gate is the Python-parity harness on the MTR + simple-loop scope, not full library parity.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 53's `stage2_reference.py` pattern** (`test/data/stage2_reference.py`) — pure-Python fallback that re-implements Python STREAM formulas inline + verified byte-for-byte against the upstream Python source. The "ready-to-paste Julia const block" output format is the model for D-17's generator rewrite. Equivalence-checklist 1e-12 rtol asserts (D-10) mirror Stage-2's verification approach.
- **Existing `generate_reference.py` + `generate_mtr_reference.py` topologies** — already encode the simple-loop and MTR scenarios that D-02 names as the parity targets. The geometry, BC, and solver setup are reusable; only the *outputs* (per-quantity references for all four D-07 tiers) need expansion.
- **Existing `test_validation.jl` testset structure** — section-comment style and `@testset "VAL-..."` naming convention are the template for the new "Python parity: ..." testset names.
- **`src/fluids.jl` `@register_symbolic` correlations** — already callable from any MTK equation; equivalence checklist evaluates them at three reference Ts directly without any new plumbing.
- **CAC's `@observed` quantities** (`T_wall_left[i]`, `h_tc_left[i]`, `q_wall_left[i]`, etc.) — already extracted post-solve via `sol[ssys.cac.T_wall_left[i]]`. Tier (c) of D-07 reads these directly; no new observable additions needed.
- **HeatDiffusion's `T(z,x)` 2D state** — already accessible post-solve via `sol[ssys.hd.T[z, x]]` for `z in 1:nz, x in 1:nx`. Tier (d) of D-07 reads this directly.

### Established Patterns
- **Hardcoded Python reference constants in Julia tests** (`test/test_validation.jl`'s `T_outlet_ref = 327.7894`) — committed to repo, no Python runtime in CI. D-05 / D-06 keep this pattern; D-17 expands the constants per D-07's quantity list.
- **`steady_state_guess` + `solve_steady` invocation pattern** (`test/test_validation.jl:21-25`) — IC seeding for the steady-state nonlinear solve. Reused by the new parity testsets unchanged.
- **`@testset "VAL-..."` naming** + section-comment headers — template for the new "Python parity: ..." testsets. D-13 KEEPS the existing testsets unchanged where they're not Python-parity (VAL-02 transient step, HD Fourier, two-plate, PK).
- **`@test isapprox(...; rtol=...)`** — the existing pass/fail mechanism. Phase 56 extends this with a printed-table + CSV reporting layer (D-08) so gray-zone drifts surface as data, not just a binary `@test` outcome.

### Integration Points
- **`test/test_validation.jl`** — modified per D-13 (5 testsets replaced, 3 testsets kept). New testsets named "Python parity: simple loop", "Python parity: MTR symmetric", "Python parity: MTR asymmetric", "Python parity: MTR one-sided" (planner-picked exact names).
- **`test/generate_reference.py`** — REWRITTEN per D-17. Output expanded to cover all D-07 tiers.
- **`test/generate_mtr_reference.py`** — REWRITTEN per D-17. Output expanded to cover all D-07 tiers including plate-side `T(z,x)`.
- **`test/parity_helpers.jl`** (NEW, optional per D-15) — equivalence checklist + drift-report machinery. `include`-d by `test_validation.jl` if separated; otherwise inlined.
- **`test/data/parity_report.csv`** (NEW per D-08) — per-quantity rtol artifact. Committed.
- **`test/data/python_parity_reference.jl`** (NEW, optional per D-17) — Julia-side reference data (large const blocks). Generator output destination if planner picks file separation over inline-in-test_validation.jl.
- **`runtests.jl`** — UNCHANGED (test_validation.jl is already wired in).
- **`.planning/MILESTONES.md`** — gains v1.1-close narrative entry per D-09. Single edit at milestone-close time.
- **`.planning/REQUIREMENTS.md`** — TEST-04 marked complete at milestone close.
- **`.planning/ROADMAP.md`** — Phase 56 marked complete at milestone close.
- **No `src/` changes expected.** Phase 56 is test-only by design; if the harness uncovers a physics divergence requiring a `src/` fix, that's a deviation that gets escalated, not absorbed silently.

</code_context>

<specifics>
## Specific Ideas

- **User's foundational frame (this discuss):** "We can worry a little less about [diagnosing the 1.75% drift]. The best thing to do is to rewrite the python and Julia reference and comparison, and make sure EVERYTHING is exactly one-to-one. After that the comparison should be one to one in all timesteps (if its transient) in all parameters that are expected to be identical. We should do this extremely thoroughly because this is the most important part." This is the DOC-01 license: phase scope is the rewrite, not the diagnosis. The drift answer falls out of the rewrite.

- **User's solver-floor truth (this discuss):** "If we solve the same exact system in two codes, the result should be within solvers' tols. That much is obvious. But the problem is that I don't know if we are there yet. Maybe we can do a max tolerance of 1-2%, meaning if the tol is higher than that something is obviously really wrong. If the tol is 1e-6 or below, we are perfectly fine. But, anywhere in between is a gray zone and that test might not be a 'pass or fail' at this point, but more of a 'how close are we'. This is probably what we want to do right now." This is the D-03 three-tier verdict in the user's own words. The middle band is reported, not buried; the harness is honest about distance from the solver-floor truth.

- **User's "everything one-to-one" framing on quantities (this discuss):** "All parameters that are expected to be identical." Translated by the AskUserQuestion turn into the four-tier list (D-07): inlet/outlet scalars, per-cell coolant T[i], per-cell wall T_wall[i] + h_tc[i] + q[i], plate-side T(z,x). User selected ALL four — full coverage, no skipping.

- **User's "extremely thoroughly" emphasis:** "We should do this extremely thoroughly because this is the most important part." Justifies the equivalence checklist + 1e-12 rtol fluid-property asserts (D-10) over a faster "trust the generators" approach (D-10's rejected option). The thoroughness extends to documenting equivalence gaps explicitly (D-11) so drift interpretation is grounded.

- **Future-work signal (the v1.2+ implication):** "In future work we will copy integration examples and tests from python STREAM one-to-one and expect the same results." Phase 56's harness is the *mechanism* future work plugs into. The two scenarios in v1.1 (D-02) are the seed; v1.2+ adds LOF transient parity, PK trajectory parity, channel/CHF parity, etc. by following the same pattern. Implication for D-15 / D-17: planner should design `parity_helpers.jl` and the generator-output format with extensibility in mind — adding a third / fourth / Nth scenario should be a "copy this template" exercise, not a rewrite.

- **User's "two parity scenarios, not four" decision (this discuss):** Selected simple loop + MTR plate; explicitly NOT LOF transient or PK + thermal feedback. Reads as "centerpiece use case first" — CAC↔HD is the v1.1 main driver per the Phase 55 user frame, and steady-state is the cheapest one-to-one. LOF and PK trajectories are deferred not because they don't matter but because the harness mechanism needs to exist before they're worth porting.

- **User's "do them both" decision on reporting (this discuss):** Both stdout drift table AND committed CSV artifact. The stdout is for the developer in the moment; the CSV is the auditable record. Accepts the small storage cost for the diffable history.

</specifics>

<deferred>
## Deferred Ideas

- **LOF transient Python-parity** — full trajectory comparison `build_loop_lof_bypass` vs Python's PCS-coastdown integration test. User explicitly deferred from v1.1. Picks up in v1.2 or later, copying Python integration tests one-to-one onto the Phase 56 harness mechanism.

- **PK + thermal feedback Python-parity** — full trajectory comparison `build_loop_pk` vs Python's Tfuel + Tcool feedback integration test. User explicitly deferred. Some coverage already exists via v0.9 VAL-PK-01..03 (prompt-jump, beta-effective, reactivity insertion); a full per-timestep parity harness extends that and is future work.

- **Channel / ChannelHeatFlux parity scenarios** — neither variant seeded in v1.1 per the Phase 55 user frame ("simplified-model fixtures and concept demos"). Could be added later if downstream consumers care.

- **Manifest-drift root cause investigation** — explicitly NOT a Phase 56 deliverable per D-01. If the harness's drift report identifies a manifest-drift culprit (MTK / Sundials / Symbolics version), that's a separate investigation in a future maintenance phase, not Phase 56.

- **Python STREAM cross-import via PyCall / juliacall** — D-06 explicitly out for v1.1. Strongest possible drift detection but requires Python in CI. Picks up if v1.2+ work makes that overhead worthwhile.

- **Auto-regenerate Python reference in CI** — D-05 explicitly out. Requires Python in CI. Future enhancement when reference-drift-detection-on-PR becomes high enough priority.

- **`test_validation.jl` split into per-scenario files** (D-14 explicitly NOT chosen) — could revisit once parity_helpers.jl machinery shows whether the file is unwieldy. Out of v1.1 scope.

- **Strict-tier (≤1e-6) achievement as a milestone gate** — D-12 makes hard-floor + drift-report-committed the gate; strict-tier is aspirational, not blocking. If/when strict-tier becomes achievable, future milestone could promote it to a gate.

- **Parity harness for Channel/CHF flow-reversal scenarios** — flow-reversal sign safety is already tested in test_channels.jl (Phase 55 D-17), but a Python-parity flow-reversal scenario doesn't exist on either side. Could be future work if Python STREAM gains a flow-reversal integration test.

- **HTC-correlation regime-switching parity (e.g., NC via Gr/Re²>1)** — would require Python STREAM having a matching NC mode test. Defer until Python side has the comparison point.

- **MILESTONES.md / PROJECT.md / STATE.md updates** — D-09 names the MILESTONES.md narrative entry. PROJECT.md "Current Milestone" → "Shipped" transition + STATE.md key-decisions append happen at `/gsd:complete-milestone` time, not in Phase 56 itself. Listed here so they're not forgotten.

</deferred>

---

*Phase: 56-Python STREAM Cross-Validation*
*Context gathered: 2026-05-08*
