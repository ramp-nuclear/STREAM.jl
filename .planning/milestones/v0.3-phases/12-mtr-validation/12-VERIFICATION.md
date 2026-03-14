---
phase: 12-mtr-validation
verified: 2026-03-14T09:00:00Z
status: gaps_found
score: 4/5 must-haves verified
re_verification: false
gaps:
  - truth: "Steady-state T_outlet, mdot, and T_plate center match Python STREAM within 1% (VAL-01, VAL-03)"
    status: failed
    reason: >
      The PLAN must-have explicitly requires 1% tolerance against Python STREAM reference values.
      The REQUIREMENTS.md text for VAL-01 states 'matching Python STREAM reference within 1%'.
      The actual tests use physics-based energy balance assertions (T_out > T_in, symmetry,
      T_rise = P/(mdot*cp) within 5%) because the two codebases use geometrically incompatible
      heating areas: Python STREAM uses EffectivePipe.circular (one-sided heated perimeter) while
      Julia uses pi*Dh/2 per face (two-sided). The deviation was documented and justified in the
      SUMMARY, but it means the stated goal of '1% agreement with Python STREAM' is not met.
      VAL-02 has no quantitative reference value in either the plan or tests (only qualitative
      asymmetry check), which does pass. VAL-03 similarly lacks 1% comparison.
    artifacts:
      - path: "test/runtests.jl"
        issue: >
          VAL-01 testset (line 832) and VAL-03 testset (line 983) contain no val01_T_outlet_l_ref
          or val03_T_outlet_ref variables. The Plan 02 must_have artifact check for
          'val01_T_outlet_l_ref' is absent. Python reference constants were obtained but
          deliberately not used as test tolerances due to geometry incompatibility.
    missing:
      - >
        Resolution decision: either (a) fix the Julia ChannelAndContacts heating area to match
        Python STREAM's one-sided circular pipe model and then add 1% tolerance tests against
        the reference constants, OR (b) update REQUIREMENTS.md and ROADMAP to officially restate
        VAL-01/VAL-03 as 'physics-based validation (energy balance within 5%)' rather than
        '1% match to Python STREAM', then re-run this verification against the updated goal.
        Option (b) is lower-effort if the geometry difference is intentional for Julia-STREAM.
---

# Phase 12: MTR Validation — Verification Report

**Phase Goal:** Coupled HeatDiffusion + two ChannelAndContacts in MTR geometry (cladding+meat+cladding,
two water channels) solves and matches Python STREAM reference outputs within 1%, including an
asymmetric heating case that confirms left/right coupling direction is correct.

**Verified:** 2026-03-14T09:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | `test/generate_mtr_reference.py` exists, is syntactically valid, imports `plate` and `one_sided_connection` from `stream.composition.mtr_geometry`, and covers VAL-01/02/03 | VERIFIED | File exists at 290 lines; `from stream.composition.mtr_geometry import plate, one_sided_connection` at line 60; three scenario blocks at lines 164-266 |
| 2  | HDIFF-03 gap test is in runtests.jl Phase 12 testset and passes (center-only power cell is hottest) | VERIFIED | `@testset "HDIFF-03-gap"` at line 780; uses `[0.0, 1.0, 0.0]` power_shape; asserts `T_center > T_left + 0.01` and `T_center > T_right + 0.01` |
| 3  | VAL-01 (symmetric MTR) and VAL-02 (asymmetric) integration tests exist in Phase 12 testset with full two-loop topology (HeatDiffusion + 2x ChannelAndContacts) | VERIFIED | `@testset "VAL-01"` at line 832 and `@testset "VAL-02"` at line 915; both assemble nz=10, nx=3, two loops, `getproperty(hd, Symbol(:thermal_left, i))` wiring, `mtkcompile(sys; fully_determined=false)`, `sol.retcode == ReturnCode.Success` |
| 4  | VAL-03 (one-sided) integration test exists with only thermal_left connected; thermal_right adiabatic (Q_flow=0) verified | VERIFIED | `@testset "VAL-03"` at line 983; single-loop composition; adiabatic assertion loop at lines 1042-1045 checking `right_syms[i].Q_flow` within `atol=1e-6` |
| 5  | T_outlet, mdot, and T_plate center match Python STREAM within 1% (VAL-01 and VAL-03) | FAILED | No reference constants appear in runtests.jl. Tests assert physics-based conditions only (T_out > T_in, symmetry within 0.1%, energy balance within 5%). Python STREAM reference values were obtained but declared incompatible due to geometry difference (see Geometry Incompatibility section below). |

