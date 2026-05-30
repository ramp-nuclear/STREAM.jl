---
phase: 53-shared-channel-core-with-enthalpy-form-energy-balance
plan: 04
subsystem: channels
tags: [julia-mtk, deletion, flag-removal, phase-close, pitfall-4-option-a]

# Dependency graph
requires:
  - phase: 53-shared-channel-core-with-enthalpy-form-energy-balance/01
    provides: "Pitfall 4 Option A lock-in (deletion + inlining at the final commit chain), STAGE1/STAGE2 baselines, _StubChannelCore harness scaffolding"
  - phase: 53-shared-channel-core-with-enthalpy-form-energy-balance/02
    provides: "_channel_core(...) with enthalpy-form energy balance and full observable surface"
  - phase: 53-shared-channel-core-with-enthalpy-form-energy-balance/03
    provides: "G1 (rtol=1e-6 vs v1.0 baseline), G2 (rtol=1e-9 vs Python pair_mean_1d), G3/G3b (forward/reverse mirror), G4 (branch coverage) — all green on _channel_core"
provides:
  - "_channel_base_eqs deleted from src/components/channel.jl (CORE-02; ROADMAP success criterion #1)"
  - "observed_mode/skip_htc/T_wall_cells flag knobs eliminated from src/ (CORE-03/04/05; ROADMAP success criterion #2)"
  - "ChannelAndContacts and ChannelHeatFlux carry inlined per-variant equation blocks (constant-cp form, byte-identical to legacy helper) — Phase 54 will migrate them onto _channel_core"
  - "Phase 53 closure gate: full channel-family test suite + G1-G4 gates green; only pre-existing NET-03 KINSol flake remains"
affects:
  - 54-channel-family-variants  # Phase 54 inherits the inlined CAC/CHF blocks for migration onto _channel_core
  - 55-composition-helpers
  - 56-cross-validation-python-stream

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pitfall 4 Option A: delete legacy helper + inline body into call sites in same plan; each commit boundary leaves the working tree buildable (Task 1 cleans CAC, Task 2 cleans CHF, Task 3 deletes the now-unreferenced helper)"
    - "Variant-local inlined equation blocks (transitional): observed_mode=true behavior baked into CAC's inlined block (Re/Nu/v stay observed, h_tc uses inlined Re_i/Pr_i/T_w_i with thermal_left[i].T); observed_mode=false behavior baked into CHF's inlined block (v[i]/Re[i]/Nu[i]/h_tc[i] all pushed as solver unknowns)"

key-files:
  created: []
  modified:
    - "src/components/channel.jl: -111 / +5 lines. Deleted _channel_base_eqs (lines 146-249) and its 26-line block-comment header. Updated file-header comment at line 1 to reference _channel_core. Rewrote the _channel_core block-comment (lines 251-261 in pre-state) to drop the now-defunct 'coexists with legacy helper' language. _channel_core (introduced by Plan 02) is now the only underscore-prefixed function in the file."
    - "src/components/thermal_channel.jl: ChannelAndContacts (lines 105-131 pre-state) and ChannelHeatFlux (lines 322-342 pre-state) call sites of _channel_base_eqs replaced with the equivalent inlined equation blocks. Local _T_wall_cells temp removed from CAC. Block-comments rewritten to drop literal flag-knob references."
    - "test/test_channel_core.jl: comments rewritten to drop literal '_channel_base_eqs' references in narrative text (G1 docstring, STAGE1_BASELINE_* capture comments, sanity-check comment) — narrative content unchanged, just generic terminology."

