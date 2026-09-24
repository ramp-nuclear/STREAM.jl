"""
    Transition(from => to, condition, description=nothing)

One edge of a [`StateMachine`](@ref). The machine's docstring lists what `from` and
`condition` may be. `from` is stored as a set of states, or `nothing` for any state.

`description` is what the machine's log records as the cause when this edge is taken.
Without one, an inequality or equation describes itself, as in `"pump₊inlet₊ṁ(t) < 0.01"`,
and a predicate is recorded as `"predicate"`.

# Throws
- `ArgumentError`: for a condition that is not an inequality, an equation or a
  `(machine, sys, t)` predicate
"""
struct Transition
    from::Union{Nothing,Set}
    to::Any
    condition::Any
    description::String
end

function Transition(edge::Pair, condition, description=nothing)
    from, to = edge
    _check_condition(condition)
    states = from isa Union{Tuple,AbstractVector,AbstractSet} ? from : (from,)
    cause = description === nothing ? _describe(condition) : String(description)
    return Transition(from === nothing ? nothing : Set(states), to, condition, cause)
end

"""
    _describe(condition) -> String

The cause a transition without a description records: the condition written out, or
`"predicate"` for a function, whose printed form says nothing.
"""
_describe(condition::Function) = "predicate"
_describe(condition) = string(condition)

"""
    _relation(condition::Num) -> (op, lhs, rhs)

Split an inequality into its operator and its two sides.

# Throws
- `ArgumentError`: if `condition` is not one of `<`, `<=`, `>`, `>=`
"""
function _relation(condition::Num)
    expr = Symbolics.unwrap(condition)
    op = SymbolicUtils.iscall(expr) ? SymbolicUtils.operation(expr) : nothing
    op in (<, <=, >, >=) || throw(ArgumentError(_BAD_CONDITION * "got $condition"))
    lhs, rhs = SymbolicUtils.arguments(expr)
    return op, lhs, rhs
end

const _BAD_CONDITION =
    "a transition condition must be an inequality such as `x > 1.0`, an equation such as " *
    "`x ~ 1.0`, or a predicate `(machine, sys, t) -> Real`; "

"""
    _check_condition(condition) -> Nothing

Reject a condition [`machine_callbacks`](@ref) could not turn into an event. This runs when
the edge is added, so the error points at the `push!` that caused it rather than at the
solve.

# Throws
- `ArgumentError`: for anything but an inequality, an equation, or a function callable as
  `(machine, sys, t)`
"""
function _check_condition(condition)
    if condition isa Function
        hasmethod(condition, Tuple{StateMachine,Any,Float64}) || throw(ArgumentError(
            _BAD_CONDITION * "got a function that cannot be called as (machine, sys, t)"
        ))
    elseif condition isa Num
        _relation(condition)
    elseif !(condition isa Equation)
        throw(ArgumentError(_BAD_CONDITION * "got $condition"))
    end
    return nothing
end

