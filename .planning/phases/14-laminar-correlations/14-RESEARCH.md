# Phase 14: Laminar Correlations - Research

**Researched:** 2026-03-15
**Domain:** Julia MTK correlation function design, pluggable HTC/friction architecture
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Correlation function signatures:**
- HTC correlation: `(Re, Pr) -> Nu` — returns Nusselt number. Surrounding channel code handles `h_tc = Nu * k_water(T) / Dh`. Geometry-independent; MTK-compatible (Re and Pr are symbolic expressions at solve time).
- Friction correlation: `(Re) -> f_darcy` — returns Darcy friction factor. Surrounding channel code handles the full Darcy-Weisbach equation. MTK-compatible.
- Re and Pr are the only solve-time variables needed across all Phase 14 correlations. Everything else (geometry corrections, configuration) is captured in closures at construction time — mirrors Python STREAM's `partial` pattern.
- Closures for complex correlations (e.g. `laminar_friction(aspect_ratio=0.57)`) capture construction-time scalars; the inner function receives only symbolic Re/Pr.

**Correlation factories to implement:**
- `dittus_boelter(Re, Pr) = 0.023 * Re^0.8 * Pr^0.4` — named standalone function (currently hardcoded inline)
- `blasius_friction(Re) = 0.3164 * Re^(-0.25)` — named standalone function (currently hardcoded inline)
- `constant_Nusselt(; Nu=8.235)` — factory returning `(Re, Pr) -> Nu`; default 8.235 = uniform-heat-flux parallel plates (Shah & London)
- `laminar_friction(; aspect_ratio)` — factory returning `(Re) -> 64 / (Re * rectangular_laminar_correction(aspect_ratio))`; circular case (aspect_ratio=1.0) reduces to plain 64/Re
- `rectangular_laminar_correction(aspect_ratio)` — scalar precomputed from KAERI formula; exposed as a standalone utility

**regime_dependent:**
- `regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent, Re_transition=2300)` — requires all four correlation args (both htc pair and friction pair)
- Returns a named tuple `(htc=fn, friction=fn)` where each fn is a closure with `ifelse` switching baked in:
  ```julia
  htc_fn      = (Re, Pr) -> ifelse(Re < Re_transition, htc_lam(Re, Pr), htc_turb(Re, Pr))
  friction_fn = (Re)     -> ifelse(Re < Re_transition, f_lam(Re), f_turb(Re))
  ```
- `ifelse()` switching is the established project pattern (carry-forward from prior phases)
- User unpacks explicitly: `rd = regime_dependent(...); ChannelAndContacts(htc_correlation=rd.htc, friction_correlation=rd.friction)`

**ChannelAndContacts / channel variant API:**
- All three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux) get `htc_correlation` and `friction_correlation` kwargs
- Defaults: `htc_correlation=dittus_boelter`, `friction_correlation=blasius_friction` — all existing tests pass unchanged
- `_channel_base_eqs` is refactored to accept and call `htc_correlation(Re[i], Pr_i)` and `friction_correlation(Re_mean)` instead of hardcoded expressions; ChannelAndContacts and ChannelHeatFlux inherit this for free by passing kwargs through
- Channel (which does not use `_channel_base_eqs`) gets the same kwargs updated inline — same logic, same small swap
- Pr is computed inline as `cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])` and passed to the htc closure as a symbolic expression; no new MTK variable needed

