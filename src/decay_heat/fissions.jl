"""
    _PROFILE_CUTOFF

Prompt power below which [`Fissions`](@ref) stores an exact zero, `1e-12` of the operating
power. Deep into a shutdown the solved profile is numerical noise around zero, and a
negative sample there would show up as a negative heat source.
"""
const _PROFILE_CUTOFF = 1e-12

"""
    _interp(x, xs, ys)

Linear interpolation of `ys` over the increasing grid `xs`, held flat outside it.

Matches `numpy.interp`, which is what Python STREAM evaluates a fission profile with.
"""
function _interp(x, xs, ys)
    x <= first(xs) && return first(ys)
    x >= last(xs) && return last(ys)

    i = searchsortedlast(xs, x)
    slope = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
    return ys[i] + slope * (x - xs[i])
end

"""
    Fissions(times, profile) <: AbstractDecayHeat
    Fissions(times, rho_c_fn; Lambda, beta_k, lambda_k, kwargs...) <: AbstractDecayHeat

The fission rate itself once the reactor is shut down, `F(t) = P(t)`.

Shutting a reactor down does not stop fission. The neutron population follows the delayed
groups down, so for the first minutes the fissions still happening are a source in their own
right, on top of the decays that [`FissionProducts`](@ref) and the rest cover.

`P(t)` comes from a point-kinetics solve normalized to 1 at the operating point, so it is
dimensionless. Multiply by the energy a fission deposits in the component to get
MeV/fission, as in `Q_prompt * fis`.

The second form runs the solve: it builds a [`PointKinetics`](@ref) driven by `rho_c_fn`,
starts it from criticality at unit power, and samples it on `times`. Solving once and
interpolating afterwards is what keeps this cheap to evaluate, which is the same trade
Python STREAM makes. The first form takes an already-sampled profile.

`T`, the operation time, is accepted for the [`AbstractDecayHeat`](@ref) contract and
ignored, as in Python.

Source: Python STREAM decay_heat/fissions.py `profile`.

# Arguments
- `times`: the increasing grid the profile is sampled on [s]
- `profile`: prompt power at each of `times`, normalized to 1 at the operating point
- `rho_c_fn`: control reactivity, a callable or a `ReactivityController`, as
  [`PointKinetics`](@ref) takes it

# Keywords
- `Lambda`, `beta_k`, `lambda_k`: kinetic parameters, defaulting to the U-235 values
- `kwargs...`: forwarded to `solve_transient`

# Returns
An [`AbstractDecayHeat`](@ref) whose value is dimensionless.

# Throws
- `DimensionMismatch`: if `times` and `profile` differ in length
"""
struct Fissions <: AbstractDecayHeat
    times::Vector{Float64}
    profile::Vector{Float64}

    function Fissions(times::AbstractVector, profile::AbstractVector)
        if length(times) != length(profile)
            throw(DimensionMismatch("times has $(length(times)) points, \
                                     profile has $(length(profile))"))
        end
        return new(collect(Float64, times), collect(Float64, profile))
    end
end

function Fissions(
    times::AbstractVector,
    rho_c_fn;
    Lambda=U235_LAMBDA,
    beta_k=U235_BETA_K,
    lambda_k=U235_LAMBDA_K,
    kwargs...,
)
    @named pk = PointKinetics(rho_c_fn; Lambda=Lambda, beta_k=beta_k, lambda_k=lambda_k)
    ssys = mtkcompile(pk)
    # Unit operating power, so the sampled trajectory is already the normalized profile.
    ic = point_kinetics_steady_state(1.0; Lambda=Lambda, beta_k=beta_k, lambda_k=lambda_k)
    op = Pair{Any,Any}[
        ssys.rho_c_fn => rho_c_fn,
        ssys.P => ic.P,
        (ssys.C[k] => ic.C_k[k] for k in eachindex(ic.C_k))...,
    ]

    sol = STREAM.solve_transient(ssys, op, times; kwargs...)
    profile = sol[ssys.P, :]
    profile[profile .< _PROFILE_CUTOFF] .= 0.0

    return Fissions(times, profile)
end

(model::Fissions)(t, T=Inf) = _interp(t, model.times, model.profile)
