# pump.jl — Pump component for STREAM.jl

"""
    Pump(; name, dP_pump=nothing, mdot0=nothing) -> ODESystem

Fixed-pressure-drop or fixed-mass-flow pump. Exactly one of `dP_pump` or `mdot0` must be
provided; errors if both or neither kwarg is provided.

# Arguments
- `name`: system name (Symbol)
- `dP_pump`: fixed pressure rise [Pa], or `nothing`
- `mdot0`: fixed mass flow rate [kg/s], or `nothing`

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Pump(; name, dP_pump=nothing, mdot0=nothing)
    if dP_pump !== nothing && mdot0 === nothing
        # Fixed-pressure mode: pressure rise is a parameter; mdot determined by loop resistance
        pars = @parameters dP_pump = dP_pump
        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        eqs = Equation[
            port_in.mdot + port_out.mdot ~ 0,
            port_out.P - port_in.P ~ dP_pump,
            port_out.T ~ instream(port_in.T),
            port_in.T  ~ instream(port_out.T),
        ]
        compose(System(eqs, t, [], pars; name=name), port_in, port_out)
    elseif mdot0 !== nothing && dP_pump === nothing
        # Fixed-flow mode: mass flow is a parameter; no pressure equation (caller provides anchor)
        pars = @parameters mdot0 = mdot0
        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        eqs = Equation[
            port_in.mdot + port_out.mdot ~ 0,
            port_in.mdot ~ mdot0,
            port_out.T ~ instream(port_in.T),
            port_in.T  ~ instream(port_out.T),
        ]
        compose(System(eqs, t, [], pars; name=name), port_in, port_out)
    else
        error("Pump: provide exactly one of `dP_pump` or `mdot0`")
    end
end
