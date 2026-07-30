# subcooled_boiling.jl -- Subcooled boiling heat flux correlations
#
# Design:
#   - Standalone named functions (mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux,
#     partial_SCB_correction): plain Julia arithmetic, NOT @register_symbolic.
#     MTK traces through these symbolically when T_wall/T_sat are symbolic.
#   - Factory (regime_dependent_q_scb): returns a closure that captures construction-time
#     scalars (pressure, h_fg, sigma); inner function receives symbolic T_wall, T_sat, Re.
#   - ifelse() for guards — same MTK pattern as flow reversal and regime switching.

# Bergles-Rohsenow wall superheat at the onset of nucleate boiling, T_ONB - T_sat, for a
# single-phase wall heat flux `q_spl` [W/m^2] at pressure `P_Pa`. It sets where boiling
# starts, so it belongs with the boiling physics rather than with the HTC correlations.
function _bergles_rohsenow_dT_ONB(P_Pa, q_spl)
    p = P_Pa / 1e5
    return 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
end

"""
    mcadams_scb_heat_flux(T_sat, T_wall) -> q [W/m^2]

McAdams (1949) subcooled boiling heat flux correlation for water.
Formula: `q = 740.0 * (T_wall - T_sat)^3.86` [W/m^2].

The coefficient 740 corresponds to McAdams' original `0.074 W/cm^2/K^3.86`
converted to SI units (0.074 * 1e4 = 740).

Returns 0.0 when `T_wall <= T_sat` (no boiling below saturation).
Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `T_sat`: saturation temperature [°C]
- `T_wall`: wall temperature [°C]

# Returns
Subcooled boiling heat flux `q` [W/m^2].
"""
function mcadams_scb_heat_flux(T_sat, T_wall)
    dT = T_wall - T_sat
    dT_safe = max(dT, 0.0)
    return ifelse(dT > 0, 740.0 * dT_safe^3.86, 0.0)
end

"""
    bergles_rohsenow_scb_heat_flux(T_wall, T_sat, pressure; h_fg=2257e3, sigma=0.059) -> q [W/m^2]

Bergles-Rohsenow (1964) subcooled boiling heat flux correlation.
Formula: `q = 1082.0 * p^1.156 * dT^(1.0 / (0.463 * p^0.0234))` [W/m^2]
where `p = pressure / 1e5` (pressure in bar) and `dT = T_wall - T_sat`.

This is the inverse of the `_bergles_rohsenow_dT_ONB` formula in correlations.jl,
using the same `1082 * p^1.156` coefficient family for consistency.

Returns 0.0 when `T_wall <= T_sat` (no boiling below saturation).
Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `T_wall`: wall temperature [°C]
- `T_sat`: saturation temperature [°C]
- `pressure`: system pressure [Pa]
- `h_fg`: latent heat of vaporization [J/kg] (reserved for forward compatibility; not used in current formula)
- `sigma`: surface tension [N/m] (reserved for forward compatibility; not used in current formula)

# Returns
Subcooled boiling heat flux `q` [W/m^2].
"""
function bergles_rohsenow_scb_heat_flux(T_wall, T_sat, pressure; h_fg=2257e3, sigma=0.059)
    dT = T_wall - T_sat
    p = pressure / 1e5  # Pa to bar
    dT_safe = max(dT, 0.0)
    return ifelse(dT > 0, 1082.0 * p^1.156 * dT_safe^(1.0 / (0.463 * p^0.0234)), 0.0)
end

"""
    partial_SCB_correction(q_spl, q_scb, q_scb_inc) -> factor (dimensionless)

Bergles-Rohsenow partial boiling superposition correction factor.
Formula: `factor = sqrt(1 + (q_scb^2 - q_scb_inc^2) / q_spl^2)`

This factor multiplies the single-phase HTC to produce the effective HTC
in the partial subcooled boiling regime. The factor is >= 1.0 when boiling
is active (`q_scb > q_scb_inc`) and exactly 1.0 otherwise.

Guards:
- Returns 1.0 when `q_spl <= 0` (division-by-zero safety)
- Returns 1.0 when `q_scb^2 <= q_scb_inc^2` (outside boiling regime)

Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `q_spl`: single-phase convective heat flux [W/m^2]
- `q_scb`: subcooled boiling heat flux at wall temperature [W/m^2]
- `q_scb_inc`: subcooled boiling heat flux at onset of nucleate boiling temperature [W/m^2]

# Returns
Dimensionless correction factor (>= 1.0).
"""
function partial_SCB_correction(q_spl, q_scb, q_scb_inc)
    q_spl_sq = max(q_spl^2, 1e-20)
    ratio = (q_scb^2 - q_scb_inc^2) / q_spl_sq
    safe_arg = max(1 + ratio, 1.0)
    return ifelse(q_spl > 0, ifelse(ratio > 0, sqrt(safe_arg), 1.0), 1.0)
