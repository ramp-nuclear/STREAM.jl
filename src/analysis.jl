# analysis.jl — Post-processing framework for nuclear safety threshold analysis
#
# Bridges MTK solver output (NonlinearSolution or ODESolution) to the physics
# correlation functions in src/physical_models/threshold_analysis.jl.
#
# Public API:
#   ChannelState          — struct holding all pre-extracted MTK solution fields
#   threshold_analysis    — dispatcher: extracts ChannelState, calls user-supplied analysis fns
#   chfr                  — factory: returns CHF ratio closure with direction + guard
#   ONB_temperature       — wrapper: Bergles_Rohsenow_T_ONB per cell
#   boiling_onset_power   — wrapper: q_boiling_onset per cell
#   OFI_power             — wrapper: q_OFI_whittle_forgan (scalar result)
#   OSV_flux              — wrapper: q_OSV_saha_zuber (scalar result)
#   Sudo_Kaminaga_CHF     — wrapper: q_CHF_sudo_kaminaga per cell
#   Mirshak_CHF           — wrapper: q_CHF_mirshak per cell
#   Fabrega_CHF           — wrapper: q_CHF_fabrega per cell
#   twall_limit(::ChannelState; ...) — method overload on ChannelState

"""
    ChannelState

Pre-extracted MTK solution fields for a single channel system.
Used as the input to all pre-built analysis wrappers and `threshold_analysis`.

For **steady-state** solutions, each vector field has length `n` (one value per axial cell).
For **transient** solutions, each field that was `AbstractVector` becomes `AbstractMatrix`
with shape `[n_cells, n_times]` — broadcasting in wrappers handles both uniformly.

# Fields
- `n::Int`                     — number of axial cells
- `T_bulk::AbstractArray`     — bulk coolant temperature per cell [K]
- `T_wall::AbstractArray`     — conservative wall temperature: `max(T_wall_left, T_wall_right)` per cell [K]
- `T_wall_left::AbstractArray`  — left face wall temperature per cell [K]
- `T_wall_right::AbstractArray` — right face wall temperature per cell [K]
- `T_sat::AbstractArray`      — saturation temperature per cell [K]
- `T_ONB::AbstractArray`      — onset of nucleate boiling temperature per cell [K]
- `T_inlet::Float64`           — inlet temperature from `port_in.T` [K]
- `P::AbstractArray`          — absolute pressure per cell [Pa]
- `q_flux::AbstractArray`     — conservative heat flux: `max(q_flux_left, q_flux_right)` per cell [W/m²]
- `q_flux_left::AbstractArray`  — left face heat flux per cell [W/m²]
- `q_flux_right::AbstractArray` — right face heat flux per cell [W/m²]
- `mdot::Float64`              — mass flow rate from `port_in.mdot` [kg/s]
- `velocity::AbstractArray`   — absolute fluid velocity per cell [m/s]
- `pipe::Union{PipeGeometry, Nothing}` — channel geometry, or `nothing` if unavailable
- `gravity::Float64`           — gravitational acceleration [m/s²]
"""
#! format: off
@kwdef struct ChannelState
    n             ::Int
    T_bulk        ::AbstractArray
    T_wall        ::AbstractArray
    T_wall_left   ::AbstractArray
    T_wall_right  ::AbstractArray
    T_sat         ::AbstractArray
    T_ONB         ::AbstractArray
    T_inlet       ::Float64
    P             ::AbstractArray
    q_flux        ::AbstractArray
    q_flux_left   ::AbstractArray
    q_flux_right  ::AbstractArray
    mdot          ::Float64
    velocity      ::AbstractArray
    pipe          ::Union{PipeGeometry, Nothing}
    gravity       ::Float64
end
#! format: on

# #### Private helper

