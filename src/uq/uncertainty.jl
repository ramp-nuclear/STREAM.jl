@doc raw"""
    Uncertainty(; systematic_relative=0.0, statistical_relative=0.0,
                  systematic_absolute=0.0, statistical_absolute=0.0)

The uncertainty of one model input, as Python STREAM's `Uncertainty` writes it: a systematic
part and a statistical part, each relative to the nominal value or absolute. An input with
nominal value ``x_0`` is taken to be distributed as

```math
X ∼ x_0 (1 + μ_{sys,rel}) N(1, σ_{stat,rel}^2) + N(μ_{sys,abs}, σ_{stat,abs}^2)
```

The systematic part is a bias that moves every entry of a vector input together, and it
propagates linearly. The statistical part is a standard deviation, independent between
entries, and it propagates in quadrature. [`uq`](@ref) does both.

Each field is a number, or for a vector input a vector of its length. `a + b` adds the
systematic parts and combines the statistical parts in quadrature.

# Arguments
- `systematic_relative`: bias as a fraction of the nominal value
- `statistical_relative`: standard deviation as a fraction of the nominal value
- `systematic_absolute`: bias, in the input's units
- `statistical_absolute`: standard deviation, in the input's units

# Returns
An `Uncertainty`.

# Examples
```jldoctest
julia> UQ.Uncertainty(statistical_absolute=3.0) + UQ.Uncertainty(statistical_absolute=4.0)
Uncertainty(statistical_absolute=5.0)
```
"""
@kwdef struct Uncertainty{SR,TR,SA,TA}
    systematic_relative::SR = 0.0
    statistical_relative::TR = 0.0
    systematic_absolute::SA = 0.0
    statistical_absolute::TA = 0.0
end

"""
    as_absolute(u::Uncertainty, nominal) -> (systematic, statistical)

The systematic and statistical parts of `u` in the input's own units, at the nominal value
`nominal`. The relative and absolute systematic parts add; the statistical parts add in
quadrature.

# Arguments
- `u`: the uncertainty
- `nominal`: the input's nominal value, a number or a vector

# Returns
The tuple `(systematic, statistical)`, each a number or a vector shaped like `nominal`.

# Examples
```jldoctest
julia> UQ.as_absolute(UQ.Uncertainty(systematic_relative=0.1, statistical_absolute=2.0), 50.0)
(5.0, 2.0)
```
"""
function as_absolute(u::Uncertainty, nominal)
    systematic = u.systematic_relative .* nominal .+ u.systematic_absolute
    statistical = sqrt.((u.statistical_relative .* nominal) .^ 2 .+ u.statistical_absolute .^ 2)
    return systematic, statistical
end

function Base.:+(a::Uncertainty, b::Uncertainty)
    quadrature(x, y) = sqrt.(x .^ 2 .+ y .^ 2)
    return Uncertainty(
        a.systematic_relative .+ b.systematic_relative,
        quadrature(a.statistical_relative, b.statistical_relative),
        a.systematic_absolute .+ b.systematic_absolute,
        quadrature(a.statistical_absolute, b.statistical_absolute),
    )
end

Base.iszero(u::Uncertainty) = all(f -> all(iszero, getfield(u, f)), fieldnames(Uncertainty))

function Base.show(io::IO, u::Uncertainty)
    given = [f for f in fieldnames(Uncertainty) if !all(iszero, getfield(u, f))]
    print(io, "Uncertainty(", join(("$f=$(getfield(u, f))" for f in given), ", "), ")")
end

@doc raw"""
    uq(s::LocalSensitivities, uncertainties::Pair...) -> NamedTuple

Propagate input uncertainties to the outputs, to first order, through the derivatives
[`local_sensitivities`](@ref) computed, the way Python STREAM's `UQModel.uq` does. Nothing is
solved, so `uq` can be called with any number of uncertainty sets on the same `s`.

Each pair is `parameter => Uncertainty(...)`, with `parameter` one of `s.parameters`, and
an input left out has no uncertainty. With ``J^{(p)}`` the Jacobian columns of input ``p``, and
``s^{(p)}`` and ``σ^{(p)}`` its systematic and statistical parts from [`as_absolute`](@ref),

```math
s_i = ∑_p |∑_j J^{(p)}_{ij} s^{(p)}_j|,   σ_i = (∑_p ∑_j (J^{(p)}_{ij} σ^{(p)}_j)^2)^{1/2}
```

Different inputs are taken as independent.

With Distributions.jl loaded, an input can take a `Distribution` of its value instead: a
univariate one for a number, a multivariate one of the same length for a vector. Its mean less
the nominal value is then the systematic part, and its covariance ``C`` the statistical part,
which adds ``J^{(p)} C (J^{(p)})^T`` to the output variance, so a multivariate distribution
carries correlations between the entries.

# Arguments
- `s`: the result of [`local_sensitivities`](@ref)
- `uncertainties`: `parameter => Uncertainty` or `parameter => Distribution` pairs

# Returns
`(; nominal, sys, stat)`: the nominal outputs, and their systematic and statistical
uncertainties, each a vector the length of `s.nominal`. A model returning a `NamedTuple` gets
its keys and nesting back instead, with `(; nominal, sys, stat)` at each leaf in that leaf's
shape.

# Examples
```jldoctest
julia> s = UQ.local_sensitivities(UQ.FunctionUQ(x -> x.a + x.b, (a=2.0, b=3.0)));

julia> UQ.uq(s, :a => UQ.Uncertainty(systematic_absolute=1.0),
                :b => UQ.Uncertainty(statistical_absolute=2.0))
(nominal = [5.0], sys = [1.0], stat = [2.0])

julia> s = UQ.local_sensitivities(UQ.FunctionUQ(x -> (sum=x.a + x.b, b=[x.b]), (a=2.0, b=3.0)));

julia> UQ.uq(s, :a => UQ.Uncertainty(statistical_absolute=2.0)).sum
(nominal = 5.0, sys = 0.0, stat = 2.0)
```
"""
function uq(s::LocalSensitivities, uncertainties::Pair...)
    c = _contributions(s, uncertainties...)
    r = (; nominal=s.nominal, sys=vec(sum(abs, c.sys; dims=2)),
         stat=vec(sqrt.(sum(abs2, c.stat; dims=2))))
    return _mirror(r, s.output)
