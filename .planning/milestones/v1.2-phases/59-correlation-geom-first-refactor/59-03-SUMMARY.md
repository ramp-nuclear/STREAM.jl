---
phase: 59-correlation-geom-first-refactor
plan: 03
subsystem: correlations
tags: [julia, mtk, modelingtoolkit, examples, integration-tests, geom-first, refactor, call-site-sweep]

# Dependency graph
requires:
  - plan: 59-01
    provides: laminar_friction(geom::PipeGeometry) sole signature + HTCCorrelation alias
  - plan: 59-02
    provides: elenbaas_htc(geom; g) / fully_developed_laminar_h_spl(geom) / developing_laminar_h_spl(geom; develop_length) / regime_dependent(geom; ...) sole signatures
provides:
  - src/examples.jl build_loop_lof_bypass + build_loop_pk call sites converted to geom-first factories
  - test/test_composition.jl _mtr_pair fixture converted to laminar_friction(geom)
  - test/test_integration.jl TF-06 + TF-07 testsets converted to laminar_friction(geom_tf / geom_tf7)
  - Repo-wide audit: zero remaining scalar/kwarg-form refactored-factory call sites in src/ and test/
affects:
  - 59-04 (handoff doc — all factories + call sites now stable, API table can be finalized)
  - 61 (GUI registry rewrite — clean geom-first surface to consume)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Numerical-identity preservation in call-site sweep: every scalar/kwarg replaced with a geom binding constructed from the same underlying PipeGeometry that produced the original scalar; e.g. laminar_friction(0.0025/0.070) → laminar_friction(geom_tf) where geom_tf = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070) so geom.depth/geom.width == 0.0025/0.070 exactly"
    - "Collapsed-group sweep: where the old regime_dependent group required (htc_natural, Dh, g), the new call sites pass only (htc_natural, g) with Dh derived from the leading geom argument"

key-files:
  created: []
  modified:
    - src/examples.jl
    - test/test_composition.jl
    - test/test_integration.jl

key-decisions:
  - "Source-level acceptance criteria are the gate for this worktree — Julia binary is not on PATH in the worktree environment (same as Plans 01 and 02). All grep-based source assertions and negations pass. The runtime green-test gate (bin/jl test/test_correlations.jl, test_composition.jl, test_channels.jl, test_integration.jl, test_validation.jl) MUST be run by the orchestrator/user from the main checkout after merge — that is the load-bearing semantic-drift gate per CONTEXT.md and the orchestrator's prompt."
  - "examples.jl build_loop_lof_bypass: the standalone Dh=D_ch kwarg on regime_dependent is deleted entirely (collapsed NC group per Plan 02 D-01); g=g_acc retained."
  - "examples.jl build_loop_pk: laminar_friction(geom) uses the geom already constructed at line 575 (PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)); no new geom binding introduced."
  - "test_integration.jl: two surgical edits only — TF-06 line 770 and TF-07 line 854. LOF transient, ISCB, PK loops, COMPAT testsets explicitly untouched per the plan."

patterns-established:
  - "Wave-3 call-site sweep pattern: after a clean-break factory refactor lands in earlier waves, the integration plan greps repo-wide for any remaining old-form calls, replaces each with the geom-first form using the in-scope geom binding (or introduces one if absent), and asserts source-wide that no old-form call sites remain. Acceptance grep is run repo-wide, not per-file, to catch unenumerated sites."

requirements-completed: []

# Metrics
duration: ~15min
completed: 2026-05-11
---

# Phase 59 Plan 03: Correlation `geom`-first refactor (call-site sweep + test gate) Summary

**Final call-site sweep — `src/examples.jl` (4 sites), `test/test_composition.jl` (1 site), `test/test_integration.jl` (2 sites: TF-06, TF-07) — converted to geom-first factory calls. Repo-wide audit confirms zero remaining scalar/kwarg-form calls. Runtime green-test gate deferred to orchestrator post-merge because Julia is not on PATH in the worktree.**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-05-11
- **Tasks:** 3 / 3 (Tasks 1, 2, 2b complete at source level; Task 3 runtime gate deferred — see Issues Encountered)
- **Files modified:** 3

## Accomplishments

