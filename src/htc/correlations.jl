@doc raw"""
    dittus_boelter(Re, Pr, args...) -> Nu

Dittus-Boelter turbulent forced convection, in its heating form [DittusBoelter1930](@cite):

```math
Nu = 0.023 \, Re^{0.8} Pr^{0.4}
```

Valid for `Re > 10⁴`, `0.6 ≤ Pr ≤ 160` and `L/D > 10`. Trailing arguments are ignored, so
the correlation fits the `(Re, Pr, T_wall, T_bulk)` signature of the others.

# Arguments
- `Re`, `Pr`: Reynolds and Prandtl numbers

# Returns
Nusselt number (dimensionless).

# Examples
```jldoctest
julia> HTC.dittus_boelter(1.0e4, 32.0)
145.8101737064225
```
"""
dittus_boelter(Re, Pr, args...) = 0.023 * Re^0.8 * Pr^0.4

"""
    constant_Nusselt(; Nu=8.235) -> (Re, Pr, args...) -> Nu

A fixed Nusselt number. The default is the fully developed laminar value for parallel
plates under uniform heat flux [ShahLondon1978](@cite).

Wrap it in [`ConstantNusselt`](@ref) to hand it to a channel.

# Arguments
- `Nu`: the Nusselt number to return

# Returns
A function `(Re, Pr, args...) -> Nu` that ignores its arguments.

# Examples
```jldoctest
julia> HTC.constant_Nusselt()(300.0, 7.0)
8.235
```
"""
constant_Nusselt(; Nu=8.235) = _ConstantNu(Nu)

# A struct rather than a closure, so the value can be printed.
struct _ConstantNu{T}
    Nu::T
end
(c::_ConstantNu)(Re, Pr, args...) = c.Nu
Base.show(io::IO, c::_ConstantNu) = print(io, "constant Nu = ", c.Nu)

@doc raw"""
    elenbaas_nusselt(Ra, b, L) -> Nu

Natural convection between parallel vertical plates [Elenbaas1942](@cite):

```math
Nu = (1/24) \, |Ra| \, (b/L) \, (1 - e^{-35 L / (|Ra| \, b)})^{0.75}
```

A wall colder than the coolant drives the same convection, downward, hence `|Ra|`.

# Arguments
- `Ra`: Rayleigh number, based on the gap `b`
- `b`: gap between the plates [m], the channel depth
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless), zero only at `Ra = 0`.

# Examples
```jldoctest
julia> round(HTC.elenbaas_nusselt(12375.512696, 0.00254, 0.6); digits=10)
1.2731625848
```
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
at very small dimensionless length `x`, eq. 316 of [ShahLondon1978](@cite). Their table 34
was computed from it below `x = 1e-4`.
"""
function _leveque_nusselt(x)
    xt = x^(1 / 3)
    return 1 / (0.670960978 * xt + 0.159064137 * xt^2 + 0.12012 * x + 0.12495 * xt^4 +
                0.15602 * xt^5 + 0.22176 * x^2 + 0.34932 * xt^7 - 4 * x)
end

"""
    _nusselt_coefficient_developing(x) -> Nu

Local Nusselt number for thermally developing, hydrodynamically developed laminar flow
between parallel plates at the dimensionless length `x = L / (D_h Re Pr)`. It interpolates
linearly in table 34 of [ShahLondon1978](@cite) over `1e-6 ≤ x ≤ 0.2`, with
[`_leveque_nusselt`](@ref) below that range and the fully developed 8.2353 above it.

`@register_symbolic`, so a channel equation carries the lookup as one opaque node.
"""
function _nusselt_coefficient_developing(x::Real)
    # A solver iterate can make x NaN. It fails both range checks, and searchsortedlast puts
    # it past the table's end, so it is passed on for the solver to reject the step.
    isnan(x) && return x
    x < first(_XSTAR_TABLE34) && return _leveque_nusselt(x)
    x >= last(_XSTAR_TABLE34) && return last(_NU_TABLE34)
    k = searchsortedlast(_XSTAR_TABLE34, x)
    x1, x2 = _XSTAR_TABLE34[k], _XSTAR_TABLE34[k + 1]
    return _NU_TABLE34[k] + (_NU_TABLE34[k + 1] - _NU_TABLE34[k]) * (x - x1) / (x2 - x1)
end

@register_symbolic _nusselt_coefficient_developing(x::Real)

@doc raw"""
    fully_developed_laminar_nusselt(geom::PipeGeometry) -> (Re, Pr, T_bulk, T_wall) -> Nu

Fully developed laminar Nusselt number in a rectangular duct heated on its two long sides,
a fifth-order polynomial in the aspect ratio `α = depth / width` [ShahLondon1978](@cite):

```math
Nu = 8.235 \, (1 - 1.4122 α + 2.3473 α^2 - 2.8983 α^3 + 2.0629 α^4 - 0.6077 α^5)
```

# Arguments
- `geom`: the duct; only `depth / width` is used

# Returns
A function `(Re, Pr, T_bulk, T_wall) -> Nu`, constant in its arguments.
"""
function fully_developed_laminar_nusselt(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    nu = _two_sided_heating_nusselt(aspect_ratio)
    return (Re, Pr, args...) -> nu
end

@doc raw"""
    developing_laminar_nusselt(geom::PipeGeometry; develop_length) -> (Re, Pr, T_bulk, T_wall) -> Nu

Laminar Nusselt number in a rectangular duct heated on its two long sides, while the
temperature profile is still developing. It is the parallel-plate developing value at the
dimensionless distance

```math
x^* = x / (D_h \, Re \, Pr \, c), \qquad c = 6 - 5 e^{-0.75 α / 0.3257}
```

scaled to the aspect ratio `α` as in [`fully_developed_laminar_nusselt`](@ref)
[ShahLondon1978](@cite). Far enough downstream it falls to the fully developed value.

# Arguments
- `geom`: the duct
- `develop_length`: distance from the heated entrance [m]. Required, since the result depends
  on where along the channel it is evaluated.

# Returns
A function `(Re, Pr, T_bulk, T_wall) -> Nu`.
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

@doc raw"""
    marco_han_nusselt(aspect_ratio) -> Nu

Marco and Han's fit for the fully developed laminar Nusselt number in a rectangular duct
heated on all four sides [ShahLondon1978](@cite):

```math
Nu = 8.235 \, (1 - 2.0421 α + 3.853 α^2 - 2.4765 α^3 + 1.0578 α^4 - 0.1861 α^5)
```

# Arguments
- `aspect_ratio`: `α`, depth over width, in [0, 1]

# Returns
Nusselt number (dimensionless).

# Examples
```jldoctest
julia> HTC.marco_han_nusselt(0.2)
5.991134842079999
```
"""
function marco_han_nusselt(aspect_ratio)
    return 8.235 * (
        1.0 - 2.0421 * aspect_ratio + 3.853 * aspect_ratio^2 - 2.4765 * aspect_ratio^3 +
        1.0578 * aspect_ratio^4 - 0.1861 * aspect_ratio^5
    )
end
