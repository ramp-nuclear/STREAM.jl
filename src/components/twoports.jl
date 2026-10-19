"""
    HydraulicTwoPort(; name) -> System

Shared shell for a hydraulic two-port component: one `inlet` and one `outlet`
[`FlowPort`](@ref), with mass conservation and temperature pass-through, so each component
only has to state its own law. The shell names the two quantities a law relates: `Δp`, the
pressure rise `outlet.p - inlet.p`, as Python STREAM's `dp_out`, and `ṁ`, the flow in at the
inlet. A component `extend`s it:

```julia
function Resistor(R; name)
    two = HydraulicTwoPort(; name)
    @unpack Δp, ṁ = two
    @parameters R = R
    return extend(System([Δp ~ -R * ṁ], t; name), two)
end
```

Every flow carries a guess, the inlet's positive and the outlet's negative, so a steady solve
starts the component flowing forward whichever of its equal flows `mtkcompile` keeps.

A **two-port component** takes flow in at one port and passes it out at one other, holds no
fluid, and adds no heat. [`Pump`](@ref), [`Flapper`](@ref), [`Resistor`](@ref),
[`FrictionResistor`](@ref), [`VolumetricFlowResistor`](@ref), [`LocalPressureDrop`](@ref),
[`Gravity`](@ref) and [`Inertia`](@ref) are built on it. Channels are not two-ports: they hold
fluid and exchange heat, and state their own energy balance. [`inseries`](@ref) and
[`inparallel`](@ref) accept either, needing only an `inlet` and an `outlet`.

The component's law is usually one equation for `Δp`. Besides defining `Δp` and `ṁ`, the
shell holds three more:

```julia
inlet.ṁ + outlet.ṁ ~ 0        # what goes in comes out
outlet.T ~ instream(inlet.T)  # forward flow: outlet carries the inlet stream
inlet.T ~ instream(outlet.T)  # reversed flow: inlet carries the outlet stream
```

# On `instream`

`T` on a [`FlowPort`](@ref) is declared `[connect = Stream]`, making it a *stream variable*:
carried along by the flow rather than equalised across a connection. `instream(inlet.T)` is the
temperature of the fluid arriving at `inlet` from whatever is connected there, mixed if several
branches feed it. Plain `inlet.T` is the opposite direction, the temperature this component
sends back out through that port. The two equations above therefore say that whatever arrives at
one port leaves at the other, once per flow direction.

`outlet.T ~ inlet.T` is not equivalent: it relates the two outgoing values and leaves the
incoming ones unconstrained.

Stream connectors come from Modelica. The reference for the semantics is Franke et al., "Stream
Connectors: An Extension of Modelica for Device-Oriented Modeling of Convective Transport
Phenomena", Modelica Conference 2009.

# Arguments
- `name`: the component's name, the same one it builds its own `System` under

# Returns
An uncompiled `System` holding `inlet`, `outlet`, `Δp` and `ṁ`, to `extend`.
"""
function HydraulicTwoPort(; name)
    @named inlet = FlowPort()
    @named outlet = FlowPort(; ṁ_guess=-FLOW_GUESS)
    @variables Δp(t) [guess = 0.0] ṁ(t) [guess = FLOW_GUESS]
    eqs = [
        Δp ~ outlet.p - inlet.p,
        ṁ ~ inlet.ṁ,
        inlet.ṁ + outlet.ṁ ~ 0,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t; name), inlet, outlet)
end
