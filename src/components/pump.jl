"""
    Pump(dP_pump::Real; name) -> System
    Pump(dP_pump::Any; name) -> System
    Pump(; name, ṁ0) -> System

A pump, in one of three modes:

- **Fixed head**, `Pump(dP)` with a number: the outlet pressure is `dP` above the inlet,
  whatever the flow. The loop's resistance sets the flow. `dP` becomes the parameter
  `dP_pump`, which an operating point or `overrides` can change.
- **Head in time**, `Pump(f)` with a function `f(t)`, such as a coastdown: the same, with the
  head `f(t)`. `f` becomes the callable parameter `dP_pump_fn`, which must also be given in the
  operating point of the solve, as `sys.pump.dP_pump_fn => f`. See
  [Drive an input from a function of time](@ref).
- **Fixed flow**, `Pump(; ṁ0)`: the flow is `ṁ0` and the head is whatever it takes. The
  pump states no pressure, so fix one elsewhere in the loop.

# Arguments
- `dP_pump`: the pressure rise [Pa], a number or a function of time
- `ṁ0`: the mass flow [kg/s], for the fixed-flow mode
- `name`: system name, supplied by `@named`

# Ports
- `inlet`, `outlet`: `FlowPort`

# Returns
Uncompiled `System`.
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

function Pump(; name, ṁ0)
    pars = @parameters ṁ0 = ṁ0
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.ṁ ~ ṁ0]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end
