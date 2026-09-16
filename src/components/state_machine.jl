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
    StateMachine(edges...)

The transitions a [`ReactivityController`](@ref) may take, and what fires each one.

Each edge pairs `from => to` with the condition that takes it:

```julia
machine = StateMachine(
    (:NORMAL => :SCRAM,            ssys.pk.P_neutron > 1.2e6),
    (:NORMAL => :SCRAM,            ssys.pump.inlet.ṁ < 0.85 * ṁ_design),
    ((:NORMAL, :DERATED) => :TRIP, ssys.ch.T[5] ~ 95.0),
    (:SCRAM => :ABORT,             (ctrl, t) -> t - ctrl.t_state > 2.0),
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
- A predicate `(ctrl, t) -> Bool` is for conditions about the controller rather than the
  system, such as time spent in the current state. It is checked once per accepted step, so
  it resolves to the step size rather than exactly.

[`machine_callbacks`](@ref) turns the machine into solver events. Edges are tried in the
order given, which is what decides the outcome when two fire at the same instant.

# Arguments
- `edges`: the transitions, each `(from => to, condition)`

# Returns
A `StateMachine` to hand to [`machine_callbacks`](@ref).
"""
struct StateMachine
    transitions::Vector{Transition}
    # Typed rather than left to the default constructor, which would take a single
    # `(from => to, condition)` edge and try to read it as the whole list.
    StateMachine(transitions::Vector{Transition}) = new(transitions)
end

StateMachine(edges...) = StateMachine([e isa Transition ? e : Transition(e...) for e in edges])

"""
    _armed(ctrl, tr) -> Bool

Whether `tr` leaves the state `ctrl` is in. An edge with no `from` leaves any state.
"""
_armed(ctrl, tr::Transition) = tr.from === nothing || ctrl.state in tr.from

"""
    _take!(ctrl, tr, integrator) -> Nothing

Take `tr` if it is armed, stamping and logging through [`trip!`](@ref), and stop the
integration if the state entered is one of `ctrl.abort_states`.
"""
function _take!(ctrl, tr::Transition, integrator)
    _armed(ctrl, tr) || return nothing
    trip!(ctrl, integrator.t; state=tr.to)
    ctrl.state in ctrl.abort_states && terminate!(integrator)
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
            "`x ~ 1.0`, or a predicate (ctrl, t) -> Bool; got $condition",
        ),
    )
    a, b = SymbolicUtils.arguments(expr)
    # `a < b` holds where `b - a` is positive, `a >= b` where `a - b` is.
    gap = op in (<, <=) ? b - a : a - b
    return ModelingToolkit.build_explicit_observed_function(ssys, gap), false
end

"""
    machine_callbacks(ssys, ctrl, machine) -> ContinuousCallback | CallbackSet

Build the solver events a [`StateMachine`](@ref) describes.

Each symbolic transition becomes a `ContinuousCallback` root-finding its own condition, so it
fires at the exact crossing. Predicate transitions become `DiscreteCallback`s, checked after
each accepted step. Taking a transition stamps `ctrl.state` and `ctrl.t_state` and appends to
`ctrl.log`, so a reactivity schedule and a `DecayHeatSource` read the time off `ctrl` as they
always have.

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
    cbs = map(machine.transitions) do tr
        fire!(integ) = _take!(ctrl, tr, integ)
        tr.condition isa Function && return DiscreteCallback(
            (u, t, integ) -> _armed(ctrl, tr) && tr.condition(ctrl, t), fire!
        )
        gap, both_edges = _crossing(ssys, tr.condition)
        # The gap is positive where the relation holds, so its rising edge is where the
        # transition becomes true. An equation has no side to become true and fires both ways.
        ContinuousCallback(
            (u, t, integ) -> gap(u, integ.p, t), fire!, both_edges ? fire! : nothing
        )
    end
    return length(cbs) == 1 ? only(cbs) : CallbackSet(cbs...)
end
