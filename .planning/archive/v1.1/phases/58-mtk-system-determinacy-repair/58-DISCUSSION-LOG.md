# Phase 58: MTK System Determinacy Repair - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 58-mtk-system-determinacy-repair
**Areas discussed:** Scenario scope, Plan structure, fully_determined=false audit, Regression assertion + D-2 fold-in

---

## Gray-area selection

Of six pre-analyzed gray areas the user picked four to discuss; two were left to Claude's discretion (see end of log).

| Gray area | Selected for discussion |
|-----------|-------------------------|
| Scenario scope | ✓ |
| Plan structure | ✓ |
| `fully_determined=false` audit | ✓ |
| Regression assertion | ✓ (combined turn) |
| MTK API root-cause depth | — (Claude's discretion) |
| Fold in Phase 56 deferred-items D-2 | ✓ (combined turn) |

---

## Scenario scope

| Option | Description | Selected |
|--------|-------------|----------|
| MTR + all KEPT + VAL-02 transient | Full set in 56-PAUSE-CONTEXT.md: MTR (3) + HD Fourier VAL-01 + two-plate VAL-02 steady + PK validation + VAL-02 transient `T_wall` step. Closes the "Phase 58 should resolve" column. | ✓ |
| MTR + KEPT (steady only) | Drop VAL-02 transient (different error family `variable sys does not exist`). | |
| MTR only | Just the 3 MTR scenarios. Unblocks parity_report; leaves KEPT testsets failing. | |

**User's choice:** Full set. Rationale (per 56-PAUSE-CONTEXT.md verdict): closing v1.1 with documented broken testsets is incompatible with the user's directive against "papering over with looser tolerances or known gaps."

---

## Plan structure

| Option | Description | Selected |
|--------|-------------|----------|
| Diagnostic-first, then targeted fixes | Plan 58-01 = no-source-edit diagnostic (per-scenario eqs/unknowns/ICs introspection table on minimal repros). Plans 58-02..N = one fix plan per scenario family. | ✓ |
| One plan per scenario family | Skip dedicated diagnostic; each plan diagnoses + fixes its own scenario. | |
| One combined fix plan | All six scenarios fixed in one plan. | |

**User's choice:** Diagnostic-first.
**Notes:** Diagnostic table's column names are fixed in CONTEXT.md `<specifics>` so Plan 58-01 has zero ambiguity on the deliverable. Minimal repros live in scratch (`tmp/` or under `.planning/phases/58.../scratch/`), not `test/`.

---

## `fully_determined=false` audit

| Option | Description | Selected |
|--------|-------------|----------|
| Audit + convert; document survivors | Sweep src/ + test/ for every `fully_determined=false` and `check_length=false` site; classify legitimate-structural vs bug-hiding; convert bug-hiding to `true`, comment legitimate. | ✓ |
| Only fix the broken-six | Fix the 6 in-scope scenarios. Leave existing usages alone. | |
| Make `true` the default everywhere | Force `true`; rewrite tests that genuinely need `false` (e.g. RL circuit). | |

**User's choice:** Audit + convert + document survivors.
**Notes:** Audit is folded into Plan 58-01's diagnostic step — same grep pass as the eqs/unknowns introspection. Per-family fix plans flip `false → true` after their structural fix lands. `solve_steady` does NOT grow a `check_length` kwarg (D-05).

---

## Regression assertion + Phase 56 D-2 fold-in (combined turn)

### Regression assertion

| Option | Description | Selected |
|--------|-------------|----------|
| Per-builder + per-scenario | New `test/test_determinacy.jl`: assert `mtkcompile(sys; fully_determined=true)` succeeds AND `length(equations(ssys)) == length(unknowns(ssys))` for every builder in `examples.jl` AND each fixed Phase-58 scenario topology. | ✓ |
| Builders only | Cover only `examples.jl`; let `test_validation.jl` failures surface scenario regressions. | |
| No new regression test | Trust the existing test suite. | |

**User's choice:** Per-builder + per-scenario.
**Notes:** New file, added to `test/runtests.jl` orchestrator (CLAUDE.md "Test placement rule"). Scenario topologies that today live only inside `test_validation.jl` get lifted into small builder helpers inside `test_determinacy.jl`.

### Fold in Phase 56 deferred-items D-2

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Plan 56-06 resume | D-2 (geometry precision %.10e → %.17g + 3 rtol bumps) stays owned by Plan 56-06. The 1e-9 mitigation continues to pass. | ✓ |
| Fold into Phase 58 | Bump precision and re-tighten as part of Phase 58 since we're regenerating MTR reference data anyway. | |

**User's choice:** Defer.
**Notes:** Phase 58 stays strictly about MTK structural balance. D-2 is a precision-paste tweak unrelated to determinacy.

---

## Claude's Discretion

- **MTK API drift root-cause depth** — diagnostic plan reads ModelingToolkit / ModelingToolkitBase CHANGELOG entries near the version range in `Manifest.toml`; commit-by-commit bisect deferred unless the CHANGELOG read fails to produce a hypothesis.
- **MTR sym/asym/one-sided as one fix plan vs three** — decided by Plan 58-01's diagnostic. Same shape across all three; if missing equation is identical, one fix plan; else split.
- **Where scenario-builder helpers live** — default is inside `test/test_determinacy.jl`; planner may lift any reusable helper into `src/examples.jl`.
- **VAL-02 transient as its own plan vs folded into VAL-02 steady** — decided by Plan 58-01's diagnostic; depends on whether `variable sys does not exist` shares root cause with the structural-balance gap.

## Deferred Ideas

- Phase 56 deferred-items D-2 (geometry precision tweak) — owned by Plan 56-06 resume.
- Deep bisect of ModelingToolkitBase for the API drift commit — escalation path inside Plan 58-01 if needed; otherwise indefinitely deferred.
- A `solve_steady` wrapper that internally calls `mtkcompile(...; fully_determined=true)` — API coordination cost too high for v1.1.
- NET-03 Cube flow flakiness (Phase 55 D-22) — independent of MTK API drift.
