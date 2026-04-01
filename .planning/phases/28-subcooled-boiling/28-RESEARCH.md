# Phase 28: Subcooled Boiling - Research

**Researched:** 2026-03-29
**Domain:** Subcooled boiling heat transfer correlations + MTK component integration
**Confidence:** HIGH

## Summary

Phase 28 adds subcooled boiling (SCB) heat flux correlations as standalone Julia functions and optionally integrates them into ChannelAndContacts via an `scb_correction` closure kwarg. The implementation domain is well-constrained: four standalone correlation functions in a new file (`src/physical_models/subcooled_boiling.jl`), plus a conditional modification to the `h_tc[i]` equation in ChannelAndContacts.

The key technical challenge is the ISCB-01 integration: modifying `h_tc[i]` in ChannelAndContacts while preserving backward compatibility when `scb_correction=nothing`. The existing `_channel_base_eqs` helper generates `h_tc[i]` equations (line 163 of channel.jl), so the SCB correction must either modify the h_tc equation after `_channel_base_eqs` returns, or be wired directly in the ChannelAndContacts constructor loop. The CONTEXT.md leaves this choice to Claude's discretion.

**Primary recommendation:** Implement standalone SCB functions first (pure arithmetic, easy to test), then integrate into ChannelAndContacts by replacing the `h_tc[i]` equation post-`_channel_base_eqs` when `scb_correction` is provided.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** All SCB correlation functions go in a new `src/physical_models/subcooled_boiling.jl` file (per REQUIREMENTS.md). Not added to the existing correlations.jl.
- **D-02:** `McAdams_SCB_heat_flux(T_sat, T_wall)` -- standalone function returning W/m^2; signature matches REQUIREMENTS.md exactly.
- **D-03:** `Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure; h_fg=..., sigma=...)` -- h_fg and sigma are optional keyword arguments with light-water defaults at ~100C (h_fg ~ 2257 kJ/kg, sigma ~ 0.059 N/m). Callers can override for non-standard conditions.
- **D-04:** `partial_SCB_correction(q_spl, q_scb, q_scb_inc)` -- dimensionless factor; Bergles-Rohsenow smooth SPL<->SCB blend. Returns 1.0 when q_spl >= q_scb (no correction needed outside boiling regime).
- **D-05:** `regime_dependent_q_scb(T_wall, T_sat, Re; Re_transition=2300)` -- sharp cutoff (no interpolation zone); McAdams for Re >= Re_transition, Bergles-Rohsenow for Re < Re_transition. Consistent with existing `regime_dependent` pattern. The `re_bounds` name from REQUIREMENTS.md maps to a single `Re_transition` kwarg (not a tuple).
- **D-06:** `ChannelAndContacts` gains an optional `scb_correction` kwarg (`nothing` by default). When provided, it is a q-flux closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]` (e.g. a `regime_dependent_q_scb` call with appropriate re_bounds).
- **D-07:** ChannelAndContacts calls the closure twice per cell -- once at T_wall[i] to get q_scb and once at T_ONB[i] to get q_scb_inc -- then calls `partial_SCB_correction(q_spl, q_scb, q_scb_inc)` internally to compute the factor.
- **D-08:** Modified h_tc[i] equation (per ISCB-01): `ifelse(T_wall[i] >= T_ONB[i], h_spl[i] * partial_scb_factor, h_spl[i])` -- uses the established `ifelse()` MTK pattern. This replaces the existing `h_tc[i] ~ ...` equation in the energy balance.
- **D-09:** When `scb_correction` is `nothing` (default), ChannelAndContacts behavior is identical to the current implementation -- no performance impact, no new equations.

### Claude's Discretion
- Exact McAdams coefficient and exponent (match Python STREAM physical_models exactly)
- Exact Bergles-Rohsenow formula variant and coefficient (match Python STREAM temperatures.py / heat_transfer.py)
- Whether `scb_correction` wiring goes through `_channel_base_eqs` or directly in the ChannelAndContacts constructor (whichever avoids observed_mode complexity)
- Light-water default values for h_fg and sigma (verify against Python STREAM or standard water tables)
- Export names in STREAM.jl (follow existing export pattern; `_private` prefix for internal helpers)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCB-01 | McAdams_SCB_heat_flux(T_sat, T_wall) -> W/m^2 as standalone function | Standalone arithmetic function in subcooled_boiling.jl; McAdams correlation q = C * (T_wall - T_sat)^n where C and n are well-known from nuclear TH literature |
| SCB-02 | Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure, ...) -> W/m^2 | Standalone function with h_fg, sigma kwargs; uses Bergles-Rohsenow family formula consistent with existing `_bergles_rohsenow_dT_ONB` |
| SCB-03 | partial_SCB_correction(q_spl, q_scb, q_scb_inc) -> dimensionless factor | Bergles-Rohsenow superposition: factor = sqrt(1 + (q_scb^2 - q_scb_inc^2) / q_spl^2) |
| SCB-04 | regime_dependent_q_scb(T_wall, T_sat, Re, re_bounds) selects McAdams or Bergles-Rohsenow | Factory using ifelse() sharp cutoff at Re_transition=2300; follows regime_dependent pattern in correlations.jl |
| ISCB-01 | ChannelAndContacts scb_correction kwarg; h_tc[i] replaced by ifelse(T_wall[i] >= T_ONB[i], h_spl[i]*factor, h_spl[i]) | Modify h_tc[i] equation in ChannelAndContacts constructor; T_ONB[i] already available as observed |
| ISCB-02 | Validation: T_wall >> T_sat gives higher HTC; T_wall < T_ONB gives exact single-phase match | Integration test with ConstantTemperature BCs at high/low wall temps |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | (existing) | Symbolic equation system | Project foundation |
| DifferentialEquations.jl | (existing) | ODE/DAE solver | Project foundation |

### Supporting
No new libraries required. Phase 28 uses only plain Julia arithmetic and existing MTK patterns.

## Architecture Patterns

### Recommended Project Structure
```
src/
  physical_models/
    subcooled_boiling.jl     # NEW: McAdams, Bergles-Rohsenow SCB, partial_SCB_correction, regime_dependent_q_scb
    correlations.jl          # EXISTING: _bergles_rohsenow_dT_ONB stays here (used by T_ONB observable)
  components/
    thermal_channel.jl       # MODIFIED: ChannelAndContacts gains scb_correction kwarg
  STREAM.jl                  # MODIFIED: include + export new functions
