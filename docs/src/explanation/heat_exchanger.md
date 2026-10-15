# Heat exchangers and the heat sink

A reactor's heat ends up somewhere outside the model: a cooling tower, a river, the air. The
[`HeatExchanger`](@ref STREAM.Components.HeatExchanger) is where a loop hands it over, and the
form chosen decides whether that sink can run out. This page gives the physics of the three
forms and the reasons for the model behind them. The
[loss of heat sink tutorial](../tutorials/09_loss_of_heat_sink.md) builds a plant with them.

## The ideal exchanger

`HeatExchanger(T)` sends liquid out at `T` whatever arrives, in either flow direction. It is a
temperature boundary, not a model of an exchanger: it takes away whatever heat the loop brings,
at any flow, so the plant's heat sink is unbounded. That is what most models want, a loop
whose temperature is anchored while something else is studied, and it is why `HeatExchanger(T)`
appears in nearly every example. It is also what makes a loss of heat sink impossible to model
with it.

## Capacity rates and the effectiveness

A stream's capacity rate is the heat it carries per kelvin,

```math
C = |\dot m| c_p
```

Between a hot stream and a cold one, the most heat that could cross is what would bring the
stream of smaller capacity rate, ``C_{min}``, all the way to the other's inlet temperature. The
effectiveness ε is the fraction of that which does cross:

```math
Q = ε C_{min} (T_{h,in} - T_{c,in})
```

ε depends on two numbers [Incropera2007](@cite) [KaysLondon1984](@cite): the number of
transfer units, which is the exchanger's conductance against the smaller stream's capacity,
and the ratio of the capacity rates,

```math
NTU = UA / C_{min}, \qquad C_r = C_{min} / C_{max}
```

and on the arrangement, the way the streams run past each other.

**Counterflow.** The streams enter at opposite ends. The cold stream leaves next to the hot
inlet, so it can leave hotter than the hot stream does:

```math
ε = (1 - e^{-NTU (1 - C_r)}) / (1 - C_r e^{-NTU (1 - C_r)}), \qquad ε = NTU / (1 + NTU) \quad \mathrm{at}\ C_r = 1
```

**Parallel flow.** The streams enter at the same end and run the same way. The two approach a
common temperature, and neither outlet can pass it:

```math
ε = (1 - e^{-NTU (1 + C_r)}) / (1 + C_r)
```

Both arrangements are real. For the same UA and flows counterflow always transfers more, which
is why most plate and shell-and-tube exchangers approximate it.
[`HTC.effectiveness`](@ref STREAM.HTC.effectiveness) gives both:

```@example hx
using STREAM, CairoMakie

NTU = range(0.0, 5.0; length=101)
fig = Figure(size=(700, 420))
ax = Axis(fig[1, 1]; xlabel="NTU", ylabel="effectiveness ε")
for (Cr, color) in ((0.0, :black), (0.5, :steelblue), (1.0, :darkorange))
    lines!(ax, NTU, HTC.effectiveness.(HTC.Counterflow(), NTU, Cr); color,
           label="counterflow, Cr = $Cr")
    Cr > 0 && lines!(ax, NTU, HTC.effectiveness.(HTC.ParallelFlow(), NTU, Cr); color,
                     linestyle=:dash, label="parallel, Cr = $Cr")
end
axislegend(ax; position=:rb)
fig
```

At ``C_r = 0`` the two coincide at ``1 - e^{-NTU}``: one stream's temperature does not move,
so it does not matter which way it runs. At ``C_r = 1`` parallel flow can do no better than
one half.

## Where LMTD fits

The textbook form of the same exchanger is the log-mean temperature difference. Integrating
the local heat flux ``U (T_h - T_c)`` along the exchanger gives

```math
Q = UA \, ΔT_{lm}, \qquad ΔT_{lm} = (ΔT_1 - ΔT_2) / \ln(ΔT_1 / ΔT_2)
```

where ``ΔT_1`` and ``ΔT_2`` are the hot-to-cold differences at the two ends: ``T_{h,in} -
T_{c,out}`` and ``T_{h,out} - T_{c,in}`` in counterflow, and ``T_{h,in} - T_{c,in}`` and
``T_{h,out} - T_{c,out}`` in parallel flow. With the two outlets eliminated through the energy
balance of each stream, this is exactly the ε-NTU relation above. They are the same model.

