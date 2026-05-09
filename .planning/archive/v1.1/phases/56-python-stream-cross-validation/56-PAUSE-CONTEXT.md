# Phase 56 — Pause Context

**Status:** PAUSED mid-Plan-06 on 2026-05-08.
**Resume gate:** Phases 57 (HTC film-T) and 58 (MTK determinacy) must both ship before Plan 56-06 can close v1.1.

## What shipped

| Plan | State |
|------|-------|
| 56-01 | ✓ Complete — `test/parity_helpers.jl` (274 lines) |
| 56-02 | ✓ Complete — `test/generate_reference.py` rewritten (139 lines, 4 inline bug-fixes via Plan 04) |
| 56-03 | ✓ Complete — `test/generate_mtr_reference.py` rewritten (555 lines) |
| 56-04 | ✓ Complete — `test/data/python_parity_reference.jl` (674 lines, 65 const PARITY_*) + 4 PYTHON_*_AT_REF tuples paste at %.17g |
| 56-05 | ✓ Complete — `test/test_validation.jl` (880 lines) parity_check pipeline + 12 harness self-tests + parity_report.csv (86 rows) |
| 56-06 | ◆ PAUSED — Task 1 (cleanup grep, branch verify, suite tally) ran inline; Task 2 (human-verdict) returned "do not close — fix root causes first"; Task 3 (MILESTONES.md narrative) NOT started |

## What the parity harness reports right now

86 rows, 21 CLEAN, 12 GRAY, 53 FAIL. The FAIL profile decomposes to:

- **40 rows** = HTC eval-point gap (Gap #2). Julia evaluates fluid props at T_cool; Python evaluates at T_film = (T_cool+T_wall)/2. ~19% h_tc drift cascades into ~19% q_density drift via q = h·ΔT. **Phase 57 fixes this at source.**
- **3 rows** = MTR sentinels (D-1 MTK API mismatch). Pre-existing breakage; MTR scenarios cannot reach `solve_steady`. **Phase 58 fixes this at source.**
- **10 rows** = q_density_total — same Gap #2 cascade, mislabeled in 56-05 SUMMARY as "Gap #1 mitigated"; in fact Gap #1 (heated_parts partition) is exact, the residual drift is Gap #2.

**No new Julia regressions.** Everything is either a known design gap (Gap #2, fixable in Phase 57) or a pre-existing API drift (D-1, fixable in Phase 58). The harness is doing its job.

## Decisions made during Plan 06 Task 2

1. **Verdict (c)-shaped:** Do NOT close v1.1 with documented hard_ceiling widening. Replicate Python STREAM behavior, do not paper over with looser tolerances. (User directive 2026-05-08.)
2. **Phase 57 (HTC film-T):** Change Julia HTC correlations to evaluate fluid props at T_film = (T_cool + T_wall)/2, matching Python. Expect h_tc + q_density drift to collapse to CLEAN/GRAY.
3. **Phase 58 (MTK determinacy):** Find why current loop builders produce under-determined systems. Fix at source so equations == unknowns. No `check_length=false` workarounds. Once fixed, MTR scenarios + HD Fourier + 2-plate + PK + VAL-02 all run.
4. **D-2 (geometry precision)** — was going to fold into Plan 06; defer to Phase 57 or 58 since Plan 06 isn't running anyway.

## What to do on resume (after Phases 57 + 58 ship)

1. Re-run the harness:
   ```
   bin/jl test/runtests.jl
   ```
   Inspect `test/data/parity_report.csv` — expect zero FAIL rows beyond GRAY-tier physics drift. If FAIL rows persist, that's a real Julia regression and Phases 57/58 didn't fully address it.
2. Resume Plan 06 Task 1 (re-tally) and Task 3 (MILESTONES.md narrative) using the new parity report.
3. Use `/gsd:execute-phase 56` again to re-enter; init context will detect Plan 06 has no SUMMARY and resume from there.
4. Run gsd-verifier, /gsd:ship, /gsd:complete-milestone.

## Pre-existing baselines (record for the resume tally)

| Failure | Origin | Phase 57/58 should resolve? |
|---------|--------|------------------------------|
| NET-03 Cube flow | Phase 55 D-22 documented flaky | No — independent flaky |
| HD Fourier (VAL-01) | D-1 MTK API mismatch | Yes (Phase 58) |
| Two-plate one-channel (KEPT) | D-1 MTK API mismatch | Yes (Phase 58) |
| PointKinetics validation (KEPT) | D-1 MTK API mismatch | Yes (Phase 58) |
| VAL-02 transient T_wall step | D-1-related (`variable sys does not exist`) | Yes (Phase 58) |
| MTR sym/asym/one-sided parity sentinels | D-1 MTK API mismatch | Yes (Phase 58) |
| 40 simple-loop h_tc + q_density FAIL rows | Gap #2 HTC eval point | Yes (Phase 57) |
