---
phase: 59-correlation-geom-first-refactor
plan: 04
subsystem: correlations
tags: [docs, handoff, geom-first, gui-redesign, phase-61, correlation, api-surface]

# Dependency graph
requires:
  - plan: 59-01
    provides: laminar_friction(geom) clean break + HTCCorrelation type alias
  - plan: 59-02
    provides: elenbaas_htc(geom; g), fully_developed_laminar_h_spl(geom), developing_laminar_h_spl(geom; develop_length), regime_dependent(geom; ...) clean breaks
  - plan: 59-03
    provides: Repo-wide call-site sweep complete; Python parity gate confirmed zero semantic drift (424 CLEAN / 78 GRAY / 34 FAIL baseline preserved)
provides:
  - .planning/notes/correlation-geom-first-api.md — Phase 61 canonical handoff doc per D-05
affects:
  - 61 (GUI registry rewrite — consumes the new API surface from this doc instead of re-deriving from source)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phase-handoff via .planning/notes/ artifact (D-05): when a refactor's API surface needs to be communicated to a downstream phase, emit a self-contained doc alongside the design-decisions doc; downstream phase reads only this doc + in-source docstrings."

key-files:
  created:
    - .planning/notes/correlation-geom-first-api.md
  modified: []

key-decisions:
  - "Doc structure follows the §3.1 / CONTEXT.md `<specifics>` suggestion: one pipe-table row per refactored factory with columns (Factory, File, Final signature, geom fields read, Remaining kwargs, Notes), plus a dedicated 'Not touched' section listing every stateless / private / out-of-scope correlation function with rationale anchored to §3.1 or D-02."
  - "Doc explicitly named Phase 61 (GUI registry rewrite) as its consumer in Section 5 — the doc carries actionable GUI-registry guidance (collapse Dh/L/b/aspect_ratio into a single geom reference; render only remaining kwargs as editable fields; mark develop_length as required-no-default; ignore HTCCorrelation alias)."
  - "Doc states the in-source docstrings remain the canonical source of truth for argument semantics, eval-point conventions, and per-correlation references — the handoff doc captures the API surface only, not the physics derivations."
  - "Validation / parity status (Section 6) points to 59-03-SUMMARY.md for the parity-gate evidence rather than recomputing the baseline (424 CLEAN / 78 GRAY / 34 FAIL identical pre- vs. post-refactor)."

patterns-established:
  - "Plan-04-style 'handoff doc' wave: after a multi-plan API-shaping phase lands and the parity gate confirms zero semantic drift, emit a self-contained reference doc that captures the final API surface for the downstream phase to consume directly. The doc lives in .planning/notes/ alongside the original design-decisions doc; it does NOT replace docstrings."

requirements-completed: []

# Metrics
duration: ~10min
completed: 2026-05-11
---

# Phase 59 Plan 04: Correlation geom-first API handoff doc Summary

**Single deliverable: `.planning/notes/correlation-geom-first-api.md` — the canonical Phase 61 (GUI registry rewrite) handoff artifact capturing the post-Phase-59 correlation API surface (five refactored factories + `HTCCorrelation` documentation alias + explicit non-modifications list + GUI registry guidance). No source/test code touched.**

## Performance

- **Duration:** ~10 min
- **Completed:** 2026-05-11
- **Tasks:** 1 / 1
- **Files created:** 1

## Accomplishments

- `.planning/notes/correlation-geom-first-api.md` exists at 174 lines (well above the 60-line floor in `<acceptance_criteria>`).
- Doc structure has six sections per the plan's `<action>` block:
  1. Header — states this is the canonical Phase 61 handoff per D-05, lives alongside `gui-redesign-design-decisions.md`, lists the four Phase 59 plans that produced it.
  2. Type alias — documents `const HTCCorrelation = Function` exported from `src/STREAM.jl`; states it is documentation-only (not runtime-enforcing); cites §3.1; flags that the GUI registry should ignore it.
  3. Refactored factories table — single pipe table with header `| Factory | File | Final signature | geom fields read | Remaining kwargs | Notes |` and one row per refactored factory (laminar_friction, elenbaas_htc, fully_developed_laminar_h_spl, developing_laminar_h_spl, regime_dependent). Each row carries the verbatim final signature confirmed from `src/physical_models/htc/correlations.jl` and `src/physical_models/friction/correlations.jl` at the wave-3-final HEAD.
  4. Not touched section — bulleted list with every untouched correlation function (dittus_boelter, blasius_friction, turbulent_friction, constant_Nusselt, maximal_htc, elenbaas_nusselt, Marco_Han_Nusselt, viscosity_correction, rectangular_laminar_correction, regime_dependent_q_scb, plus private helpers) with one-line rationale anchored to §3.1 or D-02.
  5. GUI registry implications — actionable bullets for Phase 61: collapse Dh/L/b/aspect_ratio into a single geom reference; render only remaining kwargs as editable per-factory fields (g for elenbaas_htc; develop_length mandatory for developing_laminar_h_spl; htc_*/friction_*/Re_transition for regime_dependent; Nu for constant_Nusselt; epsilon for turbulent_friction); ignore HTCCorrelation alias; cross-reference §3.10 / §3.11 for ChannelAndContacts Properties-tab wiring.
  6. Validation / parity status — single sentence pointing to 59-03-SUMMARY.md for the parity-gate evidence; states the 424 CLEAN / 78 GRAY / 34 FAIL baseline preserved with zero semantic drift.
