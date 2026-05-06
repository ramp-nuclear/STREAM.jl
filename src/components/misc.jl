# misc.jl — Inertia, HeatExchanger, ConstantTemperature components for STREAM.jl

# Inertia (COMP-01): fluid inertia as ODE pressure-drop term
# Equation: inlet.P - outlet.P ~ L_over_A * D(mdot)
# L_over_A = L/A [m/m² = m⁻¹] — user pre-computes from geometry
# No explicit mdot state variable needed — MTK auto-promotes inlet.mdot
# as a differential state because it appears inside Dt(inlet.mdot).
"""
    Inertia(L_over_A; name) -> ODESystem

Concentrated fluid inertia element for transient simulations. Adds `L/A * d(mdot)/dt`
to the momentum equation.

Note: Channel, ChannelAndContacts, and ChannelHeatFlux now carry their own distributed
inertia via a momentum ODE `(L/A)*Dt(mdot)`. Use standalone Inertia only for concentrated
inertia effects (fittings, sudden area changes, valves, piping outside channels). When
placed in series with a Channel, both momentum ODEs contribute additively through MTK
network topology -- correct physics (distributed + concentrated).

# Arguments
- `L_over_A`: length-to-area ratio [1/m]
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Inertia(L_over_A; name)
    Dt = Differential(t)           # same operator used in Channel energy balance
    pars = @parameters L_over_A = L_over_A
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,
        inlet.P - outlet.P ~ L_over_A * Dt(inlet.mdot),   # ODE pressure eq
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end

# HeatExchanger (COMP-02): temperature boundary condition as a public component.
# Injects a fixed outlet temperature T_bc into the downstream stream, breaking
# the circular thermal dependency in closed loops (where instream() would
# otherwise resolve to the previous component's outlet T).
# 4-equation structure: mass conservation, no pressure drop, T_bc outlet, adiabatic inlet.
"""
    HeatExchanger(T_bc; name) -> ODESystem

Ideal heat exchanger that resets fluid temperature to a fixed boundary condition.

# Arguments
- `T_bc`: boundary condition temperature [K]
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function HeatExchanger(T_bc; name)
    pars = @parameters T_bc = T_bc
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        inlet.mdot + outlet.mdot ~ 0,    # mass conservation
        inlet.P - outlet.P ~ 0,     # no pressure drop
        outlet.T ~ T_bc,                   # inject fixed outlet temperature
        inlet.T ~ T_bc,                   # backward stream: also reset to T_bc
    ]
    return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
end

# ConstantTemperature: pins a ThermalPort's temperature to a fixed parameter.
# Used as a thermal boundary condition in tests and simple simulations.
# MTK acausal semantics solve for Q_flow from the connected component's balance.
"""
    ConstantTemperature(T; name) -> ODESystem

Constant-temperature thermal boundary condition.

# Arguments
- `T`: fixed surface temperature [K]
- `name`: system name (Symbol)

# Ports
- `thermal` -- `ThermalPort` (single port, used as a wall BC)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ConstantTemperature(T; name)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
