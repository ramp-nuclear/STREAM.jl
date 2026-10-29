"""
    AbstractLiquid

Supertype for coolants. A concrete liquid implements the nine three-argument methods
listed in `LIQUID_PROPERTIES`, each taking `(liquid, T, p)` with `T` in Celsius
and `p` in Pa.

The correlations are plain arithmetic, so MTK traces straight through them and a component
ends up with the property expression written out in its equations. Nothing is
`@register_symbolic`: dispatch on the liquid happens once while the equations are being
built, which is what keeps the coolant swappable without the solver ever seeing a type.

`LightWater` (aliased [`H2O`](@ref)) and `HeavyWater` (aliased [`D2O`](@ref)) ship with
the package. [`Liquid`](@ref) holds a fixed set of property values and is itself an
`AbstractLiquid`, so a frozen snapshot can stand in wherever a coolant is expected.
"""
abstract type AbstractLiquid end

"""
    LIQUID_PROPERTIES

Names of the nine property functions a liquid implements. The two-argument convenience
forms are generated from this tuple.
"""
const LIQUID_PROPERTIES = (
    :density,
    :vapor_density,
    :specific_heat,
    :viscosity,
    :conductivity,
    :surface_tension,
    :latent_heat,
    :thermal_expansion,
    :sat_temperature,
)

for f in LIQUID_PROPERTIES
    @eval function $f end
end

"""
    density(liquid, T, p)           # ρ  [kg/m^3]
    vapor_density(liquid, T, p)     # ρᵥ [kg/m^3]
    specific_heat(liquid, T, p)     # cₚ [J/(kg·K)]
    viscosity(liquid, T, p)         # μ  [Pa·s]
    conductivity(liquid, T, p)      # k  [W/(m·K)]
    surface_tension(liquid, T, p)   # σ  [N/m]
    latent_heat(liquid, T, p)       # hfg [J/kg]
    thermal_expansion(liquid, T, p) # β  [1/K]
    sat_temperature(liquid, T, p)   # Tsat [°C]

Saturated-liquid properties of `liquid` at temperature `T` [°C] and pressure `p` [Pa].

Each has a two-argument form. For the eight temperature-driven properties it reads
`density(liquid, T)` and fills the pressure with [`ATM`](@ref); for `sat_temperature`
the single argument is the pressure, `sat_temperature(liquid, p)`, since that is the
variable it actually depends on.

Components call the two-argument form. Passing a local pressure instead would make every
property expression depend on that pressure symbol, coupling the Jacobian for correlations
that ignore pressure anyway. A coolant with genuinely pressure-dependent properties wants
the three-argument form at the call site.

The two-argument forms are generated over `LIQUID_PROPERTIES` with the signature
`(liquid::AbstractLiquid, T)`. A coolant wanting a different default pressure defines its own,
more specific method, which dispatch prefers:

```julia
struct MoltenSalt <: AbstractLiquid end
density(l::MoltenSalt, T) = density(l, T, 2.0e5)   # this pressure, not ATM
```

Only the properties you override change; the rest keep falling back to the generated method.

Each alias below names the same function, so `ρ === density` and either spelling
dispatches identically.

| alias | function            | alias  | function          |
|:------|:--------------------|:-------|:------------------|
| `ρ`   | `density`           | `σ`    | `surface_tension` |
| `ρᵥ`  | `vapor_density`     | `hfg`  | `latent_heat`     |
| `cₚ`  | `specific_heat`     | `β`    | `thermal_expansion` |
| `μ`   | `viscosity`         | `Tsat` | `sat_temperature` |
| `κ`   | `conductivity`      | `hₗ`   | `enthalpy`        |
|       |                     | `hᵥ`   | `vapor_enthalpy`  |

Three more come from these nine and need no method of their own: [`enthalpy`](@ref) integrates
the specific heat, [`temperature`](@ref) inverts it, and [`vapor_enthalpy`](@ref) adds the
latent heat at saturation.
"""
density, vapor_density, specific_heat, viscosity, conductivity,
surface_tension, latent_heat, thermal_expansion, sat_temperature

