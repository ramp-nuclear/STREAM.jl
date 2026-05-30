# Phase 59: Correlation `geom`-first refactor - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-11
**Phase:** 59-correlation-geom-first-refactor
**Areas discussed:** Breaking-change strategy, regime_dependent_q_scb scope, elenbaas_htc on non-rectangular geom, Phase 61 handoff artifact + test split, develop_length default

---

## Breaking-change strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Clean break, no shim | Rename/remove old kwargs in one commit. Update `src/examples.jl` + `test/test_correlations.jl` in the same phase. Document in CHANGELOG that v1.2 broke the correlation factory API. Simplest; no dead code to maintain. | ✓ |
| Clean break + named alias period | Old factory names removed, but keep old kwarg names accepted via `@deprecate` for one milestone. Allows Phase 61 GUI and external scripts a grace window. Adds ~10 lines of deprecation glue. | |
| Parallel rollout | Introduce new factories with new names (e.g. `laminar_friction_g`, `elenbaas_htc_g`), keep old, flip incrementally, then remove old in v1.3. Heavy — doubles surface area mid-milestone. | |

**User's choice:** Clean break, no shim.
**Notes:** v1.2 is the API-break boundary; STREAM.jl is pre-1.0 in the Julia ecosystem sense, no external consumers to protect.

---

## regime_dependent_q_scb scope

| Option | Description | Selected |
|--------|-------------|----------|
| Out of scope — leave as-is | Already satisfies the invariant (no `Dh`/`L`/`depth`/`width` kwargs). Phase 59 = "every factory that needs ANY geom value takes geom first". SCB needs no geom values. Touching it would be churn. | ✓ |
| In scope — add geom positional for uniformity | Make `geom` the first positional even though no field is read today, so every factory in `physical_models/` has the same call shape. Slightly easier GUI introspection. Adds an unused arg. | |
| In scope only if it reads geom in future | Note in CONTEXT.md that if a future correction needs `Dh`, add geom then. No code change in Phase 59. | |

**User's choice:** Out of scope — leave as-is.
**Notes:** Strict reading of the §3.1 invariant: factories that don't read geom fields are untouched.

---

## elenbaas_htc on non-rectangular geom

| Option | Description | Selected |
|--------|-------------|----------|
| Document, no runtime check | Docstring says "parallel-plates correlation; pass a rectangular `PipeGeometry` where `geom.depth` is the plate gap." Trust the user; `PipeGeometry` has no `kind` field, so any check is heuristic and a `depth==width` test would false-positive on square rectangular channels. | ✓ |
| `@assert depth < width`, error message | Reject any geom where `depth == width` with a clear error. Catches circular at construction. Also rejects square-cross-section channels. | |
| `@warn` on `depth == width`, proceed | Warn at construction but still build the closure. User gets a one-line warning at model build time. | |

**User's choice:** Document, no runtime check.
**Notes:** Consistent with rest-of-library trust-the-user posture.

---

## Phase 61 handoff artifact

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — `.planning/notes/correlation-geom-first-api.md` | Short doc (~50 lines): table of factories with (a) signature after refactor, (b) which geom fields are read internally, (c) which kwargs remain. Phase 61 reads this directly. Survives as v1.2 design ref. | ✓ |
| No — source-of-truth is the code | Docstrings on each factory document signature + geom-field usage. Phase 61 reads `correlations.jl` + design-decisions §3.1 directly. No extra doc to maintain in sync. | |
| Yes, but inline in design-decisions §3.1 | Append the final signature table to existing `gui-redesign-design-decisions.md` §3.1 instead of a new file. Keeps all v1.2 design in one doc. | |

**User's choice:** Yes — `.planning/notes/correlation-geom-first-api.md`.
**Notes:** Phase 61 (registry rewrite) consumes this directly.

---

## Test file split

| Option | Description | Selected |
|--------|-------------|----------|
| Keep one file | `test/test_correlations.jl` stays as-is, just port signatures. The src side was already split into `htc/` and `friction/` subfolders without splitting the test file, so the precedent is set. | ✓ |
| Split into `test_htc_correlations.jl` + `test_friction_correlations.jl` | Mirror `src/physical_models/{htc,friction}/correlations.jl`. Brings the test layout in line with CLAUDE.md mirror rule. ~80 lines per file after refactor. | |

**User's choice:** Keep one file.
**Notes:** Phase 59 scope is signature-porting, not test layout reorganization.

---

## develop_length default

| Option | Description | Selected |
|--------|-------------|----------|
| Stay mandatory, no default | Caller must pass `develop_length`. Matches today's behavior. Forces conscious choice; no surprise `= geom.L` substitution. GUI registry encodes `develop_length` as a required field. | ✓ |
| Default to `geom.L` | `develop_length=geom.L` means "developing over the full channel length". Removes a required field from GUI. Subtle: `x_star` formula then evaluates at channel exit, which may not be what every user wants. | |
| Default to `nothing`, error if not provided | Stays effectively mandatory but with a clearer error than `UndefKeywordError`. Cosmetic difference. | |

**User's choice:** Stay mandatory, no default.
**Notes:** Matches today's call-site behavior, so no test churn beyond the signature change.

---

## Claude's Discretion

- Internal helper preservation (`rectangular_laminar_correction`, `_two_sided_heating_nusselt`, `_nusselt_coefficient_developing`, `_bergles_rohsenow_dT_ONB`) — keep current signatures.
- Error message tightening around `regime_dependent`'s NC group validation — allowed if it improves clarity, not required.
- Docstring "Eval-point convention" boilerplate consolidation — cosmetic, planner/executor choice.

## Deferred Ideas

- `regime_dependent_q_scb` geom-first treatment (D-02).
- Test file split into htc + friction (D-06).
- Deprecation shims (D-01).
- Runtime geometry-kind enforcement (D-03).
