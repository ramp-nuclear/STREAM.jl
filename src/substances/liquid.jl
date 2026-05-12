using ModelingToolkit
const atm = 101325.0
abstract type AbstractLiquid end

struct Liquid{T}
    ρ::T
    ρᵥ::T
    cₚ::T
    μ::T
    Tsat::T
    σ::T
    hfg::T
    k::T
    β::T
end

function density(::AbstractLiquid, T, p) end
const ρ = density
@register_symbolic ρ(liq, T, p)

function vapor_density(::AbstractLiquid, T, p) end
const ρᵥ = vapor_density
@register_symbolic ρᵥ(liq, T, p)

function specific_heat(::AbstractLiquid, T, p) end
const cₚ = specific_heat
@register_symbolic cₚ(liq, T)

function viscosity(::AbstractLiquid, T, p) end
const μ = viscosity
@register_symbolic μ(liq, T, p)

function conductivity(::AbstractLiquid, T, p) end
const k = conductivity
@register_symbolic k(liq, T, p)

function surface_tension(::AbstractLiquid, T, p) end
const σ = surface_tension
@register_symbolic σ(liq, T, p)

function latent_heat(::AbstractLiquid, T, p) end
const hfg = latent_heat
@register_symbolic hfg(liq, T, p)

function thermal_expansion(::AbstractLiquid, T, p) end
const β = thermal_expansion
@register_symbolic β(liq, T, p)

function sat_temperature(::AbstractLiquid, T, p) end
const Tsat = sat_temperature
@register_symbolic Tsat(liq, T, p)


(liq::AbstractLiquid)(T::P, p::P) where P = Liquid{P}(
        density(liq, T, p),
        vapor_density(liq, T, p),
        specific_heat(liq, T, p),
        viscosity(liq, T, p),
        sat_temperature(liq, T, p),
        surface_tension(liq, T, p),
        latent_heat(liq, T, p),
        conductivity(liq, T, p),
        thermal_expansion(liq, T, p),
)

(liq::AbstractLiquid)(T::P, p::P) where P <: AbstractArray = Liquid{P}(
        density.(liq, T, p),
        vapor_density.(liq, T, p),
        specific_heat.(liq, T, p),
        viscosity.(liq, T, p),
        sat_temperature.(liq, T, p),
        surface_tension.(liq, T, p),
        latent_heat.(liq, T, p),
        conductivity.(liq, T, p),
        thermal_expansion.(liq, T, p),
)

Base.broadcastable(liq::AbstractLiquid) = Ref(liq)
