# analysis.jl -- Post-processing framework for nuclear safety threshold analysis
#
# Bridges MTK solver output (NonlinearSolution or ODESolution) to the physics
# correlation functions in src/physical_models/thresholds.jl.
#
# Public API:
#   ChannelState       — the solution fields a threshold correlation needs, pre-extracted
#   threshold_analysis — extracts a ChannelState and applies the functions you name
#   chfr               — CHF ratio closure, with face selection and a zero-flux guard
#
# Each correlation in thresholds.jl also gains a ChannelState method here, so the state is
# just another way to call it rather than a parallel set of names.

"""
    ChannelState

Pre-extracted MTK solution fields for a single channel system.
Used as the input to all pre-built analysis wrappers and `threshold_analysis`.

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

# #### Private helper

"""
    _extract_channel_state(sol, channel_sys; pipe=nothing, gravity=9.81) -> ChannelState

Extract MTK solution data from `sol` for `channel_sys` into a `ChannelState` bundle.

For steady-state solutions (`NonlinearSolution` or single-timestep `ODESolution`),
all vector fields have length `n`. For transient solutions, each per-cell field is
assembled into a matrix of shape `[n_cells, n_times]`.

`q_flux_left[i] = q_wall_left[i] / (pipe.heated_parts[1] * dz)`.
When `pipe` is `nothing`, all `q_flux_*` fields are zeros.
"""
function _extract_channel_state(sol, channel_sys; pipe=nothing, gravity=9.81)
    # Determine n from the length of the T array
    n = length(channel_sys.T)

    # Detect steady vs transient: a NonlinearSolution has no time field.
    is_transient = hasproperty(sol, :t) && length(sol.t) > 1

    if is_transient
        # Transient: assemble [n_cells, n_times] matrices
        T_bulk = hcat([sol[channel_sys.T[i], :] for i in 1:n]...)'
        T_wall_left = hcat([sol[channel_sys.T_wall_left[i], :] for i in 1:n]...)'
        T_wall_right = hcat([sol[channel_sys.T_wall_right[i], :] for i in 1:n]...)'
        T_sat_arr = hcat([sol[channel_sys.T_sat[i], :] for i in 1:n]...)'
        T_ONB_arr = hcat([sol[channel_sys.T_ONB[i], :] for i in 1:n]...)'
        P_arr = hcat([sol[channel_sys.P[i], :] for i in 1:n]...)'
        vel_arr = hcat([sol[channel_sys.velocity[i], :] for i in 1:n]...)'
        qwl_arr = hcat([sol[channel_sys.q_wall_left[i], :] for i in 1:n]...)'
        qwr_arr = hcat([sol[channel_sys.q_wall_right[i], :] for i in 1:n]...)'
        # Scalar fields: use first time point
        T_inlet_val = sol[channel_sys.inlet.T, 1]
        ṁ_val = sol[channel_sys.inlet.ṁ, 1]
    else
        # Steady state: scalar per cell
        T_bulk = [sol[channel_sys.T[i]] for i in 1:n]
        T_wall_left = [sol[channel_sys.T_wall_left[i]] for i in 1:n]
        T_wall_right = [sol[channel_sys.T_wall_right[i]] for i in 1:n]
        T_sat_arr = [sol[channel_sys.T_sat[i]] for i in 1:n]
        T_ONB_arr = [sol[channel_sys.T_ONB[i]] for i in 1:n]
        P_arr = [sol[channel_sys.P[i]] for i in 1:n]
        vel_arr = [sol[channel_sys.velocity[i]] for i in 1:n]
        qwl_arr = [sol[channel_sys.q_wall_left[i]] for i in 1:n]
        qwr_arr = [sol[channel_sys.q_wall_right[i]] for i in 1:n]
        T_inlet_val = sol[channel_sys.inlet.T]
        ṁ_val = sol[channel_sys.inlet.ṁ]
    end

    # Conservative wall temperature: max of left and right face
    T_wall = max.(T_wall_left, T_wall_right)

    # q_flux conversion: q_wall [W] -> q_flux [W/m²]
    if pipe !== nothing
        dz = pipe.L / n
        q_flux_left = qwl_arr ./ (pipe.heated_parts[1] * dz)
        q_flux_right = qwr_arr ./ (pipe.heated_parts[2] * dz)
    else
        q_flux_left = zero(T_bulk)
        q_flux_right = zero(T_bulk)
    end

    # Conservative q_flux: max of both faces
    q_flux = max.(q_flux_left, q_flux_right)

    return ChannelState(;
        n=n,
        T_bulk=T_bulk,
        T_wall=T_wall,
        T_wall_left=T_wall_left,
        T_wall_right=T_wall_right,
        T_sat=T_sat_arr,
        T_ONB=T_ONB_arr,
        T_inlet=T_inlet_val,
        P=P_arr,
        q_flux=q_flux,
        q_flux_left=q_flux_left,
        q_flux_right=q_flux_right,
        ṁ=ṁ_val,
        velocity=vel_arr,
        pipe=pipe,
        gravity=gravity,
    )
end

"""
    threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...) -> NamedTuple

Post-process an MTK solution by extracting channel state and applying user-specified
analysis functions.

Each keyword argument must be a callable `fn(state::ChannelState) -> AbstractArray`.
The function calls `_extract_channel_state` to build the `ChannelState`, then dispatches
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
    state = _extract_channel_state(sol, channel_sys; pipe=pipe, gravity=gravity)
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
