# Wall heat transfer

Heat leaves a fuel plate or rod through its surface into the coolant. The rate is set by the
heat transfer coefficient ``h``, defined by Newton's law of cooling,

```math
q'' = h\,(T_w - T_b),
```

with ``q''`` the heat flux through the wall, ``T_w`` the wall surface temperature and ``T_b``
the bulk coolant temperature. Correlations give ``h`` through the Nusselt number
``\text{Nu} = h\,D_h/k``, a function of the flow (Reynolds number), the fluid (Prandtl
number) and, for natural convection, buoyancy (Grashof or Rayleigh number).

In STREAM, a heat transfer model is an [`AbstractHTC`](@ref HTC.AbstractHTC), a callable

```julia
htc(T_wall, T_bulk, ṁ, Dh, A, liquid) -> h
```

that a [`ChannelAndContacts`](@ref STREAM.Components.ChannelAndContacts) evaluates per cell and
per face. Anything a correlation needs beyond these (the geometry, gravity, a transition band)
it captures when it is built. This page describes the models STREAM ships and the physics
behind them, using Python STREAM's names for the regimes: single-phase liquid (SPL),
incipience of boiling (INC) and subcooled boiling (SCB).

## Single-phase forced convection

**Turbulent flow.** [`HTC.DittusBoelter`](@ref) uses the Dittus-Boelter correlation in its
heating form [DittusBoelter1930](@cite),

```math
\text{Nu} = 0.023\,\text{Re}^{0.8}\,\text{Pr}^{0.4},
```

fitted for ``\text{Re} > 10^4``, ``0.6 \le \text{Pr} \le 160`` and fully developed flow,
``L/D_h > 10``. It is the standard choice in research reactor analysis. Its scatter against
data is commonly quoted as ±25%, it was fitted to circular tubes, and it is used for narrow
rectangular channels through the hydraulic diameter, so its uncertainty belongs in the hot
channel factors (see [Margins](@ref)). Below ``\text{Re} = 10^4`` it overpredicts, which is
why it should not be used alone near the laminar transition.

**Laminar flow.** In fully developed laminar flow the Nusselt number is a constant that
depends only on the duct shape and the heating. For parallel plates both heated at a uniform
flux it is 8.235 [ShahLondon1978](@cite), the default of [`HTC.ConstantNusselt`](@ref). A
rectangular duct of aspect ratio ``\alpha = \text{depth}/\text{width}`` heated on its two long
sides has a lower value, which [`HTC.FullyDevelopedLaminar`](@ref) takes from Shah and
London's polynomial fit. Near the entrance of a heated channel the thermal boundary layer is
still thin and the Nusselt number higher, which [`HTC.DevelopingLaminar`](@ref) follows as a
function of the dimensionless distance ``x^* = x/(D_h\,\text{Re}\,\text{Pr})``.

**Property basis.** A correlation is evaluated with the coolant properties at some
temperature, and the choice changes ``h`` because viscosity falls steeply with temperature.
[`HTC.AtFilm`](@ref) reads them at the film temperature ``(T_w + T_b)/2``, the usual choice
for turbulent correlations. [`HTC.AtBulk`](@ref) reads them at the bulk, the usual choice for
laminar ones. Every model takes a `basis` keyword.

## Natural convection

With little or no forced flow, as after a pump trip, the coolant next to a hot wall rises
because it is lighter. Elenbaas measured natural convection between parallel vertical plates
[Elenbaas1942](@cite), and his correlation, [`HTC.Elenbaas`](@ref), uses the plate gap ``b``
as the length scale:

```math
\text{Nu} = \frac{1}{24}\,\text{Ra}\,\frac{b}{L}
\left(1 - e^{-35\,L/(\text{Ra}\,b)}\right)^{3/4}.
```

For a narrow gap or a slow flow (``\text{Ra}\,b/L`` small) the exponential vanishes and
``\text{Nu} \to \text{Ra}\,b/(24 L)``, the fully developed flow between the plates. For a wide
gap it tends to ``\text{Nu} \to (35^{3/4}/24)\,(\text{Ra}\,b/L)^{1/4}``, the boundary layer of
an isolated vertical plate.

## Choosing by regime

A channel that coasts down from forced flow to natural circulation passes through every
regime. [`HTC.RegimeDependent`](@ref) chooses:

- by the **bulk Reynolds number**, between its `laminar` and `turbulent` models, blending
  linearly across a transition band, 2000 to 5000 by default, so that ``h`` stays continuous;
- by **buoyancy**, switching to its `natural` model where ``\text{Gr} > \text{Re}^2``, the
  usual criterion for buoyancy outweighing the forced flow. Gr and Re are both taken at the
  film temperature, with ``D_h`` as the length, so that like is compared with like.

The switch to natural convection is a step, not a blend. A solver integrating through it
sees ``h`` jump, which it handles by taking smaller steps there.

