---
phase: 58-mtk-system-determinacy-repair
plan: 01
subsystem: mtk
status: complete
tags: [mtk, determinacy, diagnostic, regression-scaffold]
dependency_graph:
  requires:
    - .planning/phases/58-mtk-system-determinacy-repair/58-CONTEXT.md
    - .planning/phases/58-mtk-system-determinacy-repair/58-RESEARCH.md
    - .planning/phases/58-mtk-system-determinacy-repair/58-VALIDATION.md
  provides:
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/audit_table.md
    - test/test_determinacy.jl
  affects:
    - test/runtests.jl
tech_stack:
  added: []
  patterns:
    - "assert_determined_compiled / assert_determined helper split for compiled vs uncompiled systems"
key_files:
  created:
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val01_fourier.jl
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate.jl
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_transient.jl
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md
    - .planning/phases/58-mtk-system-determinacy-repair/scratch/audit_table.md
    - test/test_determinacy.jl
  modified:
    - test/runtests.jl
decisions:
  - "Keep _build_* scenario helpers private inside test_determinacy.jl (RESEARCH OQ-3)"
  - "MTR sym/asym/one-sided collapse to one fix plan 58-02 (RESEARCH OQ-1)"
  - "VAL-02 transient folds into Plan 58-04 alongside VAL-02 steady (RESEARCH OQ-2)"
  - "Each fix plan flips its own audit sites (RESEARCH OQ-4)"
  - "No length(initialization_equations) assertion in regression (RESEARCH OQ-5)"
  - "Split helper into two: assert_determined for uncompiled, assert_determined_compiled for canonical builders (Rule 1 deviation during execution — see Deviations)"
metrics:
  completed: 2026-05-08
---

# Phase 58 Plan 01: Diagnostic + Audit + Wave 0 Scaffold Summary

Per-scenario diagnostic table for all seven Phase-58 in-scope scenarios; classification of all 38 `fully_determined=false` / `check_length=false` sites with downstream-plan ownership; new `test/test_determinacy.jl` regression scaffold with canonical-builders testset GREEN and Phase-58 scenarios testset RED-as-expected; MTK API drift verified directly from installed source (no CHANGELOG ships).

## What was built

- **Three new diagnostic scratch scripts** (D/E/F): `diag_val01_fourier.jl`, `diag_val02_twoplate.jl`, `diag_val02_transient.jl`. All include `using ModelingToolkit: connect` to mitigate the `Sockets.connect` shadowing (RESEARCH §R-1).
- **Per-scenario diagnostic table** (`scratch/diag_table.md`) with the locked column names and verbatim outputs from all five scratch scripts.
- **Audit table** (`scratch/audit_table.md`) covering all 38 `fully_determined=false` / `check_length=false` sites in `src/` and `test/`, each routed to a specific verdict (`legitimate-structural`, `isolated-component-test`, `bug-hiding`, `doc-only`) and Disposition (specific downstream plan owner for `bug-hiding` sites).
- **Determinacy regression scaffold** (`test/test_determinacy.jl`) with two testsets:
  1. Canonical builders — `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`, `build_loop_pk` (6 sub-tests, all GREEN at plan-end).
  2. Phase-58 scenarios — `_build_mtr_sym`, `_build_mtr_asym`, `_build_mtr_onesided`, `_build_val01_fourier`, `_build_val02_twoplate` (5 sub-tests, RED-as-expected; helpers deliberately omit the `hd.power ~ value` pin until the per-scenario fix plans land).
- **Orchestrator wiring**: `test/runtests.jl` now `include("test_determinacy.jl")` after `test_heat_diffusion.jl` (line 23).

No edits to any file under `src/`. No edits to `test/test_validation.jl` (those land in Plans 58-02..04). No new branches.

## Diagnostic table

> Locked column names per CONTEXT.md `<specifics>`:
> `(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)`
> All counts measured live this session against MTK 11.25.0 / MTKBase 1.34.0 / SciMLBase 2.155.1.

