# htc/correlations.jl -- Nusselt number correlations.
#
# Everything here is dimensionless: a correlation takes `(Re, Pr, T_wall, T_bulk)` and
# returns Nu. Closing one into a heat transfer coefficient, which is where the choice of
# film or bulk properties lives, is [`FromNusselt`](@ref)'s job in htc.jl.
#
# Geometry-dependent factories take `geom::PipeGeometry` first and capture the scalars they
# need (`geom.depth`, `geom.width`, `geom.L`, `geom.Dh`) at construction, so the returned
# closure sees only symbolic Re and Pr.
#
# Nothing here is @register_symbolic: it is all plain arithmetic that MTK traces through.

"""
    dittus_boelter(Re, Pr, args...) -> Nu

Dittus-Boelter turbulent forced convection, `Nu = 0.023·Re^0.8·Pr^0.4`. Trailing arguments
are accepted and ignored so the correlation fits the `(Re, Pr, T_wall, T_bulk)` signature.

Valid for Re > 10,000, 0.6 <= Pr <= 160, L/D > 10.
"""
dittus_boelter(Re, Pr, args...) = 0.023 * Re^0.8 * Pr^0.4

"""
    constant_Nusselt(; Nu=8.235) -> (Re, Pr, args...) -> Nu

A fixed Nusselt number. The default is the Shah and London fully-developed value for
parallel plates under uniform heat flux.

Wrap it in [`ConstantNusselt`](@ref) to hand it to a channel.
"""
function constant_Nusselt(; Nu=8.235)
    return (Re, Pr, args...) -> Nu
end

"""
    elenbaas_nusselt(Ra, b, L) -> Nu

Elenbaas natural convection correlation for parallel vertical plates.
Formula: Nu = (1/24) * Ra * (b/L) * (1 - exp(-35 * L / (Ra * b)))^0.75

Natural convection has no driving force for non-positive Rayleigh (wall not
hotter than bulk), so Nu = 0 for Ra <= 0. The shape term's base is clamped so
the fractional power never sees a negative argument, even when the expression is
eagerly constant-folded.

Source: Elenbaas (1942), as implemented in Python STREAM `_Elenbaas`.

# Arguments
- `Ra`: Rayleigh number (based on gap width b)
- `b`: gap between plates [m] (channel depth)
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless). Zero for Ra <= 0.
"""
function elenbaas_nusselt(Ra, b, L)
    # The return below already zeroes Nu for Ra <= 0, so this clamp only has to keep the shape
    # term finite while that not-taken branch is traced. A symbolic Num cannot take an early
    # `return`, hence the ifelse rather than a guard clause. The clamp value is arbitrary as long
    # as it is finite and positive; one(Ra) is the simplest. An epsilon would be worse, it blows
    # the 35*L/(Ra*b) exponent up toward Inf.
    Ra_pos = ifelse(Ra > 0, Ra, one(Ra))
    shape = (1 - exp(-35 * L / (Ra_pos * b)))^0.75
    return ifelse(Ra > 0, (1 / 24) * Ra * (b / L) * shape, zero(Ra))
end


function _two_sided_heating_nusselt(aspect_ratio, nu0=8.235)
    return nu0 * (
        1.0 - 1.4122 * aspect_ratio + 2.3473 * aspect_ratio^2 - 2.8983 * aspect_ratio^3 +
        2.0629 * aspect_ratio^4 - 0.6077 * aspect_ratio^5
    )
end

function _nusselt_coefficient_developing(x)
    nu_low = 1.49 * x^(-1 / 3)
    nu_mid = 1.49 * x^(-1 / 3) - 0.4
    nu_high = 8.235 + 8.68 * exp(-164 * x) * (1e3 * x)^(-0.506)
    return ifelse(x <= 2e-4, nu_low, ifelse(x <= 1e-3, nu_mid, nu_high))
end

"""
    fully_developed_laminar_nusselt(geom::PipeGeometry) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for fully-developed laminar flow in a
rectangular duct with 2-sided heating.

# Arguments
- `geom`: `PipeGeometry`; the factory reads `geom.depth` and `geom.width` to
  derive `aspect_ratio = depth / width`. `geom.Dh` is not used by the Nu calculation.

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function fully_developed_laminar_nusselt(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    nu = _two_sided_heating_nusselt(aspect_ratio)
    return (Re, Pr, args...) -> nu
end

"""
    developing_laminar_nusselt(geom::PipeGeometry; develop_length) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for thermally developing laminar flow in a
rectangular duct with 2-sided heating.

`develop_length` is a **mandatory** kwarg with no default. The caller must explicitly
choose the evaluation point along the channel; there is no silent substitution with
`geom.L`.

# Arguments
- `geom`: `PipeGeometry`; the factory reads `geom.Dh`, `geom.depth`, and `geom.width`,
  deriving `aspect_ratio = depth / width`.
- `develop_length`: distance from channel entrance [m] (mandatory, no default).

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function developing_laminar_nusselt(geom::PipeGeometry; develop_length)
    aspect_ratio = geom.depth / geom.width
    Dh_v = geom.Dh
    correction = 6 - 5 * exp(-0.75 * aspect_ratio / 0.3257)
    return (Re, Pr, args...) -> begin
        x_star = develop_length / Dh_v / Re / Pr / correction
        nudev = _nusselt_coefficient_developing(x_star)
        _two_sided_heating_nusselt(aspect_ratio, nudev)
    end
end

"""
    marco_han_nusselt(aspect_ratio) -> Nu

Marco and Han approximation for Nusselt number in fully-developed laminar flow
through rectangular ducts with uniform wall temperature (4-sided heating).

# Arguments
- `aspect_ratio`: channel depth / channel width (0 to 1)

# Returns
Nusselt number (dimensionless).
"""
function marco_han_nusselt(aspect_ratio)
    return 8.235 * (
        1.0 - 2.0421 * aspect_ratio + 3.853 * aspect_ratio^2 - 2.4765 * aspect_ratio^3 +
        1.0578 * aspect_ratio^4 - 0.1861 * aspect_ratio^5
    )
end