- `src/examples.jl` build_loop_lof_bypass: `regime_dependent(geom; ...)` first-positional form; `friction_laminar=laminar_friction(geom)`; `htc_natural=elenbaas_htc(geom; g=g_acc)`; standalone `Dh=D_ch` kwarg deleted (collapsed NC group from Plan 02); `g=g_acc` retained.
- `src/examples.jl` build_loop_pk: `friction_correlation=laminar_friction(geom)` replaces scalar `0.0025 / 0.070` form. The local `geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)` already at line 575 is reused; `geom.depth/geom.width == 0.0025/0.070` exactly so the produced closure is numerically identical.
- `test/test_composition.jl` _mtr_pair fixture: `friction_correlation=laminar_friction(geom)`; geom already constructed at line 16 (`PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)`); numerical identity preserved.
- `test/test_integration.jl` TF-06 (line 770): `laminar_friction(geom_tf)`; TF-07 (line 854): `laminar_friction(geom_tf7)`. Both geom bindings constructed two lines above each call site as `PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)`; numerical identity preserved.
- Repo-wide audit: a `grep -rnE "(laminar_friction|elenbaas_htc|fully_developed_laminar_h_spl|developing_laminar_h_spl|regime_dependent)\(" src/ test/` followed by inverse-grep for any line lacking the `geom` argument returns ZERO matches across the entire codebase. All call sites are on the geom-first surface. (Helpers `_geom_for_ar(ar)` and `_geom_for(Dh, ar)` introduced by Plan 02 inside test_correlations.jl HTC-02 / HTC-03 testsets are valid — they take a leading underscore in the call but still pass a constructed geom into the factory.)

## Task Commits

1. **Task 1: Update src/examples.jl call sites to geom-first factories** — `36865ce` (refactor)
2. **Task 2: Update test/test_composition.jl laminar_friction call site** — `649569f` (test)
3. **Task 2b: Update test/test_integration.jl TF-06 and TF-07 to laminar_friction(geom)** — `cc90404` (test)

(Task 3 — runtime green-test gate — has NO commit because no source edit is associated with it. It is documented under Issues Encountered as a worktree-environment deferral, not a phase regression.)

## Files Created/Modified

- `src/examples.jl` — four call sites converted (build_loop_lof_bypass lines 438/441/443; build_loop_pk line 580). `regime_dependent(geom; ...)` first-positional; standalone `Dh=D_ch` kwarg removed; `elenbaas_htc(geom; g=g_acc)` replaces `elenbaas_htc(; b=D_ch, L=L_ch, Dh=D_ch, g=g_acc)`; `laminar_friction(geom)` replaces both `laminar_friction(1.0)` (inside regime_dependent kwargs) and `laminar_friction(0.0025 / 0.070)` (inside build_loop_pk ChannelAndContacts).
- `test/test_composition.jl` — single call site (line 20) inside `_mtr_pair`: `laminar_friction(geom)` replaces `laminar_friction(0.0025 / 0.070)`.
- `test/test_integration.jl` — two call sites (lines 770 / 854) inside TF-06 / TF-07 testsets: `laminar_friction(geom_tf)` / `laminar_friction(geom_tf7)` replace the scalar `laminar_friction(0.0025/0.070)` form. LOF transient, ISCB, PK loops, COMPAT testsets untouched.

## Decisions Made

- **Source-level acceptance only, runtime gate deferred to orchestrator post-merge.** Julia is not on PATH in the worktree (no `julia` binary, no `bin/jl*` scripts, no daemon for this worktree path). Plans 01 and 02 surfaced the same constraint and the orchestrator accepted source-level grep checks. Per the orchestrator's prompt: "If Julia is unavailable in the worktree, HALT and report so the orchestrator can run tests in main after merge — do NOT fabricate test results." Test results are NOT fabricated; the runtime gate is explicitly deferred. See Issues Encountered for what was verified locally and what must be run from main.
- **Numerical-identity preservation across all six edits.** Each scalar replaced by a `geom` binding whose `depth/width` equals the original scalar. For the integration testsets: `geom_tf` and `geom_tf7` are both `PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)` so `depth/width == 0.0025/0.070`. For the composition fixture: same. For the examples.jl build_loop_pk: same again. For build_loop_lof_bypass: `geom = PipeGeometry_circular(L_ch, D_ch)` was previously paired with `laminar_friction(1.0)` (the workaround scalar for circular geometry where `aspect_ratio=1` was a deliberate physical placeholder per the pre-refactor comment); after the refactor, `laminar_friction(geom)` derives `aspect_ratio = geom.depth/geom.width = 1.0` (circular geom has `depth == width == Dh`), so the closure produced is bit-for-bit identical to the old `laminar_friction(1.0)`.
- **Parity baseline snapshot (Step 0 of Task 3) not captured.** The plan's Step 0 instructs the executor to run `bin/jl test/test_validation.jl` before any source edit lands and `cp test/data/parity_report.csv /tmp/parity_baseline_59.csv`. Without a Julia binary, this is not executable in the worktree. The orchestrator must capture the baseline from the main checkout BEFORE running the post-merge test gate, then run the deterministic diff `diff <(awk -F, '$NF=="FAIL"' /tmp/parity_baseline_59.csv | sort) <(awk -F, '$NF=="FAIL"' test/data/parity_report.csv | sort)`. The pre-refactor MTR L/R FAIL set (per STATE.md last activity 2026-05-09: 424 CLEAN / 78 GRAY / 34 FAIL) is the acceptance baseline.

