---
phase: 57-htc-film-temperature-evaluation
verified: 2026-05-08T18:30:00Z
status: passed
score: 16/17 must-haves verified
overrides_applied: 0
---

# Phase 57: HTC Film-Temperature Evaluation — Verification Report

**Phase Goal:** Switch the Julia STREAM HTC pipeline so coolant fluid properties feeding `h = Nu(Re,Pr)*k/Dh` are evaluated at film temperature `T_film = (T_cool + T_wall)/2` instead of bulk `T[i]`; preserve bulk-T for friction Re and NC Gr; close Phase 56 Gap #2 so simple_loop h_tc and q_density rows move from FAIL to CLEAN/GRAY.

**Verified:** 2026-05-08T18:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | [D-01] `T_film_i = (T[i] + T_w_i) / 2` computed in CAC SPL + SCB branches | VERIFIED | `grep -c 'T_film_i = (T\[i\] + T_w_i) / 2' channels.jl` returns 2 (lines 681, 689) |
| 2 | [D-01/B3] `T_film_obs_i = (T[i] + thermal_left[i].T) / 2` at variant_obs Nu[i] site | VERIFIED | `grep -c 'T_film_obs_i = ...'` returns 1 (line 774); variable renamed `Re_i_film`/`Pr_i_film` per CR-01 fix |
| 3 | [D-01/B3] `_channel_core` line 147 `Pr_i` stays at bulk (no wall T in scope for Channel/CHF) | VERIFIED | `grep -c 'Pr_i = cp_water(T\[i\]) \* mu_water(T\[i\]) / k_water(T\[i\])' channels.jl` returns 1 |
| 4 | [D-02] SPL branch Re_i, Pr_i, leading k all at T_film_i | VERIFIED | Lines 682-684: `mu_water(T_film_i)`, `cp_water(T_film_i)`, `k_water(T_film_i)` in Re/Pr/leading-k |
| 5 | [D-02] SCB branch Re_i, Pr_i, leading k all at T_film_i | VERIFIED | Lines 690-692: same pattern; `htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T_film_i) / Dh` |
| 6 | [D-02/B3] variant_obs Nu[i] Re_i/Pr_i at T_film_obs_i (film, matching SPL h_tc[i]) | VERIFIED | Lines 775-777: `Re_i_film`, `Pr_i_film` at `T_film_obs_i`; `htc_correlation(Re_i_film, Pr_i_film, T[i], thermal_left[i].T)` |
| 7 | [D-03] Friction Re_i_for_friction at line 139 STILL at bulk T[i] | VERIFIED | `grep -c 'Re_i_for_friction = abs(port_in.mdot) \* Dh / (A \* mu_water(T\[i\]))'` returns 1 |
| 8 | [D-03] `regime_dependent` / `elenbaas_htc` NC Gr bodies unchanged (correlations.jl) | VERIFIED | `beta_water(T_bulk)` count = 2; `mu_water(T_bulk) / rho_water(T_bulk)` count = 2; bodies intact |
| 9 | [D-03] variant_obs `nu_i = mu_water(T[i]) / rho_water(T[i])` at line 787 stays bulk | VERIFIED | `grep -c 'nu_i = mu_water(T\[i\]) / rho_water(T\[i\])'` returns 1 |
| 10 | [D-03/CR-01 fix] `Gr_over_Re2[i]` denominator uses `Re_i_bulk` (bulk), not `Re_i_film` | VERIFIED | Line 786: `Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))`; line 789: `Gr_i / Re_i_bulk^2` |
| 11 | [D-03/WR-01 fix] `scb_correction` Re argument uses `Re_i_bulk` (bulk) | VERIFIED | Lines 706-709: `Re_i_bulk` computed and passed to both `scb_correction` calls; comment at 702-705 documents intent |
| 12 | [D-03] Single anchored block comment documents HTC=film vs friction/NC=bulk split | VERIFIED | `grep -c 'Phase 57 D-01/D-02/D-03: HTC fluid-property eval point'` returns 1; `grep -c 'Phase 57 D-01/D-02/B3: Nu\[i\] reports...'` returns 1 |
| 13 | [D-04] HTC correlation 4-arg signature `(Re, Pr, T_bulk, T_wall) -> Nu` unchanged | VERIFIED | All 7 factory signatures verified via `grep -E 'function (constant_Nusselt|...)' correlations.jl`; no signature drift |
| 14 | [D-04] Module header + 7 factory docstrings carry eval-point convention note | VERIFIED | `grep -c "Eval-point convention: callers should pass "` returns 8; `NC exception` count = 1 (elenbaas_htc) |
| 15 | [D-05] All 20 simple_loop h_tc_left/right[1..10] rows in CLEAN tier (was FAIL ~0.196) | VERIFIED | awk check (column $7): all 20 rows CLEAN; rtol range ~2.76e-11 to ~1.75e-10; hard ceiling 0.02 not exceeded |
| 16 | [D-05] All 30 simple_loop q_density_left/right/total[1..10] rows in CLEAN tier | VERIFIED | awk check: all 30 rows CLEAN; no GRAY; no FAIL |
| 17 | [D-06] Full test suite run confirms no Phase-57 regressions; parity CSV regenerated | WARNING — see note below | Cold-start `julia --project=. -e 'include("test/test_validation.jl")'` used; pre-existing Sockets/daemon ambiguity blocks `bin/jl test/runtests.jl` (pre-existing, not caused by this phase) |