key-decisions:
  - "Pitfall 4 Option A executed as planned: 3 atomic commits (CAC inline → CHF inline → helper deletion) rather than a single mega-commit. Each commit boundary leaves the project buildable and the channel-family tests passing. This satisfies CORE-02 (helper deletion) and the D-13 commit-boundary invariant simultaneously."
  - "test/test_channel_core.jl narrative comments updated to satisfy the strict 'grep -rn _channel_base_eqs src/ test/ returns ZERO hits' acceptance criterion (CORE-02 / ROADMAP #1). The helper symbol is referenced nowhere in the codebase — neither code nor docs in versioned files. Phase-53 plan-package files (PLANs, SUMMARYs, RESEARCH, etc.) deliberately retain the literal name as historical record (the audit only covers src/ and test/, per the plan)."
  - "Inlined CAC/CHF blocks deliberately preserve the OLD constant-cp form (cp_water(T[i]) in numerator AND denominator) — they do NOT switch to the enthalpy form here. Phase 54's variant rewrite migrates them onto _channel_core (which has the enthalpy form). This was the explicit Option A design (CONTEXT line 26): Phase 53 ships the shared core + the energy-balance switch ONLY for _channel_core; variant migration is Phase 54's mandate."

patterns-established:
  - "Phase 53 closure gate format: four negative grep audits (one for each deleted symbol) + G1-G4 gates + existing CHAN-*/GRAV-*/THERM-*/PHY-*/SIGN-* tests, all gated together. Future deletion plans can mirror this structure."
  - "Comment-rewrite as part of grep-audit hygiene: when a deletion plan mandates 'grep returns zero hits', narrative comments referencing the deleted symbol must also be rewritten — generic terminology preserves the explanation while clearing the audit."

requirements-completed: [CORE-02, CORE-03, CORE-04, CORE-05]

# Metrics
duration: ~31 min
completed: 2026-05-06
---

# Phase 53 Plan 04: Delete `_channel_base_eqs` + inline into CAC/CHF Summary

**Phase 53 closes: legacy `_channel_base_eqs` helper fully removed from `src/`; ChannelAndContacts and ChannelHeatFlux carry inlined per-variant equation blocks (constant-cp, transitional); `_channel_core` is now the sole shared channel-family helper, ready for Phase 54 variant migration.**

## Performance

- **Duration:** ~31 min
- **Started:** 2026-05-06T21:08:00Z (session start, post-handoff)
- **Completed:** 2026-05-06T21:39:00Z
- **Tasks:** 3 (all type="auto", autonomous, no checkpoints)
- **Files modified:** 3 (`src/components/channel.jl`, `src/components/thermal_channel.jl`, `test/test_channel_core.jl`)
- **Net diff vs parent commit `6c9bc95`:** +77 / -173 lines (net -96; the deletion of `_channel_base_eqs` outweighs the inlining duplication because the helper carried branching code paths that the variant-specific inlined blocks no longer need)

## Accomplishments

- **`_channel_base_eqs` is deleted from `src/`.** The legacy helper that had served as the shared body for ChannelAndContacts and ChannelHeatFlux through ~9 phases of accreted flag knobs (`observed_mode`, `skip_htc`, `T_wall_cells=nothing`) is gone. `grep -rn '_channel_base_eqs' src/ test/` returns ZERO hits.
- **Flag knobs eliminated.** `grep -rn 'observed_mode\|skip_htc\|T_wall_cells' src/` returns ZERO hits. The variant-specific behavior that the flags used to encode is now inlined directly at each call site (CAC = the old `observed_mode=true, skip_htc=(scb_correction !== nothing)` path; CHF = the old default `observed_mode=false` path with the scalar `T_wall_p` substituted for `T_wall_cells`).
- **Plan 03 gates G1/G2/G3/G3b/G4 still green.** Plan 04 did not touch `_channel_core`, so the enthalpy-form numerical parity with the v1.0 baseline (G1, rtol=1e-6) and Python pair_mean_1d (G2, rtol=1e-9) is preserved unchanged.
- **Existing channel-family tests pass byte-identically.** CHAN-01/02/03, GRAV-01/02, THERM-01/02/03, SIGN-01/02/03 (all four sub-numbers), PHY-01/05 — the inlined equation blocks emit the same MTK system that `_channel_base_eqs(...)` produced, so the regression suite is silent.
- **Phase 53 closure satisfies all four CORE-* requirements.** CORE-01 was Plan 02 (`_channel_core` exists). CORE-02 (delete legacy helper), CORE-03 (no `observed_mode`), CORE-04 (no `skip_htc`), CORE-05 (no `T_wall_cells`) all close in this plan. Combined with NRG-01..04 (closed by Plan 02 + Plan 03 gates), Phase 53 is COMPLETE.

