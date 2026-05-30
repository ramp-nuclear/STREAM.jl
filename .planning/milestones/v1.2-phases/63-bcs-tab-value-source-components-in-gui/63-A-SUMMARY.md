---
phase: 63-bcs-tab-value-source-components-in-gui
plan: A
subsystem: utilities
tags: [julia, mtk, rebin, area-weighting, cosine-profile, value-sources, bcs]

# Dependency graph
requires:
  - phase: 62-power-shape-resources-foundation
    provides: "`src/utilities.jl` with `_rebin_1d`, `rebin_extensive` (2D), and `cosine_power_shape` (Phase 62); export-list discipline in `STREAM.jl`; CONS-01..04 testset shape in `test/test_utilities.jl`"
provides:
  - "`rebin_intensive(v::AbstractVector, n_target::Integer)` — 1D area-weighted-mean-conserving rebin"
  - "`rebin_intensive(M::AbstractMatrix, target_shape::Tuple{Int,Int})` — 2D separable (z-then-x) mean-conserving rebin"
  - "`cosine_T_wall_profile(n; amplitude, peaking_factor)` — thin alias over `cosine_power_shape` for axial BC profiles"
  - "`rebin_extensive(v::AbstractVector, n_out::Integer)` — 1D public method (deviation Rule 3; symmetric companion required for INT-05 cross-check)"
  - "Public exports of `rebin_intensive` and `cosine_T_wall_profile` from `STREAM`"
  - "INT-01..05 + CT-01 testsets covering mean conservation across 5 reshape regimes and cosine alias contract"
affects:
  - "63-B (codeGenerator.ts Profile-mode emit calls `rebin_intensive(...)` and `cosine_T_wall_profile(...)` — both now resolvable at script runtime)"
  - "63-C / 63-D (BCs-tab GUI plans — depend on the codegen path that this plan unblocks)"
  - "Future intensive-field imports for HeatDiffusion initial conditions and multi-material k-fields (project_future_multi_material.md)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Intensive-vs-extensive rebin duality: `rebin_intensive(v, M) .* N == rebin_extensive(v, M) .* M` — overlap normalization by target-cell-width vs source-cell-width"
    - "Four-section docstring (Arguments / Returns / Algorithm / Caller trust) extended from Phase 62 to all new public helpers"
    - "Thin-alias public API for intent-named codegen entry points (`cosine_T_wall_profile` -> `cosine_power_shape`)"
    - "Multiple-dispatch on first argument type (Vector vs Matrix) for 1D/2D rebin variants, no kwargs (per `feedback_keyword_only_rule.md`)"

key-files:
  created: []
  modified:
    - "src/utilities.jl — appended `_rebin_1d_intensive`, `rebin_intensive` (1D + 2D), `cosine_T_wall_profile`, and the 1D `rebin_extensive(v, n_out)` companion. 155 -> 370 lines (+215)."
    - "test/test_utilities.jl — appended INT-01..05 + CT-01 testsets; extended import line. 101 -> 233 lines (+132)."
    - "src/STREAM.jl — extended one export line from 2 symbols to 4 (`rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile`)."

key-decisions:
  - "CD-02 resolved: `cosine_T_wall_profile` is a thin alias over `cosine_power_shape(n, 1; amplitude=amplitude*peaking_factor)[:, 1]`. Deeper PPF-extrapolation-length physics (Python STREAM `cosine_shape` parity) deferred to Phase 72."
  - "INT-05 cross-check identity locked as `rebin_intensive(v, M) .* N ≈ rebin_extensive(v, M) .* M` (where N = length(v), M = target). Derivation in plan comments; ones(N) sanity = N*ones(M) on both sides."
  - "Added 1D `rebin_extensive(v::AbstractVector, n_out::Integer)` as Rule-3 deviation: required for INT-05 to compile (plan's `<interfaces>` block claimed it existed; in reality only the 2D form existed)."
  - "Caller-trust posture (no validation, no normalization, NaN-through) carried verbatim from `rebin_extensive` per `feedback_power_shape_trust_caller.md` memory."

patterns-established:
  - "Intensive rebin separable-pass arithmetic: `_rebin_1d_intensive` differs from `_rebin_1d` only in overlap scaling (`* n_out` vs `* n_in`). 2D form uses the canonical z-then-x order for reproducibility (matching `rebin_extensive`'s Phase 62 convention from RESEARCH Pitfall 6)."
  - "Public 1D wrapper + private `_rebin_1d_*` helper + public 2D separable wrapper — the three-function pattern is now mirrored across both `rebin_extensive` (Phase 63-A added 1D wrapper) and `rebin_intensive`."

requirements-completed:
  - D-13
  - D-14
  - D-15
  - D-16
  - CD-02

# Metrics
duration: 3.4min
completed: 2026-05-13
---

