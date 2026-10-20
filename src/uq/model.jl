"""
    UQModel

A model's outputs as a function of some of its inputs, for uncertainty propagation. The
derivatives come from forward-mode automatic differentiation (ForwardDiff), not from finite
differences, so there is no step size to choose.

Build one with [`UQModel(f, parameters)`](@ref) for any function, with
[`UQModel(ssys, op, parameters; output)`](@ref) for a compiled system at steady state, or with
[`UQModel(ssys, op, parameters, t; output)`](@ref) for a transient. Then [`uq`](@ref)
propagates [`Uncertainty`](@ref)s to the outputs to first order, [`jacobian`](@ref) gives the
derivatives themselves, and [`monte_carlo`](@ref) samples the full model instead. See
[Propagate input uncertainties](@ref).

Building a model solves its nominal state once: the steady state for
`UQModel(ssys, op, parameters; output)`, the transient saved at `t` for
`UQModel(ssys, op, parameters, t; output)`. The saved times are what make a model a transient,
as they make [`solve_transient`](@ref) one rather than [`solve_steady`](@ref).

The derivatives are taken on the first call that needs them ([`jacobian`](@ref), [`uq`](@ref)
or [`measurements`](@ref)) in one ForwardDiff pass over every input, and the model keeps them.
That pass is a solve of the whole model in dual numbers, a full integration for a transient,
and keeping its result lets [`uq`](@ref) be called with any number of different uncertainties
without repeating it. The kept Jacobian never goes stale: nothing in a model changes after it
is built, and a different operating point, list of inputs or output is a new model.

# Fields
- `parameters`: the inputs, in the order given
- `values`: the nominal value of each input
- `nominal`: the outputs at the nominal inputs, as one flat vector
"""
struct UQModel{F,G}
    evaluate::F
    resolve::G
    threaded::Bool
    parameters::Vector{Any}
    values::Vector{Any}
    slices::Vector{UnitRange{Int}}
    nominal::Vector{Float64}
    cache::Base.RefValue{Union{Nothing,Matrix{Float64}}}
end

"""
    UQModel(f, parameters::NamedTuple) -> UQModel

A model of any function of named inputs.

`f` is called with ForwardDiff dual numbers in place of the values, so it must be generic
over `Real`: no `Float64` annotations on its arguments, and no conversion to `Float64`.

# Arguments
- `f`: the model, taking a `NamedTuple` with the keys of `parameters` and returning a number
  or an array
- `parameters`: the nominal inputs, each a number or an array of numbers

# Returns
A `UQModel` whose parameters are the keys of `parameters`, as symbols.

# Examples
```jldoctest
julia> m = UQ.UQModel(x -> x.a * x.b, (a=2.0, b=3.0));

julia> UQ.jacobian(m)
1×2 Matrix{Float64}:
 3.0  2.0
```
"""
function UQModel(f, parameters::NamedTuple)
    names = keys(parameters)
    values = collect(Any, Base.values(parameters))
    slices = _slices(values)
    evaluate(x) = _outputs(f(NamedTuple{names}(Tuple(_unflatten(x, values, slices)))))
    return _uqmodel(evaluate, evaluate, names, values, Float64.(_outputs(f(parameters))))
end

@doc raw"""
    UQModel(ssys, op, parameters; output, solver=nothing, abstol=1e-10, reltol=1e-10) -> UQModel

A model of a compiled system at steady state.

The steady state is solved once, with [`solve_steady`](@ref), and differentiated where it
lands. With ``F(u, p) = 0`` the steady equations, the implicit function theorem gives

```math
du/dp = -(∂F/∂u)^{-1} ∂F/∂p
```

so the derivatives cost one linear solve, whichever steady solver found the root. `output`
reads them off a solution whose values carry them, the same way it reads a plain one: by
variable, through a [`ChannelState`](@ref STREAM.Thresholds.ChannelState), or through any
threshold correlation.

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
A `UQModel` keyed by `parameters`.

# Throws
- `ArgumentError`: for an entry of `parameters` that is not a parameter of `ssys`
- `ErrorException`: when the steady solve fails, or when ``∂F/∂u`` is singular there
"""
function UQModel(
    ssys, op, parameters::AbstractVector; output, solver=nothing, abstol=1e-10, reltol=1e-10
)
    steady = _steady_state(ssys, op, parameters; solver, abstol, reltol)
    readout = _readout(output)
    function evaluate(x)
        vals = _unflatten(x, steady.values, steady.slices)
        return _outputs(readout(_dual_solution(steady, vals, eltype(x))))
    end
    function resolve(x)
        sol = _resolve(steady, _unflatten(x, steady.values, steady.slices))
        return sol === nothing ? nothing : _outputs(readout(sol))
    end
    nominal = Float64.(_outputs(readout(steady.sol)))
    return _uqmodel(evaluate, resolve, parameters, steady.values, nominal)
