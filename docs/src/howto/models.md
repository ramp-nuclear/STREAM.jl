# Choose heat transfer and friction models

A [`ChannelAndContacts`](@ref STREAM.Components.ChannelAndContacts) takes its wall heat
transfer model as `htc` and its friction model as `darcy`. Both are values: build one, pass it
in. The physics behind each is in [Wall heat transfer](../explanation/heat_transfer.md) and
[Pressure drop](../explanation/pressure_drop.md).

```@example models
using STREAM
using STREAM.Components: ChannelAndContacts
using ModelingToolkit: @named

geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
nothing # hide
```

## A model for every regime

For a transient that reaches low flow, switch models by regime. This is the combination the
[pool loss-of-flow tutorial](../tutorials/06_pool_lofa.md) uses: laminar, turbulent and natural
convection, with subcooled boiling on top, and friction that blends from laminar to turbulent
with the rectangular-duct correction.

```@example models
htc = HTC.SubcooledBoiling(
    HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(),
                        natural=HTC.Elenbaas(geom), geom),
    HTC.regime_dependent_q_scb(),
)
darcy = Friction.RegimeDependent(; k_R=Friction.rectangular_correction(geom.depth / geom.width))
@named ch = ChannelAndContacts(; n=10, geometry=geom, htc, darcy)
nothing # hide
```

A model can be called directly, which is a quick way to see what it gives. A heat transfer
model takes the wall and bulk temperatures, the flow, the hydraulic diameter, the flow area
and the coolant:

```@example models
htc(60.0, 40.0, 0.3, geom.Dh, geom.A, H2O)
```

A friction model takes the bulk and wall temperatures, the flow, the coolant and the geometry:

```@example models
darcy(40.0, 60.0, 0.3, H2O, geom)
```

## Read the properties at the film or the bulk

Each Nusselt-based model takes a `basis`: [`HTC.AtFilm`](@ref), the default, reads the coolant
properties at ``(T_w + T_b)/2``, and [`HTC.AtBulk`](@ref) at the bulk temperature.

```@example models
(film=HTC.DittusBoelter()(80.0, 40.0, 0.3, geom.Dh, geom.A, H2O),
 bulk=HTC.DittusBoelter(; basis=HTC.AtBulk())(80.0, 40.0, 0.3, geom.Dh, geom.A, H2O))
```

`HTC.RegimeDependent` sets the basis of its branches itself: bulk for the laminar and natural
branches, film for the turbulent one.

## Add the heated-wall viscosity correction

```@example models
darcy_hot = Friction.RegimeDependent(; viscosity=Friction.viscosity_correction)
(plain=darcy(40.0, 90.0, 0.3, H2O, geom), corrected=darcy_hot(40.0, 90.0, 0.3, H2O, geom))
```

The wall's lower viscosity lowers the friction. A channel using this correction needs both
wall temperatures bound.

## Use your own correlation

A Nusselt correlation is a function `(Re, Pr, T_wall, T_bulk) -> Nu`. Wrap it in
[`HTC.FromNusselt`](@ref) and it becomes a model. Here is Gnielinski's correlation, which
STREAM does not ship:

```@example models
function gnielinski(Re, Pr, args...)
    f = (0.79 * log(Re) - 1.64)^-2
    return (f / 8) * (Re - 1000) * Pr / (1 + 12.7 * sqrt(f / 8) * (Pr^(2 / 3) - 1))
end
gn = HTC.FromNusselt(gnielinski)
gn(60.0, 40.0, 0.3, geom.Dh, geom.A, H2O)
```

A friction correlation of the Reynolds number alone goes into [`Friction.FromReynolds`](@ref):

```@example models
mcadams_friction = Friction.FromReynolds(Re -> 0.184 * Re^-0.2)
mcadams_friction(40.0, 40.0, 0.3, H2O, geom)
```

For anything else, [`HTC.FromFunction`](@ref) and [`Friction.FromFunction`](@ref) take a
function of the full argument list.

The model is evaluated inside the equations, with symbolic arguments, so it must be plain
arithmetic: no `if` on its arguments, since that would be decided once when the model is
built. Use `ifelse` for a branch, and keep both branches finite, since both are evaluated:

```@example models
# Gnielinski is fitted above Re = 3000. Below that, fall back to the laminar constant.
safe(Re, Pr, args...) = ifelse(Re > 3000, gnielinski(max(Re, 3000.0), Pr), 8.235)
HTC.FromNusselt(safe)(60.0, 40.0, 0.01, geom.Dh, geom.A, H2O)
```