**PipeGeometry extension:**
- Add `width` and `depth` fields to `PipeGeometry` struct (aligning with Python STREAM's `EffectivePipe`)
- `PipeGeometry_rectangular`: `width = max(edge1, edge2)`, `depth = min(edge1, edge2)`
- `PipeGeometry_circular`: `width = D`, `depth = D` (aspect_ratio = 1.0 → k_R = 1.0 → plain 64/Re, correct)
- `aspect_ratio = depth / width` is derived by the user at construction time when building laminar closures — NOT auto-injected by channel components

### Claude's Discretion

- Exact Julia module/file organization for correlation functions (new file vs. added to `components.jl`)
- Whether `dittus_boelter` and `blasius_friction` become the default argument values directly or are referenced by name
- Test structure for PHY-04: which Re values to exercise for both laminar and turbulent branches

### Deferred Ideas (OUT OF SCOPE)

- Developing-length laminar HTC (`developing_laminar_h_spl` equivalent) — needs `develop_length` from cell position; complex; no Phase 14 validation target
- Viscosity correction for friction (`viscosity_correction(heat_wet_ratio, mu_ratio)`) — needs `T_wall` at solve time; not uniformly available in `_channel_base_eqs`; defer to future phase
- Natural convection (`Elenbaas_h_spl`) — out of scope for v0.4
- `maximal_h_spl` equivalent (take max of multiple correlations) — no current validation target
- `turbulent_friction` (Colebrook-White approximation, more accurate than Blasius) — Blasius is sufficient for Phase 14 scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PHY-02 | `constant_Nusselt(Nu=8.235)` HTC correlation available and pluggable into ChannelAndContacts | `constant_Nusselt` factory verified in Python STREAM source; Nu=8.235 is FIXED_FLUXES constant from Shah & London for parallel plates under uniform heat flux; closure pattern trivial |
| PHY-03 | `laminar_friction(Re)` friction correlation available and pluggable into ChannelAndContacts | KAERI formula for `rectangular_laminar_correction` verified from Python STREAM `friction.py`; `laminar_friction` factory with `aspect_ratio` kwarg replaces the raw function signature |
| PHY-04 | `regime_dependent(; Re_transition=2300)` wrapper that switches between laminar and turbulent correlations based on Re | `ifelse()` MTK-compatible switching confirmed as established pattern; named-tuple return design is locked; both htc and friction branches required |
</phase_requirements>

---

## Summary

Phase 14 makes HTC and friction correlations pluggable across all three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux). The primary refactor target is `_channel_base_eqs` — currently 3 lines hardcode Dittus-Boelter Nu and Blasius friction. Replacing those 3 lines with calls to passed-in closure arguments, then threading the new kwargs through all callers, is the complete channel-side change. All existing tests remain unaffected because the defaults are the currently-hardcoded expressions.

The correlation library itself is a collection of pure Julia math functions: two named standalone functions (extracted from current inline code), two factories returning closures, one scalar utility function (KAERI rectangular correction), and one factory returning a named tuple. None of these interact with MTK internals — they are plain Julia callables that return symbolic expressions when called with symbolic Re/Pr. The `ifelse()` pattern for regime switching is already used for flow reversal; the same idiom applies here.

`PipeGeometry` needs two new fields (`width`, `depth`) to support user-constructed laminar closures. This is a struct extension, not a behavior change — existing factory constructors gain two lines each, and the struct field list grows by two. No existing tests break because the new fields are not read by any existing code path.

**Primary recommendation:** Implement as two clean waves — Wave 1 extracts and wires the correlation architecture (refactor `_channel_base_eqs`, add `width`/`depth`, implement all six correlation functions/factories, export them); Wave 2 adds PHY-02/PHY-03/PHY-04 tests plus regression check that all prior VAL tests still pass.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia (base) | 1.x | Pure math closures for correlation functions | No dependencies needed; plain `(Re, Pr) -> Nu` functions are native Julia |
| ModelingToolkit | existing | `ifelse()` for symbolic switching in regime_dependent | Already used for flow-reversal smoothing in Channel |

### No New Dependencies
All correlation functions are pure Julia arithmetic. `ifelse()` for smooth switching is already in scope via ModelingToolkit (used in existing channel code for flow reversal).

---

## Architecture Patterns

### Recommended File Organization

