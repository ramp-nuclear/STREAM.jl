@doc raw"""
    monte_carlo(model::UQModel, uncertainties::Pair...; n=1000, rng=default_rng()) -> NamedTuple

Sample the full model at inputs drawn from their uncertainties, for a check of what
[`uq`](@ref) gives to first order.

Each entry of an uncertain input is drawn from the distribution [`Uncertainty`](@ref)
describes,

```math
X = x_0 (1 + μ_{sys,rel}) (1 + σ_{stat,rel} ε_1) + μ_{sys,abs} + σ_{stat,abs} ε_2
```

with ``ε_1`` and ``ε_2`` independent standard normal draws, so the systematic part shifts every
sample by the same signed amount and the statistical part scatters them. The other inputs stay
at their nominal values. Each sample is a full solve: of the function, of the steady state
from the nominal one, or of the transient. The samples are solved on all of Julia's threads,
so start Julia with `--threads=auto` to use them. The inputs are drawn from `rng` before any
solve, so the result does not depend on the number of threads.

# Arguments
- `model`: the model
- `uncertainties`: `parameter => Uncertainty` pairs
- `n`: the number of samples
- `rng`: the random number generator, for a reproducible set of draws

# Returns
`(; samples, mean, std, failed)`: the outputs of every sample, a column each, with `NaN` for
a sample that failed to solve; the mean and the standard deviation of each output over the
samples that solved; and how many did not.

# Examples
```jldoctest
julia> using Random

julia> m = UQ.UQModel(x -> 2x.a, (a=1.0,));

julia> r = UQ.monte_carlo(m, :a => UQ.Uncertainty(statistical_absolute=0.1);
                          n=10_000, rng=Xoshiro(1));

julia> round.(r.std; digits=2)
1-element Vector{Float64}:
 0.2
```
"""
function monte_carlo(model::UQModel, uncertainties::Pair...; n=1000, rng::AbstractRNG=default_rng())
    x0 = _flat(model.values)
    drawn = [model.slices[_position(model, p)] => u for (p, u) in uncertainties]
    inputs = repeat(x0, 1, n)
    for k in 1:n, (slice, uncertainty) in drawn
        inputs[slice, k] = _draw(rng, uncertainty, x0[slice])
    end
    samples = fill(NaN, length(model.nominal), n)
    solved = fill(false, n)
    Threads.@threads for k in 1:n
        y = model.resolve(inputs[:, k])
        y === nothing && continue
        samples[:, k] = y
        solved[k] = true
    end
    good = samples[:, solved]
    return (; samples, mean=vec(mean(good; dims=2)), std=vec(std(good; dims=2)),
            failed=n - count(solved))
end

"""
    _draw(rng, u::Uncertainty, x0) -> Vector{Float64}

One draw of the input entries `x0` from the distribution `u` describes.
"""
function _draw(rng, u::Uncertainty, x0)
    ε1, ε2 = randn(rng, length(x0)), randn(rng, length(x0))
    return @. x0 * (1 + u.systematic_relative) * (1 + u.statistical_relative * ε1) +
              u.systematic_absolute + u.statistical_absolute * ε2
end