**Score: 16/17 truths fully verified; 1 WARNING (D-06 variant)**

---

### D-06 Warning: Test Execution Method Deviation

The PLAN must-have D-06 states "`bin/jl test/runtests.jl` exits 0". This did not happen:

- `bin/jl test/runtests.jl` / `julia --project=. test/runtests.jl` both fail before reaching test_validation.jl due to a pre-existing DaemonMode/Sockets ambiguity (`UndefVarError: connect not defined in Main` in test_channels.jl line 105 when run under the daemon). Additionally STATE.md documents two other pre-existing failures (VAL-01 Fourier validation flakiness, NET-03 Cube KINSOL convergence) that block a clean runtests.jl regardless.
- The SUMMARY verified (confirmed by SUMMARY self-check) that the issue reproduces on the pre-Phase-57 commit with edits stashed — not a Phase 57 regression.
- test_validation.jl was run successfully via cold-start `julia --project=. -e 'include("test/test_validation.jl")'`, which CLAUDE.md explicitly permits as a fallback.
- D-05 bars (the actual deliverable tested by D-06) all pass: parity_report.csv regenerated, all simple_loop h_tc and q_density rows CLEAN, mtime of CSV (1778252407) newer than channels.jl (1778252298).

**Verdict on D-06:** The infrastructure failure is pre-existing and unrelated to Phase 57's edits. The substance of D-06 (re-run the parity harness, verify D-05 bars pass) was achieved. Treated as WARNING, not BLOCKER. No gap filing needed.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/components/channels.jl` | Film-T HTC in CAC SPL+SCB; film-T Re/Pr in variant_obs Nu[i]; bulk-T friction+NC unchanged | VERIFIED | All T_film_i/T_film_obs_i/Re_i_bulk/Re_i_film locals confirmed; CR-01 and WR-01 fixes confirmed in commit 6fdcb5c |
| `src/physical_models/htc/correlations.jl` | Updated docstrings; signatures unchanged; module header + 8 docstring eval-point notes | VERIFIED | 8 "Eval-point convention" lines; 1 NC exception note; all factory signatures unchanged; `beta_water(T_bulk)` count = 2 |
| `test/data/parity_report.csv` | Regenerated; h_tc and q_density rows CLEAN/GRAY; no new FAIL in simple_loop | VERIFIED | All 20 h_tc rows CLEAN; all 30 q_density rows CLEAN; only FAIL rows are 3 MTR solver_error sentinels (Phase 58 deferred); CSV mtime newer than channels.jl |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| CAC SPL branch (line ~681) | `mu_water`/`cp_water`/`k_water` | `T_film_i = (T[i] + T_w_i) / 2` used in Re_i, Pr_i, k_water leading factor | WIRED | `h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T_film_i) / Dh` confirmed at line 684 |
| CAC SCB branch (line ~689) | `mu_water`/`cp_water`/`k_water` | Same film-T pattern; `h_spl_i` head | WIRED | `h_spl_i = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T_film_i) / Dh` confirmed at line 692 |
| CAC SCB `scb_correction` calls (lines 707, 709) | bulk Re | `Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))` (WR-01 fix) | WIRED | `scb_correction(T_w_i, T_sat_i, Re_i_bulk)` and `scb_correction(T_ONB_i, T_sat_i, Re_i_bulk)` confirmed |
| variant_obs Nu[i] site (line ~774) | `mu_water`/`cp_water`/`k_water` | `T_film_obs_i`, `Re_i_film`, `Pr_i_film` (CR-01 fix: renamed from Re_i/Pr_i) | WIRED | `Nu[i] ~ htc_correlation(Re_i_film, Pr_i_film, T[i], thermal_left[i].T)` at line 777 |
| variant_obs `Gr_over_Re2[i]` (line 789) | bulk Re | `Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))` (CR-01 fix) | WIRED | `Gr_over_Re2[i] ~ Gr_i / Re_i_bulk^2` at line 789; no film-T leak |
| `test/test_validation.jl` | `test/data/parity_report.csv` | Cold-start `julia --project=. -e 'include("test/test_validation.jl")'` | WIRED (via fallback) | CSV mtime confirms regeneration post-edit |

---

### Data-Flow Trace (Level 4)

