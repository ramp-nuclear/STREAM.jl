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
    function integrate_dual(prob, dual, plain, init)
        callbacks === nothing || throw(ArgumentError(
            "derivatives cannot follow a StateMachine, whose trip time lives outside the " *
            "problem; sample the model with monte_carlo instead",
        ))
        return _integrate_dual(prob, dual, plain, t, solver, init, abstol, reltol)
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
    held = [e for e in op if is_parameter(ssys, first(e))]
    prob = ODEProblem(
        ssys, _merge(held, states .=> steady.sol[states], overrides), tspan;
        warn_initialize_determined=false, build_initializeprob=false,
    )
    init = initializealg === nothing ? OrdinaryDiffEq.BrownFullBasicInit() : initializealg
    kept = findall(p -> !any(o -> isequal(first(o), p), overrides), parameters)
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
kept.

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

@doc raw"""
    uq(model::UQModel, uncertainties::Pair...) -> NamedTuple

Propagate input uncertainties to the outputs of `model`, to first order, the way Python
STREAM's `UQModel.uq` does.

Each pair is `parameter => Uncertainty(...)`, with `parameter` one of `model.parameters`, and
an input left out has no uncertainty. With ``J^{(p)}`` the Jacobian columns of input ``p``, and
``s^{(p)}`` and ``σ^{(p)}`` its systematic and statistical parts from [`as_absolute`](@ref),

```math
s_i = ∑_p |∑_j J^{(p)}_{ij} s^{(p)}_j|,   σ_i = (∑_p ∑_j (J^{(p)}_{ij} σ^{(p)}_j)^2)^{1/2}
```

Different inputs are taken as independent.

# Arguments
- `model`: the model
- `uncertainties`: `parameter => Uncertainty` pairs

# Returns
`(; nominal, sys, stat)`: the nominal outputs, and their systematic and statistical
uncertainties, each a vector the length of `model.nominal`.

# Examples
```jldoctest
julia> m = UQ.UQModel(x -> x.a + x.b, (a=2.0, b=3.0));

julia> UQ.uq(m, :a => UQ.Uncertainty(systematic_absolute=1.0),
                :b => UQ.Uncertainty(statistical_absolute=2.0))
(nominal = [5.0], sys = [1.0], stat = [2.0])
```
"""
function uq(model::UQModel, uncertainties::Pair...)
    n = length(model.nominal)
    sys, variance = zeros(n), zeros(n)
    for (parameter, uncertainty) in uncertainties
        J = jacobian(model, parameter)
        s, σ = as_absolute(uncertainty, model.values[_position(model, parameter)])
        sys .+= abs.(J * _entries(s, size(J, 2)))
        variance .+= J .^ 2 * _entries(σ, size(J, 2)) .^ 2
    end
    return (; nominal=model.nominal, sys, stat=sqrt.(variance))
end

function Base.show(io::IO, ::MIME"text/plain", model::UQModel)
    print(io, "UQModel: ", length(model.nominal), " outputs of ", length(model.parameters),
          " parameters (", join(model.parameters, ", "), ")")
end

"""
    _position(model, parameter) -> Int

Where `parameter` sits in `model.parameters`.

# Throws
- `ArgumentError`: when it is not one of them
"""
function _position(model::UQModel, parameter)
    i = findfirst(p -> isequal(p, parameter), model.parameters)
    i === nothing && throw(ArgumentError(
        "$parameter is not a parameter of this model, which has $(join(model.parameters, ", "))"
    ))
    return i
end

"""
    _slices(values) -> Vector{UnitRange{Int}}

The positions each input takes in the flat vector ForwardDiff differentiates over, one entry
for a number and one per element for an array.
"""
function _slices(values)
    stops = cumsum(length.(values))
    return [(stop - length(v) + 1):stop for (v, stop) in zip(values, stops)]
end

"""
    _unflatten(x, values, slices) -> Vector

The inputs held in the flat vector `x`, each shaped like its nominal value in `values`.
"""
function _unflatten(x, values, slices)
    return [v isa Number ? x[only(s)] : reshape(x[s], size(v)) for (v, s) in zip(values, slices)]
end

"""
    _outputs(y) -> AbstractVector

A model's result as the flat vector of outputs ForwardDiff differentiates.

# Throws
- `ArgumentError`: for anything but a number or an array
"""
_outputs(y::Number) = [y]
_outputs(y::AbstractArray) = vec(y)
_outputs(y) = throw(ArgumentError("a model returns a number or an array, not a $(typeof(y))"))

"""
    _entries(x, n) -> AbstractVector

An uncertainty part as one value per Jacobian column: a number repeated `n` times, or an
array flattened.
"""
_entries(x::Number, n) = fill(float(x), n)
_entries(x::AbstractArray, n) = vec(x)

"""
    _state_jacobian(prob, u) -> Matrix{Float64}

``∂F/∂u``, the Jacobian of the steady residual of `prob` at `u`, by ForwardDiff.
"""
_state_jacobian(prob, u) = ForwardDiff.jacobian((du, v) -> _f!(du, prob, v, prob.p), similar(u), u)

