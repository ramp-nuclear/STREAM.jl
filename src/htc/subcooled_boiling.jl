"""
    _bergles_rohsenow_dT_ONB(P_Pa, q_spl) -> ΔT [K]

Bergles-Rohsenow wall superheat at the onset of nucleate boiling, `T_ONB - T_sat`, for a
single-phase wall heat flux `q_spl` [W/m^2] at pressure `P_Pa` [Pa].

Sets where boiling starts. Private to `HTC`; `Thresholds` and `Components` both import it by
name.
"""
function _bergles_rohsenow_dT_ONB(P_Pa, q_spl)
    p = P_Pa / 1e5
    return 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
end

@doc raw"""
    mcadams_scb_heat_flux(T_sat, T_wall) -> q [W/m^2]

McAdams' subcooled boiling heat flux for water [McAdams1949](@cite), in the SI form given in
[IAEA1980](@cite):

```math
q = 2.26 \, (T_{wall} - T_{sat})^{3.86}
```

with the superheat in K and `q` in W/m². Zero at or below saturation.

# Arguments
- `T_sat`: saturation temperature [°C]
- `T_wall`: wall temperature [°C]

# Returns
Subcooled boiling heat flux `q` [W/m²].

# Examples
```jldoctest
julia> HTC.mcadams_scb_heat_flux(100.0, 120.0)
237730.12702161702

julia> HTC.mcadams_scb_heat_flux(100.0, 90.0)
0.0
```
"""
mcadams_scb_heat_flux(T_sat, T_wall) = 2.26 * max(T_wall - T_sat, 0.0)^3.86

@doc raw"""
    rohsenow_scb_heat_flux(T_wall, sat; n=1.26, csf=0.011, g=G_EARTH) -> q [W/m^2]

Rohsenow's nucleate boiling heat flux [Rohsenow1952](@cite), used for subcooled boiling in
laminar flow:

```math
q = μ \, h_{fg} \sqrt{g (ρ - ρ_v) / σ} \; [c_p (T_{wall} - T_{sat}) / (C_{sf} h_{fg} Pr^n)]^{1/0.33}
```

Every property is read from `sat`, the coolant at saturation. Zero at or below saturation,
where the superheat is clamped at zero so the fractional power never sees a negative base.

# Arguments
- `T_wall`: wall temperature [°C]
- `sat`: the coolant's [`Liquid`](@ref) snapshot at saturation, `liquid(Tsat(liquid, P), P)`
- `n`: exponent on the Prandtl number
- `csf`: the surface-fluid constant `C_sf`
- `g`: gravitational acceleration [m/s²]

# Returns
Subcooled boiling heat flux `q` [W/m²].

# Examples
```jldoctest
julia> sat = H2O(Tsat(H2O, 1.7e5), 1.7e5);  # water at saturation at 1.7 bar

julia> round(HTC.rohsenow_scb_heat_flux(125.0, sat); sigdigits=8)
229086.82
```
"""
function rohsenow_scb_heat_flux(T_wall, sat::Liquid; n=1.26, csf=0.011, g=G_EARTH)
    superheat = max(T_wall - sat.Tsat, 0.0)
    Pr_sat = sat.cₚ * sat.μ / sat.κ
    x = sat.cₚ * superheat / (sat.hfg * csf * Pr_sat^n)
    return sat.μ * sat.hfg * sqrt(g * (sat.ρ - sat.ρᵥ) / sat.σ) * x^(1 / 0.33)
end

@doc raw"""
    partial_SCB_correction(q_spl, q_scb, q_scb_inc) -> factor

The partial boiling factor of Bergles and Rohsenow [BerglesRohsenow1964](@cite), which scales the single-phase
coefficient between the onset of nucleate boiling and fully developed boiling:

```math
\mathrm{factor} = \sqrt{1 + ((q_{scb} - q_{scb,inc}) / q_{spl})^2}
```

It is 1 at the onset, where `q_scb = q_scb_inc`, and grows with the wall superheat. Below
the onset, and when `q_spl` is not positive, it is 1.

# Arguments
- `q_spl`: single-phase convective heat flux [W/m²]
- `q_scb`: subcooled boiling heat flux at the wall temperature [W/m²]
- `q_scb_inc`: subcooled boiling heat flux at the onset temperature [W/m²]

# Returns
The dimensionless factor, at least 1.
"""
function partial_SCB_correction(q_spl, q_scb, q_scb_inc)
    # ifelse keeps the choice symbolic inside a compiled channel, but evaluates both sides,
    # so the division is floored to stay finite where q_spl is zero.
    ratio = (q_scb - q_scb_inc) / max(q_spl, 1e-20)
    return ifelse(q_spl > 0, ifelse(ratio > 0, sqrt(1 + ratio^2), 1.0), 1.0)
end

"""
    regime_dependent_q_scb(; re_bounds=(2000.0, 5000.0)) -> (T_wall, sat, Re) -> q [W/m^2]

A subcooled boiling heat flux closure that switches on the bulk Reynolds number.

It is [`rohsenow_scb_heat_flux`](@ref) in laminar flow, [`mcadams_scb_heat_flux`](@ref) in
turbulent flow, and a linear blend across `re_bounds` via [`flow_regime_blend`](@ref).

Hand the closure to [`SubcooledBoiling`](@ref), which calls it with `sat`, the coolant's
[`Liquid`](@ref) snapshot at saturation at each cell's pressure.

# Arguments
- `re_bounds`: `(re_lo, re_hi)` transition band on the Reynolds number

# Returns
Closure `(T_wall, sat, Re) -> q_scb [W/m²]`.

# Examples
At a 125 °C wall in water at 1.7 bar, laminar, mid-band and turbulent:
```jldoctest
julia> q = HTC.regime_dependent_q_scb(); sat = H2O(Tsat(H2O, 1.7e5), 1.7e5);

julia> round.([q(125.0, sat, Re) for Re in (1000.0, 3500.0, 8000.0)]; sigdigits=8)
3-element Vector{Float64}:
 229086.82
 122057.77
  15028.724
```
"""
function regime_dependent_q_scb(; re_bounds=(2000.0, 5000.0))
    bounds = (Float64(re_bounds[1]), Float64(re_bounds[2]))
    return (T_wall, sat, Re) -> flow_regime_blend(
        Re, bounds,
        rohsenow_scb_heat_flux(T_wall, sat),
        mcadams_scb_heat_flux(sat.Tsat, T_wall),
    )
end

"""
    _scb_corrected(h_spl, q_scb, T_wall, T_bulk, ṁ, Dh, A, liquid, P) -> h

The Bergles-Rohsenow partial boiling blend, applied to a single-phase `h` that some
[`AbstractHTC`](@ref) has already produced.

Below the onset of nucleate boiling nothing changes. At or above it the single-phase value is
scaled by the partial boiling factor, switched with `ifelse`. The flux closure `q_scb` gets the
coolant at saturation at the local pressure `P`, and the bulk Reynolds number.
"""
function _scb_corrected(h_spl, q_scb, T_wall, T_bulk, ṁ, Dh, A, liquid, P)
    q_spl = max(h_spl * (T_wall - T_bulk), 0.0)
    T_sat = Tsat(liquid, P)
    sat = liquid(T_sat, P)
    Re_bulk = Re(liquid, T_bulk, ṁ, A, Dh)
    T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)
    factor = partial_SCB_correction(
        q_spl, q_scb(T_wall, sat, Re_bulk), q_scb(T_ONB, sat, Re_bulk)
    )
    return ifelse(T_wall >= T_ONB, h_spl * factor, h_spl)
end
