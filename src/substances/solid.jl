"""
    Solid(ρ, cₚ, κ)
    Solid(; ρ, cₚ, κ)
    Solid(; density, specific_heat, conductivity)

Bulk thermal properties of a solid, constant in temperature.

A plate or rod made of several materials is a `Matrix{Solid}` with one entry per cell, and
`κ.(materials)` gives the matching conductivity matrix.

# Arguments
- `ρ`, or `density` in ASCII: density [kg/m^3]
- `cₚ`, or `specific_heat`: specific heat [J/(kg·K)]
- `κ`, or `conductivity`: thermal conductivity [W/(m·K)]

Each property takes either spelling.

# Returns
A `Solid`. `density`, `specific_heat` and `conductivity` (or `ρ`, `cₚ`, `κ`) read its fields.

# Throws
`ArgumentError` when a property is missing.

# Example
```julia
clad, meat = Solid(2700, 900, 250), Solid(3000, 800, 100)
materials = ifelse.([false true false], meat, clad)   # clad-meat-clad across the plate
κ.(materials)                                        # [250.0 100.0 250.0]
```
"""
struct Solid{T}
    ρ::T
    cₚ::T
    κ::T
end

Solid(ρ, cₚ, κ) = Solid(promote(ρ, cₚ, κ)...)
# Julia does not dispatch on keywords, so one method takes both spellings.
function Solid(; ρ=nothing, cₚ=nothing, κ=nothing, density=ρ, specific_heat=cₚ, conductivity=κ)
    props = (density, specific_heat, conductivity)
    any(isnothing, props) && throw(ArgumentError("Solid needs a density, specific heat and conductivity"))
    return Solid(props...)
end

density(s::Solid) = s.ρ
specific_heat(s::Solid) = s.cₚ
conductivity(s::Solid) = s.κ
Base.broadcastable(s::Solid) = Ref(s)
