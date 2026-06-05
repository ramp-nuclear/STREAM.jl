# subcooled_boiling.jl — Subcooled boiling heat flux correlations for STREAM.jl
#
# Design:
#   - Standalone named functions (mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux,
#     partial_SCB_correction): plain Julia arithmetic, NOT @register_symbolic.
#     MTK traces through these symbolically when T_wall/T_sat are symbolic.
#   - Factory (regime_dependent_q_scb): returns a closure that captures construction-time
#     scalars (pressure, h_fg, sigma); inner function receives symbolic T_wall, T_sat, Re.
#   - ifelse() for guards — same MTK pattern as flow reversal and regime switching.

"""
    mcadams_scb_heat_flux(T_sat, T_wall) -> q [W/m^2]

McAdams (1949) subcooled boiling heat flux correlation for water.
Formula: `q = 740.0 * (T_wall - T_sat)^3.86` [W/m^2].

The coefficient 740 corresponds to McAdams' original `0.074 W/cm^2/K^3.86`
converted to SI units (0.074 * 1e4 = 740).

Returns 0.0 when `T_wall <= T_sat` (no boiling below saturation).
Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `T_sat`: saturation temperature [K]
- `T_wall`: wall temperature [K]

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
- `T_wall`: wall temperature [K]
- `T_sat`: saturation temperature [K]
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
    regime_dependent_q_scb(; pressure=1e5, h_fg=2257e3, sigma=0.059, Re_transition=2300) -> (T_wall, T_sat, Re) -> q [W/m^2]

Factory returning a regime-dependent subcooled boiling heat flux closure.
Sharp cutoff at `Re_transition`: McAdams for `Re >= Re_transition`,
Bergles-Rohsenow for `Re < Re_transition`.

Captures `pressure`, `h_fg`, and `sigma` at construction time. The returned
closure signature `(T_wall, T_sat, Re) -> q_scb` is compatible with the
`scb_correction` kwarg of `ChannelAndContacts`.

Follows the same factory pattern as `regime_dependent` in correlations.jl.
Uses `ifelse()` for MTK-compatible symbolic conditional evaluation.

# Arguments
- `pressure`: system pressure [Pa] (default 1e5 = 1 bar)
- `h_fg`: latent heat of vaporization [J/kg] (default 2257e3 for water at ~100C)
- `sigma`: surface tension [N/m] (default 0.059 for water at ~100C)
- `Re_transition`: Reynolds number transition threshold (default 2300)

# Returns
Closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]`.
"""
function regime_dependent_q_scb(;
    pressure=1e5, h_fg=2257e3, sigma=0.059, Re_transition=2300
)
    Re_tr = Float64(Re_transition)
    return (T_wall, T_sat, Re) -> ifelse(
        Re >= Re_tr,
        mcadams_scb_heat_flux(T_sat, T_wall),
        bergles_rohsenow_scb_heat_flux(T_wall, T_sat, pressure; h_fg=h_fg, sigma=sigma),
    )
end
