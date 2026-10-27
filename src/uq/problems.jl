"""
    AbstractUQ

An uncertainty problem: a [`FunctionUQ`](@ref), a [`SteadyUQ`](@ref) or a [`TransientUQ`](@ref).
A problem only stores what to solve and which inputs are uncertain. The computing is done by
[`local_sensitivities`](@ref) and [`monte_carlo`](@ref).
"""
abstract type AbstractUQ end

"""
    FunctionUQ(f, parameters::NamedTuple)

An uncertainty problem on any function of named inputs.

`f` is called with ForwardDiff dual numbers in place of the values, so it must be generic
over `Real`: no `Float64` annotations on its arguments, and no conversion to `Float64`.

# Arguments
- `f`: the model, taking a `NamedTuple` with the keys of `parameters` and returning a number
  or an array
- `parameters`: the nominal inputs, each a number or an array of numbers

# Returns
A `FunctionUQ`, whose inputs are the keys of `parameters`.

# Examples
```jldoctest
julia> prob = UQ.FunctionUQ(x -> x.a * x.b, (a=2.0, b=3.0))
FunctionUQ in 2 inputs (a, b)

julia> s = UQ.local_sensitivities(prob)
LocalSensitivities of 1 output in 2 inputs (a, b)

julia> UQ.jacobian(s)
1×2 Matrix{Float64}:
 3.0  2.0
```
"""
struct FunctionUQ{F,P<:NamedTuple} <: AbstractUQ
    f::F
    parameters::P
end

@doc raw"""
    SteadyUQ(ssys, op, parameters; output, solver=nothing, abstol=1e-10, reltol=1e-10)

An uncertainty problem on the steady state of a compiled system.

[`local_sensitivities`](@ref) solves the steady state once, with [`solve_steady`](@ref), and
differentiates it where it lands. With ``F(u, p) = 0`` the steady equations, the implicit
function theorem gives

```math
du/dp = -(∂F/∂u)^{-1} ∂F/∂p
```

so the derivatives cost one linear solve, whichever steady solver found the root. `output`
reads them off a solution whose values carry them, the same way it reads a plain one: by
variable, through a [`ChannelState`](@ref STREAM.Thresholds.ChannelState), or through any
threshold correlation. [`monte_carlo`](@ref) solves the steady state again for every sample,
starting from the nominal one.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point for the steady solve, as for [`solve_steady`](@ref)
- `parameters`: the inputs, each a parameter of `ssys`: a design knob, or a component
  parameter such as `ssys.pump.dP_pump`. Each takes its value from `op`, or its default.
- `output`: the outputs. A function `sol -> number or array`, or a vector of variables of
  `ssys`, read as `sol[v]`.
- `solver`, `abstol`, `reltol`: passed to `solve_steady`. The tolerances are tighter than its
  defaults, since the derivatives are taken at the root it returns.

# Returns
A `SteadyUQ`.

# Throws
- `ArgumentError`: naming the entries of `parameters` that are not parameters of `ssys`
"""
struct SteadyUQ{R} <: AbstractUQ
    ssys::System
    op::Vector{Pair{Any,Any}}
    parameters::Vector{Any}
    output::R
    solver::Union{Nothing,SciMLBase.AbstractSciMLAlgorithm}
    abstol::Float64
    reltol::Float64
end

function SteadyUQ(
    ssys, op, parameters::AbstractVector; output, solver=nothing, abstol=1e-10, reltol=1e-10
)
    _check_parameters(ssys, parameters)
    return SteadyUQ(ssys, collect(Pair{Any,Any}, op), collect(Any, parameters), output, solver,
                    abstol, reltol)
end

