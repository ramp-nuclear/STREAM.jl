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

Dimensionless and normalized to 1 at `t = 0, T = Inf`. The expression cancels as `λ₂`
approaches `λ₁`, so within a relative `1e-6` of each other the rates are replaced by
their mean in the equal-rate limit, [`_equal_rate_decay`](@ref). Python STREAM leaves
that case unguarded.

Source: Python STREAM decay_heat/activation.py `double_decay_profile`.

# Arguments
- `λ₁`: decay rate of the activated isotope [1/s]
- `λ₂`: decay rate of the isotope it decays into [1/s]
"""
struct DoubleDecay <: AbstractDecayHeat
    λ₁::Float64
    λ₂::Float64
end

# Against a 50-digit reference the general form loses about 1e-16/(Δλ/λ) to cancellation
# and the mean-rate limit is off by about (Δλ/λ)²(λt)², so switching at 1e-6 keeps both
# near 1e-10 for λt up to 10.
const _EQUAL_RATES = 1e-6

function (model::DoubleDecay)(t, T=Inf)
    λ₁, λ₂ = model.λ₁, model.λ₂
    λ = (λ₁ + λ₂) / 2
    abs(λ₁ - λ₂) <= _EQUAL_RATES * λ && return _equal_rate_decay(t, T, λ)
    charge₁ = _saturated_decay(t, T, λ₁)
    charge₂ = _saturated_decay(t, T, λ₂)
    return (λ₁ * charge₂ - λ₂ * charge₁) / (λ₁ - λ₂)
end

"""
    _equal_rate_decay(t, T, λ)

[`DoubleDecay`](@ref) in the limit `λ₁ = λ₂ = λ`,

    F(t, T) = e^(-λt)·[(1 + λt)(1 - e^(-λT)) - λT·e^(-λT)]

The function is symmetric in its two rates, so taking the limit at their mean is accurate
to second order in their difference. The last term is dropped at `T = Inf`, where
`λT·e^(-λT)` would otherwise evaluate to `Inf·0 = NaN`.
"""
function _equal_rate_decay(t, T, λ)
    tail = isinf(T) ? 0.0 : λ * T * exp(-λ * T)
    return exp(-λ * t) * ((1 + λ * t) * -expm1(-λ * T) - tail)
end
