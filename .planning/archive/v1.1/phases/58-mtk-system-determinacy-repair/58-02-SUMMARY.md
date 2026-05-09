---
phase: 58-mtk-system-determinacy-repair
plan: 02
subsystem: mtk
status: complete
tags: [mtk, determinacy, mtr, fix]
dependency_graph:
  requires:
    - .planning/phases/58-mtk-system-determinacy-repair/58-01-SUMMARY.md
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md
  provides:
    - "Three MTR scenarios reach solve_steady ReturnCode.Success"
    - "Three Phase-58 determinacy regression rows GREEN"
    - "Real MTR rows in test/data/parity_report.csv (no more solver_error sentinels)"
  affects:
    - test/test_validation.jl
    - test/test_determinacy.jl
    - test/data/parity_report.csv
tech_stack:
  added: []
  patterns:
    - "Closing-equation pin (hd.power ~ value) to balance HeatDiffusion's free power(t) variable"
key_files:
  created: []
  modified:
    - test/test_validation.jl
    - test/test_determinacy.jl
    - test/data/parity_report.csv
decisions:
  - "Pin hd.power ~ 1e4 (the same value used at the HeatDiffusion constructor) on all three MTR scenarios"
  - "Flip MTR audit sites to fully_determined=true in the same diff (per Plan 58-01 OQ-4)"
  - "Mirror the pin in test/test_determinacy.jl helpers so the regression gate flips to GREEN at the same commit"
metrics:
  duration: "~1 hour total (cold-start verification dominates)"
  completed: 2026-05-08
  tasks_completed: 1
  files_changed: 3
scenarios_addressed:
  - MTR-SYM
  - MTR-ASYM
  - MTR-ONESIDED
---

# Phase 58 Plan 02: MTR Determinacy Fix (sym + asym + one-sided) Summary

Mechanical fix from Plan 58-01's diagnostic table applied to the three MTR scenarios: a single closing equation `hd.power ~ 1e4` added to each scenario's `conns` vector, plus the corresponding three `fully_determined=false` audit sites flipped to `=true`, plus three identical pins added to the matching `_build_mtr_*` helpers in `test/test_determinacy.jl`. Three Phase-58 rows in `test/test_determinacy.jl` go RED→GREEN; three MTR testsets in `test/test_validation.jl` reach `ReturnCode.Success` and emit real per-tier rows to `test/data/parity_report.csv` instead of the prior `solver_error` sentinel.

## What was built

Nine line-level edits across two files (the planned shape of the fix), plus one regenerated test artifact:

### `test/test_validation.jl` — six edits in three testsets

| # | Site | Before | After |
| - | ---- | ------ | ----- |
| 1 | line 374→375 (MTR sym `conns` vector) | last bracket-list-splat then `]` | `hd.power ~ 1e4,` inserted as last element before `]` |
| 2 | line 379 (was 379 → still 380 after insert) | `ssys = mtkcompile(sys; fully_determined=false)` | `ssys = mtkcompile(sys; fully_determined=true)` |
| 3 | line 544→546 (MTR asym `conns` vector) | last bracket-list-splat then `]` | `hd.power ~ 1e4,` inserted as last element before `]` |
| 4 | line 549→551 | `ssys = mtkcompile(sys; fully_determined=false)` | `ssys = mtkcompile(sys; fully_determined=true)` |
| 5 | line 706→709 (MTR one-sided `conns` vector) | last bracket-list-splat then `]` | `hd.power ~ 1e4,` inserted as last element before `]` |
| 6 | line 709→712 | `ssys = mtkcompile(sys; fully_determined=false)` | `ssys = mtkcompile(sys; fully_determined=true)` |

### `test/test_determinacy.jl` — three edits in three helpers

| # | Site | Before | After |
| - | ---- | ------ | ----- |
| 7 | `_build_mtr_sym` (~line 91) | `# Plan 58-02 adds: hd.power ~ 1e4` | `hd.power ~ 1e4,` (real equation in place of placeholder) |
| 8 | `_build_mtr_asym` (~line 124) | same placeholder comment | `hd.power ~ 1e4,` |
| 9 | `_build_mtr_onesided` (~line 148) | same placeholder comment | `hd.power ~ 1e4,` |

### `test/data/parity_report.csv` — regenerated as side effect of running `test_validation.jl`

The MTR `solver_error` sentinel rows are gone; real per-tier rows now occupy that space (478 inserted CSV lines, 28 deleted — the deleted lines are the three sentinel placeholders plus minor trailing-digit deltas in pre-existing `simple_loop` rows that come from rebuilding the same numerical computation). No solver-error sentinel rows exist for `mtr_symmetric`, `mtr_asymmetric`, or `mtr_one_sided` after the regeneration.

## Verification cycle

### Determinacy regression gate — `julia --project=. test/test_determinacy.jl`

