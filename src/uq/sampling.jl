@doc raw"""
    monte_carlo(prob::AbstractUQ, uncertainties::Pair...; n=1000, rng=default_rng()) -> NamedTuple

Solve `prob` at inputs drawn from their uncertainties, for a check of what [`uq`](@ref) gives
to first order. It solves the nominal state first, then every sample.

Each entry of an uncertain input is drawn from the distribution [`Uncertainty`](@ref)
describes,

```math
X = x_0 (1 + μ_{sys,rel}) (1 + σ_{stat,rel} ε_1) + μ_{sys,abs} + σ_{stat,abs} ε_2
```

with ``ε_1`` and ``ε_2`` independent standard normal draws, so the systematic part shifts every
sample by the same signed amount and the statistical part scatters them. An input given a
`Distribution` instead, with Distributions.jl loaded, is drawn from it. The other inputs stay
at their nominal values. Each sample is a full solve: of the function, of the steady state
from the nominal one, or of the transient. The samples are solved on all of Julia's threads,
so start Julia with `--threads=auto` to use them, except for a model driving a `StateMachine`,
whose runs share the machine and go one at a time. The inputs are drawn from `rng` before any
solve, so the result does not depend on the number of threads.

# Arguments
- `prob`: the problem
- `uncertainties`: `parameter => Uncertainty` or `parameter => Distribution` pairs
- `n`: the number of samples
- `rng`: the random number generator, for a reproducible set of draws

# Returns
`(; nominal, samples, mean, std, failed)`: the outputs at the nominal inputs; the outputs of
every sample that solved, a column each; the mean and the standard deviation of each output
over them; and how many samples failed to solve. A model returning a `NamedTuple` gets its keys
and nesting back instead, with these at each leaf in that leaf's shape, and the samples along
a last dimension.

# Examples
```jldoctest
julia> using Random

julia> prob = UQ.FunctionUQ(x -> 2x.a, (a=1.0,));

julia> r = UQ.monte_carlo(prob, :a => UQ.Uncertainty(statistical_absolute=0.1);
                          n=10_000, rng=Xoshiro(1));

julia> round.(r.std; digits=2)
1-element Vector{Float64}:
 0.2
```
"""
function monte_carlo(prob::AbstractUQ, uncertainties::Pair...; n=1000,
                     rng::AbstractRNG=default_rng())
    prepared = _prepare(prob)
    nominal = Float64.(_outputs(prepared.output))
    x0 = _flat(prepared.values)
    drawn = [prepared.slices[_position(prepared.parameters, p)] => u for (p, u) in uncertainties]
    inputs = repeat(x0, 1, n)
    for k in 1:n, (slice, uncertainty) in drawn
        inputs[slice, k] = _draw(rng, uncertainty, x0[slice])
    end
    results = Vector{Union{Nothing,Vector{Float64}}}(nothing, n)
    function sample(k)
        y = prepared.resolve(inputs[:, k])
        results[k] = y === nothing ? nothing : _outputs(y)
    end
    if prepared.threaded
        Threads.@threads for k in 1:n
            sample(k)
        end
    else
        foreach(sample, 1:n)
    end
    solved = filter(!isnothing, results)
    samples = reduce(hcat, solved; init=zeros(length(nominal), 0))
    r = (; nominal, samples, mean=vec(mean(samples; dims=2)), std=vec(std(samples; dims=2)),
         failed=n - length(solved))
    return _mirror(r, prepared.output)
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
