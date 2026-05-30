---
phase: 58-mtk-system-determinacy-repair
plan: 04
subsystem: mtk
status: complete
tags: [mtk, determinacy, val-02, two-plate, transient, symbol-access, fix]
dependency_graph:
  requires:
    - .planning/phases/58-mtk-system-determinacy-repair/58-01-SUMMARY.md
    - .planning/phases/58-mtk-system-determinacy-repair/58-02-SUMMARY.md
    - .planning/phases/58-mtk-system-determinacy-repair/58-03-SUMMARY.md
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md
  provides:
    - "VAL-02 two-plate steady reaches mtkcompile(...; fully_determined=true) success (Δ=0, n_eqs=91, n_unk=91)"
    - "VAL-02 two-plate steady solve_steady returns Success with energy balance T_rise within 5% rtol"
    - "VAL-02 transient T_wall step testset reaches solve_transient Success (no `variable sys does not exist` ArgumentError)"
    - "Fifth and final Phase-58 determinacy regression row GREEN (VAL-02 twoplate)"
    - "All five Phase-58 scenario rows in test/test_determinacy.jl are GREEN (5 PASS / 0 ERROR)"
    - "test_validation.jl is bug-hiding-flag-free: every mtkcompile call uses fully_determined=true"
  affects:
    - test/test_validation.jl
    - test/test_determinacy.jl
tech_stack:
  added: []
  patterns:
    - "Multi-instance closing-equation pattern: each HeatDiffusion instance contributes one `hd_k.power ~ value` pin (Δ scales with HD count)"
    - "MTK named-property access for callable parameters: `ssys.<name>` resolves; `ssys.sys.<name>` raises after compile"
key_files:
  created:
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate_solve.jl
  modified:
    - test/test_validation.jl
    - test/test_determinacy.jl
key_decisions:
  - "Pin both HD instances at the constructor value `power_per_plate` — same shape as MTR/VAL-01 fixes, scaled to two pins for the Δ=−2 deficit (per scratch/diag_table.md Scenario E live verification)"
  - "Use direct named access `ssys.T_wall_callable` rather than `last(parameters(ssys))` — preserves the existing inline comment's stable-named-access rationale"
  - "Flip simple_loop audit at :204 to `fully_determined=true` — last bug-hiding flag in test_validation.jl per RESEARCH §5 audit"
  - "Add scratch/diag_val02_twoplate_solve.jl to capture standalone solve_steady proof — VAL-01 Fourier's pre-existing BoundsError (documented out-of-scope in 58-03 §Deviations 1) exits the wrapping try block before VAL-02 two-plate runs in test_validation.jl"
patterns_established:
  - "When N HeatDiffusion instances appear in a topology, supply N `hd_k.power ~ value` pins as the closing equations; N-pin pattern generalizes the single-pin fix from 58-02/58-03"
  - "Symbol access on a compiled MTK system: `ssys.<name>` for named properties (parameters, observed, unknowns); never `ssys.sys.<name>` post-compile"
metrics:
  duration: "~12 min total (cold-start verification dominates)"
  completed: 2026-05-08
  tasks_completed: 3
  files_changed: 3
scenarios_addressed:
  - VAL-02-TWOPLATE
  - VAL-02-TRANSIENT
  - DETERMINACY-PHASE58 (row 5 of 5)
requirements_completed: []
---

# Phase 58 Plan 04: VAL-02 Two-Plate + Transient Determinacy Fix Summary

**Closes the last Phase-58 scenario: VAL-02 two-plate steady (two HD instances → two `hd_k.power ~ power_per_plate` pins, Δ=−2 → Δ=0) and VAL-02 transient symbol-access (`ssys.sys.T_wall_callable` → `ssys.T_wall_callable`); all five Phase-58 determinacy rows GREEN; `test_validation.jl` bug-hiding-flag-free (zero `fully_determined=false` matches).**

## Performance

- **Duration:** ~12 min total (cold-start verification dominates)
- **Started:** 2026-05-08 (plan execution began with first edit)
- **Completed:** 2026-05-08
- **Tasks:** 3
- **Files modified:** 3 (test/test_validation.jl, test/test_determinacy.jl, scratch/diag_val02_twoplate_solve.jl created)

## Accomplishments

