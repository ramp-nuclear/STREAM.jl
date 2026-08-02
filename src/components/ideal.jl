# misc.jl -- Inertia, HeatExchanger, ConstantTemperature components

"""
    Inertia(L_over_A; name) -> System

Concentrated fluid inertia element for transient simulations. Adds `L/A * d(ṁ)/dt`
to the momentum equation.

`L_over_A` is either a number, or a callable `(ṁ) -> L/A` for an inertia that depends on
the flow itself. See [`bilinear_inertia`](@ref) for the standard flow-dependent form. A
callable is traced symbolically, so build it out of arithmetic and `ifelse` rather than a
Julia `if`.

Note: Channel, ChannelAndContacts, and ChannelHeatFlux carry their own distributed
inertia via a momentum ODE `(L/A)*D(ṁ)`. Use standalone Inertia only for concentrated
inertia effects (fittings, sudden area changes, valves, piping outside channels). When
placed in series with a Channel, both momentum ODEs contribute additively through MTK
network topology -- correct physics (distributed + concentrated).

# Arguments
- `L_over_A`: length-to-area ratio [1/m], a number or a callable `(ṁ) -> L/A`
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Inertia(L_over_A::Real; name)
    pars = @parameters L_over_A = L_over_A
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.p - outlet.p ~ L_over_A * D(inlet.ṁ)]   # ODE pressure eq
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

function Inertia(L_over_A; name)
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    vars = @variables L_eff(t)
    eqs = Equation[
        L_eff ~ L_over_A(inlet.ṁ),
        inlet.p - outlet.p ~ L_eff * D(inlet.ṁ),
    ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars=vars)
end

"""
    bilinear_inertia(L0, ṁ0) -> (ṁ) -> L/A

Flow-dependent inertia that falls off linearly below a knee, for [`Inertia`](@ref):

    L = L0 * (ṁ/ṁ0)   for |ṁ| < ṁ0
    L = L0                  otherwise

It models a branch that is only partly filled at low flow, so the accelerating column is
shorter than the pipe. `ifelse` keeps the switch a symbolic branch the solver takes per step,
and the magnitude of the flow is what selects it, so a reversal is handled the same as
forward flow.

# Arguments
- `L0`: the inertia constant above the knee [1/m]
- `ṁ0`: the knee mass flow rate [kg/s]

# Returns
A closure `(ṁ) -> L/A`.
"""
function bilinear_inertia(L0, ṁ0)
    return (m) -> ifelse(abs(m) < ṁ0, L0 * abs(m) / ṁ0, L0)
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