## Task Commits

Each task was committed atomically. Per Pitfall 4 Option A (locked in Plan 01), each commit boundary leaves the working tree buildable and the channel-family tests passing:

1. **Task 1: Inline `_channel_base_eqs` body into ChannelAndContacts (CAC)** — `c9da9c1` (refactor)
   - Replaced the `_channel_base_eqs(...)` call (lines 105-131 pre-state) with the equivalent inlined block. Local `_T_wall_cells = [thermal_left[i].T for i in 1:n]` removed. The `observed_mode=true` behavior (Re/Nu/v stay as observed; h_tc uses inlined `Re_i`/`Pr_i`/`T_w_i = thermal_left[i].T`) is baked in. The `skip_htc=(scb_correction !== nothing)` semantic is encoded by the `if scb_correction === nothing` guard around the per-cell h_tc loop. After this commit: CAC region of `thermal_channel.jl` has zero references to `_channel_base_eqs`/`observed_mode`/`skip_htc`/`T_wall_cells`/`_T_wall_cells`. CHF still calls the helper (Task 2 handles).

2. **Task 2: Inline `_channel_base_eqs` body into ChannelHeatFlux (CHF)** — `5bbc522` (refactor)
   - Replaced the `_channel_base_eqs(...)` call (lines 322-342 pre-state) with the equivalent inlined block. The default `observed_mode=false` semantic (push v[i]/Re[i]/Nu[i]/h_tc[i] as solver unknowns) is baked in. The previous `T_wall_cells=fill(T_wall_p, n)` substitution becomes the scalar `T_wall_p` inline (uniform across cells, declared in the @parameters block). After this commit: thermal_channel.jl has ZERO references to the deleted symbols anywhere. The CAC block-comment was also rewritten to drop the literal flag-knob terminology.

3. **Task 3: Delete `_channel_base_eqs` from `channel.jl`; rewrite test comments** — `68ade99` (refactor)
   - Deleted the helper (was lines 146-249 pre-state) and its 26-line block-comment header. Updated the file-header comment at line 1: "channel.jl — Channel component and `_channel_base_eqs` helper" → "channel.jl — Channel component and `_channel_core` helper". Rewrote the `_channel_core` block-comment (lines 251-261 pre-state) to drop the now-defunct "Coexists with the legacy `_channel_base_eqs` above" language; the D-13 coexistence window has closed. Also rewrote 4 narrative comments in `test/test_channel_core.jl` (G1 docstring, STAGE1_BASELINE_* capture rationale, sanity-check comment, phase-ownership header) to drop literal references to the deleted symbol — same narrative, generic terminology — so that the strict `grep -rn '_channel_base_eqs' src/ test/` audit returns ZERO hits.

## Files Created/Modified

- **`src/components/channel.jl`** (-111 / +5) — `_channel_base_eqs` and its block-comment header deleted. File-header comment updated. `_channel_core` block-comment rewritten to drop coexistence language. `Channel` constructor (lines 26-144) UNCHANGED — Phase 54 rewrites it onto `_channel_core`.
- **`src/components/thermal_channel.jl`** (+32 / -27 net) — ChannelAndContacts (`_channel_base_eqs` call → inlined `observed_mode=true` body, `skip_htc=(scb_correction !== nothing)` encoded by `if scb_correction === nothing` guard) and ChannelHeatFlux (`_channel_base_eqs` call → inlined `observed_mode=false` body with `T_wall_p` scalar substitution).
- **`test/test_channel_core.jl`** (-23 / +23 narrative comment rewrite) — G1 docstring, STAGE1_BASELINE_* capture comments, sanity-check comment, phase-ownership header — all rewritten to drop literal `_channel_base_eqs` references. Test logic UNCHANGED; constants UNCHANGED.