- VAL-02 two-plate steady topology compiles with `fully_determined=true` (n_eqs=91, n_unknowns=91, Δ=0)
- VAL-02 two-plate `solve_steady` returns `Success` with energy balance `T_rise` matching expected `2P/(ṁ·cp)` to 0.06% (18.62 K actual vs 18.63 K expected)
- VAL-02 transient T_wall step testset runs to completion and passes its 3 `@test` assertions (no `ArgumentError: System sys: variable sys does not exist`)
- All 5 Phase-58 scenario rows in `test/test_determinacy.jl` GREEN (was 4 PASS / 1 ERROR before this plan)
- `grep -c 'fully_determined=false' test/test_validation.jl` returns **0** — file-level evidence that the bug-hiding audit sweep is complete for `test_validation.jl`

## Task Commits

Each task was committed atomically on `worktree-agent-ac4f8f5ff3b8a6206`:

1. **Task 1: VAL-02 two-plate — two pins + audit flip; sync test_determinacy.jl helper** — `016a54c` (fix)
2. **Task 2: VAL-02 transient symbol-access fix at line 317** — `65428c3` (fix)
3. **Task 3: Flip simple_loop audit site at test_validation.jl:204** — `fe7b315` (fix)

## Files Created/Modified

### Created

- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate_solve.jl` — Standalone proof script: builds the VAL-02 two-plate topology with both pins, calls `mtkcompile(...; fully_determined=true)`, runs `solve_steady`, asserts energy balance. Captures end-to-end proof outside the test_validation.jl try/catch block.

### Modified

- `test/test_validation.jl` — Five line-level edits across three testsets:
  - Line 204 (simple_loop): `mtkcompile(sys; fully_determined=false)` → `=true` (Task 3, bug-hiding flag flip)
  - Line 317 (VAL-02 transient): `T_wall_sym = ssys.sys.T_wall_callable` → `T_wall_sym = ssys.T_wall_callable` (Task 2, symbol-access fix)
  - Lines 996-1001 (VAL-02 two-plate): inserted comment + `hd1.power ~ power_per_plate,` + `hd2.power ~ power_per_plate,` (Task 1, two pins)
  - Line 1007 (VAL-02 two-plate, was :996): `mtkcompile(sys_v02; fully_determined=false)` → `=true` (Task 1, audit flip)
- `test/test_determinacy.jl` — Helper sync:
  - Lines 203-204 in `_build_val02_twoplate`: replaced two `# Plan 58-04 adds:` placeholder comments with `hd1.power ~ power_per_plate,` and `hd2.power ~ power_per_plate,` (Task 1, helper update)

## Verification cycle

### Determinacy regression gate — `julia --project=. test/test_determinacy.jl`

Cold-start run after all three commits land:

```
Test Summary:                                        | Pass  Total   Time
Determinacy: canonical builders are fully determined |    6      6  56.1s

Test Summary:                   | Pass  Total  Time
Determinacy: Phase 58 scenarios |    5      5  4.0s
  MTR symmetric                 |    1      1  ...
  MTR asymmetric                |    1      1  ...
  MTR one-sided                 |    1      1  ...
  VAL-01 Fourier                |    1      1  ...
  VAL-02 twoplate               |    1      1  ...   ← Plan 58-04 RED→GREEN
```

All 5 Phase-58 scenario rows GREEN, all 6 canonical-builder rows GREEN — no regressions.

### Standalone VAL-02 two-plate solve probe — `julia --project=. .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate_solve.jl`

```
compile OK n_eqs=91 n_unk=91
solve retcode = Success
T_rise expected = 18.634148042438408  actual = 18.62315844599425  isapprox(rtol=0.05): true
```