STREAM solves the ε-NTU form because, given the inlets, it is explicit in the outlets. LMTD
is implicit in them, which leaves it with three problems a transient runs into:

- it is ``0/0`` when the two end differences are equal, which in counterflow is any time the
  capacity rates are;
- the logarithm is undefined if a solver iterate puts the outlets past each other;
- as one stream stops, its end difference goes to zero and the logarithm diverges.

The last is exactly the loss of heat sink. The tests check the solved exchanger against
``Q = UA ΔT_{lm}``.

## The two-stream exchanger

`HeatExchanger(; UA, arrangement)` couples two loops. Each side is a two-port, `hx.primary` and
`hx.secondary`, with no pressure drop of its own: a resistor in series supplies one. With
``T_{p,in}`` and ``T_{s,in}`` the temperatures arriving on each side, the heat into the
primary is

```math
Q = ε C_{min} (T_{s,in} - T_{p,in})
```

and each side's outlet is its inlet plus its share, ``Q / C_p`` on the primary and
``-Q / C_s`` on the secondary. The model writes the share as ``ε C_{min} / C_i``, which stays
between 0 and 1, so nothing divides by a flow that can be zero.

**A loss of heat sink.** When the secondary stops, ``C_s`` and with it ``C_{min}`` go to zero,
so ``Q`` goes to zero whatever the effectiveness. The primary then passes through unchanged
and its heat stays in the plant. Nothing in the exchanger has to be switched off: losing the
secondary flow is enough. The secondary flow can be lost to a pump trip, a valve shutting in
the secondary line, or the secondary draining.

**Flow reversal.** An arrangement is defined for forward flow on both sides. If exactly one
side flows backwards, its inlet is at the other end, so counterflow becomes parallel flow and
the reverse. The model checks the signs of the two flows and uses the formula for the
arrangement the streams are actually in. Each side reads its inlet temperature from whichever
port the liquid arrives at, as a [channel](channel.md) does.

**Properties.** Each side takes ``c_p`` at the temperature arriving there, from its own
coolant, so the two sides can be different liquids.

## The exchanger to a fixed sink

`HeatExchanger(T; UA)` is between the two. The sink is held at `T`, like the ideal exchanger,
but the exchange is finite. A sink whose temperature does not move has an unbounded capacity
rate, so ``C_r = 0`` and

```math
T_{out} = T_{in} + (1 - e^{-UA / C}) (T - T_{in})
```

It suits a cooler whose far side the plant cannot warm: an air cooler, a pond, a river. A
large `UA` recovers the ideal exchanger. Its heat sink is lost by the conductance falling (the
fans stop) or by `T` rising, both of which a time input or a callback can drive.

## A conductance that follows the flow

UA is not a property of the exchanger alone. It is the series sum of the two film resistances
and the wall's,

```math
1 / UA = 1 / (hA)_p + 1 / (hA)_s + R_{wall}
```

and each film conductance depends on its flow, roughly as ``\dot m^{0.8}`` in turbulent flow
through the Reynolds number [DittusBoelter1930](@cite). A fixed UA therefore overstates the
exchanger as a flow falls. `UA` can be a function of the two mass flows instead of a number,
and [`HTC.flow_scaled_UA`](@ref STREAM.HTC.flow_scaled_UA) builds the usual one from UA at a
known operating point and the share of its resistance on each side. Near zero flow it keeps a
small fraction of each film's conductance rather than none, so that the solver's derivatives
stay finite.

## What the model leaves out

- **Holdup.** The exchanger stores no heat: its outlets follow its inlets at once. That is
  fair when the inventory around it, a pool or the rest of a loop, holds far more heat than
  the exchanger's water and metal. A transient as fast as the exchanger's own transit time
  needs a model with storage: two [channels](channel.md) coupled through a
  [wall](conduction.md), wired in opposite directions for counterflow.
- **One phase.** Neither side boils or condenses.
- **Natural convection.** A side with no forced flow still exchanges some heat by natural
  convection. Here its film conductance falls to near zero instead, so the heat removed
  after a loss of heat sink is an underestimate, which is the conservative direction for the
  primary.
- **Pressure drop.** None, by design. The resistance of a real exchanger's passages goes in a
  separate resistor.