end

@doc raw"""
    UQModel(ssys, op, parameters, t; output, start=:op, overrides=Pair[], solver=Rodas5P(),
            abstol=1e-8, reltol=1e-8, initializealg=nothing, steady_solver=nothing,
            callbacks=nothing, machines=()) -> UQModel

A model of a transient of a compiled system, saved at the times `t`.

The derivatives are carried through the integration as dual numbers, and the solver controls
their error along with the values'. Where the run starts depends on `start`:

- `:op` starts from the operating point `op`, as [`solve_transient(ssys, op, t)`](@ref
  STREAM.solve_transient) does.
- `:steady` solves the steady state at `op` first and starts from it with `overrides`
  applied, as [`solve_transient(ssys, sol, t; overrides)`](@ref STREAM.solve_transient)
  does. The starting state is differentiated as in the steady [`UQModel`](@ref), so an
  input moves the run both through where it starts and through what follows. An input that
  `overrides` sets acts on the steady state only.

A model driven by a [`StateMachine`](@ref STREAM.Components.StateMachine) takes its
`callbacks`, and the `machines` they drive. [`monte_carlo`](@ref) then samples it, resetting
each machine before every run and solving the runs one at a time, since they share the
machines: a trip falls wherever each sample takes it. Its derivatives cannot be taken, since
the machine's state and trip time live outside the problem, where the duals do not reach, so
[`jacobian`](@ref) and [`uq`](@ref) throw.

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
- `initializealg`: DAE initialization; `nothing` takes `NoInit()` for `start=:op`, as
  `solve_transient` does, and `BrownFullBasicInit()` for `start=:steady`
- `steady_solver`: the steady solver for `start=:steady`
- `callbacks`: the callbacks of the run, such as `machine_callbacks(ssys, machine)`
- `machines`: the `StateMachine`s the callbacks drive, reset before every run

# Returns
A `UQModel` keyed by `parameters`.

# Throws
- `ArgumentError`: for an entry of `parameters` that is not a parameter of `ssys`, or a
  `start` other than `:op` and `:steady`
- `ErrorException`: when the nominal run fails
"""
function UQModel(
    ssys, op, parameters::AbstractVector, t::AbstractVector; output, start=:op,
    overrides=Pair[], solver=Rodas5P(), abstol=1e-8, reltol=1e-8, initializealg=nothing,
    steady_solver=nothing, callbacks=nothing, machines=(),
)
    start in (:op, :steady) ||
        throw(ArgumentError("start must be :op or :steady, got $(repr(start))"))
    _check_parameters(ssys, parameters)
    readout = _readout(output)
    tspan = float.((first(t), last(t)))
    states = unknowns(ssys)
    function integrate(prob, u0, p, init)
        foreach(reset!, machines)
        return _integrate(prob, u0, p, t, solver, init, abstol, reltol, callbacks)
    end
    function integrate_dual(prob, (u0, p), (u0_plain, p_plain), init)
        callbacks === nothing || throw(ArgumentError(
            "derivatives cannot follow a StateMachine, whose trip time lives outside the " *
            "problem; sample the model with monte_carlo instead",
        ))
        # BrownFullBasicInit drops the derivatives of the algebraic states it solves for, so the
        # start is made consistent here instead, and the run goes on without initializing again.
        if init isa OrdinaryDiffEq.BrownFullBasicInit
            u0 = _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol)
            init = SciMLBase.NoInit()
        end
        return _integrate(prob, u0, p, t, solver, init, abstol, reltol)
    end
    threaded = isempty(machines)

    # MTK's initialization data would set u0 at solve time from the initial values the problem
    # was built with, dropping the state's derivatives and any new start, so the problems
    # here go without it and the integrator's own `initializealg` makes the start consistent.
    if start === :op
        prob = ODEProblem(ssys, op, tspan; warn_initialize_determined=false,
                          build_initializeprob=false)
        init = initializealg === nothing ? SciMLBase.NoInit() : initializealg
        values = Any[prob.ps[p] for p in parameters]
        slices = _slices(values)
        u_start = getsym(prob, states)(prob)
        set = setsym_oop(prob, [states; parameters])
        function evaluate_op(x)
            vals = _unflatten(x, values, slices)
            dual = set(prob, Any[convert.(eltype(x), u_start); vals])
            plain = set(prob, Any[u_start; _values(vals)])
            return _outputs(readout(integrate_dual(prob, dual, plain, init)))
        end
        function resolve_op(x)
            u0, p = set(prob, Any[u_start; _unflatten(x, values, slices)])
            sol = integrate(prob, u0, p, init)
            return SciMLBase.successful_retcode(sol) ? _outputs(readout(sol)) : nothing
        end
        nominal = resolve_op(_flat(values))
        nominal === nothing && error("the nominal transient failed")
        return _uqmodel(evaluate_op, resolve_op, parameters, values, Float64.(nominal);
                        threaded)
    end

    steady = _steady_state(ssys, op, parameters; solver=steady_solver)
    overridden(x) = any(o -> isequal(first(o), x), overrides)
    held = [e for e in op if is_parameter(ssys, first(e)) && !overridden(first(e))]
    prob = ODEProblem(
        ssys, Pair{Any,Any}[held; states .=> steady.sol[states]; overrides], tspan;
        warn_initialize_determined=false, build_initializeprob=false,
    )
    init = initializealg === nothing ? OrdinaryDiffEq.BrownFullBasicInit() : initializealg
    kept = findall(!overridden, parameters)
    set = setsym_oop(prob, [states; parameters[kept]])
    function evaluate_steady(x)
        vals = _unflatten(x, steady.values, steady.slices)
        start = _dual_solution(steady, vals, eltype(x))[states]
        dual = set(prob, Any[start; vals[kept]])
        plain = set(prob, Any[ForwardDiff.value.(start); _values(vals[kept])])
        return _outputs(readout(integrate_dual(prob, dual, plain, init)))
    end
    function resolve_steady(x)
        vals = _unflatten(x, steady.values, steady.slices)
        settled = _resolve(steady, vals)
        settled === nothing && return nothing
        u0, p = set(prob, Any[settled[states]; vals[kept]])
        sol = integrate(prob, u0, p, init)
        return SciMLBase.successful_retcode(sol) ? _outputs(readout(sol)) : nothing
    end
    nominal = resolve_steady(_flat(steady.values))
    nominal === nothing && error("the nominal transient failed")
    return _uqmodel(evaluate_steady, resolve_steady, parameters, steady.values,
                    Float64.(nominal); threaded)
