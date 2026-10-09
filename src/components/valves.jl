"""
    Flapper(; name, f=1.0, area=1.0, open_rate=1.0, machine, open_state=:OPEN,
            open_fraction=nothing, dp_linear=1.0, liquid=H2O) -> System

Passive check valve. Shut, it passes no flow. Open, it is a quadratic resistor
`ΔP = f·ṁ·|ṁ| / (2·ρ·area²)`, and part way open it passes `xi` times that flow, where `xi` is
the open fraction, 0 shut and 1 fully open.

The valve holds no setpoint. It is open while its [`StateMachine`](@ref) is in `open_state`
and shut otherwise, and transitions on the machine decide when:

```julia
machine = StateMachine(; initial_state=:CLOSED)
@named flap = Flapper(; machine=machine)
machine.transitions = [
    (:CLOSED => :OPEN, bypass.inlet.ṁ < 0.01, "bypass flow low"),
    (:OPEN => :CLOSED, bypass.inlet.ṁ > 0.05, "bypass flow restored"),
]
sol = solve_transient(ssys, op, times; callbacks=machine_callbacks(ssys, machine))
```

A number in a condition, like `0.01` above, is compiled into the event. To vary it between
runs without recompiling, write it as a parameter of the model and change it with `remake`:

```julia
@parameters ṁ_open_at = 0.01
machine.transitions = [(:CLOSED => :OPEN, bypass.inlet.ṁ < ṁ_open_at, "bypass flow low")]
@named loop = assembly(connections, flap, bypass, ...; parameters=[ṁ_open_at])
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

A flapper is an [`Orifice`](@ref) with the discharge coefficient `1/√f`: the two share the flow
law, the opening and the sealed state. They differ in role. A flapper sits inside a loop and
moves flow between its paths; an orifice is where the loop loses its coolant.

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: how fast it opens and closes [1/s]; either takes `1/open_rate` s (default 1.0)
- `machine`: the [`StateMachine`](@ref) the valve follows (default a fresh one in `:CLOSED`)
- `open_state`: the state in which the valve is open (default `:OPEN`)
- `open_fraction`: a function of time `t -> xi` in `[0, 1]` to use instead of the ramp above,
  such as an interpolation of a measured opening curve. It may read the machine but not the
  model's variables: a fraction that depends on the flow it controls makes the equations
  non-smooth, and a steady solve stalls. Zero or less means shut.
- `dp_linear`: pressure drop [Pa] below which the open valve's flow goes as `ΔP` instead of
  its square root (default 1). The open valve passes
  `ṁ = xi·area·sqrt(2ρ/f)·ΔP / (ΔP² + dp_linear²)^{1/4}`, which crosses zero with a finite
  slope. Well above `dp_linear` this is the quadratic law above.
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref), whose density on the
  side the flow enters sets the open valve's pressure drop

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`, with the open fraction as the variable `xi`.
"""
function Flapper(; name, f=1.0, area=1.0, open_rate=1.0,
                 machine::StateMachine=StateMachine(; initial_state=:CLOSED),
                 open_state=:OPEN, open_fraction=nothing, dp_linear=1.0,
                 liquid::AbstractLiquid=H2O)
    fraction = open_fraction === nothing ?
        _Opening(machine, open_state, open_rate) : open_fraction
    fs = @parameters f = f
    # ΔP = f·ṁ|ṁ|/(2ρA²) is the orifice law with cd = 1/√f.
    return _Valve(; name, area, fraction, dp_linear, liquid, cc=nothing,
                  cd_of_Re=_ -> 1 / sqrt(fs[1]), extra_pars=fs)
end

