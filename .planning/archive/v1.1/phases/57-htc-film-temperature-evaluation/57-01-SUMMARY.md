---
phase: 57-htc-film-temperature-evaluation
plan: 01
subsystem: channels / heat-transfer-coefficient
tags: [htc, film-temperature, mtk, parity, channel-core]
requires: []
provides:
  - "Film-T HTC pipeline in ChannelAndContacts SPL + SCB branches"
  - "Film-T Re/Pr in CAC variant_obs Nu[i] observable"
  - "Module-header + per-factory docstring documentation of eval-point convention"
  - "Regenerated test/data/parity_report.csv showing Gap #2 closed (h_tc, q_density rows CLEAN)"
affects:
  - src/components/channels.jl
  - src/physical_models/htc/correlations.jl
  - test/data/parity_report.csv
tech-stack:
  added: []
  patterns:
    - "Property-eval-point shift at call site (T_film_i, T_film_obs_i locals; no new @register_symbolic)"
    - "Single anchored block comment documents the HTC=film vs friction/NC=bulk split"
key-files:
  created: []
  modified:
    - src/components/channels.jl
    - src/physical_models/htc/correlations.jl
    - test/data/parity_report.csv
decisions:
  - "[D-01] Film-T computed at call site as Symbolics local (T_film_i in SPL/SCB; T_film_obs_i in variant_obs Nu[i] observable)"
  - "[D-02] HTC pipeline (Re, Pr, leading k outside Nu) ALL evaluated at film T — full Python parity"
  - "[D-03] Friction Re, _channel_core Pe/Pr observable, and variant_obs NC nu_i/Gr_i intentionally remain at bulk T"
  - "[D-04] HTC correlation 4-arg signature unchanged; module header + 7 factory docstrings document the eval-point convention; elenbaas_htc carries the bulk-NC exception note"
  - "[D-05] Gap #2 closed — all simple_loop h_tc and q_density rows now CLEAN (rtol ~2.76e-11)"
metrics:
  duration: ~10m
  completed: 2026-05-08T14:42:59Z
  tasks: 3
  files_modified: 3
  commits: 3
---

# Phase 57 Plan 01: HTC Film-Temperature Evaluation Summary

Switched the Julia STREAM HTC pipeline so coolant fluid properties feeding `h = Nu(Re,Pr) · k / Dh` are evaluated at film temperature `T_film = (T_cool + T_wall)/2`, matching Python STREAM's `coolant_funcs.to_properties(T_film, pressure)` convention; friction Re and natural-convection Gr stay at bulk T per Python convention; closes Phase 56's Gap #2 (h_tc rows ~0.196 FAIL → ~2.76e-11 CLEAN).

## What Shipped

### Edit sites (post-edit line numbers in src/components/channels.jl)

| Site | Line | Local | Formula |
|------|------|-------|---------|
| CAC SPL branch (`scb_correction === nothing`) | 681 | `T_film_i` | `(T[i] + T_w_i) / 2` |
| CAC SCB branch (`scb_correction !== nothing`) | 689 | `T_film_i` | `(T[i] + T_w_i) / 2` |
| CAC variant_obs Nu[i] observable | 769 | `T_film_obs_i` | `(T[i] + thermal_left[i].T) / 2` |

The local-name distinction (`T_film_i` vs `T_film_obs_i`) is for diagnostic clarity at a glance — the SPL/SCB locals feed the equation system; the variant_obs local feeds the diagnostic Nu[i] observable so Nu[i] reports the same Re/Pr that h_tc[i] consumes (B3).

A single anchored block comment (channels.jl ~lines 651-678) documents WHY HTC switches to film while friction Re, the _channel_core Pe/Pr observable, and variant_obs NC nu_i/Gr_i all stay at bulk — citing Python STREAM `heat_transfer_coefficient/__init__.py:208-209`. A smaller note inside the variant_obs loop explains why `T_film_obs_i` exists as a separate local from `T_film_i`.

### Fluid-property eval-site audit (post-edit)