test/
  test_subcooled_boiling.jl  # NEW: unit + integration tests for SCB-01..04, ISCB-01..02
  runtests.jl                # MODIFIED: add include("test_subcooled_boiling.jl")
```

### Pattern 1: SCB Standalone Correlation Functions
**What:** Pure Julia arithmetic functions, NOT `@register_symbolic`. MTK traces through them symbolically.
**When to use:** All SCB correlation functions.
**Example:**
```julia
# Source: existing correlations.jl pattern (dittus_boelter, elenbaas_nusselt)
"""
    McAdams_SCB_heat_flux(T_sat, T_wall) -> q [W/m^2]
"""
function McAdams_SCB_heat_flux(T_sat, T_wall)
    dT = T_wall - T_sat
    # McAdams (1949): q = C * dT^n for subcooled water
    # Coefficients from nuclear TH reference (match Python STREAM)
    return C * dT^n
end
```

### Pattern 2: SCB Closure Factory (regime_dependent_q_scb)
**What:** Returns a closure `(T_wall, T_sat, Re) -> q_scb` that selects McAdams or Bergles-Rohsenow based on Re.
**When to use:** SCB-04 implementation; follows existing `regime_dependent` pattern.
**Example:**
```julia
# Source: existing regime_dependent() in correlations.jl
function regime_dependent_q_scb(T_wall, T_sat, Re; Re_transition=2300)
    Re_tr = Float64(Re_transition)
    q_mcadams = McAdams_SCB_heat_flux(T_sat, T_wall)
    q_bergles = Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure_default)
    ifelse(Re >= Re_tr, q_mcadams, q_bergles)
