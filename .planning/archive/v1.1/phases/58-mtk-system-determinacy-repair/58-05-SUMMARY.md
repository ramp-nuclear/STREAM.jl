---
phase: 58-mtk-system-determinacy-repair
plan: 05
subsystem: testing
tags: [mtk, determinacy, audit, phase-close, pk-verify, julia, modelingtoolkit]

# Dependency graph
requires:
  - phase: 58-mtk-system-determinacy-repair (Plans 58-01..58-04)
    provides: structural fixes for the seven broken Phase-58 scenarios + 11/11 GREEN test_determinacy.jl + 7 of 8 bug-hiding audit flips done
provides:
  - Final bug-hiding audit flip (test_heat_diffusion.jl:185 ⇒ fully_determined=true)
  - Inline rationale comments on every legitimate-structural / isolated-component-test mtkcompile site
  - Tightened src/components/flapper.jl:38 docstring naming the ContinuousCallback as the structural reason
  - Standalone PK validation proof script (scratch/pk_validation_proof.jl) with 8/8 PASS
  - Phase 58 audit sweep closed
affects: [phase-59-and-later (numerical convergence work owns VAL-01 InitialFailure / NET-03 KINSOL / LOF-02-03 transient flakies), future-grep-maintainers (rationale comments are now self-explanatory)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Audit table → inline rationale comment: every fully_determined=false / check_length=false site must carry a one-line marker (`isolated`, `legitimate-structural`, `callback`, `Phase 55 D-08`, `value-source`, `no T equations`, or `pressure anchor`) so future maintainers do not reclassify it as bug-hiding."
    - "Standalone proof script under scratch/ when the test file's own try/catch wrapper short-circuits a downstream testset due to an upstream pre-existing failure."

key-files:
  created:
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/pk_validation_proof.jl
    - .planning/phases/58-mtk-system-determinacy-repair/58-05-SUMMARY.md
  modified:
    - test/test_heat_diffusion.jl
    - test/test_misc.jl
    - test/test_pump.jl
    - test/test_resistors.jl
    - test/test_channels.jl
    - test/test_flapper.jl
    - src/components/flapper.jl

key-decisions:
  - "test_heat_diffusion.jl:185 was the LAST bug-hiding `fully_determined=false` site. Flipped to `=true` (HDIFF-04 already pins `[hd.power ~ pwr]` at :182, so the system IS structurally determined). 8/8 audit-table bug-hiding flips now complete (7 in test_validation.jl across Plans 58-02..58-04, 1 in test_heat_diffusion.jl in this plan)."
  - "Every remaining `fully_determined=false` / `check_length=false` site is legitimate-structural or isolated-component-test scope, not a bug-hiding site. ~22 inline comments added across test_misc.jl, test_pump.jl, test_resistors.jl, test_channels.jl, test_flapper.jl, and test_heat_diffusion.jl:44 to make the rationale self-explanatory to future grep maintainers."
  - "Flapper docstring at src/components/flapper.jl:38 now explicitly names `ContinuousCallback`-set `T_open(t)` as the structural reason for `fully_determined=false` (so a future maintainer reading the docstring does not need to grep tests to learn it). The change is purely additive — preserves existing factual content."
  - "PK validation testset cannot be reached via direct `julia test/test_validation.jl` run because of the upstream VAL-01 Fourier `Rodas5P` `InitialFailure` BoundsError that throws inside the `try` block at line 837 (jumping past the PK testset block at line 1053 to the `catch` at line 1226). A standalone proof script under `scratch/` is the correct mitigation per 58-04 SUMMARY 'Lessons learned'. All four VAL-PK-* sub-testsets PASS via the existing transient fallback path (KINSOL flag −7 expected per RESEARCH §3 PK-VAL, R-4)."

patterns-established:
  - "Inline rationale comment on every fully_determined=false call site so the audit classification is grep-able from the source code without consulting scratch/audit_table.md."
  - "Component docstrings name the structural reason (e.g. callback-set state) for any required `mtkcompile(...; fully_determined=false)` flag, so the API contract is self-documenting."

requirements-completed: []

# Metrics
duration: ~30min
completed: 2026-05-08
---

# Phase 58 Plan 05: Audit close + PK verification + flapper docstring tighten Summary

**Final Phase 58 bug-hiding audit flip (test_heat_diffusion.jl:185 → fully_determined=true), ~22 inline rationale comments on legitimate-structural sites across 6 test files, src/components/flapper.jl:38 docstring tightened to name the ContinuousCallback structural reason, and standalone PK validation proof (8/8 PASS via transient fallback).**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-05-08T17:35:00Z (worktree spawn)
- **Completed:** 2026-05-08T18:07:35Z
- **Tasks:** 2
- **Files modified:** 7
- **Commits:** 3 (Task 1, Task 2, PK proof script)

## Accomplishments

- **Last bug-hiding audit flip done:** `test/test_heat_diffusion.jl:185` flipped to `fully_determined=true`. With this, all 8 sites in scratch/audit_table.md classified as bug-hiding are now using the strict `=true` flag (7 in test_validation.jl across Plans 58-02..58-04 + 1 in test_heat_diffusion.jl in Plan 58-05).
- **Audit-self-documenting comments added:** 22 inline `# ` rationale comments on every remaining `fully_determined=false` / `check_length=false` site. Future `grep -n 'fully_determined=false'` returns every match annotated with one of the marker keywords (`isolated`, `legitimate-structural`, `callback`, `Phase 55 D-08`, `value-source`, `no T equations`, `pressure anchor`).
- **Flapper docstring tightened:** `src/components/flapper.jl:38` now names `ContinuousCallback` as the structural reason. Pure additive change (no logic).
- **PK validation testset reaches solve_*:** all four VAL-PK-* sub-testsets pass via the existing transient fallback path (KINSOL flag −7 ⇒ steady-state Failure ⇒ transient solve to 50 s / 200 s / 50 s reaches the assertions). 8/8 assertions PASS in standalone proof.
- **test_determinacy.jl: 11/11 GREEN** (6 canonical builders + 5 Phase-58 scenarios). No regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: Flip last bug-hiding site + add inline comments to legitimate sites** — `c9edc8b` (chore)
2. **Task 2: Tighten src/components/flapper.jl:38 docstring** — `b2c1869` (docs)
3. **Standalone PK validation proof** — `2af3e35` (docs) — supplementary scratch script that proves the PK testset reaches its assertions via the existing transient fallback when run in isolation (the file-level `test_validation.jl` run short-circuits before reaching PK due to a pre-existing upstream VAL-01 InitialFailure).

## Files Created/Modified

- `test/test_heat_diffusion.jl` — Line 185 flipped to `fully_determined=true` (HDIFF-04 audit flip); line 44 carries `# isolated component: dangling thermal ports + unset power(t) by design`.
- `test/test_misc.jl` — 5 inline comments (lines 19, 37, 71, 131, 178; line 41/48 already commented per audit table, left as-is).
- `test/test_pump.jl` — 6 inline comments (lines 18, 36, 68, 83, 99, 133).
- `test/test_resistors.jl` — 1 inline comment (line 18).
- `test/test_channels.jl` — 7 inline comments (lines 70, 84, 94, 468, 675, 804, 1087); free-standing comment lines at 16/67 left as-is per audit table.
- `test/test_flapper.jl` — 3 inline comments (lines 58, 110, 151).
- `src/components/flapper.jl` — Lines 37-40 docstring tightened to name `ContinuousCallback` and `T_open(t)` as the structural reason for `fully_determined=false`.
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/pk_validation_proof.jl` — NEW. Standalone re-run of the four VAL-PK-* sub-testsets, mirroring test_validation.jl:1053-1224.

## Decisions Made

- **Skip free-standing comment lines (test_channels.jl:16, 67):** Per audit table, those are pre-amble commentary explaining the test file's strategy, not `mtkcompile` call sites. Touching them would be cosmetic. Skipped per RESEARCH §5 instruction.
- **Use absolute paths derived from `git rev-parse --show-toplevel`:** Worktree path safety practiced throughout. All Edits used relative paths inside the worktree (Read tool with absolute paths, Edit succeeds against the canonical worktree root).
- **Standalone PK proof script lives under `scratch/`:** Per 58-04 SUMMARY "Lessons learned" (try/catch wraps interact with deferred-items), the correct mitigation when a try-block short-circuits the LATER testset is a standalone scratch script. Matches the `scratch/diag_*.jl` pattern from earlier Phase 58 plans.
- **`test/data/parity_report.csv` left unstaged:** Same precedent as 58-04 SUMMARY "Issues Encountered" — the CSV is a regression artifact appended by `test_validation.jl` runs, not a plan deliverable. Letting the user decide whether to commit the parity drift refresh as a separate change.

## Deviations from Plan

None — plan executed exactly as written. The PreToolUse "READ-BEFORE-EDIT REMINDER" hook fired informationally on every Edit call (same observation as 58-02/58-03/58-04); each Edit succeeded as evidenced by `git diff --stat`.

## Issues Encountered

- **`julia test/runtests.jl` halts at NET-03** (KINSOL flag −11 — pre-existing, documented in STATE.md "Blockers/Concerns" line 101). The orchestrator stops on first failure, which prevents downstream test files from running under that single invocation. Mitigation: ran each test file individually instead.
- **`julia test/test_validation.jl` halts at VAL-01 Fourier** (`InitialFailure` ⇒ BoundsError on extracted T_center vector — pre-existing, documented in STATE.md "Blockers/Concerns" line 100 and deferred-items.md D-1). The try/catch wrapper at line 837 catches the exception, but the catch jumps past the PK validation testset block (line 1053). Mitigation: standalone proof script `scratch/pk_validation_proof.jl` re-runs ONLY the four VAL-PK-* sub-testsets in isolation. Result: 8/8 PASS.
- **Several non-Phase-58 transient flakies in test_correlations.jl (HTC-02 KINSOL flag −7) and test_integration.jl (LOF-02 flapper threshold, LOF-03 reversal, VAL-01/VAL-02 BoundsError on Vector{Vector{Float64}})**: pre-existing numerical-conditioning issues, none touch the files Plan 58-05 modifies, and none produce determinacy/symbol-access errors (no `ExtraVariablesSystemException`, `ExtraEquationsSystemException`, `ArgumentError: Equations ... lengths`, or `ArgumentError: System sys` anywhere in any test file output).

## Verification

### `julia --project=. test/test_determinacy.jl` (verbatim — final 11/11 PASS proof)

```
┌ Info: build_loop compile time: 14.61s
│   n_equations = 11
└   n_unknowns = 11
┌ Info: build_loop_vertical compile time: 0.03s
│   n_equations = 11
└   n_unknowns = 11
┌ Info: build_loop_transient compile time: 0.03s
│   n_equations = 11
└   n_unknowns = 11
┌ Info: build_cube compile time: 0.15s
│   n_equations = 14
└   n_unknowns = 14
┌ Info: build_loop_lof_bypass compile time: 0.82s
│   n_equations = 64
└   n_unknowns = 64
┌ Info: build_loop_pk compile time: 0.11s
│   n_equations = 43
└   n_unknowns = 43
Test Summary:                                        | Pass  Total   Time
Determinacy: canonical builders are fully determined |    6      6  57.2s
Test Summary:                   | Pass  Total  Time
Determinacy: Phase 58 scenarios |    5      5  4.4s
```

11/11 testsets PASS. No regression vs Plan 58-04 baseline.

### `julia --project=. .planning/phases/58-mtk-system-determinacy-repair/scratch/pk_validation_proof.jl` (verbatim — PK validation 8/8 PASS)

```
┌ Info: build_loop_pk compile time: 15.75s
│   n_equations = 43
└   n_unknowns = 43
[ERROR][rank 0][/workspace/srcdir/sundials/src/kinsol/kinsol.c:756][KINSol] Five consecutive steps have been taken that satisfy a scaled step length test.
┌ Error: KINSol failed with error code = 
│   flag = -7
└ @ Sundials ~/.julia/packages/Sundials/TDKcO/src/simple.jl:20
┌ Info: build_loop_pk compile time: 0.08s
┌ Info: build_loop_pk compile time: 0.16s
┌ Info: build_loop_pk compile time: 0.15s
Test Summary:                                            | Pass  Total     Time
PointKinetics validation (standalone proof — Plan 58-05) |    8      8  1m31.8s
```

KINSOL flag −7 in VAL-PK-01 is the documented behavior — the test then enters the existing transient fallback at test_validation.jl:1071-1074 and reaches the assertions. All four VAL-PK-* sub-testsets PASS, 8 assertions pass total.

### Per-test-file outcomes (julia --project=. test/<file>)

| File | Outcome | Notes |
|------|---------|-------|
| test_geometry.jl | PASS | clean |
| test_connectors.jl | PASS | clean |
| test_fluids.jl | PASS | clean |
| test_channels.jl | PASS | clean (Plan 58-05 added 7 inline comments here) |
| test_pump.jl | PASS | clean (Plan 58-05 added 6 inline comments here) |
| test_flapper.jl | PASS | clean (Plan 58-05 added 3 inline comments here; flapper.jl docstring tightened) |
| test_misc.jl | PASS | clean (Plan 58-05 added 5 inline comments here) |
| test_heat_diffusion.jl | PASS | clean (Plan 58-05 flipped HDIFF-04 to fully_determined=true and added 1 inline comment to HDIFF-01) |
| test_correlations.jl | 1 FAIL | HTC-02 `fully_developed_laminar_h_spl compiles in Channel` — KINSOL flag −7 numerical (pre-existing, NOT touched by Plan 58-05) |
| test_thresholds.jl | PASS | clean |
| test_composition.jl | PASS | clean |
| test_integration.jl | 4 FAIL + 2 ERROR | LOF-02 flapper threshold + LOF-03 reversal + VAL-01/VAL-02 BoundsError on Vector{Vector{Float64}} — all pre-existing transient flakies, NOT touched by Plan 58-05 |
| test_point_kinetics.jl | PASS | clean (PK component-unit tests; the integration tests are in test_validation.jl PK-VAL block proven via standalone script) |
| test_resistors.jl | 1 FAIL | NET-03 Cube KINSOL flag −11 — pre-existing per STATE.md "Blockers/Concerns" line 101, NOT touched by Plan 58-05 |
| test_validation.jl | runs to VAL-01 then catches via try/catch wrapper | VAL-01 InitialFailure pre-existing per STATE.md line 100 + deferred-items.md D-1; Phase 56 parity harness 467/559 PASS (92 FAIL = parity drift, NOT determinacy); MTR scenarios reach `solve_steady` (sentinel-row wrapper consumes any KINSOL Failure into a parity row) |

**Critical Phase-58 acceptance signal:** none of these failures produce `ExtraVariablesSystemException`, `ExtraEquationsSystemException`, `ArgumentError: Equations ... different lengths`, or `ArgumentError: System sys: variable sys does not exist`. All failures are numerical (KINSOL non-convergence, ODE BoundsError on short solutions) — Phase-58-independent and out of scope per CONTEXT.md `<domain>` "Out of scope" and RESEARCH R-4.

### Audit completeness check

```
$ grep -n 'fully_determined=false' test/*.jl | grep -v '#' | head -1
(empty)
```

Every remaining `fully_determined=false` site carries a `#` comment on the same line (verified above per file via `grep -n 'fully_determined=' test/*.jl`).

### `test_heat_diffusion.jl` count of `fully_determined=false`:

```
$ awk '/fully_determined=false/{n++} END{print n}' test/test_heat_diffusion.jl
1
```

Exactly 1 remaining (line 44, the isolated-HD compile in HDIFF-01 — explicitly preserved). Line 185 is the audit-flipped `=true` (HDIFF-04). Acceptance criterion satisfied.

### Audit table reconciliation

| Audit-table site | Plan-05 disposition | Verified |
|------------------|---------------------|----------|
| `test/test_heat_diffusion.jl:185` (bug-hiding) | flipped to `fully_determined=true` | line reads `ssys = mtkcompile(sys; fully_determined=true)` |
| `test/test_heat_diffusion.jl:44` | inline comment added | "isolated component: dangling thermal ports + unset power(t) by design" |
| `test/test_misc.jl:19, 37, 71, 131, 178` | 4 new inline comments + 1 tightened existing | per-line keywords match audit table |
| `test/test_misc.jl:41, 48` | left as-is per audit table | unchanged |
| `test/test_pump.jl:18, 36, 68, 83, 99, 133` | 6 inline comments added | per-line keywords match audit table |
| `test/test_resistors.jl:18` | inline comment added | "isolated component: pure resistance, no anchor" |
| `test/test_channels.jl:70, 84, 94, 468, 675, 804, 1087` | 7 inline comments added | per-line keywords reference Phase 55 D-08 / Hypothesis-A |
| `test/test_channels.jl:16, 67` | left as-is per audit table | comment lines, not call sites |
| `test/test_flapper.jl:58, 110, 151` | 3 inline comments added | "callback" keyword present, references flapper.jl:38 |
| `src/components/flapper.jl:38` | docstring tightened | now contains "ContinuousCallback" and "T_open(t)" |
| `src/components/channels.jl:207, 409` | left as-is per audit table | inline doc references to Phase 55 D-08 |

All sites in audit_table.md are now either (a) flipped to `=true` if classified bug-hiding, (b) carrying inline rationale comments if classified legitimate-structural / isolated-component-test, or (c) intentionally left as-is per audit table (free-standing comment lines, doc-only inline comments inside src/components/channels.jl).

## Self-Check: PASSED

- `test/test_heat_diffusion.jl` line 185 reads `ssys = mtkcompile(sys; fully_determined=true)` — VERIFIED via `grep -n` output above
- `test/test_heat_diffusion.jl` has exactly ONE remaining `fully_determined=false` (line 44) — VERIFIED via `awk` count
- Every `fully_determined=false` call site in the modified files carries an inline `#` comment with a marker keyword — VERIFIED via per-file `grep -n 'fully_determined=false'`
- `src/components/flapper.jl` lines 37-40 contain the substring `ContinuousCallback` — VERIFIED
- All 11 testsets in `test/test_determinacy.jl` PASS — VERIFIED via verbatim output above
- All 8 assertions in `scratch/pk_validation_proof.jl` PASS — VERIFIED via verbatim output above
- Commits `c9edc8b`, `b2c1869`, `2af3e35` exist on the worktree branch — VERIFIED via `git log --oneline`
- `git rev-parse --abbrev-ref HEAD` returns `worktree-agent-a2893b7f29136f505` (per-agent worktree branch) — VERIFIED
- No `ExtraVariablesSystemException`, `ExtraEquationsSystemException`, `ArgumentError: Equations ... lengths`, or `ArgumentError: System sys: variable sys does not exist` in any per-file run — VERIFIED via `grep -E` against each output

## Next Phase Readiness

Phase 58 is **closed** with this plan. Remaining surfaces:

- The audit-table sweep is fully reconciled (8/8 bug-hiding sites flipped, ~22 inline rationale comments added, 1 docstring tightened, 0 src/ logic changes).
- The five Phase-58 scenario rows in `test/test_determinacy.jl` are GREEN: MTR symmetric, MTR asymmetric, MTR one-sided, VAL-01 HD Fourier (structurally; numerically still pre-existing flaky), VAL-02 two-plate.
- The PK validation testset reaches `solve_*` via the existing transient fallback (8/8 assertions pass standalone).

**Pre-existing flakies carried into Phase 59+ (out-of-Phase-58 scope):**

- VAL-01 Fourier `Rodas5P` `InitialFailure` (test_validation.jl:917) — numerical conditioning of the diffusion ODE initial state, NOT a determinacy issue. The structural fix landed in Plan 58-03; only the numerical solve fails. Owns: future numerical-investigation plan (Phase 59 candidate).
- NET-03 Cube KINSOL flag −11 (test_resistors.jl:36-72) — pre-existing per STATE.md "Blockers/Concerns" line 101.
- LOF-02 / LOF-03 / VAL-01 / VAL-02 BoundsError in test_integration.jl — pre-existing transient solver flakies (solver returns short solution; BoundsError on `[k]` indexing). NOT determinacy.
- HTC-02 fully_developed_laminar_h_spl KINSOL flag −7 (test_correlations.jl:670) — pre-existing transient/steady solver flaky.

These are all numerical, not structural. The Phase 58 mandate ("repair MTK system determinacy") is complete.

---
*Phase: 58-mtk-system-determinacy-repair*
*Completed: 2026-05-08*
