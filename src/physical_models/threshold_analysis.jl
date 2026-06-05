# threshold_analysis.jl -- Post-solve nuclear safety threshold analysis functions
#
# Design:
#   - All functions are plain Julia arithmetic — NOT @register_symbolic, NOT ifelse().
#     These are post-solve analysis functions, not embedded in MTK equations.
#   - They operate on scalar (or vector) Float64 values from solver solutions.
#   - No MTK dependencies here.
#
# Functions: bergles_rohsenow_t_onb, q_boiling_onset, q_OFI_whittle_forgan,
#            q_OSV_saha_zuber, q_CHF_sudo_kaminaga, q_CHF_mirshak,
#            q_CHF_fabrega, twall_limit

# #### Private sub-correlation helpers for Sudo-Kaminaga CHF

function _SKq1(G_star)
    return 0.005 * abs(G_star)^0.611
end

function _SKq2(A_ratio, G_star, dT_inlet)
    return A_ratio * abs(G_star) * dT_inlet
end

function _SKq3(A_ratio, w, lamda, dT_inlet, rho_v, rho_l)
    return 0.7 * A_ratio * sqrt(w / lamda) * (1 + dT_inlet) / (1 + (rho_v / rho_l)^0.25)^2
end

function _SKq4(G_star, dT_outlet)
    return iszero(G_star) ? Inf : _SKq1(G_star) * (1 + 5000 * dT_outlet / abs(G_star))
end

# #### Public API

"""
    bergles_rohsenow_t_onb(pressure, q_wall, T_sat) -> T_ONB [K]

Onset of Nucleate Boiling wall temperature using Bergles-Rohsenow (1964) correlation.
Thin wrapper around the private `_bergles_rohsenow_dT_ONB` helper in correlations.jl.

Formula: `T_ONB = T_sat + 0.556 * (q_wall / (1082 * p^1.156))^(0.463 * p^0.0234)`
where `p = pressure / 1e5` (pressure in bar).

Source: Python STREAM temperatures.py `bergles_rohsenow_t_onb`.

# Arguments
- `pressure`: absolute system pressure [Pa]
- `q_wall`: wall heat flux [W/m^2]
- `T_sat`: saturation temperature [K]

# Returns
Wall temperature at onset of nucleate boiling `T_ONB` [K].
"""
function bergles_rohsenow_t_onb(pressure, q_wall, T_sat)
    return T_sat + _bergles_rohsenow_dT_ONB(pressure, q_wall)
end

"""
    q_boiling_onset(mdot, T_sat, T_inlet, cp) -> Q [W]

Channel power required to reach the saturation temperature at the outlet (Boiling Power / BP).
Also known as the "boiling power limit" per TERMIC/CONVEC.

Formula: `Q = |mdot| * cp * (T_sat - T_inlet)`

Source: Python STREAM thresholds.py `boiling_power`.

# Arguments
- `mdot`: mass flow rate [kg/s] (sign-insensitive; uses `abs(mdot)`)
- `T_sat`: saturation temperature [K]
- `T_inlet`: coolant inlet temperature [K]
- `cp`: specific heat at inlet temperature [J/(kg·K)]

# Returns
Channel power limit for boiling onset `Q` [W].
"""
function q_boiling_onset(mdot, T_sat, T_inlet, cp)
    return abs(mdot) * cp * (T_sat - T_inlet)
end

"""
    q_OFI_whittle_forgan(mdot, T_sat, T_inlet, pipe) -> Q [W]

Channel power at Onset of Flow Instability (OFI) per Whittle-Forgan (1967)
with Fabréga correction.

Formula:
    Q_OFI = |mdot| * ∫cp(T)dT / (1 + 3.15*(Dh/L)*(1.08*G_cgs)^0.29)

where G_cgs = |mdot|/A / 10 (mass flux converted from SI to CGS).
The cp integral ∫cp(T)dT is evaluated from T_inlet to T_sat using `quadgk`.

Source: Python STREAM thresholds.py `Whittle_Forgan_OFI`.

# Arguments
- `mdot`: mass flow rate [kg/s] (sign-insensitive; uses `abs(mdot)`)
- `T_sat`: saturation temperature [K]
- `T_inlet`: coolant inlet temperature [K]
- `pipe`: channel geometry [`PipeGeometry`]

# Returns
OFI limit power `Q_OFI` [W].
"""
function q_OFI_whittle_forgan(mdot, T_sat, T_inlet, pipe)
    G = abs(mdot) / pipe.A
    G_cgs = G / 10  # SI to CGS conversion (G must be in CGS per Whittle-Forgan)
    integral_cp, _ = quadgk(cp_water, T_inlet, T_sat)
    return abs(mdot) * integral_cp / (1.0 + 3.15 * (pipe.Dh / pipe.L) * (1.08 * G_cgs)^0.29)
