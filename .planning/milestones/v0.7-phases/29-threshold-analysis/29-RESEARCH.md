# Phase 29: Threshold Analysis - Research

**Researched:** 2026-03-31
**Domain:** Nuclear thermal-hydraulics safety threshold correlations + post-processing framework
**Confidence:** HIGH

## Summary

Phase 29 implements nine threshold analysis requirements (THRS-01..09) split across two files: physics-layer functions in `src/physical_models/threshold_analysis.jl` (plain Julia arithmetic, no MTK) and a post-processing layer in `src/analysis.jl` (ChannelState struct, extraction from MTK solutions, pre-built wrappers, chfr helper, threshold_analysis dispatcher). All decisions are locked via CONTEXT.md with very detailed specifications.

The physics functions are direct ports from Python STREAM `physical_models/thresholds.py` and `heat_transfer_coefficient/temperatures.py`. They are pure arithmetic -- no symbolic tracing, no MTK dependencies. The post-processing layer is a new pattern for the codebase: extracting data from `SciMLBase.NonlinearSolution` / `SciMLBase.ODESolution` objects into a flat struct, then dispatching user-provided closures over it.

A critical design constraint is that Sudo-Kaminaga CHF (THRS-05) requires saturation thermophysical properties (vapor density, latent heat, surface tension) that do not exist in STREAM.jl's fluid property functions. These must be provided as hardcoded constants or simple correlations within the threshold_analysis.jl file itself, since the requirement signature `q_CHF_sudo_kaminaga(T_bulk, mdot, pipe, gravity)` has no pressure parameter.

**Primary recommendation:** Implement physics functions first (THRS-01..08), then the post-processing framework (THRS-09). Sudo-Kaminaga needs internal saturation property constants for light water at ~1 atm -- match Python STREAM's values exactly.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Physics functions (THRS-01..08) go in `src/physical_models/threshold_analysis.jl` -- plain Julia, no MTK
- **D-02:** Post-processing layer goes in `src/analysis.jl` -- ChannelState, extraction, wrappers, threshold_analysis()
- **D-03:** `Bergles_Rohsenow_T_ONB(pressure, q_wall, T_sat)` wraps private `_bergles_rohsenow_dT_ONB` from correlations.jl
- **D-04:** `ChannelState` is a struct with all pre-extracted MTK solution fields (detailed field list in CONTEXT.md)
- **D-05:** `q_flux_left[i]` = `q_wall_left[i] / (pipe.heated_parts[1] * dz)`; zeros when pipe is nothing
- **D-06:** Transient: AbstractVector fields become AbstractMatrix [n_times, n_cells]; broadcasting handles both
- **D-07:** `threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...)` signature
- **D-08:** `pipe` and `gravity` are top-level kwargs (needed by _extract_channel_state)
- **D-09:** Ship one analysis wrapper per THRS-02..08 correlation; naming: physics fn -> wrapper
- **D-10:** Full wrapper set: ONB_temperature, boiling_onset_power, OFI_power, OSV_flux, Sudo_Kaminaga_CHF, Mirshak_CHF, Fabrega_CHF, twall_limit
- **D-11:** `chfr(chf_fn; direction=:max)` returns closure; direction values :left/:right/:max/:total; q<=0 -> Inf
- **D-12:** chfr is the primary safety ratio helper; other ratios users compute as closures

### Claude's Discretion
- Exact formula coefficients for THRS-02..07 -- match Python STREAM exactly
- Whether ChannelState is struct or @kwdef struct (prefer @kwdef)
- How to handle n for transient extraction
- Whether _extract_channel_state uses sol[ssys.comp.variable] style or a helper
- Test file name: test_analysis.jl
- Export list additions to src/STREAM.jl

