"""
    _saturated_decay(t, T, λ)

The single-decay profile `(1 - e^(-λT))·e^(-λt)`, shared by [`Activation`](@ref) and
[`DoubleDecay`](@ref).

Written with `expm1` so the saturation factor keeps its precision for short irradiations,
where `λT` is small. `T = Inf` gives a factor of 1 and `T = 0` gives 0.
"""
_saturated_decay(t, T, λ) = -expm1(-λ * T) * exp(-λ * t)

"""
    Activation(λ) <: AbstractDecayHeat

Decay of a material activated at a constant rate through the irradiation,

    F(t, T) = e^(-λt)·(1 - e^(-λT))

Dimensionless and normalized to 1 at `t = 0, T = Inf`. Multiply by the energy deposited per
decay event to get MeV/fission, as in `E_d * Activation(λ)`.

Source: Python STREAM decay_heat/activation.py `profile`.

# Arguments
- `λ`: decay rate of the activated isotope [1/s]
"""
struct Activation <: AbstractDecayHeat
    λ::Float64
end

(model::Activation)(t, T=Inf) = _saturated_decay(t, T, model.λ)

"""
    DoubleDecay(λ₁, λ₂) <: AbstractDecayHeat

Decay of the daughter of an activated isotope, where the activated isotope decays at `λ₁`
and the isotope it produces decays at `λ₂`,

    F(t, T) = [λ₁·e^(-λ₂t)(1 - e^(-λ₂T)) - λ₂·e^(-λ₁t)(1 - e^(-λ₁T))] / (λ₁ - λ₂)

Dimensionless and normalized to 1 at `t = 0, T = Inf`. Singular at `λ₁ = λ₂`, which is not
guarded here or in Python.

Source: Python STREAM decay_heat/activation.py `double_decay_profile`.

# Arguments
- `λ₁`: decay rate of the activated isotope [1/s]
- `λ₂`: decay rate of the isotope it decays into [1/s]
"""
struct DoubleDecay <: AbstractDecayHeat
    λ₁::Float64
    λ₂::Float64
end

function (model::DoubleDecay)(t, T=Inf)
    charge₁ = _saturated_decay(t, T, model.λ₁)
    charge₂ = _saturated_decay(t, T, model.λ₂)
    return (model.λ₁ * charge₂ - model.λ₂ * charge₁) / (model.λ₁ - model.λ₂)
end