end
```
**Note:** Unlike `regime_dependent` which is a factory returning closures, D-05 specifies `regime_dependent_q_scb` as a direct function call (not a factory). It receives symbolic T_wall, T_sat, Re at equation time. The pressure needs to come from somewhere -- the CONTEXT.md D-06 specifies the scb_correction closure captures construction-time constants.

### Pattern 3: Conditional h_tc Modification in ChannelAndContacts
**What:** When `scb_correction !== nothing`, replace the `h_tc[i]` equation with one that applies the SCB factor.
**When to use:** ISCB-01 integration.
**Key design decision:** The `_channel_base_eqs` helper pushes `h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh` into `eqs`. Two options:

**Option A (recommended): Post-replace in ChannelAndContacts constructor.**
After `_channel_base_eqs` returns, find and replace each `h_tc[i]` equation when `scb_correction` is non-nothing. This avoids modifying `_channel_base_eqs` signature or adding complexity to the shared helper.

Implementation sketch:
```julia
if scb_correction !== nothing
    for i in 1:n
        # Compute h_spl[i] (the single-phase HTC from the correlation, same as current h_tc)
        Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        T_w_i = thermal_left[i].T
        h_spl_i = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh

        # Compute SCB quantities
        P_i_expr = ...  # inline P[i] expression (avoid observed-to-observed chain)
        T_sat_i = sat_temperature(P_i_expr)
        q_spl_i = ...   # from q_wall or h_spl * A_heated * (T_w - T)
        q_scb_i = scb_correction(T_w_i, T_sat_i, Re_i)
        T_ONB_i = T_sat_i + _bergles_rohsenow_dT_ONB(P_i_expr, q_spl_i)
        q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i)
        factor_i = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

        # Replace h_tc[i] equation: find index and overwrite
        # h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i)
    end