### Deferred Ideas (OUT OF SCOPE)
- Marco-Han Nusselt, developing laminar HTC, maximal_htc, turbulent friction, viscosity correction -> Phase 30
- Direction-specific ONB wrappers (ONB_left, ONB_right)
- ONB uncertainty factor (onb_factor) beyond what twall_limit handles
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| THRS-01 | Bergles_Rohsenow_T_ONB(pressure, q_wall, T_sat) -> K | Thin wrapper over existing `_bergles_rohsenow_dT_ONB` in correlations.jl; verified formula matches Python |
| THRS-02 | q_boiling_onset(mdot, T_sat, T_inlet, cp) -> W | Direct port of Python `boiling_power`: `abs(mdot) * cp * (T_sat - T_inlet)` |
| THRS-03 | q_OFI_whittle_forgan(mdot, T_sat, T_inlet, pipe) -> W | Whittle-Forgan with Fabrega correction; needs cp integration or simplified cp; CGS G conversion |
| THRS-04 | q_OSV_saha_zuber(T_inlet, mdot, pipe, ...) -> W/m^2 | Self-consistent computed_bulk variant; Pe threshold 70000; Nu_c=455, St_c=0.0065 |
| THRS-05 | q_CHF_sudo_kaminaga(T_bulk, mdot, pipe, gravity) -> W/m^2 | Kaminaga 1998; needs hardcoded saturation properties (rho_v, rho_l, hfg, sigma, cp_sat, T_sat) |
| THRS-06 | q_CHF_mirshak(T_bulk, T_sat, pressure, v) -> W/m^2 | Simple formula: `1.51e6 * (1+0.1198v)(1+0.00914(T_sat-T_bulk))(1+0.19e-5*P)` |
| THRS-07 | q_CHF_fabrega(T_inlet, T_sat, pipe) -> W/m^2 | Simple formula: `1e7 * Dh * (0.023(T_sat-T_inlet) + 4.56)` |
| THRS-08 | twall_limit(T_wall, inhomogeneity_factor) -> K | Scale wall temperature by inhomogeneity factor |
| THRS-09 | threshold_analysis(sol, channel_sys; kwargs...) -> NamedTuple | Post-processor: ChannelState extraction + dispatch |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia stdlib | - | All physics functions are plain arithmetic | No external deps needed for physics layer |
| SciMLBase | (existing) | Solution type queries `sol[sys.var]` and `sol[sys.var, :]` | Already used by solvers.jl |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| QuadGK | (existing via DiffEq) | Numerical integration for OFI cp integral | Available through DifferentialEquations dependency |

No new packages needed. All physics functions use plain Julia arithmetic. Solution querying uses existing SciMLBase patterns.

## Architecture Patterns

### Recommended Project Structure
```
src/
  physical_models/
    threshold_analysis.jl    # NEW: THRS-01..08 physics functions
  analysis.jl                # NEW: ChannelState, wrappers, chfr, threshold_analysis
test/
  test_analysis.jl           # NEW: tests for both files
```

### Pattern 1: Physics Function (plain Julia, no MTK)
**What:** Each threshold function is a plain Julia function operating on Float64 (or AbstractVector for cell-wise). No `ifelse()`, no `@register_symbolic`, no symbolic variables.
**When to use:** All THRS-01..08 functions.
**Why:** These run post-solve on extracted numerical data, not inside MTK equation graphs.
**Example:**
```julia
# Source: Python STREAM physical_models/thresholds.py line 475
function q_CHF_mirshak(T_bulk, T_sat, pressure, v)
    return 1.51e6 * (1 + 0.1198 * v) * (1 + 0.00914 * (T_sat - T_bulk)) * (1 + 0.19e-5 * pressure)
end
```

### Pattern 2: File Structure (following subcooled_boiling.jl)
**What:** Header comment block explaining design, then function docstrings with `# Arguments` / `# Returns`, all `export` statements in STREAM.jl only.
**When to use:** The new threshold_analysis.jl file.
**Example header:**
```julia
# threshold_analysis.jl -- Nuclear safety threshold correlations for STREAM.jl
#
# Design:
#   - All functions are plain Julia arithmetic (NOT @register_symbolic).
#   - Used post-solve for safety margin analysis, not inside MTK equations.
#   - Formulas match Python STREAM physical_models/thresholds.py exactly.
```

### Pattern 3: ChannelState Struct with @kwdef
**What:** A mutable or immutable struct using `@kwdef` for convenient keyword construction, holding all pre-extracted MTK solution data needed by threshold wrappers.
**When to use:** THRS-09 extraction layer.
**Example:**
```julia
@kwdef struct ChannelState
    n::Int
    T_bulk::AbstractVector
    T_wall::AbstractVector
    # ... all fields from D-04
end
```

