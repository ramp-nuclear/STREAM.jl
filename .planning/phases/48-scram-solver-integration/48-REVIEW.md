---
phase: 48-scram-solver-integration
reviewed: 2026-04-08T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - src/components/point_kinetics.jl
  - src/components/flapper.jl
  - src/STREAM.jl
  - src/examples.jl
  - test/test_flapper.jl
  - test/test_loss_of_flow.jl
  - test/test_point_kinetics.jl
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 48: Code Review Report

**Reviewed:** 2026-04-08
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

The phase introduces `SCRAMCondition`, `SCRAM_at_power`, `scram_callback`, and `flapper_callback` — a coherent set of integrator-callback factories built on `DifferentialEquations.ContinuousCallback`. The design is well-structured: pure-data condition structs, side-effect-free condition lambdas, and mutable-state only in the affect. The existing `Flapper` component and its callback factory are sound. Test coverage for the SCRAM path (SCRAM-01, SCRAM-02) and the Flapper path (FLAP-05, FLAP-06, LOF-01..03) is good.

Three warnings deserve attention before Phase 49 integration:

1. `scram_callback` reads `integrator.du[p_idx]` to obtain `dPdt`, but `dPdt` is declared `@observed` (not in the ODE state vector `u`). Reading it from `du` is fragile and may silently return the wrong value or a stale value after structural simplification.
2. `flapper_callback` is hardcoded to look up `ssys.flapper` by literal name, making it unusable when the `Flapper` subsystem is named anything other than `:flapper`.
3. `build_loop_lof_bypass` omits the `threshold` parameter from its public signature even though the docstring lists it, causing a mismatch between the documented API and the actual function.

---

## Warnings

### WR-01: `scram_callback` reads `dPdt` from `integrator.du` — observed variable not in `du`

**File:** `src/components/point_kinetics.jl:497-503`

**Issue:** The affect closes over `p_idx = ModelingToolkit.variable_index(integrator, p_sym)` and then reads `dPdt` as `integrator.du[p_idx]`. The code comment acknowledges this ("dPdt is @observed (not in ODE u vector)") but then asserts it is safe because `Dt(P) ~ ...` means `du[p_idx] IS dPdt`. This is only true when `P` is a plain ODE state and the index has not been changed by structural simplification (index reduction, variable aliasing). After `mtkcompile`, MTK may reorder variables, drop states via substitution, or apply Pantelides index-reduction so that the `du` slot indexed by `variable_index(integrator, p_sym)` is no longer `dP/dt` in the original sense. The `@observed` classification of `dPdt` (line 128/261) is specifically because it must NOT be read from the ODE `u`/`du` arrays. Reading it via `integrator.du` can silently return zero, NaN, or a spurious value depending on the solver's internal representation at the callback instant.

In the SCRAM-02 test, `change_state` is called but the `dPdt` value is passed only to the user's `state_machine` callable, not used by `SCRAMCondition` itself (which ignores `dPdt`). So the current test does not catch the error. Phase 49 integration of a `SCRAM_at_dPdt` variant would be silently wrong.

**Fix:** Use `integrator[dPdt_sym]` (symbolic indexing via `SymbolicIndexingInterface`) to evaluate the observed `dPdt` expression at the current state, the same way the condition lambda reads `integrator[p_sym]`. Capture the compiled `dPdt` symbolic at callback-construction time:

```julia
function scram_callback(p_sym::Num, ctrl; terminate = true)
    plimit = ctrl.state_machine.power_limit

    condition = (u, t, integrator) -> integrator[p_sym] - plimit

    affect! = function (integrator)
        P  = integrator[p_sym]
        dP = integrator[integrator.f.sys.dPdt]  # symbolic indexing for @observed
        change_state(ctrl, integrator.t, P, dP)
        terminate && DifferentialEquations.terminate!(integrator)
    end

    ContinuousCallback(condition, affect!)
end
```

