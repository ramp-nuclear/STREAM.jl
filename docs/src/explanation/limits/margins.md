# Margins

A limit on its own says where trouble starts. A safety analysis needs to say how far the
solved state is from it, as one number per limit that can be compared against an acceptance
criterion. STREAM computes these numbers after a solve with [`threshold_analysis`](@ref Thresholds.threshold_analysis),
which reads a channel's solved state into a [`ChannelState`](@ref Thresholds.ChannelState) and applies the
correlations you name to it. This page explains what the numbers mean.

## Two kinds of margin

Some limits are temperatures and give a *difference*:

```math
\Delta T_\text{ONB} = T_\text{ONB} - T_w, \qquad
\Delta T_\text{wall} = T_\text{allowed} - T_\text{limit}.
```

The others are heat fluxes or powers and give a *ratio*, the limit over the actual value:

```math
\text{CHFR}(z) = \frac{q''_\text{CHF}(z)}{q''(z)}, \qquad
\text{OSVR}(z) = \frac{q''_\text{OSV}(z)}{q''(z)}, \qquad
\text{OFIR} = \frac{Q_\text{OFI}}{Q_\text{channel}}.
```

Either way, larger is safer, and the margin is lost when the difference reaches 0 or the
ratio reaches 1. [`worst_case`](@ref Thresholds.worst_case) relies on this: it returns the smallest value of a
margin field, with the cell and the time where it occurs.

## Flux ratios and power ratios

A ratio can mean two different things, and the distinction matters.

A **flux ratio** compares the limit and the flux at one cell, with everything else held at the
solved state. CHFR is one: it is the factor the local flux could rise by, with the bulk
temperature, flow and pressure unchanged. That is the right question for a local hot spot,
whose extra heat does not reach the bulk. It is not the right question for a rise in channel
power, which also heats the bulk and so reduces the subcooling the limit depends on.

A **power ratio** asks by what factor the whole channel's power could rise before the limit,
with the bulk temperature following the power. OFIR is one, since the Whittle-Forgan
correlation is written for the channel power. The OSV flux STREAM computes is another: its
bulk temperature is that of a channel running at the OSV flux (see
[Onset of significant void](@ref)), so ``q''_\text{OSV}(z)/q''(z)`` is the power factor at
which OSV first appears at ``z``.

For the same channel, a flux ratio is usually larger than the power ratio of the same limit, because
it ignores the heating of the bulk. Use flux ratios for local effects and power ratios for
global ones, and say which one an acceptance criterion is written for.

## Which face

A plate between two channels heats each from one face, and the two faces can carry different
fluxes. The threshold functions on a `ChannelState` take a `direction`, or [`chfr`](@ref Thresholds.chfr)
does: `:left`, `:right`, or `:max` for the larger flux, the conservative default. A face that
is not heating the coolant gives an infinite ratio, since a wall the coolant is cooling cannot
reach CHF.

## Over a transient

For a transient, [`threshold_analysis`](@ref Thresholds.threshold_analysis) builds a `ChannelState` at every saved time,
so a correlation sees the flow and temperatures at that time. A per-cell margin comes back as
a matrix with one column per saved time, and `worst_case(margin; times=sol.t)` finds the
minimum over cells and time. The minimum can fall between saved times, so save often enough
to resolve the events that drive it: a trip, the flow reversal, the opening of a valve.

## Uncertainties

The margins STREAM computes are for the conditions it was given. A safety analysis also has
to cover what those conditions do not: the uncertainty in the power distribution, the fuel
fabrication tolerances, the flow distribution between channels, and the scatter of the
correlations themselves. Research reactor practice expresses these as hot channel and hot
spot factors, which multiply the power, the flow or the film temperature drop, and combines
them either multiplicatively or statistically [IAEA1980](@cite). The acceptance criterion is
then a minimum value of the margin after the factors are applied.

STREAM does not apply such factors for you. Apply them through the inputs (raise the channel
power, lower its flow), or through the analysis: [`twall_limit`](@ref Thresholds.twall_limit) takes an inhomogeneity
factor on the local flux, and a CHF ratio can be divided by the uncertainty of the
correlation behind it.

## References

```@bibliography
Pages = ["margins.md"]
Canonical = false
```