| scenario | n_eqs | n_unknowns | n_init_eqs | missing_kind | hypothesis | fix_sketch |
| -------- | ----- | ---------- | ---------- | ------------ | ---------- | ---------- |
| MTR symmetric (test_validation.jl:333) | 92 | 93 | 0 | unknowns_pin | `hd.power(t)` declared as `@variables` in `HeatDiffusion` (heat_diffusion.jl:145) but no equation closes it | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:374 |
| MTR asymmetric (test_validation.jl:504) | 92 | 93 | 0 | unknowns_pin | identical to MTR sym (single HD, two CAC, asymmetric inlet T) | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:544 |
| MTR one-sided (test_validation.jl:668) | 61 | 62 | 0 | unknowns_pin | identical to MTR sym (single HD, single CAC) | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:706 |
| VAL-01 HD Fourier (test_validation.jl:842) | 50 | 51 | 0 | unknowns_pin | identical pattern; HD-only with `power=0.0`; no closing eq | Add `hd_v01.power ~ 0.0` to `conns_v01` at test_validation.jl:898 |
| VAL-02 two-plate (test_validation.jl:935) | 91 | 93 | 0 | unknowns_pin (×2) | TWO HD instances → two missing pins (Δ=-2) | Add `hd1.power ~ power_per_plate` AND `hd2.power ~ power_per_plate` at test_validation.jl:991 |
| VAL-02 transient T_wall step (test_validation.jl:295) | 11 | 11 | 0 | symbol_access (NOT determinacy) | `ssys.sys.T_wall_callable` raises `ArgumentError: System sys: variable sys does not exist`; correct path is `ssys.T_wall_callable` (verified live) | Replace `ssys.sys.T_wall_callable` → `ssys.T_wall_callable` at test_validation.jl:317 |
| PointKinetics validation (test_validation.jl:1042) | 43 | 43 | 0 | NO_GAP | Δ=0 already (`build_loop_pk` has `power_eqs = [rods_fuel.power ~ pk.P * power_scale]` at examples.jl:651). KINSOL retcode=Failure / flag −7 is **numerical** non-convergence; transient fallback in test code (:1059, :1118, :1167) covers it. Out of Phase 58 scope. | No fix; verify VAL-PK-01..03 pass after upstream try/catch wrapper at :834 stops tripping |

The full set of verbatim live outputs is preserved in `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md`.

## Audit table

The audit (`scratch/audit_table.md`) covers all 38 sites returned by `grep -rn "fully_determined\|check_length" src/ test/`. Summary by verdict:

- **Bug-hiding (7 sites):** all in `test/test_validation.jl` (lines 204, 379, 549, 709, 903, 996) and `test/test_heat_diffusion.jl:185`. Each gets flipped to `fully_determined=true` *after* its corresponding determinacy fix lands.
- **Legitimate-structural / isolated-component-test (~26 sites):** preserved with inline comments naming the structural reason. Most are isolated component compiles (Pump/Resistor/Inertia/HeatExchanger/HD/CAC/CHF/Channel/Flapper/WallTemperature/HeatFluxSource alone) where the unit-test pattern is "compile this component in isolation; verify shape, not solvability".
- **Doc-only (5 sites):** `src/components/channels.jl:207, 409` (comments), `src/components/flapper.jl:38` (docstring), `test/test_pump.jl:17` (comment), `test/test_channels.jl:16, 67` (comments). Only `src/components/flapper.jl:38` warrants a small docstring tightening (Plan 58-05).

The full table with per-site verdicts and Dispositions is at `.planning/phases/58-mtk-system-determinacy-repair/scratch/audit_table.md`.

## MTK CHANGELOG read