end

"""
    contributions(s::LocalSensitivities, uncertainties::Pair...) -> NamedTuple

Split what [`uq`](@ref) gives by input, with the same arguments. `sys` keeps its sign, so
`sum(abs, c.sys; dims=2)` is `uq`'s `sys` and `sum(c.sys; dims=2)` the shift
[`monte_carlo`](@ref) sees, and `sqrt.(sum(abs2, c.stat; dims=2))` is `uq`'s `stat`. An array
input is one column, since its entries combine before `uq` adds the inputs.

# Arguments
- `s`: the result of [`local_sensitivities`](@ref)
- `uncertainties`: `parameter => Uncertainty` or `parameter => Distribution` pairs

# Returns
`(; inputs, sys, stat)`: the inputs of `uncertainties` in order, and matrices of each one's
systematic and statistical part, a row per output and a column per input. A model returning
a `NamedTuple` gets its keys and nesting back instead, with `(; inputs, sys, stat)` at each
leaf, whose last dimension is the inputs.

# Examples
```jldoctest
julia> s = UQ.local_sensitivities(UQ.FunctionUQ(x -> x.a - x.b, (a=2.0, b=3.0)));

julia> UQ.contributions(s, :a => UQ.Uncertainty(systematic_absolute=1.0),
                           :b => UQ.Uncertainty(systematic_absolute=1.0)).sys
1×2 Matrix{Float64}:
 1.0  -1.0
```
"""
function contributions(s::LocalSensitivities, uncertainties::Pair...)
    return _mirror(_contributions(s, uncertainties...), s.output)
end

"""
    _contributions(s, uncertainties...) -> NamedTuple

[`contributions`](@ref) over the flat outputs, which [`uq`](@ref) adds up.
"""
function _contributions(s, uncertainties::Pair...)
    parts = map(uncertainties) do (parameter, input)
        J = jacobian(s, parameter)
        bias, spread = _moments(input, s.values[_position(s.parameters, parameter)])
        return J * bias, sqrt.(_variance(J, spread))
    end
    columns(i) = reduce(hcat, getindex.(parts, i); init=zeros(length(s.nominal), 0))
    return (; inputs=first.(uncertainties), sys=columns(1), stat=columns(2))
end

@doc raw"""
    measurements(s::LocalSensitivities, uncertainties::Pair...) -> Vector{Measurement{Float64}}

The outputs as Measurements.jl values, `nominal ± σ`, with the statistical parts of
`uncertainties` propagated to first order through the derivatives in `s`. Needs
`using Measurements`.

Each input entry becomes an independent `0 ± σ_j` deviation, and output `i` is
``y_i + ∑_j J_{ij} δ_j``. The standard deviations are those [`uq`](@ref) gives as `stat`, but
the outputs also remember which inputs they came from, so arithmetic between them keeps
their correlation: the uncertainty of `y[1] - y[2]` is that of the difference, not the
quadrature sum of the two.

# Arguments
- `s`: the result of [`local_sensitivities`](@ref)
- `uncertainties`: `parameter => Uncertainty` pairs, with no systematic part

# Returns
A `Vector{Measurement{Float64}}`, one per output.

# Throws
- `ArgumentError`: for an uncertainty with a systematic part, which a Measurement cannot hold
"""
function measurements end

"""
    _moments(input, nominal) -> (bias, spread)

What [`uq`](@ref) propagates for one input at its nominal value: the systematic part, one
value per entry, and the statistical part, as a variance per entry or a covariance matrix.
"""
function _moments(u::Uncertainty, nominal)
    systematic, statistical = as_absolute(u, nominal)
    n = length(nominal)
    return _entries(systematic, n), _entries(statistical, n) .^ 2
end

"""
    _entries(x, n) -> AbstractVector

An uncertainty part as one value per Jacobian column: a number repeated `n` times, or an
array flattened.
"""
_entries(x::Number, n) = fill(float(x), n)
_entries(x::AbstractArray, n) = vec(x)

"""
    _variance(J, spread) -> Vector

The output variance an input adds through its Jacobian columns `J`: from independent entries
with variances `spread`, or from a covariance matrix `spread`, the diagonal of ``J C J^T``.
"""
_variance(J, spread::AbstractVector) = J .^ 2 * spread
_variance(J, spread::AbstractMatrix) = vec(sum((J * spread) .* J; dims=2))