const ρ = density
const ρᵥ = vapor_density
const cₚ = specific_heat
const μ = viscosity
const κ = conductivity
const σ = surface_tension
const hfg = latent_heat
const β = thermal_expansion
const Tsat = sat_temperature

for f in LIQUID_PROPERTIES
    f === :sat_temperature && continue
    @eval $f(liquid::AbstractLiquid, T) = $f(liquid, T, ATM)
end

# Saturation temperature is driven by pressure, so its short form takes the pressure.
# The temperature slot is unused and gets a placeholder.
sat_temperature(liquid::AbstractLiquid, p) = sat_temperature(liquid, 0.0, p)

"""
    _GAUSS_LEGENDRE

Nodes and weights of the 16-point Gauss-Legendre rule on `[-1, 1]`, which [`enthalpy`](@ref)
integrates the specific heat with.
"""
const _GAUSS_LEGENDRE = gauss(16)

@doc raw"""
    enthalpy(liquid, T, p) -> J/kg
    enthalpy(liquid, T)

Specific enthalpy of the liquid at temperature `T` [°C] and pressure `p` [Pa], zero at 0 °C:

```math
h(T) = ∫_0^T c_p(T') \, dT'
```

The integral is a 16-point Gauss-Legendre quadrature of [`specific_heat`](@ref), exact for a
polynomial `cₚ` of degree 31 or less, and within 1e-12 of adaptive quadrature for the water
fits. A coolant may define its own method. The two-argument form fills the pressure with
[`ATM`](@ref).

# Examples
```jldoctest
julia> enthalpy(H2O, 50.0)
208954.9069972446

julia> enthalpy(D2O, 50.0)
212827.30382156605
```
"""
function enthalpy(liquid::AbstractLiquid, T, p)
    x, w = _GAUSS_LEGENDRE
    T_nodes = (T / 2) .* (x .+ 1)   # the rule's [-1, 1] mapped onto [0, T]
    return (T / 2) * sum(w .* specific_heat.(liquid, T_nodes, p))
end
enthalpy(liquid::AbstractLiquid, T) = enthalpy(liquid, T, ATM)

"""
    _invert_enthalpy(liquid, h, p) -> °C

The temperature at which the liquid's [`enthalpy`](@ref) is `h`, by Newton's method with `cₚ`
as the slope, starting from `h / cₚ(liquid, 0 °C)`. [`temperature`](@ref) interpolates it.
"""
function _invert_enthalpy(liquid, h, p)
    T = h / specific_heat(liquid, 0.0, p)
    for _ in 1:20
        ΔT = (enthalpy(liquid, T, p) - h) / specific_heat(liquid, T, p)
        T -= ΔT
        # Quadratic convergence: a step this small leaves the next error at rounding.
        abs(ΔT) < 1e-9 && break
    end
    return T
end

"""
    _T_FIT

The temperature range [°C] that [`temperature`](@ref) is fitted over.
"""
const _T_FIT = (0.0, 300.0)

"""
    _CHEBYSHEV_ANGLES

The angles `θⱼ = π (j + 1/2) / 21`, `j = 0, …, 20`, whose cosines are the nodes
[`temperature`](@ref) interpolates through.
"""
const _CHEBYSHEV_ANGLES = [π * (j + 0.5) / 21 for j in 0:20]