```
Test Summary:                                        | Pass  Total   Time
Determinacy: canonical builders are fully determined |    6      6  56.1s

Test Summary:                   | Pass  Error  Total  Time
Determinacy: Phase 58 scenarios |    3      2      5  5.0s
  MTR symmetric                 |    1             1  2.1s   ← Plan 58-02 RED→GREEN
  MTR asymmetric                |    1             1  0.6s   ← Plan 58-02 RED→GREEN
  MTR one-sided                 |    1             1  0.4s   ← Plan 58-02 RED→GREEN
  VAL-01 Fourier                |           1      1  1.4s   ← still RED — Plan 58-03 owns
  VAL-02 twoplate               |           1      1  0.4s   ← still RED — Plan 58-04 owns
```

The two remaining errors are `ExtraVariablesSystemException` from the same family of unknowns_pin gap, expected per Plan 58-01's per-plan ownership matrix.

### MTR retcode verification — `julia --project=. test/test_validation.jl`

```
Test Summary:                                        | Pass  Fail  Error  Total     Time
Phase 56 parity harness                              |  464    92      1    557  1m26.8s
  Python parity: simple loop                         |   86                  86    59.4s
  VAL-02: Transient T_outlet rises after T_wall step |                 1      1     5.3s   ← Plan 58-04 owns
  Python parity: MTR symmetric                       |  145    32           177    15.5s   ← solve_steady SUCCESS
  Python parity: MTR asymmetric                      |  137    40           177     1.4s   ← solve_steady SUCCESS
  Python parity: MTR one-sided                       |   96    20           116     5.2s   ← solve_steady SUCCESS
```

`grep "solver_error" /tmp/val_output.txt` returns **empty** — no MTR scenario emits the sentinel row. Real per-tier results now flow to `parity_report.csv`. The 32 / 40 / 20 tier-FAIL rows in MTR sym / asym / one-sided are pre-existing tier-verdict gaps owned by Plan 56-06's resume (HTC film-T fine-tuning, partition-q, plate-T tier-d ceiling decisions, KNOWN GAP D-11 widening). They are explicitly out of Plan 58-02 scope per the plan's `<acceptance_criteria>` (line "Tier-FAIL rows are out of scope").

### Branching invariant

```
$ git rev-parse --abbrev-ref HEAD
worktree-agent-ad31a7d7b30678f58
```

The worktree-agent branch is the documented per-agent exception in CLAUDE.md "Branching Policy". The orchestrator merges this branch into the user's `channels-redesign` working branch after all wave-2 plans complete. No `git switch` / `git checkout -b` / `git branch <new>` was invoked. `git config branch.*.remote` was not modified.

## Acceptance criteria check

- [x] `grep -n 'hd.power ~ 1e4' test/test_validation.jl` returns exactly 3 matches (lines 375, 546, 709) — VERIFIED
- [x] `grep -n 'fully_determined=false' test/test_validation.jl` no longer matches lines 379, 549, 709; those three lines now read `fully_determined=true` (at 380, 551, 712 after pin insertion shifted line numbers by one each) — VERIFIED
- [x] `grep -c 'hd.power ~ 1e4' test/test_determinacy.jl` returns exactly 3 (lines 91, 124, 148) — VERIFIED
- [x] `julia --project=. test/test_determinacy.jl`: three MTR Phase-58 rows PASS — VERIFIED
- [x] `julia --project=. test/test_validation.jl`: MTR testsets run to completion; no `solver_error` sentinel — VERIFIED
- [x] `git rev-parse --abbrev-ref HEAD` returns the per-agent branch (worktree-agent exception) — VERIFIED
- [x] No `git switch` / `git checkout -b` / `git branch` invoked — VERIFIED
- [x] Working tree contains exactly two source-file modifications (`test/test_validation.jl`, `test/test_determinacy.jl`); `test/data/parity_report.csv` is a regenerated test artifact, not a source change. No `src/` files modified — VERIFIED

## Forbidden actions audit

- [x] No `check_length=false` added — VERIFIED (D-05 lock honored)
- [x] No edits to `src/components/heat_diffusion.jl` — VERIFIED
- [x] No `Manifest.toml` MTK package version bumps — VERIFIED
- [x] No `connect(...)` lines added/removed beyond the three new pin equations — VERIFIED
- [x] No tolerance widening or `try/catch` added around `solve_steady` — VERIFIED

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Edit tool initially routed first 7 of 9 edits to the main repo path instead of the worktree path**

