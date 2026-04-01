# Phase 30: HTC & Friction Completions - Research

**Researched:** 2026-04-01
**Domain:** Heat transfer and friction correlation functions (plain Julia arithmetic, no MTK symbolic)
**Confidence:** HIGH

## Summary

Phase 30 adds 6 new correlation functions and splits the existing `correlations.jl` into two domain-specific files under `src/physical_models/htc/` and `src/physical_models/friction/`. All functions are plain Julia arithmetic (no `@register_symbolic`, no MTK dependency). The Python STREAM reference implementations have been fully reviewed -- every formula, edge case, and coefficient is documented below.

The phase is pure function addition plus file reorganization. No existing component behavior changes. No new MTK components. The primary risk is formula transcription errors, mitigated by testing against Python STREAM doctest values.

**Primary recommendation:** Implement the file split first (wave 0 / plan 01), then add new functions (plan 02). This avoids merge conflicts and keeps each plan focused.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: `fully_developed_laminar_h_spl` (HTC-02) uses `_two_sided_heating_nusselt(aspect_ratio)` -- the Kakac Table 44 case 3 polynomial for 2-sided rectangular duct heating. NOT Marco-Han.
- D-02: `_two_sided_heating_nusselt` is a private helper (underscore-prefixed, not exported). Used internally by both HTC-02 and HTC-03.
- D-03: `developing_laminar_h_spl` (HTC-03) applies `_two_sided_heating_nusselt(aspect_ratio, nudev)` as a finite-size correction. x_star formula: `develop_length / Dh / Re / Pr / (6 - 5 * exp(-0.75 * aspect_ratio / 0.3257))`.
- D-04: Requirements incorrectly state HTC-02 uses "Marco-Han." The correct function is two-sided heating (user decision).
- D-05: Split `src/physical_models/correlations.jl` into `src/physical_models/htc/correlations.jl` and `src/physical_models/friction/correlations.jl`.
- D-06: Update `src/STREAM.jl` includes. All exports remain in `src/STREAM.jl` only.
- D-07: `laminar_friction(aspect_ratio::Real)` and `rectangular_laminar_correction` go to friction/.
- D-08: `turbulent_friction(Re, epsilon=0)` guards `Re <= 0 -> 0.0` before Colebrook-White formula.

### Claude's Discretion
- Exact piecewise formula for `_nusselt_coefficient_developing` -- match Python STREAM exactly
- `maximal_htc(correlations...)` variadic signature
- Test file: `test/test_correlations.jl` -- add new test cases to existing file
- `_nusselt_coefficient_developing` private, not exported

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HTC-01 | Marco_Han_Nusselt(aspect_ratio) -> Nu for 4-sided laminar rectangular duct | Exact polynomial from Python STREAM laminar.py lines 37-73; reference values at ar=0.0 (8.235) and ar=0.2 (5.991) |
| HTC-02 | fully_developed_laminar_h_spl(; Dh, aspect_ratio) -> closure | Uses _two_sided_heating_nusselt (D-01); closure returns Nu (not h in W/m2K); factory pattern matches existing constant_Nusselt |
| HTC-03 | developing_laminar_h_spl(; Dh, develop_length, aspect_ratio) -> closure | Uses _nusselt_coefficient_developing + _two_sided_heating_nusselt; x_star formula from Python STREAM; piecewise Shah & London |
| HTC-04 | maximal_htc(correlations...) -> closure returning max Nu | Python STREAM uses reduce(np.maximum, ...); Julia equivalent: variadic closure with max broadcast |
| FRIC-01 | turbulent_friction(Re, epsilon=0) -> f_darcy via Colebrook-White | Exact formula from Python STREAM friction.py lines 22-53; reference values at Re=4e3 (0.03980), Re=1e6 (0.01165) |
| FRIC-02 | viscosity_correction(heat_wet_ratio, mu_ratio) -> K_H | Formula: 1 + heat_wet_ratio * (mu_ratio^0.58 - 1); reference values from Python STREAM |
</phase_requirements>

## Standard Stack

No new dependencies. All functions are plain Julia arithmetic.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia stdlib (Math) | N/A | exp, log10, max | All correlations are plain arithmetic |

### Supporting
None required. No external packages needed for this phase.

## Architecture Patterns

