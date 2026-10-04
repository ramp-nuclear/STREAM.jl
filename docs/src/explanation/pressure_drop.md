# Pressure drop

The flow through a cooling system is set by its pressures: a pump raises the pressure, and
every pipe, fitting, valve and channel lowers it, until the flow is the one at which the two
balance. The pressure drops fall into four kinds:

```math
\Delta p = \underbrace{f\,\frac{L}{D_h}\,\frac{\dot m|\dot m|}{2\rho A^2}}_{\text{friction}}
+ \underbrace{K\,\frac{\dot m|\dot m|}{2\rho A^2}}_{\text{local losses}}
+ \underbrace{\rho\,g\,\Delta z}_{\text{gravity}}
+ \underbrace{\frac{L}{A}\,\frac{d\dot m}{dt}}_{\text{inertia}}.
```

The first two are irreversible losses that grow roughly with the square of the flow and
always oppose it, which the ``\dot m|\dot m|`` form keeps true when the flow reverses. Gravity
depends on which way the coolant goes, up or down, and inertia only on how fast the flow
changes. A [`Channel`](@ref STREAM.Components.Channel) carries friction, gravity and inertia
inside it (see [The coolant channel](@ref)). The rest of the loop is built from components
that each carry one kind.

## Friction

Friction along a duct follows the Darcy-Weisbach equation, with a friction factor ``f`` that
depends on the Reynolds number. In STREAM a friction model is an
[`AbstractDarcyFactor`](@ref Friction.AbstractDarcyFactor), a callable
`darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f` that forms the Reynolds number at the bulk
temperature.

**Laminar flow** has the exact Hagen-Poiseuille result ``f = 64/\text{Re}`` in a circular
duct, [`Friction.Laminar`](@ref). In a rectangular duct the constant depends on the aspect
ratio, ``f = 64/(\text{Re}\,K_R)``, with ``K_R`` from a fit given in [KAERI2014](@cite)
([`Friction.RectangularLaminar`](@ref)): 0.667 between parallel plates, 1.12 for a square.
The laminar friction of a narrow plate-fuel channel is therefore about 1.5 times the circular
value.

**Turbulent flow** in a smooth pipe follows Blasius [Blasius1913](@cite),
``f = 0.3164\,\text{Re}^{-1/4}`` ([`Friction.Blasius`](@ref), the default), fitted for
``4000 < \text{Re} < 10^5``. [`Friction.Turbulent`](@ref) adds wall roughness through an
explicit form of the Colebrook-White equation [Colebrook1939](@cite), and holds at higher
Reynolds numbers.

**Across the transition**, [`Friction.RegimeDependent`](@ref) blends a laminar and a turbulent
branch linearly between two Reynolds numbers, 2000 and 5000 by default, and returns zero at
zero flow. Both matter for a transient that passes through low flow: the blend keeps ``f``
continuous, and the guard avoids the infinite ``64/\text{Re}`` at ``\text{Re} = 0``, where
the pressure drop itself, ``\propto f\,\text{Re}^2``, goes smoothly to zero.

```@example dp
using STREAM, CairoMakie
CairoMakie.activate!(type="svg")

geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.067)
Re = 10 .^ range(2, 5; length=300)
k_R = Friction.rectangular_correction(geom.depth / geom.width)
rd = Friction.RegimeDependent(; k_R)

fig = Figure(size=(700, 440))
ax = Axis(fig[1, 1]; xscale=log10, yscale=log10, xlabel="Reynolds number",
          ylabel=L"Darcy friction factor $f$")
lines!(ax, Re, Friction.laminar.(Re); label="laminar, circular")
lines!(ax, Re, Friction.laminar.(Re .* k_R); label="laminar, plate channel")
lines!(ax, Re, Friction.blasius.(Re); label="Blasius")
lines!(ax, Re, Friction.turbulent.(Re); label="Colebrook-White, smooth")
# The model takes a mass flow, so turn each Reynolds number into one at 40 °C.
ṁ = Re .* geom.A .* μ(H2O, 40.0) ./ geom.Dh
lines!(ax, Re, [rd(40.0, 40.0, m, H2O, geom) for m in ṁ];
       label="regime dependent, plate channel", linewidth=3, color=(:black, 0.35))
axislegend(ax; position=:rt)
fig
```