end
```

**Option B: Branch inside _channel_base_eqs.**
Pass `scb_correction` as an optional kwarg to `_channel_base_eqs` and generate the modified h_tc[i] equation there. Downside: adds complexity to a shared helper that other channel variants (Channel, ChannelHeatFlux) do not need.

**Recommendation:** Option A. ChannelAndContacts already has substantial custom logic after `_channel_base_eqs` returns (energy balance, thermal port wiring, observed block). Adding the SCB modification there keeps the shared helper clean.

### Pattern 4: Equation Replacement Strategy
**What:** After `_channel_base_eqs` pushes `h_tc[i] ~ expr` into `eqs`, we need to replace those equations.
**When to use:** When scb_correction is non-nothing.
**Implementation detail:** `_channel_base_eqs` pushes h_tc equations in order. We can either:
1. Track indices where h_tc equations were pushed (fragile, index-dependent)
2. Filter `eqs` to remove h_tc equations and push new ones (safer)
3. Push h_tc equations only when scb_correction is nothing; otherwise push SCB-modified versions directly

**Recommended approach (3):** Modify the ChannelAndContacts function to pass a flag or skip the h_tc push from `_channel_base_eqs`, then push the correct version in the constructor. This is cleanest but requires a small change to `_channel_base_eqs` (add `skip_htc=false` kwarg). When `skip_htc=true`, `_channel_base_eqs` omits the `h_tc[i]` equation, and the caller is responsible for pushing it.

**Alternative (filter-based):** After `_channel_base_eqs` returns, filter out equations containing `h_tc[i]` on the LHS and replace them. This is less invasive to `_channel_base_eqs` but relies on equation inspection.

**Simplest approach:** Since `_channel_base_eqs` pushes h_tc equations at known positions in the loop (one per cell, at the start of the i-loop), and ChannelAndContacts always calls it with `observed_mode=true`, the h_tc equations are the first n equations pushed. After the call, pop those n equations and push the SCB-corrected versions. Or better: let `_channel_base_eqs` always push h_tc, then when scb_correction is present, iterate through `eqs` and replace any equation whose LHS matches `h_tc[i]`.

### Anti-Patterns to Avoid
- **Making h_tc[i] an @observed variable:** h_tc[i] appears on the RHS of the energy balance (thermal_left.Q_flow, thermal_right.Q_flow, Dt(T[i])). It MUST remain an MTK unknown, not observed.
- **Referencing T_ONB[i] or P[i] observed variables in equations:** These are observed quantities. Using them on the RHS of an equation creates observed-to-observed chains that MTK cannot resolve. Always inline the P[i] expression (as done in the existing codebase, lines 150-154 of thermal_channel.jl).
- **Using `if` instead of `ifelse()`:** Julia `if` evaluates at trace time. `ifelse()` creates a symbolic conditional node evaluated at solve time. Required for `T_wall[i] >= T_ONB[i]` switching.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Saturation temperature from pressure | Custom Antoine eq | `sat_temperature(P)` | Already @register_symbolic in fluids.jl |
| T_ONB offset | Custom ONB formula | `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` | Already exists in correlations.jl |
| Regime switching | Manual if/else | `ifelse()` MTK pattern | Established project convention |

## Common Pitfalls

### Pitfall 1: Observed-to-Observed Chain in SCB Integration
**What goes wrong:** Using `T_ONB[i]` (observed) inside the `h_tc[i]` equation (unknown) creates an observed-to-observed dependency chain that MTK cannot resolve.
**Why it happens:** T_ONB[i] is defined as an observed variable. If h_tc[i] references it, MTK sees an unknown depending on an observed -- illegal.
**How to avoid:** Inline the full T_ONB expression: `sat_temperature(P_i_expr) + _bergles_rohsenow_dT_ONB(P_i_expr, q_spl_i_expr)` where P_i_expr and q_spl_i_expr are built from unknowns (dp[j], q_wall[i]) not from observed symbols.
**Warning signs:** MTK error during `mtkcompile`: "observed variable appears in equation RHS."

### Pitfall 2: Circular Dependency Between q_spl and h_tc
**What goes wrong:** `q_spl_i` depends on `q_wall[i]` which depends on `h_tc[i]` which (with SCB correction) depends on `q_spl_i`. This is a circular algebraic dependency.
**Why it happens:** The partial_SCB_correction formula needs q_spl as input, but q_spl = h_tc * A_heated * dz * (T_wall - T) / (A_heated * dz) = h_tc * (T_wall - T). If h_tc depends on q_spl, we have a loop.
**How to avoid:** Use the **single-phase** heat flux `q_spl` computed from the base h_spl (before SCB correction): `q_spl_i = h_spl_i * (T_wall_i - T[i])` where h_spl_i is the uncorrected HTC. The SCB factor then multiplies h_spl_i. This breaks the circular dependency because h_spl_i does not depend on the SCB-corrected q.
**Warning signs:** MTK structural singularity error during `mtkcompile`.

### Pitfall 3: Division by Zero in partial_SCB_correction
**What goes wrong:** When q_spl = 0 (no heat transfer), the formula `sqrt(1 + (q_scb^2 - q_scb_inc^2) / q_spl^2)` divides by zero.
**Why it happens:** At initialization or in adiabatic regions, q_spl can be zero.
**How to avoid:** The `ifelse(T_wall >= T_ONB, corrected, uncorrected)` guard in ISCB-01 prevents this: when T_wall < T_ONB, the partial_SCB_correction is never evaluated. Additionally, when T_wall = T_sat (q_spl = 0), T_ONB > T_sat always holds (positive _bergles_rohsenow_dT_ONB offset), so the uncorrected branch is selected. For extra safety, `partial_SCB_correction` itself should return 1.0 when q_spl <= 0.
**Warning signs:** NaN or Inf in solution at early timesteps.

### Pitfall 4: Type Promotion with Symbolic Expressions
**What goes wrong:** Literal Julia `Float64` constants mixed with MTK `Num` expressions can cause type promotion errors.
**Why it happens:** `ifelse()` and arithmetic on symbolic expressions require consistent types.
**How to avoid:** All constants should be `Float64` literals (e.g., `2257e3` not `2257000`). Follow existing pattern: `Re_tr = Float64(Re_transition)` in regime_dependent.
**Warning signs:** MethodError during system construction.

### Pitfall 5: Pressure Argument in regime_dependent_q_scb
**What goes wrong:** `Bergles_Rohsenow_SCB_heat_flux` needs pressure as an argument, but `regime_dependent_q_scb` only takes `(T_wall, T_sat, Re)` per D-05 signature.
**Why it happens:** D-06 specifies the scb_correction closure captures construction-time constants.
**How to avoid:** `regime_dependent_q_scb` should be a **factory** that captures `pressure` (and optionally `h_fg`, `sigma`) at construction time, returning a closure `(T_wall, T_sat, Re) -> q_scb`. This matches D-06 which calls it "a q-flux closure." Alternatively, the pressure can be a default captured at definition time. The CONTEXT.md D-05 signature `regime_dependent_q_scb(T_wall, T_sat, Re; Re_transition=2300)` suggests it's a direct function -- but it also needs pressure for Bergles-Rohsenow. Resolution: add `pressure` as a required positional argument or kwarg: `regime_dependent_q_scb(T_wall, T_sat, Re; pressure=1e5, Re_transition=2300)`.

## Code Examples

### McAdams SCB Heat Flux (SCB-01)
```julia
# McAdams (1949) subcooled boiling heat flux for water
# q'' = 0.074 * dT_sat^3.86  [W/cm^2] (original units)
# Convert to SI: q [W/m^2] = 0.074 * 1e4 * dT_sat^3.86 = 740 * dT_sat^3.86
# NOTE: Exact coefficient must be verified against Python STREAM.
# Alternative common form: q = C * p^a * dT^n where p = pressure in bar
# The _bergles_rohsenow_dT_ONB already uses 1082*p^1.156 family of constants.
function McAdams_SCB_heat_flux(T_sat, T_wall)
    dT = T_wall - T_sat
    # Guard: no boiling when wall below saturation
    return ifelse(dT > 0, COEFF * dT^EXPONENT, 0.0)