**Score: 4/5 truths verified**

---

### Required Artifacts

#### Plan 01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/generate_mtr_reference.py` | Python STREAM MTR reference script covering VAL-01/02/03; exports T_outlet_K, mdot, T_plate_center_K | VERIFIED | Exists (290 lines); covers all three scenarios; prints reference constants in paste-ready format; sanity asserts present |
| `test/runtests.jl` | Phase 12 testset block with HDIFF-03 gap test | VERIFIED | `@testset "STREAM Phase 12 Tests"` at line 773; HDIFF-03-gap test at line 780 |

#### Plan 02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/runtests.jl` | VAL-01, VAL-02, VAL-03 `@testset` blocks inside Phase 12 testset | VERIFIED | All three tests present at lines 832, 915, 983 |
| `test/runtests.jl` | Contains `val01_T_outlet_l_ref` (Plan 02 must_have `contains` check) | FAILED | String absent from file. Tests were redesigned to use physics assertions instead of hardcoded Python reference constants. |
| `src/components.jl` | Q_flow sign fixed: `k*(T_bc - T_plate)/(dx/2)` | VERIFIED | `_diffusion_eqs` at lines 407-414 uses `thermal_left[i].T - T[i, 1]` formula (correct: negative when plate hotter than boundary) |
| `src/fluids.jl` | `sqrt(max(0.0, ...))` guard in `cp_water` | VERIFIED | Line 39: `return sqrt(max(0.0, (A + C * T_C) / (1 + B * T_C + D * T_C^2))) * 1000.0` |
| `src/solvers.jl` | `build_initializeprob=false` parameter in `solve_steady` | VERIFIED | Lines 102-105: kwarg present with default `false`; passed to KINSOL |

---

### Key Link Verification

