"""
    Transition(from => to, condition)

One edge of a [`StateMachine`](@ref), which is where the forms `from` and `condition` take
are described. `from` is kept as a set of states, or `nothing` for any state.
"""
struct Transition
    from::Union{Nothing,Set}
    to::Any
    condition::Any
end

function Transition(edge::Pair, condition)
    from, to = edge
    states = from isa Union{Tuple,AbstractVector,AbstractSet} ? from : (from,)
    return Transition(from === nothing ? nothing : Set(states), to, condition)
end

"""
    StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())

A control system: the state it is in, when it entered it, how it got there, and the
transitions it may still take.

Nothing about it is particular to neutronics. [`ReactivityController`](@ref) is one user,
which reads the state to schedule rod worth, and a `DecayHeatSource` is another, which reads
the time of the trip.

Each edge pairs `from => to` with the condition that takes it:

```julia
machine = StateMachine(
    (:NORMAL => :SCRAM,            ssys.pk.P_neutron > 1.2e6),
    (:NORMAL => :SCRAM,            ssys.pump.inlet.ṁ < 0.85 * ṁ_design),
    ((:NORMAL, :DERATED) => :TRIP, ssys.ch.T[5] ~ 95.0),
    (:SCRAM => :ABORT,             (machine, t) -> t - machine.t_state > 2.0),
)
```

`from` is one state, any collection of states, or `nothing` for any state. The condition is
written the way ModelingToolkit writes a continuous event:

- An inequality fires at the instant it becomes true. The crossing is root-found, so the time
  is exact whether the quantity is a state or computed from one. Either side may be any
  expression of the system, so a closing margin is
  `ssys.ch.T_wall_left[3] > ssys.ch.T_ONB[3]`.
- An equation fires whenever its sides cross, in either direction, as an equation does in
  ModelingToolkit's own `continuous_events`. It is edge-triggered only: it has no truth value
  at an instant, so a machine built from equations alone cannot tell you it should already
  have fired.
- A predicate `(machine, t) -> Bool` is for conditions about the machine rather than the
  system, such as time spent in the current state. It is checked once per accepted step, so
  it resolves to the step size rather than exactly.

A condition names quantities of components, written the same way before or after
`mtkcompile`: `pump.inlet.ṁ` on the component you built is the symbol the compiled system
carries. Edges therefore go in wherever the components are, either here or through `push!`,
which is what a trip watching the very kinetics the machine's own controller drives needs,
since that component cannot be built until the controller is. Entering a state in
`abort_states` stops the integration. [`machine_callbacks`](@ref) turns the machine into
solver events, and edges are tried in the order given, which is what decides the outcome when
two fire at the same instant.

# Arguments
- `edges`: the transitions, each `(from => to, condition)`

# Keywords
- `initial_state`: the state it starts in (default `:NORMAL`)
- `initial_time`: when it entered that state [s] (default `0.0`)
- `abort_states`: states whose entry stops the integration (default none)

# Fields
- `transitions::Vector{Transition}`: the edges
- `state`: the state it is in now
- `t_state::Float64`: when it entered that state [s]
- `log::Vector{Tuple{Any,Float64}}`: every state entered, with its time, oldest first
- `abort_states::Set`: the states that stop the integration
"""
mutable struct StateMachine
    transitions::Vector{Transition}
    state::Any
    t_state::Float64
    log::Vector{Tuple{Any,Float64}}
    abort_states::Set

    # An inner constructor, so no default one competes with this signature.
    function StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())
        t0 = Float64(initial_time)
        machine = new(
            Transition[], initial_state, t0,
            Tuple{Any,Float64}[(initial_state, t0)], Set{Any}(abort_states),
        )
        foreach(edge -> push!(machine, edge), edges)
        return machine
    end
end

"""
    push!(machine::StateMachine, edge) -> StateMachine

Add one edge, either a [`Transition`](@ref) or the `(from => to, condition)` it is built
from. This is how a machine gets a condition on a component that could not exist when the
machine was built, such as the kinetics driven by the controller holding it.
"""
Base.push!(machine::StateMachine, edge) =
    (push!(machine.transitions, edge isa Transition ? edge : Transition(edge...)); machine)

"""
    trip!(machine::StateMachine, t_now; state=:SCRAM) -> state

Put `machine` into `state` at time `t_now`, stamping `t_state` and appending to `log`.

This is how a transition is taken, and the way to trip a machine by hand. It latches: calling
it again while the machine is already in `state` changes nothing, so the first time stands.

# Arguments
- `machine`: the [`StateMachine`](@ref) to move
- `t_now`: the time of the transition [s]

# Keywords
- `state`: the state to enter (default `:SCRAM`)

# Returns
The state the machine is in afterwards.
"""
function trip!(machine::StateMachine, t_now; state=:SCRAM)
    machine.state == state && return machine.state
    machine.state = state
    machine.t_state = Float64(t_now)
    push!(machine.log, (state, Float64(t_now)))
    return machine.state
end

