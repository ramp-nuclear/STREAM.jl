# pump.jl — Pump component for STREAM.jl

"""
    Pump(dP_pump::Real; name) -> System
    Pump(dP_pump::Any; name) -> System
    Pump(; name, mdot0) -> System

Fixed-pressure-drop (scalar or callable) or fixed-mass-flow pump. Three dispatch methods:

1. `Pump(dP_pump::Real; name)` — scalar fixed-pressure mode. `dP_pump` is a constant
   pressure rise parameter [Pa]. Mass flow is determined by the loop resistance.

2. `Pump(dP_pump::Any; name)` — callable fixed-pressure mode. `dP_pump` is any callable
   `f(t) -> Float64` (anonymous function, closure, DataInterpolations interpolant, etc.).
   The callable is stored as an MTK callable parameter `dP_pump_fn`. The caller must pass
   `ssys.pump.dP_pump_fn => f` in the `op` dict to `ODEProblem` / `solve_transient`.

3. `Pump(; name, mdot0)` — fixed-flow mode. `mdot0` is a fixed mass flow rate parameter
   [kg/s]. No pressure equation is added; the caller must anchor pressure elsewhere.

# Arguments
**Scalar mode (method 1):**
- `dP_pump::Real`: fixed pressure rise [Pa]
- `name`: system name (Symbol)

**Callable mode (method 2):**
- `dP_pump::Any`: callable `f(t) -> Float64` giving pump pressure rise [Pa]
- `name`: system name (Symbol)
- The callable is stored as MTK parameter `dP_pump_fn`. Pass it in `op`:
  `ssys.pump.dP_pump_fn => f` when constructing `ODEProblem` or calling `solve_transient`.

**Fixed-flow mode (method 3):**
- `name`: system name (Symbol)
- `mdot0`: fixed mass flow rate [kg/s]

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function Pump(dP_pump::Real; name)
    pars = @parameters dP_pump = dP_pump
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_out.P - port_in.P ~ dP_pump,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

function Pump(dP_pump::Any; name)
    FType = typeof(dP_pump)
    pars = @parameters (dP_pump_fn::FType)(..)
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_out.P - port_in.P ~ dP_pump_fn(t),
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

function Pump(; name, mdot0)
    pars = @parameters mdot0 = mdot0
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.mdot ~ mdot0,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
