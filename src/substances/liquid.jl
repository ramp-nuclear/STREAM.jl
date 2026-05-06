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

function density(::AbstractLiquid, T) end
const ρ = density
@register_symbolic ρ(liq, T)

function vapor_density(::AbstractLiquid, T) end
const ρᵥ = vapor_density
@register_symbolic ρᵥ(liq, T)

function specific_heat(::AbstractLiquid, T) end
const cₚ = specific_heat
@register_symbolic cₚ(liq, T)

function viscosity(::AbstractLiquid, T) end
const μ = viscosity
@register_symbolic μ(liq, T)

function conductivity(::AbstractLiquid, T) end
const k = conductivity
@register_symbolic k(liq, T)

function surface_tension(::AbstractLiquid, T) end
const σ = surface_tension
@register_symbolic σ(liq, T)

function latent_heat(::AbstractLiquid, T) end
const hfg = latent_heat
@register_symbolic hfg(liq, T)

function thermal_expansion(::AbstractLiquid, T) end
const β = thermal_expansion
@register_symbolic β(liq, T)

function sat_temperature(::AbstractLiquid, p) end
const Tsat = sat_temperature
@register_symbolic Tsat(liq, p)


(liq::AbstractLiquid)(T::P, p::P) where P = Liquid{P}(
        density(liq, T),
        vapor_density(liq, T),
        specific_heat(liq, T),
        viscosity(liq, T),
        sat_temperature(liq, p),
        surface_tension(liq, T),
        latent_heat(liq, T),
        conductivity(liq, T),
        thermal_expansion(liq, T),
)

(liq::AbstractLiquid)(T::P, p::P) where P <: AbstractArray = Liquid{P}(
        density.(liq, T),
        vapor_density.(liq, T),
        specific_heat.(liq, T),
        viscosity.(liq, T),
        sat_temperature.(liq, p),
        surface_tension.(liq, T),
        latent_heat.(liq, T),
        conductivity.(liq, T),
        thermal_expansion.(liq, T),
)

Base.broadcastable(liq::AbstractLiquid) = Ref(liq)