"""
    DecayHeatSource(model, controller; P0, Q=200.0, T=Inf, shutdown_states=(:SCRAM,))

Turn a decay heat contribution into the `power_input` a [`PointKinetics`](@ref) takes.

An [`AbstractDecayHeat`](@ref) answers `model(t, T)` in MeV per fission, with `t` counted
from shutdown. A component wants one number in power units at the simulation's own time.
This closes both gaps:

    source(t) = Φ · model(t - t_shutdown, T)      Φ = P0 / Q

`Φ` is the fission rate of equation FR: at `P0` power and `Q` recoverable MeV per fission,
the core runs `P0/Q` fissions worth of energy per second, so multiplying by it converts
MeV/fission into the units `P0` was given in.

# The clock

`t_shutdown` is read off the `controller`, which already stamps `t_state` when it enters a
state. Until it reaches one of `shutdown_states` the decay time is zero, and after that it
is `t - ctrl.t_state`, floored at zero.

Flooring at zero is the physics rather than a guard. A reactor at power holds a saturated
decay heat inventory, and `model(0, T)` is exactly that saturated value, so the source sits
there while the reactor runs and decays away from there once tripped. Two things follow.
The source is continuous in value across the trip, with only its slope jumping, at an
instant [`scram_callback`](@ref) already stops the solver at. And the operating point closes
exactly, since `point_kinetics_steady_state(P0; power_input=source(0.0))` is seeded with the
same number the source returns before the trip.

The floor also covers the trial times a solver evaluates at inside a Newton iteration, which
can sit below a `t_state` that only advances on accepted steps. Those clamp to zero and
return the untripped value, so nothing moves under the error controller.

A trip at a time you already know needs nothing extra: a controller built in the shutdown
state, `ReactivityController(f; initial_state=:SCRAM, initial_time=5.0)`, is a fixed trip at
`t = 5`.

# Units

`P0` sets them. Pass the power the reactor runs at in whatever units the kinetics use, which
is Watts only if `P` is in Watts. A model running dimensionless kinetics at `P0 = 1.0` and
scaling to Watts downstream, as `build_loop_pk` does, wants `P0 = 1.0` here too.

# Arguments
- `model`: the contribution, any [`AbstractDecayHeat`](@ref). Sum several with `+`.
- `controller`: the `ReactivityController` driving the reactor, read for the trip time

# Keywords
- `P0`: power the reactor operates at, in the units the kinetics use
- `Q`: recoverable energy per fission [MeV] (default 200.0)
- `T`: irradiation time before shutdown [s] (default `Inf`, a saturated inventory)
- `shutdown_states`: controller states that count as shut down (default `(:SCRAM,)`, which
  is what `SCRAMCondition` sets)

# Returns
A callable `source(t) -> power`, ready to pass as `PointKinetics(...; power_input=source)`.
"""
struct DecayHeatSource{M<:AbstractDecayHeat,C,S<:Tuple}
    model::M
    Φ::Float64
    T::Float64
    controller::C
    shutdown_states::S
end

function DecayHeatSource(
    model::AbstractDecayHeat,
    controller::ReactivityController;
    P0,
    Q=200.0,
    T=Inf,
    shutdown_states=(:SCRAM,),
)
    return DecayHeatSource(
        model, Float64(P0 / Q), Float64(T), controller, Tuple(shutdown_states)
    )
end

"""
    decay_time(source, t) -> Second

Seconds since shutdown at simulation time `t`, or zero while the reactor is still running.

Zero is the saturated end of the decay curve, so it is the right answer both before the trip
and at a trial time that has fallen back behind it.
"""
function decay_time(source::DecayHeatSource, t)
    controller = source.controller
    controller.state in source.shutdown_states || return zero(float(t))
    return max(t - controller.t_state, zero(float(t)))
end

(source::DecayHeatSource)(t) = source.Φ * source.model(decay_time(source, t), source.T)
