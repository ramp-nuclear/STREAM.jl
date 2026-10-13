# Wall temperature limit

The simplest limit is a temperature: the clad surface must stay below a value set by the fuel,
not by the coolant. For aluminium-clad plate fuel the usual one is the blister temperature,
above which gas trapped in the fuel meat swells the clad. Fuel qualification sets its value
for a given fuel type, so STREAM leaves it to you. For transients that heat the fuel quickly,
such as reactivity insertions, the peak clad temperature is often the limit that governs.

## The inhomogeneity factor

The solved wall temperature belongs to the heat flux the model was given: an average over each
cell, from a nominal fuel loading. Real fuel has local hot spots where the fuel meat is
thicker or denser than nominal, and there the flux is higher by a factor ``f`` that fuel
manufacturing tolerances bound. Holding the coolant temperature and the heat transfer
coefficient fixed and scaling the flux by ``f`` gives the wall temperature at such a spot:

```math
T_\text{limit} = T_b + f\,\frac{q''}{h} = T_b + f\,(T_w - T_b),
```

since ``q'' = h\,(T_w - T_b)``. This is [`twall_limit`](@ref Thresholds.twall_limit). Python STREAM writes it in the
first form and STREAM.jl in the second, which needs only the solved temperatures.

Holding ``h`` fixed is the assumption to keep in mind. If the hot spot pushes the wall past
[Onset of nucleate boiling](@ref), the real ``h`` rises and the real wall runs cooler than
this, so the estimate is conservative there. It is not conservative if the hot spot is large
enough to raise the bulk temperature too, which the factor does not account for.

On a [`ChannelState`](@ref Thresholds.ChannelState), `twall_limit` evaluates both faces and returns the hotter, per
cell. Compare it with the limit for your fuel; the margin is
``T_\text{allowed} - T_\text{limit}``.