"""
    StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())

A control system, such as a reactor protection system. It holds the state it is in, when it
entered that state, a log of every state it entered and why, and the transitions it can take.

Build the machine first and hand it to whatever acts on its state: a
[`ReactivityController`](@ref) for the rods, a [`Flapper`](@ref), a `DecayHeatSource`. Then add
its transitions, and [`machine_callbacks`](@ref) turns them into events for the solver:

```julia
machine = StateMachine(; abort_states=(:ABORT,))
rods = ReactivityController((state, t_state, t) -> state === :SCRAM ? -0.05 : 0.0;
                            machine=machine)
@named pk = PointKinetics(rods)
@named pump = Pump(dP_design)

push!(machine, (:NORMAL => :SCRAM, pk.P_neutron > 1.2e6, "high power"))
push!(machine, (:NORMAL => :SCRAM, pump.inlet.ṁ < 0.85 * ṁ_design, "low flow"))
push!(machine, (:SCRAM => :ABORT, (m, sys, t) -> t - m.t_state - 2.0, "2 s after scram"))

# compose the model, mtkcompile it into ssys, and solve for sol_ss, then:
sol = solve_transient(ssys, sol_ss, times; callbacks=machine_callbacks(ssys, machine))
machine.log   # each state entered, when, and which transition caused it
```

A transition is `(from => to, condition)`, or `(from => to, condition, description)`. The
description is what the log records as the cause, so name anything a reader of the log will
ask about. `from` is one state, a collection of states, or `nothing` to leave from any state.
`nothing` rather than an empty collection, since an empty one would read as "from no state".

The condition is one of three things:

- **An inequality** between two expressions of the model, such as `pump.inlet.ṁ < 0.01` or
  `ch.T_wall_left[3] > ch.T_ONB[3]`. It fires at the instant it becomes true, which the solver
  finds exactly.
- **An equation** such as `ch.T[5] ~ 95.0`. It fires whenever the two sides cross, in either
  direction, as an equation does in ModelingToolkit's own `continuous_events`.
- **A predicate** `(machine, sys, t) -> Real`, for whatever the first two cannot say, such as
  time spent in the current state. It returns a number that is positive where its condition
  holds, the way `t - m.t_state - 2.0` is positive two seconds after the last transition.
  `sys[pump.inlet.ṁ]` reads any variable of the model, so one predicate can combine the
  machine and the system, with `min` for "and" and `max` for "or":
  `(m, sys, t) -> min(t - m.t_state - 2.0, sys[ch.T[5]] - 95.0)`.

All three fire at the exact instant the condition becomes true, which the solver finds by
looking back inside its last step. So it calls a condition at times between its steps, and
more than once per step: a predicate has to be a plain function of `(machine, sys, t)`, with
no counters and no side effects.

A transition also fires if its condition already holds when the machine enters a state it
can be taken from, and at the start of the run. A scram with the temperature already past an
abort limit therefore aborts at once rather than waiting for a crossing that will not come.
An equation is the exception: it has no side that holds, so it only ever fires on a crossing.

Write conditions on the variables of the components you built, such as `pump.inlet.ṁ`, as
soon as those components exist. They are the same variables in the system `mtkcompile`
returns, so a machine does not wait for the compiled model. A trip on the kinetics is the
one edge that has to come after `PointKinetics` is built, since the kinetics need the
controller and the controller needs the machine.

When two transitions fire at the same instant, the one added first is taken. Entering a state
in `abort_states` stops the integration.

# Arguments
- `edges`: the transitions, each `(from => to, condition)` or
  `(from => to, condition, description)`

# Keywords
- `initial_state`: the state it starts in (default `:NORMAL`)
- `initial_time`: when it entered that state [s] (default `0.0`)
- `abort_states`: states whose entry stops the integration (default none)

# Fields
- `transitions::Vector{Transition}`: the edges
- `state`: the state it is in now
- `t_state::Float64`: when it entered that state [s]
- `log`: every state entered, oldest first, as `(state, t, cause)` named tuples. `cause` is
  the description of the transition taken, `"initial"` for the first entry, or whatever
  [`trip!`](@ref) was given.
- `abort_states::Set`: the states that stop the integration

# Throws
- `ArgumentError`: for an edge whose condition is not one of the three forms
"""
mutable struct StateMachine
    transitions::Vector{Transition}
    state::Any
    t_state::Float64
    log::Vector{@NamedTuple{state::Any, t::Float64, cause::String}}
    abort_states::Set

    # Inner, so no default constructor competes with it.
    function StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())
        t0 = Float64(initial_time)
        machine = new(
            Transition[], initial_state, t0,
            [(state=initial_state, t=t0, cause="initial")], Set{Any}(abort_states),
        )
        foreach(edge -> push!(machine, edge), edges)
        return machine
    end
end

"""
    push!(machine::StateMachine, edge) -> StateMachine

Add one edge, either a [`Transition`](@ref) or the `(from => to, condition)` or
`(from => to, condition, description)` it is built from.

# Throws
- `ArgumentError`: for a condition that is not an inequality, an equation or a
  `(machine, sys, t)` predicate
"""
Base.push!(machine::StateMachine, edge) =
    (push!(machine.transitions, edge isa Transition ? edge : Transition(edge...)); machine)

"""
    trip!(machine::StateMachine, t_now; state=:SCRAM, cause="manual") -> state

Put `machine` into `state` at time `t_now`, stamping `t_state` and adding `cause` to the log.

Taking a transition calls this with the transition's description. Calling it yourself is a
manual override, which is what the default cause says. It latches: calling it again while the
machine is already in `state` changes nothing, so the first time and cause stand.

# Arguments
- `machine`: the [`StateMachine`](@ref) to move
- `t_now`: the time of the transition [s]

# Keywords
- `state`: the state to enter (default `:SCRAM`)
- `cause`: why, as the log records it (default `"manual"`)

# Returns
The state the machine is in afterwards.
"""
function trip!(machine::StateMachine, t_now; state=:SCRAM, cause="manual")
    machine.state == state && return machine.state
    machine.state = state
    machine.t_state = Float64(t_now)
    push!(machine.log, (state=state, t=Float64(t_now), cause=String(cause)))
    return machine.state