"""
    _residual(prob, u, p, T) -> Vector{T}

The steady residual ``F(u, p)`` of `prob`, in element type `T`.
"""
function _residual(prob, u, p, T)
    du = similar(u, T)
    _f!(du, prob, u, p)
    return du
end

"""
    _f!(du, prob, u, p)

Evaluate the steady residual of `prob` into `du`. A `SteadyStateProblem`'s function takes a
time, and root finders call it at `t = Inf`. A root finder hands back its solution on the
`NonlinearProblem` it converted that to, whose function takes none.
"""
_f!(du, prob::SciMLBase.SteadyStateProblem, u, p) = prob.f(du, u, p, Inf)
_f!(du, prob::SciMLBase.NonlinearProblem, u, p) = prob.f(du, u, p)

"""
    _check_parameters(ssys, parameters)

Check that every entry of `parameters` is a parameter of `ssys`.

# Throws
- `ArgumentError`: for an entry of `parameters` that is not a parameter of `ssys`
"""
function _check_parameters(ssys, parameters)
    for p in parameters
        is_parameter(ssys, p) || throw(ArgumentError("$p is not a parameter of $(nameof(ssys))"))
    end
end

"""
    _readout(output) -> Function

`output` as a function of a solution: a function as it is, and a vector of variables as the
function reading each of them.
"""
_readout(output::AbstractVector) = sol -> reduce(vcat, [sol[v] for v in output])
_readout(output) = output

"""
    _steady_state(ssys, op, parameters; solver=nothing, abstol=1e-10, reltol=1e-10) -> NamedTuple

Solve the steady state of `ssys` at `op` and prepare it for differentiation in `parameters`:
the solution and its problem, ``∂F/∂u`` factorized there, the out-of-place parameter setter,
the solver settings, and each parameter's value and slice.

# Throws
- `ArgumentError`: for an entry of `parameters` that is not a parameter of `ssys`
- `ErrorException`: when the solve fails, or when ``∂F/∂u`` is singular at its root
"""
function _steady_state(ssys, op, parameters; solver=nothing, abstol=1e-10, reltol=1e-10)
    _check_parameters(ssys, parameters)
    sol = solve_steady(ssys, op; solver, abstol, reltol)
    SciMLBase.successful_retcode(sol) ||
        error("the steady solve failed with retcode $(sol.retcode), so there is nothing to " *
              "differentiate")
    prob = sol.prob
    ∂F∂u = lu(_state_jacobian(prob, sol.u); check=false)
    issuccess(∂F∂u) ||
        error("∂F/∂u is singular at the steady state, so the state does not depend smoothly " *
              "on the parameters")
    values = Any[prob.ps[p] for p in parameters]
    return (; sol, prob, ∂F∂u, setter=setp_oop(prob, parameters), solver, abstol, reltol,
            values, slices=_slices(values))
end

"""
    _resolve(steady, vals) -> Union{SciMLSolution,Nothing}

The steady state at the parameter values `vals`, solved again from the nominal one with the
same solver and tolerances, or `nothing` when that solve fails.
"""
function _resolve(steady, vals)
    prob = remake(steady.prob; p=steady.setter(steady.prob, vals), u0=steady.sol.u)
    inner = steady.solver isa DynamicSS ? (; odesolve_kwargs=(; dense=false)) : (;)
    sol = solve(prob, steady.solver; steady.abstol, steady.reltol, inner...)
    return SciMLBase.successful_retcode(sol) ? sol : nothing
end

"""
    _integrate(prob, u0, p, t, solver, initializealg, abstol, reltol, callbacks=nothing)

`prob` from `u0` with parameters `p`, stepping onto every saved time as
[`solve_transient`](@ref) does.
"""
function _integrate(prob, u0, p, t, solver, initializealg, abstol, reltol, callbacks=nothing)
    prob = remake(prob; u0, p)
    return solve(prob, solver; saveat=t, initializealg, abstol, reltol, callback=callbacks,
                 _saved_steps(prob, t, (;))...)
end

"""
    _integrate_dual(prob, (u0, p), (u0_plain, p_plain), t, solver, initializealg, abstol, reltol)

[`_integrate`](@ref) from a start whose `u0` and `p` carry ForwardDiff duals, with
`u0_plain` and `p_plain` the same start in plain numbers.

`BrownFullBasicInit` solves for the algebraic states with their derivatives dropped, so under
it the start is made consistent here instead, by [`_consistent_start`](@ref), and the run goes
on from there without initializing again.
"""
function _integrate_dual(prob, (u0, p), (u0_plain, p_plain), t, solver, initializealg,
                         abstol, reltol)
    if initializealg isa OrdinaryDiffEq.BrownFullBasicInit
        u0 = _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol)
        initializealg = SciMLBase.NoInit()
    end
    return _integrate(prob, u0, p, t, solver, initializealg, abstol, reltol)
end

