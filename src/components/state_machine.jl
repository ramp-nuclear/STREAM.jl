"""
    Transition(from => to, condition)

One edge of a [`StateMachine`](@ref): the states it leaves, the state it enters, and the
condition that fires it.

`from` is a single state, any collection of states, or `nothing` for "from any state". `to`
is the state entered.

The condition is written the way ModelingToolkit writes a continuous event, as a relation
between quantities of the compiled system:

- An inequality, `ssys.pk.P_neutron > 1.2e6` or `ssys.pump.inlet.ṁ < 0.85`, fires at the
  instant it becomes true. The crossing is root-found, so the time is exact whether the
  watched quantity is a state or computed from one.
- An equation, `ssys.ch.T[5] ~ 95.0`, fires whenever the two sides cross, in either
  direction, as an equation does in ModelingToolkit's own `continuous_events`. It is
  edge-triggered only: unlike an inequality it has no truth value at an instant, so a
  machine built from equations alone cannot tell you it should already have fired.
- A predicate `(ctrl, t) -> Bool` is for conditions on the controller itself, such as time
  spent in the current state or how many transitions have happened. It is checked once per
  accepted step, so its resolution is the step size rather than exact.

Either side of a relation can be any expression of the system, so a margin closing is
`ssys.ch.T_wall_left[3] > ssys.ch.T_ONB[3]`.

# Arguments
- `from => to`: the states this edge leaves, and the one it enters
- `condition`: an inequality, an equation, or a predicate `(ctrl, t) -> Bool`
"""
struct Transition{S,C}
    from::Union{Nothing,Set{S}}
    to::S
    condition::C
end

_state_set(states::Union{Tuple,AbstractVector,AbstractSet}) = states
_state_set(state) = (state,)

function Transition(edge::Pair, condition)
    from, to = first(edge), last(edge)
    S = typeof(to)
    froms = from === nothing ? nothing : Set{S}(_state_set(from))
    return Transition{S,typeof(condition)}(froms, to, condition)
end

"""
    StateMachine(edges...)

The transitions a [`ReactivityController`](@ref) may take, and what fires each one.

Each edge is a [`Transition`](@ref), or the `(from => to, condition)` tuple one is built
from. The machine is the single description of the reactor's protection logic:
[`machine_callbacks`](@ref) derives the solver events from it, so a setpoint or a direction
is written once.

```julia
machine = StateMachine(
    (:NORMAL => :SCRAM,            ssys.pk.P_neutron > 1.2e6),
    (:NORMAL => :SCRAM,            ssys.pk.dPdt > 5.0e5),
    (:NORMAL => :SCRAM,            ssys.pump.inlet.ṁ < 0.85 * ṁ_design),
    ((:NORMAL, :DERATED) => :TRIP, ssys.ch.T[5] ~ 95.0),
    (:SCRAM => :ABORT,             (ctrl, t) -> t - ctrl.t_state > 2.0),
)
```

Edges are tried in the order given, which is what decides the outcome when two fire at the
same instant.

# Arguments
- `edges`: the transitions, as [`Transition`](@ref) values or `(from => to, condition)` tuples

# Returns
A `StateMachine` to hand to [`machine_callbacks`](@ref).
"""
struct StateMachine{T<:Tuple}
    transitions::T
    # Only the parameterized form builds one directly. A default constructor taking a tuple
    # would swallow `StateMachine((:A => :B, condition))`, the single-edge call, and read the
    # edge itself as the list of transitions.
    StateMachine{T}(transitions::T) where {T<:Tuple} = new{T}(transitions)
end

function StateMachine(edges...)
    transitions = map(_transition, edges)
    return StateMachine{typeof(transitions)}(transitions)
end
_transition(tr::Transition) = tr
_transition(entry::Tuple{Pair,Any}) = Transition(entry[1], entry[2])

"""
    _crossing(ssys, condition) -> (g, both_edges)

The zero-crossing function behind a symbolic condition, and whether both edges fire.

`g(u, p, t)` is positive exactly where the condition holds, so the edge that fires it is `g`
rising through zero. Symbolics normalizes `a > b` into `b < a`, so every inequality reduces
to one rule and only the argument order differs.

# Throws
- `ArgumentError`: for a symbolic expression that is not a relation
"""
function _crossing(ssys, condition::Equation)
    return ModelingToolkit.build_explicit_observed_function(
        ssys, condition.lhs - condition.rhs
    ), true
end

