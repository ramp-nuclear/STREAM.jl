# flapper.jl -- Flapper check-valve component

"""
    Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0, fluid=Water()) -> System

Flapper (passive check valve). Closed, it admits **no flow** (`mdot = 0`); once open it is
a quadratic resistor `ΔP = f·mdot·|mdot| / (2·ρ·area²)`. The valve opens when the wired
reference flow `ref_mdot` drops to `open_at_current` (detected externally by
`flapper_callback`, which latches `T_open` to the crossing time). After `T_open` the flow
ramps in gradually through the relaxation factor `xi = r(open_rate·(t − T_open))`, a C1
Hermite cubic (`-2x³ + 3x²`) rising 0→1, so `mdot = xi · mdot_open`. This mirrors Python
STREAM's `Flapper` (closed ⇒ mdot 0, open ⇒ quadratic with an `open_rate` relaxation).

Because a closed flapper carries no flow, it is meant to sit in **parallel** with another
branch (the bypass that carries flow while the valve is shut); a closed flapper placed in
series would block the whole loop.

`T_open` uses a large finite sentinel (`1e30`), not `Inf` — `Inf` in the state vector makes
Rodas5P report instability; `1e30` keeps `t ≤ T_open` true (valve closed) until the event.

`ref_mdot` has **no equation inside the component**. The caller wires it during composition:
```julia
flapper.ref_mdot ~ pump.port_in.mdot
```
To detect the opening event, use `flapper_callback(ssys, monitored; threshold=open_at_current)`
and pass the resulting `ContinuousCallback` to `solve_transient(...; callbacks=cb)`.

# Arguments
- `name`: system name (Symbol), injected by `@named` macro
- `open_at_current`: reference flow at/below which the valve opens [kg/s] (default 0.01).
  Pass this as the `flapper_callback` threshold.
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: relaxation rate [1/s]; the open ramp completes after `1/open_rate` s (default 1.0)
- `fluid`: coolant property set (`AbstractFluid`), default `Water()` — supplies the density
  at the inlet stream temperature

# Ports
- `port_in`, `port_out`: `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. `T_open(t)` is set by an external `ContinuousCallback` (see
`flapper_callback`), not an MTK equation, and `ref_mdot` has no in-component equation, so a
standalone Flapper is structurally underdetermined — call
`mtkcompile(sys; fully_determined=false)`, or compose it into a system where `ref_mdot` is wired.
"""
function Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0,
                 fluid::AbstractFluid=Water())
    pars = @parameters begin
        open_at_current = open_at_current
        f = f
        area = area
        open_rate = open_rate
    end

    vars = @variables T_open(t) = 1e30 xi(t) ref_mdot(t)

    @named port_in = FlowPort()
    @named port_out = FlowPort()

    rho = density(fluid, instream(port_in.T))
    dp = port_in.P - port_out.P
    x = open_rate * (t - T_open)
    relax = ifelse(x <= 0.0, 0.0, ifelse(x >= 1.0, 1.0, -2 * x^3 + 3 * x^2))
    # Open-state flow: invert ΔP = f·mdot·|mdot|/(2ρA²) ⇒ mdot = sign(dp)·sqrt(|dp|·2ρA²/f).
    mdot_open = sign(dp) * sqrt(abs(dp) * 2 * rho * area^2 / f)

    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        D(T_open) ~ 0,
        xi ~ relax,
        # Closed (t ≤ T_open): mdot = 0. Open: mdot = xi · mdot_open (quadratic, ramped in).
        ifelse(t <= T_open, port_in.mdot, port_in.mdot - relax * mdot_open) ~ 0,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
        # ref_mdot has no equation here — user wires it during composition
    ]

    return compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
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
function flapper_callback(ssys, monitored_sym; threshold=0.01)
    T_open_idx = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
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
        affect!,    # downward crossing: latch T_open = t_now
    )
end