# Phase 63 Plan A: rebin_intensive + cosine_T_wall_profile Helpers Summary

**Symmetric mean-conserving 1D+2D `rebin_intensive` and a thin-alias `cosine_T_wall_profile` shipped alongside Phase 62's `rebin_extensive` — unblocks 63-B GUI codegen for Profile-mode BC value imports.**

## Performance

- **Duration:** 3.4 min (cold-start `julia --project=.` used per `feedback` re: worktree daemon bypass)
- **Started:** 2026-05-13T14:21:10Z
- **Completed:** 2026-05-13T14:24:34Z (approximate)
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- `rebin_intensive(v::AbstractVector{<:Real}, n_target::Integer) -> Vector{Float64}` — 1D area-weighted-mean-conserving rebin (`sum(out)/n_target == sum(v)/length(v)` to FP precision).
- `rebin_intensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}` — 2D separable (z-then-x) mean-conserving rebin; reserved for future intensive-field imports.
- `cosine_T_wall_profile(n::Integer; amplitude::Real=1.0, peaking_factor::Real=1.0) -> Vector{Float64}` — thin alias over `cosine_power_shape` giving codegen an intent-named axial-cosine entry point (CD-02 resolved).
- Added a public 1D `rebin_extensive(v, n_out)` method as a Rule-3 deviation to make the INT-05 cross-check identity compile.
- Six new testsets (INT-01..05, CT-01), 24 new test assertions, all green; CONS-01..04 + `cosine_power_shape` testsets unaffected.
- Public exports updated in `STREAM.jl` from 2 -> 4 symbols on the rebin/cosine line.

## Task Commits

Each task was committed atomically:

1. **Task 63-A-01: Append `rebin_intensive` + cosine alias to `src/utilities.jl`** — `328e180` (feat)
2. **Task 63-A-02: Append INT-01..05 + CT-01 testsets to `test/test_utilities.jl`** — `af56ad4` (test)
3. **Task 63-A-03: Append `rebin_intensive` and `cosine_T_wall_profile` to public exports in `src/STREAM.jl`** — `ba0100e` (feat)

_Note: Per project preference, tests were committed after the implementation rather than in a strict RED-first order. Task 02's `<verify>` step ran the full test_utilities.jl suite green at first execution, confirming the implementation in Task 01 was correct and no RED iteration was needed._

## Files Created/Modified

- `src/utilities.jl` — Added `_rebin_1d_intensive` private helper + `rebin_intensive` (1D + 2D) + `cosine_T_wall_profile` + 1D `rebin_extensive` method. **+215 lines** (155 -> 370). Pre-existing `_rebin_1d`, `rebin_extensive(M, target_shape)`, `cosine_power_shape` left untouched.
- `test/test_utilities.jl` — Added INT-01..05 + CT-01 testsets; extended import line. **+132 lines** (101 -> 233). Pre-existing CONS-01..04 testsets unmodified.
- `src/STREAM.jl` — Single export line: `export rebin_extensive, cosine_power_shape` -> `export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile`. **+0 net lines** (one-line replacement).

## Decisions Made

- **CD-02 (cosine alias name) resolved as `cosine_T_wall_profile`** with a thin-alias implementation `cosine_power_shape(n, 1; amplitude=amplitude*peaking_factor)[:, 1]`. The plan explicitly authorized this v1 form and deferred a stricter PPF-based physics interpretation to Phase 72.
- **`peaking_factor` folds into `amplitude`** (verified by CT-01: `cosine_T_wall_profile(n; amplitude=1.0, peaking_factor=2.0) == cosine_T_wall_profile(n; amplitude=2.0, peaking_factor=1.0)` to `rtol=1e-12`). The two-knob signature matches the 63-CONTEXT D-06 spec; the simple multiplicative semantics is the cheapest v1 contract.
- **INT-05 cross-check identity (D-15) implemented as** `rebin_intensive(v, M) .* N ≈ rebin_extensive(v, M) .* M` (where `N = length(v)`, `M = n_target`) across all 5 reshape regimes. Derivation: the `ones(N)` sanity case gives `LHS = N*ones(M)` and `RHS = N*ones(M)` — they match. The mirror form would only hold when `M == N` and is therefore wrong.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added 1D public `rebin_extensive(v::AbstractVector, n_out::Integer)` method**
- **Found during:** Task 63-A-01 read-through.
- **Issue:** The plan's `<interfaces>` block at line 76 of 63-A-PLAN.md listed `rebin_extensive(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}` as an existing public 1D form, but inspection of `src/utilities.jl` showed only the 2D `rebin_extensive(M, target_shape)` method exists. The INT-05 cross-check identity test (`rebin_intensive(v, M) .* N ≈ rebin_extensive(v, M) .* M`) calls `rebin_extensive` on a vector and would fail at parse time without a 1D method.
- **Fix:** Added a thin 1D public method `rebin_extensive(v::AbstractVector{<:Real}, n_out::Integer) = _rebin_1d(v, n_out)` with the full four-section docstring, in `src/utilities.jl` between the Phase 62 block and the new intensive block. No change to the existing 2D method.
- **Files modified:** `src/utilities.jl` (Task 63-A-01 commit).
- **Verification:** INT-05 testset passes `julia --project=. test/test_utilities.jl` (5/5 cross-check cases green).
- **Committed in:** `328e180` (part of Task 63-A-01).