**Decision (Claude's discretion):** Create a new `src/correlations.jl` file for all correlation functions. This keeps `components.jl` focused on MTK component constructors, avoids bloat, and makes the correlation library independently navigable. Add `include("correlations.jl")` to `STREAM.jl` before `components.jl`.

```
src/
├── STREAM.jl          # module entry; add correlations to exports
├── fluids.jl          # existing fluid properties
├── connectors.jl      # existing ports
├── correlations.jl    # NEW: all Phase 14 correlation functions
├── components.jl      # existing components; _channel_base_eqs refactored
└── solvers.jl         # existing solvers
```

### Pattern 1: Named standalone functions as defaults

Extract the currently-hardcoded Dittus-Boelter and Blasius expressions into named functions at module level in `correlations.jl`. These become the default argument values in `_channel_base_eqs`, `Channel`, `ChannelAndContacts`, and `ChannelHeatFlux`:

```julia
# In correlations.jl
dittus_boelter(Re, Pr) = 0.023 * Re^0.8 * Pr^0.4
blasius_friction(Re)   = 0.3164 * Re^(-0.25)
```

Because these are plain functions (not `@register_symbolic`), MTK traces through them symbolically when Re/Pr are MTK variables. This is the same reason fluid property functions like `rho_water` are `@register_symbolic` (they are opaque to MTK) but arithmetic expressions like the Dittus-Boelter formula do not need annotation — MTK can differentiate through them directly.

### Pattern 2: Factory closures capturing construction-time scalars

```julia
# In correlations.jl

"""
    constant_Nusselt(; Nu=8.235)

Returns an HTC correlation `(Re, Pr) -> Nu` that yields the fixed Nusselt
number `Nu`. Default Nu=8.235 is the Shah & London fully-developed value for
uniform-heat-flux parallel plates (FIXED_FLUXES).
"""
function constant_Nusselt(; Nu=8.235)
    return (Re, Pr) -> Nu + zero(Re)   # zero(Re) ensures type-stability with symbolic Re
end

"""
    rectangular_laminar_correction(aspect_ratio)

Scalar geometric correction factor K_R from the KAERI formula.
Returns a Float64. aspect_ratio = depth/width, must be in [0, 1].
For aspect_ratio=1 (square): K_R ≈ 1.1246.
For aspect_ratio→0 (thin gap): K_R → 0.6668.
"""
function rectangular_laminar_correction(aspect_ratio::Real)
    return (
        0.88919 + 87.656 *
        ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end

"""
    laminar_friction(; aspect_ratio)

Returns a friction correlation `(Re) -> f_darcy` for laminar flow.
For circular geometry (aspect_ratio=1.0): f = 64/Re * (1/K_R(1.0))
which numerically equals ~56.9/Re (not plain 64/Re).

NOTE: The `aspect_ratio` kwarg is REQUIRED. For plain 64/Re (textbook circular
pipe), pass `aspect_ratio=0.0` only if K_R→0.667 is acceptable, or compute
K_R manually. For truly circular geometry (no correction), use a raw lambda
`(Re) -> 64.0 / Re` directly.
"""
function laminar_friction(; aspect_ratio::Real)
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end
```

**Important note on `constant_Nusselt` type stability:** When `Nu` is a plain `Float64` and `Re` is a symbolic MTK variable, the expression `Nu` (a constant) is already type-stable. The `+ zero(Re)` idiom is optional but can help MTK tracing; the simplest correct form is just `(Re, Pr) -> Nu` since `Nu` is captured as a Float64 constant in the closure.

### Pattern 3: _channel_base_eqs refactored signature

```julia
# In components.jl — _channel_base_eqs with correlation kwargs
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    port_in, port_out,
    Dh, A, L, g_acc, dz,
    htc_correlation  = dittus_boelter,    # NEW
    friction_correlation = blasius_friction)  # NEW

    for i in 1:n
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])  # NEW: inline Pr
        push!(eqs, v[i]    ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i]   ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
        push!(eqs, Nu[i]   ~ htc_correlation(Re[i], Pr_i))        # CHANGED
        push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / Dh)
    end

    i_mid   = max(1, n ÷ 2)
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = friction_correlation(Re_mean)                        # CHANGED
    push!(eqs, T_out ~ T[n])
    push!(eqs, dP    ~ f_ch * (port_in.mdot * abs(port_in.mdot) /
                                (2 * rho_water(T[i_mid]) * A^2)) * (L / Dh)
                      + rho_water(T[i_mid]) * g_acc * L)

    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_out.P - port_in.P       ~ -dP)
    push!(eqs, port_out.T                   ~ T[n])
    push!(eqs, port_in.T                    ~ instream(port_out.T))
end
```

The call sites in `ChannelAndContacts` and `ChannelHeatFlux` already pass kwargs to `_channel_base_eqs`; they simply add `htc_correlation` and `friction_correlation` to their own kwargs and forward them.

`Channel` does not call `_channel_base_eqs`. Its inline equations at lines 144-152 (Nu/h_tc) and 151-152 (f_ch) receive the same treatment as a direct edit.

### Pattern 4: regime_dependent named-tuple return

```julia
# In correlations.jl
function regime_dependent(;
    htc_laminar,
    htc_turbulent,
    friction_laminar,
    friction_turbulent,
    Re_transition = 2300.0)

    htc_fn = (Re, Pr) -> ifelse(Re < Re_transition,
                                htc_laminar(Re, Pr),
                                htc_turbulent(Re, Pr))
    friction_fn = (Re) -> ifelse(Re < Re_transition,
                                 friction_laminar(Re),
                                 friction_turbulent(Re))
    return (htc = htc_fn, friction = friction_fn)
end
```

Usage at the call site:
```julia
geom = PipeGeometry_rectangular(L, edge1, edge2, heated_edge)
rd = regime_dependent(
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction(aspect_ratio = geom.depth / geom.width),
    friction_turbulent = blasius_friction,
    Re_transition      = 2300.0
)
ch = ChannelAndContacts(; name=:ch, n=5, geometry=geom,
    htc_correlation       = rd.htc,
    friction_correlation  = rd.friction)
```

### Pattern 5: PipeGeometry struct extension

```julia
struct PipeGeometry
    L                ::Float64
    Dh               ::Float64
    A                ::Float64
    heated_perimeter ::Float64
    wet_perimeter    ::Float64
    heated_parts     ::NTuple{2,Float64}
    width            ::Float64    # NEW: longer cross-section dimension [m]
    depth            ::Float64    # NEW: shorter cross-section dimension [m]
end
```

Constructor additions:
- `PipeGeometry_rectangular`: `width = max(Float64(edge1), Float64(edge2))`, `depth = min(Float64(edge1), Float64(edge2))`
- `PipeGeometry_circular`: `width = _D`, `depth = _D`

Note: all existing `PipeGeometry(...)` calls use the factory constructors exclusively (old positional constructor was deleted in Phase 12.1 with no shim). Adding two trailing fields to the struct means the positional inner constructor changes signature, but since it was already forbidden by docstring and no test calls it directly, this is safe.

### Anti-Patterns to Avoid

- **`@register_symbolic` on correlation functions:** These are plain arithmetic — MTK traces through them. Only opaque functions (like spline-based fluid properties) need `@register_symbolic`. Registering `dittus_boelter` would make it a black box to MTK, breaking symbolic differentiation.
- **Hard if/else branch in regime_dependent:** A hard branch creates a discontinuity at Re_transition that nonlinear solvers struggle with. Use `ifelse()` exactly as done for flow reversal in Channel.
- **Nu variable vs. inline Nu:** The current code has `Nu[i]` as an MTK observable. After refactoring, `Nu[i] ~ htc_correlation(Re[i], Pr_i)` keeps this observable. Do not collapse `Nu` into the `h_tc` equation — it must remain inspectable via `sol[sys.ch.Nu, :]` for QOL-01 (Phase 15).
- **Pr as a new MTK variable:** Prandtl number is a function of T[i] only. It does not need to be declared as a separate state or observable variable. Compute it inline as a symbolic expression passed to the htc closure.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Smooth regime transition | Custom blending/interpolation | `ifelse()` | MTK already handles; consistent with flow reversal pattern; no new dependencies |
| K_R formula | Alternative polynomial fit | KAERI formula from Python STREAM | Verified reference; used in production TERMIC/KAERI codes |
| Pr computation | New MTK variable Pr(t) | Inline `cp*mu/k` expression | Avoids adding N new MTK unknowns that are observable but not state variables |

---

## Common Pitfalls

### Pitfall 1: `ifelse` with non-symbolic Re_transition
**What goes wrong:** If `Re_transition` is `Int` (e.g. `Re_transition=2300` without decimal), `ifelse(Re < 2300, ...)` may fail type promotion when `Re` is a Symbolics.Num.
**Why it happens:** Julia's type system; `2300` is Int64, but `Re` is symbolic.
**How to avoid:** Store as `Float64`: `Re_transition = Float64(Re_transition)` in the `regime_dependent` function body before use in the closure.
**Warning signs:** MethodError or type error at system construction time (not solve time).

### Pitfall 2: Default argument value captured at definition time
**What goes wrong:** If the default `htc_correlation=dittus_boelter` in `_channel_base_eqs` is evaluated before `dittus_boelter` is defined (e.g. if `correlations.jl` is included after `components.jl`), Julia throws an UndefVarError.
**Why it happens:** Default argument expressions are evaluated at call time in Julia, NOT definition time — so ordering typically works. But module load order still matters for the symbol to be in scope.
**How to avoid:** `include("correlations.jl")` before `include("components.jl")` in `STREAM.jl`.
**Warning signs:** `UndefVarError: dittus_boelter not defined` when loading STREAM.

### Pitfall 3: PipeGeometry positional constructor called in tests
**What goes wrong:** If any test (even an indirect one via `build_loop`, `build_loop_vertical`) calls `PipeGeometry(L, Dh, A, hp, wp, hparts)` with 6 positional args, adding the `width`/`depth` fields makes it a MethodError.
**Why it happens:** The inner struct constructor changes when fields are added.
**How to avoid:** Grep the full codebase for `PipeGeometry(` (not `PipeGeometry_`) before adding fields. Per Phase 12.1 notes, the old positional constructor was deleted; factory functions are the only surviving callers.
**Warning signs:** MethodError on `PipeGeometry` at test time.

### Pitfall 4: `constant_Nusselt` closure returns wrong type at symbolic evaluation
**What goes wrong:** `(Re, Pr) -> Nu` where `Nu::Float64` returns a `Float64` even when called with symbolic Re/Pr, because the return value doesn't depend on the arguments at all.
**Why it happens:** Julia closures return the type of the last expression; `Nu` is a captured Float64 constant.
**How to avoid:** MTK handles this correctly — a constant RHS in an equation like `Nu[i] ~ 8.235` is valid. This is not actually a bug, just a non-obvious property. Test that `Nu[i] ~ constant_Nusselt()(Re[i], Pr_i)` produces `Nu[i] ~ 8.235` in the equation system (it does).
**Warning signs:** None expected — this is correct Julia/MTK behavior.

### Pitfall 5: Exports missing for new symbols
**What goes wrong:** Users get `UndefVarError` when calling `constant_Nusselt`, `laminar_friction`, etc. even after `using STREAM`.
**Why it happens:** New symbols in `correlations.jl` are not automatically exported.
**How to avoid:** Add all new public symbols to the `export` list in `STREAM.jl`: `dittus_boelter`, `blasius_friction`, `constant_Nusselt`, `laminar_friction`, `rectangular_laminar_correction`, `regime_dependent`. Also add `PipeGeometry_rectangular` and `PipeGeometry_circular` are already exported; verify `width` and `depth` fields don't need separate export (they are struct fields, accessed as `geom.width` — no export needed).
**Warning signs:** Test-time `UndefVarError` after `import STREAM: ...`.

---

## Code Examples

Verified from Python STREAM source (`/home/itay/projects/STREAM/stream/physical_models/pressure_drop/friction.py`):

### rectangular_laminar_correction (KAERI formula)
```julia
# Source: Python STREAM friction.py rectangular_laminar_correction
# Formula: KAERI, as used in TERMIC thermal-hydraulics code
function rectangular_laminar_correction(aspect_ratio::Real)
    # aspect_ratio = depth/width, must be in [0, 1]
    # Returns K_R: multiply into denominator of 64/Re to get rectangular laminar f
    return (
        0.88919 +
        87.656 * ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end
```

**Verified reference values (Python STREAM, 2026-03-15):**
| aspect_ratio | K_R |
|---|---|
| 0.0 (thin gap limit) | 0.66684841 |
| 0.01814 (MTR: 0.00127/0.07) | 0.68543763 |
| 0.5 | 1.03638961 |
| 1.0 (square) | 1.12461904 |

**Note on circular geometry:** `PipeGeometry_circular` will set `depth=D, width=D`, giving `aspect_ratio=1.0`. K_R(1.0) ≈ 1.1246, so `laminar_friction(aspect_ratio=1.0)` gives `f = 64 / (Re * 1.1246)` ≈ `56.9/Re`, NOT `64/Re`. For the pure textbook circular pipe laminar formula `f = 64/Re`, one should use a raw lambda `(Re) -> 64.0 / Re`. This is acceptable because Phase 14 does not require a "circular laminar" test case; `constant_Nusselt` + `laminar_friction` are intended for rectangular MTR-style channels.

### dittus_boelter and blasius_friction (extraction from existing inline code)
```julia
# Source: currently at components.jl lines 144-146 and 152-153 (inline)
# Extracted as named functions
dittus_boelter(Re, Pr)  = 0.023 * Re^0.8 * Pr^0.4
blasius_friction(Re)    = 0.3164 * Re^(-0.25)
```

### regime_dependent switching test values
For a hypothetical MTR-geometry channel at very low mdot (laminar Re ≈ 100):
- `ifelse(100.0 < 2300, ...)` → takes laminar branch
- `constant_Nusselt(Nu=8.235)(100.0, 7.0)` → 8.235
- `laminar_friction(aspect_ratio=0.01814)(100.0)` → `64 / (100 * 0.6854)` ≈ 0.9334

For normal MTR operation (turbulent Re ≈ 8000):
- `ifelse(8000.0 < 2300, ...)` → takes turbulent branch
- `dittus_boelter(8000.0, 7.0)` → `0.023 * 8000^0.8 * 7^0.4` ≈ 53.6 (Nu)
- `blasius_friction(8000.0)` → `0.3164 * 8000^(-0.25)` ≈ 0.0531

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Dittus-Boelter hardcoded inline in `_channel_base_eqs` | Named `dittus_boelter(Re, Pr)` function + pluggable kwarg | Phase 14 | Zero behavior change for existing tests; enables override |
| Blasius hardcoded inline in `_channel_base_eqs` | Named `blasius_friction(Re)` function + pluggable kwarg | Phase 14 | Zero behavior change for existing tests |
| Nu computed as `0.023 * Re^0.8 * Pr^0.4` where Pr was not computed | Pr computed inline as `cp*mu/k` and passed to correlation | Phase 14 | More correct; Pr was implicitly correct before only because Dittus-Boelter is the same expression |
| PipeGeometry has no `width`/`depth` fields | `width` and `depth` fields added | Phase 14 | User can derive `aspect_ratio` for laminar closures |

**Deprecated/outdated:**
- Inline hardcoded `0.023 * Re[i]^0.8 * (cp*mu/k)^0.4` in `_channel_base_eqs`: replaced by `htc_correlation(Re[i], Pr_i)` call
- Inline hardcoded `0.3164 * Re_mean^(-0.25)` in `_channel_base_eqs`: replaced by `friction_correlation(Re_mean)` call
- Same two patterns in `Channel` inline code (lines 144-152): same treatment

---

## Open Questions

1. **`laminar_friction` name collision with Python STREAM**
   - What we know: Python STREAM has `laminar_friction(re)` as a standalone function returning `64/re` (no correction). Julia version is a factory `laminar_friction(; aspect_ratio)` returning a closure.
   - What's unclear: Whether the name is appropriate given the different semantics (factory vs. direct function).
   - Recommendation: Keep `laminar_friction` as the factory name per CONTEXT.md locked decision. The Julia API is function-factory oriented by design; the Python API is different. Document the distinction in the docstring.

2. **`Nu[i]` observable when htc_correlation returns a constant**
   - What we know: `Nu[i] ~ constant_Nusselt()(Re[i], Pr_i)` simplifies to `Nu[i] ~ 8.235`. MTK treats this as a valid algebraic equation. `sol[sys.ch.Nu, :]` returns `[8.235, 8.235, ...]` for all cells.
   - What's unclear: Whether MTK optimizes away the `Nu` variable in this case (it may, as it is a trivial algebraic equation). QOL-01 (Phase 15) needs `Nu` accessible.
   - Recommendation: Keep the `Nu[i]` declaration in all three channel components regardless. MTK retains observed variables.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (no version) |
| Config file | none — `test/runtests.jl` is the entry point |
| Quick run command | `julia --project=. -e "include(\"test/runtests.jl\")"` |
| Full suite command | `julia --project=. -e "include(\"test/runtests.jl\")"` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PHY-02 | `constant_Nusselt(Nu=8.235)` returns correct constant Nu in solved system | unit | `julia --project=. -e "include(\"test/runtests.jl\")"` (filter PHY-02 testset) | ❌ Wave 1 |
| PHY-03 | `laminar_friction(aspect_ratio=x)` returns `64/(Re*K_R)` with correct K_R; pluggable into ChannelAndContacts | unit | same | ❌ Wave 1 |
| PHY-04 | `regime_dependent(...)` exercises both laminar and turbulent branches; prior MTR VAL-01/02/03 still pass | integration | same | ❌ Wave 1 |

### Sampling Rate
- **Per task commit:** `julia --project=. -e "include(\"test/runtests.jl\")"`
- **Per wave merge:** same
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — add PHY-02, PHY-03, PHY-04 testsets (file exists, append to it)
- [ ] `src/correlations.jl` — does not exist; create in Wave 1

*(No new test infrastructure needed — existing runtests.jl pattern is sufficient)*

---

## Sources

### Primary (HIGH confidence)
- `/home/itay/projects/Julia-STREAM/src/components.jl` — current implementation of `_channel_base_eqs`, `Channel`, `ChannelAndContacts`, `ChannelHeatFlux`, `PipeGeometry`; read directly
- `/home/itay/projects/STREAM/stream/physical_models/pressure_drop/friction.py` — Python STREAM reference: `rectangular_laminar_correction` KAERI formula, `laminar_friction`, `blasius_friction`, `regime_dependent_friction`; read directly
- `/home/itay/projects/STREAM/stream/physical_models/heat_transfer_coefficient/laminar.py` — Python STREAM reference: `constant_Nusselt_h_spl`, `FIXED_FLUXES=8.235`, Shah & London source
- `/home/itay/projects/STREAM/stream/pipe_geometry.py` — Python STREAM `EffectivePipe.rectangular()`: `width=max(edge1,edge2)`, `depth=min(edge1,edge2)` exact formulas
- `.planning/phases/14-laminar-correlations/14-CONTEXT.md` — all locked implementation decisions

### Secondary (MEDIUM confidence)
- Python STREAM test file `tests/test_libraries/test_pressure_drop.py` — spot-checked K_R values: `K_R(0.05)=0.71742`, `K_R(0.1)=0.76565`, `K_R(0.15)=0.81110`, `K_R(0.2)=0.85346` (verified against formula)
- Computed reference values for MTR geometry: `aspect_ratio=0.01814`, `K_R=0.68544` (Python numpy, 2026-03-15)

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all existing Julia/MTK patterns
- Architecture: HIGH — all patterns directly ported from verified Python STREAM source; CONTEXT.md has locked all key decisions
- Pitfalls: HIGH — derived from code inspection of existing patterns + Julia semantics

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (stable — no fast-moving dependencies)
