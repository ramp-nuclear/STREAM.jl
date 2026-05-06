---
phase: 49-full-loop-integration-validation
reviewed: 2026-04-09T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - src/examples.jl
  - src/STREAM.jl
  - test/test_examples.jl
  - test/test_validation.jl
findings:
  critical: 0
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 49: Code Review Report

**Reviewed:** 2026-04-09
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Phase 49 adds `build_loop_pk` to `src/examples.jl` plus LOOP-01..04 integration tests
in `test/test_examples.jl` and VAL-PK-01..03 validation tests in `test/test_validation.jl`.
The PK+TH coupling design is sound: the MTK callable parameter pattern is applied
consistently, the `_resolve_tw` / `fb_components` guard correctly avoids wiring feedback
unknowns that were never declared, and the IC construction follows the established
`point_kinetics_steady_state` helper.

Five warnings are raised: a dropped docstring parameter, a test that does not verify
solver success before asserting physics, a fragile parameter-order assumption for
extracting the callable parameter, an untested path in the fallback IC override loop,
and an incomplete SCRAM check. Three info items cover dead parameters, test naming
collision, and a magic constant.

No security issues were found. No logic errors that would produce silently wrong
physics results were found.

---

## Warnings

### WR-01: `threshold` parameter silently dropped from `build_loop_lof_bypass` signature

**File:** `src/examples.jl:317,351`
**Issue:** The docstring at line 317 documents a `threshold` parameter (`- \`threshold\`: Flapper trigger threshold [kg/s] (default 0.01)`), but the actual function signature at line 351 does not include it. The `Flapper` component is constructed without a trigger threshold, and the docstring advertises a non-existent interface. A caller following the docstring will get a `MethodError` or silently no-op.
**Fix:** Either add the `threshold` kwarg to the function signature and pass it through to `Flapper`, or remove the parameter from the docstring. Since `build_loop_lof_bypass` is not in scope for Phase 49, the docstring fix is the minimal safe correction:

```julia
# Remove this line from the docstring:
# - `threshold`: Flapper trigger threshold [kg/s] (default 0.01)
```

Or add the kwarg if `Flapper` accepts it:

```julia
function build_loop_lof_bypass(;
    ...
    threshold = 0.01,
    dt_ramp   = 5.0,
)
    ...
    @named flapper = Flapper(dt=dt_ramp, threshold=threshold)
```

---

### WR-02: LOOP-02 does not verify solver `retcode` before asserting physics invariants

**File:** `test/test_examples.jl:35-39`
**Issue:** `solve_transient` is called and `P_trace` is extracted without checking `sol.retcode`. If the solver fails (stiff ODE, step rejection, etc.), `P_trace` may be partially populated with `NaN`/`Inf` or truncated to fewer than 200 points. The `all(isfinite, P_trace)` check would catch NaN but not a truncated trace with all-valid-but-wrong values from a failed integration.

```julia
sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
# No retcode check here
P_trace = sol[ssys.pk.P, :]
```

**Fix:** Add a retcode assertion before the physics checks:

```julia
sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
@test sol.retcode == ReturnCode.Success
P_trace = sol[ssys.pk.P, :]
```

---

### WR-03: LOOP-03 does not verify solver `retcode` before asserting physics invariants

**File:** `test/test_examples.jl:65-72`
**Issue:** Same pattern as WR-02. `sol` is not checked for `ReturnCode.Success` before reading `P_trace`. A solver failure would produce a truncated or NaN-filled trace. `all(isfinite, P_trace)` is a partial guard but does not distinguish success from a cleanly-terminated failed solve.

```julia
sol = solve_transient(ssys, ic, t_arr; tstops=[t_step], maxiters=1_000_000)
# No retcode check
P_trace = sol[ssys.pk.P, :]
```

**Fix:**

```julia
sol = solve_transient(ssys, ic, t_arr; tstops=[t_step], maxiters=1_000_000)
@test sol.retcode == ReturnCode.Success
P_trace = sol[ssys.pk.P, :]
```

---

### WR-04: `T_wall_sym = last(parameters(ssys))` is a fragile ordering assumption

**File:** `test/test_validation.jl:55`
**Issue:** The callable parameter for `T_wall` is retrieved by assuming it is the *last* element of `parameters(ssys)`:

```julia
T_wall_sym = last(parameters(ssys))   # T_wall_callable is the last parameter
```