end

"""
    jacobian(model::UQModel) -> Matrix{Float64}
    jacobian(model::UQModel, parameter) -> Matrix{Float64}

Derivatives of the outputs of `model` with respect to its inputs. Row `i` is output `i` of
`model.nominal`, and the columns run over the inputs in order, one per entry of an array
input. With `parameter`, only that input's columns, which is Python STREAM's
`UQModel.subjacobian`.

The full matrix is computed on the first call, in one ForwardDiff pass over every input, and
kept for every later call; [`UQModel`](@ref) says why it never goes stale.

# Arguments
- `model`: the model
- `parameter`: one of `model.parameters`

# Returns
A `Matrix{Float64}` with a row per output.
"""
function jacobian(model::UQModel)
    cached = model.cache[]
    cached === nothing || return cached
    return model.cache[] = ForwardDiff.jacobian(model.evaluate, _flat(model.values))
end

jacobian(model::UQModel, parameter) = jacobian(model)[:, model.slices[_position(model, parameter)]]

function Base.show(io::IO, ::MIME"text/plain", model::UQModel)
    print(io, "UQModel: ", length(model.nominal), " outputs of ", length(model.parameters),
          " parameters (", join(model.parameters, ", "), ")")
end

"""
    _uqmodel(evaluate, resolve, parameters, values, nominal; threaded=true) -> UQModel

A `UQModel` with its slices worked out from `values` and nothing cached yet. `evaluate` maps
inputs carrying ForwardDiff duals to the outputs, for [`jacobian`](@ref). `resolve` maps plain
inputs to the outputs of the full model, or to `nothing` when it fails to solve, for
[`monte_carlo`](@ref), which calls it from several threads at once unless `threaded` is false.
"""
function _uqmodel(evaluate, resolve, parameters, values, nominal; threaded=true)
    cache = Ref{Union{Nothing,Matrix{Float64}}}(nothing)
    return UQModel(evaluate, resolve, threaded, collect(Any, parameters), values,
                   _slices(values), nominal, cache)
end
