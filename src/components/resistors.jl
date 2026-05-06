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
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

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
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        Re ~ abs(inlet.mdot) * D / (A * mu_water(T_in)),
        f ~ 0.3164 * Re ^ (-0.25),
        inlet.P - outlet.P ~ f * (inlet.mdot * abs(inlet.mdot) / (2 * rho_water(
            T_in
        ) * A ^ 2)) * (L / D),
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t, vars, pars; name=name), inlet, outlet)
end

"""
    Gravity(H; name) -> ODESystem

Hydrostatic pressure change for a vertical elevation change.

# Arguments
- `H`: elevation change [m], positive = upward
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Gravity(H; name)
    pars = @parameters H = H
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        inlet.P - outlet.P ~ rho_water(T_in) * 9.80665 * H,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end

"""
    Resistor(R; name) -> ODESystem

Generic flow resistance with a fixed resistance coefficient.

# Arguments
- `R`: resistance coefficient [Pa/(kg/s)]
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Resistor(R; name)
    pars = @parameters R = R
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        inlet.P - outlet.P ~ R * inlet.mdot,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end