### Pattern 4: Solution Querying (existing codebase pattern)
**What:** Extract values from MTK solutions using `sol[ssys.comp.var]` (steady) or `sol[ssys.comp.var, :]` (transient). Observed variables (T_sat, T_ONB, P, T_wall_left/right, q_wall_left/right, velocity) are accessible this way.
**When to use:** Inside `_extract_channel_state`.
**Example:**
```julia
# Steady state: returns scalar or Vector{Float64}
T_bulk_i = sol[channel_sys.T[i]]        # scalar for cell i
mdot_val = sol[channel_sys.inlet.mdot] # scalar

# Transient: returns Vector{Float64} over time
T_bulk_i_t = sol[channel_sys.T[i], :]    # vector over time for cell i
```

### Pattern 5: chfr Factory (closure pattern from regime_dependent)
**What:** `chfr(chf_fn; direction=:max)` captures the CHF function and direction at construction, returns a closure `(state::ChannelState) -> AbstractArray` that computes the ratio with q<=0 -> Inf guard.
**When to use:** THRS-09 safety ratio computation.

### Anti-Patterns to Avoid
- **Using ifelse() in threshold functions:** These are post-solve functions on Float64 data. Use plain `if`/ternary operators. `ifelse()` is only for MTK symbolic equations.
- **Using @register_symbolic:** Threshold functions never appear in MTK equation graphs. No symbolic registration needed.
- **Observed-to-observed chains in _extract_channel_state:** Query each variable independently from the solution. Don't chain observed variable queries.
- **Hardcoding channel system structure in extraction:** Use the `channel_sys` parameter to navigate the MTK variable tree, not string-based names.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ONB temperature | Custom formula | `_bergles_rohsenow_dT_ONB` from correlations.jl | Already implemented and tested; D-03 mandates thin wrapper |
| Cp integration for OFI | Manual Riemann sum | `QuadGK.quadgk` or simplified average | Python uses scipy.integrate.quad; Julia has QuadGK |
| Solution variable extraction | Custom solution parser | `sol[sys.var]` / `sol[sys.var, :]` SciMLBase API | Established codebase pattern, handles both steady and transient |

**Key insight:** The physics formulas are simple arithmetic -- the complexity is in the post-processing framework (ChannelState extraction, steady/transient uniformity, directional q_flux, chfr guards).

## Common Pitfalls

### Pitfall 1: Sudo-Kaminaga Missing Saturation Properties
**What goes wrong:** STREAM.jl has no `rho_vapor`, `latent_heat`, or `surface_tension` functions. Python STREAM passes a `sat_coolant` Liquid object with these properties.
**Why it happens:** STREAM.jl focuses on single-phase liquid properties; two-phase properties were never needed until now.
**How to avoid:** Hardcode saturation properties for light water at ~1 atm within the `q_CHF_sudo_kaminaga` function or as module-level constants. Values from Python STREAM's light_water at saturation: `rho_v ~ 0.598 kg/m^3`, `rho_l ~ 958.4 kg/m^3`, `hfg ~ 2257e3 J/kg`, `sigma ~ 0.059 N/m`, `cp_sat ~ 4217 J/(kg*K)`, `T_sat ~ 373.15 K`. Or accept these as keyword arguments with defaults.
**Warning signs:** `MethodError: no method matching` when trying to call nonexistent fluid functions.

### Pitfall 2: OFI Whittle-Forgan CGS Conversion
**What goes wrong:** The G mass flux in the Whittle-Forgan formula must be in CGS units (g/cm^2/s), not SI (kg/m^2/s).
**Why it happens:** The original French correlation uses CGS. Python STREAM divides by 10 to convert.
**How to avoid:** Apply `G_cgs = G_si / 10` conversion. Document the CGS quirk clearly.
**Warning signs:** OFI power off by factor of ~2 compared to Python reference.

### Pitfall 3: OFI Cp Integration
**What goes wrong:** Python STREAM uses `scipy.integrate.quad(cp, T_inlet, T_sat)` for the average cp over the temperature range. If a simple `cp_water(T_inlet)` is used instead, results differ.
**Why it happens:** The REQUIREMENTS.md signature is `q_OFI_whittle_forgan(mdot, T_sat, T_inlet, pipe)` with no cp argument. The function needs to integrate cp internally.
**How to avoid:** Use `QuadGK.quadgk(cp_water, T_inlet, T_sat)` to match Python exactly. Or use `cp_water` as the integration function since it is already available. The result of the integral is `integral_cp = quadgk(cp_water, T_inlet, T_sat)[1]` which replaces `mdot * cp * dT` with `mdot * integral_cp`.
**Warning signs:** OFI power disagrees with Python by >1%.