### File Split Structure (D-05)
```
src/physical_models/
  htc/
    correlations.jl          # All HTC functions (existing + new)
  friction/
    correlations.jl          # All friction functions (existing + new)
  subcooled_boiling.jl       # Unchanged
  threshold_analysis.jl      # Unchanged
  dimensionless.jl           # Unchanged
```

### HTC file contents after split
Existing (migrated from correlations.jl):
- `dittus_boelter(Re, Pr, args...)` -- turbulent forced convection
- `constant_Nusselt(; Nu)` -- factory for fixed Nu
- `regime_dependent(; ...)` -- regime-switching factory
- `elenbaas_nusselt(Ra, b, L)` -- natural convection standalone
- `elenbaas_htc(; b, L, Dh, g)` -- natural convection factory
- `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` -- private helper

New (added in this phase):
- `Marco_Han_Nusselt(aspect_ratio)` -- HTC-01
- `_two_sided_heating_nusselt(aspect_ratio, nu0=8.235)` -- private helper (D-02)
- `_nusselt_coefficient_developing(x)` -- private helper
- `fully_developed_laminar_h_spl(; Dh, aspect_ratio)` -- HTC-02 factory
- `developing_laminar_h_spl(; Dh, develop_length, aspect_ratio)` -- HTC-03 factory
- `maximal_htc(correlations...)` -- HTC-04 combinator

### Friction file contents after split
Existing (migrated from correlations.jl):
- `blasius_friction(Re)` -- turbulent Blasius
- `rectangular_laminar_correction(aspect_ratio)` -- geometry correction (D-07)
- `laminar_friction(aspect_ratio::Real)` -- factory (D-07)

New (added in this phase):
- `turbulent_friction(Re, epsilon=0)` -- FRIC-01
- `viscosity_correction(heat_wet_ratio, mu_ratio)` -- FRIC-02

### Pattern: Correlation Closure Factory (established)
All factories follow the same pattern: capture construction-time scalars, return a closure with the standard interface.

```julia
# HTC closures: (Re, Pr, T_bulk, T_wall) -> Nu
# Friction closures: (Re) -> f_darcy
function my_factory(; param1, param2)
    # Precompute at construction time
    precomputed = some_calculation(param1)
    # Return closure matching standard interface
    return (Re, Pr, args...) -> formula(Re, Pr, precomputed)
end
```

### Anti-Patterns to Avoid
- **Exporting private helpers:** `_two_sided_heating_nusselt`, `_nusselt_coefficient_developing` must NOT appear in STREAM.jl exports. They are underscore-prefixed private functions per CLAUDE.md convention.
- **Using `if`/`else` on symbolic values:** Not relevant here (these are plain arithmetic functions, not MTK equations), but worth noting that `ifelse()` is the project pattern for symbolic conditionals.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| N/A | N/A | N/A | All functions in this phase are analytical formulas from published correlations -- they MUST be hand-written to match the reference |

**Key insight:** This phase is the opposite of "don't hand-roll" -- every function IS a hand-implementation of a published analytical formula. The risk is transcription error, mitigated by testing against Python STREAM reference values.

## Common Pitfalls

### Pitfall 1: Marco-Han vs Two-Sided Heating Confusion
**What goes wrong:** Requirements text says HTC-02 uses "Marco-Han" but per D-01/D-04, it actually uses `_two_sided_heating_nusselt` (Kakac Table 44 case 3).
**Why it happens:** Requirements were written before the discuss session clarified the physics.
**How to avoid:** Follow CONTEXT.md decisions D-01 and D-04. Marco_Han_Nusselt (HTC-01) is 4-sided uniform heat flux. Two-sided heating (HTC-02/03) is 2-sided rectangular duct.
**Warning signs:** If HTC-02 factory calls Marco_Han_Nusselt, it is wrong.

### Pitfall 2: turbulent_friction NaN at Re <= 0
**What goes wrong:** log10(21.25 / Re^0.9) produces -Inf or NaN when Re=0.
**Why it happens:** Colebrook-White formula has Re in denominators and log arguments.
**How to avoid:** D-08 specifies: `Re <= 0 ? 0.0 : formula`. This is Julia's equivalent of Python's `nan_to_num`.
**Warning signs:** NaN in friction factor output at low Re.

