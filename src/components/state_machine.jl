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
    # A function prints as its type, which says nothing to a reader of the log.
    cause = description !== nothing ? String(description) :
            condition isa Function ? "predicate" : string(condition)
    return Transition(from === nothing ? nothing : Set(states), to, condition, cause)
end

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
    MachineLog

The record a [`StateMachine`](@ref) keeps: every state it entered, oldest first, as
`(state, t, cause)` named tuples. It is a vector of them, so `log[end].cause` reads the last
cause, and it prints as a table.
"""
struct MachineLog <: AbstractVector{@NamedTuple{state::Any, t::Float64, cause::String}}
    entries::Vector{@NamedTuple{state::Any, t::Float64, cause::String}}
end

Base.size(log::MachineLog) = size(log.entries)
Base.IndexStyle(::Type{MachineLog}) = IndexLinear()
Base.getindex(log::MachineLog, i::Int) = log.entries[i]
Base.push!(log::MachineLog, entry) = (push!(log.entries, entry); log)
Base.resize!(log::MachineLog, n::Integer) = (resize!(log.entries, n); log)

_format_time(t) = string(round(t; sigdigits=6))

"""
    _show_entries(io, log, indent)

Print each entry of `log` on its own line, as `t = <time> s  <state>  <cause>`, with the
columns aligned.
"""
function _show_entries(io::IO, log, indent)
    times = [_format_time(entry.t) for entry in log]
    states = [string(entry.state) for entry in log]
    wt, ws = maximum(length, times), maximum(length, states)
    for (time, state, entry) in zip(times, states, log)
        print(io, "\n", indent, "t = ", lpad(time, wt), " s   ", rpad(state, ws), "   ",
              entry.cause)
    end
end

function Base.show(io::IO, ::MIME"text/plain", log::MachineLog)
    n = length(log)
    print(io, n, n == 1 ? " state entered:" : " states entered:")
    _show_entries(io, log, "  ")
end

"""
    StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())

A control system, such as a reactor protection system: the state it is in, when it entered
that state, a log of every state it entered and why, and the transitions it can take.

Hand the machine to whatever acts on its state, such as a [`ReactivityController`](@ref), a
[`Flapper`](@ref) or a `DecayHeatSource`, then set its transitions, and
[`machine_callbacks`](@ref) turns them into events for the solver. See
[Trip a reactor or open a valve](@ref) for worked recipes, and [Events and control](@ref) for
how the solver finds an event.

A transition is `(from => to, condition, description)`. `from`
is one state, a collection of states, or `nothing` for any state. The description is what the
log records as the cause; without one, the condition is written out.

The condition is one of:

- **An inequality** between two expressions of the model, such as `pump.inlet.ṁ < 0.01`. It
  fires when it becomes true.
- **An equation** such as `ch.T[5] ~ 95.0`. It fires when the two sides cross, either way.
- **A predicate** `(machine, sys, t) -> Real`, positive where its condition holds, for what
  the other two cannot say, such as time in the current state: `t - m.t_state - 2.0`.
  `sys[var]` reads any variable of the model, and `min` and `max` combine conditions as
  "and" and "or". The solver calls it between its steps as well as at them, so it must have
  no side effects.

Each fires at the instant its condition becomes true. A condition that already holds fires
when the machine enters a state its transition leaves from, and at the start of the run. When
two fire at once, the one added first is taken. Entering a state in `abort_states` stops the
integration.

Transitions can be set as soon as the components they mention exist: `pump.inlet.ṁ` is the
same variable after `mtkcompile`. Assigning `machine.transitions` replaces the list and
`push!(machine, edge)` adds to it, either before [`machine_callbacks`](@ref) reads it.

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
- `log`: every state entered, oldest first, as `(state, t, cause)` named tuples in a
  `MachineLog`, which prints as a table. `cause` is
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
    log::MachineLog
    abort_states::Set

    # Inner, so no default constructor competes with it.
    function StateMachine(edges...; initial_state=:NORMAL, initial_time=0.0, abort_states=())
        t0 = Float64(initial_time)
        machine = new(
            Transition[], initial_state, t0,
            MachineLog([(state=initial_state, t=t0, cause="initial")]), Set{Any}(abort_states),
        )
        foreach(edge -> push!(machine, edge), edges)
        return machine
    end
