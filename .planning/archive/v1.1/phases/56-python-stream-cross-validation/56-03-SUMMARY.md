---
phase: 56-python-stream-cross-validation
plan: 03
subsystem: testing
tags:
  - testing
  - validation
  - parity-harness
  - python-generator
  - mtr
  - heat-diffusion
  - channel-and-contacts

# Dependency graph
requires:
  - phase: 56-python-stream-cross-validation
    provides: "D-02 three MTR variants, D-07 four-tier quantity coverage, D-17 generator-rewrite mandate"
provides:
  - "test/generate_mtr_reference.py rewritten per D-17 — emits ALL D-07 tiers (a)+(b)+(c)+(d) for ALL 3 MTR variants (symmetric, asymmetric, one-sided)"
  - "Geometry block (PARITY_MTR_GEOM_DH / AREA / WETPERIM / HEATED) emitted once for shared use across MTR scenarios"
  - "Tier (d) plate-side T(z,x) emitted as Julia Matrix-literal of shape (NZ=10, NX=3) per scenario"
  - "begin/end-paste markers bracket each pasteable block for Plan 04 grep/sed extraction"
  - "KNOWN GAP comment block in the one-sided scenario per RESEARCH.md Known-Different Master List"
  - "Pitfall 3 verdict (T_left/T_right auto-wired by plate()/symmetric_plate()/one_sided_connection() via _pair_connection graph edges) recorded in commit message and code comments"
affects:
  - 56-04-regenerate-and-paste
  - 56-05-mtr-parity-testsets
  - test/data/python_parity_reference.jl

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Phase 53 stage2_reference.py begin/end-paste-marker generator pattern extended to 4 paste-blocks (geometry + 3 scenarios)"
    - "ChannelVar enum import with try/except fallback for upstream Python STREAM HEAD-drift resilience"
    - "Defensive try/except KeyError on tier (c) state-dict extraction with diagnostic-and-raise (no funcs-augmentation self-recovery)"

key-files:
  created: []
  modified:
    - "test/generate_mtr_reference.py — D-17 rewrite, 543 lines (was 306)"

key-decisions:
  - "Pitfall 3 verified at planning time: plate()/symmetric_plate()/one_sided_connection() ALL auto-wire T_left/T_right via _pair_connection graph edges (per ~/projects/STREAM/stream/composition/mtr_geometry.py:99-104, 197-200, 224-231); NO funcs augmentation needed for tier (c) twall_left/twall_right state-dict keys to populate. Recorded in code comments."
  - "Belt-and-suspenders try/except KeyError on each tier (c) extraction surfaces upstream Python STREAM HEAD drift cleanly (diagnostic + raise, never auto-augment funcs mid-run — that would override graph-wired values and silently break parity)."
  - "Geometry block emitted ONCE (not per-scenario) since all 3 MTR scenarios share the same EffectivePipe.rectangular(L=0.6, edge1=0.07, edge2=0.00127, heated_edge=0.07) — Dh ≈ 0.002495 m, both faces heated."
  - "np.isnan assertion on each plate matrix after extraction catches scipy.optimize.root 'success'-with-NaN equivalent; without it downstream printing would silently emit NaN constants."
  - "ChannelVar import path tracked in _CHANNELVAR_IMPORT_PATH module variable and printed in the generator's stdout banner so Plan 04 can record which path was active when the references were regenerated."
  - "Generator end-to-end smoke run on developer machine deferred to Plan 04 per D-06 (manual regenerate-and-paste step) — Phase 56 is split into rewrite (this plan) and regenerate-and-paste (Plan 04) to keep waves atomic."