"""
    _extract_channel_state(sol, channel_sys; pipe=nothing, gravity=9.81) -> ChannelState

Extract MTK solution data from `sol` for `channel_sys` into a `ChannelState` bundle.

For steady-state solutions (`NonlinearSolution` or single-timestep `ODESolution`),
all vector fields have length `n`. For transient solutions, each per-cell field is
assembled into a matrix of shape `[n_cells, n_times]`.

`q_flux_left[i] = q_wall_left[i] / (pipe.heated_parts[1] * dz)` per D-05.
When `pipe` is `nothing`, all `q_flux_*` fields are zeros.
"""
function _extract_channel_state(sol, channel_sys; pipe=nothing, gravity=9.81)
    # Determine n from the length of the T array
    n = length(channel_sys.T)

    # Detect steady vs transient: a NonlinearSolution has no time field.
    is_transient = hasproperty(sol, :t) && length(sol.t) > 1

    #! format: off
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
        T_inlet_val = sol[channel_sys.port_in.T, 1]
        mdot_val = sol[channel_sys.port_in.mdot, 1]
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
        T_inlet_val = sol[channel_sys.port_in.T]
        mdot_val = sol[channel_sys.port_in.mdot]
    end
    #! format: on

    # Conservative wall temperature: max of left and right face
    T_wall = max.(T_wall_left, T_wall_right)

    # q_flux conversion: q_wall [W] -> q_flux [W/m²] per D-05
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

    #! format: off
    return ChannelState(
        n            = n,
        T_bulk       = T_bulk,
        T_wall       = T_wall,
        T_wall_left  = T_wall_left,
        T_wall_right = T_wall_right,
        T_sat        = T_sat_arr,
        T_ONB        = T_ONB_arr,
        T_inlet      = T_inlet_val,
        P            = P_arr,
        q_flux       = q_flux,
        q_flux_left  = q_flux_left,
        q_flux_right = q_flux_right,
        mdot         = mdot_val,
        velocity     = vel_arr,
        pipe         = pipe,
        gravity      = gravity,
    )
    #! format: on
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
- `pipe`: optional `PipeGeometry` — needed for `q_flux_*` computation and wrappers that use pipe geometry
- `gravity`: gravitational acceleration [m/s²] (default 9.81)
- `kwargs...`: named analysis functions, e.g. `chfr_mirshak=chfr(Mirshak_CHF), onb=ONB_temperature`

# Returns
`NamedTuple` with the same keys as `kwargs`, each containing the result of the corresponding function.

