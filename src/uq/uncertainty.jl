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
