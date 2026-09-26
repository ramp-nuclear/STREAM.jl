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

The correlation takes `|Ra|`: a wall colder than the bulk drives natural convection just as a
hotter one does, only downward. At `Ra = 0` there is no buoyancy and `Nu` is zero.

Source: Elenbaas (1942), as implemented in Python STREAM `_Elenbaas`.

# Arguments
- `Ra`: Rayleigh number (based on gap width b)
- `b`: gap between plates [m] (channel depth)
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless), zero only at `Ra = 0`.
"""
function elenbaas_nusselt(Ra, b, L)
    # The 1e-30 keeps the exponent finite at Ra = 0, where exp(-Inf) = 0 would still work but
    # its derivative would not. It is Python's floor, far below any Ra that means anything.
    Ra_abs = abs(Ra) + 1e-30
    shape = (1 - exp(-35 * L / (Ra_abs * b)))^0.75
    return (1 / 24) * Ra_abs * (b / L) * shape
end


function _two_sided_heating_nusselt(aspect_ratio, nu0=8.235)
    return nu0 * (
        1.0 - 1.4122 * aspect_ratio + 2.3473 * aspect_ratio^2 - 2.8983 * aspect_ratio^3 +
        2.0629 * aspect_ratio^4 - 0.6077 * aspect_ratio^5
    )
end

const _XSTAR_TABLE34 = vcat(
    [j * 10.0^(-i) for i in 6:-1:2 for j in (1, 1.5, 2, 3, 4, 5, 6, 7, 8, 9)],
    [0.1, 0.15, 0.2],
)
const _NU_TABLE34 = vcat(
    [148.773, 129.944, 118.049, 103.110, 93.673, 86.954, 81.824, 77.724, 74.339, 71.477,
     69.011, 60.292, 54.787, 47.880, 43.521, 40.419, 38.054, 36.165, 34.607, 33.290,
     32.153, 28.154, 25.636, 22.488, 20.512, 19.133, 18.050, 17.205, 16.511, 15.928,
     15.427, 13.681, 12.604, 11.299, 10.516, 9.9878, 9.6085, 9.3249, 9.1073, 8.9374,
     8.8031, 8.4393, 8.3107, 8.2458, 8.2368, 8.2355],
    fill(8.2353, 7),
)

"""
    _leveque_nusselt(x) -> Nu

Worsøe-Schmidt's Lévêque-type solution for the local Nusselt number between parallel plates
at very small dimensionless length `x`, Shah and London (1978) eq. 316. It is what their
table 34 was computed from below `x = 1e-4`.
"""
function _leveque_nusselt(x)
    xt = x^(1 / 3)
    return 1 / (0.670960978 * xt + 0.159064137 * xt^2 + 0.12012 * x + 0.12495 * xt^4 +
                0.15602 * xt^5 + 0.22176 * x^2 + 0.34932 * xt^7 - 4 * x)
end

"""
    _nusselt_coefficient_developing(x) -> Nu

Local Nusselt number for thermally developing, hydrodynamically developed laminar flow
between parallel plates at dimensionless length `x = L/(Dh·Re·Pr)`. Interpolated linearly in
Shah and London (1978) table 34 over `1e-6 <= x <= 0.2`, with [`_leveque_nusselt`](@ref)
below it and the fully developed 8.2353 above it. Continuous in `x`, unlike the three-piece
fit from the same book, which jumps at `x = 2e-4` and `1e-3`.

`@register_symbolic`, so a channel equation carries the lookup as one opaque node.
"""
function _nusselt_coefficient_developing(x::Real)
    x < first(_XSTAR_TABLE34) && return _leveque_nusselt(x)
    x >= last(_XSTAR_TABLE34) && return last(_NU_TABLE34)
    k = searchsortedlast(_XSTAR_TABLE34, x)
    x1, x2 = _XSTAR_TABLE34[k], _XSTAR_TABLE34[k + 1]
    return _NU_TABLE34[k] + (_NU_TABLE34[k + 1] - _NU_TABLE34[k]) * (x - x1) / (x2 - x1)
end

@register_symbolic _nusselt_coefficient_developing(x::Real)

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