**Heated walls.** The coolant next to a heated wall is hotter and less viscous than the bulk,
so the friction there is lower. `RegimeDependent` takes an optional correction,
[`Friction.viscosity_correction`](@ref),

```math
K_H = 1 + \frac{P_\text{heated}}{P_\text{wet}}\left[\left(\frac{\mu_w}{\mu_b}\right)^{0.58} - 1\right],
```

which multiplies ``f``. It is off by default, as in Python STREAM.

## Local losses

A sudden change of flow area, a bend, a grid or an orifice causes a loss that depends on the
fitting, not on a length of pipe:

```math
\Delta p = K\,\frac{\dot m|\dot m|}{2\rho A^2}.
```

[`LocalPressureDrop`](@ref STREAM.Components.LocalPressureDrop) computes ``K`` for a sudden
expansion or contraction from Idelchik's tables [Idelchik1996](@cite), as functions of the
area ratio and the Reynolds number. At high Reynolds number the expansion loss is the
Borda-Carnot result ``K = (1 - A_1/A_2)^2``, and the contraction loss
``K = 0.5\,(1 - A_1/A_2)^{3/4}``. The direction of the flow decides which applies: a sudden
expansion in forward flow is a sudden contraction in reversed flow.

For a fitting with no correlation, a measured or design operating point is enough.
[`ResistorFromKnownPoint`](@ref STREAM.Components.ResistorFromKnownPoint) builds a quadratic
loss through a known ``(\Delta p, \dot m)`` at a known temperature, which is how a loop is
calibrated against plant data. [`VolumetricFlowResistor`](@ref STREAM.Components.VolumetricFlowResistor)
takes the loss coefficient in terms of volumetric flow, the way pump and valve data are often
given.

## Gravity

A column of coolant of height ``H`` weighs ``\rho\,g\,H`` per unit area.
[`Gravity`](@ref STREAM.Components.Gravity) adds it to a loop, with ``\rho`` at the
temperature of the coolant passing through, and a channel adds it cell by cell. Around a
closed loop the heights cancel, but the densities do not: a loop whose rising leg is hotter
than its falling leg has a net buoyancy head

```math
\Delta p_\text{buoyancy} = g\,H\,(\rho_\text{cold} - \rho_\text{hot}),
```

which drives natural circulation. This is why the sign of ``g`` on every channel and gravity
element matters, and [`check_gravity_mismatch`](@ref STREAM.Assemblies.check_gravity_mismatch)
checks that the channels of a loop agree about which way is up.

## Inertia

Accelerating the coolant in a pipe of length ``L`` and area ``A`` takes a pressure
``(L/A)\,d\dot m/dt``. [`Inertia`](@ref STREAM.Components.Inertia) adds it. Its main use is a
flywheel or a long pipe that keeps the flow going after a pump trip: with the pump off and a
quadratic loss ``k\,\dot m^2`` in the loop, the flow coasts down as

```math
\dot m(t) = \frac{\dot m_0}{1 + \dot m_0\,(k A/L)\,t},
```

so a larger ``L/A`` keeps the flow longer. The [Pump coastdown](../tutorials/03_pump_coastdown.md)
tutorial checks STREAM against this solution.

## Implications of the choices

- **At low flow the quadratic losses vanish.** Friction in turbulent flow and local losses go
  as ``\dot m^2``, so at the low flows of natural circulation they are small and the laminar
  friction, linear in ``\dot m``, sets the flow. A loop model that is accurate at full flow
  can be poor at natural circulation if its low-flow behaviour was never checked.
- **The friction factor is fitted to fully developed flow.** Entrance effects, spacers and
  plate-end fittings add losses that belong in local loss terms.
- **Pressure drops are evaluated at single-phase density.** Boiling would raise the friction
  and the acceleration losses sharply. This is the effect behind the
  [Onset of flow instability](@ref), and STREAM does not model it.

## References

```@bibliography
Pages = ["pressure_drop.md"]
Canonical = false
```
