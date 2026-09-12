"""
    U239_DECAY_RATE

Decay rate of U239, `4.91e-4` 1/s, from ANSI/ANS-5.1-2014. Used by
[`U238CaptureChain`](@ref).
"""
const U239_DECAY_RATE = 4.91e-4

"""
    NP239_DECAY_RATE

Decay rate of Np239, `3.41e-6` 1/s, from ANSI/ANS-5.1-2014. Used by
[`U238CaptureChain`](@ref).
"""
const NP239_DECAY_RATE = 3.41e-6

"""
    E_U239

Energy deposited per U239 decay, `0.460` MeV, from ANSI/ANS-5.1-2014. Used by
[`U238CaptureChain`](@ref).
"""
const E_U239 = 0.460

"""
    E_NP239

Energy deposited per Np239 decay, `0.405` MeV, from ANSI/ANS-5.1-2014. Used by
[`U238CaptureChain`](@ref).
"""
const E_NP239 = 0.405

"""
    U238CaptureChain(R) <: AbstractDecayHeat

Decay heat from the U239 and Np239 that neutron capture in U238 leaves behind,

    U238 --(n,γ)--> U239 --β⁻--> Np239 --β⁻--> Pu239

evaluated as

    F(t, T) = R·[E_U239·A(t, T; λ₁) + E_NP239·D(t, T; λ₁, λ₂)]

with `A` an [`Activation`](@ref) profile at the U239 decay rate and `D` a
[`DoubleDecay`](@ref) profile through Np239.

ANSI/ANS-5.1-2014 requires this term alongside the fission products and gives the decay
rates and energies used here. It is this one capture chain, not the decay heat of all
actinides, although Python STREAM calls it `actinides`.

Source: Python STREAM decay_heat/actinides.py `contribution`.

# Arguments
- `R`: neutron captures in U238 per fission event at operation time [1/fission]

# Returns
An [`AbstractDecayHeat`](@ref) whose value is in MeV/fission.
"""
struct U238CaptureChain <: AbstractDecayHeat
    R::Float64
end

const _U239_PROFILE = Activation(U239_DECAY_RATE)
const _NP239_PROFILE = DoubleDecay(U239_DECAY_RATE, NP239_DECAY_RATE)

function (model::U238CaptureChain)(t, T=Inf)
    return model.R * (E_U239 * _U239_PROFILE(t, T) + E_NP239 * _NP239_PROFILE(t, T))
end