No CHANGELOG file ships with the installed packages — `find ~/.julia/packages/ModelingToolkit* -name CHANGELOG*` returns nothing. The API drift was therefore verified directly from installed source: `~/.julia/packages/ModelingToolkitBase/.../src/systems/abstractsystem.jl` (location of `check_eqs_u0`, the strict-by-default length check that throws `ArgumentError: Equations (N), unknowns (N+1), and initial conditions (N+1) are of different lengths`) and `.../systems/systems.jl` (the `fully_determined` semantics in `mtkcompile` — `false` only suppresses the compile-time check; downstream `process_SciMLProblem.check_eqs_u0` always runs strict). Installed package versions: MTK **11.25.0**, MTKBase **1.34.0**, SciMLBase **2.155.1**. Per CONTEXT.md "Claude's Discretion: MTK API drift root-cause depth", this satisfies the obligation without a commit-by-commit bisect — the fix shape is already determined by the diagnostic table.

## Wave 0 RED-state proof

`julia --project=. test/test_determinacy.jl` output (excerpt) at plan-end of 58-01:

```
Test Summary:                                        | Pass  Total   Time
Determinacy: canonical builders are fully determined |    6      6  57.6s
  build_loop                                         |    1      1
  build_loop_vertical                                |    1      1
  build_loop_transient                               |    1      1
  build_cube                                         |    1      1
  build_loop_lof_bypass                              |    1      1
  build_loop_pk                                      |    1      1

Test Summary:                   | Error  Total  Time
Determinacy: Phase 58 scenarios |     5      5   4.5s
  MTR symmetric                 |     1      1   2.9s   # → Plan 58-02 fixes
  MTR asymmetric                |     1      1   0.5s   # → Plan 58-02 fixes
  MTR one-sided                 |     1      1   0.3s   # → Plan 58-02 fixes
  VAL-01 Fourier                |     1      1   0.4s   # → Plan 58-03 fixes
  VAL-02 twoplate               |     1      1   0.4s   # → Plan 58-04 fixes
```

Each Phase-58 scenario row throws `ExtraVariablesSystemException` from `assert_determined`'s call to `mtkcompile(sys; fully_determined=true)`. The exception class is the RED-state contract; flipping a row to GREEN is the per-task gate Plans 58-02..04 use.

## Per-plan ownership matrix

| Plan | Scenarios fixed | test_validation.jl edits | test_determinacy.jl edits | Audit flips |
|------|-----------------|---------------------------|----------------------------|-------------|
| 58-02 | MTR sym/asym/onesided | add `hd.power ~ 1e4` at :374, :544, :706 | add `hd.power ~ 1e4` to `_build_mtr_sym`, `_build_mtr_asym`, `_build_mtr_onesided` | flip :379, :549, :709 to `fully_determined=true` |
| 58-03 | VAL-01 Fourier | add `hd_v01.power ~ 0.0` at :898 | add `hd_v01.power ~ 0.0` to `_build_val01_fourier` | flip :903 |
| 58-04 | VAL-02 steady + transient | add two pins at :991; replace string at :317 (`ssys.sys.T_wall_callable` → `ssys.T_wall_callable`) | add two pins to `_build_val02_twoplate` | flip :996, flip :204 |
| 58-05 | (audit-only + PK verify) | (none) | (none) | flip `test_heat_diffusion.jl:185` to `fully_determined=true`; tighten `flapper.jl:38` docstring; add inline comments to legitimate-structural sites |

## Open questions for downstream plans

All five RESEARCH §9 open questions are resolved and embedded above:

- **OQ-1** — MTR sym/asym/one-sided collapse to **one** fix plan (58-02). Identical mechanical fix; consolidated diff.
- **OQ-2** — VAL-02 transient folds into VAL-02 steady (Plan 58-04). Both edits in `test/test_validation.jl`, blast radius small.
- **OQ-3** — `_build_*` helpers stay private inside `test/test_determinacy.jl`. No public API surface widening.
- **OQ-4** — Each fix plan flips its own audit sites in the same diff (e.g., 58-02 fixes MTR sym/asym/one-sided AND flips lines 379, 549, 709).
- **OQ-5** — `length(initialization_equations(ssys))` assertion **NOT** added to regression. The two-check contract (length-equality + `fully_determined=true`) catches every measured case; adding the third-length check would couple to MTK-internal init-eqs semantics.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `assert_determined` fails on already-compiled canonical builders**