- **Found during:** First verification grep after applying all 9 edits. `git status --short` in the worktree showed clean tree; `git status` in the main repo (`/home/itay/projects/Julia-STREAM/`) showed `M test/test_validation.jl` and `M test/test_determinacy.jl` despite this executor running inside the worktree at `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-ad31a7d7b30678f58/`.
- **Issue:** The Edit tool calls used absolute paths `/home/itay/projects/Julia-STREAM/test/test_validation.jl` and `/home/itay/projects/Julia-STREAM/test/test_determinacy.jl` (main-repo paths) for the first 7 edits, instead of the worktree-prefixed paths `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-ad31a7d7b30678f58/test/...`. This is the absolute-path safety violation #3099 that the executor's path-guard step warns against. The Edit tool reported "updated successfully" on each of those 7 calls, but the file modifications landed in the main-repo working tree, not the worktree's working tree. The harness's read-tracking was based on file path, so the readbefore-edit guard (which used the worktree-prefixed path on initial Reads) failed to catch the divergence.
- **Fix:**
  1. Reverted the 7 main-repo edits with `git checkout -- test/test_validation.jl test/test_determinacy.jl` inside the main repo. Confirmed via md5 that the main-repo files match HEAD again.
  2. Re-Read each affected file via the worktree-prefixed absolute path (so the Edit tool's read-tracking would associate the Read with the worktree path).
  3. Re-applied the same 7 edits with explicit worktree-prefixed absolute paths.
  4. Verified all 9 edits landed in the worktree tree only (md5 mismatch with main repo confirms divergence is intentional and lives only in the worktree).
- **Files affected:** `test/test_validation.jl`, `test/test_determinacy.jl` — temporarily modified the main repo but reverted before any commit on either side.
- **Commit:** No separate commit; `ae61bc1` contains only the correct worktree-side edits.

**Note on the read-before-edit hook:** The PreToolUse hook fired a "READ-BEFORE-EDIT REMINDER" warning on every edit call (including ones that succeeded). The warning appears to be advisory rather than blocking — the actual edit operation succeeded each time the worktree-prefixed path was used and a prior Read of that exact path had been issued in the session. This is consistent with the hook being a heuristic rather than a hard gate. The deviation above is the only one where the warning was actionable; in all other cases the edits landed correctly.

### Auth gates

None.

## Per-plan ownership matrix (post-58-02 status)

| Plan | Status | Scenarios | test_validation.jl | test_determinacy.jl | Audit flips |
|------|--------|-----------|---------------------|----------------------|-------------|
| 58-01 | ✅ DONE | (diagnostic + scaffold) | (none) | created | (none yet) |
| **58-02** | **✅ DONE** | **MTR sym/asym/one-sided GREEN** | **3 pins + 3 audit flips** | **3 helper updates** | **lines 379→380, 549→551, 709→712 flipped** |
| 58-03 | pending | VAL-01 Fourier | 1 pin + 1 flip at :903 | helper update | 1 audit flip |
| 58-04 | pending | VAL-02 steady + transient | 2 pins at :996 + symbol fix at :317 | helper update | 2 audit flips |
| 58-05 | pending | (audit-only + PK verify) | (none) | (none) | inline comments + flapper.jl docstring tighten |

## Lessons learned

- The single-pin fix (`hd.power ~ 1e4`) is a tiny, mechanical equation that closes Δ=−1 in three different topologies, validating Plan 58-01's RESEARCH §3 OQ-1 collapse decision: the three MTR scenarios are structurally identical from the determinacy point of view; one fix plan covers all three. Plans 58-03 and 58-04 follow the same shape with a single-pin (Δ=−1) and double-pin (Δ=−2) variant respectively.
- Worktree-isolated executors must use **worktree-prefixed absolute paths** in every Edit tool call, not just the obvious-looking shorter `/home/<user>/projects/<repo>/...` paths. The shorter paths point at the user-owned main repo and writes there bypass the worktree's branch isolation. This is documented in `references/worktree-path-safety.md` (#3099). The path-guard step in `agents/gsd-executor.md` step 0b is the authoritative checklist; deriving paths from `git rev-parse --show-toplevel` after the worktree-branch-check at agent startup is the safe pattern.
- The "READ-BEFORE-EDIT REMINDER" PreToolUse hook is advisory — its warning fires on every Edit tool call regardless of whether the actual read-tracking gate would pass. Treat the hook output as informational only; the real determinant is whether the file on disk reflects the change (verifiable via `grep` / `git status` in Bash).

## Self-Check: PASSED

- `test/test_validation.jl` modified — VERIFIED (md5 changed; 3 hd.power pins; 3 fully_determined audit flips at lines 380, 551, 712)
- `test/test_determinacy.jl` modified — VERIFIED (md5 changed; 3 hd.power pins at lines 91, 124, 148)
- `test/data/parity_report.csv` regenerated — VERIFIED (478 inserts, 28 deletes; no solver_error rows for mtr_*)
- Commit `ae61bc1` exists in `git log --oneline` — VERIFIED
- HEAD on `worktree-agent-ad31a7d7b30678f58` post-commit — VERIFIED
- No `src/` modifications — VERIFIED
- All three MTR rows in test/test_determinacy.jl PASS — VERIFIED via cold-start `julia --project=. test/test_determinacy.jl`
- All three MTR testsets in test/test_validation.jl reach `ReturnCode.Success` (no `solver_error` sentinel emitted) — VERIFIED via cold-start `julia --project=. test/test_validation.jl`