end

"""
    reset!(machine::StateMachine) -> StateMachine

Put `machine` back in the state and time it started from, and clear its log down to that
first entry. Its transitions are kept.

A machine remembers what happened in the last run, so a second run from the same model, for
instance after changing a setpoint with `remake`, needs the machine reset first.

# Returns
The same machine.
"""
function reset!(machine::StateMachine)
    first_entry = first(machine.log)
    machine.state = first_entry.state
    machine.t_state = first_entry.t
    resize!(machine.log, 1)
    return machine
end

"""
    StateSchedule(f=nothing; machine=StateMachine())

A signal read off a [`StateMachine`](@ref): `f(state, t_state, t)`, called as `s(t)`.

`f` gets the state the machine is in, the time it entered it, and the current time, so a
signal can follow how long the machine has been in a state: rods driving in after a scram,
or a valve opening. [`ReactivityController`](@ref) is this under the name the kinetics use.
Without an `f` the signal is zero.

One machine can drive any number of schedules, and that is how a control system with several
output signals is written: the machine holds the logic once, and each signal is a schedule
reading it, handed to the component it drives.

```julia
machine = StateMachine()
rods = ReactivityController((state, t_state, t) -> state === :SCRAM ? -0.05 : 0.0;
                            machine=machine)
@named pk = PointKinetics(rods)
@named bypass = Flapper(; machine=machine, open_state=:SCRAM)   # opens on the same scram
```

# Arguments
- `f`: callable `(state, t_state, t) -> Float64`

# Keywords
- `machine`: the machine whose state is read, a fresh one by default

# Fields
- `f`: the schedule
- `machine::StateMachine`: the machine it follows

# Returns
A callable `s(t) -> Float64`.
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
    _applicable(machine, tr) -> Bool

Whether `tr` can be taken from the state `machine` is in now. An edge with no `from` can be
taken from any state, but no edge is taken into the state the machine is already in.
"""
_applicable(machine::StateMachine, tr::Transition) =
    machine.state != tr.to && (tr.from === nothing || machine.state in tr.from)

"""
    _ModelState(ssys, u, p, t, getters)

The model as a predicate sees it, the `sys` in `(machine, sys, t)`. `sys[var]` reads any
variable of `ssys`, computed ones included, at state `u` and time `t`. While the solver looks
for the instant a predicate turned positive, `u` is a state it estimated inside a step, which
is why the predicate is handed this rather than the integrator. `getters` keeps one reader per
variable across calls.
"""
struct _ModelState{S,U,P,T}
    ssys::S
    u::U
    p::P
    t::T
    getters::Dict{Any,Any}
end

Base.getindex(sys::_ModelState, var) =
    get!(() -> getsym(sys.ssys, var), sys.getters, var)(ProblemState(; u=sys.u, p=sys.p, t=sys.t))

"""
    _gap(ssys, machine, condition) -> (gap, both_edges)

The function a transition's `ContinuousCallback` root-finds, and whether it fires on both
edges. `gap(u, p, t)` is positive exactly where the condition holds, so the transition fires as
`gap` rises through zero. For an inequality it is the difference of the two sides, taken the
way round that makes it positive where the inequality holds. For an equation it is the
difference either way, which has no side that holds, so it fires on both edges. A predicate
already returns one.
"""
_gap(ssys, machine, condition::Equation) =
    ModelingToolkit.build_explicit_observed_function(ssys, condition.lhs - condition.rhs), true

function _gap(ssys, machine, condition::Num)
    op, lhs, rhs = _relation(condition)
    # `lhs < rhs` holds where `rhs - lhs` is positive, `lhs >= rhs` where `lhs - rhs` is.
    gap = op in (<, <=) ? rhs - lhs : lhs - rhs
    return ModelingToolkit.build_explicit_observed_function(ssys, gap), false
end

function _gap(ssys, machine, condition::Function)
    getters = Dict{Any,Any}()
    gap(u, p, t) = _signed(condition(machine, _ModelState(ssys, u, p, t, getters), t))
    return gap, false
end

