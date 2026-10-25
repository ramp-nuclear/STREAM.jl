# Change the coolant

A component takes its coolant as the `liquid` keyword, light water ([`H2O`](@ref)) by
default. A model can instead name its coolant once with [`with_coolant`](@ref) and leave the
keyword out. An explicit keyword wins over the block, and the block wins over the default.

## Per component

Pass [`D2O`](@ref) to each component that carries coolant:

```@example coolant
using STREAM
using STREAM.Components: ChannelAndContacts, Gravity, ResistorFromKnownPoint
using ModelingToolkit: @named

geom = Duct(0.6, Rectangular(0.067, 0.0024); heated=0.063)
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

## Once for a whole model

Build the components inside a `with_coolant` block, and every `liquid` keyword left out
takes the block's coolant:

```@example coolant
using STREAM.Components: HeatExchanger, Pump
using STREAM.Assemblies: inseries

model = with_coolant(D2O) do
    @named pump = Pump(3.0e4)
    @named hx = HeatExchanger(40.0)
    @named core = ChannelAndContacts(; n=10, geometry=geom)
    assembly([inseries(pump, hx, core, pump), pump.inlet.p ~ ATM], pump, hx, core; name=:model)
end
@assert Substances.coolant(model.core) === D2O   # the channel keeps the block's coolant
Substances.default_coolant()
```

The block returns its last expression, here the model, and `Substances.default_coolant()` is
back to `H2O` outside it.

Every channel records the coolant it was built with, so a `ChannelState` reads the right one
after the block ends. `steady_state_guess` runs before any model exists, so it reads the default
when it is called: call it inside the block, or pass `liquid=`.

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