@doc raw"""
    TransientUQ(ssys, op, parameters, t; output, start=:op, overrides=Pair[], solver=Rodas5P(),
                abstol=1e-8, reltol=1e-8, initializealg=nothing, steady_solver=nothing,
                callbacks=nothing, machines=())

An uncertainty problem on a transient of a compiled system, saved at the times `t`.

[`local_sensitivities`](@ref) carries the derivatives through the integration as dual
numbers, and the solver controls their error along with the values'. Where the run starts
depends on `start`:

- `:op` starts from the operating point `op`, as [`solve_transient(ssys, op, t)`](@ref
  STREAM.solve_transient) does.
- `:steady` solves the steady state at `op` first and starts from it with `overrides`
  applied, as [`solve_transient(ssys, sol, t; overrides)`](@ref STREAM.solve_transient)
  does. The starting state is differentiated as in a [`SteadyUQ`](@ref), so an input moves
  the run both through where it starts and through what follows. An input that `overrides`
  sets acts on the steady state only.

A run driven by a [`StateMachine`](@ref STREAM.Components.StateMachine) takes its
`callbacks`, and the `machines` they drive. [`monte_carlo`](@ref) then samples it, resetting
each machine before every run and solving the runs one at a time, since they share the
machines: a trip falls wherever each sample takes it. Its derivatives cannot be taken, since
the machine's state and trip time live outside the problem, where the duals do not reach, so
[`local_sensitivities`](@ref) refuses it.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point: the start for `start=:op`, the steady solve's for `start=:steady`
- `parameters`: the inputs, each a parameter of `ssys`
- `t`: the times to save at
- `output`: a function of the solution, `sol -> number or array`, such as
  `sol -> sol[ssys.ch.T_out]`, or a vector of variables, each read as its time series
- `start`: `:op` or `:steady`
- `overrides`: parameter changes at `t[1]` for `start=:steady`
- `solver`, `abstol`, `reltol`: for the integration
- `initializealg`: DAE initialization; by default `NoInit()` for `start=:op`, as
  `solve_transient` does, and `BrownFullBasicInit()` for `start=:steady`
- `steady_solver`: the steady solver for `start=:steady`
- `callbacks`: the callbacks of the run, such as `machine_callbacks(ssys, machine)`
- `machines`: the `StateMachine`s the callbacks drive, reset before every run

# Returns
A `TransientUQ`.

# Throws
- `ArgumentError`: naming the entries of `parameters` that are not parameters of `ssys`, or
  for a `start` other than `:op` and `:steady`
"""
struct TransientUQ{R} <: AbstractUQ
    ssys::System
    op::Vector{Pair{Any,Any}}
    parameters::Vector{Any}
    t::Vector{Float64}
    output::R
    start::Symbol
    overrides::Vector{Pair{Any,Any}}
    solver::SciMLBase.AbstractODEAlgorithm
    abstol::Float64
    reltol::Float64
    initializealg::SciMLBase.DAEInitializationAlgorithm
    steady_solver::Union{Nothing,SciMLBase.AbstractSciMLAlgorithm}
    callbacks::Union{Nothing,SciMLBase.DECallback}
    machines::Vector{StateMachine}
end

function TransientUQ(
    ssys, op, parameters::AbstractVector, t::AbstractVector; output, start=:op,
    overrides=Pair[], solver=Rodas5P(), abstol=1e-8, reltol=1e-8, initializealg=nothing,
    steady_solver=nothing, callbacks=nothing, machines=(),
)
    start in (:op, :steady) ||
        throw(ArgumentError("start must be :op or :steady, got $(repr(start))"))
    _check_parameters(ssys, parameters)
    initializealg = something(initializealg,
                              start === :op ? SciMLBase.NoInit() : BrownFullBasicInit())
    return TransientUQ(ssys, collect(Pair{Any,Any}, op), collect(Any, parameters),
                       collect(Float64, t), output, start, collect(Pair{Any,Any}, overrides),
                       solver, abstol, reltol, initializealg, steady_solver, callbacks,
                       collect(StateMachine, machines))
end

"""
    LocalSensitivities

The outputs of an uncertainty problem at its nominal inputs, and their derivatives with respect
to every input there. [`local_sensitivities`](@ref) returns one, and [`uq`](@ref),
[`jacobian`](@ref) and [`measurements`](@ref) read it, so one computation serves any number of
uncertainty sets.

# Fields
- `parameters`: the inputs, in the order given
- `values`: the nominal value of each input
- `nominal`: the outputs at the nominal inputs, as one flat vector
- `jacobian`: the derivatives, a row per output and a column per input entry
"""
struct LocalSensitivities
    parameters::Vector{Any}
    values::Vector{Any}
    slices::Vector{UnitRange{Int}}
    nominal::Vector{Float64}
    jacobian::Matrix{Float64}