- Canonical construction example included after Section 3 (the `geom` + factories + ChannelAndContacts shape Phase 61's GUI generator should emit).
- All acceptance grep criteria from the plan pass (verified below).

## Task Commits

1. **Task 1: Author correlation-geom-first-api.md handoff doc** — `28e0d0f` (docs)

## Files Created/Modified

- `.planning/notes/correlation-geom-first-api.md` — new file, 174 lines. Six sections (header + 5 `## ` subsections). One pipe-table covering all five refactored factories. Bulleted list of every untouched correlation function. Phase 61 named explicitly as the consumer in Section 5. HTCCorrelation alias documented in Section 2.

## Decisions Made

- **Pipe-table column count is six, not the four shown in CONTEXT.md `<specifics>`.** The CONTEXT.md sketch was minimal (`Factory | Final signature | geom fields read | Remaining kwargs`); the plan's `<action>` block expanded it to six (`Factory | File | Final signature | geom fields read | Remaining kwargs | Notes`) by adding File and Notes columns. The File column gives Phase 61 a direct path-to-source pointer per factory; the Notes column carries the rationale-per-row that would otherwise need a separate prose paragraph. Followed the plan's six-column form.
- **`develop_length` MANDATORY status emphasized in two places.** In the table (Remaining kwargs column: "`develop_length` (**MANDATORY**, no default per D-04)") AND in the GUI Registry Implications section (Section 5, bullet: "the GUI should mark this field as required and refuse to submit without a user-supplied value"). The double-emphasis is deliberate — D-04 is the most surprise-prone change for Phase 61 since the pre-Phase-59 form silently accepted `develop_length=geom.L` via a default substitution.
- **Section 5 includes GUI-registry guidance for `constant_Nusselt` and `turbulent_friction` even though they are NOT refactored.** Phase 61 will still render them in the registry, and the §3.1 "pure-tuning-kwarg-only" bucket applies to them. Calling out `Nu` (default 8.235) and `epsilon` (default 0) in Section 5 keeps Phase 61's registry-form generator from having to re-derive these defaults from source. The plan's `<action>` Section 5 bullet explicitly listed these — followed verbatim.
- **Validation section (Section 6) is one sentence, not a full table.** The plan's `<action>` Section 6 prescribed a single sentence pointing to 59-03-SUMMARY.md; followed verbatim. Phase 61 doesn't need the parity numbers reproduced here — 59-03-SUMMARY.md has them and lives in the same `.planning/phases/59-correlation-geom-first-refactor/` directory.
- **Did not reorder sections.** Sections 1-6 are in the exact order specified by the plan's `<action>` block. The `## ` heading count is 5 (Sections 2-6 are `## `; Section 1 is the title `# ` plus a couple of `**` paragraphs without a `## ` heading of its own, matching the plan's acceptance criterion "where Section 1 may be `#` and the rest `##`").

## Deviations from Plan

None functional. Task 1 executed per the plan's `<action>` block verbatim.

One **pre-existing wave-1 issue** is documented in the Issues Encountered section below for the orchestrator's awareness. It is NOT a deviation from this plan — it was discovered by the orchestrator between Plan 01 landing and Plan 02 starting, and the orchestrator added an extra commit (`f4a0042 fix(59): hoist HTCCorrelation alias above includes`) to fix it. That commit sits at the worktree base for this plan. Surfaced here per the orchestrator's prompt instruction: "Reference this in the SUMMARY's 'Issues Encountered' section as a small wave-1 acceptance gap."

## Issues Encountered

**1. Wave-1 precompile-order bug fixed by orchestrator commit `f4a0042` (not by this plan)**