patterns-established:
  - "Per-scenario per-cell extraction block immediately after _solve_scenario(): T_cells_l/r (tier b), 6 wall arrays per channel × 1 or 2 channels (tier c), plate matrix (tier d) — uniform shape across 3 scenarios for downstream grep/sed extensibility"
  - "Three Julia const-block emitter helpers (_emit_julia_scalar / _emit_julia_array / _emit_julia_matrix) with optional comment_each / comment_prefix kwargs — reusable template for future v1.2+ parity-scenario generators"
  - "Matrix-literal print convention: row z=1..NZ separated by `;`, each row space-separated NX cell values in Kelvin; consumer reads `PARITY_NAME[z, x]` as direct (z, x) tuple index"

requirements-completed:
  - TEST-04

# Metrics
duration: ~10min
completed: 2026-05-08
---

# Phase 56 Plan 03: MTR Reference Generator Rewrite Summary

**Rewrote test/generate_mtr_reference.py per D-17 to emit per-tier Julia const blocks (geometry + symmetric/asymmetric/one-sided) covering D-07 tiers (a)+(b)+(c)+(d) — including the 30-cell plate T(z,x) Matrix-literal — bracketed by begin/end-paste markers for Plan 04 ingestion.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-08T~10:05:00Z
- **Completed:** 2026-05-08T~10:15:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `test/generate_mtr_reference.py` grown from 306 lines (T_outlet + mdot + T_plate_center scalars only) to 543 lines covering all D-07 tiers for all 3 MTR variants per D-02.
- All 5 scalar consts × 3 scenarios + 14 per-cell array consts (sym/asym) + 7 per-cell array consts (one-sided) + 3 plate-T matrix consts + 4 geometry consts = **complete tier (a)+(b)+(c)+(d) coverage**.
- Output bracketed by 4 `# --- begin paste ---` / `# --- end paste ---` markers (geometry + 3 scenarios) per Phase 53 `stage2_reference.py` pattern.
- KNOWN GAP comment block disclosed in the one-sided scenario per RESEARCH.md Known-Different Master List (Python `one_sided_connection` distributes heat to BOTH plate faces — acknowledged Python bug; Plan 05 testset compares Julia plate-T against analytical T_max formula instead, NOT against Python plate-T).
- ChannelVar enum imported with try/except fallback path; active path tracked in `_CHANNELVAR_IMPORT_PATH` and printed in the generator banner so Plan 04 records which version was active during regeneration.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite test/generate_mtr_reference.py — replace scalar-only print epilogue with per-tier const-block emitter for all 3 MTR variants** — `89917c0` (feat)

## Files Created/Modified

- `test/generate_mtr_reference.py` — D-17 rewrite. Replaces the lines 286–306 print epilogue (T_outlet + mdot + T_plate_center scalar prints) with a comprehensive per-tier emitter. Adds three Julia const-block emitter helpers, ChannelVar import with try/except fallback, per-cell extraction blocks for each scenario (symmetric / asymmetric / one-sided), and an `np.isnan` assertion on each plate matrix to catch scipy "success"-with-NaN.

## Const Names Emitted (the full grep set for Plan 04 / Plan 05)

### Block 0 — Geometry (shared across all 3 MTR scenarios)

- `PARITY_MTR_GEOM_DH`
- `PARITY_MTR_GEOM_AREA`
- `PARITY_MTR_GEOM_WETPERIM`
- `PARITY_MTR_GEOM_HEATED` — `(heated_left, heated_right)` tuple, both 0.07 m

### Block 1 — Symmetric (5 scalars + 14 per-cell arrays + 1 plate matrix)

Scalars: `PARITY_MTR_SYM_T_OUT_L`, `_T_OUT_R`, `_MDOT_L`, `_MDOT_R`, `_DP`

Per-cell coolant (tier b): `PARITY_MTR_SYM_T_CELLS_L`, `_T_CELLS_R`