MTK does not guarantee parameter ordering across versions. A future MTK upgrade or a change in the system composition order could silently push a different parameter to the last position, causing `T_wall_sym` to be bound to the wrong symbol. The wrong binding would produce a solver `KeyError` or a silently incorrect transient (constant wall temperature from a numeric parameter misidentified as the callable).

**Fix:** Retrieve the parameter by name using `ModelingToolkit.getproperty` on the compiled system, which is stable:

```julia
T_wall_sym = ssys.sys.T_wall_callable
```

This is the canonical MTK idiom for accessing a named callable parameter and is immune to parameter reordering.

---

### WR-05: SCRAM test does not assert `sol.retcode` is `Terminated` (only checks `t[end] < 10`)

**File:** `test/test_examples.jl:106`
**Issue:** LOOP-04 checks `sol.t[end] < 10.0` as evidence that the SCRAM callback terminated the solver early. However, if the solver naturally reaches the end of the time window faster than expected (e.g., due to a stiff error exit), `sol.t[end]` could also be small. The test would pass for the wrong reason.

Additionally, the test does not confirm that `sol.retcode` is the expected `ReturnCode.Terminated` that `DifferentialEquations.terminate!` produces.

```julia
@test sol.t[end] < 10.0            # terminated early
```

**Fix:** Strengthen the assertion:

```julia
@test sol.retcode == ReturnCode.Terminated   # DiffEq terminate! sets this
@test sol.t[end] < 10.0                      # early stop confirmed by time
```

---

## Info

### IN-01: `A_ch` is accepted but never used in `build_loop`, `build_loop_vertical`, `build_loop_transient`

**File:** `src/examples.jl:51,124,191`
**Issue:** All three pre-existing builders accept `A_ch = 7.85e-5` as a keyword argument but never reference it in the function body. It is a dead parameter that silently accepts user input and discards it, potentially causing confusion when a caller changes `A_ch` expecting it to affect the hydraulic area.

```julia
function build_loop(;
    ...
    A_ch     = 7.85e-5,   # accepted but never used
    ...
)
```

**Fix:** Remove the `A_ch` kwarg from the three signatures, or use it in `PipeGeometry_circular` if the intent was to override computed area:

```julia
function build_loop(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,
    T_wall   = 373.15,
)
```

Note: `build_loop_pk` does **not** have this issue — it constructs `PipeGeometry_rectangular` directly without an `A_ch` parameter.

---

### IN-02: Test label collision — two separate test groups both labelled `VAL-01` and `VAL-02`

**File:** `test/test_validation.jl:18,71 and 320,387`
**Issue:** `test_validation.jl` contains four top-level `@testset` blocks with conflicting names:

- Lines 18 and 71 are both `"VAL-01: ..."` (different content)
- Lines 36 and 387 are both `"VAL-02: ..."` (different content)

Julia's test runner allows duplicate `@testset` names; they run independently without error. However, duplicate names make CI output ambiguous — a failure in either `VAL-01` block is reported under the same label, making it hard to identify which test failed. The Phase 49 PK tests are inside a nested `"PointKinetics validation"` testset, which gives them a unique prefix, but the top-level MTR and Fourier blocks still clash.

**Fix:** Rename the earlier (MTR) top-level testsets with unambiguous prefixes:

```julia
@testset "MTR-VAL-01: Symmetric MTR — HeatDiffusion + two ChannelAndContacts" begin
@testset "MTR-VAL-02: Asymmetric MTR — right channel at 363.15 K inlet" begin
@testset "MTR-VAL-03: One-sided MTR — left channel only, thermal_right adiabatic" begin
@testset "HDIFF-VAL-01: HeatDiffusion transient — Fourier series validation" begin
@testset "HDIFF-VAL-02: Two-plate one-channel topology — both faces active" begin
```

---

### IN-03: Magic constant `0.2` for initial mdot IC in `build_loop_pk`

**File:** `src/examples.jl:557`
**Issue:** The initial condition for `rods.cac.inlet.mdot` is hardcoded to `0.2` kg/s:

```julia
ssys.rods.cac.inlet.mdot => 0.2,
```

This value is appropriate for the default `PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)` at `dP_pump=3.0e4`, but it is not derived from physics — it is an empirical guess. If a caller passes a different `dP_pump` or geometry (via future extension), this guess may be far off and cause KINSOL/transient initialization to fail. A comment explaining the origin would reduce future maintenance risk.

**Fix:** Add an inline comment:

```julia
ssys.rods.cac.inlet.mdot => 0.2,   # empirical mdot guess for default geom at dP=30 kPa
```

---

_Reviewed: 2026-04-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