#### Plan 01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `test/generate_mtr_reference.py` | `stream.composition.mtr_geometry` | `plate()` and `one_sided_connection()` API calls | VERIFIED | Import at line 60; `plate()` used at lines 171, 212; `one_sided_connection()` used at line 244 |
| `test/runtests.jl (HDIFF-03 gap)` | `HeatDiffusion power_shape parameter` | `power_shape = reshape([0.0, 1.0, 0.0], 1, 3)` | VERIFIED | Line 792: `ps = reshape([0.0, 1.0, 0.0], nz, nx)` (pattern changed from plan's `[0.5, 0.0, 0.5]` due to physics correction — documented) |

#### Plan 02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `test/runtests.jl (VAL-01/02)` | `HeatDiffusion.thermal_left[i]` | `getproperty(hd, Symbol(:thermal_left, i)) connect to cac_l.thermal_left[i]` | VERIFIED | Lines 865-866, 944-945; pattern `getproperty(hd, Symbol(:thermal_left, i))` confirmed; 24 occurrences of the pattern across file |
| `test/runtests.jl (VAL-01/02)` | `HeatDiffusion.thermal_right[i]` | `connect to cac_r.thermal_left[i]` | VERIFIED | Lines 867-868, 946-947; right channel sees plate on ITS left; pattern `getproperty(hd, Symbol(:thermal_right, i))` wired to `getproperty(cac_r, Symbol(:thermal_left, i))` |
| `test/runtests.jl (VAL-03)` | Adiabatic `thermal_right` | `fully_determined=false` | VERIFIED | Line 1013: `mtkcompile(sys; fully_determined=false)`; adiabatic Q_flow=0 asserted at lines 1042-1045 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VAL-01 | 12-01-PLAN, 12-02-PLAN | Coupled HeatDiffusion + two ChannelAndContacts in MTR geometry matches Python STREAM within 1% | PARTIAL | Test exists and passes physics checks. The 1% tolerance against Python STREAM is not implemented due to documented geometry incompatibility. REQUIREMENTS.md marks it `[x]` Complete — but the requirement text says "within 1%" which is not verified. |
| VAL-02 | 12-01-PLAN, 12-02-PLAN | Asymmetric heating produces correct non-symmetric plate temperature profile | SATISFIED | `@testset "VAL-02"` at line 915 asserts `T_plate_right_col > T_plate_left_col` and `sol.retcode == ReturnCode.Success`; qualitative physics verified |
| VAL-03 | 12-01-PLAN, 12-02-PLAN | One-sided coupling solves correctly with unconnected face adiabatic | PARTIAL | Test exists; adiabatic Q_flow=0 verified; energy balance within 5% verified. The 1% Python STREAM tolerance is absent for same geometry reasons as VAL-01. |

**Orphaned Requirements (Phase 12 in REQUIREMENTS.md but not in any plan):** None. All three VAL IDs appear in both plan frontmatter sections.

---

### Geometry Incompatibility: Core Finding

The SUMMARY for Plan 02 documents a deliberate decision not to use Python STREAM reference values.
The root cause is a genuine model difference:

- **Python STREAM:** `EffectivePipe.circular(D=0.01)` gives a heated perimeter of `pi*D` on the
  left channel face only (the channel sees the fuel on one side; the other side is a wall).
- **Julia STREAM:** `ChannelAndContacts` uses `pi*Dh/2` per face, meaning BOTH faces heat
  the fluid symmetrically.

This is not a bug — it is a design difference that must be resolved for the "within 1%" goal to
be achievable. With two-sided heating, each channel receives approximately twice as much heat
flux per face area as the Python model's single-sided channel does, making the outlet temperatures
physically incomparable.

The Python reference constants collected in Plan 01 were:

| Constant | Value | Unit |
|----------|-------|------|
| val01_T_outlet_l | 313.1500 | K |
| val01_T_outlet_r | 313.9996 | K |
| val01_mdot_l | 0.597697 | kg/s |
| val01_mdot_r | 0.598400 | kg/s |
| val01_T_plate_center | 317.5816 | K |
| val02_T_plate_center | 342.6925 | K |
| val03_T_outlet | 314.0473 | K |
| val03_mdot | 0.598428 | kg/s |
| val03_T_plate_center | 317.8484 | K |

These constants are not used in any Julia test.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/runtests.jl` | 835-836 | Comment: "Python reference values are NOT applicable. Instead, validate physical correctness" | Info | Intended documentation of a design decision; not a placeholder or stub |

No TODO/FIXME/placeholder patterns found in Phase 12 test blocks. No empty implementations.
No `return null` or stub returns in modified source files.

---

### Human Verification Required

No human verification items for automated assertions. However, one design question requires
human judgment:

#### 1. Geometry Compatibility Decision

**Test:** Decide whether Julia-STREAM's `ChannelAndContacts` should match Python STREAM's
single-sided heating model or whether the requirement text should be updated to reflect the
physics-based validation strategy.

**Expected:** Either (a) Julia uses one-sided heating and 1% numeric tolerance tests pass,
OR (b) REQUIREMENTS.md VAL-01/VAL-03 text is updated from "within 1%" to "physics-based
validation (energy balance within 5%)" and the traceability is re-verified.

**Why human:** This is an architectural/specification decision, not a code defect. The SUMMARY
documents the incompatibility clearly. Whether to align the models or relax the requirement
cannot be determined programmatically.

---

### Gaps Summary

One gap blocks the stated phase goal:

**The "within 1%" validation against Python STREAM** (the explicit, named goal in ROADMAP.md
and REQUIREMENTS.md VAL-01/VAL-03) is not implemented. The Julia test suite validates correct
physics behavior — energy conservation, symmetry, coupling direction, adiabatic defaults — but
does not compare numerically to Python STREAM output.

This gap stems from a documented architectural difference: Julia `ChannelAndContacts` uses
two-sided symmetric heating (`pi*Dh/2` per face), while Python STREAM uses single-sided
circular pipe heating. The Python reference constants were obtained and are recorded in
`12-01-SUMMARY.md`, but were not used in tests.

The gap can be closed in two ways:
1. **Align heating model:** Change Julia `ChannelAndContacts` to match Python STREAM's one-sided
   geometry for the MTR validation case, then add `isapprox(...; rtol=0.01)` tolerance tests.
2. **Update requirements:** Officially restate VAL-01/VAL-03 in REQUIREMENTS.md to reflect
   physics-based validation rather than numeric 1% Python parity, then re-verify.

The HDIFF-03 gap test, VAL-02 asymmetry test, VAL-03 adiabatic right face test, and all
wiring / topology assembly code are fully working and verified.

---

_Verified: 2026-03-14T09:00:00Z_
_Verifier: Claude (gsd-verifier)_
