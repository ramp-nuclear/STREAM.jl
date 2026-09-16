"""
    Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0, liquid=H2O) -> System

Flapper (passive check valve). While closed it admits **no flow** (`ṁ = 0`); once open it
is a quadratic resistor `ΔP = f·ṁ·|ṁ| / (2·ρ·area²)`. How far it is open is a
[`StateSchedule`](@ref): the valve reads which state its machine is in and how long it has
been there, exactly as a rod bank reads its own. In the `open_state` the flow ramps in through
`xi = r(open_rate·(t − t_state))`, the C1 Hermite cubic `−2x³ + 3x²` rising 0→1, so
`ṁ = xi · ṁ_open`; in any other state `xi` is zero and the valve is shut.

The opening itself is a [`StateMachine`](@ref) transition, which [`flapper_opens`](@ref)
writes for you: the valve opens when the flow you name falls through `open_at_current`.

This mirrors Python STREAM's `Flapper` (closed ⇒ `ṁ` 0; open ⇒ quadratic local-pressure
resistor relaxed in from `t_open`). Two deliberate conventions:

  - **Relaxation.** STREAM.jl always uses the continuously-differentiable ramp `−2x³ + 3x²`.
    Python *defaults* to `legacy_relaxation` and only opts into this shape per-call, so the
    ramp *shape* differs for cases that take Python's default; the open/closed binary and the
    latch time — what the integration tests assert — do not.
  - **Open-state sign.** `ṁ_open = sign(P_in − P_out)·√(|ΔP|·2ρA²/f)`. Python writes
    `−sign(dp)·√(…)` against its own `dp = P_out − P_in`; the two sign flips cancel, so the two
    formulas are numerically identical (verified across both flow directions).

A flapper built with its own fresh machine never opens, since nothing transitions it. To
pre-open the valve at a known time (Python's `open(t0)`), hand it a machine that starts open:
`StateMachine(; initial_state=:OPEN, initial_time=t0)`. A machine back in `:CLOSED` is
Python's `close()`.

Because a closed flapper carries no flow, it is meant to sit in **parallel** with another
branch (a bypass that carries flow while the valve is shut); a closed flapper placed in series
would block the whole loop.

Give the machine the opening edge, naming the flow the valve watches, and hand its events to
the solver:
```julia
machine = StateMachine(; initial_state=:CLOSED)
@named flap = Flapper(; machine=machine)
push!(machine, flapper_opens(flap, bypass.inlet.ṁ))
sol = solve_transient(ssys, op, times; callbacks=machine_callbacks(ssys, machine))
```

# Arguments
- `name`: system name (Symbol), injected by `@named` macro
- `open_at_current`: the watched flow at or below which the valve opens [kg/s] (default
  0.01). [`flapper_opens`](@ref) reads it off the component, so only the flow is named at the
  call site, and it stays a parameter, so `remake` can move the setpoint without a rebuild.
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: relaxation rate [1/s]; the open ramp completes after `1/open_rate` s (default 1.0)
- `machine`: the [`StateMachine`](@ref) the valve follows (default a fresh one in `:CLOSED`)
- `open_state`: the state in which the valve is open (default `:OPEN`)
- `opening`: a callable `(t) -> xi` replacing the default ramp outright, for a valve whose
  profile is not a Hermite ramp
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref), supplying the density at
  the inlet stream temperature

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)
"""
function Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0,
                 machine::StateMachine=StateMachine(; initial_state=:CLOSED),
                 open_state=:OPEN, opening=nothing, liquid::AbstractLiquid=H2O)
    # The C1 Hermite ramp, in the state that opens the valve and nowhere else.
    ramp(state, t_state, t) =
        state === open_state ?
        (x = clamp(open_rate * (t - t_state), 0.0, 1.0); x * x * (3 - 2x)) : 0.0
    schedule = opening === nothing ? StateSchedule(ramp; machine=machine) : opening
    FType = typeof(schedule)

    pars = @parameters begin
        open_at_current = open_at_current
        f = f
        area = area
    end
    open_pars = @parameters (opening::FType)(..) = schedule

    vars = @variables xi(t)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    rho = ρ(liquid, instream(inlet.T))
    dp = inlet.p - outlet.p
    # Open-state flow: invert ΔP = f·ṁ·|ṁ|/(2ρA²) ⇒ ṁ = sign(dp)·sqrt(|dp|·2ρA²/f).
    ṁ_open = sign(dp) * sqrt(abs(dp) * 2 * rho * area^2 / f)

    # The opening is read from the schedule rather than from `xi`, so the branch below turns
    # on time and a parameter, as it did when the valve latched a `T_open`. Branching on the
    # unknown instead leaves the residual non-smooth in it, and a steady solve stalls.
    open_fraction = open_pars[1](t)

    eqs = Equation[
        xi ~ open_fraction,
        # A shut valve must not reach the square root, whose slope is unbounded at dp = 0.
        ifelse(open_fraction <= 0.0, inlet.ṁ, inlet.ṁ - open_fraction * ṁ_open) ~ 0,
    ]

    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars=[pars; open_pars])
end

"""
    flapper_opens(flapper, flow; from=:CLOSED, to=:OPEN) -> edge

The [`StateMachine`](@ref) edge that opens `flapper`: `flow` falling through the valve's own
`open_at_current`. Push it onto the machine the valve follows.

The setpoint is read off the component, so only the flow is named here, and the crossing is
root-found like any other transition. That is what makes the opening
time exact: a closed flapper carries no flow and is dynamically decoupled from the flow it
watches, so an
adaptive solver places no steps near the crossing and a per-step check can sail straight past
it. It also works whether the flow resolves to a differential state, on a branch with
inertia, or to a purely algebraic quantity on a quasi-static one.

# Arguments
- `flapper`: a Flapper subsystem, before compilation or after
- `flow`: the mass flow the valve watches, any flow variable of the system

# Keywords
- `from`: the state the valve leaves (default `:CLOSED`)
- `to`: the state in which it is open (default `:OPEN`), which is the valve's `open_state`

# Returns
An edge, `(from => to, condition)`, for `push!(machine, edge)` or `StateMachine(edge)`.

# Example
```julia
machine = StateMachine(; initial_state=:CLOSED)
@named flap = Flapper(; machine=machine)
push!(machine, flapper_opens(flap, bypass.inlet.ṁ))
```
"""
flapper_opens(flapper, flow; from=:CLOSED, to=:OPEN) =
    (from => to, flow < flapper.open_at_current)
