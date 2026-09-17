"""
    Flapper(; name, f=1.0, area=1.0, open_rate=1.0, machine, open_state=:OPEN,
            opening=nothing, liquid=H2O) -> System

Passive check valve. Shut it admits no flow; open it is a quadratic resistor
`ΔP = f·ṁ·|ṁ| / (2·ρ·area²)`.

How far it is open is a [`StateSchedule`](@ref) of its machine. In `open_state` the flow ramps
in as `xi = r(open_rate·(t − t_state))`, the C1 Hermite cubic `−2x³ + 3x²` rising 0 to 1, so
`ṁ = xi·ṁ_open`; in any other state `xi` is zero. What opens the valve is a transition, so the
valve holds no setpoint of its own:

```julia
machine = StateMachine(; initial_state=:CLOSED)
@named flap = Flapper(; machine=machine)
push!(machine, (:CLOSED => :OPEN, bypass.inlet.ṁ < 0.01))
sol = solve_transient(ssys, op, times; callbacks=machine_callbacks(ssys, machine))
```

Write the threshold against a parameter when it should move under `remake`; a literal is
compiled into the condition.

A valve whose machine never transitions never opens. One that starts open,
`StateMachine(; initial_state=:OPEN, initial_time=t0)`, is Python's `open(t0)`, and a machine
back in `:CLOSED` is its `close()`.

A shut valve carries no flow, so it belongs in **parallel** with a branch that carries flow
meanwhile. In series it would block the loop.

Two deliberate differences from Python STREAM's `Flapper`:

  - **Relaxation.** We always use the differentiable ramp `−2x³ + 3x²`, where Python defaults
    to `legacy_relaxation` and opts into this shape per call. The ramp shape differs for cases
    taking Python's default; the open/closed binary and the opening time do not.
  - **Open-state sign.** `ṁ_open = sign(P_in − P_out)·√(|ΔP|·2ρA²/f)` against Python's
    `−sign(dp)·√(…)` with `dp = P_out − P_in`. The two flips cancel, checked in both flow
    directions.

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: relaxation rate [1/s]; the ramp completes after `1/open_rate` s (default 1.0)
- `machine`: the [`StateMachine`](@ref) the valve follows (default a fresh one in `:CLOSED`)
- `open_state`: the state in which the valve is open (default `:OPEN`)
- `opening`: a callable `(t) -> xi` replacing the ramp, for a profile that is not Hermite
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref), read for the density at
  the inlet stream temperature

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)
"""
function Flapper(; name, f=1.0, area=1.0, open_rate=1.0,
                 machine::StateMachine=StateMachine(; initial_state=:CLOSED),
                 open_state=:OPEN, opening=nothing, liquid::AbstractLiquid=H2O)
    ramp(state, t_state, t) =
        state === open_state ?
        (x = clamp(open_rate * (t - t_state), 0.0, 1.0); x * x * (3 - 2x)) : 0.0
    schedule = opening === nothing ? StateSchedule(ramp; machine=machine) : opening
    FType = typeof(schedule)

    pars = @parameters begin
        f = f
        area = area
    end
    open_pars = @parameters (opening::FType)(..) = schedule
    vars = @variables xi(t)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    rho = ρ(liquid, instream(inlet.T))
    dp = inlet.p - outlet.p
    # ΔP = f·ṁ·|ṁ|/(2ρA²), inverted for the flow an open valve passes.
    ṁ_open = sign(dp) * sqrt(abs(dp) * 2 * rho * area^2 / f)
    # Taken from the schedule rather than from `xi`: branching on the unknown leaves the
    # residual non-smooth in it, and a steady solve stalls.
    open_fraction = open_pars[1](t)

    eqs = Equation[
        xi ~ open_fraction,
        # A shut valve must not reach the square root, whose slope is unbounded at dp = 0.
        ifelse(open_fraction <= 0.0, inlet.ṁ, inlet.ṁ - open_fraction * ṁ_open) ~ 0,
    ]

    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars=[pars; open_pars])
end
