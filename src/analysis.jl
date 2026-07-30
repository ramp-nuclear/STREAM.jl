# analysis.jl -- Post-processing framework for nuclear safety threshold analysis
#
# Bridges MTK solver output (NonlinearSolution or ODESolution) to the physics
# correlation functions in src/physical_models/thresholds.jl.
#
# Public API:
#   ChannelState       — the solution fields a threshold correlation needs; construct it
#                        from a solution with ChannelState(sol, channel_sys; pipe, gravity)
#   threshold_analysis — extracts a ChannelState and applies the functions you name
#   chfr               — CHF ratio closure, with face selection and a zero-flux guard
#
# Each correlation in thresholds.jl also gains a ChannelState method here, so the state is
# just another way to call it rather than a parallel set of names.

"""
    ChannelState

Pre-extracted MTK solution fields for a single channel system, built with
`ChannelState(sol, channel_sys; pipe, gravity)` and accepted by every threshold correlation
and by `threshold_analysis`.

For **steady-state** solutions, each vector field has length `n` (one value per axial cell).
For **transient** solutions, each field that was `AbstractVector` becomes `AbstractMatrix`
with shape `[n_cells, n_times]` — broadcasting in wrappers handles both uniformly.

# Fields
- `n::Int`                     — number of axial cells
- `T_bulk::AbstractArray`     — bulk coolant temperature per cell [°C]
- `T_wall::AbstractArray`     — conservative wall temperature: `max(T_wall_left, T_wall_right)` per cell [°C]
- `T_wall_left::AbstractArray`  — left face wall temperature per cell [°C]
- `T_wall_right::AbstractArray` — right face wall temperature per cell [°C]
- `T_sat::AbstractArray`      — saturation temperature per cell [°C]
- `T_ONB::AbstractArray`      — onset of nucleate boiling temperature per cell [°C]
- `T_inlet::Float64`           — inlet temperature from `inlet.T` [°C]
- `P::AbstractArray`          — absolute pressure per cell [Pa]
- `q_flux::AbstractArray`     — conservative heat flux: `max(q_flux_left, q_flux_right)` per cell [W/m²]
- `q_flux_left::AbstractArray`  — left face heat flux per cell [W/m²]
- `q_flux_right::AbstractArray` — right face heat flux per cell [W/m²]
- `ṁ::Float64`              — mass flow rate from `inlet.ṁ` [kg/s]
- `velocity::AbstractArray`   — absolute fluid velocity per cell [m/s]
- `pipe::Union{PipeGeometry, Nothing}` — channel geometry, or `nothing` if unavailable
- `gravity::Float64`           — gravitational acceleration [m/s²]
"""
@kwdef struct ChannelState
    n::Int
    T_bulk::AbstractArray
    T_wall::AbstractArray
    T_wall_left::AbstractArray
    T_wall_right::AbstractArray
    T_sat::AbstractArray
    T_ONB::AbstractArray
    T_inlet::Float64
    P::AbstractArray
    q_flux::AbstractArray
    q_flux_left::AbstractArray
    q_flux_right::AbstractArray
    ṁ::Float64
    velocity::AbstractArray
    pipe::Union{PipeGeometry,Nothing}
    gravity::Float64
end

