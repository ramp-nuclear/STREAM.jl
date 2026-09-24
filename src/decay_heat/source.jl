"""
    DecayHeatSource(model, machine; P0, Q=200.0, T=Inf, shutdown_states=(:SCRAM,))

Turn a decay heat contribution into the `power_input` a [`PointKinetics`](@ref) takes.

An [`AbstractDecayHeat`](@ref) answers `model(t, T)` in MeV per fission, with `t` counted
from shutdown. A component wants one number in power units at the simulation's own time.
This closes both gaps:

    source(t) = Φ · model(t - t_shutdown, T)      Φ = P0 / Q

`Φ` is the fission rate of equation FR: at `P0` power and `Q` recoverable MeV per fission,
the core runs `P0/Q` fissions worth of energy per second, so multiplying by it converts
MeV/fission into the units `P0` was given in.

# The clock

`t_shutdown` is read off the [`StateMachine`](@ref)'s log: while the machine is in one of
`shutdown_states` the decay time is `t` minus the time it entered that state, floored at zero,
and in any other state it is zero. Reading the log rather than the machine's current state
makes the source right at any `t` after the solve, not only during it.

Flooring at zero is the physics rather than a guard. A reactor at power holds a saturated
decay heat inventory, and `model(0, T)` is exactly that saturated value, so the source sits
there while the reactor runs and decays away from there once tripped. Two things follow.
The source is continuous in value across the trip, with only its slope jumping, at the
instant the machine's own transition fires. And the operating point closes
exactly, since `point_kinetics_steady_state(P0; power_input=source(0.0))` is seeded with the
same number the source returns before the trip.

A trip at a time you already know needs nothing extra: a machine built in the shutdown
state, `StateMachine(; initial_state=:SCRAM, initial_time=5.0)`, is a fixed trip at `t = 5`.

# Units

`P0` sets them. Pass the power the reactor runs at in whatever units the kinetics use, which
is Watts only if `P` is in Watts. A model running dimensionless kinetics at `P0 = 1.0` and
scaling to Watts downstream, as `build_loop_pk` does, wants `P0 = 1.0` here too.

# Arguments
- `model`: the contribution, any [`AbstractDecayHeat`](@ref). Sum several with `+`.
- `machine`: the [`StateMachine`](@ref) the reactor is controlled by, read for the trip
  time. A [`ReactivityController`](@ref) may be handed over instead, and its machine is used.

# Keywords
- `P0`: power the reactor operates at, in the units the kinetics use
- `Q`: recoverable energy per fission [MeV] (default 200.0)
- `T`: irradiation time before shutdown [s] (default `Inf`, a saturated inventory)
- `shutdown_states`: machine states that count as shut down (default `(:SCRAM,)`, the state
  [`trip!`](@ref) enters)

# Returns
A callable `source(t) -> power`, ready to pass as `PointKinetics(...; power_input=source)`.
"""
struct DecayHeatSource{M<:AbstractDecayHeat,S<:Tuple}
    model::M
    Φ::Float64
    T::Float64
    machine::StateMachine
    shutdown_states::S
end

function DecayHeatSource(
    model::AbstractDecayHeat,
    machine::StateMachine;
    P0,
    Q=200.0,
    T=Inf,
    shutdown_states=(:SCRAM,),
)
    return DecayHeatSource(
        model, Float64(P0 / Q), Float64(T), machine, Tuple(shutdown_states)
    )
end

DecayHeatSource(model::AbstractDecayHeat, ctrl::ReactivityController; kwargs...) =
    DecayHeatSource(model, ctrl.machine; kwargs...)

"""
    decay_time(source, t) -> Second

Seconds since shutdown at simulation time `t`, or zero while the reactor is still running.

Zero is the saturated end of the decay curve, so it is the right answer both before the trip
and at a trial time that has fallen back behind it.
"""
function decay_time(source::DecayHeatSource, t)
    entry = _entry_at(source.machine, t)
    entry.state in source.shutdown_states || return zero(float(t))
    return max(t - entry.t, zero(float(t)))
end

(source::DecayHeatSource)(t) = source.Φ * source.model(decay_time(source, t), source.T)