### Pitfall 3: _nusselt_coefficient_developing Piecewise Boundaries
**What goes wrong:** Wrong piecewise breakpoints or formulas produce incorrect developing flow Nu.
**Why it happens:** Three separate formulas with specific x_star boundaries.
**How to avoid:** Match Python STREAM exactly: `x <= 2e-4: 1.49*x^(-1/3)`, `x <= 1e-3: 1.49*x^(-1/3) - 0.4`, else `8.235 + 8.68*exp(-164*x)*(1e3*x)^-0.506`. Use nested ternary or if/elseif/else (plain Julia, not symbolic).
**Warning signs:** Developing flow Nu values diverge from Python STREAM at moderate x_star.

### Pitfall 4: File Split Breaking Existing Tests
**What goes wrong:** After splitting correlations.jl, existing test_correlations.jl imports fail.
**Why it happens:** The split changes include paths in STREAM.jl, which could subtly affect module load order.
**How to avoid:** The split only changes `include()` paths in STREAM.jl. All functions remain in the STREAM module namespace. Test imports (`import STREAM: dittus_boelter, ...`) are unaffected because they reference the module, not the file.
**Warning signs:** Any `UndefVarError` in existing correlation tests after the split.

### Pitfall 5: x_star Correction Factor in HTC-03
**What goes wrong:** Missing the aspect-ratio correction factor in the x_star denominator.
**Why it happens:** The correction `(6 - 5 * exp(-0.75 * aspect_ratio / 0.3257))` is easy to overlook.
**How to avoid:** Copy the exact formula from D-03: `x_star = develop_length / Dh / Re / Pr / (6 - 5 * exp(-0.75 * aspect_ratio / 0.3257))`.
**Warning signs:** Developing flow Nu matches parallel-plate values but not finite-aspect-ratio values.

## Code Examples

### HTC-01: Marco_Han_Nusselt (from Python STREAM laminar.py:37-73)
```julia
# 4-sided uniform heat flux, Kakac ch. 3
function Marco_Han_Nusselt(aspect_ratio)
    return 8.235 * (
        1.0
        - 2.0421 * aspect_ratio
        + 3.853 * aspect_ratio^2
        - 2.4765 * aspect_ratio^3
        + 1.0578 * aspect_ratio^4
        - 0.1861 * aspect_ratio^5
    )
end
# Reference: Marco_Han_Nusselt(0.0) == 8.235, Marco_Han_Nusselt(0.2) == 5.991134842...
```

### D-02: _two_sided_heating_nusselt (from Python STREAM laminar.py:76-123)
```julia
# Kakac Table 44 case 3, 2-sided heating
function _two_sided_heating_nusselt(aspect_ratio, nu0=8.235)
    return nu0 * (
        1.0
        - 1.4122 * aspect_ratio
        + 2.3473 * aspect_ratio^2
        - 2.8983 * aspect_ratio^3
        + 2.0629 * aspect_ratio^4
        - 0.6077 * aspect_ratio^5
    )
end
# Reference values (Shah & London Table 44):
# ar=0.0 -> 8.235, ar=0.1 -> 7.248 (rtol 1.1%), ar=1.0 -> 4.094 (rtol 1.1%)
```

### Private helper: _nusselt_coefficient_developing (from Python STREAM laminar.py:147-195)
```julia
# Shah & London equations 317-319 for parallel plates, thermally developing flow
function _nusselt_coefficient_developing(x)
    if x <= 2e-4
        return 1.49 * x^(-1/3)
    elseif x <= 1e-3
        return 1.49 * x^(-1/3) - 0.4
    else
        return 8.235 + 8.68 * exp(-164 * x) * (1e3 * x)^(-0.506)
    end
end
```

### HTC-02: fully_developed_laminar_h_spl factory
```julia
function fully_developed_laminar_h_spl(; Dh, aspect_ratio)
    nu = _two_sided_heating_nusselt(aspect_ratio)  # precompute at construction
    return (Re, Pr, args...) -> nu
end
```

### HTC-03: developing_laminar_h_spl factory
```julia
function developing_laminar_h_spl(; Dh, develop_length, aspect_ratio)
    correction = 6 - 5 * exp(-0.75 * aspect_ratio / 0.3257)  # precompute
    return (Re, Pr, args...) -> begin
        x_star = develop_length / Dh / Re / Pr / correction
        nudev = _nusselt_coefficient_developing(x_star)
        _two_sided_heating_nusselt(aspect_ratio, nudev)
    end
end
```