end
```

### Bergles-Rohsenow SCB Heat Flux (SCB-02)
```julia
# Bergles-Rohsenow (1964) subcooled boiling heat flux
# Uses surface tension (sigma) and latent heat (h_fg) for nucleation physics
function Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure;
                                         h_fg=2257e3, sigma=0.059)
    dT = T_wall - T_sat
    # Formula from Bergles-Rohsenow family
    # Exact form matches Python STREAM (Claude's discretion)
    return ifelse(dT > 0, FORMULA_EXPR, 0.0)
end
```

### partial_SCB_correction (SCB-03)
```julia
# Bergles-Rohsenow partial boiling interpolation
# q_total = q_spl * sqrt(1 + ((q_scb/q_spl)^2 - (q_scb_inc/q_spl)^2))
# factor = q_total / q_spl = sqrt(1 + (q_scb^2 - q_scb_inc^2) / q_spl^2)
# Returns dimensionless correction factor >= 1.0
function partial_SCB_correction(q_spl, q_scb, q_scb_inc)
    # D-04: returns 1.0 when outside boiling regime
    ratio = (q_scb^2 - q_scb_inc^2) / q_spl^2
    return ifelse(ratio > 0, sqrt(1 + ratio), 1.0)
end
```

### ChannelAndContacts SCB Integration (ISCB-01)
```julia
# In ChannelAndContacts constructor, after _channel_base_eqs:
if scb_correction !== nothing
    for i in 1:n
        # h_spl_i: single-phase HTC (what _channel_base_eqs computed)
        Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        T_w_i = thermal_left[i].T
        h_spl_i = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh

        # Inline P[i] and T_ONB[i] expressions (avoid observed refs)
        P_i = port_in.P - sum(dp[j] for j in 1:i) - (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
        T_sat_i = sat_temperature(P_i)
        q_spl_i = h_spl_i * (T_w_i - T[i])  # single-phase heat flux density [W/m^2]

        # SCB correction (D-07: call closure twice per cell)
        q_scb_i = scb_correction(T_w_i, T_sat_i, Re_i)
        T_ONB_i = T_sat_i + _bergles_rohsenow_dT_ONB(P_i, q_spl_i)
        q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i)
        factor_i = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

        # Replace h_tc[i] equation (D-08)
        # Find and replace the h_tc[i] equation pushed by _channel_base_eqs
        # New: h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i)
    end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single h_tc per channel | Per-cell h_tc with regime switching | Phase 14 (v0.5) | SCB builds on this |
