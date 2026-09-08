"""
    U239_DECAY_RATE

Decay rate of U-239, `4.91e-4` 1/s. Used by [`Actinides`](@ref).
"""
const U239_DECAY_RATE = 4.91e-4

"""
    NP239_DECAY_RATE

Decay rate of Np-239, `3.41e-6` 1/s. Used by [`Actinides`](@ref).
"""
const NP239_DECAY_RATE = 3.41e-6

"""
    E_U239

Energy deposited per U-239 decay, `0.460` MeV. Used by [`Actinides`](@ref).
"""
const E_U239 = 0.460

"""
    E_NP239

Energy deposited per Np-239 decay, `0.405` MeV. Used by [`Actinides`](@ref).
"""
const E_NP239 = 0.405

"""
    Actinides(R) <: AbstractDecayHeat

Decay heat from the U-239 and Np-239 that neutron capture in U-238 leaves behind,

    ²³⁸U --(n,γ)--> ²³⁹U --β⁻--> ²³⁹Np --β⁻--> ²³⁹Pu

evaluated as

    F(t, T) = R·[E_U·A(t, T; λ₁) + E_Np·D(t, T; λ₁, λ₂)]

with `A` an [`Activation`](@ref) profile at the U-239 decay rate and `D` a
[`DoubleDecay`](@ref) profile through Np-239. Named in ANS-5.1.

Source: Python STREAM decay_heat/actinides.py `contribution`.

# Arguments
- `R`: neutron captures in U-238 per fission event at operation time [1/fission]

# Returns
An [`AbstractDecayHeat`](@ref) whose value is in MeV/fission.
"""
struct Actinides <: AbstractDecayHeat
    R::Float64
end

const _U239_PROFILE = Activation(U239_DECAY_RATE)
const _NP239_PROFILE = DoubleDecay(U239_DECAY_RATE, NP239_DECAY_RATE)

function (model::Actinides)(t, T=Inf)
    return model.R * (E_U239 * _U239_PROFILE(t, T) + E_NP239 * _NP239_PROFILE(t, T))
end