function _crossing(ssys, condition::Num)
    expr = ModelingToolkit.Symbolics.unwrap(condition)
    # The operator is read before the arguments are taken apart: a bare variable is a call
    # too, and destructuring its one argument would throw something unhelpful.
    relation = ModelingToolkit.SymbolicUtils.iscall(expr)
    op = relation ? ModelingToolkit.SymbolicUtils.operation(expr) : nothing
    relation &= op === (<) || op === (<=) || op === (>) || op === (>=)
    relation || throw(
        ArgumentError(
            "a transition condition must be a relation such as `x > 1.0`, `x < 1.0` or " *
            "`x ~ 1.0`, or a predicate (ctrl, t) -> Bool; got $condition",
        ),
    )
    a, b = ModelingToolkit.SymbolicUtils.arguments(expr)
    # `a < b` holds where `b - a` is positive, `a >= b` where `a - b` is.
    gap = (op === (<) || op === (<=)) ? b - a : a - b
    return ModelingToolkit.build_explicit_observed_function(ssys, gap), false
end

"""
    _armed(ctrl, tr) -> Bool

Whether `tr` leaves the state `ctrl` is in. A transition with no `from` leaves any state.
"""
_armed(ctrl, tr::Transition) = tr.from === nothing || ctrl.state in tr.from

"""
    _take!(ctrl, tr, integrator) -> Nothing

Take transition `tr` if it is armed, and stop the integrator if the state entered is one of
`ctrl.abort_states`.
"""
function _take!(ctrl, tr::Transition, integrator)
    _armed(ctrl, tr) || return nothing
    trip!(ctrl, integrator.t; state=tr.to)
    ctrl.state in ctrl.abort_states && terminate!(integrator)
    return nothing
end

"""
    machine_callbacks(ssys, ctrl, machine) -> ContinuousCallback | DiscreteCallback | CallbackSet
    machine_callbacks(ssys, ctrl) -> ...

Build the solver events a [`StateMachine`](@ref) describes.

Every symbolic transition becomes a `ContinuousCallback` root-finding its own condition, so
each fires at the exact crossing. An inequality fires on the edge where it becomes true; an
equation fires on both edges. Predicate transitions share one `DiscreteCallback` checked
after each accepted step.

Taking a transition stamps `ctrl.state` and `ctrl.t_state` and appends to `ctrl.log`, the
way [`trip!`](@ref) does, so a reactivity schedule and a `DecayHeatSource` read the time off
`ctrl` as they always have. Entering a state in `ctrl.abort_states` stops the integration.

The second form reads the machine off `ctrl.state_machine`, for a controller built with one.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `ctrl`: the [`ReactivityController`](@ref) the transitions move
- `machine`: the [`StateMachine`](@ref)

# Returns
One callback, or a `CallbackSet` of them, for `solve_transient(...; callbacks=...)`.

# Example
```julia
machine = StateMachine((:NORMAL => :SCRAM, ssys.flywheel.inlet.ṁ < 0.85 * ṁ_design))
sol = solve_transient(ssys, sol_ss, times; callbacks=machine_callbacks(ssys, ctrl, machine))
```
"""
function machine_callbacks(ssys, ctrl::ReactivityController, machine::StateMachine)
    cbs = Any[]
    predicates = Any[]
    for tr in machine.transitions
        if tr.condition isa Function
            push!(predicates, tr)
            continue
        end
        gap, both_edges = _crossing(ssys, tr.condition)
        condition = (u, t, integ) -> gap(u, integ.p, t)
        affect! = integ -> _take!(ctrl, tr, integ)
        # The condition is positive where the transition's relation holds, so the rising
        # edge is where it becomes true. An equation has no side to become true and fires
        # both ways.
        push!(cbs, ContinuousCallback(condition, affect!, both_edges ? affect! : nothing))
    end

    if !isempty(predicates)
        ready(tr, t) = _armed(ctrl, tr) && tr.condition(ctrl, t)
        push!(
            cbs,
            DiscreteCallback(
                (u, t, integ) -> any(tr -> ready(tr, t), predicates),
                function (integ)
                    for tr in predicates
                        ready(tr, integ.t) && _take!(ctrl, tr, integ)
                    end
                end,
            ),
        )
    end

    isempty(cbs) && throw(ArgumentError("the state machine has no transitions"))
    return length(cbs) == 1 ? cbs[1] : CallbackSet(cbs...)
end

function machine_callbacks(ssys, ctrl::ReactivityController)
    ctrl.state_machine isa StateMachine || throw(
        ArgumentError(
            "this controller's state_machine is not a StateMachine, so there are no " *
            "transitions to build events from; pass one as machine_callbacks(ssys, ctrl, machine)",
        ),
    )
    return machine_callbacks(ssys, ctrl, ctrl.state_machine)
end
