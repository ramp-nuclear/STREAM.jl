"""
    UQModel

A model's outputs as a function of some of its inputs, for first-order uncertainty
propagation. The derivatives come from forward-mode automatic differentiation (ForwardDiff),
not from finite differences, so there is no step size to choose.

Build one with [`UQModel(f, parameters)`](@ref) for any function, or with
[`UQModel(ssys, op, parameters; output)`](@ref) for a compiled system at steady state. Then
[`uq`](@ref) propagates [`Uncertainty`](@ref)s to the outputs, and [`jacobian`](@ref) gives
the derivatives themselves. See [Propagate input uncertainties](@ref).

# Fields
- `parameters`: the inputs, in the order given
- `values`: the nominal value of each input
- `nominal`: the outputs at the nominal inputs, as one flat vector
"""
struct UQModel{F}
    evaluate::F
    parameters::Vector{Any}
    values::Vector{Any}
    slices::Vector{UnitRange{Int}}
    nominal::Vector{Float64}
    cache::Base.RefValue{Union{Nothing,Matrix{Float64}}}
end

"""
    _uqmodel(evaluate, parameters, values, nominal) -> UQModel

A `UQModel` with its slices worked out from `values` and nothing cached yet.
"""
function _uqmodel(evaluate, parameters, values, nominal)
    cache = Ref{Union{Nothing,Matrix{Float64}}}(nothing)
    return UQModel(evaluate, collect(Any, parameters), values, _slices(values), nominal, cache)
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
    return _uqmodel(evaluate, names, values, Float64.(_outputs(f(parameters))))
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
    for p in parameters
        is_parameter(ssys, p) || throw(ArgumentError("$p is not a parameter of $(nameof(ssys))"))
    end
    sol = solve_steady(ssys, op; solver, abstol, reltol)
    SciMLBase.successful_retcode(sol) ||
        error("the steady solve failed with retcode $(sol.retcode), so there is nothing to " *
              "differentiate")
    prob = sol.prob
    ∂F∂u = lu(_state_jacobian(prob, sol.u); check=false)
    issuccess(∂F∂u) ||
        error("∂F/∂u is singular at the steady state, so the state does not depend smoothly " *
              "on the parameters")

    readout = output isa AbstractVector ? (s -> [s[v] for v in output]) : output
    values = Any[prob.ps[p] for p in parameters]
    slices = _slices(values)
    setter = setp_oop(prob, parameters)
    function evaluate(x)
        p = setter(prob, _unflatten(x, values, slices))
        return _outputs(readout(_dual_solution(prob, sol.u, ∂F∂u, p, eltype(x))))
    end
    return _uqmodel(evaluate, parameters, values, Float64.(_outputs(readout(sol))))
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
    x0 = reduce(vcat, [Float64.(vec(collect(v))) for v in model.values])
    return model.cache[] = ForwardDiff.jacobian(model.evaluate, x0)
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

@doc raw"""
    _dual_solution(prob, u, ∂F∂u, p, D) -> NonlinearSolution

The steady state `u` of `prob`, with its derivatives along the directions seeded in `p`
attached, for parameters `p` holding ForwardDiff duals of type `D`.

The partials of the residual ``F(u, p)`` are ``∂F/∂p`` along those directions, and
``du/dp = -(∂F/∂u)^{-1} ∂F/∂p``, with `∂F∂u` the factorized ``∂F/∂u``. The solution holds `u`
as duals carrying ``du/dp``, and `p` as given, so anything read off it (an unknown, an
observed variable, a parameter) carries its derivative.
"""
function _dual_solution(prob, u, ∂F∂u, p, ::Type{D}) where {D<:ForwardDiff.Dual}
    N = ForwardDiff.npartials(D)
    r = _residual(prob, u, p, D)
    ∂F∂p = [ForwardDiff.partials(r[i], j) for i in eachindex(r), j in 1:N]
    du = -(∂F∂u \ ∂F∂p)
    u_dual = [D(u[i], ForwardDiff.Partials(ntuple(j -> du[i, j], Val(N)))) for i in eachindex(u)]
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