end

"""
    push!(machine::StateMachine, edge) -> StateMachine

Add one edge to the end of `machine.transitions`, either a [`Transition`](@ref) or the
`(from => to, condition)` or `(from => to, condition, description)` it is built from.

# Throws
- `ArgumentError`: for a condition that is not an inequality, an equation or a
  `(machine, sys, t)` predicate
"""
Base.push!(machine::StateMachine, edge) = (push!(machine.transitions, edge); machine)

# Builds a Transition from its tuple, checks included, wherever one is stored: `push!`, and
# `machine.transitions = [(from => to, condition), ...]`.
Base.convert(::Type{Transition}, edge::Tuple) = Transition(edge...)

function Base.show(io::IO, tr::Transition)
    from = tr.from === nothing ? "any state" : join(sort!(string.(collect(tr.from))), " or ")
    condition = tr.condition isa Function ? "a predicate holds" : string(tr.condition)
    print(io, from, " → ", tr.to, " when ", condition)
    # The description defaults to the condition itself, which would print twice.
    tr.description in (condition, "predicate") || print(io, ": ", tr.description)
end

function Base.show(io::IO, ::MIME"text/plain", machine::StateMachine)
    print(io, "StateMachine in ", machine.state, " since t = ", _format_time(machine.t_state),
          " s")
    if isempty(machine.transitions)
        print(io, "\n  no transitions")
    else
        print(io, "\n  transitions:")
        foreach(tr -> print(io, "\n    ", tr), machine.transitions)
    end
    isempty(machine.abort_states) ||
        print(io, "\n  stops on entering ", join(sort!(string.(collect(machine.abort_states))), " or "))
    print(io, "\n  log:")
    _show_entries(io, machine.log, "    ")
end

Base.show(io::IO, machine::StateMachine) =
    print(io, "StateMachine(", machine.state, " since t = ", _format_time(machine.t_state), " s)")

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

`f` gets the state the machine was in at `t`, the time it entered that state, and `t`, so a
signal can follow how long the machine has been in a state: rods driving in after a scram, or
a pump coasting down after a trip. [`ReactivityController`](@ref) is this under the name the
kinetics use. Without an `f` the signal is zero.

The state is looked up in the machine's log, so `s(t)` is right for any `t` after the solve
as well as during it. That is what makes a quantity computed from a schedule, such as
`sol[pk.reactivity]`, show the rods out before a scram and in after it.

# Arguments
- `f`: callable `(state, t_state, t)`, returning what the component reading it expects

# Keywords
- `machine`: the machine whose state is read, a fresh one by default

# Fields
- `f`: the schedule
- `machine::StateMachine`: the machine it follows

# Returns
A callable `s(t)`.
"""
struct StateSchedule{F}
    f::F
    machine::StateMachine
end

function StateSchedule(f=nothing; machine::StateMachine=StateMachine())
    return StateSchedule(f === nothing ? ((state, t_state, t) -> 0.0) : f, machine)
end

function (schedule::StateSchedule)(t)
    entry = _entry_at(schedule.machine, t)
    return schedule.f(entry.state, entry.t, t)
end

Base.show(io::IO, schedule::StateSchedule) = print(io, "StateSchedule on ", schedule.machine)

"""
    _entry_at(machine, t) -> NamedTuple

The log entry in force at time `t`: the last one entered at or before `t`, or the first if `t`
comes before them all. During a run that is the state the machine is in; after it, the state
it was in at `t`.
"""
function _entry_at(machine::StateMachine, t)
    i = findlast(entry -> entry.t <= t, machine.log)
    return machine.log[something(i, firstindex(machine.log))]
end

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

Build the solver events one or more [`StateMachine`](@ref)s describe, one
`ContinuousCallback` per transition. A model may run on one machine or on one per piece of
equipment. Taking a transition goes through [`trip!`](@ref), so whatever reads the machine
sees the change at the same event.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `machines`: the [`StateMachine`](@ref)s the events move

# Returns
One callback, or a `CallbackSet` of them, for `solve_transient(...; callbacks=...)`.

# Throws
- `ArgumentError`, during the solve: from a predicate that returns `true` or `false`
- `ErrorException`, during the solve: when transitions keep firing around a cycle
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