"""
    StateSchedule(f=nothing; machine=StateMachine())

A quantity scheduled off a [`StateMachine`](@ref): `f(state, t_state, t)`, called as `s(t)`.

Control equipment tends to act on which state it is in and how long it has been there, so
this is the shape both a rod bank and a valve take. [`ReactivityController`](@ref) is this
under the name the kinetics use, and a [`Flapper`](@ref) opening ramp is another. Without an
`f` the schedule is zero, which reads as no rod worth and as a valve that stays shut.

# Arguments
- `f`: callable `(state, t_state, t) -> Float64`

# Keywords
- `machine`: the machine whose state is read, a fresh one by default

# Fields
- `f`: the schedule
- `machine::StateMachine`: the machine it follows

# Example
```julia
machine = StateMachine(; initial_state=:CLOSED)
opening = StateSchedule(; machine=machine) do state, t_state, t
    state === :OPEN ? clamp(2.0 * (t - t_state), 0.0, 1.0) : 0.0
end
```
"""
struct StateSchedule{F}
    f::F
    machine::StateMachine
end

function StateSchedule(f=nothing; machine::StateMachine=StateMachine())
    return StateSchedule(f === nothing ? ((state, t_state, t) -> 0.0) : f, machine)
end

(schedule::StateSchedule)(t) = schedule.f(schedule.machine.state, schedule.machine.t_state, t)

"""
    _armed(machine, tr) -> Bool

Whether `tr` leaves the state `machine` is in. An edge with no `from` leaves any state.
"""
_armed(machine::StateMachine, tr::Transition) =
    tr.from === nothing || machine.state in tr.from

"""
    _take!(machine, tr, integrator) -> Nothing

Take `tr` if it is armed, and stop the integration if the state entered is one of
`machine.abort_states`.
"""
function _take!(machine::StateMachine, tr::Transition, integrator)
    _armed(machine, tr) || return nothing
    trip!(machine, integrator.t; state=tr.to)
    machine.state in machine.abort_states && terminate!(integrator)
    return nothing
end

"""
    _crossing(ssys, condition) -> (gap, both_edges)

The function behind a symbolic condition, and whether both edges fire. `gap(u, p, t)` is
positive exactly where the condition holds, so the edge that fires it is `gap` rising through
zero. Symbolics normalizes `a > b` into `b < a`, so only the argument order tells the two
apart.

# Throws
- `ArgumentError`: for a symbolic expression that is not a relation
"""
_crossing(ssys, condition::Equation) =
    ModelingToolkit.build_explicit_observed_function(ssys, condition.lhs - condition.rhs), true

function _crossing(ssys, condition::Num)
    expr = Symbolics.unwrap(condition)
    op = SymbolicUtils.iscall(expr) ? SymbolicUtils.operation(expr) : nothing
    op in (<, <=, >, >=) || throw(
        ArgumentError(
            "a transition condition must be a relation such as `x > 1.0`, `x < 1.0` or " *
            "`x ~ 1.0`, or a predicate (machine, t) -> Bool; got $condition",
        ),
    )
    a, b = SymbolicUtils.arguments(expr)
    # `a < b` holds where `b - a` is positive, `a >= b` where `a - b` is.
    gap = op in (<, <=) ? b - a : a - b
    return ModelingToolkit.build_explicit_observed_function(ssys, gap), false
end

"""
    machine_callbacks(ssys, machines...) -> ContinuousCallback | CallbackSet

Build the solver events one or more [`StateMachine`](@ref)s describe.

Whether a model runs on one machine or on one per piece of equipment is the caller's choice:
pass them all here and their events are collected together.

Each symbolic transition becomes a `ContinuousCallback` root-finding its own condition, so it
fires at the exact crossing. Predicate transitions become `DiscreteCallback`s, checked after
each accepted step. Taking a transition stamps the machine through [`trip!`](@ref), so
anything reading its state or `t_state`, such as a [`ReactivityController`](@ref) schedule or
a `DecayHeatSource` clock, follows from the same event.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `machines`: the [`StateMachine`](@ref)s the events move

# Returns
One callback, or a `CallbackSet` of them, for `solve_transient(...; callbacks=...)`.

# Example
```julia
machine = StateMachine((:NORMAL => :SCRAM, flywheel.inlet.ṁ < 0.85 * ṁ_design))
sol = solve_transient(ssys, sol_ss, times; callbacks=machine_callbacks(ssys, machine))
```
"""
function machine_callbacks(ssys, machines::StateMachine...)
    cbs = reduce(vcat, map(machine -> _callbacks(ssys, machine), machines))
    return length(cbs) == 1 ? only(cbs) : CallbackSet(cbs...)
end

function _callbacks(ssys, machine::StateMachine)
    return map(machine.transitions) do tr
        fire!(integ) = _take!(machine, tr, integ)
        tr.condition isa Function && return DiscreteCallback(
            (u, t, integ) -> _armed(machine, tr) && tr.condition(machine, t), fire!
        )
        gap, both_edges = _crossing(ssys, tr.condition)
        # The gap is positive where the relation holds, so its rising edge is where the
        # transition becomes true. An equation has no side to become true and fires both ways.
        ContinuousCallback(
            (u, t, integ) -> gap(u, integ.p, t), fire!, both_edges ? fire! : nothing
        )
    end
end
