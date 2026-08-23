"""
    AbstractLiquid

Supertype for coolants. A concrete liquid implements the nine three-argument methods
listed in [`LIQUID_PROPERTIES`](@ref), each taking `(liquid, T, p)` with `T` in Celsius
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

The two-argument forms are generated over [`LIQUID_PROPERTIES`](@ref) with the signature
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
| `κ`   | `conductivity`      |        |                   |
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

# A `Liquid` returns stored numbers, so a symbolic temperature folds away to a constant.

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