end

"""
    regime_dependent_q_scb(; pressure=1e5, h_fg=2257e3, sigma=0.059, re_bounds=(2000.0, 5000.0)) -> (T_wall, T_sat, Re) -> q [W/m^2]

Factory returning a regime-dependent subcooled boiling heat flux closure: Bergles-Rohsenow
in the laminar regime, McAdams in the turbulent one, and a linear blend across the
transition band, via [`flow_regime_blend`](@ref). Python STREAM's `regime_dependent_q_scb`
partitions the same way.

Captures `pressure`, `h_fg`, and `sigma` at construction time. The returned
closure signature `(T_wall, T_sat, Re) -> q_scb` is compatible with the
`scb_correction` kwarg of `ChannelAndContacts`.

Follows the same factory pattern as `regime_dependent` in correlations.jl.
Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `pressure`: system pressure [Pa] (default 1e5 = 1 bar)
- `h_fg`: latent heat of vaporization [J/kg] (default 2257e3 for water at ~100C)
- `sigma`: surface tension [N/m] (default 0.059 for water at ~100C)
- `re_bounds`: `(re_lo, re_hi)` transition band on the Reynolds number
(default `(2000.0, 5000.0)`)

# Returns
Closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]`.
"""
function regime_dependent_q_scb(;
    pressure=1e5, h_fg=2257e3, sigma=0.059, re_bounds=(2000.0, 5000.0)
)
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return (T_wall, T_sat, Re) -> flow_regime_blend(
        Re, bounds,
        bergles_rohsenow_scb_heat_flux(T_wall, T_sat, pressure; h_fg=h_fg, sigma=sigma),
        mcadams_scb_heat_flux(T_sat, T_wall),
    )
end

"""
    h_subcooled_boiling(T_wall, T_bulk, P, ṁ, Dh, A, nusselt, q_scb, liquid) -> W/(m^2·K)

Heat transfer coefficient with partial subcooled boiling folded in: the single-phase value
below the onset of nucleate boiling, and that value scaled by the Bergles-Rohsenow partial
boiling factor at or above it.

The switch is `ifelse` on `T_wall >= T_ONB`, so it stays a symbolic branch the solver
evaluates per step rather than one fixed at trace time.

# Arguments
- `T_wall`, `T_bulk`: wall and bulk coolant temperature [°C]
- `P`: local absolute pressure [Pa], which sets `T_sat` and the ONB superheat
- `ṁ`: mass flow rate [kg/s]
- `Dh`: hydraulic diameter [m]
- `A`: flow area [m^2]
- `nusselt`: single-phase Nusselt correlation, as for [`h_single_phase`](@ref)
- `q_scb`: subcooled boiling heat flux closure `(T_wall, T_sat, Re) -> q [W/m^2]`, e.g. from
  [`regime_dependent_q_scb`](@ref)
- `liquid`: coolant (`AbstractLiquid`)

# Returns
Heat transfer coefficient [W/(m^2·K)].
"""
function h_subcooled_boiling(T_wall::Real, T_bulk::Real, P::Real, ṁ::Real, Dh::Real,
                             A::Real, nusselt::Function, q_scb::Function, liquid)
    h_spl = h_single_phase(T_wall, T_bulk, ṁ, Dh, A, nusselt, liquid)
    q_spl = max(h_spl * (T_wall - T_bulk), 0.0)
    T_sat = Tsat(liquid, P)
    Re_bulk = Re(ṁ, A, Dh, μ(liquid, T_bulk))
    T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)
    factor = partial_SCB_correction(
        q_spl, q_scb(T_wall, T_sat, Re_bulk), q_scb(T_ONB, T_sat, Re_bulk)
    )
    return ifelse(T_wall >= T_ONB, h_spl * factor, h_spl)
end