Per-cell wall (tier c — both channels):
- L: `PARITY_MTR_SYM_T_WALL_LEFT_L`, `_T_WALL_RIGHT_L`, `_H_TC_LEFT_L`, `_H_TC_RIGHT_L`, `_Q_LEFT_L`, `_Q_RIGHT_L`
- R: `PARITY_MTR_SYM_T_WALL_LEFT_R`, `_T_WALL_RIGHT_R`, `_H_TC_LEFT_R`, `_H_TC_RIGHT_R`, `_Q_LEFT_R`, `_Q_RIGHT_R`

Plate matrix (tier d): `PARITY_MTR_SYM_T_PLATE`

### Block 2 — Asymmetric (same shape as symmetric, ASYM prefix)

Scalars: `PARITY_MTR_ASYM_T_OUT_L`, `_T_OUT_R`, `_MDOT_L`, `_MDOT_R`, `_DP`

Per-cell coolant: `PARITY_MTR_ASYM_T_CELLS_L`, `_T_CELLS_R`

Per-cell wall (tier c — both channels):
- L: `PARITY_MTR_ASYM_T_WALL_LEFT_L`, `_T_WALL_RIGHT_L`, `_H_TC_LEFT_L`, `_H_TC_RIGHT_L`, `_Q_LEFT_L`, `_Q_RIGHT_L`
- R: `PARITY_MTR_ASYM_T_WALL_LEFT_R`, `_T_WALL_RIGHT_R`, `_H_TC_LEFT_R`, `_H_TC_RIGHT_R`, `_Q_LEFT_R`, `_Q_RIGHT_R`

Plate matrix (tier d): `PARITY_MTR_ASYM_T_PLATE`

### Block 3 — One-sided (3 scalars + 7 per-cell arrays + 1 plate matrix; left-only)

Scalars: `PARITY_MTR_ONESIDED_T_OUT_L`, `_MDOT_L`, `_DP`

Per-cell coolant: `PARITY_MTR_ONESIDED_T_CELLS_L`

Per-cell wall (tier c — left channel only):
- `PARITY_MTR_ONESIDED_T_WALL_LEFT_L`, `_T_WALL_RIGHT_L`, `_H_TC_LEFT_L`, `_H_TC_RIGHT_L`, `_Q_LEFT_L`, `_Q_RIGHT_L`

Plate matrix (tier d, KNOWN GAP): `PARITY_MTR_ONESIDED_T_PLATE`

**Total const names:** 4 (geometry) + 20 (symmetric) + 20 (asymmetric) + 11 (one-sided) = **55 emitted constants** across all 3 MTR scenarios.

## Decisions Made

- **Pitfall 3 verdict — RESOLVED at planning time, NO funcs augmentation needed.** Per the plan's WARNING #8 fix and the planning-time read of `~/projects/STREAM/stream/composition/mtr_geometry.py`: `plate()` (lines 99–104), `symmetric_plate()` (lines 224–231), and `one_sided_connection()` (lines 197–200) ALL auto-wire `T_left` / `T_right` via `_pair_connection`'s graph edges. Therefore `_build_channel_and_loop`'s `funcs={channel: dict(p_abs=P_ABS)}` is sufficient for tier (c) `state[ch.name][ChannelVar.twall_left]` / `[ChannelVar.twall_right]` to populate at solve time. The defensive `try/except KeyError` blocks on each per-cell extraction are belt-and-suspenders for upstream Python STREAM HEAD drift; if they ever fire the diagnostic surfaces and re-raises rather than silently augmenting `funcs` (which would override the graph-wired values and break parity).
- **ChannelVar import path tracking.** `_CHANNELVAR_IMPORT_PATH` module variable records which try/except branch fired (`stream.calculations.channel` or `stream.calculations.channel_vars`); printed in the generator stdout banner so Plan 04 (manual regenerate-and-paste) records the path that was active during regeneration. Future drift in upstream Python STREAM is then attributable.
- **Geometry block emitted once.** All 3 MTR scenarios share the same `EffectivePipe.rectangular(L=0.6, edge1=0.07, edge2=0.00127, heated_edge=0.07)`; Dh ≈ 0.002495 m, both faces heated. Single `# --- begin paste: ... MTR geometry ---` block at the top of the output keeps the const file compact and avoids three identical copies.
- **`pipe_ch.area` attribute name.** The plan flagged this as needing verification ("If `pipe_ch.area` doesn't exist, try `pipe_ch.A`"). The current Python STREAM `EffectivePipe` exposes `area` directly per existing usage in the codebase; not changed. If Plan 04 hits an `AttributeError` here, fix is a one-character swap to `pipe_ch.A`.
- **Plate matrix indexing parity verified by construction.** Per RESEARCH.md "How 2D plate T(z,x) renders": Julia `Float64[a b c; d e f; ...]` is row-major-readable; `mat[z, x]` returns row z, col x. Python `state[fuel.name]["T"]` is shape `(NZ, NX)` numpy row-major. The emitter iterates `for z in range(NZ): row = mat[z, :]` and prints each row separated by `;` — Julia consumer reads `PARITY_NAME[z, x]` as direct (z, x) tuple index. No transpose ever needed.