### Pitfall 4: Transient Solution Shape [n_times, n_cells]
**What goes wrong:** Transient solution queries `sol[sys.T[i], :]` return a `Vector{Float64}` (one per time point). Assembling into a matrix needs careful shape management.
**Why it happens:** SciMLBase returns column-major arrays; each `sol[sys.T[i], :]` is a time series for cell i.
**How to avoid:** For n cells: `T_bulk = hcat([sol[channel_sys.T[i], :] for i in 1:n]...)` gives `[n_times, n_cells]` shape. Broadcasting in wrappers (`.` operations) works on both Vector (steady) and Matrix columns (transient).
**Warning signs:** `DimensionMismatch` in wrapper broadcasting.

### Pitfall 5: Sudo-Kaminaga Direction-Dependent Selection
**What goes wrong:** Sudo-Kaminaga has FOUR sub-correlations (q1, q2, q3, q4) with direction-dependent selection rules. Upward flow uses max(max(min(q2,q4), q1), q3). Downward uses max(min(q2,q4), q3).
**Why it happens:** The correlation covers countercurrent flow limiting (q3) and different regime transitions for upward vs downward flow.
**How to avoid:** Port the Python logic exactly, including the `G_star >= 0` (downward) vs `G_star < 0` (upward) split. Note that Python STREAM uses `np.maximum`/`np.minimum` (elementwise), so Julia should use `max.`/`min.` broadcasting or plain comparisons for scalar inputs.
**Warning signs:** CHF values differ by orders of magnitude for negative (upward) flow.

### Pitfall 6: q_flux vs q_wall Units
**What goes wrong:** MTK solution provides `q_wall_left[i]` in Watts (total heat rate), but CHF correlations need `q_flux` in W/m^2 (heat flux per unit area).
**Why it happens:** ChannelAndContacts equations define `q_wall_left[i] ~ thermal_left[i].Q_flow` which is in Watts.
**How to avoid:** D-05 defines: `q_flux_left[i] = q_wall_left[i] / (pipe.heated_parts[1] * dz)`. This conversion happens in `_extract_channel_state`, not in the physics functions.
**Warning signs:** CHFR values are 1e3..1e6 times too large/small.

### Pitfall 7: chfr Guard for q <= 0
**What goes wrong:** Dividing CHF by zero or negative actual flux produces Inf, NaN, or negative values.
**Why it happens:** Adiabatic faces have q_flux = 0; reversed heat flow has q_flux < 0.
**How to avoid:** D-11 mandates: `q_i <= 0 ? Inf : chf_i / q_i`. Never return negative CHFR.
**Warning signs:** NaN or negative safety ratios in results.

## Code Examples

### THRS-01: Bergles-Rohsenow T_ONB (thin wrapper)
```julia
# Source: CONTEXT.md D-03, Python STREAM temperatures.py line 40-69
function Bergles_Rohsenow_T_ONB(pressure, q_wall, T_sat)
    return T_sat + _bergles_rohsenow_dT_ONB(pressure, q_wall)
end
```

### THRS-02: Boiling Onset Power
```julia
# Source: Python STREAM thresholds.py line 273
function q_boiling_onset(mdot, T_sat, T_inlet, cp)
    return abs(mdot) * cp * (T_sat - T_inlet)
end
```

### THRS-06: Mirshak CHF
```julia
# Source: Python STREAM thresholds.py line 475
function q_CHF_mirshak(T_bulk, T_sat, pressure, v)
    return 1.51e6 * (1 + 0.1198 * v) * (1 + 0.00914 * (T_sat - T_bulk)) * (1 + 0.19e-5 * pressure)
end
```

### THRS-07: Fabrega CHF
```julia
# Source: Python STREAM thresholds.py line 497
function q_CHF_fabrega(T_inlet, T_sat, pipe)
    return 1e7 * pipe.Dh * (0.023 * (T_sat - T_inlet) + 4.56)
end
```

