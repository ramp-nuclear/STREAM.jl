"""
    _PROFILE_CUTOFF

Prompt power below which [`Fissions`](@ref) stores an exact zero, `1e-12` of the operating
power. Deep into a shutdown the solved profile is numerical noise around zero, and a
negative sample there would show up as a negative heat source.
"""
const _PROFILE_CUTOFF = 1e-12

"""
    ProfileInterpolation

How [`Fissions`](@ref) fills in between the samples of its profile: [`LogLinear`](@ref) or
[`Linear`](@ref).
"""
abstract type ProfileInterpolation end

"""
    LogLinear <: ProfileInterpolation

Interpolate the logarithm of the profile, `y = y₀·(y₁/y₀)^w`.

A shut-down fission rate is a sum of decaying exponentials, so this is exact for a single
exponential and close to it for the delayed groups together. Segments with a zero endpoint
fall back to [`Linear`](@ref), a zero having no logarithm.
"""
struct LogLinear <: ProfileInterpolation end

"""
    Linear <: ProfileInterpolation

Interpolate the profile on a straight line, `y = y₀ + w·(y₁ - y₀)`.

Matches `numpy.interp`, so this is the mode to pick when comparing against Python STREAM.
"""
struct Linear <: ProfileInterpolation end

"""
    _interp(mode, x, xs, ys)

Interpolate `ys` over the increasing grid `xs` under `mode`, held flat outside it.

Both modes agree at the samples and differ only between them.
"""
function _interp(mode::ProfileInterpolation, x, xs, ys)
    x <= first(xs) && return first(ys)
    x >= last(xs) && return last(ys)

    i = searchsortedlast(xs, x)
    w = (x - xs[i]) / (xs[i + 1] - xs[i])
    return _blend(mode, ys[i], ys[i + 1], w)
end

_blend(::Linear, y₀, y₁, w) = y₀ + w * (y₁ - y₀)

function _blend(::LogLinear, y₀, y₁, w)
    # `_PROFILE_CUTOFF` leaves exact zeros in a fully decayed tail, and zero has no
    # logarithm. A straight line is what is left, and it is exact when both ends are zero.
    (y₀ <= 0 || y₁ <= 0) && return _blend(Linear(), y₀, y₁, w)

    return exp(muladd(w, log(y₁) - log(y₀), log(y₀)))
end

"""
    Fissions(times, profile; interpolation=LogLinear()) <: AbstractDecayHeat
    Fissions(times, rho_c_fn; interpolation, Lambda, beta_k, lambda_k, ...)

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

# Interpolation, and how far to trust it

The default is [`LogLinear`](@ref), which departs from Python STREAM. Python evaluates the
profile with `numpy.interp`, a straight line between samples, but the quantity being
interpolated is a sum of decaying exponentials, where a straight line always overshoots. On
a step insertion of -0.005 sampled over 100 s at 50 points, the straight line is off by up
to 12% past the first interval against a grid eight times finer, where interpolating the
logarithm is off by 3.6%; past the fifth interval it is 3.2% against 0.29%. For one
exponential the log form is exact. Pass [`Linear`](@ref) to reproduce Python.

Neither mode rescues a grid that is too coarse across the prompt drop. Under that same
insertion the first 2 s interval falls by a factor of about 10, and both modes are then
wrong by more than 100% inside it. Sample `times` densely near shutdown, or on a log grid,
if the first seconds matter.

Source: Python STREAM decay_heat/fissions.py `profile`.

# Arguments
- `times`: the increasing grid the profile is sampled on [s]
- `profile`: prompt power at each of `times`, normalized to 1 at the operating point
- `rho_c_fn`: control reactivity, a callable or a `ReactivityController`, as
  [`PointKinetics`](@ref) takes it

# Keywords
- `interpolation`: [`LogLinear`](@ref) (default) or [`Linear`](@ref)
- `Lambda`, `beta_k`, `lambda_k`: kinetic parameters, defaulting to the U235 values
- `kwargs...`: forwarded to `solve_transient`

# Returns
An [`AbstractDecayHeat`](@ref) whose value is dimensionless.

# Throws
- `DimensionMismatch`: if `times` and `profile` differ in length
"""
struct Fissions{I<:ProfileInterpolation} <: AbstractDecayHeat
    times::Vector{Float64}
    profile::Vector{Float64}
    interpolation::I

    function Fissions(
        times::AbstractVector, profile::AbstractVector, interpolation::I
    ) where {I<:ProfileInterpolation}
        if length(times) != length(profile)
            throw(DimensionMismatch("times has $(length(times)) points, \
                                     profile has $(length(profile))"))
        end
        return new{I}(collect(Float64, times), collect(Float64, profile), interpolation)
    end
end

function Fissions(
    times::AbstractVector, profile::AbstractVector; interpolation=LogLinear()
)
    return Fissions(times, profile, interpolation)
end

function Fissions(
    times::AbstractVector,
    rho_c_fn;
    Lambda=U235_LAMBDA,
    beta_k=U235_BETA_K,
    lambda_k=U235_LAMBDA_K,
    interpolation=LogLinear(),
    kwargs...,
)
    @named pk = PointKinetics(rho_c_fn; Lambda=Lambda, beta_k=beta_k, lambda_k=lambda_k)
    ssys = mtkcompile(pk)
    # Unit operating power, so the sampled trajectory is already the normalized profile.
    ic = point_kinetics_steady_state(1.0; Lambda=Lambda, beta_k=beta_k, lambda_k=lambda_k)
    op = Pair{Any,Any}[
        ssys.rho_c_fn => rho_c_fn,
        ssys.P_neutron => ic.P_neutron,
        (ssys.C[k] => ic.C_k[k] for k in eachindex(ic.C_k))...,
    ]

    sol = STREAM.solve_transient(ssys, op, times; kwargs...)
    profile = sol[ssys.P_neutron, :]
    profile[profile .< _PROFILE_CUTOFF] .= 0.0

    return Fissions(times, profile, interpolation)
end

(model::Fissions)(t, T=Inf) = _interp(model.interpolation, t, model.times, model.profile)