### HTC-04: maximal_htc combinator
```julia
function maximal_htc(correlations...)
    return (Re, Pr, T_bulk, T_wall) -> begin
        reduce(max, (c(Re, Pr, T_bulk, T_wall) for c in correlations))
    end
end
```

### FRIC-01: turbulent_friction (from Python STREAM friction.py:22-53)
```julia
function turbulent_friction(Re, epsilon=0)
    Re <= 0 && return 0.0  # D-08: guard against NaN
    inlog = log10(epsilon + 21.25 / Re^0.9)
    outlog = log10(epsilon / 3.7 + (2.51 / Re) * (1.14 - 2 * inlog))
    return (-2 * outlog)^(-2)
end
# Reference: turbulent_friction(4e3) == 0.039804935964641644
#            turbulent_friction(4e3, 0.1) == 0.10560870441248855
#            turbulent_friction(1e6) == 0.011649393290640643
#            turbulent_friction(5.0) == 0.0
```

### FRIC-02: viscosity_correction (from Python STREAM friction.py:129-156)
```julia
function viscosity_correction(heat_wet_ratio, mu_ratio)
    return 1 + heat_wet_ratio * (mu_ratio^0.58 - 1)
end
# Reference: viscosity_correction(1.0, 1.0) == 1.0
#            viscosity_correction(1.0, 0.0) == 0.0
#            viscosity_correction(1.0, 2.0) == 1.4948492486349383
```

## State of the Art

No changes in the heat transfer correlation domain since these formulas were established. Shah & London (1978) and Kakac correlations are stable references.

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single correlations.jl | Split htc/ + friction/ | This phase | Better organization per CLAUDE.md guidelines |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib |
| Config file | test/runtests.jl |
| Quick run command | `julia --project -e 'using Pkg; Pkg.test()' 2>&1 \| tail -50` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HTC-01 | Marco_Han_Nusselt returns correct Nu at ar=0, 0.2, 1.0 | unit | `julia --project -e 'include("test/test_correlations.jl")'` | Partial (file exists, new tests needed) |
| HTC-02 | fully_developed_laminar_h_spl closure returns _two_sided_heating Nu | unit | same | Partial |
| HTC-03 | developing_laminar_h_spl matches Python STREAM developing flow Nu | unit | same | Partial |
| HTC-04 | maximal_htc returns max across multiple correlations | unit | same | Partial |
| FRIC-01 | turbulent_friction matches Python STREAM reference values | unit | same | Partial |
| FRIC-02 | viscosity_correction matches Python STREAM reference values | unit | same | Partial |

### Sampling Rate
- **Per task commit:** `julia --project -e 'include("test/test_correlations.jl")'`
- **Per wave merge:** Full test suite
- **Phase gate:** Full suite green before verification

### Wave 0 Gaps
- [ ] New test cases for HTC-01..04 and FRIC-01..02 in `test/test_correlations.jl`
- [ ] Import additions in test file for new exported names

## Sources

### Primary (HIGH confidence)
- Python STREAM `stream/physical_models/heat_transfer_coefficient/laminar.py` -- Marco_Han_Nusselt, two_sided_heating_nusselt, _nusselt_coefficient_developing, fully_developed_laminar_h_spl, developing_laminar_h_spl exact formulas
- Python STREAM `stream/physical_models/pressure_drop/friction.py` -- turbulent_friction (Colebrook-White), viscosity_correction exact formulas
- Python STREAM `stream/physical_models/heat_transfer_coefficient/single_phase.py` -- maximal_h_spl pattern
- Existing Julia `src/physical_models/correlations.jl` -- current code to be split
- Phase 30 CONTEXT.md -- all locked decisions D-01 through D-08

### Secondary (MEDIUM confidence)
- Shah & London (1978) "Laminar Flow Forced Convection in Ducts" -- original Table 34, Table 44 references (verified via Python STREAM implementation)
- Kakac, Shah, Wung "Handbook of Single-Phase Convective Heat-transfer" ch. 3 -- Marco-Han and two-sided heating polynomials

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, plain Julia arithmetic
- Architecture: HIGH -- file split is mechanical; factory pattern well-established in codebase
- Pitfalls: HIGH -- all formulas verified against Python STREAM source code directly
- Formulas: HIGH -- transcribed from Python STREAM with exact coefficients and reference values

**Research date:** 2026-04-01
**Valid until:** indefinite (analytical correlations from stable textbook references)
