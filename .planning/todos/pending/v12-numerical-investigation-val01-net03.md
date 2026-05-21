---
created: 2026-05-21
title: v1.2 numerical-investigation backlog — VAL-01 Fourier + NET-03 KINSol flakies
area: numerics
resolves_phase: future-numerical-phase
files:
  - test/test_integration.jl
  - test/test_resistors.jl
  - src/solvers.jl (possibly)
---

## Source

Carried forward from v1.1 STATE.md "Blockers/Concerns" during the 2026-05-21 deferred-work audit. v1.1 milestone shipped without these — Plan 56-06 close-up annotated them with `@test_skip` and routed the deeper investigation to a future v1.2 numerical phase. Removing them from STATE.md to clear the v1.1-era backlog, but preserving the work here so they don't fall through the cracks.

## Items

### VAL-01 — Fourier-series validation `solve` InitialFailure

**Symptom:** `test/test_validation.jl` VAL-01 testset — `solve_steady` on the HD Fourier benchmark returns `ReturnCode.InitialFailure`.

**Status in code:** `test/test_integration.jl` has `@test_skip false` markers; the validation is wired but the numerical convergence is unresolved.

**What Phase 58 did/didn't do:** Phase 58 fixed *structural* MTK determinacy (equations == unknowns). Numerical convergence on this specific scenario is independent and was explicitly declared out-of-scope per `58-CONTEXT.md`.

**Hypotheses to explore in a future phase:**
- IC quality — VAL-01 may need a better warm-start than the current `steady_state_guess`.
- Solver choice — KINSol vs Newton-Raphson trade-off for this scenario shape.
- May connect to NET-03 (below) — both look like KINSol stiffness/convergence issues.

### NET-03 — Cube flow KINSol flag −11

**Symptom:** `test/test_resistors.jl` NET-03 testset (Cube flow distribution matches analytical 5/6 R equivalent resistance) — KINSol returns flag −11 (line-search failure / KINSOL_LINESEARCH_NONCONV).

**Status in code:** `@test_skip` markers in place; the orchestrator no longer halts on it.

**Pre-existing baseline:** Documented as flaky since Phase 55 D-22. Survived three milestones (v1.1, v1.2 GUI-redesign progress so far) without resolution because the test-skip workaround is acceptable.

**Hypotheses:** Could be a degenerate Jacobian at the symmetric solution, line-search step too aggressive, or numerically ill-conditioned R matrix. Needs a focused KINSol-tuning investigation OR a switch to a more robust solver for this scenario.

## When to do this

A dedicated v1.2 numerical-investigation phase, OR roll into v1.3+. Not a priority while the GUI redesign milestone is active; the `@test_skip` markers are sufficient to keep CI honest.

## Files involved

- `test/test_integration.jl:302, 323, 352, 438` — `@test_skip` markers
- `test/test_resistors.jl:31-35` — NET-03 testset
- `test/test_validation.jl` — VAL-01 testset (commented/skipped path)
- `src/solvers.jl` — `solve_steady` entry point (where KINSol is invoked)

## Cross-references

- `.planning/archive/v1.1/phases/56-python-stream-cross-validation/56-PAUSE-CONTEXT.md` — original baselines table
- `.planning/archive/v1.1/phases/56-python-stream-cross-validation/56-06-SUMMARY.md` — final close-up decisions
- `.planning/v1.1-MILESTONE-AUDIT.md` — `status: tech_debt` with 22/22 requirements complete; these flakies are the residual tech debt