"""
    Orifice(; name, area, cd, machine, open_state=:OPEN, open_rate=10.0, dp_linear=1.0,
            cc=nothing, liquid=H2O) -> System

A hole a liquid discharges through: a break in a pool wall, a breach in a pipe, or a severed
pipe end. Open, it passes

    ṁ = cd·area·sqrt(2·ρ·Δp)

with `Δp` the pressure across it. Close to `Δp = 0` the flow goes as `Δp` instead (see
`dp_linear`), so it passes through zero smoothly and reverses when `Δp` does. What kind of
break it is depends on where it sits in the loop, not on what it computes: discharge into an
[`Environment`](@ref) to lose the inventory.

Shut, it passes no flow and leaves the pressure across it free, so the intact loop solves with
the break already in place. It opens and shuts with its [`StateMachine`](@ref) exactly as a
[`Flapper`](@ref) does, over `1/open_rate` seconds along the same curve:

```julia
# A break at t = 100 s.
@named breach = Orifice(; area=5e-4, cd=discharge_cd(:sharp),
                        machine=StateMachine(; initial_state=:OPEN, initial_time=100.0))

# A siphon breaker: the drain line shuts for good once the pool falls to z_breaker.
line = StateMachine(; initial_state=:OPEN)
@named drain = Orifice(; area=5e-4, cd=0.6, machine=line)
line.transitions = [(:OPEN => :SHUT, pool.L < z_breaker, "siphon breaker")]
```

The orifice applies the single-phase law throughout and does not check, during the run,
whether the liquid at its throat flashes. With a contraction coefficient `cc` it reports the
static pressure at its vena contracta and how far the liquid there is below saturation.
[`cavitation`](@ref) reads those after the run, at the saved times only, so a dip below
saturation between two saved times goes unseen. To catch one as it happens, put a transition
on the subcooling in a [`StateMachine`](@ref):

```julia
flash = StateMachine(; initial_state=:LIQUID)
push!(flash, (:LIQUID => :FLASHING, breach.subcooling < 0, "throat at saturation"))
```

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `area`: geometric area of the hole [m²]
- `cd`: discharge coefficient, a number such as `discharge_cd(:sharp)`, or a function of the
  throat Reynolds number such as `Re -> lichtarowicz_cd(Re, 2.0)`. The Reynolds number is taken
  on the diameter of a round hole of that area and floored at 1. At zero flow, through a shut
  break or one just opening, the floor keeps such a `cd` positive, so a break opening from
  rest starts to flow.
- `machine`: the [`StateMachine`](@ref) the break follows (default a fresh one in `:SHUT`,
  which never opens)
- `open_state`: the state in which the break is open (default `:OPEN`)
- `open_rate`: how fast it opens and shuts [1/s] (default 10)
- `dp_linear`: pressure difference [Pa] below which the flow goes as `Δp` instead of its
  square root (default 1). The open orifice passes
  `ṁ = xi·cd·area·sqrt(2ρ)·Δp / (Δp² + dp_linear²)^{1/4}`, which crosses zero with a finite
  slope. Well above `dp_linear` this is the square-root law above.
- `cc`: contraction coefficient of the vena contracta, or `nothing` (default) to skip the
  throat report
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref)

# Ports
- `inlet`, `outlet`: `FlowPort`

# Returns
Uncompiled `System`, with the open fraction as the variable `xi`, and with `cc` given the
throat pressure `p_throat` [Pa] and the throat `subcooling` [K], the saturation temperature at
`p_throat` less the liquid temperature.
"""
function Orifice(; name, area, cd, machine::StateMachine=StateMachine(; initial_state=:SHUT),
                 open_state=:OPEN, open_rate=10.0, dp_linear=1.0, cc=nothing,
                 liquid::AbstractLiquid=H2O)
    fraction = _Opening(machine, open_state, open_rate)
    cd isa Function && return _Valve(; name, area, fraction, dp_linear, cc, liquid, cd_of_Re=cd)
    cds = @parameters cd = cd
    return _Valve(; name, area, fraction, dp_linear, cc, liquid,
                  cd_of_Re=_ -> cds[1], extra_pars=cds)
end