"""
    _signed(value) -> Float64

A predicate's result as the number the solver root-finds.

# Throws
- `ArgumentError`: for `true` or `false`, which give the solver no crossing to find
"""
_signed(value::Real) = Float64(value)
_signed(value::Bool) = throw(ArgumentError(
    "a predicate returns a number that is positive where its condition holds, not true or " *
    "false: write `t - m.t_state - 2.0` rather than `t - m.t_state > 2.0`, and combine " *
    "conditions with `min` for and, `max` for or"
))

"""
    _enter!(machine, tr, integrator) -> Bool

Take `tr`, logging its description as the cause. If the state entered is one of
`machine.abort_states`, stop the integration and return `false`.
"""
function _enter!(machine::StateMachine, tr::Transition, integrator)
    trip!(machine, integrator.t; state=tr.to, cause=tr.description)
    machine.state in machine.abort_states || return true
    terminate!(integrator)
    return false
end

"""
    _settle!(machine, edges, integrator) -> Nothing

Take, in order, every transition whose condition already holds in the state the machine has
just entered, and keep going until none does. A crossing only counts while its transition can
be taken, so without this a condition that became true under an earlier state would never
fire. Equations are left out, since they have no side that holds.

# Throws
- `ErrorException`: when transitions go on firing at one instant, which only a cycle of states
  whose conditions all hold can do
"""
function _settle!(machine::StateMachine, edges, integrator)
    u, p, t = integrator.u, integrator.p, integrator.t
    holds(edge) =
        !edge.both_edges && _applicable(machine, edge.transition) && edge.gap(u, p, t) > 0
    for _ in 0:length(edges)
        i = findfirst(holds, edges)
        i === nothing && return nothing
        _enter!(machine, edges[i].transition, integrator) || return nothing
    end
    error("the transitions of this machine keep firing at t = $t, around a cycle of states " *
          "whose conditions all hold")
end

"""
    machine_callbacks(ssys, machines...) -> ContinuousCallback | CallbackSet

Build the solver events one or more [`StateMachine`](@ref)s describe.

Whether a model runs on one machine or on one per piece of equipment is the caller's choice:
pass them all here and their events are collected together.

Every transition becomes a `ContinuousCallback` root-finding its condition, so it fires at the
exact instant the condition becomes true. After each transition, and once at the start of the
run, the machine also takes any transition whose condition already holds. Taking a transition
goes through [`trip!`](@ref), so anything reading the machine's state or `t_state`, such as a
[`ReactivityController`](@ref) or a `DecayHeatSource` clock, sees the change at the same
event.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `machines`: the [`StateMachine`](@ref)s the events move

# Returns
One callback, or a `CallbackSet` of them, for `solve_transient(...; callbacks=...)`.

# Throws
- `ArgumentError`, during the solve: from a predicate that returns `true` or `false`
- `ErrorException`, during the solve: when transitions keep firing around a cycle

# Example
```julia
machine = StateMachine((:NORMAL => :SCRAM, flywheel.inlet.ṁ < 0.85 * ṁ_design, "low flow"))
sol = solve_transient(ssys, sol_ss, times; callbacks=machine_callbacks(ssys, machine))
```
"""
function machine_callbacks(ssys, machines::StateMachine...)
    cbs = reduce(vcat, map(machine -> _callbacks(ssys, machine), machines))
    return length(cbs) == 1 ? only(cbs) : CallbackSet(cbs...)
end

function _callbacks(ssys, machine::StateMachine)
    edges = map(machine.transitions) do tr
        gap, both_edges = _gap(ssys, machine, tr.condition)
        (transition=tr, gap=gap, both_edges=both_edges)
    end
    function fire!(integrator, i)
        _applicable(machine, edges[i].transition) || return nothing
        _enter!(machine, edges[i].transition, integrator) && _settle!(machine, edges, integrator)
        return nothing
    end
    # The machine settles once at the start; the other callbacks only keep the default.
    settle(cb, u, t, integrator) =
        (_settle!(machine, edges, integrator); u_modified!(integrator, false))
    keep(cb, u, t, integrator) = u_modified!(integrator, false)
    return map(eachindex(edges)) do i
        affect!(integrator) = fire!(integrator, i)
        ContinuousCallback(
            (u, t, integrator) -> edges[i].gap(u, integrator.p, t),
            affect!, edges[i].both_edges ? affect! : nothing;
            initialize=i == firstindex(edges) ? settle : keep,
        )
    end
end