`mtkcompile(...; fully_determined=true)` succeeds with the predicted Δ=0 (`n_eqs=91=n_unknowns=91`, matching `scratch/diag_table.md` Scenario E). `solve_steady` returns `ReturnCode.Success`. The energy balance `T_rise ≈ 2·power_per_plate / (ṁ·cp)` matches the expected value to 0.06% (well within the test_validation.jl assertion's 5% rtol).

### test_validation.jl validation — `julia --project=. test/test_validation.jl`

The kept testset block (line 837-1228) wraps VAL-01 Fourier, VAL-02 two-plate, and PK validation in a single `try ... catch`. VAL-01 Fourier's `BoundsError` (documented out-of-scope in 58-03 §Deviations §1: `solve(prob_v01, Rodas5P()...)` returns `ReturnCode.InitialFailure` with `length(sol.u) == 1`, then indexing `T_center_series[1]` raises `BoundsError`) exits the try block before the VAL-02 two-plate testset can execute. This pre-exists Plan 58-04 and is owned by a future numerical-investigation plan.

In-scope-for-58-04 testset results from the cold-start run:

```
Test Summary:                                        | Pass  Fail  Total     Time
Phase 56 parity harness                              |  467    92    559  1m39.1s
  Python parity: simple loop                         |   86           86  1m01.9s   ← Task 3 GREEN
  VAL-02: Transient T_outlet rises after T_wall step |    3            3    14.6s   ← Task 2 GREEN
  Python parity: MTR symmetric                       |  145    32    177    16.4s   ← Phase 56 parity Fs (pre-existing, OOS)
  Python parity: MTR asymmetric                      |  137    40    177     1.4s   ← Phase 56 parity Fs (pre-existing, OOS)
  Python parity: MTR one-sided                       |   96    20    116     4.8s   ← Phase 56 parity Fs (pre-existing, OOS)
```

The 86/86 simple-loop pass after the `=true` flip confirms Task 3 is structurally clean. The 3/3 VAL-02 transient pass (was previously erroring with `ArgumentError: System sys: variable sys does not exist`) confirms Task 2 fixes the symbol-access bug. The 92 FAIL-tier rows in the MTR-* parity testsets are Phase-56 parity drift (Gap #2 candidate — HTC film-T vs bulk-T noted at lines 256, 260) — unrelated to Plan 58-04 and pre-existing. Plan 58-04's structural gate is satisfied: every kept testset that runs reaches `solve_*` Success.

VAL-02 two-plate's end-to-end behavior is confirmed by the standalone scratch script above (which also verifies the energy-balance assertion that line 1019 in the test would check).

### Bug-hiding flag sweep

```
$ grep -cn 'fully_determined=false' test/test_validation.jl
0
```

Zero matches — every `mtkcompile` call in `test/test_validation.jl` now uses `fully_determined=true`. The file-level evidence that Phase 58's bug-hiding audit sweep for this file is complete.

### Branching invariant

```
$ git rev-parse --abbrev-ref HEAD
worktree-agent-ac4f8f5ff3b8a6206
```

The worktree-agent branch is the documented per-agent exception in CLAUDE.md "Branching Policy". No `git switch` / `git checkout -b` / `git branch <new>` invoked. `.planning/config.json` `git.branching_strategy` left as `"none"`.

## Decisions Made

- **Pin shape (Task 1):** Two pins at `power_per_plate` (the local variable already passed to both HD constructors at lines 957 and 969). Same shape as MTR/VAL-01 single-pin fixes, scaled to N=2 for the Δ=−2 deficit. Live-verified in `scratch/diag_val02_twoplate.jl` (Δ=−2 with no pins → Δ=0 with both pins).
- **Symbol access (Task 2):** Direct `ssys.T_wall_callable` rather than `last(parameters(ssys))` (which is also valid per RESEARCH OQ-2). The named access is more readable, and the test's existing inline comment ("stable named access, immune to parameter reordering") was authored with the named access in mind — the fix only drops the spurious `.sys.` namespace segment. No comment edit required.
- **Order of edits / commits:** Three separate commits (one per task) instead of a single squashed commit. The plan explicitly identifies three distinct edits with three distinct justifications, and the per-task commit is the GSD-mandated atomic unit.
- **Standalone proof script:** Added `scratch/diag_val02_twoplate_solve.jl` to capture the end-to-end VAL-02 two-plate solve_steady success outside the test_validation.jl try/catch (which VAL-01 Fourier's pre-existing BoundsError exits before VAL-02 two-plate executes). Without this, the only direct evidence of the test_validation.jl assertions' passing would be the determinacy contract; the script captures the full energy-balance check.

## Deviations from Plan

### Auto-fixed Issues / Documented out-of-scope

**1. [Documented out-of-scope] VAL-02 two-plate testset blocked from running by VAL-01 Fourier's pre-existing BoundsError**

- **Found during:** Final `julia --project=. test/test_validation.jl` validation step.
- **Issue:** VAL-01 Fourier, VAL-02 two-plate, and PK validation testsets are wrapped in a single `try ... catch` block (lines 837-1228). VAL-01 Fourier raises a `BoundsError` (carried over from 58-03 §Deviations §1: `solve` returns `InitialFailure` with `length(sol.u) == 1`, indexing `T_center_series[1]` then raises `BoundsError`). The `catch` block at line 1227 swallows the exception with `@warn`, but the try block has already exited — VAL-02 two-plate (line 939) and PK validation (line 1053) never execute under `julia test/test_validation.jl`.
- **Why this is out of scope:** Plan 58-03 §Deviations §1 explicitly documents the `InitialFailure` as out-of-scope numerical investigation. Plan 58-04's structural deliverable for VAL-02 two-plate is the determinacy contract (`mtkcompile(...; fully_determined=true)` succeeds with Δ=0), which is verified GREEN in `test/test_determinacy.jl`. The end-to-end `solve_steady` plus energy-balance assertion is also verified — but via `scratch/diag_val02_twoplate_solve.jl` rather than the wrapping testset, because the wrapping try block is blocked by VAL-01 Fourier's pre-existing failure.
- **Fix applied:** None within Plan 58-04 scope. Future ownership: a numerical-investigation plan (Phase 59 or later) needs to diagnose and fix the VAL-01 Fourier `Rodas5P` `InitialFailure`. Once that lands, the `BoundsError` disappears, the try block runs to completion, and VAL-02 two-plate + PK validation testsets execute under `julia test/test_validation.jl` directly.
- **Files affected:** None (analysis only; standalone proof script added under `scratch/`).
- **Commit:** `fe7b315` (Task 3 commit, includes the `scratch/diag_val02_twoplate_solve.jl` proof script).

**2. [Inline-noted] Plan source-line numbers shifted slightly relative to plan body**

- **Found during:** Task 1 edit prep.
- **Issue:** Plan 58-04 references the VAL-02 two-plate `mtkcompile` audit site as line 996 and the closing `]` of `conns_v02` as line 992. In the actual file the closing `]` is at line 996 and the `mtkcompile` call is at line 1000 (pre-edit).
- **Why this is not a deviation in the GSD-rules sense:** The plan's `<verify>` and `<acceptance_criteria>` blocks gate on grep-content, not line numbers. All grep checks (`grep -c 'hd1.power ~ power_per_plate'` etc.) pass. The inline `<source_lines>` block in the plan is documentary — it captures author intent ("two pins right before the closing `]` of `conns_v02`"), and that intent was honored. Recorded here for future plan-author reference.
- **Fix applied:** N/A — plan executed correctly against the actual file content.
- **Commit:** N/A.

### Auth gates

None.

## Forbidden actions audit

- [x] No `check_length=false` added — VERIFIED (D-05 lock honored)
- [x] No edits to `src/` — VERIFIED
- [x] No `Manifest.toml` MTK package version bumps — VERIFIED
- [x] No `connect(...)` lines added/removed beyond the new pin equations — VERIFIED
- [x] No tolerance widening or `try/catch` added around `solve` — VERIFIED
- [x] No new branches created — VERIFIED (worktree-agent branch is the documented per-agent exception)

## Per-plan ownership matrix (post-58-04 status)

| Plan | Status | Scenarios | test_validation.jl | test_determinacy.jl | Audit flips |
|------|--------|-----------|---------------------|----------------------|-------------|
| 58-01 | DONE | (diagnostic + scaffold) | (none) | created | (none yet) |
| 58-02 | DONE | MTR sym/asym/one-sided GREEN | 3 pins + 3 audit flips | 3 helper updates | lines 380, 551, 712 flipped |
| 58-03 | DONE | VAL-01 Fourier GREEN (determinacy) | 1 pin + 1 audit flip at :902/:907 | 1 helper update at :169 | line 907 flipped |
| **58-04** | **DONE** | **VAL-02 twoplate GREEN; VAL-02 transient GREEN; simple_loop audit-clean** | **2 pins at :1001-1002 + symbol fix at :317 + 2 audit flips** | **1 helper update (2 pins) at :203-204** | **lines 204, 1007 flipped** |
| 58-05 | pending | (audit-only + PK verify) | (none) | (none) | inline comments + flapper.jl docstring tighten |

## Lessons learned

- **N-pin generalization:** the single-pin pattern from 58-02/58-03 (`hd.power ~ value`) extends cleanly to N HD instances with N pins. Plan 58-04 confirms the diagnostic-table prediction (Δ=−2 with two HDs → Δ=0 with two pins). For future topologies with M HD instances, expect Δ=−M (one pin missing per instance) absent any closing equations.
- **`ssys.<name>` is the canonical post-compile access pattern:** the `.sys.` segment was a leftover from an older MTK API where the compiled system was a thin wrapper around an internal `sys`. Current MTK exposes named properties directly on the compiled system. The named access (`ssys.T_wall_callable`) and the indexed-parameter access (`last(parameters(ssys))`) both resolve; the named access reads better and is selected by Plan 58-04 deliberately.
- **try/catch wraps interact with deferred-items:** when a kept-block try wraps multiple testsets (VAL-01 + VAL-02 two-plate + PK validation in this file), a failure in the FIRST kept testset short-circuits all remaining testsets in the same block. If a fix plan owns one of the LATER testsets but not the FIRST, the wrapping try block can prevent the LATER testset from executing under the file-level run — even after the structural fix lands. The standalone proof script under `scratch/` is the correct mitigation.
- **PreToolUse "READ-BEFORE-EDIT REMINDER" hook continues to fire informationally:** all four Edit calls in this plan triggered the hook even though the Read tool had been used on each path in the same session. Same observation as Plans 58-02 and 58-03: the warning is informational; the determinant is whether the file on disk reflects the change (verified via `git status` + `git diff --stat`).

## Issues Encountered

- **`test/data/parity_report.csv` modified by test_validation.jl run** (CSV append at line 283 in the simple_loop testset). The file is git-tracked but unrelated to Plan 58-04's code edits — it is a regression artifact updated by previous fix commits (`ae61bc1`, `2cf8a02`, etc.). Deliberately NOT staged in any of the three task commits to keep the per-task diff focused on plan deliverables. The user can decide whether to commit the parity drift refresh as a separate change.

## Self-Check: PASSED

- `test/test_validation.jl` line 204 reads `ssys = mtkcompile(sys; fully_determined=true)` — VERIFIED via `sed -n '204p'`
- `test/test_validation.jl` line 317 reads `T_wall_sym = ssys.T_wall_callable   # stable named access, immune to parameter reordering` — VERIFIED via `sed -n '317p'`
- `test/test_validation.jl` lines 1001-1002 contain `hd1.power ~ power_per_plate,` and `hd2.power ~ power_per_plate,` — VERIFIED via `grep -n`
- `test/test_validation.jl` line 1007 reads `ssys_v02 = mtkcompile(sys_v02; fully_determined=true)` — VERIFIED via `grep -n 'ssys_v02 = mtkcompile'`
- `test/test_determinacy.jl` lines 203-204 contain `hd1.power ~ power_per_plate,` and `hd2.power ~ power_per_plate,` — VERIFIED via `grep -n`
- `grep -c 'fully_determined=false' test/test_validation.jl` returns `0` — VERIFIED
- `grep -c 'ssys\.sys\.T_wall_callable' test/test_validation.jl` returns `0` — VERIFIED
- Commits `016a54c`, `65428c3`, `fe7b315` exist in `git log --oneline` — VERIFIED
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate_solve.jl` exists — VERIFIED
- HEAD on `worktree-agent-ac4f8f5ff3b8a6206` post-commit — VERIFIED
- No `src/` modifications — VERIFIED
- All 5 Phase-58 scenario rows in `test/test_determinacy.jl` PASS (cold-start verified) — VERIFIED
- All 6 canonical-builder rows still PASS (no regression) — VERIFIED
- VAL-02 two-plate `solve_steady` returns `Success` with energy balance at 0.06% drift (well within 5% rtol) — VERIFIED via `scratch/diag_val02_twoplate_solve.jl`
- VAL-02 transient testset 3/3 PASS — VERIFIED via `julia test/test_validation.jl` summary

## Next Phase Readiness

- Phase 58 has two remaining plans: 58-05 (audit-only inline comment tightening + PK verify) and any closing/archiving plan. The structural-fix wave (58-02 → 58-04) is complete: every Phase-58 scenario row is GREEN, and `test/test_validation.jl` carries zero `fully_determined=false` flags.
- Pre-existing out-of-scope work: VAL-01 Fourier `Rodas5P` `InitialFailure` (documented in 58-03 §Deviations §1). Future numerical-investigation plan (Phase 59 or later) should diagnose and fix; once it lands, the wrapping try block in test_validation.jl runs to completion and the VAL-02 two-plate + PK validation testsets execute under direct file run.

---
*Phase: 58-mtk-system-determinacy-repair*
*Completed: 2026-05-08*