| Function | Site | Eval at film T | Eval at bulk T |
|----------|------|----------------|----------------|
| `mu_water` | SPL Re_i (line ~684) | film `T_film_i` | — |
| `cp_water` | SPL Pr_i (line ~685) | film `T_film_i` | — |
| `mu_water` | SPL Pr_i (line ~685) | film `T_film_i` | — |
| `k_water` | SPL Pr_i (line ~685) | film `T_film_i` | — |
| `k_water` | SPL leading k (line ~686) | film `T_film_i` | — |
| `mu_water` | SCB Re_i (line ~692) | film `T_film_i` | — |
| `cp_water` | SCB Pr_i (line ~693) | film `T_film_i` | — |
| `mu_water` | SCB Pr_i (line ~693) | film `T_film_i` | — |
| `k_water` | SCB Pr_i (line ~693) | film `T_film_i` | — |
| `k_water` | SCB leading k (line ~694) | film `T_film_i` | — |
| `mu_water` | variant_obs Re_i (line ~770) | film `T_film_obs_i` | — |
| `cp_water` | variant_obs Pr_i (line ~771) | film `T_film_obs_i` | — |
| `mu_water` | variant_obs Pr_i (line ~771) | film `T_film_obs_i` | — |
| `k_water` | variant_obs Pr_i (line ~771) | film `T_film_obs_i` | — |
| `mu_water` | _channel_core Re_i_for_friction (line 139) | — | bulk `T[i]` |
| `cp_water` | _channel_core Pr_i observable (line 147) | — | bulk `T[i]` |
| `mu_water` | _channel_core Pr_i observable (line 147) | — | bulk `T[i]` |
| `k_water` | _channel_core Pr_i observable (line 147) | — | bulk `T[i]` |
| `cp_water` | _channel_core energy balance face cp (lines 123) | — | bulk (face avg) |
| `cp_water` | _channel_core energy balance denominator (line 134) | — | bulk `T[i]` |
| `mu_water` | variant_obs nu_i for Gr_over_Re2 (line ~778) | — | bulk `T[i]` |
| `rho_water` | variant_obs nu_i for Gr_over_Re2 (line ~778) | — | bulk `T[i]` |
| `beta_water` | variant_obs Gr (line ~779) | — | bulk `T[i]` |

**Whole-file token totals (post-edit, matches Task 1 audit):**
- `mu_water(T[i])`: 3 lines (139, 147, ~778)
- `cp_water(T[i])`: 7 lines (73 / 75 / 79 docstring; 123 / 126 comment / 134 energy balance; 147 core observable)
- `k_water(T[i])`: 1 line (147 core observable)