Alternatively, accept a `dPdt_sym` keyword argument so the caller provides the correct compiled symbol.

---

### WR-02: `flapper_callback` is hardcoded to `ssys.flapper` — breaks when subsystem is renamed

**File:** `src/components/flapper.jl:99-116`

**Issue:** `flapper_callback` accesses the Flapper state with `ssys.flapper.T_open` and `ssys.flapper.ref_mdot` (lines 99, 104). If the user names their Flapper component anything other than `:flapper` (e.g., `@named valve = Flapper()`), the function will throw a `KeyError` at the property access on `ssys`. The docstring says "Must contain a Flapper subsystem accessible as `ssys.flapper`" — but this is an unnecessary restriction that contradicts the rest of the codebase, where callbacks and helpers work with the compiled symbolic directly.

```julia
# Current call site (examples.jl:384):
@named flapper = Flapper(dt=dt_ramp)
# Works only because the name matches the hardcoded ssys.flapper access.

# Would silently fail at runtime:
@named valve = Flapper(dt=dt_ramp)
cb = flapper_callback(ssys)  # ssys.flapper does not exist
```

**Fix:** Accept the symbolic variables as arguments (analogous to how `scram_callback` takes `p_sym` as an explicit argument), or at minimum accept a `name` kwarg:

```julia
function flapper_callback(ssys, T_open_sym, ref_mdot_sym; threshold = 0.01)
    T_open_idx   = ModelingToolkit.variable_index(ssys, T_open_sym)
    ref_mdot_sym = ref_mdot_sym   # already symbolic

    condition = (u, t, integrator) -> integrator[ref_mdot_sym] - threshold
    affect!   = (integrator) -> (integrator.u[T_open_idx] = integrator.t)

    ContinuousCallback(condition, nothing, affect!)
end
```

Call site becomes: `flapper_callback(ssys, ssys.valve.T_open, ssys.valve.ref_mdot)`.

---

### WR-03: `build_loop_lof_bypass` `threshold` parameter missing from function signature

**File:** `src/examples.jl:351-414`

**Issue:** The docstring for `build_loop_lof_bypass` (lines 338-340) lists `threshold` as an accepted keyword argument with default `0.01`, but the actual function signature at line 351 does not include `threshold`. The parameter is absent from the `function build_loop_lof_bypass(; ...)` argument list. The function hardcodes the threshold implicitly through the default value of `Flapper()` and then `flapper_callback` — but the caller has no way to change it via `build_loop_lof_bypass`. This makes the docstring misleading and the LOF test's use of a separate `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)` surprising (the build function and callback must be kept in sync manually).

```julia
# Docstring says this parameter exists:
# - `threshold`: Flapper trigger threshold [kg/s] (default 0.01)

# Actual signature (line 351-361):
function build_loop_lof_bypass(;
    n::Int    = 10,
    L_ch      = 1.0,
    D_ch      = 0.01,
    T_wall    = 373.15,
    T_inlet   = 313.15,
    L_over_A  = 1.75e5,
    g_acc     = 9.80665,
    R_ext     = 1.0e6,
    dt_ramp   = 5.0,
    # threshold is NOT here
)
```

**Fix:** Add `threshold = 0.01` to the signature and forward it to `Flapper`'s construction or return it alongside `ssys` so the caller can use a consistent value. Since `Flapper` itself does not store a threshold (threshold lives in the callback), the cleanest fix is to return `threshold` as part of a `NamedTuple` or document that callers must pass `threshold` consistently to `flapper_callback`. At minimum, remove `threshold` from the docstring to match the actual API.

---

## Info

### IN-01: `C_1`..`C_6` precursor initial conditions have no default values

**File:** `src/components/point_kinetics.jl:95-106`