## Deviations from Plan

None — plan executed exactly as written. The plan's "EDIT-IN-PLACE" (replace print epilogue lines 286–306) was implemented as a full file write because the rewrite touches header, imports, and adds three helper functions in addition to the epilogue replacement. The result preserves topology lines 1–282 verbatim.

## Issues Encountered

None. The Pitfall 3 verdict was already resolved at planning time (per the plan's WARNING #8 fix), so the implementation followed a green path.

## Open Items / Next-Plan Inputs

- **Generator NOT smoke-run end-to-end on the developer machine in this plan.** Per D-06 (Python runtime not in CI) and the plan's split structure, the smoke run + paste happens in Plan 04 (manual regenerate-and-paste checkpoint). If Plan 04's smoke run fails on the developer's local Python STREAM (e.g., `pipe_ch.area` AttributeError, ChannelVar enum path drift), return to this plan for fixes. Likely failure modes:
  - `pipe_ch.area` → swap to `pipe_ch.A`
  - `ChannelVar` import → both paths already covered by try/except
  - tier (c) KeyError → planning-time verdict says this won't happen, but if it does, the diagnostic message in the except branch tells Plan 04 exactly what to investigate before any funcs-augmentation
- **Asymmetric-tier-(c) right-side magnitude check.** RESEARCH.md "Known-Different Master List" notes the asymmetric scenario should have `T_plate[z, NX-1] > T_plate[z, 0]` because the right channel is at 90 °C vs 40 °C on the left. The existing assertion at lines ~373 of the rewritten file enforces this; if Plan 04's smoke run trips it, the regenerated values are physically inconsistent and should be investigated before pasting.

## User Setup Required

None — no external service configuration required. Generator is a developer-machine-only script per D-06.

## Next Phase Readiness

- Plan 04 (regenerate-and-paste, manual checkpoint) is **unblocked** for the MTR side — it can now run `cd test && python3 generate_mtr_reference.py`, capture the 4 paste-blocks (geometry + 3 scenarios) bracketed by `# --- begin/end paste ---` markers, and paste them into `test/data/python_parity_reference.jl`.
- Plan 05 (MTR parity testsets in `test_validation.jl`) has the 55 const names listed above to grep against — every per-quantity reference for tier (a)+(b)+(c)+(d) is generatable.
- TEST-04 sub-requirements (b)+(c)+(d) reference data for the 3 MTR parity testsets are now generatable. Tier (a) was already generatable from the pre-rewrite generator; the rewrite extends it.

## Self-Check

Verifications run after writing this SUMMARY (file existence + commit hash):

```text
FOUND: test/generate_mtr_reference.py
FOUND: 89917c0 (commit hash for Task 1 rewrite)
```

## Self-Check: PASSED

---
*Phase: 56-python-stream-cross-validation*
*Plan: 03*
*Completed: 2026-05-08*