@doc raw"""
    _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol) -> Vector

`u0` with its algebraic states solved for, holding its differential states, and with the
derivatives of both.

The values come from `BrownFullBasicInit` on the plain problem. With ``g`` the algebraic rows
at the first time, ``u_d`` the differential states and ``u_a`` the algebraic ones, the
derivatives of the algebraic states follow from ``g = 0`` as

```math
du_a = -(∂g/∂u_a)^{-1} (∂g/∂u_d \, du_d + ∂g/∂p \, dp)
```

the bracket being the partials of ``g`` at the new values, with ``du_a`` set to zero.
"""
function _consistent_start(prob, u0, p, u0_plain, p_plain, solver, abstol, reltol)
    M = prob.f.mass_matrix
    algebraic = M isa AbstractMatrix ? findall(iszero, diag(M)) : Int[]
    isempty(algebraic) && return u0
    integrator = SciMLBase.init(remake(prob; u0=u0_plain, p=p_plain), solver;
                                initializealg=OrdinaryDiffEq.BrownFullBasicInit(), abstol, reltol)
    plain = integrator.u
    t0 = first(prob.tspan)
    u = copy(u0)
    u[algebraic] .= plain[algebraic]
    r = similar(u)
    prob.f(r, u, p, t0)
    function g(u_a)
        v = convert(Vector{eltype(u_a)}, plain)
        v[algebraic] = u_a
        out = similar(v)
        prob.f(out, v, p_plain, t0)
        return out[algebraic]
    end
    du = -(ForwardDiff.jacobian(g, plain[algebraic]) \ _partials(r[algebraic]))
    u[algebraic] = _with_partials(plain[algebraic], du, eltype(u0))
    return u
end

"""
    _values(vals) -> Vector

The plain values of parameter values that may carry ForwardDiff duals.
"""
_values(vals) = [ForwardDiff.value.(v) for v in vals]

"""
    _partials(x) -> Matrix

The partials of the ForwardDiff duals `x`, a row per entry and a column per direction.
"""
_partials(x) = stack(ForwardDiff.partials.(x); dims=1)

"""
    _with_partials(x, du, D) -> Vector{D}

The values `x` as duals of type `D`, entry `i` carrying the partials in row `i` of `du`.
"""
_with_partials(x, du, ::Type{D}) where {D} =
    map((xi, row) -> D(xi, ForwardDiff.Partials(Tuple(row))), x, eachrow(du))

"""
    _merge(ops...) -> Vector{Pair{Any,Any}}

The operating points `ops` as one, a later entry for a symbol replacing an earlier one.
"""
function _merge(ops...)
    merged = Pair{Any,Any}[]
    for entry in Iterators.flatten(ops)
        filter!(e -> !isequal(first(e), first(entry)), merged)
        push!(merged, entry)
    end
    return merged
end

"""
    _flat(values) -> Vector{Float64}

The inputs' values as the one flat vector ForwardDiff differentiates over.
"""
_flat(values) = collect(Float64, Iterators.flatten(values))

@doc raw"""
    _dual_solution(steady, vals, D) -> NonlinearSolution

The steady state of [`_steady_state`](@ref) with its derivatives attached, for parameter
values `vals` holding ForwardDiff duals of type `D`.

With `p` the parameters set to `vals`, the partials of the residual ``F(u, p)`` are
``∂F/∂p`` along the seeded directions, and ``du/dp = -(∂F/∂u)^{-1} ∂F/∂p``. The solution holds
`u` as duals carrying ``du/dp``, and `p` as given, so anything read off it (an unknown, an
observed variable, a parameter) carries its derivative.
"""
function _dual_solution(steady, vals, ::Type{D}) where {D<:ForwardDiff.Dual}
    (; prob, sol, ∂F∂u) = steady
    p = steady.setter(prob, vals)
    du = -(∂F∂u \ _partials(_residual(prob, sol.u, p, D)))
    u_dual = _with_partials(sol.u, du, D)
    dual_prob = remake(prob; u0=u_dual, p=p)
    resid = _residual(dual_prob, u_dual, p, D)
    return SciMLBase.build_solution(dual_prob, nothing, u_dual, resid; retcode=ReturnCode.Success)
end

@doc raw"""
    measurements(model::UQModel, uncertainties::Pair...) -> Vector{Measurement{Float64}}

The outputs of `model` as Measurements.jl values, `nominal ± σ`, with the statistical parts of
`uncertainties` propagated to first order. Needs `using Measurements`.

Each input entry becomes an independent `0 ± σ_j` deviation, and output `i` is
``y_i + ∑_j J_{ij} δ_j``. The standard deviations are those [`uq`](@ref) gives as `stat`, but
the outputs also remember which inputs they came from, so arithmetic between them keeps
their correlation: the uncertainty of `y[1] - y[2]` is that of the difference, not the
quadrature sum of the two.

# Arguments
- `model`: the model
- `uncertainties`: `parameter => Uncertainty` pairs, with no systematic part

# Returns
A `Vector{Measurement{Float64}}`, one per output.

# Throws
- `ArgumentError`: for an uncertainty with a systematic part, which a Measurement cannot hold
"""
function measurements end