"""
    _temperature_polynomial(liquid, p) -> (; h_lo, h_hi, powers)

The enthalpies at the ends of `_T_FIT` and the coefficients, in powers of
`x = 2 (h - h_lo) / (h_hi - h_lo) - 1`, of the degree 20 Chebyshev interpolant of the inverse
of [`enthalpy`](@ref) through its exact values at 21 nodes. [`temperature`](@ref) evaluates it.
"""
function _temperature_polynomial(liquid, p)
    h_lo, h_hi = enthalpy(liquid, first(_T_FIT), p), enthalpy(liquid, last(_T_FIT), p)
    nodes = cos.(_CHEBYSHEV_ANGLES)
    T_nodes = [_invert_enthalpy(liquid, h_lo + (x + 1) / 2 * (h_hi - h_lo), p) for x in nodes]
    N = length(nodes)
    c = [2 / N * sum(T_nodes .* cos.(k .* _CHEBYSHEV_ANGLES)) for k in 0:(N - 1)]
    c[1] /= 2
    # Σ cₖ Tₖ(x) rewritten in powers of x through T₀ = 1, T₁ = x and Tₖ₊₁ = 2x Tₖ - Tₖ₋₁, so
    # that `temperature` is one Horner chain.
    powers = zeros(N)
    T_prev, T_k = [1.0; zeros(N - 1)], [0.0; 1.0; zeros(N - 2)]
    powers .+= c[1] .* T_prev .+ c[2] .* T_k
    for k in 3:N
        T_prev, T_k = T_k, [0.0; 2 .* T_k[1:(end - 1)]] .- T_prev
        powers .+= c[k] .* T_k
    end
    return (; h_lo, h_hi, powers)
end

"""
    temperature(liquid, h, p) -> °C
    temperature(liquid, h)

The temperature at which the liquid's [`enthalpy`](@ref) is `h` [J/kg], at pressure `p` [Pa].

Between 0 and 300 °C it is the degree 20 Chebyshev interpolant of the exact inverse, within
1e-10 K of it for both waters, evaluated as a polynomial in `h` so that it traces into a
model's equations. Beyond either end it continues linearly, with the specific heat at that end
as the slope, so a solver iterate outside the range gets a finite temperature with a finite
slope. A coolant used well outside 0 to 300 °C should define its own method. The two-argument
form fills the pressure with [`ATM`](@ref).

# Examples
```jldoctest
julia> round(Substances.temperature(H2O, enthalpy(H2O, 50.0)); digits=9)
50.0
```
"""
function temperature(liquid::AbstractLiquid, h, p)
    (; h_lo, h_hi, powers) = _temperature_polynomial(liquid, p)
    T_lo, T_hi = _T_FIT
    inside = evalpoly(2 * (h - h_lo) / (h_hi - h_lo) - 1, powers)
    below = T_lo + (h - h_lo) / specific_heat(liquid, T_lo, p)
    above = T_hi + (h - h_hi) / specific_heat(liquid, T_hi, p)
    return ifelse(h < h_lo, below, ifelse(h > h_hi, above, inside))
end
temperature(liquid::AbstractLiquid, h) = temperature(liquid, h, ATM)

"""
    vapor_enthalpy(liquid, p) -> J/kg

Specific enthalpy of the saturated vapor at pressure `p` [Pa]: the liquid's
[`enthalpy`](@ref) at the saturation temperature plus the [`latent_heat`](@ref) there.

# Examples
```jldoctest
julia> round(vapor_enthalpy(H2O, 1.0e5); sigdigits=10)
2.675325264e6
```
"""
function vapor_enthalpy(liquid::AbstractLiquid, p)
    T_sat = sat_temperature(liquid, p)
    return enthalpy(liquid, T_sat, p) + latent_heat(liquid, T_sat, p)
end

const hₗ = enthalpy
const hᵥ = vapor_enthalpy

"""
    Liquid(; ρ=1.0, ρᵥ=1.0, cₚ=1.0, μ=1.0, Tsat=1.0, σ=1.0, hfg=1.0, κ=1.0, β=1.0)
    liquid(T, p) -> Liquid

Fixed property values, held as an `AbstractLiquid` so it can be passed anywhere a coolant
is.

Calling a liquid evaluates all nine correlations at `(T, p)` and returns the result as a
`Liquid`, freezing a coolant at one state point. `T` and `p` may be arrays, in which case
the fields hold arrays evaluated elementwise.

Constructed directly it is a temperature-independent coolant, which is what tests use to get
closed-form answers out of a channel. The all-ones default is the usual choice: with
`cₚ = 1` a uniformly heated channel rises linearly.

# Arguments
- `ρ`: density [kg/m^3]
- `ρᵥ`: vapor density [kg/m^3]
- `cₚ`: specific heat [J/(kg·K)]
- `μ`: dynamic viscosity [Pa·s]
- `Tsat`: saturation temperature [°C]
- `σ`: surface tension [N/m]
- `hfg`: latent heat of vaporization [J/kg]
- `κ`: thermal conductivity [W/(m·K)]
- `β`: thermal expansion coefficient [1/K]

The enthalpies follow from these: [`enthalpy`](@ref) of a `Liquid` is `cₚ T`, and
[`vapor_enthalpy`](@ref) is `cₚ Tsat + hfg`. So a snapshot such as `H2O(50.0)` has the
enthalpy of a liquid with the specific heat at 50 °C throughout, not light water's.
"""
struct Liquid{T} <: AbstractLiquid
    ρ::T
    ρᵥ::T
    cₚ::T
    μ::T
    Tsat::T
    σ::T
    hfg::T
    κ::T
    β::T