**2. [Rule 3 - Tooling] Used cold-start `julia --project=.` instead of `bin/jl`**
- **Found during:** Task 63-A-01 verification.
- **Issue:** Plan's `<verify>` blocks specify `bin/jl test/test_utilities.jl`. CLAUDE.md notes that "worktree-isolated executor agents bypass the daemon... worktree work uses cold-start `julia ...`" — and indeed `bin/` does not exist in the worktree spawn. Daemon Revise on the main repo is watching the wrong path, so any `bin/jl` invocation would test stale files even if it worked.
- **Fix:** Ran `julia --project=. test/test_utilities.jl` directly (~30s precompile + ~1s test execution). This is the documented worktree path.
- **Files modified:** None.
- **Verification:** All 11 testsets (4 pre-existing + 6 new + 1 already-passing identity) green, 0 failures, 0 errors.
- **Committed in:** N/A (no source change required).

---

**Total deviations:** 2 auto-fixed (1 blocking-missing-API, 1 tooling-path-fix).
**Impact on plan:** Both deviations are documented exceptions, not scope creep. The 1D `rebin_extensive` method is a tiny surface addition (single-line wrapper around an existing private helper); the cold-start tooling swap is explicit in CLAUDE.md.

## Issues Encountered

None beyond the two deviations above. Both new functions worked correctly on first implementation; tests passed on first run (no RED iteration needed because the math was validated against the existing `_rebin_1d` analog before writing the new helper).

## User Setup Required

None — no external service configuration, no new dependencies, no env vars.

## Next Phase Readiness

- **63-B (Wave 1 parallel sibling) unblocked** — `rebin_intensive` and `cosine_T_wall_profile` resolve at script runtime via `using STREAM`, so codegen `.jl` emit will compile.
- **63-C / 63-D (BCs-tab GUI plans, Wave 2) unblocked** — depend on the codegen path that 63-B+63-A together complete.
- **Future work:** Phase 72 design-system audit may upgrade `cosine_T_wall_profile`'s `peaking_factor` from a scalar multiplier to a true PPF-extrapolation-length parameter matching Python STREAM `cosine_shape`. The thin-alias contract makes that refactor a single-file change with no caller migration needed.

## TDD Gate Compliance

Plan frontmatter declares each task `tdd="true"` but plan `type: execute` (not `type: tdd`). The natural execution order with Task 01 = impl and Task 02 = tests means the strict RED-before-GREEN gate sequence is not directly applicable. Task 02's test commit (`af56ad4`) follows Task 01's impl commit (`328e180`) — equivalent to a GREEN-then-test-codify pattern. All six new testsets passed on first execution after committing, confirming no shortcut/bug in the implementation. CONS-01..04 regression-safe (un-modified, all green).

## Verification Summary

- `julia --project=. test/test_utilities.jl` — exits 0, all 11 testsets green (CONS-01..04 + INT-01..05 + CT-01).
- `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive); @assert isdefined(STREAM, :cosine_T_wall_profile); println("OK")'` — prints `OK`.
- `grep -E '^export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile$' src/STREAM.jl` — single-line exact match.
- Acceptance grep counts (`grep -c '^function rebin_intensive' src/utilities.jl == 2`, `^function _rebin_1d_intensive == 1`, `^function cosine_T_wall_profile == 1`, `# Caller trust >= 3`) — all pass.
- No `_rebin_1d`, `rebin_extensive(M, target_shape)`, or `cosine_power_shape` changes (Phase 62 invariants preserved).
- No modifications to any Julia source file outside `src/utilities.jl`, `src/STREAM.jl`, and `test/test_utilities.jl` (no v1.1 channel/CAC regression risk).

## Self-Check: PASSED

- File `src/utilities.jl` present, 370 lines, new symbols defined.
- File `test/test_utilities.jl` present, 233 lines, INT-01..05 + CT-01 testsets present.
- File `src/STREAM.jl` present, line 100 carries the four-symbol export.
- Commits found: `328e180` (utilities), `af56ad4` (tests), `ba0100e` (exports) — all in `git log`.

---
*Phase: 63-bcs-tab-value-source-components-in-gui*
*Plan: A*
*Completed: 2026-05-13*
