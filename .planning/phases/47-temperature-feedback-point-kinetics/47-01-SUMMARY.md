---
phase: 47
plan: 01
subsystem: point-kinetics
tags: [temperature-feedback, point-kinetics, mtk, symbolic-unknowns, composition-helper]
dependency_graph:
  requires:
    - "46-02 (callable PointKinetics + ReactivityController)"
  provides:
    - "temp_worth/ref_temp kwargs on callable PointKinetics constructor"
    - "connect_temperature_feedback composition helper"
  affects:
    - "Phase 49 (SCRAM wiring — will use T_source unknowns)"
tech_stack:
  added: []
  patterns:
    - "Runtime-named array unknowns via @variables $(var_sym)(t)[1:n_flat]"
    - "Alpha/Tref inlined as constants in symbolic equations (same as power_shape in HeatDiffusion)"
    - "Composition helper returning Vector{Equation} (same pattern as symmetric_plate)"
key_files:
  created: []
  modified:
    - src/components/point_kinetics.jl
    - src/composition/helpers.jl
    - src/STREAM.jl
    - test/test_point_kinetics.jl
decisions:
  - "ndims(T_sym) dispatches on component T shape (authoritative) not alpha shape (may be scalar)"
  - "ref_temp key lookup uses get(ref_dict, comp, 0.0) for missing-key default zero"
  - "feedback_expr=0 (Julia literal Int) promotes to Num on first alpha*T_source addition"
  - "_flatten_weights shared between alpha and ref_temp calls; for ref_temp, scalar 0.0 broadcasts correctly"
metrics:
  duration_minutes: 65
  completed_date: "2026-04-05"
  tasks_completed: 2
  files_modified: 4
---

# Phase 47 Plan 01: Temperature Feedback PointKinetics Summary

Implemented per-cell temperature feedback for `PointKinetics`: `temp_worth` + `ref_temp` kwargs on the callable constructor create per-component flattened `T_source` unknowns and inline alpha/Tref as symbolic constants, plus a `connect_temperature_feedback` composition helper that binds `pk.T_source_<name>[j]` to `comp.T[j]` (1D) or `comp.T[jz,jx]` (2D row-major).

## Task Commits

| Task | Commit | Files | Description |
|------|--------|-------|-------------|
| 1 | `6087db5` | point_kinetics.jl, test_point_kinetics.jl | _flatten_weights + temp_worth/ref_temp kwargs |
| 2 | `6627873` | helpers.jl, STREAM.jl, test_point_kinetics.jl | connect_temperature_feedback + export |

## Implementation Details

### Task 1: _flatten_weights + Constructor Extension

**New code location:** `src/components/point_kinetics.jl`

- `_flatten_weights` helper added at line 25 (after constants block, before docstring)
  - Handles scalar broadcast, 1D vector, 2D matrix (row-major for HeatDiffusion)
  - ArgumentError on shape mismatch (T-47-01 mitigation)
- `PointKinetics(rho_c_fn::Any; ...)` callable constructor at line 206 extended with:
  - `temp_worth=nothing` and `ref_temp=nothing` new kwargs
  - Phase 47 feedback-building block at lines 230-249:
    - `T_source_vars = Num[]` accumulator
    - `feedback_expr = 0` (promotes to Num on first symbolic addition)
    - Per-component loop: `_flatten_weights`, `get(ref_dict, comp, 0.0)`, `@variables $(var_sym)(t)[1:n_flat]`
  - `feedback_expr` added to power ODE (line 251), dPdt obs (line 262), reactivity obs (line 263)
  - `T_source_vars...` appended to System unknowns list (line 266)

**@variables splice-interpolation verification (Pitfall 6):**
`only(@variables $(var_sym)(t)[1:n_flat])` works correctly in function scope — verified by TF-02a/b/c tests that confirm the T_source unknowns appear in `unknowns(pk)`. The `only()` wrapper is required because `@variables` returns a tuple and the array form produces a single-element tuple containing the symbolic array.

### Task 2: connect_temperature_feedback

**New code location:** `src/composition/helpers.jl` lines 278-328

- Follows the `symmetric_plate` pattern: takes uncompiled System instances, returns `Vector{Equation}`
- Dispatches on `ndims(T_sym)` (introspects the component's T shape — authoritative)
  - 1D: `pk_T_source[j] ~ T_sym[j]` for j in 1:n
  - 2D: `pk_T_source[(jz-1)*nx+jx] ~ T_sym[jz,jx]` for jz in 1:nz, jx in 1:nx (row-major D-03)
- `getproperty(comp, :T)` reads the component's existing T symbolic (D-05 — no component modification)
- `getproperty(pk, Symbol(:T_source_, cname))` accesses the PK T_source array by name

**Export:** `connect_temperature_feedback` added to `src/STREAM.jl` line 40.

## Deviations from Plan

None — plan executed exactly as written.

The only deviation from RESEARCH.md code examples was not using the `T_source_by_comp`/`alpha_flat_by_comp`/`Tref_flat_by_comp` intermediate dicts (Pattern 1) — instead, the feedback_expr was built inline in the same loop iteration. This is simpler and equally correct because `feedback_expr` accumulates all contributions regardless.

## Test Results

All 1364 tests pass (previous 1344 + 20 new TF tests):

| Test | Description | Status |
|------|-------------|--------|
| TF-01a | Default no temp_worth gives 7 state vars | PASS |
| TF-01b | temp_worth=nothing gives 7 state vars | PASS |
| TF-02a | Scalar alpha broadcasts to 5 channel cells (7+5=12 unknowns) | PASS |
| TF-02b | 1D vector per channel cell | PASS |
| TF-02c | 2D matrix for HeatDiffusion (3*2=6 cells, 7+6=13 unknowns) | PASS |
| TF-02d | Shape mismatch raises ArgumentError (wrong length vector) | PASS |
| TF-02e | Shape mismatch raises ArgumentError (wrong matrix shape) | PASS |
| TF-03a | ref_temp omitted — constructor succeeds | PASS |
| TF-03b | ref_temp missing key — constructor succeeds | PASS |
| TF-03c | ref_temp=nothing — constructor succeeds | PASS |
| TF-04a | 1D channel generates 5 binding equations | PASS |
| TF-04b | 2D HeatDiffusion generates 6 binding equations (row-major) | PASS |
| TF-04c | Multiple components: 5+6=11 equations | PASS |
| TF-04e | connect_temperature_feedback exported from STREAM | PASS |

## Threat Model Coverage

- T-47-01 (shape mismatch): `ArgumentError` raised at construction time — verified by TF-02d/TF-02e
- T-47-02 (information disclosure): N/A — pure in-process symbolic math
- T-47-03 (symbolic growth): accepted — n_cells <= 100 for realistic cores

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- `src/components/point_kinetics.jl` — modified, exists
- `src/composition/helpers.jl` — modified, exists
- `src/STREAM.jl` — modified, exists
- `test/test_point_kinetics.jl` — modified, exists
- Commit `6087db5` — exists
- Commit `6627873` — exists
- 1364 tests pass (verified by `julia --project=. test/test_point_kinetics.jl`)