end

function Liquid(;
    ρ=1.0, ρᵥ=1.0, cₚ=1.0, μ=1.0, Tsat=1.0, σ=1.0, hfg=1.0, κ=1.0, β=1.0
)
    return Liquid(promote(ρ, ρᵥ, cₚ, μ, Tsat, σ, hfg, κ, β)...)
end

density(l::Liquid, T, p) = l.ρ
vapor_density(l::Liquid, T, p) = l.ρᵥ
specific_heat(l::Liquid, T, p) = l.cₚ
viscosity(l::Liquid, T, p) = l.μ
conductivity(l::Liquid, T, p) = l.κ
surface_tension(l::Liquid, T, p) = l.σ
latent_heat(l::Liquid, T, p) = l.hfg
thermal_expansion(l::Liquid, T, p) = l.β
sat_temperature(l::Liquid, T, p) = l.Tsat
enthalpy(l::Liquid, T, p) = l.cₚ * T
temperature(l::Liquid, h, p) = h / l.cₚ
vapor_enthalpy(l::Liquid, p) = l.cₚ * l.Tsat + l.hfg

# A `Liquid` returns stored numbers, so a symbolic temperature folds away to a constant,
# except in the enthalpy, which keeps it as `cₚ T`.

(liquid::AbstractLiquid)(T, p=ATM) = Liquid(
    density(liquid, T, p),
    vapor_density(liquid, T, p),
    specific_heat(liquid, T, p),
    viscosity(liquid, T, p),
    sat_temperature(liquid, T, p),
    surface_tension(liquid, T, p),
    latent_heat(liquid, T, p),
    conductivity(liquid, T, p),
    thermal_expansion(liquid, T, p),
)

function (liquid::AbstractLiquid)(T::AbstractArray, p=ATM)
    return Liquid(
        density.(liquid, T, p),
        vapor_density.(liquid, T, p),
        specific_heat.(liquid, T, p),
        viscosity.(liquid, T, p),
        sat_temperature.(liquid, T, p),
        surface_tension.(liquid, T, p),
        latent_heat.(liquid, T, p),
        conductivity.(liquid, T, p),
        thermal_expansion.(liquid, T, p),
    )
end

Base.broadcastable(liquid::AbstractLiquid) = Ref(liquid)

# A bare struct dump is nine unlabelled floats, which is unreadable at the REPL. Show the
# properties with their names and units instead, and summarise array-valued fields (which is
# what calling a liquid on a vector of temperatures produces) rather than printing them.
_show_property(v::Real) = string(round(v; sigdigits=6))
_show_property(v) = summary(v)

const _LIQUID_UNITS = (
    (:ρ, "kg/m^3"), (:ρᵥ, "kg/m^3"), (:cₚ, "J/(kg·K)"), (:μ, "Pa·s"), (:κ, "W/(m·K)"),
    (:β, "1/K"), (:σ, "N/m"), (:hfg, "J/kg"), (:Tsat, "°C"),
)

function Base.show(io::IO, ::MIME"text/plain", l::Liquid)
    print(io, "Liquid")
    for (name, unit) in _LIQUID_UNITS
        print(io, "\n  ", rpad(string(name), 4), " ",
              lpad(_show_property(getfield(l, name)), 12), " ", unit)
    end
end