end

"""
    local_sensitivities(prob::AbstractUQ) -> LocalSensitivities

Solve `prob` at its nominal inputs, and differentiate its outputs there with respect to every
input, in one ForwardDiff pass. The derivatives are exact, not finite differences, so there
is no step size to choose. How a steady state and a transient are differentiated is in
[`SteadyUQ`](@ref) and [`TransientUQ`](@ref).

# Arguments
- `prob`: the problem

# Returns
A [`LocalSensitivities`](@ref), for [`uq`](@ref), [`jacobian`](@ref) and
[`measurements`](@ref).

# Throws
- `ArgumentError`: for a [`TransientUQ`](@ref) with callbacks, whose trips the derivatives
  cannot follow; sample it with [`monte_carlo`](@ref) instead
- `ErrorException`: when the nominal solve fails, or when ``∂F/∂u`` is singular at a steady
  state
"""
function local_sensitivities(prob::AbstractUQ)
    prob isa TransientUQ && prob.callbacks !== nothing && throw(ArgumentError(
        "derivatives cannot follow a StateMachine, whose trip time lives outside the problem; " *
        "sample it with monte_carlo instead",
    ))
    prepared = _prepare(prob)
    J = ForwardDiff.jacobian(prepared.evaluate, _flat(prepared.values))
    return LocalSensitivities(prepared.parameters, prepared.values, prepared.slices,
                              prepared.nominal, J)
end

"""
    jacobian(s::LocalSensitivities) -> Matrix{Float64}
    jacobian(s::LocalSensitivities, parameter) -> Matrix{Float64}

The derivatives of the outputs with respect to the inputs. Row `i` is output `i` of
`s.nominal`, and the columns run over the inputs in order, one per entry of an array input.
With `parameter`, only that input's columns, which is Python STREAM's `UQModel.subjacobian`.

# Arguments
- `s`: the result of [`local_sensitivities`](@ref)
- `parameter`: one of `s.parameters`

# Returns
A `Matrix{Float64}` with a row per output.
"""
jacobian(s::LocalSensitivities) = s.jacobian
jacobian(s::LocalSensitivities, parameter) = s.jacobian[:, s.slices[_position(s.parameters, parameter)]]

function Base.show(io::IO, ::MIME"text/plain", prob::AbstractUQ)
    inputs = prob isa FunctionUQ ? keys(prob.parameters) : prob.parameters
    print(io, nameof(typeof(prob)), " in ", _count(length(inputs), "input"), " (",
          join(inputs, ", "), ")")
end

function Base.show(io::IO, ::MIME"text/plain", s::LocalSensitivities)
    print(io, "LocalSensitivities of ", _count(length(s.nominal), "output"), " in ",
          _count(length(s.parameters), "input"), " (", join(s.parameters, ", "), ")")
end

"""
    _count(n, noun) -> String

`n` and `noun`, plural unless `n` is 1: `"1 input"`, `"3 inputs"`.
"""
_count(n, noun) = n == 1 ? "$n $noun" : "$n $(noun)s"

"""
    _prepare(prob::AbstractUQ) -> NamedTuple

Solve the nominal state of `prob` and build what [`local_sensitivities`](@ref) and
[`monte_carlo`](@ref) run on: `(; evaluate, resolve, parameters, values, slices, nominal,
threaded)`.

`evaluate` maps the flat input vector, holding ForwardDiff duals, to the outputs, and is what
ForwardDiff differentiates. `resolve` maps plain inputs to the outputs of the full model, or to
`nothing` when it fails to solve. `monte_carlo` calls it from several threads at once unless
`threaded` is false.
"""
function _prepare(prob::FunctionUQ)
    (; f, parameters) = prob
    names = keys(parameters)
    values = collect(Any, Base.values(parameters))
    slices = _slices(values)
    evaluate(x) = _outputs(f(NamedTuple{names}(Tuple(_unflatten(x, values, slices)))))
    nominal = Float64.(_outputs(f(parameters)))
    return (; evaluate, resolve=evaluate, parameters=collect(Any, names), values, slices,
            nominal, threaded=true)