"""
    _Valve(; name, area, fraction, cd_of_Re, dp_linear, cc, liquid, extra_pars=[]) -> System

The component behind [`Flapper`](@ref) and [`Orifice`](@ref): a hole of area `area` whose open
fraction `xi` follows `fraction(t)`, passing

    ṁ = xi·cd·area·sqrt(2ρ)·_smooth_signed_sqrt(Δp, dp_linear)

and nothing while `xi` is zero or less. `cd_of_Re` gives the discharge coefficient from the
throat Reynolds number, on the diameter of a round hole of that area and floored at 1; the two
constructors hand it a constant when the coefficient does not depend on the flow. The density
is taken on the side the flow enters. With `cc`, it also carries the vena contracta pressure
`p_throat` and its `subcooling`.

`extra_pars` are parameters `cd_of_Re` refers to, such as a flapper's `f`.
"""
function _Valve(; name, area, fraction, cd_of_Re, dp_linear, cc, liquid, extra_pars=[])
    FType = typeof(fraction)
    pars = @parameters begin
        area = area
        dp_linear = dp_linear
        (xi_fn::FType)(..) = fraction
    end
    append!(pars, extra_pars)
    vars = @variables xi(t)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    ṁ = inlet.ṁ
    T_up = ifelse(ṁ >= 0, instream(inlet.T), instream(outlet.T))
    rho = ρ(liquid, T_up)
    Re_throat = max(abs(ṁ) * sqrt(4 * area / π) / (area * μ(liquid, T_up)), 1.0)
    ṁ_open = cd_of_Re(Re_throat) * area * sqrt(2 * rho) *
        _smooth_signed_sqrt(inlet.p - outlet.p, dp_linear)
    opened = xi_fn(t)

    eqs = Equation[
        xi ~ opened,
        # Shut, the equation is just ṁ = 0, and the pressure across the valve is left to the
        # rest of the loop.
        ifelse(opened <= 0.0, ṁ, ṁ - opened * ṁ_open) ~ 0,
    ]
    if cc !== nothing
        ccs = @parameters cc = cc
        append!(pars, ccs)
        throat = @variables p_throat(t) subcooling(t)
        append!(vars, throat)
        push!(eqs, p_throat ~ inlet.p - (ṁ / (ccs[1] * area))^2 / (2 * rho))
        # Below a few hundred pascals the saturation fits leave their range; Python floors
        # the pressure at the same value.
        push!(eqs, subcooling ~ Tsat(liquid, max(p_throat, _SATURATION_PRESSURE_FLOOR)) - T_up)
    end
    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars)
end

"""
    _smooth_signed_sqrt(x, eps)

`sign(x)·sqrt(|x|)` with the corner at zero rounded off, `x / (x² + eps²)^(1/4)`. The exact
form has an infinite slope at zero, which a valve's flow crosses whenever it seals or reverses;
this one's slope stays near `1/sqrt(eps)`, and for `|x| ≫ eps` it is within `eps²/(4x²)` of
the exact form.
"""
_smooth_signed_sqrt(x, eps) = x / (x^2 + eps^2)^(1 / 4)

"""
    _SATURATION_PRESSURE_FLOOR

The lowest pressure [Pa] a valve reads a saturation temperature at, as Python's break flow
does. A throat driven to or below zero pressure then reports a large negative subcooling
rather than an extrapolated fit.
"""
const _SATURATION_PRESSURE_FLOOR = 700.0

"""
    _Opening(machine, open_state, open_rate)

The open fraction of a [`Flapper`](@ref) or an [`Orifice`](@ref) that ramps open and shut at
the same rate, called as `o(t)`.

It walks `machine.log`. Along each entry the ramp coordinate `y` rises at `open_rate` if the
state is `open_state` and falls at `open_rate` otherwise, clamped to `[0, 1]` as it goes, and
the fraction is `3y² − 2y³`. A valve that only ever opens reduces to
`r(clamp(open_rate·(t − t_open), 0, 1))`.

Building one adds the ramp time `1/open_rate` to the machine's `ramp_times`, so the solver
stops where each ramp ends.
"""
struct _Opening
    machine::StateMachine
    open_state::Any
    open_rate::Float64

    function _Opening(machine::StateMachine, open_state, open_rate)
        rate = Float64(open_rate)
        union!(machine.ramp_times, 1 / rate)
        return new(machine, open_state, rate)
    end
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