"""
    ChannelState(sol, channel_sys; pipe=nothing, gravity=9.81) -> ChannelState

Extract MTK solution data from `sol` for `channel_sys` into a `ChannelState` bundle.

For steady-state solutions (`NonlinearSolution` or single-timestep `ODESolution`),
all vector fields have length `n`. For transient solutions, each per-cell field is
assembled into a matrix of shape `[n_cells, n_times]`.

`q_flux_left[i] = q_wall_left[i] / (pipe.heated_parts[1] * dz)`.
When `pipe` is `nothing`, all `q_flux_*` fields are zeros.
"""
function ChannelState(sol, channel_sys; pipe=nothing, gravity=9.81)
    n = length(channel_sys.T)
    # A NonlinearSolution has no time axis; a single-step ODESolution is steady too.
    is_transient = hasproperty(sol, :t) && length(sol.t) > 1

    # One reader for both layouts, so the field list is written once: steady gives a value
    # per cell, transient a [cell, time] matrix.
    cells(sym) = is_transient ?
        permutedims(reduce(hcat, (sol[sym[i], :] for i in 1:n))) :
        [sol[sym[i]] for i in 1:n]
    scalar(sym) = is_transient ? sol[sym, 1] : sol[sym]

    # `velocity` is the unsigned speed and only ChannelAndContacts declares it. The other
    # variants expose the signed `v`, so read that and take the magnitude, which lets a plain
    # Channel or a ChannelHeatFlux be analyzed too.
    signed_velocity = !hasproperty(channel_sys, :velocity)
    velocity = cells(signed_velocity ? channel_sys.v : channel_sys.velocity)
    signed_velocity && (velocity = abs.(velocity))

    T_wall_left = cells(channel_sys.T_wall_left)
    T_wall_right = cells(channel_sys.T_wall_right)

    # q_wall is a heat flow [W]; dividing by the face area gives the flux the correlations
    # want. Without a geometry there is no area, so the fluxes stay zero.
    q_wall_left = cells(channel_sys.q_wall_left)
    q_wall_right = cells(channel_sys.q_wall_right)
    # A face with no heated perimeter (the second face of a circular pipe, or the dangling
    # side of a one-sided channel) has no area to divide by, and its flux is zero rather than
    # 0/0. Leaving that as NaN would propagate through max() into every CHF ratio.
    function face_flux(q_wall, perimeter)
        (pipe === nothing || iszero(perimeter)) && return zero(q_wall)
        return q_wall ./ (perimeter * (pipe.L / n))
    end
    q_flux_left = face_flux(q_wall_left, pipe === nothing ? 0 : pipe.heated_parts[1])
    q_flux_right = face_flux(q_wall_right, pipe === nothing ? 0 : pipe.heated_parts[2])

    return ChannelState(;
        n=n,
        T_bulk=cells(channel_sys.T),
        # The conservative face: whichever is hotter, and whichever carries more flux.
        T_wall=max.(T_wall_left, T_wall_right),
        T_wall_left=T_wall_left,
        T_wall_right=T_wall_right,
        T_sat=cells(channel_sys.T_sat),
        T_ONB=cells(channel_sys.T_ONB),
        T_inlet=scalar(channel_sys.inlet.T),
        P=cells(channel_sys.P),
        q_flux=max.(q_flux_left, q_flux_right),
        q_flux_left=q_flux_left,
        q_flux_right=q_flux_right,
        ṁ=scalar(channel_sys.inlet.ṁ),
        velocity=velocity,
        pipe=pipe,
        gravity=gravity,
    )
end

"""
    threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...) -> NamedTuple

Post-process an MTK solution by extracting channel state and applying user-specified
analysis functions.

Each keyword argument must be a callable `fn(state::ChannelState) -> AbstractArray`.
The function builds the `ChannelState` from the solution, then dispatches
each function and collects results into a `NamedTuple`.

# Arguments
- `sol`: solver output — `NonlinearSolution` (steady) or `ODESolution` (transient)
- `channel_sys`: the compiled MTK subsystem with `T`, `T_wall_left`, `T_wall_right`, etc.
- `pipe`: optional `PipeGeometry`, needed for `q_flux_*` and any correlation that uses geometry
- `gravity`: gravitational acceleration [m/s²] (default 9.81)
- `kwargs...`: named analysis functions

# Returns
`NamedTuple` with the same keys as `kwargs`, each holding that function's result.

# Example
```julia
result = threshold_analysis(sol, ssys.cac;
    pipe=pipe, gravity=9.81,
    chfr_mirshak = chfr(q_CHF_mirshak),
    onb          = bergles_rohsenow_t_onb,
)
result.chfr_mirshak  # CHF ratio per cell
result.onb           # ONB wall temperature per cell
```
"""
function threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...)
    state = ChannelState(sol, channel_sys; pipe=pipe, gravity=gravity)
    names = keys(kwargs)
    values = [fn(state) for fn in Base.values(kwargs)]
    return NamedTuple{names}(Tuple(values))
end

"""
    chfr(chf_fn; direction=:max) -> Function

Factory that returns a CHF ratio (CHFR) closure with directional heat flux selection
and a guard for zero/negative flux.

The returned closure has signature `(state::ChannelState) -> AbstractArray`.

# Arguments
- `chf_fn`: a callable `(state::ChannelState) -> AbstractArray`, i.e. any of
  `q_CHF_mirshak`, `q_CHF_sudo_kaminaga`, `q_CHF_fabrega`
- `direction`: which face's heat flux to use as denominator:
  - `:max` (default) — `max.(q_flux_left, q_flux_right)` (most conservative)
  - `:left`  — `state.q_flux_left`
  - `:right` — `state.q_flux_right`
  - `:total` — `state.q_flux` (same as `:max`, but named separately for clarity)

# Returns
Closure `(state::ChannelState) -> Vector{Float64}` where each entry is `CHF[i] / q[i]`,
with `q[i] <= 0 → Inf` (no boiling risk when wall is not being heated).
"""
function chfr(chf_fn; direction=:max)
    return function (state::ChannelState)
        q = if direction == :left
            state.q_flux_left
        elseif direction == :right
            state.q_flux_right
        elseif direction == :max
            max.(state.q_flux_left, state.q_flux_right)
        elseif direction == :total
            state.q_flux
        else
            throw(
                ArgumentError("direction must be :left, :right, :max, or :total, got :$direction"),
            )
        end
        chf_vals = chf_fn(state)
        return [q_i > 0 ? c_i / q_i : Inf for (c_i, q_i) in zip(chf_vals, q)]
    end
