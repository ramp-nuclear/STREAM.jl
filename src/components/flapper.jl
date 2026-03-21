# flapper.jl — Flapper check-valve component for STREAM.jl

using ModelingToolkit: SymbolicContinuousCallback

"""
    Flapper(; name, dt=5.0, threshold=0.01, R_closed=1e8, R_open=100.0, use_callback=true) -> System

Flapper check-valve component with a continuous event trigger. When the wired reference
mass flow `ref_mdot` drops below `threshold`, the event fires and latches `T_open` to the
current solver time. After that, the valve resistance ramps smoothly from `R_closed` to
`R_open` over `dt` seconds using a C1 Hermite cubic (`3*xi^2 - 2*xi^3`).

`T_open` uses a large finite sentinel value (`1e30`) rather than `Inf` as its initial
condition. `Inf` in the solver state vector causes Rodas5P to report instability. With
`T_open = 1e30`, the ramp expression `clamp((t - 1e30)/dt, 0, 1)` evaluates to 0 for all
practical `t` values, keeping the valve closed before the event fires.

`ref_mdot` has **no equation inside the component**. The user must wire it externally during
system composition:
```julia
flapper.ref_mdot ~ pump.port_in.mdot
```
`mtkcompile` will error if this equation is omitted (under-determined system).

When `use_callback=false`, the `SymbolicContinuousCallback` is omitted from the component.
This is required for parallel (multi-path) topologies where channel momentum inertia terms
`(L/A)*Dt(mdot)` appear in the pressure balance equations that MTK's callback DAE solver
would need to handle — causing an `UnsolvableCallbackError`. In that case, supply an
external `DifferentialEquations.ContinuousCallback` that directly sets `T_open` in the
ODE state vector, and pass it via `solve_transient(...; callbacks=cb)`.

# Arguments
- `name`: system name (Symbol), injected by `@named` macro
- `dt`: ramp duration [s]; time for resistance to transition from closed to open (default: 5.0)
- `threshold`: mass flow threshold [kg/s]; event fires when `ref_mdot` drops below this value (default: 0.01)
- `R_closed`: closed-state hydraulic resistance [Pa·s/kg]; high resistance keeps valve shut (default: 1e8)
- `R_open`: open-state hydraulic resistance [Pa·s/kg]; low resistance after valve opens (default: 100.0)
- `use_callback`: register MTK `SymbolicContinuousCallback` (default: `true`); set to `false`
  for parallel topologies where channel inertia causes `UnsolvableCallbackError`

# Ports
- `port_in`: `FlowPort` — inlet (pressure, mass flow, temperature)
- `port_out`: `FlowPort` — outlet (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys; fully_determined=false)` before solving a
standalone Flapper (since `ref_mdot` is underdetermined alone), or compose it into a full
system where `ref_mdot` is wired.
"""
function Flapper(; name, dt = 5.0, threshold = 0.01, R_closed = 1e8, R_open = 100.0,
                   use_callback = true)
    pars = @parameters begin
        dt        = dt
        threshold = threshold
        R_closed  = R_closed
        R_open    = R_open
    end

    vars = @variables T_open(t) = 1e30 xi(t) ref_mdot(t)

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    D = Differential(t)

    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        D(T_open) ~ 0,
        xi ~ clamp((t - T_open) / dt, 0.0, 1.0),
        port_in.P - port_out.P ~ (R_closed + (R_open - R_closed) * (3 * xi^2 - 2 * xi^3)) * port_in.mdot,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
        # ref_mdot has no equation here -- user wires it during composition
    ]

    if use_callback
        # Continuous event: fires when ref_mdot drops below threshold (downward crossing).
        # affect = nothing  → ignore upward crossing (ref_mdot rises above threshold)
        # affect_neg fires  → downward crossing (ref_mdot drops below threshold); latch T_open
        cb = SymbolicContinuousCallback(
            [ref_mdot - threshold ~ 0],
            nothing;
            affect_neg = [T_open ~ t]
        )
        compose(System(eqs, t, vars, pars; name = name, continuous_events = [cb]), port_in, port_out)
    else
        compose(System(eqs, t, vars, pars; name = name), port_in, port_out)
    end
end
