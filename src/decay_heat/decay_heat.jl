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

Contributions add, so `fp + act` and `sum([fp, act, fis])` both give the total per fission
event of equation FDH, and `Q_prompt * fis` applies a per-event energy. Python STREAM leaves
both to the caller. They are the only thing here that its own package does not have.

Scalars in, scalars out. `model.(ts)` evaluates over a vector of times.
"""
abstract type AbstractDecayHeat end

Base.broadcastable(model::AbstractDecayHeat) = Ref(model)

"""
    Sum(parts) <: AbstractDecayHeat

Several contributions evaluated as one, `F(t, T) = Σᵢ Fᵢ(t, T)`.

Built by `+` and by `sum`, which fold into a flat `Sum` rather than nesting.

# Arguments
- `parts`: a tuple of [`AbstractDecayHeat`](@ref)
"""
struct Sum{P<:Tuple} <: AbstractDecayHeat
    parts::P
end

(model::Sum)(t, T=Inf) = sum(part -> part(t, T), model.parts)

Base.:+(a::AbstractDecayHeat, b::AbstractDecayHeat) = Sum((a, b))
Base.:+(a::Sum, b::AbstractDecayHeat) = Sum((a.parts..., b))
Base.:+(a::AbstractDecayHeat, b::Sum) = Sum((a, b.parts...))
Base.:+(a::Sum, b::Sum) = Sum((a.parts..., b.parts...))

"""
    Scaled(factor, model) <: AbstractDecayHeat

A contribution multiplied by a constant, `F(t, T) = factor · F_model(t, T)`.

Built by `*`. This is how a dimensionless profile picks up its energy per event, and how a
per-fission contribution picks up a fission rate.

# Arguments
- `factor`: the multiplier
- `model`: the [`AbstractDecayHeat`](@ref) being scaled
"""
struct Scaled{M<:AbstractDecayHeat} <: AbstractDecayHeat
    factor::Float64
    model::M
end

(scaled::Scaled)(t, T=Inf) = scaled.factor * scaled.model(t, T)

Base.:*(factor::Real, model::AbstractDecayHeat) = Scaled(Float64(factor), model)
Base.:*(model::AbstractDecayHeat, factor::Real) = Scaled(Float64(factor), model)