end

"""
    bergles_rohsenow_t_onb(state::ChannelState)
    q_boiling_onset(state::ChannelState; liquid=H2O)
    q_CHF_mirshak(state::ChannelState)
    q_CHF_fabrega(state::ChannelState)
    q_CHF_sudo_kaminaga(state::ChannelState)
    q_OFI_whittle_forgan(state::ChannelState)
    q_OSV_saha_zuber(state::ChannelState)
    twall_limit(state::ChannelState; inhomogeneity_factor=1.0)

Every threshold correlation also accepts a solved channel, taking its arguments out of the
`ChannelState`. These are methods on the correlations themselves, not a second set of names
for them. Results come back per cell, or as `[cell, time]` for a transient.

`q_OFI_whittle_forgan` and `q_OSV_saha_zuber` return one number for the whole channel: the
first is a channel power, the second reports the most conservative cell. Those two and the
two geometry-dependent CHF correlations need `state.pipe`.

`q_OFI_whittle_forgan` reads its saturation temperature from the downstream cell, since
pressure falls along the channel and the outlet is what limits the margin. Under reversed
flow the downstream end is the other one, and it follows.

What each correlation computes is in its own docstring.
"""
bergles_rohsenow_t_onb(s::ChannelState) = bergles_rohsenow_t_onb.(s.P, s.q_flux, s.T_sat)

function q_boiling_onset(s::ChannelState; liquid::AbstractLiquid=H2O)
    return q_boiling_onset.(s.ṁ, s.T_sat, s.T_inlet, cₚ.(liquid, s.T_bulk))
end

q_CHF_mirshak(s::ChannelState) = q_CHF_mirshak.(s.T_bulk, s.T_sat, s.P, s.velocity)

q_CHF_fabrega(s::ChannelState) = q_CHF_fabrega.(s.T_inlet, s.T_sat, Ref(s.pipe))

function q_CHF_sudo_kaminaga(s::ChannelState)
    return q_CHF_sudo_kaminaga.(s.T_bulk, s.ṁ, Ref(s.pipe), s.gravity)
end

# T_sat is taken at the downstream end of the channel, where the coolant has warmed the most
# and the pressure has dropped the furthest, so it is the cell that limits OFI. Which end is
# downstream follows the flow direction. Matches Python STREAM's
# `pressure[-1 if mdot >= 0 else 0]`.
function q_OFI_whittle_forgan(s::ChannelState; liquid::AbstractLiquid=H2O)
    per_cell = s.T_sat isa AbstractMatrix ? view(s.T_sat, :, 1) : s.T_sat
    T_sat_out = s.ṁ >= 0 ? last(per_cell) : first(per_cell)
    return q_OFI_whittle_forgan(s.ṁ, T_sat_out, s.T_inlet, s.pipe; liquid=liquid)
end

q_OSV_saha_zuber(s::ChannelState) = q_OSV_saha_zuber(s.T_inlet, s.ṁ, s.pipe)

function twall_limit(s::ChannelState; inhomogeneity_factor=1.0)
    limit(T_wall) = twall_limit.(s.T_bulk, T_wall, inhomogeneity_factor)
    return max.(limit(s.T_wall_left), limit(s.T_wall_right))
end

function Base.show(io::IO, ::MIME"text/plain", s::ChannelState)
    kind = s.T_bulk isa AbstractMatrix ? "transient, $(size(s.T_bulk, 2)) time points" : "steady"
    rng(v) = "$(round(minimum(v); sigdigits=5))..$(round(maximum(v); sigdigits=5))"
    print(io, "ChannelState: ", s.n, " cells, ", kind)
    print(io, "\n  ṁ        ", round(s.ṁ; sigdigits=5), " kg/s")
    print(io, "\n  T_bulk   ", rng(s.T_bulk), " °C")
    print(io, "\n  T_wall   ", rng(s.T_wall), " °C")
    print(io, "\n  T_sat    ", rng(s.T_sat), " °C")
    print(io, "\n  q_flux   ", rng(s.q_flux), " W/m^2")
    print(io, "\n  pipe     ", s.pipe === nothing ? "not given (q_flux is zero)" : "given")
end
