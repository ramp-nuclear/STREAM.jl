# misc.jl -- Inertia, HeatExchanger, ConstantTemperature components

"""
    Inertia(L_over_A; name) -> System

Concentrated fluid inertia element for transient simulations. Adds `L/A * d(ṁ)/dt`
to the momentum equation.

Note: Channel, ChannelAndContacts, and ChannelHeatFlux now carry their own distributed
inertia via a momentum ODE `(L/A)*D(ṁ)`. Use standalone Inertia only for concentrated
inertia effects (fittings, sudden area changes, valves, piping outside channels). When
placed in series with a Channel, both momentum ODEs contribute additively through MTK
network topology -- correct physics (distributed + concentrated).

# Arguments
- `L_over_A`: length-to-area ratio [1/m]
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)


"""
function Inertia(L_over_A; name)
    pars = @parameters L_over_A = L_over_A
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.p - outlet.p ~ L_over_A * D(inlet.ṁ)]   # ODE pressure eq
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    HeatExchanger(T_bc; name) -> System

Ideal heat exchanger that resets fluid temperature to a fixed boundary condition.

# Arguments
- `T_bc`: boundary condition temperature [°C]
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)


"""
function HeatExchanger(T_bc; name)
    pars = @parameters T_bc = T_bc
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        inlet.ṁ + outlet.ṁ ~ 0,
        inlet.p - outlet.p ~ 0,
        outlet.T ~ T_bc,
        inlet.T ~ T_bc,
    ]
    return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end

"""
    ConstantTemperature(T; name) -> System

Constant-temperature thermal boundary condition.

# Arguments
- `T`: fixed surface temperature [°C]
- `name`: system name (Symbol)

# Ports
- `thermal` -- `ThermalPort` (single port, used as a wall BC)
"""
function ConstantTemperature(T; name)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    return compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