**Issue:** In both `PointKinetics` constructors, `C_1(t)` through `C_6(t)` are declared without default initial values (lines 96-101 and 212-217). `P(t)` gets `= 1.0` but the six `C_k` do not. MTK will default-initialize them to zero, which is the trivial (P=0) fixed point. Every caller must explicitly pass all six `C_k` initial conditions, and if any are omitted the solve starts from a physically wrong state. The companion `point_kinetics_steady_state` helper exists to compute correct values, but its use is not enforced at construction time.

**Suggestion:** Add default IC expressions derived from the steady-state formula in the `@variables` block, so that `PointKinetics(rho=0.0)` is self-consistent without a separate IC call:

```julia
@variables begin
    P(t)   = 1.0
    C_1(t) = beta_1 / (lambda_1 * Lambda_gen)    # steady-state C_k at P=1
    C_2(t) = beta_2 / (lambda_2 * Lambda_gen)
    ...
end
```

This is a quality-of-life improvement, not a correctness bug (the trivial IC is documented), but it would eliminate PK-01c as a "gotcha" test.

---

### IN-02: `_flatten_weights` is an unexported internal helper but referenced in docstrings via the public API

**File:** `src/components/point_kinetics.jl:25-46`

**Issue:** `_flatten_weights` is correctly prefixed with `_` and not exported. However, it calls `getproperty(comp, :T)` and `size(T_sym)` / `length(T_sym)` without any guard against components that lack a `:T` symbolic field. If a user accidentally passes a non-thermal component (e.g., a `Pump`) in `temp_worth`, they will get an opaque `KeyError` from `getproperty` rather than a clear `ArgumentError`. This is a UX issue.

**Suggestion:** Add a guard at the top of `_flatten_weights`:

```julia
function _flatten_weights(raw, comp)
    if !hasproperty(comp, :T)
        throw(ArgumentError("Component $(nameof(comp)) has no symbolic T field — only thermal components (Channel, HeatDiffusion, etc.) are valid temp_worth keys"))
    end
    T_sym = getproperty(comp, :T)
    ...
end
```

---

### IN-03: `ReactivityController.state_machine` field is untyped — prevents dispatch and introspection

**File:** `src/components/point_kinetics.jl:320-327`

**Issue:** The `ReactivityController` struct definition (line 321) types `input_reactivity::F` (parameterized) but leaves `state_machine` untyped (a bare field). The docstring at line 314 notes this is intentional ("untyped -- may be swapped"). However, `scram_callback` at line 489 accesses `ctrl.state_machine.power_limit` directly without a type check. If `ctrl.state_machine` is not a `SCRAMCondition` (e.g., it is the default identity lambda), this will throw a `FieldError` at runtime — a cryptic error with no guidance.

**Suggestion:** Add a type assertion or informative error at the top of `scram_callback`:

```julia
function scram_callback(p_sym::Num, ctrl; terminate = true)
    if !(ctrl.state_machine isa SCRAMCondition)
        throw(ArgumentError(
            "scram_callback requires ctrl.state_machine to be a SCRAMCondition " *
            "(constructed via SCRAM_at_power). Got: $(typeof(ctrl.state_machine))"
        ))
    end
    plimit = ctrl.state_machine.power_limit
    ...
end
```

---

### IN-04: `build_loop_lof_bypass` function builds a Flapper but `threshold` is not passed to the build function — `flapper_callback` threshold must be matched manually

**File:** `src/examples.jl:384`, `test/test_loss_of_flow.jl:114`

**Issue:** `build_loop_lof_bypass` creates the Flapper with `@named flapper = Flapper(dt=dt_ramp)` but never communicates the threshold value. The test then calls `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)` with a separately-maintained constant. If the user changes the LOF threshold, they must remember to update two independent values. This is a coupling / discoverability issue rather than a bug, but it is a potential source of silent inconsistency in downstream usage.

**Suggestion:** Either return the threshold from `build_loop_lof_bypass` (as part of a config NamedTuple), or add `threshold` to the signature (addressing WR-03 above closes this too).

---

_Reviewed: 2026-04-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
