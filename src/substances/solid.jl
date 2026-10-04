"""
    Solid(ρ, cₚ, κ)
    Solid(; ρ, cₚ, κ)

Bulk thermal properties of a solid, constant in temperature.

A plate or rod made of several materials is a `Matrix{Solid}` with one entry per cell, and
`κ.(materials)` gives the matching conductivity matrix.

# Arguments
- `ρ`: density [kg/m^3]
- `cₚ`: specific heat [J/(kg·K)]
- `κ`: thermal conductivity [W/(m·K)]

# Returns
A `Solid`. `density`, `specific_heat` and `conductivity` (or `ρ`, `cₚ`, `κ`) read its fields.

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
Solid(; ρ, cₚ, κ) = Solid(ρ, cₚ, κ)

density(s::Solid) = s.ρ
specific_heat(s::Solid) = s.cₚ
conductivity(s::Solid) = s.κ
Base.broadcastable(s::Solid) = Ref(s)