end

"""
    q_OSV_saha_zuber(T_inlet, mdot, pipe; flux_shape=nothing, dz=nothing, flux_enworse=1.0) -> q_OSV [W/m^2]

Onset of Significant Void (OSV) heat flux using self-consistent Saha-Zuber (1974) formulation.

Uses the computed-bulk variant: the bulk temperature is computed as though the channel
operates exactly at q_OSV, yielding a self-consistent result.

Pe threshold: Pe < 70000 → `X = k/Dh * Nu_c` (Nu_c = 455);
              Pe >= 70000 → `X = St_c * G * cp` (St_c = 0.0065).

Formula: `q_OSV = X * (T_sat - T_inlet) / (1 + X * Hp/(|mdot|*cp) * cumsum(q_shape*dz) / (q_shape*flux_enworse))`

When `flux_shape` is `nothing`, uniform flux is assumed (all flux values equal; shape factor = 1 at each cell).

Source: Python STREAM thresholds.py `Saha_Zuber_OSV_computed_bulk`.

# Arguments
- `T_inlet`: coolant inlet temperature [K]
- `mdot`: mass flow rate [kg/s]
- `pipe`: channel geometry [`PipeGeometry`]
- `flux_shape`: optional axial heat flux distribution vector (freely normalized); default: uniform
- `dz`: optional axial cell lengths [m]; default: `pipe.L / n_cells` per cell
- `flux_enworse`: multiplicative factor for local flux disturbance effects (default 1.0)

# Returns
OSV heat flux `q_OSV` [W/m^2]. Returns the minimum (most conservative) value along the channel.
"""
function q_OSV_saha_zuber(
    T_inlet, mdot, pipe; flux_shape=nothing, dz=nothing, flux_enworse=1.0
)
    # Coolant properties at inlet temperature
    rho = rho_water(T_inlet)
    cp = cp_water(T_inlet)
    k = k_water(T_inlet)
    G = abs(mdot) / pipe.A
    u = G / rho
    # Peclet number
    pe = rho * u * pipe.Dh * cp / k

    # Saha-Zuber coefficient X
    Nu_c = 455.0
    St_c = 0.0065
    if pe <= 7e4
        X = k / pipe.Dh * Nu_c
    else
        X = St_c * G * cp
    end

    T_sat_est = sat_temperature(1e5)  # use 1 atm default for self-consistent bulk

    # Handle uniform vs provided flux shape
    n_cells = flux_shape === nothing ? 10 : length(flux_shape)
    if flux_shape === nothing
        # Uniform flux: cumsum(dz) / (1 * flux_enworse)
        dz_local = fill(pipe.L / n_cells, n_cells)
        shape = ones(n_cells)
    else
        dz_local = dz === nothing ? fill(pipe.L / n_cells, n_cells) : dz
        shape = Float64.(flux_shape)
    end

    dT = T_sat_est - T_inlet
    Hp = pipe.heated_perimeter
    power_factor = Hp / (abs(mdot) * cp)
    cumulative = cumsum(shape .* dz_local)
    shape_factor = cumulative ./ (shape .* flux_enworse)
    denominator = 1.0 .+ X .* power_factor .* shape_factor
    q_osv_cells = X .* dT ./ denominator
    # Return minimum (most conservative cell — first cell where void first onset)
    return minimum(q_osv_cells)
end

