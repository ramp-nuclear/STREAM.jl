"""
    AbstractDecayHeat

A decay heat contribution. Subtypes are callable as

    model(t, T=Inf) -> MeV/fission

where `t` is seconds after shutdown and `T` is seconds of operation before it, at a fission
rate taken to be constant over that period. `T = Inf` is saturation, which is the default,
and `T = 0` gives zero everywhere.

Shipped contributions: [`FissionProducts`](@ref) for the summed exponential fits the decay
heat standards publish, [`Actinides`](@ref) for U239 and Np239, [`Activation`](@ref) and
[`DoubleDecay`](@ref) for activated structural material, and [`Fissions`](@ref) for the
prompt fission profile after a reactivity insertion.

[`Activation`](@ref), [`DoubleDecay`](@ref) and [`Fissions`](@ref) return a dimensionless
profile normalized to 1 at `t = 0, T = Inf` rather than MeV/fission. Weighting them by the
energy deposited per event is the caller's job, which is what `*` below is for.

Contributions add and scale, so `fp + act` and `sum([fp, act, fis])` both give the total per
fission event of equation FDH, and `Q_prompt * fis` applies a per-event energy. Either way
the result is one flat [`Sum`](@ref). Python STREAM leaves both to the caller. They are the
only thing here that the Python source does not have.

Scalars in, scalars out. `model.(ts)` evaluates over a vector of times.
"""
abstract type AbstractDecayHeat end

Base.broadcastable(model::AbstractDecayHeat) = Ref(model)

"""
    Sum(weights, parts) <: AbstractDecayHeat

A weighted sum of contributions, `F(t, T) = Σᵢ wᵢ·Fᵢ(t, T)`.

Built by `+` and `*` rather than by hand. `+` joins the terms of both sides and `*` scales
every weight, so an expression of any shape is one flat `Sum`: `k * (a + b)` holds the two
parts `a` and `b`, each weighted `k`, and a single scaled contribution is a one-term `Sum`.

# Arguments
- `weights`: a tuple of `Float64` multipliers, one per part
- `parts`: a tuple of [`AbstractDecayHeat`](@ref), in the same order
"""
struct Sum{N,P<:NTuple{N,AbstractDecayHeat}} <: AbstractDecayHeat
    weights::NTuple{N,Float64}
    parts::P
end

(model::Sum)(t, T=Inf) = sum(map((w, part) -> w * part(t, T), model.weights, model.parts))

"""
    _terms(model) -> (weights, parts)

The weights and parts `model` brings into a [`Sum`](@ref): its own for a `Sum`, and itself
at weight 1 for any other contribution.
"""
_terms(model::Sum) = (model.weights, model.parts)
_terms(model::AbstractDecayHeat) = ((1.0,), (model,))

function Base.:+(a::AbstractDecayHeat, b::AbstractDecayHeat)
    (wa, pa), (wb, pb) = _terms(a), _terms(b)
    return Sum((wa..., wb...), (pa..., pb...))
end

function Base.:*(factor::Real, model::AbstractDecayHeat)
    weights, parts = _terms(model)
    return Sum(Float64(factor) .* weights, parts)
end
Base.:*(model::AbstractDecayHeat, factor::Real) = factor * model