### THRS-08: twall_limit
```julia
# Source: CONTEXT.md D-10
function twall_limit(T_wall, inhomogeneity_factor=1.0)
    return T_wall * inhomogeneity_factor
end
```

### THRS-09: ChannelState and extraction
```julia
# Steady-state extraction pattern
n = length(...)  # determine from channel system
T_bulk = [sol[channel_sys.T[i]] for i in 1:n]
T_wall_left = [sol[channel_sys.T_wall_left[i]] for i in 1:n]
mdot = sol[channel_sys.inlet.mdot]
# ... assemble into ChannelState
```

### THRS-09: chfr factory
```julia
function chfr(chf_fn; direction=:max)
    return function(state::ChannelState)
        q = if direction == :left
            state.q_flux_left
        elseif direction == :right
            state.q_flux_right
        elseif direction == :max
            max.(state.q_flux_left, state.q_flux_right)
        elseif direction == :total
            state.q_flux
        end
        chf_vals = chf_fn(state)
        return [q_i > 0 ? c_i / q_i : Inf for (c_i, q_i) in zip(chf_vals, q)]
    end
end
```

## Sudo-Kaminaga Saturation Properties

The `q_CHF_sudo_kaminaga` function requires saturation thermophysical properties not currently available in STREAM.jl. The Python STREAM version receives a `sat_coolant` Liquid object. For the Julia implementation, these must be provided.

**Recommended approach:** Accept keyword arguments with defaults for atmospheric-pressure light water:

```julia
function q_CHF_sudo_kaminaga(T_bulk, mdot, pipe, gravity;
                              rho_l=958.4, rho_v=0.598,
                              hfg=2257e3, sigma=0.059,
                              cp_sat=4217.0, T_sat=373.15)
```

This keeps the positional signature matching REQUIREMENTS.md while allowing advanced users to override saturation properties. The defaults match Python STREAM's light water at 1 atm.

**Important:** Python STREAM uses `pipe.width` (NOT `pipe.heated_perimeter / 2`) in the q3 sub-correlation, per Mishima's experimental basis. Julia `PipeGeometry` has a `.width` field -- use it directly.

## OFI Cp Integration Strategy

Python STREAM's `Whittle_Forgan_OFI` uses `scipy.integrate.quad(cp, T_inlet, T_sat)` to compute the mean-cp-weighted enthalpy rise. The Julia equivalent:

```julia
using QuadGK
integral_cp, _ = quadgk(cp_water, T_inlet, T_sat)
# Then: P_OFI = abs(mdot) * integral_cp / (1 + 3.15 * (Dh/L) * (1.08*G_cgs)^0.29)
```

QuadGK is available through the DifferentialEquations dependency chain. No new package needed.

**Alternative (simpler, slightly less accurate):** Use trapezoidal `cp_avg = (cp_water(T_inlet) + cp_water(T_sat)) / 2; integral = cp_avg * (T_sat - T_inlet)`. This may differ from Python by <0.1% for typical temperature ranges.

## Determining n from MTK Solution

The `_extract_channel_state` helper needs to know how many axial cells the channel has. Options:

1. **Accept n as kwarg:** `threshold_analysis(sol, channel_sys; n, pipe=nothing, ...)` -- explicit but redundant
2. **Probe the solution:** Try `sol[channel_sys.T[i]]` for increasing i until it errors -- fragile
3. **Access MTK system metadata:** `length(channel_sys.T)` should work since T is declared as `(T(t))[1:n]` -- the MTK array variable preserves its length

