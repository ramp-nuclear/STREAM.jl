"""
    HydraulicTwoPort(; name, inlet, outlet, eqs, vars=[], pars=[]) -> System

Shared shell for a hydraulic two-port component: one `inlet` and one `outlet`
[`FlowPort`](@ref), with mass conservation and temperature pass-through supplied here so each
component only has to state its own pressure relation.

A **two-port component** takes flow in at one port and passes it out at one other, holds no
fluid, and adds no heat. [`Pump`](@ref), [`Flapper`](@ref), [`Resistor`](@ref),
[`FrictionResistor`](@ref), [`VolumetricFlowResistor`](@ref), [`LocalPressureDrop`](@ref),
[`Gravity`](@ref) and [`Inertia`](@ref) are built on it. Channels are not two-ports: they hold
fluid and exchange heat, and state their own energy balance. [`inseries`](@ref) and
[`inparallel`](@ref) accept either, needing only an `inlet` and an `outlet`.

`eqs` holds the component's pressure relation, usually one equation of the form
`inlet.p - outlet.p ~ <something>`. This adds three more:

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
- `name`: system name (Symbol, injected by `@named`)
- `inlet`, `outlet`: `FlowPort` connectors, already `@named` by the caller
- `eqs`: the component's own equations, usually a single pressure relation
- `vars`: extra unknowns the component introduces (default none)
- `pars`: parameters the component introduces (default none)

# Returns
An uncompiled `System` with `inlet` and `outlet` composed in.
"""
function HydraulicTwoPort(; name, inlet, outlet, eqs, vars=[], pars=[])
    full_eqs = Equation[
        inlet.ṁ + outlet.ṁ ~ 0,
        eqs...,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(full_eqs, t, vars, pars; name=name), inlet, outlet)
end