The figure shows ``h`` against flow for a plate-fuel channel, 2.4 mm by 67 mm and 0.6 m long,
with the bulk at 40 °C and the wall at 60 °C.

```@example htc
using STREAM, CairoMakie
CairoMakie.activate!(type="svg")

geom = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.067)
T_wall, T_bulk = 60.0, 40.0
models = [
    "Dittus-Boelter" => HTC.DittusBoelter(),
    "constant Nu = 8.235" => HTC.ConstantNusselt(),
    "regime dependent, with Elenbaas" => HTC.RegimeDependent(;
        laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(),
        natural=HTC.Elenbaas(geom), geom),
]
ṁ = range(1e-4, 0.15; length=600)
Re_bulk = [Re(H2O, T_bulk, m, geom.A, geom.Dh) for m in ṁ]

fig = Figure(size=(700, 420))
ax = Axis(fig[1, 1]; xlabel="bulk Reynolds number", ylabel=L"$h$ [kW/(m²·K)]")
for (label, model) in models
    h = [model(T_wall, T_bulk, m, geom.Dh, geom.A, H2O) for m in ṁ]
    lines!(ax, Re_bulk, h ./ 1e3; label)
end
vspan!(ax, 2000, 5000; color=(:gray, 0.12))
axislegend(ax; position=:lt)
fig
```

The shaded band is the laminar-turbulent blend. At the lowest flows, where buoyancy outweighs
the forced flow, the regime-dependent model switches to natural convection. Here that gives a
lower ``h`` than the laminar constant: the switch is a choice of regime, not of the larger
value, and it is the conservative one. [`HTC.Maximal`](@ref) takes the larger of several
models instead, for a wall cooled by whichever mechanism wins.

## Subcooled boiling

Past the [Onset of nucleate boiling](@ref), bubbles at the wall carry heat away on top of
convection, and the wall stays cooler than single-phase convection would make it.
[`HTC.SubcooledBoiling`](@ref) adds this to any single-phase model with the partial boiling
interpolation of Bergles and Rohsenow [BerglesRohsenow1964](@cite):

```math
q'' = \sqrt{q''^2_\text{spl} + \big(q''_\text{scb}(T_w) - q''_\text{scb}(T_\text{ONB})\big)^2},
```

where ``q''_\text{spl}`` is the single-phase flux and ``q''_\text{scb}`` a fully developed
boiling curve, a function of the wall superheat only. At the onset the second term is zero and
the flux is single-phase. Far above it, boiling dominates and the flux follows the boiling
curve. STREAM writes the same thing as a factor on ``h``, so the channel's equations do not
change form.

The boiling curve is McAdams' for turbulent flow [McAdams1949](@cite) and Rohsenow's pool
boiling correlation for laminar flow [Rohsenow1952](@cite), blended across the same Reynolds
band as the single-phase models by [`HTC.regime_dependent_q_scb`](@ref).

```@example htc
p = 1.7e5
T_sat = Tsat(H2O, p)
ṁ0 = 0.3
spl = HTC.DittusBoelter()
scb = HTC.SubcooledBoiling(spl, HTC.regime_dependent_q_scb())
T_w = range(T_bulk + 1, T_sat + 30; length=300)
q_spl = [spl(Tw, T_bulk, ṁ0, geom.Dh, geom.A, H2O) * (Tw - T_bulk) for Tw in T_w]
q_scb = [scb(Tw, T_bulk, ṁ0, geom.Dh, geom.A, H2O, p) * (Tw - T_bulk) for Tw in T_w]

fig = Figure(size=(700, 420))
ax = Axis(fig[1, 1]; xlabel=L"wall superheat $T_w - T_\mathrm{sat}$ [K]",
          ylabel=L"heat flux $q''$ [MW/m²]")
lines!(ax, T_w .- T_sat, q_spl ./ 1e6; label="single phase only")
lines!(ax, T_w .- T_sat, q_scb ./ 1e6; label="with subcooled boiling")
axislegend(ax; position=:lt)
fig
```

Below the onset the two curves coincide. Above it the boiling curve rises much more steeply:
a small rise in wall temperature removes a lot more heat.

## Implications of the choices

- **Dittus-Boelter everywhere** is the simplest model, and adequate for normal operation at
  high flow. It is not adequate for a loss of flow, where it predicts ``h \to 0`` as the flow
  stops. Use `RegimeDependent` with a natural branch for any transient that reaches low flow.
- **The laminar constant** assumes fully developed flow. Channels are short enough that the
  entrance region covers a fair part of them at low Reynolds number, where the true ``h`` is
  higher, so the constant is conservative.
- **Subcooled boiling** lowers the predicted wall temperature. A margin to the onset of
  nucleate boiling is then a margin to the regime change, not to damage, and a model without
  it overpredicts wall temperatures past the onset.
- **Two faces.** Each face of a channel gets its own ``h`` from its own wall temperature, so a
  channel between two plates at different powers has different coefficients on each side.

## References

```@bibliography
Pages = ["heat_transfer.md"]
Canonical = false
```
