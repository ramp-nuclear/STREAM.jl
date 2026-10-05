@doc raw"""
    DecayHeatSource(model, machine; P0, Q=200.0, T=Inf, shutdown_states=(:SCRAM,))

Turn a decay heat contribution into the `power_input` a [`PointKinetics`](@ref) takes.

An [`AbstractDecayHeat`](@ref) answers `model(t, T)` in MeV per fission, with `t` counted
from shutdown. A component wants one number in power units at the simulation's own time.
This closes both gaps:

```math
\mathrm{source}(t) = Φ \, \mathrm{model}(t - t_{shutdown}, T), \qquad Φ = P_0 / Q
```

with `Φ` the fission rate and `t_shutdown` the time the machine entered one of
`shutdown_states`, read off its log. Before the trip the decay time is zero, so the source holds
the saturated value a reactor at power carries, and the operating point closes exactly. See
[Decay heat](@ref) for the physics and [Add decay heat to a transient](@ref) for how to use it.

`P0` sets the units: those of the kinetics, so `P0 = 1` for kinetics run in units of the
rated power.

# Arguments
- `model`: the contribution, any [`AbstractDecayHeat`](@ref). Sum several with `+`.
- `machine`: the [`StateMachine`](@ref) the reactor is controlled by, read for the trip
  time. A [`ReactivityController`](@ref) may be handed over instead, and its machine is used.

# Keywords
- `P0`: power the reactor operates at, in the units the kinetics use
- `Q`: recoverable energy per fission [MeV] (default 200.0)
- `T`: irradiation time before shutdown [s] (default `Inf`, a saturated inventory)
- `shutdown_states`: machine states that count as shut down (default `(:SCRAM,)`, the state
  [`trip!`](@ref STREAM.Components.trip!) enters)

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

function Base.show(io::IO, ::MIME"text/plain", s::DecayHeatSource)
    print(io, "DecayHeatSource at fission rate P0/Q = ", s.Φ, ", ",
          isinf(s.T) ? "saturated" : "after $(s.T) s of operation",
          ", shut down in ", join(string.(s.shutdown_states), " or "), " of ", s.machine)
    inner = sprint(show, MIME("text/plain"), s.model)
    print(io, "\n  ", replace(inner, "\n" => "\n  "))
end
