# flapper.jl — Flapper check-valve component for STREAM.jl

"""
    Flapper(; name, dt=5.0, R_closed=1e8, R_open=100.0) -> System

Flapper check-valve component. When the wired reference mass flow `ref_mdot` drops
below a threshold (monitored externally via `flapper_callback`), the latching state
`T_open` is set to the current solver time. After that, the valve resistance ramps
smoothly from `R_closed` to `R_open` over `dt` seconds using a C1 Hermite cubic
(`3*xi^2 - 2*xi^3`).

`T_open` uses a large finite sentinel value (`1e30`) rather than `Inf` as its initial
condition. `Inf` in the solver state vector causes Rodas5P to report instability. With
`T_open = 1e30`, the ramp expression `clamp((t - 1e30)/dt, 0, 1)` evaluates to 0 for all
practical `t` values, keeping the valve closed before the event fires.

`ref_mdot` has **no equation inside the component**. The user must wire it externally
during system composition:
```julia
flapper.ref_mdot ~ pump.port_in.mdot
```
`mtkcompile` will error if this equation is omitted (under-determined system).

To detect the closing event, use `flapper_callback(ssys; threshold)` and pass the
resulting `ContinuousCallback` to `solve_transient(...; callbacks=cb)`.

# Arguments
- `name`: system name (Symbol), injected by `@named` macro
- `dt`: ramp duration [s]; time for resistance to transition from closed to open (default: 5.0)
- `R_closed`: closed-state hydraulic resistance [Pa*s/kg] (default: 1e8)
- `R_open`: open-state hydraulic resistance [Pa*s/kg] (default: 100.0)

# Ports
- `port_in`: `FlowPort` — inlet (pressure, mass flow, temperature)
- `port_out`: `FlowPort` — outlet (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys; fully_determined=false)` before solving a
standalone Flapper (since `ref_mdot` is underdetermined alone), or compose it into a full
system where `ref_mdot` is wired.
"""
function Flapper(; name, dt = 5.0, R_closed = 1e8, R_open = 100.0)
    pars = @parameters begin
        dt       = dt
        R_closed = R_closed
        R_open   = R_open
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
        # ref_mdot has no equation here — user wires it during composition
    ]

    compose(System(eqs, t, vars, pars; name = name), port_in, port_out)
end

"""
    flapper_callback(ssys, monitored_sym; threshold=0.01) -> ContinuousCallback

Return a `DifferentialEquations.ContinuousCallback` that fires when `monitored_sym`
drops below `threshold` (downward zero-crossing). On firing, latches `T_open` to the
current solver time, initiating the resistance ramp from `R_closed` to `R_open` over
`dt` seconds.

`monitored_sym` must be the symbolic state variable whose value triggers the event —
typically the variable wired to `flapper.ref_mdot` in the composed system. Accepting
the symbol explicitly (rather than reading it from `ssys.flapper.ref_mdot`) avoids an
issue where `mtkcompile` substitutes `ref_mdot` out as an observed variable: using
`integrator[observed_sym]` in the callback condition reads `integrator.u` (last accepted
step), causing both the step-start and step-end sign evaluations to return the same value
and preventing zero-crossing detection. Using `u[variable_index(...)]` instead reads the
interpolated state correctly.

Upward crossings (flow recovers above threshold) are ignored — the valve stays latched
open once the event fires.

# Arguments
- `ssys`: compiled MTK system from `mtkcompile`. Must contain a Flapper subsystem
  accessible as `ssys.flapper`.
- `monitored_sym`: symbolic state variable to monitor (e.g. `ssys.ine.port_in.mdot`).
  Must be a state variable (present in the ODE state vector). If algebraic (e.g. wired
  to a pump port without inertia), `variable_index` returns `nothing` and the callback
  falls back to `integrator[sym]` — acceptable for purely quasi-static loops where the
  value is consistent across step boundaries and the event never needs to fire precisely.
- `threshold` (kwarg): mass flow threshold [kg/s] below which the event fires (default: 0.01).

# Returns
`ContinuousCallback` — pass to `solve_transient(...; callbacks=cb)`.

# Example
```julia
cb  = flapper_callback(ssys, ssys.ine.port_in.mdot)                      # default threshold
cb2 = flapper_callback(ssys, ssys.ine.port_in.mdot; threshold=1e-4)      # custom threshold
sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```
"""
function flapper_callback(ssys, monitored_sym; threshold = 0.01)
    T_open_idx    = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
    monitored_idx = ModelingToolkit.variable_index(ssys, monitored_sym)

    # Use u[idx] (the interpolated state passed to the condition) for state variables.
    # Fall back to integrator[sym] only for algebraic variables where the value is
    # consistent between step boundaries and exact rootfinding is not critical.
    condition = if monitored_idx !== nothing
        (u, t, integrator) -> u[monitored_idx] - threshold
    else
        (u, t, integrator) -> integrator[monitored_sym] - threshold
    end

    # Downward crossing only: latch T_open to current solver time.
    # Upward crossing (nothing): valve stays latched after opening.
    affect! = (integrator) -> (integrator.u[T_open_idx] = integrator.t)

    ContinuousCallback(
        condition,
        nothing,   # upward crossing: ignore (flow recovered — valve stays open)
        affect!    # downward crossing: latch T_open = t_now
    )
end
