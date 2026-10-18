"""
    STREAMDistributionsExt

A `Distribution` as the uncertainty of a [`UQ.UQModel`](@ref STREAM.UQ.UQModel) input, for
[`UQ.uq`](@ref STREAM.UQ.uq) and [`UQ.monte_carlo`](@ref STREAM.UQ.monte_carlo), loaded with
Distributions.jl.
"""
module STREAMDistributionsExt

using Distributions: Distribution, Multivariate, Univariate, cov, mean, var
using Random: AbstractRNG
using STREAM.UQ: UQ

function UQ._moments(d::Distribution{Univariate}, nominal)
    _check_length(d, nominal, 1)
    return [mean(d) - only(nominal)], [var(d)]
end

function UQ._moments(d::Distribution{Multivariate}, nominal)
    _check_length(d, nominal, length(d))
    return mean(d) .- vec(nominal), cov(d)
end

UQ._draw(rng::AbstractRNG, d::Distribution{Univariate}, x0) = [rand(rng, d)]
UQ._draw(rng::AbstractRNG, d::Distribution{Multivariate}, x0) = rand(rng, d)

"""
    _check_length(d, nominal, n)

Check that an input with value `nominal` has the `n` entries the distribution `d` describes.

# Throws
- `ArgumentError`: when the input does not have the `n` entries the distribution `d` describes
"""
function _check_length(d, nominal, n)
    length(nominal) == n || throw(ArgumentError(
        "a $(typeof(d)) describes $n value(s), but the input has $(length(nominal)); a " *
        "vector input takes a multivariate distribution of its length",
    ))
end

end