# Example
```julia
result = threshold_analysis(sol, ssys.cac;
    pipe=pipe, gravity=9.81,
    chfr_mirshak = chfr(Mirshak_CHF),
    onb          = ONB_temperature,
)
result.chfr_mirshak  # Vector{Float64} of CHF ratios per cell
result.onb           # Vector{Float64} of ONB temperatures per cell
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
- `chf_fn`: a callable `(state::ChannelState) -> AbstractArray` — any CHF wrapper function,
  e.g. `Mirshak_CHF`, `Sudo_Kaminaga_CHF`, `Fabrega_CHF`
- `direction`: which face's heat flux to use as denominator:
  - `:max` (default) — `max.(q_flux_left, q_flux_right)` (most conservative)
  - `:left`  — `state.q_flux_left`
  - `:right` — `state.q_flux_right`
  - `:total` — `state.q_flux` (same as `:max` per D-04, but named separately for clarity)

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
    ONB_temperature(state::ChannelState) -> AbstractArray

Onset of Nucleate Boiling wall temperature per cell using Bergles-Rohsenow (1964).

Calls `Bergles_Rohsenow_T_ONB.(state.P, state.q_flux, state.T_sat)`.

# Arguments
- `state`: extracted channel state

# Returns
Vector (or matrix for transient) of `T_ONB` wall temperatures [K] per cell.
"""
function ONB_temperature(state::ChannelState)
    return Bergles_Rohsenow_T_ONB.(state.P, state.q_flux, state.T_sat)
end

"""
    boiling_onset_power(state::ChannelState) -> AbstractArray

Channel power at which the bulk coolant reaches saturation temperature per cell.

Calls `q_boiling_onset.(state.mdot, state.T_sat, state.T_inlet, cp_water.(state.T_bulk))`.

# Arguments
- `state`: extracted channel state

# Returns
Vector (or matrix for transient) of boiling onset power limits [W] per cell.
"""
function boiling_onset_power(state::ChannelState)
    return q_boiling_onset.(state.mdot, state.T_sat, state.T_inlet, cp_water.(state.T_bulk))
end

"""
    OFI_power(state::ChannelState) -> Float64

Channel power at Onset of Flow Instability (OFI) per Whittle-Forgan / Fabréga.
Returns a scalar (single value for the whole channel, not per cell).

Requires `state.pipe !== nothing`.

Calls `q_OFI_whittle_forgan(state.mdot, state.T_sat[1], state.T_inlet, state.pipe)`.

# Arguments
- `state`: extracted channel state (must have `pipe` set)

# Returns
OFI power limit [W] for the channel.
"""
function OFI_power(state::ChannelState)
    T_sat_rep = state.T_sat isa AbstractMatrix ? state.T_sat[1, 1] : state.T_sat[1]
    return q_OFI_whittle_forgan(state.mdot, T_sat_rep, state.T_inlet, state.pipe)
end

"""
    OSV_flux(state::ChannelState) -> Float64

Onset of Significant Void (OSV) heat flux per Saha-Zuber self-consistent formulation.
Returns a scalar (minimum over all cells — most conservative).

Requires `state.pipe !== nothing`.

Calls `q_OSV_saha_zuber(state.T_inlet, state.mdot, state.pipe)`.

# Arguments
- `state`: extracted channel state (must have `pipe` set)

# Returns
OSV heat flux limit [W/m²] (minimum over all channel cells).
"""
function OSV_flux(state::ChannelState)
    return q_OSV_saha_zuber(state.T_inlet, state.mdot, state.pipe)
end

"""
    Sudo_Kaminaga_CHF(state::ChannelState) -> AbstractArray

Critical Heat Flux per Sudo-Kaminaga (1998) plate-type fuel correlation, per cell.

Calls `q_CHF_sudo_kaminaga.(state.T_bulk, state.mdot, state.pipe, state.gravity)`.

# Arguments
- `state`: extracted channel state (must have `pipe` set)

# Returns
Vector (or matrix for transient) of CHF heat fluxes [W/m²] per cell.
"""
function Sudo_Kaminaga_CHF(state::ChannelState)
    return q_CHF_sudo_kaminaga.(state.T_bulk, state.mdot, Ref(state.pipe), state.gravity)
end

"""
    Mirshak_CHF(state::ChannelState) -> AbstractArray

Critical Heat Flux per Mirshak et al. (1959) correlation (valid for v > 1.5 m/s), per cell.

Calls `q_CHF_mirshak.(state.T_bulk, state.T_sat, state.P, state.velocity)`.

# Arguments
- `state`: extracted channel state

# Returns
Vector (or matrix for transient) of CHF heat fluxes [W/m²] per cell.
"""
function Mirshak_CHF(state::ChannelState)
    return q_CHF_mirshak.(state.T_bulk, state.T_sat, state.P, state.velocity)
end

"""
    Fabrega_CHF(state::ChannelState) -> AbstractArray

Critical Heat Flux per Fabréga (1971) correlation (valid for v < 0.5 m/s), per cell.

Calls `q_CHF_fabrega.(state.T_inlet, state.T_sat, state.pipe)`.

# Arguments
- `state`: extracted channel state (must have `pipe` set)

# Returns
Vector (or matrix for transient) of CHF heat fluxes [W/m²] per cell.
"""
function Fabrega_CHF(state::ChannelState)
    return q_CHF_fabrega.(state.T_inlet, state.T_sat, Ref(state.pipe))
end

"""
    twall_limit(state::ChannelState; inhomogeneity_factor=1.0) -> AbstractArray

Effective wall temperature limit per cell accounting for spatial inhomogeneity.
This is a `ChannelState` method overload on the physics-layer `twall_limit(T_wall, factor)`.

Calls `twall_limit.(state.T_wall, inhomogeneity_factor)`.

# Arguments
- `state`: extracted channel state
- `inhomogeneity_factor`: dimensionless hot-spot multiplier (default 1.0, no correction)

# Returns
Vector (or matrix for transient) of effective wall temperature limits [K] per cell.
"""
function twall_limit(state::ChannelState; inhomogeneity_factor=1.0)
    return twall_limit.(state.T_wall, inhomogeneity_factor)
end