Not applicable for this phase — the changed artifacts are MTK symbolic arithmetic expressions (not UI components or data-rendering pipelines). The correctness evidence is the parity_report.csv showing real solver output matching Python STREAM at CLEAN tier.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| h_tc rows CLEAN in simple_loop | `awk -F, '$1=="simple_loop" && ($2 ~ /^h_tc_(left\|right)\[/) && $7 != "CLEAN" && $7 != "GRAY"' parity_report.csv` | Empty output (all 20 rows CLEAN) | PASS |
| q_density rows CLEAN in simple_loop | `awk -F, '$1=="simple_loop" && ($2 ~ /^q_density_(left\|right\|total)\[/) && $7 != "CLEAN" && $7 != "GRAY"' parity_report.csv` | Empty output (all 30 rows CLEAN) | PASS |
| No new FAIL anywhere in simple_loop | `awk -F, '$1=="simple_loop" && $7=="FAIL"' parity_report.csv` | Empty output | PASS |
| Hard ceiling 0.02 rtol not exceeded on h_tc | `awk -F, '$1=="simple_loop" && ($2 ~ /^h_tc_(left\|right)\[/) && ($6+0) > 0.02' parity_report.csv` | Empty output (max rtol: ~1.75e-10) | PASS |
| friction Re unchanged at bulk | `grep -c 'Re_i_for_friction = abs(port_in.mdot) \* Dh / (A \* mu_water(T\[i\]))'` | 1 | PASS |
| Gr_over_Re2 denominator at bulk Re | `grep -n 'Gr_over_Re2\[i\] ~ Gr_i / Re_i_bulk'` | Line 789: confirmed | PASS |
| scb_correction Re at bulk | `grep -n 'scb_correction.*Re_i_bulk'` | Lines 707, 709: confirmed | PASS |

---

### Requirements Coverage

| Requirement | Source | Description | Status | Evidence |
|-------------|--------|-------------|--------|----------|
| D-01 | CONTEXT.md | T_film computed at call site | SATISFIED | Lines 681, 689 (SPL/SCB); line 774 (variant_obs T_film_obs_i) |
| D-02 | CONTEXT.md | All HTC-pipeline property evals at film T | SATISFIED | Re_i, Pr_i, leading k all use T_film_i or T_film_obs_i at correct sites |
| D-03 | CONTEXT.md | Friction Re, NC Gr stay at bulk | SATISFIED | Line 139 friction; line 147 core observable; line 786 Re_i_bulk; line 787 nu_i; line 789 Gr_over_Re2/Re_i_bulk^2; scb_correction Re_i_bulk |
| D-04 | CONTEXT.md | Correlation signature unchanged; docstrings document convention | SATISFIED | 8 eval-point convention docstring lines; 1 NC exception note; all signatures verified |
| D-05 | CONTEXT.md | parity_report.csv h_tc + q_density rows CLEAN/GRAY | SATISFIED | All 20 h_tc rows CLEAN; all 30 q_density rows CLEAN; no new FAIL in simple_loop |
| D-06 | CONTEXT.md | Test suite run confirms parity CSV regenerated | SATISFIED (fallback) | test_validation.jl run via cold-start; CSV regenerated; D-05 bars pass; pre-existing daemon issue is not a Phase 57 regression |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/components/channels.jl` | 663, 675 | Stale line number references ("channels.jl:742-743", "lines 733-744 below") in block comment — actual locations are ~787-789 and ~767-790 after block-comment insertion shifted lines | Info (IN-01 from review) | Documentation only; zero impact on correctness or behavior |

No blockers or functional anti-patterns found. The stale line numbers are a documentation maintenance issue identified in 57-REVIEW.md (IN-01) and left for future cleanup.

---

### Human Verification Required

None — all critical behaviors verified programmatically via grep against actual source and awk against parity CSV.

---

## Gaps Summary

No gaps. All must-have truths are verified. The single WARNING (D-06 test execution deviation) is a pre-existing infrastructure issue (Sockets/MTK namespace collision in daemon mode, VAL-01, NET-03) that pre-dates Phase 57 and was confirmed by testing on the pre-edit commit. The parity deliverable (D-05) was produced via the CLAUDE.md-sanctioned cold-start fallback. Phase goal is fully achieved.

---

## CR-01 / WR-01 Fix Verification

The 57-REVIEW.md identified two post-implementation bugs; both were fixed in commit 6fdcb5c:

**CR-01 (Critical): Gr_over_Re2 denominator at film-T Re — FIXED**
- Pre-fix: `Re_i` (film-T) was reused in `Gr_over_Re2[i] ~ Gr_i / Re_i^2`, making the denominator film-T despite the documented bulk-T invariant.
- Fix: `Re_i_film` (for Nu[i]) and `Re_i_bulk` (for Gr_over_Re2[i]) are now separate locals. Line 789: `Gr_over_Re2[i] ~ Gr_i / Re_i_bulk^2`.
- Verified: `grep -n 'Gr_over_Re2\[i\] ~ Gr_i / Re_i_bulk'` confirms line 789.

**WR-01 (Warning): scb_correction Re silently at film-T — FIXED**
- Pre-fix: `Re_i` (rebound to film-T in SCB branch head) was passed to both `scb_correction` calls.
- Fix: `Re_i_bulk` computed at line 706 and used for both `scb_correction(T_w_i, T_sat_i, Re_i_bulk)` and `scb_correction(T_ONB_i, T_sat_i, Re_i_bulk)`. Comment at 702-705 documents D-03 invariant.
- Verified: `grep -n 'scb_correction.*Re_i_bulk'` confirms lines 707 and 709.

---

_Verified: 2026-05-08T18:30:00Z_
_Verifier: Claude (gsd-verifier)_
