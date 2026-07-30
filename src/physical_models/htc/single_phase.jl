# single_phase.jl -- turning a Nusselt correlation into a single-phase HTC.
#
# A correlation gives Nu; the coolant properties that close `h = Nu·κ/Dh` are evaluated at
# the film temperature, (T_wall + T_bulk)/2, which is the convention Python STREAM uses and
# what the parity references were generated against.

# Nusselt at a given film temperature. `nusselt` is called as `(Re, Pr)`.
function _nu_film(T_film::Real, ṁ::Real, Dh::Real, A::Real, nusselt::Function, liquid)
    return nusselt(Re(liquid, T_film, ṁ, A, Dh), Pr(liquid, T_film))
end

# Nusselt for a wall/bulk pair. The film temperature sets the properties, but the wall and
# bulk temperatures are still handed to the correlation, so the strict four-argument ones
# (`regime_dependent` with natural-convection switching, `elenbaas_htc`) can use them.
# Correlations written as `(Re, Pr, args...)` absorb the extra arguments unchanged.
function _nu_film(T_wall::Real, T_bulk::Real, ṁ::Real, Dh::Real, A::Real,
                  nusselt::Function, liquid)
    T_film = (T_wall + T_bulk) / 2
    with_temps(Re_val, Pr_val) = nusselt(Re_val, Pr_val, T_wall, T_bulk)
    return _nu_film(T_film, ṁ, Dh, A, with_temps, liquid)
end

"""
    h_single_phase(T_wall, T_bulk, ṁ, Dh, A, nusselt, liquid) -> W/(m^2·K)

Single-phase convective heat transfer coefficient, `Nu·κ/Dh`, with the Nusselt number from
`nusselt` and the properties taken at the film temperature `(T_wall + T_bulk)/2`.

# Arguments
- `T_wall`, `T_bulk`: wall and bulk coolant temperature [°C]
- `ṁ`: mass flow rate [kg/s]
- `Dh`: hydraulic diameter [m]
- `A`: flow area [m^2]
- `nusselt`: correlation `(Re, Pr, T_bulk, T_wall) -> Nu`; the plain `(Re, Pr) -> Nu` form
  works too
- `liquid`: coolant (`AbstractLiquid`)

# Returns
Heat transfer coefficient [W/(m^2·K)].
"""
function h_single_phase(T_wall::Real, T_bulk::Real, ṁ::Real, Dh::Real, A::Real,
                        nusselt::Function, liquid)
    T_film = (T_wall + T_bulk) / 2
    return _nu_film(T_wall, T_bulk, ṁ, Dh, A, nusselt, liquid) * κ(liquid, T_film) / Dh
end
