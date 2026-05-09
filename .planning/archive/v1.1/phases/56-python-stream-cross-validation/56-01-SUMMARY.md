---
phase: 56-python-stream-cross-validation
plan: 01
subsystem: testing
tags: [parity-harness, validation, julia, python-stream, drift-report]

# Dependency graph
requires:
  - phase: 55-composition-helpers-examples-test-suite
    provides: test_validation.jl placeholder (this plan ships its parity-harness machinery)
provides:
  - test/parity_helpers.jl (parity-harness machinery file consumed by test_validation.jl)
  - ParityRow struct + parity_check tier-binning + print_drift_table + append_csv reporting + 5 assert_equivalence_* gates
  - Tier constants (TIER_CLEAN/TIER_GRAY/TIER_FAIL) per D-03
  - 4 PYTHON_*_AT_REF placeholder constants marked REGENERATE for Plan 04 to update
affects:
  - 56-04 (regenerate-and-paste step that replaces REGENERATE placeholders with actual Python values)
  - 56-05 (rewrites test_validation.jl parity testsets to use this harness)

# Tech tracking
tech-stack:
  added: []  # stdlib-only (Printf, DelimitedFiles, Test)
  patterns:
    - "Tier-binned drift reporting (CLEAN ≤1e-6 / GRAY <hard_ceiling / FAIL ≥hard_ceiling)"
    - "Long-format CSV with %.10e numeric precision (10 sig figs above KINSOL reltol=1e-6)"
    - "Pre-parity equivalence checklist gates assert_equivalence_*"
    - "REGENERATE marker convention for Plan-04-driven constant replacement"

key-files:
  created:
    - test/parity_helpers.jl
  modified: []

key-decisions:
  - "Helper file is NOT registered in test/runtests.jl — it is included by test_validation.jl in Plan 05 only"
  - "PYTHON_*_AT_REF reference constants embedded as PLACEHOLDER values; Plan 04 replaces them via grep on REGENERATE marker (6 occurrences)"
  - "dittus_boelter and blasius_friction reached via STREAM.* prefix despite being exported by STREAM (lines 46-47 of src/STREAM.jl) — explicit-source convention for the equivalence checklist"
  - "Zero-handling in parity_check: python_ref==0.0 → rtol falls back to abs_err (rtol on zero denominator is undefined)"

patterns-established:
  - "ParityRow 9-field struct: (scenario, qid, julia_val, python_ref, abs_err, rtol, tier, hard_ceiling, note)"
  - "Tier symbols (:CLEAN, :GRAY, :FAIL) — comparing with == against TIER_* constants"
  - "Comma-free 'note' field (CSV writer does not escape) — caller responsibility"

requirements-completed: [TEST-04]  # Phase 56 TEST-04 sub-deliverables (e) drift-report machinery and (f) equivalence checklist

# Metrics
duration: ~4min
completed: 2026-05-08
---

# Phase 56 Plan 01: Parity-Harness Machinery Summary

**Stdlib-only parity-harness data spine — ParityRow struct, tier-binned parity_check, drift-table + CSV reporters, and 5 pre-parity equivalence-checklist gates — shipped as test/parity_helpers.jl, ready for Plan 05 testsets after Plan 04 regenerates the Python reference constants.**

## Performance

- **Duration:** ~4 min
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- Created `test/parity_helpers.jl` (274 lines, ≥80 required) with the full parity-harness machinery in 6 sections: tier constants, ParityRow struct, parity_check binning, print_drift_table emitter, append_csv writer, REGENERATE-marked reference constants, and 5 assert_equivalence_* gate functions.
- Verified tier-binning matches D-03 boundaries (identity → CLEAN, 0.1% drift → GRAY, 5% drift → FAIL, zero-on-both → CLEAN) via cold-start `julia --project=. -e ...` smoke (worktree mode bypasses the Revise+DaemonMode daemon per CLAUDE.md).
- Confirmed CSV writer produces a non-empty long-format file with %.10e precision.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create test/parity_helpers.jl** — `f7c315b` (feat)
2. **Task 2: Smoke-load test/parity_helpers.jl** — _no commit (read-only smoke; plan instructs "Do NOT modify test/parity_helpers.jl in this task")_

## Files Created/Modified

- `test/parity_helpers.jl` (NEW, 274 lines) — Parity-harness data spine: ParityRow struct, parity_check tier-binning, print_drift_table + append_csv reporters, 5 assert_equivalence_* equivalence-checklist gates, and 4 PYTHON_*_AT_REF placeholder reference-constant tuples for Plan 04 to regenerate.

## Function/Struct Signatures Shipped (for Plan 05 reference)

