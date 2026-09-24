"""
    Flapper(; name, f=1.0, area=1.0, open_rate=1.0, machine, open_state=:OPEN,
            open_fraction=nothing, liquid=H2O) -> System

Passive check valve. Shut, it passes no flow. Open, it is a quadratic resistor
`ΔP = f·ṁ·|ṁ| / (2·ρ·area²)`, and part way open it passes `xi` times that flow, where `xi` is
the open fraction, 0 shut and 1 fully open.

The valve holds no setpoint. It is open while its [`StateMachine`](@ref) is in `open_state`
and shut otherwise, and transitions on the machine decide when:

```julia
machine = StateMachine(; initial_state=:CLOSED)
@named flap = Flapper(; machine=machine)
push!(machine, (:CLOSED => :OPEN, bypass.inlet.ṁ < 0.01, "bypass flow low"))
push!(machine, (:OPEN => :CLOSED, bypass.inlet.ṁ > 0.05, "bypass flow restored"))
sol = solve_transient(ssys, op, times; callbacks=machine_callbacks(ssys, machine))
```

A number in a condition, like `0.01` above, is compiled into the event. To vary it between
runs without recompiling, write it as a parameter of the model and change it with `remake`:

```julia
@parameters ṁ_open_at = 0.01
push!(machine, (:CLOSED => :OPEN, bypass.inlet.ṁ < ṁ_open_at))
model = compose(System(connections, t, [], [ṁ_open_at]; name=:loop), flap, bypass, ...)
# later, for another threshold. The machine remembers opening last time, so reset it.
reset!(machine)
prob2 = remake(prob; p=[ṁ_open_at => 0.02])
```

Opening and closing both take `1/open_rate` seconds, along the same curve: `xi = r(y)`, with
`r(y) = 3y² − 2y³` rising smoothly from 0 to 1. `y` climbs at `open_rate` while the machine is
in `open_state` and falls back at the same rate in any other state, so a valve closed part way
through opening shuts from where it had reached. A machine that starts in `open_state`,
`StateMachine(; initial_state=:OPEN, initial_time=t0)`, opens from `t0` with no transition at
all.

A shut valve carries no flow, so it belongs in **parallel** with a branch that carries flow
meanwhile. In series it would block the loop.

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: how fast it opens and closes [1/s]; either takes `1/open_rate` s (default 1.0)
- `machine`: the [`StateMachine`](@ref) the valve follows (default a fresh one in `:CLOSED`)
- `open_state`: the state in which the valve is open (default `:OPEN`)
- `open_fraction`: a function of time `t -> xi` in `[0, 1]` to use instead of the ramp above,
  for instance a measured opening curve. It may read the machine but not the model's
  variables: a fraction that depends on the flow it controls makes the equations
  non-smooth, and a steady solve stalls. Zero or less means shut.
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref), whose density at the
  inlet temperature sets the open valve's pressure drop

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`, with the open fraction as the variable `xi`.
"""
function Flapper(; name, f=1.0, area=1.0, open_rate=1.0,
                 machine::StateMachine=StateMachine(; initial_state=:CLOSED),
                 open_state=:OPEN, open_fraction=nothing, liquid::AbstractLiquid=H2O)
    fraction = open_fraction === nothing ?
        _Opening(machine, open_state, Float64(open_rate)) : open_fraction
    FType = typeof(fraction)

    pars = @parameters begin
        f = f
        area = area
        (xi_fn::FType)(..) = fraction
    end
    vars = @variables xi(t)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    rho = ρ(liquid, instream(inlet.T))
    dp = inlet.p - outlet.p
    # ΔP = f·ṁ·|ṁ|/(2ρA²), inverted for the flow an open valve passes.
    ṁ_open = sign(dp) * sqrt(abs(dp) * 2 * rho * area^2 / f)
    opened = xi_fn(t)

    eqs = Equation[
        xi ~ opened,
        # Shut, the equation is just ṁ = 0 and ṁ_open is never evaluated: its derivative in
        # dp is infinite at dp = 0, which a shut valve with no pressure across it sits on.
        ifelse(opened <= 0.0, inlet.ṁ, inlet.ṁ - opened * ṁ_open) ~ 0,
    ]

    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars=pars)
end

"""
    _Opening(machine, open_state, open_rate)

The open fraction of a [`Flapper`](@ref) that ramps open and shut at the same rate, called as
`o(t)`.

It walks `machine.log`. Along each entry the ramp coordinate `y` rises at `open_rate` if the
state is `open_state` and falls at `open_rate` otherwise, clamped to `[0, 1]` as it goes, and
the fraction is `3y² − 2y³`. A valve that only ever opens reduces to
`r(clamp(open_rate·(t − t_open), 0, 1))`.
"""
struct _Opening
    machine::StateMachine
    open_state::Any
    open_rate::Float64
end

function (o::_Opening)(t)
    log = o.machine.log
    y = 0.0
    for i in eachindex(log)
        t_start = log[i].t
        t >= t_start || break
        # Two transitions at one instant leave an entry of zero length, which adds nothing.
        t_end = i == lastindex(log) ? t : min(t, log[i + 1].t)
        rate = log[i].state === o.open_state ? o.open_rate : -o.open_rate
        y = clamp(y + rate * (t_end - t_start), 0.0, 1.0)
    end
    return y * y * (3 - 2y)
end
