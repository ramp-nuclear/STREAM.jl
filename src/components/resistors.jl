# resistors.jl — Friction, Gravity, Resistor components for STREAM.jl

"""
    Friction(; name, L, D, A) -> ODESystem

Frictional pressure drop element using Darcy-Weisbach correlation.

# Arguments
- `name`: system name (Symbol)
- `L`: pipe length [m]
- `D`: hydraulic diameter [m]
- `A`: flow area [m^2]

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Friction(; name, L, D, A)
    pars = @parameters begin
        L = L
        D_h = D
        A = A
    end
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        Re ~ abs(port_in.mdot) * D / (A * mu_water(T_in)),
        f ~ 0.3164 * Re ^ (-0.25),
        port_in.P - port_out.P ~ f * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(
            T_in
        ) * A ^ 2)) * (L / D),
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
end

"""
    Gravity(H; name) -> ODESystem

Hydrostatic pressure change for a vertical elevation change.

# Arguments
- `H`: elevation change [m], positive = upward
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Gravity(H; name)
    pars = @parameters H = H
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    Resistor(R; name) -> ODESystem

Generic flow resistance with a fixed resistance coefficient.

# Arguments
- `R`: resistance coefficient [Pa/(kg/s)]
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Resistor(R; name)
    pars = @parameters R = R
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ R * port_in.mdot,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