```julia
# Section 1 — tier constants
const TIER_CLEAN = :CLEAN
const TIER_GRAY  = :GRAY
const TIER_FAIL  = :FAIL

# ParityRow — 9 fields
struct ParityRow
    scenario     :: String
    qid          :: String
    julia_val    :: Float64
    python_ref   :: Float64
    abs_err      :: Float64
    rtol         :: Float64
    tier         :: Symbol
    hard_ceiling :: Float64
    note         :: String
end

# Section 2 — per-quantity check
parity_check(scenario::String, qid::String,
             julia_val::Real, python_ref::Real;
             hard_ceiling::Float64=0.02,
             gray_floor::Float64=1e-6,
             note::String="")::ParityRow

# Section 3 — stdout drift table
print_drift_table(rows::Vector{ParityRow}; io::IO=stdout)

# Section 4 — long-format CSV writer
append_csv(path::AbstractString, rows::Vector{ParityRow}; truncate::Bool=false)

# Section 5 — reference temperatures (placeholders; REGENERATE in Plan 04)
const REF_T_K = (313.15, 343.15, 373.15)
const PYTHON_RHO_AT_REF = (995.7654, 977.7654, 958.4321)   # — REGENERATE
const PYTHON_CP_AT_REF  = (4178.123, 4187.456, 4216.789)   # — REGENERATE
const PYTHON_MU_AT_REF  = (6.535e-4, 4.041e-4, 2.835e-4)   # — REGENERATE
const PYTHON_K_AT_REF   = (0.6294,   0.6620,   0.6783)     # — REGENERATE

# Section 6 — equivalence-checklist gates
assert_equivalence_fluid_props(; rtol::Float64=1e-12)
assert_equivalence_dittus_boelter(; rtol::Float64=1e-12)
assert_equivalence_blasius(; rtol::Float64=1e-12)
assert_equivalence_geometry(geom, expected_Dh, expected_A,
                            expected_wet_perim, expected_heated_parts;
                            rtol::Float64=1e-12)
assert_equivalence_anchors(; expected_P_abs::Float64=1.0e5)
```

## Names of PYTHON_*_AT_REF Placeholder Constants (for Plan 04 regeneration)

Plan 04 must regenerate these 4 tuples by running the rewritten Python generator and pasting the values. Locate them via `grep -n REGENERATE test/parity_helpers.jl` (6 hits — one per constant tuple plus the regeneration block header and the in-comment note).

| Constant | Type | Anchor temperatures (REF_T_K) | Units |
|----------|------|-------------------------------|-------|
| `PYTHON_RHO_AT_REF` | NTuple{3,Float64} | (313.15, 343.15, 373.15) K | kg/m^3 |
| `PYTHON_CP_AT_REF`  | NTuple{3,Float64} | (313.15, 343.15, 373.15) K | J/(kg·K) |
| `PYTHON_MU_AT_REF`  | NTuple{3,Float64} | (313.15, 343.15, 373.15) K | Pa·s |
| `PYTHON_K_AT_REF`   | NTuple{3,Float64} | (313.15, 343.15, 373.15) K | W/(m·K) |

The placeholder values currently embedded are sufficient for `include("test/parity_helpers.jl")` to load cleanly, but `assert_equivalence_fluid_props()` will fail at rtol=1e-12 against them — that is intentional. Plan 05's parity testsets call assert_equivalence_fluid_props before each parity comparison; until Plan 04 has regenerated the constants, those testsets hard-abort, forcing the regenerate-and-paste step to actually happen before downstream parity comparisons run.

## dittus_boelter / blasius_friction Import Verdict

**Verified during execution:** both functions ARE exported by STREAM (`src/STREAM.jl` lines 46-47 — they appear inside the `export dittus_boelter, blasius_friction, ...` list). The plan's `<read_first>` step was a precaution; the actual exports list confirms they are part of the public API.

**Decision:** keep `STREAM.dittus_boelter(...)` / `STREAM.blasius_friction(...)` prefix in `assert_equivalence_dittus_boelter` / `assert_equivalence_blasius` (rather than relying on the bare imported names) for explicit-source clarity. The equivalence checklist asserts on the CORRELATION SOURCE — the `STREAM.` prefix makes it obvious which module-level definition is being audited and resists future shadowing in test scope.

## Decisions Made

- **Followed plan as specified.** No deviations.
- Confirmed via `grep -n 'export' src/STREAM.jl` that `dittus_boelter` and `blasius_friction` ARE exported (lines 46-47); kept `STREAM.*` prefix anyway for explicit-source readability — see "Import Verdict" above.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The smoke test triggered a one-time package precompile (`9293.2 ms ✓ STREAM`) — that is a fresh-worktree artifact (worktree-isolated executors bypass the daemon per CLAUDE.md "Performance — Daemon dev loop"). Subsequent invocations from the same worktree hit the precompile cache.

## Self-Check: PASSED

Verification commands ran successfully:

```text
FILE EXISTS
parity_check OK
ParityRow OK
print_drift_table OK
append_csv OK
fluid_props OK
dittus_boelter OK
blasius OK
geometry OK
anchors OK
REGENERATE count: 6
Line count: 274
export count: 0
```

Smoke test stdout:
```text
[Plan 56-01 smoke] parity_helpers.jl loaded and core functions behave correctly
```

Commit `f7c315b` is reachable on branch `worktree-agent-aebf1244f10a36e2c` (verified via `git log`).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **Plan 02 (Python generator rewrite)** can proceed independently — does not depend on this plan's output.
- **Plan 04 (regenerate-and-paste reference constants)** has clear targets: search for `REGENERATE` in `test/parity_helpers.jl` (6 hits) and replace the 4 PYTHON_*_AT_REF tuples with values emitted by the rewritten Python generators.
- **Plan 05 (rewrite test_validation.jl parity testsets)** can `include("test/parity_helpers.jl")` and immediately use `parity_check`, `print_drift_table`, `append_csv`, plus the 5 `assert_equivalence_*` gates. Until Plan 04 has run, the fluid-props gate will hard-abort against placeholder constants — that is the intentional forcing function for the regenerate-and-paste step.

---
*Phase: 56-python-stream-cross-validation*
*Completed: 2026-05-08*
