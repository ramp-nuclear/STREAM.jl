# pump.jl -- Pump component

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
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Pump(dP_pump::Real; name)
    pars = @parameters dP_pump = dP_pump
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[outlet.p - inlet.p ~ dP_pump]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

function Pump(dP_pump::Any; name)
    FType = typeof(dP_pump)
    pars = @parameters (dP_pump_fn::FType)(..)
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[outlet.p - inlet.p ~ dP_pump_fn(t)]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

function Pump(; name, mdot0)
    pars = @parameters mdot0 = mdot0
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.ṁ ~ mdot0]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end
