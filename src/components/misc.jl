# misc.jl — Inertia, HeatExchanger, ConstantTemperature components for STREAM.jl

# Inertia (COMP-01): fluid inertia as ODE pressure-drop term
# Equation: port_in.P - port_out.P ~ L_over_A * D(mdot)
# L_over_A = L/A [m/m² = m⁻¹] — user pre-computes from geometry
# No explicit mdot state variable needed — MTK auto-promotes port_in.mdot
# as a differential state because it appears inside Dt(port_in.mdot).
"""
    Inertia(; name, L_over_A) -> ODESystem

Fluid inertia element for transient simulations. Adds `L/A * d(mdot)/dt` to the momentum equation.

# Arguments
- `name`: system name (Symbol)
- `L_over_A`: length-to-area ratio [1/m]

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Inertia(; name, L_over_A)
    Dt   = Differential(t)           # same operator used in Channel energy balance
    pars = @parameters L_over_A = L_over_A
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ L_over_A * Dt(port_in.mdot),   # ODE pressure eq
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# HeatExchanger (COMP-02): temperature boundary condition as a public component.
# Injects a fixed outlet temperature T_bc into the downstream stream, breaking
# the circular thermal dependency in closed loops (where instream() would
# otherwise resolve to the previous component's outlet T).
# 4-equation structure: mass conservation, no pressure drop, T_bc outlet, adiabatic inlet.
"""
    HeatExchanger(; name, T_bc) -> ODESystem

Ideal heat exchanger that resets fluid temperature to a fixed boundary condition.

# Arguments
- `name`: system name (Symbol)
- `T_bc`: boundary condition temperature [K]

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function HeatExchanger(; name, T_bc)
    pars = @parameters T_bc = T_bc
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,    # mass conservation
        port_in.P   - port_out.P    ~ 0,     # no pressure drop
        port_out.T  ~ T_bc,                   # inject fixed outlet temperature
        port_in.T   ~ instream(port_out.T),   # backward stream (adiabatic)
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# ConstantTemperature: pins a ThermalPort's temperature to a fixed parameter.
# Used as a thermal boundary condition in tests and simple simulations.
# MTK acausal semantics solve for Q_flow from the connected component's balance.
"""
    ConstantTemperature(; name, T) -> ODESystem

Constant-temperature thermal boundary condition.

# Arguments
- `name`: system name (Symbol)
- `T`: fixed surface temperature [K]

# Ports
- `thermal` -- `ThermalPort` (single port, used as a wall BC)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ConstantTemperature(; name, T)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