"""
    q_CHF_sudo_kaminaga(T_bulk, mdot, pipe, gravity; rho_l=958.4, rho_v=0.598, hfg=2257e3, sigma=0.059, cp_sat=4217.0, T_sat=373.15) -> q_CHF [W/m^2]

Critical Heat Flux (CHF) per Sudo-Kaminaga (1998) correlation for plate-type fuel.

Four sub-correlations (_SKq1..4) with direction-dependent selection:
- G_star >= 0 (downward/horizontal flow): q_star = max(min(q2,q4), q3)
- G_star < 0 (upward flow): q_star = max(max(min(q2,q4), q1), q3)

Final result: `q_CHF = q_star * hfg * sqrt(lamda * drho * rho_v * gravity)`
where `lamda = sqrt(sigma / drho / |gravity|)` (capillary length).

Uses `pipe.width` (NOT `heated_perimeter/2`) for q3 per Mishima's experiments.

Source: Python STREAM thresholds.py `sudo_kaminaga_chf`.

# Arguments
- `T_bulk`: bulk coolant temperature [K] (scalar, at inlet cell)
- `mdot`: mass flow rate [kg/s]
- `pipe`: channel geometry [`PipeGeometry`]
- `gravity`: gravitational acceleration [m/s^2] (sign: positive = upward-to-downward, negative = upward flow)
- `rho_l`: saturated liquid density [kg/m^3] (default: 958.4 at 100°C)
- `rho_v`: saturated vapor density [kg/m^3] (default: 0.598 at 100°C)
- `hfg`: latent heat of vaporization [J/kg] (default: 2257e3)
- `sigma`: surface tension [N/m] (default: 0.059)
- `cp_sat`: specific heat at saturation [J/(kg·K)] (default: 4217.0)
- `T_sat`: saturation temperature [K] (default: 373.15)

# Returns
CHF heat flux `q_CHF` [W/m^2].
"""
function q_CHF_sudo_kaminaga(
    T_bulk,
    mdot,
    pipe,
    gravity;
    rho_l=958.4,
    rho_v=0.598,
    hfg=2257e3,
    sigma=0.059,
    cp_sat=4217.0,
    T_sat=373.15,
)
    g_abs = abs(gravity)
    drho = rho_l - rho_v
    lamda = sqrt(sigma / drho / g_abs)
    Aht = sum(pipe.heated_parts) * pipe.L
    A_ratio = pipe.A / Aht

    G_star = mdot / pipe.A / sqrt(lamda * drho * rho_v * g_abs)

    dT_inlet = (cp_sat / hfg) * (T_sat - T_bulk)
    # Use T_sat as conservative outlet temperature (maximum subcooling consumed)
    dT_outlet = (cp_sat / hfg) * (T_sat - T_sat)  # 0.0 at saturated outlet

    q1 = _SKq1(G_star)
    q2 = _SKq2(A_ratio, G_star, dT_inlet)
    q3 = _SKq3(A_ratio, pipe.width, lamda, dT_inlet, rho_v, rho_l)
    q4 = _SKq4(G_star, dT_outlet)

    # Direction-dependent selection
    if G_star >= 0
        # Downward or horizontal flow
        q_star = max(min(q2, q4), q3)
    else
        # Upward flow
        q_star = max(max(min(q2, q4), q1), q3)
    end

    return q_star * hfg * sqrt(lamda * drho * rho_v * g_abs)
end

"""
    q_CHF_mirshak(T_bulk, T_sat, pressure, v) -> q_CHF [W/m^2]

Critical Heat Flux (CHF) per Mirshak et al. (1959) correlation.
Valid for rapid flows (v > 1.5 m/s).

Formula: `q_CHF = 1.51e6 * (1 + 0.1198*v) * (1 + 0.00914*(T_sat - T_bulk)) * (1 + 1.9e-6*pressure)`

Source: Python STREAM thresholds.py `mirshak_chf`.

# Arguments
- `T_bulk`: bulk coolant temperature [K]
- `T_sat`: saturation temperature [K]
- `pressure`: system pressure [Pa]
- `v`: coolant flow velocity [m/s]

# Returns
CHF heat flux `q_CHF` [W/m^2].
"""
function q_CHF_mirshak(T_bulk, T_sat, pressure, v)
    return 1.51e6 *
           (1 + 0.1198 * v) *
           (1 + 0.00914 * (T_sat - T_bulk)) *
           (1 + 1.9e-6 * pressure)
end

"""
    q_CHF_fabrega(T_inlet, T_sat, pipe) -> q_CHF [W/m^2]

Critical Heat Flux (CHF) per Fabréga (1971) correlation.
Valid for slow flows (v < 0.5 m/s).

Formula: `q_CHF = 1e7 * Dh * (0.023*(T_sat - T_inlet) + 4.56)`

Source: Python STREAM thresholds.py `fabrega_chf`.

# Arguments
- `T_inlet`: coolant bulk temperature at inlet [K]
- `T_sat`: saturation temperature [K]
- `pipe`: channel geometry [`PipeGeometry`] (uses `pipe.Dh`)

# Returns
CHF heat flux `q_CHF` [W/m^2].
"""
function q_CHF_fabrega(T_inlet, T_sat, pipe)
    return 1e7 * pipe.Dh * (0.023 * (T_sat - T_inlet) + 4.56)
end

"""
    twall_limit(T_wall, inhomogeneity_factor=1.0) -> T_limit [K]

Effective wall temperature limit accounting for spatial inhomogeneity.

Formula: `T_limit = T_wall * inhomogeneity_factor`

Used to adjust the nominal wall temperature by a multiplier that accounts
for hot-spot factors, burnup inhomogeneities, or manufacturing tolerances.

# Arguments
- `T_wall`: nominal wall temperature [K]
- `inhomogeneity_factor`: dimensionless multiplier (default: 1.0, no correction)

# Returns
Effective wall temperature limit `T_limit` [K].
"""
function twall_limit(T_wall, inhomogeneity_factor=1.0)
    return T_wall * inhomogeneity_factor
end
