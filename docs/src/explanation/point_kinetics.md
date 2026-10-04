# Point kinetics and feedback

The power of a reactor changes with its reactivity ``\rho``, the fractional excess of neutrons
produced over those lost. STREAM models this with the point kinetics equations, which treat
the neutron population as one number with a fixed spatial shape.

## The equations

Most fission neutrons are prompt, but a fraction ``\beta`` (0.65% for U-235) appears later,
from the decay of fission products called delayed neutron precursors. Grouping the precursors
by half-life into ``G`` groups gives Keepin's form [Keepin1965](@cite):

```math
\begin{aligned}
\frac{dP_n}{dt} &= \frac{\rho - \beta}{\Lambda}\,P_n + \sum_{k=1}^{G} \lambda_k\,C_k,\\
\frac{dC_k}{dt} &= \frac{\beta_k}{\Lambda}\,P_n - \lambda_k\,C_k, \qquad k = 1, \dots, G,
\end{aligned}
```

with ``P_n`` the fission power, ``C_k`` the precursor concentration of group ``k`` in the same
units, ``\beta_k`` and ``\lambda_k`` the fraction and decay constant of the group,
``\beta = \sum_k \beta_k``, and ``\Lambda`` the prompt neutron generation time.
[`PointKinetics`](@ref STREAM.Components.PointKinetics) takes any number of groups. The
defaults are Keepin's six U-235 groups and ``\Lambda = 54\ \mu\text{s}``, which belong to a
particular core: a real analysis supplies its own.

At criticality, ``\rho = 0``, a constant power holds the precursors at
``C_k = \beta_k P_n / (\lambda_k \Lambda)``, which
[`point_kinetics_steady_state`](@ref STREAM.Components.point_kinetics_steady_state)
computes. `PointKinetics` starts there by default.

## The prompt jump

A step of reactivity ``\rho < \beta`` makes the power jump almost at once, on the time scale
``\Lambda/(\beta - \rho)``, a fraction of a millisecond. The precursors cannot change that
fast, so they stay at their old values, and setting ``dP_n/dt \approx 0`` across the jump
gives the prompt jump approximation:

```math
\frac{P_1}{P_0} = \frac{\beta}{\beta - \rho}.
```

After the jump the power grows exponentially with a stable period set by the delayed
neutrons, seconds to minutes for small reactivities. At ``\rho = \beta``, one dollar, the
reactor is critical on prompt neutrons alone, and the power grows on the time scale of
``\Lambda``: this is prompt criticality, which a design must exclude.

A step of 0.2% reactivity, about 31 cents, at ``t = 0.1`` s:

```@example pk
using STREAM, CairoMakie
using STREAM.Components: PointKinetics, U235_BETA_K
using ModelingToolkit: @named, mtkcompile
CairoMakie.activate!(type="svg")

ρ_step = 0.002
@named pk = PointKinetics(t -> t < 0.1 ? 0.0 : ρ_step)
sys = mtkcompile(pk)
times = range(0.0, 2.0; length=801)
sol = solve_transient(sys, times; tstops=[0.1])

β = sum(U235_BETA_K)
fig = Figure(size=(700, 400))
ax = Axis(fig[1, 1]; xlabel="time [s]", ylabel="power / initial power")
lines!(ax, sol.t, sol[sys.P_neutron, :]; label="point kinetics")
hlines!(ax, [β / (β - ρ_step)]; linestyle=:dash, color=:gray, label="prompt jump")
axislegend(ax; position=:rb)
fig
```

Just after the step the power sits at

```@example pk
sol(0.15; idxs=sys.P_neutron)
```

against the prompt jump approximation's

```@example pk
β / (β - ρ_step)
```

and then rises slowly as the precursors build up.

## Reactivity

The reactivity the equations see is the sum of what the control system inserts and the
feedback of the core's temperatures:

```math
\rho(t) = \rho_c(t) + \sum_j \alpha_j\,(T_j - T_{\text{ref},j}).
```

**Control reactivity** ``\rho_c(t)`` is any function of time: a rod withdrawal, a step, a
scram. A [`ReactivityController`](@ref STREAM.Components.ReactivityController) makes it a
function of the state of a control system as well, so a scram can start when a trip fires (see
[Events and control](@ref)).

**Feedback** sums over cells ``j`` of the components that feed back, fuel plates and coolant
channels, each with a coefficient ``\alpha_j`` in reactivity per kelvin and a reference
temperature at which it contributes nothing. A negative coefficient is a stabilising one: as
the core heats, reactivity falls and the power with it. The coefficients are given per
component, as one number or one per cell, so a coefficient can follow the importance of each
region of the core. [`temperature_feedback`](@ref STREAM.Assemblies.Connect.temperature_feedback)
joins the kinetics to the temperatures it reads.

## Power and its uses

`PointKinetics` integrates ``P_n``, the power from fission. Its total power is

```math
P = P_n + P_\text{input}(t),
```

where ``P_\text{input}`` is power that fission does not produce, such as decay heat (see
[Decay heat](@ref)). A fuel plate should be heated by ``P``, the power it actually receives.

The kinetics can run in watts, or in units of the initial power with ``P_0 = 1`` and a scale
factor where the fuel's power is bound. Any ``P_\text{input}`` has to be in the same units.

## What the point model leaves out

The point model assumes the neutron flux keeps its shape as its amplitude changes. A rod that
moves changes the shape, and a local reactivity effect weighs differently in different places.
The per-cell feedback coefficients are where the spatial importance enters. A transient with
a strong change of flux shape, or a core whose regions are loosely coupled, needs spatial
kinetics, which STREAM does not have.

## References

```@bibliography
Pages = ["point_kinetics.md"]
Canonical = false
```