The HTC correlation 4-arg signature `(Re, Pr, T_bulk, T_wall) -> Nu` is unchanged. The 3rd arg ("T_bulk slot") still receives bulk `T[i]` in all three call sites — kept for the rare correlation that needs bulk T internally (`elenbaas_htc`'s NC `beta_water`, `mu_water`, `rho_water` evaluations).

### Documentation (src/physical_models/htc/correlations.jl)

- **Module header bullet (Phase 57 D-04):** "callers should pass `Re` and `Pr` evaluated at the FILM temperature `T_film = (T_bulk + T_wall)/2` ..."
- **Per-factory docstrings (8 sites: dittus_boelter, constant_Nusselt, regime_dependent, elenbaas_htc, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc, Marco_Han_Nusselt):** the same one-line eval-point convention note.
- **`elenbaas_htc` exception line:** "this closure evaluates `beta_water`, `mu_water`, `rho_water` INTERNALLY at `T_bulk` (NOT at film) — natural-convection driving force is a bulk-vs-wall ΔT phenomenon and Python STREAM evaluates β, ν at bulk for Gr."

Zero function bodies / signatures changed; zero new exports.

## D-05 Success Bar (regenerated test/data/parity_report.csv)

| Quantity | Pre-Phase-57 (Phase 56 baseline) | Post-Phase-57 |
|----------|----------------------------------|----------------|
| `simple_loop h_tc_left[5]` rtol | ~0.196 (FAIL) | **2.76e-11 (CLEAN)** |
| `simple_loop h_tc_right[5]` rtol | ~0.196 (FAIL) | **2.76e-11 (CLEAN)** |
| `simple_loop h_tc_*[1..10]` tier distribution | 20× FAIL | **20× CLEAN** |
| `simple_loop q_density_*[1..10]` tier distribution | 30× FAIL (downstream of h_tc) | **30× CLEAN** |
| New FAIL rows anywhere in `simple_loop` | (none expected; none observed) | **none** |
| Phase 56 D-04 hard ceiling 0.02 rtol exceeded on any non-MTR row | (none observed) | **none** |

Representative h_tc_left[5] row (post-Phase-57):
```
simple_loop,h_tc_left[5],3.8268067713e+04,3.8268067714e+04,1.0569056030e-06,2.761847e-11,CLEAN,0.0200,Gap #2 candidate (HTC film-T vs bulk-T)
```

The "Gap #2 candidate" annotation now matches a CLEAN row — the gap is closed. The annotation is left in the CSV note column as a historical breadcrumb (parity_report.csv is regenerated mechanically; rewriting the note column would require source-code changes in test_validation.jl, out of scope).

MTR scenario rows (`mtr_symmetric`, `mtr_asymmetric`, `mtr_one_sided`) continue to emit `solver_error` sentinels — handed off to Phase 58 (MTK determinacy repair) as planned.

## Working branch

`channels-redesign` — unchanged throughout the plan. No git branch operations performed (CLAUDE.md branching policy honored).

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 | `7aa1f08` | feat(57-01): switch ChannelAndContacts HTC pipeline to film T |
| 2 | `7779726` | docs(57-01): document film-T eval-point convention in HTC correlations |
| 3 | `2cf8a02` | test(57-01): regenerate parity_report.csv — h_tc gap closed |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Test orchestrator did not reach test_validation.jl via daemon**

- **Found during:** Task 3 (`bin/jl test/runtests.jl`)
- **Issue:** The Julia daemon environment (DaemonMode.jl loads `Sockets` to run the TCP listener) creates an ambiguous `connect` symbol in `Main` shared between `Sockets`, `ModelingToolkit`, and `ModelingToolkitBase`. `test_channels.jl` line 105 calls `connect(...)` (MTK acausal port connection) and errors out with `UndefVarError: connect not defined in Main` — `runtests.jl` halts before reaching `test_validation.jl`. Verified the issue is **pre-existing** by stashing the Phase 57 edits and re-running: same error appears on the pre-edit commit. Not caused by this phase's expression edits.
- **Fix:** Fell back to cold-start `julia --project=. -e 'include("test/test_validation.jl")'` (CLAUDE.md explicitly allows this as the fallback — "Plain julia ... fallback when daemon isn't desired"). Cold-start julia does not load `Sockets` into `Main`, so the ambiguity does not arise. test_validation.jl ran cleanly and regenerated parity_report.csv. Daemon was restarted before the attempt to confirm the issue is environmental, not stale-state.
- **Files modified:** none (workflow change only — test_validation.jl was the actual deliverable target).
- **Why this is not a regression:** STATE.md already documents two pre-existing test failures (VAL-01 Fourier validation flakiness and NET-03 Cube KINSOL convergence) that block a clean `runtests.jl`. The daemon `connect` ambiguity is a third pre-existing infrastructure issue surfaced by this plan but not caused by it. The Phase 57 success bar (D-05) is checked against parity_report.csv, which was regenerated successfully.

**2. [Rule 1 - Bug, in plan acceptance criteria] Wrong tier column index in plan's awk commands**

- **Found during:** Task 3 verification.
- **Issue:** Plan 57-01 acceptance criteria use `$6` for the tier check (e.g., `$6 != "CLEAN" && $6 != "GRAY"`). The actual CSV header is `scenario,quantity,julia,python,abs_err,rtol,tier,hard_ceiling,note` — tier is column **7** (`$7`), and column 6 is `rtol` (a numeric value, never equal to "CLEAN"/"GRAY", so the awk would output **every** row regardless of tier).
- **Fix:** Used `$7` for tier checks during verification (matched the actual CSV layout). The intent of the acceptance criteria — "no h_tc/q_density row outside CLEAN/GRAY; no FAIL anywhere in simple_loop" — was honored correctly.
- **Files modified:** none (verification command only).
- **Status:** Documented here so future plan authors see the column drift; consider updating the plan's awk commands if the plan template is reused.

### Auth gates

None — pure code change with local file IO only.

### Architectural changes

None — Rules 1-3 only.

## Self-Check: PASSED

- [x] `src/components/channels.jl` modified, T_film_i count = 2, T_film_obs_i count = 1.
- [x] `src/physical_models/htc/correlations.jl` modified, "Eval-point convention: callers should pass " count = 8, "NC exception" count = 1.
- [x] `test/data/parity_report.csv` regenerated (mtime newer than channels.jl).
- [x] All 20 `simple_loop h_tc_*[i]` rows in tier CLEAN.
- [x] All 30 `simple_loop q_density_*[i]` rows in tier CLEAN.
- [x] Zero FAIL rows in `simple_loop` scenario.
- [x] Working branch `channels-redesign` unchanged.
- [x] Commits `7aa1f08`, `7779726`, `2cf8a02` all on `channels-redesign`, verified via `git log --oneline`.
- [x] Working tree shows only the 3 expected paths modified (plus .planning/ docs to follow).