- **Found during:** Task 3 (running `test/test_determinacy.jl`)
- **Issue:** The plan said "Each helper returns the UNCOMPILED `sys` (NOT `ssys`) so `assert_determined` can run `mtkcompile(...; fully_determined=true)` itself." This is true for the Phase-58 `_build_*` helpers, but **all canonical `build_*` functions in `src/examples.jl` return already-compiled `ssys`** (each calls `mtkcompile(sys)` internally; cf. `src/examples.jl:84, 181, 265, 363, 514, 668`). Calling `mtkcompile(...; fully_determined=true)` on a compiled system raises `ArgumentError: Structural simplification cannot be applied to a completed system. Double simplification is not allowed.` so 5/6 canonical-builder rows were ERRORing instead of passing.
- **Fix:** Introduced a second helper, `assert_determined_compiled(label, ssys)`, that checks the length-equality contract directly (`@test length(equations(ssys)) == length(unknowns(ssys))`) without re-compiling. Updated the canonical-builders testset to call it. Phase-58 scenario testset still uses `assert_determined` (which calls `mtkcompile(...; fully_determined=true)` since the helpers return uncompiled `sys`). Justified inline in the helper docstring: if Δ ≠ 0 in a canonical builder, the internal `mtkcompile` either threw or returned an imbalanced system — both regressions are caught by the length-equality check at the entry to the test.
- **Files modified:** `test/test_determinacy.jl`
- **Commit:** included in `a7057ba`

### Auth gates

None.

## Next actions

Plans 58-02..05 may now proceed in sequence. Each plan's per-task gate is `julia --project=. test/test_determinacy.jl` (~30 s warm via the daemon for non-worktree usage; ~60 s cold for worktree-isolated executors): when the relevant Phase-58 scenario row goes from RED to GREEN, the fix is in. The audit table routes each `bug-hiding` `fully_determined=false` site to its owning plan; flipping is part of the same diff as the fix.

## Lessons learned

The under-determinacy gap was a latent bug across the MTK upgrade — the test suite passed before the upgrade because downstream `process_SciMLProblem.check_eqs_u0` did not enforce strict length-equality. When the strict default landed in MTKBase, the gap surfaced as a runtime `ArgumentError` at problem-construction time, several layers below `mtkcompile`. Lesson: **rely on `fully_determined=true` not `=false` as the structural-correctness contract.** `fully_determined=false` masks gaps that downstream code will reject. The new `test/test_determinacy.jl` regression scaffold codifies this lesson — every canonical builder and every Phase-58 scenario must satisfy `mtkcompile(sys; fully_determined=true)` (or, for already-compiled systems, length-equality on the compiled output) on every test run.

## Self-Check: PASSED

- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_table.md` — FOUND
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/audit_table.md` — FOUND
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val01_fourier.jl` — FOUND
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_twoplate.jl` — FOUND
- `.planning/phases/58-mtk-system-determinacy-repair/scratch/diag_val02_transient.jl` — FOUND
- `test/test_determinacy.jl` — FOUND
- `test/runtests.jl` includes `test_determinacy.jl` after `test_heat_diffusion.jl` — VERIFIED
- Commit `858deb6` (Task 1 — diag scripts + diag_table.md) — FOUND
- Commit `312626c` (Task 2 — audit_table.md) — FOUND
- Commit `a7057ba` (Task 3 — test_determinacy.jl + runtests.jl) — FOUND
- Canonical-builders testset GREEN (Pass 6/6) — VERIFIED via `julia --project=. test/test_determinacy.jl`
- Phase-58 scenarios testset RED-as-expected (5 errors) — VERIFIED
