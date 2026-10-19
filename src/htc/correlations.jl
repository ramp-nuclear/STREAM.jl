@doc raw"""
    dittus_boelter(Re, Pr, args...) -> Nu

Dittus-Boelter turbulent forced convection, in its heating form [DittusBoelter1930](@cite):

```math
Nu = 0.023 \, Re^{0.8} Pr^{0.4}
```

Valid for `Re > 10⁴`, `0.6 ≤ Pr ≤ 160` and `L/D > 10`. Trailing arguments are ignored, so
the correlation fits the `(Re, Pr, T_wall, T_bulk, duct)` call [`FromNusselt`](@ref) makes.

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
Nu = (1/24) \, Ra \, (b/L) \, (1 - e^{-35 L / (Ra \, b)})^{0.75}
```

With no buoyancy to drive it (`Ra ≤ 0`, a wall no hotter than the coolant) `Nu` is 0.

# Arguments
- `Ra`: Rayleigh number, based on the gap `b`
- `b`: gap between the plates [m], the channel depth
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless).

# Examples
```jldoctest
julia> round(HTC.elenbaas_nusselt(12375.512696, 0.00254, 0.6); digits=10)
1.2731625848
```
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

@doc raw"""
    fully_developed_laminar_nusselt(aspect_ratio) -> Nu
    fully_developed_laminar_nusselt(Re, Pr, T_wall, T_bulk, duct::Duct{<:Rectangular}) -> Nu

Fully developed laminar Nusselt number in a rectangular duct heated on its two long sides,
a fifth-order polynomial in the aspect ratio `α = depth / width` [ShahLondon1978](@cite):

```math
Nu = 8.235 \, (1 - 1.4122 α + 2.3473 α^2 - 2.8983 α^3 + 2.0629 α^4 - 0.6077 α^5)
```

The second form is the one [`FromNusselt`](@ref) calls, and reads `α` off the duct.

# Arguments
- `aspect_ratio`: `α`, in [0, 1]

# Returns
Nusselt number (dimensionless).

# Examples
```jldoctest
julia> HTC.fully_developed_laminar_nusselt(0.0)
8.235
```
"""
fully_developed_laminar_nusselt(aspect_ratio) = _two_sided_heating_nusselt(aspect_ratio)

function fully_developed_laminar_nusselt(Re, Pr, T_wall, T_bulk, duct::Duct{<:Rectangular})
    return fully_developed_laminar_nusselt(aspect_ratio(duct))
end

@doc raw"""
    developing_laminar_nusselt(Re, Pr, aspect_ratio, x_over_Dh) -> Nu

Laminar Nusselt number in a rectangular duct heated on its two long sides, while the
temperature profile is still developing. It is the parallel-plate developing value at the
dimensionless distance

```math
x^* = (x / D_h) / (Re \, Pr \, c), \qquad c = 6 - 5 e^{-0.75 α / 0.3257}
```

scaled to the aspect ratio `α` as in [`fully_developed_laminar_nusselt`](@ref)
[ShahLondon1978](@cite). Far enough downstream it falls to the fully developed value.
[`DevelopingLaminar`](@ref) is the model built on it.

# Arguments
- `Re`, `Pr`: Reynolds and Prandtl numbers
- `aspect_ratio`: `α`, depth over width, in [0, 1]
- `x_over_Dh`: distance from the heated entrance, in hydraulic diameters

# Returns
Nusselt number (dimensionless).

# Examples
```jldoctest
julia> round(HTC.developing_laminar_nusselt(500.0, 4.0, 0.02, 10.0); sigdigits=6)
10.1318
```
"""
function developing_laminar_nusselt(Re, Pr, aspect_ratio, x_over_Dh)
    correction = 6 - 5 * exp(-0.75 * aspect_ratio / 0.3257)
    x_star = x_over_Dh / Re / Pr / correction
    return _two_sided_heating_nusselt(aspect_ratio, _nusselt_coefficient_developing(x_star))
end

"""
    _DevelopingNu(x)

[`developing_laminar_nusselt`](@ref) at `x` metres from the heated entrance, called as
`(Re, Pr, T_wall, T_bulk, duct) -> Nu`. A struct rather than a closure, so it prints.
"""
struct _DevelopingNu{T}
    x::T
end

function (c::_DevelopingNu)(Re, Pr, T_wall, T_bulk, duct::Duct{<:Rectangular})
    return developing_laminar_nusselt(Re, Pr, aspect_ratio(duct), c.x / hydraulic_diameter(duct))
end

Base.show(io::IO, c::_DevelopingNu) = print(io, "developing laminar, ", c.x, " m from the entrance")

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