| No pressure field | Per-cell P[i], T_sat[i], T_ONB[i] | Phase 27 (v0.7) | Enables SCB integration |

## Open Questions

1. **Exact McAdams coefficient and exponent**
   - What we know: McAdams (1949) uses q ~ dT^3.86 form; the constant varies by source and unit system
   - What's unclear: Python STREAM is unavailable; exact coefficient cannot be verified against reference implementation
   - Recommendation: Use the well-known nuclear TH textbook form. The implementer should try the standard `q = 740 * dT^3.86` [W/m^2] form (McAdams for water at ~1 atm). If Python STREAM becomes available, verify. Flag as LOW confidence on exact coefficient.

2. **Exact Bergles-Rohsenow SCB heat flux formula**
   - What we know: Bergles-Rohsenow family; `_bergles_rohsenow_dT_ONB` already uses `1082 * p^1.156` where p = P/1e5 (bar). The SCB heat flux formula is related but distinct.
   - What's unclear: The exact Bergles-Rohsenow fully-developed subcooled boiling heat flux formula variant used in Python STREAM
   - Recommendation: Use the standard Bergles-Rohsenow form: `q_scb = 1082 * p^1.156 * dT^(1/(0.463*p^0.0234))` [W/m^2] where dT = T_wall - T_sat, p = P/1e5. This is the inverse of the `_bergles_rohsenow_dT_ONB` formula already in the codebase. Flag as MEDIUM confidence.

3. **q_spl definition for partial_SCB_correction**
   - What we know: q_spl should be the single-phase convective heat flux density [W/m^2]
   - What's unclear: Whether q_spl = h_spl * (T_wall - T_bulk) or h_spl * (T_wall - T_sat)
   - Recommendation: Use `q_spl = h_spl * (T_wall - T_bulk)` since the single-phase HTC correlation gives h based on (T_wall - T_bulk) driving force. This is physically consistent: q_spl is what the single-phase correlation predicts.

4. **Equation replacement mechanics**
   - What we know: `_channel_base_eqs` pushes `h_tc[i] ~ expr` into `eqs` vector
   - What's unclear: Best way to replace specific equations in a Julia `Vector{Equation}`
   - Recommendation: After `_channel_base_eqs` returns, iterate `eqs` and find equations with h_tc[i] on LHS using Symbolics comparison, or add `skip_htc` kwarg to `_channel_base_eqs`. The simplest approach: add `skip_htc=false` kwarg; when true, skip h_tc equations. ChannelAndContacts pushes its own h_tc equations afterward.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + DifferentialEquations.jl |