**Recommendation:** Use `n = length(channel_sys.T)` to determine cell count from the MTK system. This is clean and does not require the user to specify n.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib |
| Config file | test/runtests.jl (thin orchestrator) |
| Quick run command | `julia --project -e 'include("test/test_analysis.jl")'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| THRS-01 | Bergles_Rohsenow_T_ONB returns T_sat + dT_ONB | unit | `julia --project -e 'include("test/test_analysis.jl")'` | No - Wave 0 |
| THRS-02 | q_boiling_onset = abs(mdot)*cp*(T_sat-T_inlet) | unit | same | No - Wave 0 |
| THRS-03 | q_OFI Whittle-Forgan with CGS G and cp integral | unit | same | No - Wave 0 |
| THRS-04 | q_OSV Saha-Zuber computed_bulk, Pe regime switch | unit | same | No - Wave 0 |
| THRS-05 | q_CHF Sudo-Kaminaga direction-dependent | unit | same | No - Wave 0 |
| THRS-06 | q_CHF Mirshak formula | unit | same | No - Wave 0 |
| THRS-07 | q_CHF Fabrega formula | unit | same | No - Wave 0 |
| THRS-08 | twall_limit scaling | unit | same | No - Wave 0 |
| THRS-09 | threshold_analysis end-to-end with MTK solution | integration | same | No - Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project -e 'include("test/test_analysis.jl")'`
- **Per wave merge:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
- [ ] `test/test_analysis.jl` -- covers THRS-01..09
- [ ] Add `include("test_analysis.jl")` to `test/runtests.jl`
- [ ] No framework install needed (Julia Test stdlib)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Python STREAM `Saha_Zuber_OSV` (non-self-consistent) | `Saha_Zuber_OSV_computed_bulk` (self-consistent) | Pre-existing | THRS-04 uses computed_bulk variant only |
| Python STREAM Sudo q3: `1+dT` vs `1+3dT` debate | `1+dT` (conservative) | Ongoing | Use `1+dT_inlet` in q3 per Python STREAM current implementation |

## Open Questions

1. **Sudo-Kaminaga saturation property source**
   - What we know: Python STREAM uses Liquid object properties at saturation. Julia STREAM has no vapor/two-phase properties.
   - What's unclear: Whether to hardcode at 1 atm or accept pressure-dependent values via kwargs.
   - Recommendation: Use keyword arguments with atmospheric defaults -- most flexible, matches REQUIREMENTS.md positional signature, and users can override for non-atmospheric conditions.

2. **Determining n from channel_sys**
   - What we know: `channel_sys.T` is declared as `(T(t))[1:n]` in MTK.
   - What's unclear: Whether `length(channel_sys.T)` works on a compiled system variable.
   - Recommendation: Try `length(channel_sys.T)` first; fall back to requiring n as kwarg if it fails.

3. **Transient ChannelState matrix assembly**
   - What we know: `sol[sys.var, :]` returns Vector{Float64} per variable per time.
   - What's unclear: Exact shape when assembling n cells x n_times.
   - Recommendation: Test with `hcat([sol[channel_sys.T[i], :] for i in 1:n]...)` to get [n_times, n_cells].

## Project Constraints (from CLAUDE.md)

- All exports declared in `src/STREAM.jl` only (never in component files)
- Internal helpers prefixed with `_` and not exported
- Every exported name has a docstring with `# Arguments`, `# Returns`
- Positional arguments when dispatch or single-param clarity applies; keyword-only for multi-param
- `name` kwarg always keyword-only (not relevant for threshold functions)
- Test file mirrors src file: `analysis.jl` -> `test_analysis.jl`
- New physics file -> `src/physical_models/` directory
- `src/STREAM.jl` must include both new files and export all public names

## Sources

### Primary (HIGH confidence)
- Python STREAM `physical_models/thresholds.py` -- exact formulas for THRS-02..07
- Python STREAM `analysis/thresholds.py` -- analysis wrapper pattern, chfr logic
- Python STREAM `heat_transfer_coefficient/temperatures.py` -- Bergles_Rohsenow_T_ONB formula
- Existing codebase: `src/physical_models/correlations.jl` -- `_bergles_rohsenow_dT_ONB` implementation
- Existing codebase: `src/physical_models/subcooled_boiling.jl` -- file structure template
- Existing codebase: `src/components/thermal_channel.jl` -- available @observed variables
- Existing codebase: `src/solvers.jl` -- solution query patterns
- Existing codebase: `src/geometry.jl` -- PipeGeometry fields

### Secondary (MEDIUM confidence)
- Sudo/Kaminaga 1998 JNST paper (referenced via Python STREAM docstrings) -- q3 `1+dT` vs `1+3dT`

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new packages, all patterns established in codebase
- Architecture: HIGH -- CONTEXT.md specifies complete architecture with detailed decisions
- Pitfalls: HIGH -- Python reference implementation provides exact formulas and edge cases
- Physics formulas: HIGH -- direct port from Python STREAM with verified code

**Research date:** 2026-03-31
**Valid until:** 2026-04-30 (stable domain -- nuclear correlations don't change)