## Deviations from Plan

None functional. All three source-edit tasks executed per the plan's instructions; the worktree environment limitation (no Julia) is the same accepted reality Plans 01 and 02 documented and the orchestrator accepted.

## Issues Encountered

**1. Worktree environment cannot run `bin/jl` (Julia) — runtime test gate deferred to orchestrator post-merge**

- **Found during:** Task 1 verification (the plan's `<verify><automated>bin/jl -e 'using STREAM; ...'</automated></verify>` block) and Task 3 (the whole task is runtime gating).
- **Issue:** No `julia` binary on PATH in the worktree (`/home/itay/projects/STREAM.jl/.claude/worktrees/agent-af839987262331f98`); no `bin/jl-up` or `bin/jl` scripts checked in at HEAD (CLAUDE.md references them but they are not in the tree at base commit `e52cb5e`); no Julia daemon reachable on port 3000 from this worktree path. The Julia daemon described in CLAUDE.md lives in tmux session `stream-jl` watching the MAIN checkout — Revise on that daemon is watching the wrong file paths for this worktree, and submitting to it would test main, not these source edits. The orchestrator's prompt acknowledged this exact constraint: "in this worktree, Julia is NOT in the daemon's watched directory ... If Julia is not on PATH at all in this worktree environment, halt and report — DO NOT skip the green-test gate. This plan's whole point is the test gate."
- **Impact:** Task 1 verify (build_loop_lof_bypass + build_loop_pk compile-and-return-non-nothing); Task 2 verify (`bin/jl test/test_composition.jl`); Task 2b verify (`bin/jl test/test_integration.jl`); ALL FIVE files in Task 3 (`test_correlations.jl`, `test_composition.jl`, `test_channels.jl`, `test_integration.jl`, `test_validation.jl`); and Task 3 Step 0 parity baseline capture — all cannot be executed inside the worktree. Source-level acceptance criteria (the grep checks in each task) all pass.
- **Resolution:** Halt-and-report — surfaced here for the orchestrator. After merge back to `gui-redesign`, the orchestrator/user runs:

  ```
  # From the main checkout (where the daemon and julia install live)
  bin/jl-up                                          # start daemon if not running
  bin/jl test/test_correlations.jl                   # unit + integration for refactored factories
  bin/jl test/test_composition.jl                    # composition helpers + _mtr_pair
  bin/jl test/test_channels.jl                       # indirect call sites through examples.jl builders
  bin/jl test/test_integration.jl                    # TF-06 + TF-07 + LOF + ISCB + PK + COMPAT
  bin/jl test/test_validation.jl                     # Python parity — LOAD-BEARING semantic-drift gate
  diff <(awk -F, '$NF=="FAIL"' /tmp/parity_baseline_59.csv | sort) \
       <(awk -F, '$NF=="FAIL"' test/data/parity_report.csv | sort)
  # Expected: empty diff → no NEW FAIL rows vs pre-refactor MTR L/R baseline.
  ```

  Step 0 baseline (`/tmp/parity_baseline_59.csv`) must be captured BEFORE the merge lands in main, by running `bin/jl test/test_validation.jl` on `e52cb5e` (the worktree base commit — which IS the merged state of Plans 01 and 02 plus zero of Plan 03) and copying `test/data/parity_report.csv` aside. If that baseline was not captured before the merge, the deterministic diff against pre-refactor must instead key on STATE.md's recorded `424 CLEAN / 78 GRAY / 34 FAIL` totals from last_activity 2026-05-09.
- **What was verified locally (source-level, no Julia needed):**

  **Task 1 (`src/examples.jl`):**
  - `grep -E "regime_dependent\(geom;" src/examples.jl` → 1 match (line 438) ✓
  - `grep -E "elenbaas_htc\(geom" src/examples.jl` → 1 match (line 443) ✓
  - `grep -cE "laminar_friction\(geom\)" src/examples.jl` → 2 (lines 441, 580) ✓
  - `grep -nE "laminar_friction\(1\.0\)|laminar_friction\(0\.0025" src/examples.jl` → 0 matches ✓
  - `grep -nE "elenbaas_htc\(;\s*b=|elenbaas_htc\(b=" src/examples.jl` → 0 matches ✓
  - `grep -nE "Dh=D_ch," src/examples.jl | grep -v '^#'` → 0 matches ✓
  - `grep -nE "regime_dependent\(;" src/examples.jl` → 0 matches ✓

  **Task 2 (`test/test_composition.jl`):**
  - `grep -nE "laminar_friction\(0\.0025" test/test_composition.jl` → 0 matches ✓
  - `grep -cE "laminar_friction\(geom" test/test_composition.jl` → 1 ✓
  - No other refactored-factory calls (elenbaas_htc, fully_developed_laminar_h_spl, developing_laminar_h_spl, regime_dependent) present in the file ✓

  **Task 2b (`test/test_integration.jl`):**
  - `grep -nE "laminar_friction\(0\.0025/0\.070\)" test/test_integration.jl` → 0 matches ✓
  - `grep -cE "laminar_friction\(geom" test/test_integration.jl` → 2 ✓
  - `grep -nE "friction_correlation=laminar_friction\(geom_tf\)" test/test_integration.jl` → exactly 1 (line 770, TF-06) ✓
  - `grep -nE "friction_correlation=laminar_friction\(geom_tf7\)" test/test_integration.jl` → exactly 1 (line 854, TF-07) ✓

  **Repo-wide closure assertion (the phase's strongest source-level guarantee):**
  - `grep -rnE "(laminar_friction|elenbaas_htc|fully_developed_laminar_h_spl|developing_laminar_h_spl|regime_dependent)\(" src/ test/` cross-checked against an inverse-grep filtering for any line that does NOT include `geom` as the leading argument: ZERO matches. Every refactored-factory call site in the entire `src/` + `test/` tree is on the geom-first surface ✓

## User Setup Required

None — pure library refactor, no external services touched.

## Next Phase Readiness

- **Plan 04** (Phase 61 handoff doc per D-05) is unblocked at source level. The API table can be finalized — every factory's final signature is set and every internal call site is on the new surface.
- **Runtime green-test gate is the only outstanding item.** It must be executed by the orchestrator/user from the main checkout post-merge per the command list above. Until that runs, Phase 59 is not functionally proven — but it is structurally proven (no remaining old-form call sites; numerical identity preserved at every replacement).
- **Phase 61 (GUI registry rewrite)** can consume the new geom-first API as documented in Plan 04 once that ships. No blockers introduced.
- **STATE.md / ROADMAP.md** intentionally not modified per worktree-mode instructions; the orchestrator owns those writes after the worktree merges back.

## Self-Check: PASSED

Created files exist:
- `.planning/phases/59-correlation-geom-first-refactor/59-03-SUMMARY.md` — this file (about to be committed).

Commits exist on `worktree-agent-af839987262331f98` (verified via `git log --oneline e52cb5e..HEAD`):
- `36865ce` — `refactor(59-03): src/examples.jl call sites to geom-first factories`
- `649569f` — `test(59-03): test_composition.jl _mtr_pair uses laminar_friction(geom)`
- `cc90404` — `test(59-03): test_integration.jl TF-06 + TF-07 use laminar_friction(geom)`

No modifications to `.planning/STATE.md` / `.planning/ROADMAP.md` (per worktree-mode instructions; orchestrator owns those after merge).

---
*Phase: 59-correlation-geom-first-refactor*
*Completed: 2026-05-11*