- **Found by:** Orchestrator, between Plan 01 merging and Plan 02 starting.
- **Issue:** Plan 01 declared `const HTCCorrelation = Function` in `src/STREAM.jl` *after* the `include` block, but `src/physical_models/htc/correlations.jl` (also included from `STREAM.jl`) was scheduled in Plan 02 to reference `HTCCorrelation` as a type annotation at parse time on `regime_dependent`'s kwargs. The alias was declared *after* its includes — a precompile-order bug that would have manifested as `UndefVarError: HTCCorrelation` the moment Plan 02 landed and the file was evaluated at module-load time.
- **Why Plan 01 missed it:** Plan 01's source-level acceptance criteria checked that the `const HTCCorrelation = Function` line exists in `src/STREAM.jl` exactly once and that it appears in an export line, but did not assert positional ordering relative to the `include(...)` block. The Plan 01 executor's note about no Julia available in the worktree (and the runtime gate deferred to Plan 03) meant the bug was caught structurally by the orchestrator inspecting the merged source, not by any test.
- **Fix:** Orchestrator commit `f4a0042` ("fix(59): hoist HTCCorrelation alias above includes") moved `const HTCCorrelation = Function` to BEFORE the `include` block, with a comment "Declared before includes so physical_models/htc/correlations.jl can reference it at parse time." This is the wave-1-final state visible at the worktree base for this plan (confirmed via `git log` showing `f4a0042` as `HEAD` of the merged worktree base, and the current `src/STREAM.jl` lines 1-15 show the alias on line 9 followed by `include` calls on lines 11+).
- **Acceptance gap:** Plan 01's plan should have included a source-level acceptance criterion asserting the alias declaration appears at a line number *strictly less than* the line number of the first `include(...)` call in `src/STREAM.jl`. Future plans that introduce or move type aliases used by included files should encode this positional invariant. Surfacing for retrospective consideration.
- **Impact on this plan (59-04):** None — Plan 04 only writes a doc and does not depend on source-level state beyond reading the final factory signatures. The doc reflects the final, post-`f4a0042` state.

## User Setup Required

None — pure documentation deliverable, no external services touched.

## Next Phase Readiness

- **Phase 61** (GUI registry rewrite) is now fully unblocked from a documentation standpoint. The canonical handoff artifact exists at a stable path (`.planning/notes/correlation-geom-first-api.md`) alongside the original design-decisions doc; Phase 61's executor reads this doc cold and has every factory signature, every "do not touch" boundary, and explicit GUI-rendering guidance for parameter forms.
- **Phase 59 closure** — every D-* decision from CONTEXT.md is now realized:
  - D-00 (geom-first convention): all five factories ✓
  - D-01 (clean break): Plan 01 + Plan 02 ✓
  - D-02 (regime_dependent_q_scb deferred): documented in Section 4 of the handoff doc ✓
  - D-03 (docstring-only elenbaas domain note): present in `src/physical_models/htc/correlations.jl` line 211-216 + Notes column of the handoff doc ✓
  - D-04 (mandatory develop_length): factory + handoff doc table + GUI registry guidance bullet ✓
  - D-05 (Phase 61 handoff doc): this plan ✓
  - D-06 (test_correlations.jl stays single file): preserved across Plans 01-03 ✓
- **STATE.md / ROADMAP.md** intentionally untouched per worktree-mode instructions; orchestrator owns those writes after the worktree merges back.

## Self-Check: PASSED

Created files exist on disk:
- `.planning/notes/correlation-geom-first-api.md` (174 lines) — FOUND
- `.planning/phases/59-correlation-geom-first-refactor/59-04-SUMMARY.md` — being written now.

Commits exist on `worktree-agent-a78d4d7aac339abfa`:
- `28e0d0f` — `docs(59-04): correlation geom-first API handoff doc for Phase 61` — FOUND

Acceptance grep checks (from the plan's `<acceptance_criteria>`):
- `test -f .planning/notes/correlation-geom-first-api.md` → 0 ✓
- `wc -l` → 174 (≥ 60) ✓
- `grep -E "^## "` → 5 (≥ 5) ✓
- `grep -cE "laminar_friction\(geom::PipeGeometry\)"` → 1 (≥ 1) ✓
- `grep -cE "elenbaas_htc\(geom::PipeGeometry"` → 1 (≥ 1) ✓
- `grep -cE "fully_developed_laminar_h_spl\(geom::PipeGeometry\)"` → 1 (≥ 1) ✓
- `grep -cE "developing_laminar_h_spl\(geom::PipeGeometry;\s*develop_length\)"` → 1 (≥ 1) ✓
- `grep -cE "regime_dependent\(geom::PipeGeometry;"` → 1 (≥ 1) ✓
- `grep -E "HTCCorrelation\s*=\s*Function"` → 1 (≥ 1) ✓
- `grep -E "regime_dependent_q_scb"` → 1 (≥ 1) ✓
- `grep -E "dittus_boelter|blasius_friction|turbulent_friction|constant_Nusselt|maximal_htc" | wc -l` → 10 (≥ 5) ✓
- `grep -E "Phase 61"` → 7 (≥ 1) ✓
- Combined factory-name grep `>= 10` → 21 ✓

No modifications to `.planning/STATE.md` / `.planning/ROADMAP.md` (per worktree-mode instructions; orchestrator owns those after merge).

---
*Phase: 59-correlation-geom-first-refactor*
*Completed: 2026-05-11*