## Final Phase 53 grep audits (closure gate)

```bash
# CORE-02: legacy helper deleted (ROADMAP success criterion #1)
$ grep -rn '_channel_base_eqs' src/ test/
(no hits)

# CORE-03 + CORE-04 + CORE-05: flag knobs eliminated (ROADMAP success criterion #2)
$ grep -rn 'observed_mode\|skip_htc\|T_wall_cells' src/
(no hits)

# NRG-03 (Pitfall 3): cp_water grep audit — non-cancellation evidence
$ grep -cE '^[^#]*cp_water\(' src/components/channel.jl
9       # > pre-Phase-53 baseline of 5; Plan 02's _channel_core has 4 new cp_water in the energy-balance loop (cp_face + cp_denom × 2 branches), unchanged by Plan 04
$ grep -cE '^[^#]*cp_water\(' src/components/thermal_channel.jl
8       # was 6 pre-Plan-04; +2 from inlined Pr_i in CAC's h_tc loop and CHF's Pr_i loop (the legacy helper had these 2 references; they now live in thermal_channel.jl after inlining)
# Channel-family total: 9 + 8 = 17 (was 11 + 6 = 17 pre-Plan-04). Net unchanged across the family — references relocated from channel.jl into thermal_channel.jl via inlining.
```

## Phase 53 closure: full test suite

After Task 3, `julia --project=. test/runtests.jl` produces:

| Test category | Result | Note |
| --- | --- | --- |
| PHY-01 (PipeGeometry rectangular + circular) | PASS (16/16) | byte-identical |
| GRAV-01 (vertical loop mtkcompiles + solves) | PASS (3/3) | byte-identical |
| GRAV-02 (gravity cancellation within 1% horizontal) | PASS (1/1) | byte-identical |
| THERM-01 (CAC callable + mtkcompile + n ports) | PASS (13/13) | byte-identical |
| THERM-02 (Channel unmodified regression) | PASS (3/3) | byte-identical (Channel was untouched) |
| THERM-03 (CAC two-sided matches CHF within 0.1%) | PASS (1/1) | byte-identical |
| CHAN-01/02/03 (CAC dual ports + ConstantTemperature + adiabatic right) | PASS (10/10) | byte-identical |
| SIGN-01/04 (Channel reversed flow) | PASS (6/6) | byte-identical |
| SIGN-02/04 (CAC reversed flow) | PASS (6/6) | byte-identical |
| SIGN-03/04 (CHF reversed flow) | PASS (5/5) | byte-identical |
| PHY-05 (Pump fixed-flow) | PASS (4/4) | byte-identical |
| Stage-1 baseline capture (test_channel_core.jl Wave-0 sanity) | PASS (12/12) | unchanged |
| Plan 02 — `_channel_core` exists | PASS (1/1) | unchanged |
| **G1 (Stage-1 constant-cp limit baseline, rtol=1e-6 vs v1.0)** | **PASS (16/16)** | Plan 03 gate, unchanged by Plan 04 |
| **G2 (Stage-2 Python pair_mean_1d parity, rtol=1e-9)** | **PASS (6/6)** | Plan 03 gate, unchanged |
| **G3 (Single-cell forward/reverse mirror, absolute equality)** | **PASS (5/5)** | Plan 03 gate, unchanged |
| **G3b (Multi-cell mirror, spatial T(z) reflection)** | **PASS (7/7)** | Plan 03 gate, unchanged |
| **G4 (Branch-coverage matrix, every if/ifelse path in `_channel_core`)** | **PASS (6/6)** | Plan 03 gate, unchanged |
| NET-03 (Cube flow matches 5/6 R analytical within 1%) | **FAIL** (KINSol retcode Failure) | **pre-existing flake on parent commit `6c9bc95`** — same failure mode in baseline (`/tmp/baseline_full.log` line "ERROR: LoadError: Some tests did not pass: 1 passed, 1 failed"). Documented in `<julia_specific_notes>` of execute prompt: "Pre-existing failures (NET-03 KINSOL flake, VAL-02) remain — your delta is 'no NEW failures vs parent commit `6c9bc95`'." |