end

function _prepare(prob::SteadyUQ)
    steady = _steady_state(prob.ssys, prob.op, prob.parameters;
                           prob.solver, prob.abstol, prob.reltol)
    readout = _readout(prob.output)
    slices = _slices(steady.values)
    function evaluate(x)
        vals = _unflatten(x, steady.values, slices)
        return _outputs(readout(_dual_solution(steady, vals, eltype(x))))
    end
    function resolve(x)
        sol = _resolve(steady, _unflatten(x, steady.values, slices))
        return sol === nothing ? nothing : _outputs(readout(sol))
    end
    nominal = Float64.(_outputs(readout(steady.sol)))
    return (; evaluate, resolve, prob.parameters, steady.values, slices, nominal, threaded=true)
end

function _prepare(prob::TransientUQ)
    (; ssys, op, parameters, t, start, overrides, solver, abstol, reltol, initializealg,
       callbacks, machines) = prob
    states = unknowns(ssys)
    # MTK's initialization data would set u0 at solve time from the initial values the problem
    # was built with, dropping the state's derivatives and any new start, so the problem goes
    # without it and `initializealg` makes the start consistent.
    build(point) = ODEProblem(ssys, point, (first(t), last(t)); warn_initialize_determined=false,
                              build_initializeprob=false)

    # The run starts from `op` as given, or from the steady state at `op`, which moves with
    # the inputs and carries their derivatives. An overridden input acts on the steady state
    # only, so it is set on the run only when it is not overridden.
    if start === :op
        ode = build(op)
        values = Any[ode.ps[p] for p in parameters]
        u_start = getsym(ode, states)(ode)
        kept = eachindex(parameters)
        dual_start = (vals, D) -> convert.(D, u_start)
        plain_start = vals -> u_start
    else
        steady = _steady_state(ssys, op, parameters; solver=prob.steady_solver)
        values = steady.values
        overridden = x -> any(o -> isequal(first(o), x), overrides)
        held = [e for e in op if is_parameter(ssys, first(e)) && !overridden(first(e))]
        ode = build([held; states .=> steady.sol[states]; overrides])
        kept = findall(!overridden, parameters)
        dual_start = (vals, D) -> _dual_solution(steady, vals, D)[states]
        plain_start = vals -> (settled = _resolve(steady, vals);
                               settled === nothing ? nothing : settled[states])
    end
    slices = _slices(values)
    set = setsym_oop(ode, [states; parameters[kept]])
    readout = _readout(prob.output)

    function evaluate(x)
        vals = _unflatten(x, values, slices)
        u = dual_start(vals, eltype(x))
        u0, p = set(ode, Any[u; vals[kept]])
        u0_plain, p_plain = set(ode, Any[ForwardDiff.value.(u); _values(vals[kept])])
        init = initializealg
        # BrownFullBasicInit drops the derivatives of the algebraic states it solves for, so the
        # start is made consistent here instead, and the run goes on without initializing again.
        if init isa BrownFullBasicInit
            u0 = _consistent_start(ode, u0, p, u0_plain, p_plain, solver, abstol, reltol)
            init = SciMLBase.NoInit()
        end
        return _outputs(readout(_integrate(ode, u0, p, t, solver, init, abstol, reltol)))
    end
    function resolve(x)
        vals = _unflatten(x, values, slices)
        u0 = plain_start(vals)
        u0 === nothing && return nothing
        foreach(reset!, machines)
        sol = _integrate(ode, set(ode, Any[u0; vals[kept]])..., t, solver, initializealg,
                         abstol, reltol, callbacks)
        return SciMLBase.successful_retcode(sol) ? _outputs(readout(sol)) : nothing
    end
    nominal = resolve(_flat(values))
    nominal === nothing && error("the nominal transient failed")
    return (; evaluate, resolve, parameters, values, slices, nominal=Float64.(nominal),
            threaded=isempty(machines))
end
