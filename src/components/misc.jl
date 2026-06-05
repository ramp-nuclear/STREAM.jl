# misc.jl — Inertia, HeatExchanger, ConstantTemperature components for STREAM.jl

"""
    Inertia(L_over_A; name) -> System

Concentrated fluid inertia element for transient simulations. Adds `L/A * d(mdot)/dt`
to the momentum equation.

Note: Channel, ChannelAndContacts, and ChannelHeatFlux now carry their own distributed
inertia via a momentum ODE `(L/A)*D(mdot)`. Use standalone Inertia only for concentrated
inertia effects (fittings, sudden area changes, valves, piping outside channels). When
placed in series with a Channel, both momentum ODEs contribute additively through MTK
network topology -- correct physics (distributed + concentrated).

# Arguments
- `L_over_A`: length-to-area ratio [1/m]
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function Inertia(L_over_A; name)
    pars = @parameters L_over_A = L_over_A
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ L_over_A * D(port_in.mdot),   # ODE pressure eq
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    HeatExchanger(T_bc; name) -> System

Ideal heat exchanger that resets fluid temperature to a fixed boundary condition.

# Arguments
- `T_bc`: boundary condition temperature [K]
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function HeatExchanger(T_bc; name)
    pars = @parameters T_bc = T_bc
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ 0,
        port_out.T ~ T_bc,
        port_in.T ~ T_bc,
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    ConstantTemperature(T; name) -> System

Constant-temperature thermal boundary condition.

# Arguments
- `T`: fixed surface temperature [K]
- `name`: system name (Symbol)

# Ports
- `thermal` -- `ThermalPort` (single port, used as a wall BC)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function ConstantTemperature(T; name)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    return compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