| Config file | test/runtests.jl (thin orchestrator) |
| Quick run command | `julia --project -e 'using Pkg; Pkg.test()' 2>&1 \| tail -20` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCB-01 | McAdams_SCB_heat_flux returns physically plausible values | unit | `julia --project test/test_subcooled_boiling.jl` | Wave 0 |
| SCB-02 | Bergles_Rohsenow_SCB_heat_flux returns physically plausible values | unit | same | Wave 0 |
| SCB-03 | partial_SCB_correction: 1.0 outside boiling, >1.0 inside | unit | same | Wave 0 |
| SCB-04 | regime_dependent_q_scb: McAdams for turbulent, B-R for laminar | unit | same | Wave 0 |
| ISCB-01 | ChannelAndContacts with scb_correction solves without error | integration | same | Wave 0 |
| ISCB-02 | T_wall >> T_sat: higher HTC; T_wall < T_ONB: matches single-phase | integration | same | Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project -e 'include("test/test_subcooled_boiling.jl")'`
- **Per wave merge:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_subcooled_boiling.jl` -- covers SCB-01..04, ISCB-01..02
- [ ] Add `include("test_subcooled_boiling.jl")` to `test/runtests.jl`

## Project Constraints (from CLAUDE.md)

- New physical correlation file goes in `src/physical_models/subcooled_boiling.jl` (per CLAUDE.md file placement rules)
- Test file: `test/test_subcooled_boiling.jl` (mirrors src file per CLAUDE.md test placement rule)
- All exports declared in `src/STREAM.jl` only (never in component files)
- `name` kwarg is always keyword-only
- Every exported name needs a docstring with description, Arguments, Returns
- Internal helpers prefixed with `_` and not exported
- `ifelse()` for symbolic conditionals (not `if/else`)
- Plain Julia closures for correlations (not `@register_symbolic`)
- `@observed` for diagnostics not on RHS; h_tc is an unknown (on RHS of energy balance)
- `mtkcompile` before solve

## Sources

### Primary (HIGH confidence)
- `src/physical_models/correlations.jl` -- existing `_bergles_rohsenow_dT_ONB`, `regime_dependent` pattern
- `src/components/thermal_channel.jl` -- ChannelAndContacts full implementation, h_tc equations, observed block
- `src/components/channel.jl` -- `_channel_base_eqs` helper, h_tc equation generation
- `CLAUDE.md` -- project conventions for file placement, exports, MTK patterns

### Secondary (MEDIUM confidence)
- [McAdams correlation overview](https://www.nuclear-power.com/nuclear-engineering/heat-transfer/boiling-and-condensation/mcadams-thom-chens-correlation-nucleate-boiling/) -- confirms McAdams q ~ dT^3.86 form
- [Bergles-Rohsenow ONB correlation](https://www.researchgate.net/figure/Comparison-of-ONB-with-the-correlation-of-Bergles-and-Rohsenow-23_fig4_303722870) -- confirms Bergles-Rohsenow family
- [Bergles-Rohsenow 1962 MIT report](http://dspace.mit.edu/bitstream/handle/1721.1/61458/HTL_TR_1962_021.pdf) -- original reference

### Tertiary (LOW confidence)
- McAdams exact coefficient (740 W/m^2/K^3.86 at 1 atm) -- from training data, not verified against Python STREAM
- Bergles-Rohsenow SCB heat flux formula inversion -- inferred from existing `_bergles_rohsenow_dT_ONB`; needs verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, well-understood codebase patterns
- Architecture: HIGH -- clear file placement, established MTK patterns, well-defined integration point
- Correlation formulas: MEDIUM -- McAdams exponent confirmed (3.86), Bergles-Rohsenow family confirmed; exact coefficients need Python STREAM verification (unavailable)
- ISCB integration: MEDIUM -- equation replacement mechanics need implementation-time validation; circular dependency pitfall is real but has clear solution
- Pitfalls: HIGH -- all identified pitfalls have known solutions from existing codebase patterns

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (stable domain; correlation formulas do not change)
