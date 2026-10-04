# Change the coolant

Every component that reads coolant properties takes a `liquid` keyword, light water ([`H2O`](@ref))
by default.

## Heavy water

Pass [`D2O`](@ref) to each component that carries coolant:

```@example coolant
using STREAM
using STREAM.Components: ChannelAndContacts, Gravity, ResistorFromKnownPoint
using ModelingToolkit: @named

geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
@named ch = ChannelAndContacts(; n=10, geometry=geom, liquid=D2O)
@named rise = Gravity(2.0; liquid=D2O)
@named orifice = ResistorFromKnownPoint(; dp=-2.0e3, ṁ=0.4, T=40.0, liquid=D2O)
nothing # hide
```

The heat transfer and friction models read their properties from the liquid the channel
passes them, so they need no change. The property functions take any liquid:

```@example coolant
(ρ(H2O, 50.0), ρ(D2O, 50.0), Tsat(H2O, 1.0e5), Tsat(D2O, 1.0e5))
```

## Properties frozen at one state

Calling a coolant at a temperature and pressure gives its properties there, as a
[`Substances.Liquid`](@ref):

```@example coolant
H2O(40.0, 1.7e5)
```

A `Liquid` is itself a coolant, whose properties do not change with temperature. Pass one as
`liquid` to remove the property variation from a model, as for a check against a hand
calculation. One can also be built from chosen values:

```@example coolant
simple = Substances.Liquid(; ρ=1000.0, cₚ=4180.0, μ=1.0e-3, κ=0.6)
ρ(simple, 90.0)
```

## A new coolant

A coolant is a type below [`Substances.AbstractLiquid`](@ref) with nine property methods, each
taking the liquid, a temperature in °C and a pressure in Pa. Here is a made-up liquid with
linear properties:

```@example coolant
import STREAM.Substances: density, vapor_density, specific_heat, viscosity, conductivity,
                          surface_tension, latent_heat, thermal_expansion, sat_temperature

struct LinearLiquid <: Substances.AbstractLiquid end
density(::LinearLiquid, T, p) = 1000.0 - 0.4 * T
vapor_density(::LinearLiquid, T, p) = 0.6
specific_heat(::LinearLiquid, T, p) = 4180.0
viscosity(::LinearLiquid, T, p) = 1.0e-3 * exp(-0.02 * (T - 20))
conductivity(::LinearLiquid, T, p) = 0.6
surface_tension(::LinearLiquid, T, p) = 0.06
latent_heat(::LinearLiquid, T, p) = 2.26e6
thermal_expansion(::LinearLiquid, T, p) = 0.4 / density(LinearLiquid(), T, p)
sat_temperature(::LinearLiquid, T, p) = 100.0 + 25.0 * log(p / 1.0e5)

(ρ(LinearLiquid(), 50.0), Tsat(LinearLiquid(), 2.0e5))
```

The two-argument forms, `ρ(liquid, T)` and `Tsat(liquid, p)`, come for free. Write the
methods as plain arithmetic, since a channel evaluates them on symbolic temperatures:
`exp` and `log` are fine, an `if` on `T` is not.

Components call the two-argument forms, at atmospheric pressure. A coolant whose properties
depend on pressure can define its own two-argument method to choose a different one.