The NET-03 KINSol failure halts the orchestrator's `runtests.jl` script (it exits with a non-zero LoadError after the failing testset), so test files later in the include chain (test_misc, test_heat_diffusion, test_correlations, test_subcooled_boiling, test_composition, test_solvers, test_validation, test_examples, test_loss_of_flow, test_analysis, test_point_kinetics) do not run in the full-suite invocation. This was already the case at parent commit `6c9bc95`. Plan 04 introduces zero new failures.

## Decisions Made

- **Comment-rewrite to satisfy the strict `grep -rn '_channel_base_eqs' src/ test/` audit (CORE-02 / ROADMAP #1).** The plan's Task 3 acceptance criterion explicitly says "ZERO hits across src/ and test/". The legacy helper symbol was referenced in 6 narrative comments in `test/test_channel_core.jl` (header docstring, baseline-capture rationale, sanity-check). Two options: (a) keep the comments and accept the strict-audit failure, (b) rewrite the comments with generic terminology. Chose (b) because the audit is a binding closure gate and the comments are documentation-only — no test logic touches the literal string. The narrative is preserved (the comments still explain that G1's baseline came from running the v1.0/legacy variant; just no longer name the helper).
- **Did NOT switch the inlined CAC/CHF blocks to the enthalpy form.** Per Plan 04's CONTEXT lines 26-28 and PATH (CORE-02), the inlined blocks deliberately preserve the OLD constant-cp form `cp_water(T[i]) * (T_up - T[i])`. Phase 54 will migrate them onto `_channel_core` (which has the enthalpy form `cp_face = (cp(T_up) + cp(T[i]))/2`). Migrating in this plan would conflate "remove the legacy helper" with "switch the variants' energy balance" — two changes that should commit separately so failures bisect cleanly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated narrative comments in `test/test_channel_core.jl` to satisfy strict grep audit**
- **Found during:** Task 3 (final grep audits)
- **Issue:** The plan's Task 3 acceptance criterion mandates `grep -rn '_channel_base_eqs' src/ test/` returns ZERO hits, but six narrative comments in `test/test_channel_core.jl` referenced the literal symbol name (G1 docstring, STAGE1 capture rationale, sanity-check, phase-ownership header). Without rewriting these, the closure gate would fail.
- **Fix:** Rewrote the six comments to use generic terminology ("v1.0 legacy helper", "ChannelHeatFlux's legacy path") preserving the original narrative meaning. No test logic, constants, or assertions changed — only documentation comments.
- **Files modified:** `test/test_channel_core.jl`
- **Verification:** `grep -rn '_channel_base_eqs' src/ test/` → no hits.
- **Committed in:** `68ade99` (Task 3 commit, alongside the deletion itself — both changes serve the same closure-gate goal)

**2. [Rule 3 - Blocking] Updated narrative comments in `src/components/thermal_channel.jl` (Task 2 amendment)**
- **Found during:** Task 2 final grep audit before commit
- **Issue:** My initial Task 2 inlined block carried explanatory comments that retained literal references to `_channel_base_eqs`, `observed_mode`, `skip_htc`, `T_wall_cells` (e.g., "Equivalent to the deleted `_channel_base_eqs` helper invoked with observed_mode=true..."). Task 2 acceptance criteria explicitly say `grep -nE '_channel_base_eqs|observed_mode|skip_htc|T_wall_cells' src/components/thermal_channel.jl` must return ZERO hits.
- **Fix:** Rewrote the CAC block-comment and CHF block-comment to use generic terminology (describing what the inlined blocks do without naming the deleted helper or its flag knobs). Same explanatory content, narrative preserved.
- **Files modified:** `src/components/thermal_channel.jl`
- **Verification:** `grep -E '_channel_base_eqs|observed_mode|skip_htc|T_wall_cells' src/components/thermal_channel.jl` → no hits.
- **Committed in:** `5bbc522` (Task 2 commit, alongside the CHF inlining)

---

**Total deviations:** 2 auto-fixed (both Rule 3 — blocking issues that prevented the plan's strict grep-audit closure gates from passing). Both are documentation-comment rewrites; no test or production code logic was changed by the deviations.

**Impact on plan:** Zero. The deviations strengthen the closure gate (the plan's intent was that the deleted symbols be referenced nowhere in the active codebase; my comment rewrites achieve exactly that). No scope creep.

## Issues Encountered

- **Sundials/KINSol non-deterministic segfault during the full-suite run.** During Task 2 verification, two consecutive full-suite runs of `julia --project=. test/runtests.jl` produced segfaults at *different* `test_channel.jl` line numbers (line 54 in run 1, line 410 in run 2), with KINSol-internal C-level stack traces. Running each affected testset (GRAV-01, THERM-03 CHF, etc.) in *isolation* succeeded cleanly. After Task 3, the full-suite run completed without segfaults. This confirms the segfault is a non-deterministic Sundials/KINSol flake on Julia 1.12 + WSL2 unrelated to my code changes — the same failure mode that produces the deterministic "NET-03 KINSol returncode Failure" pre-existing flake under different solver paths. Documented in execute prompt: "Pre-existing failures (NET-03 KINSOL flake, VAL-02) remain". Resolution: surface in the SUMMARY, do not retry/silence; the post-Task-3 clean run is the authoritative result.

## Phase 54 Readiness

- **`_channel_core` is now the sole shared channel-family helper.** No legacy code path. No flag knobs. Phase 54 rewrites Channel, ChannelAndContacts, and ChannelHeatFlux to delegate to `_channel_core` (which already has the enthalpy form, Re/Pe/v/P/T_sat/T_ONB/q_wall/q_wall_left/q_wall_right/T_out/dP observables, and is verified by G1-G4).
- **Inlined CAC/CHF blocks (transitional) provide a clean migration target.** Phase 54 replaces the inlined blocks with `_channel_core(...)` calls. Because the inlined bodies preserve the old constant-cp form, migrating them onto `_channel_core` (enthalpy form) is a SEMANTIC change that Phase 54 must validate against the same G1/G2 baselines that Plan 03 already established for `_channel_core`.
- **No blockers.** Phase 53 closes cleanly. ROADMAP success criteria #1 (deletion) and #2 (no flags) satisfied. The orchestrator can advance to Phase 54.

---
*Phase: 53-shared-channel-core-with-enthalpy-form-energy-balance*
*Plan: 04*
*Completed: 2026-05-06*

## Self-Check: PASSED

- `src/components/channel.jl` modified (verified `git log --oneline 6c9bc95..HEAD` shows 3 commits touching it).
- `src/components/thermal_channel.jl` modified (verified).
- `test/test_channel_core.jl` modified (verified, narrative-only).
- Commit `c9da9c1` exists (Task 1: `git log --oneline | grep c9da9c1` → present).
- Commit `5bbc522` exists (Task 2).
- Commit `68ade99` exists (Task 3).
- `grep -rn '_channel_base_eqs' src/ test/` → no hits.
- `grep -rn 'observed_mode\|skip_htc\|T_wall_cells' src/` → no hits.
- G1/G2/G3/G3b/G4 testsets pass (verified in Task 3 test run).
- CHAN-*/GRAV-*/THERM-*/PHY-*/SIGN-* testsets pass byte-identically (verified).
- NET-03 KINSol failure is pre-existing on parent commit `6c9bc95` (verified via `/tmp/baseline_full.log`).

No missing artifacts. Phase 53 closes.
