"""
    _saturated_decay(t, T, lamda)

The single-decay profile `(1 - e^(-λT))·e^(-λt)`, shared by [`Activation`](@ref) and
[`DoubleDecay`](@ref).

Written with `expm1` so the saturation factor keeps its precision for short irradiations,
where `λT` is small. `T = Inf` gives a factor of 1 and `T = 0` gives 0.
"""
_saturated_decay(t, T, lamda) = -expm1(-lamda * T) * exp(-lamda * t)

"""
    Activation(lamda) <: AbstractDecayHeat

Decay of a material activated at a constant rate through the irradiation,

    F(t, T) = e^(-λt)·(1 - e^(-λT))

Dimensionless and normalized to 1 at `t = 0, T = Inf`. Multiply by the energy deposited per
decay event to get MeV/fission, as in `E_d * Activation(lamda)`.

Source: Python STREAM decay_heat/activation.py `profile`.

# Arguments
- `lamda`: decay rate of the activated isotope [1/s]
"""
struct Activation <: AbstractDecayHeat
    lamda::Float64
end

(model::Activation)(t, T=Inf) = _saturated_decay(t, T, model.lamda)

"""
    DoubleDecay(lamda1, lamda2) <: AbstractDecayHeat

Decay of the daughter of an activated isotope, where the activated isotope decays at `λ₁`
and the isotope it produces decays at `λ₂`,

    F(t, T) = [λ₁·e^(-λ₂t)(1 - e^(-λ₂T)) - λ₂·e^(-λ₁t)(1 - e^(-λ₁T))] / (λ₁ - λ₂)

Dimensionless and normalized to 1 at `t = 0, T = Inf`. Singular at `λ₁ = λ₂`, which is not
guarded here or in Python.

Source: Python STREAM decay_heat/activation.py `double_decay_profile`.

# Arguments
- `lamda1`: decay rate of the activated isotope [1/s]
- `lamda2`: decay rate of the isotope it decays into [1/s]
"""
struct DoubleDecay <: AbstractDecayHeat
    lamda1::Float64
    lamda2::Float64
end

function (model::DoubleDecay)(t, T=Inf)
    λ1, λ2 = model.lamda1, model.lamda2
    charge1 = _saturated_decay(t, T, λ1)
    charge2 = _saturated_decay(t, T, λ2)
    return (λ1 * charge2 - λ2 * charge1) / (λ1 - λ2)
end
