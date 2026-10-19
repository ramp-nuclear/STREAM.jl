"""
    HydraulicTwoPort(; name) -> System

Shared shell for a hydraulic two-port component: one `inlet` and one `outlet`
[`FlowPort`](@ref), with mass conservation and temperature pass-through, so each component
only has to state its own law. The shell observes the two quantities a law relates: `Δp`, the
pressure rise `outlet.p - inlet.p`, as Python STREAM's `dp_out`, and `ṁ`, the flow in at the
inlet. A component states its relation between them and hands it to [`flow_relation`](@ref):

```julia
function Resistor(R; name)
    two = HydraulicTwoPort(; name)
    @unpack Δp, ṁ = two
    @parameters R = R
    return flow_relation(two, [Δp ~ -R * ṁ])
end
```

`sol[ssys.r.Δp]` then reads the pressure change of any two-port. The outlet's flow guess is
negative, the inlet's positive, so a steady solve starts the component flowing forward.

A **two-port component** takes flow in at one port and passes it out at one other, holds no
fluid, and adds no heat. [`Pump`](@ref), [`Flapper`](@ref), [`Resistor`](@ref),
[`FrictionResistor`](@ref), [`VolumetricFlowResistor`](@ref), [`LocalPressureDrop`](@ref),
[`Gravity`](@ref) and [`Inertia`](@ref) are built on it. Channels are not two-ports: they hold
fluid and exchange heat, and state their own energy balance.
[`inseries`](@ref STREAM.Assemblies.Connect.inseries) and
[`inparallel`](@ref STREAM.Assemblies.Connect.inparallel) accept either, needing only an
`inlet` and an `outlet`.

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
An uncompiled `System` holding `inlet` and `outlet` and observing `Δp` and `ṁ`.
"""
function HydraulicTwoPort(; name)
    @named inlet = FlowPort()
    @named outlet = FlowPort(; ṁ_guess=-FLOW_GUESS)
    @variables Δp(t) ṁ(t)
    eqs = [inlet.ṁ + outlet.ṁ ~ 0, outlet.T ~ instream(inlet.T), inlet.T ~ instream(outlet.T)]
    obs = [Δp ~ outlet.p - inlet.p, ṁ ~ inlet.ṁ]
    return compose(System(eqs, t, [Δp, ṁ], []; observed=obs, name), inlet, outlet)
end

"""
    flow_relation(two, eqs) -> System

A two-port component: the shell `two` extended with `eqs`, the component's relation between
the pressure rise `Δp` and the flow `ṁ` the shell observes.

`Δp` and `ṁ` are replaced in `eqs` by the port expressions they stand for, so the relation
adds no unknowns and the component compiles as if written on its ports.

# Arguments
- `two`: a [`HydraulicTwoPort`](@ref), built under the component's name
- `eqs`: the component's equations, in `Δp`, `ṁ`, the ports, and its own parameters and
  variables

# Returns
An uncompiled `System`, the component, under the name `two` was built with.

# Example
```julia
function Resistor(R; name)
    two = HydraulicTwoPort(; name)
    @unpack Δp, ṁ = two
    @parameters R = R
    return flow_relation(two, [Δp ~ -R * ṁ])
end
```
"""
function flow_relation(two, eqs)
    ports = Dict(eq.lhs => eq.rhs for eq in observed(two))
    # substitute does not reach inside a derivative, so D(ṁ) is mapped in its own right.
    merge!(ports, Dict(D(k) => D(v) for (k, v) in ports))
    return extend(System(substitute(eqs, ports), t; name=nameof(two)), two)
end
