"""
    ChannelState

One channel's solved state, in the form the threshold correlations take.

Construct it from a solution with [`ChannelState(sol, channel_sys)`](@ref), or by hand with
keywords. Every correlation in `Thresholds` accepts one, as does [`threshold_analysis`](@ref).

It describes one instant, so each per-cell field has length `n`, one value per axial cell.
For a transient, [`ChannelState(sol, channel_sys; index=k)`](@ref) reads the saved time
`sol.t[k]`, and [`threshold_analysis`](@ref) runs the correlations at every saved time.

# Fields
- `n::Int`: number of axial cells
- `T_bulk::AbstractArray`: bulk coolant temperature per cell [°C]
- `T_wall::AbstractArray`: the hotter face, `max(T_wall_left, T_wall_right)`, per cell [°C]
- `T_wall_left::AbstractArray`: left face wall temperature per cell [°C]
- `T_wall_right::AbstractArray`: right face wall temperature per cell [°C]
- `T_sat::AbstractArray`: saturation temperature per cell [°C]
- `T_ONB::AbstractArray`: onset of nucleate boiling temperature per cell [°C]
- `T_inlet::Float64`: inlet temperature from `inlet.T` [°C]
- `P::AbstractArray`: absolute pressure per cell [Pa]
- `q_flux::AbstractArray`: the larger face flux, `max(q_flux_left, q_flux_right)` [W/m²]
- `q_flux_left::AbstractArray`: left face heat flux per cell [W/m²]
- `q_flux_right::AbstractArray`: right face heat flux per cell [W/m²]
- `ṁ::Float64`: mass flow rate from `inlet.ṁ` [kg/s]
- `velocity::AbstractArray`: absolute fluid velocity per cell [m/s]
- `pipe::Union{PipeGeometry, Nothing}`: channel geometry, or `nothing` if unavailable
- `gravity::Float64`: gravitational acceleration [m/s²]
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
    _instant(sol, index) -> Union{Int,Nothing}

The saved-time index a [`ChannelState`](@ref) reads `sol` at: `nothing` for a solution with
no time axis, `index` for a transient, and `1` for a transient that saved a single point.

# Throws
- `ArgumentError`: for a transient with several saved times and no `index`
"""
function _instant(sol, index)
    hasproperty(sol, :t) || return nothing
    index === nothing || return index
    length(sol.t) == 1 && return 1
    throw(
        ArgumentError(
            "sol is a transient with $(length(sol.t)) saved times, so a ChannelState " *
            "needs the index of one; threshold_analysis reads every saved time",
        ),
    )
end

"""
    ChannelState(sol, channel_sys; pipe=nothing, gravity=9.81, index=nothing)

Read one channel's state at one instant out of a solution.

A steady solution has a single instant, so `index` is not needed. A transient needs `index`,
the position of a saved time in `sol.t`. To run the correlations over a whole transient, use
[`threshold_analysis`](@ref), which builds a `ChannelState` at every saved time.

`q_flux_left[i] = q_wall_left[i] / (pipe.heated_parts[1] * dz)`.
When `pipe` is `nothing`, all `q_flux_*` fields are zeros.

`channel_sys` must expose a wall temperature, so `Channel` or `ChannelAndContacts`.
`ChannelHeatFlux` prescribes its flux and leaves `T_wall_left`/`T_wall_right` unconstrained for
`mtkcompile` to drop.

# Arguments
- `sol`: a `NonlinearSolution` or an `ODESolution`
- `channel_sys`: the compiled channel subsystem, such as `ssys.ch`
- `pipe`: the channel's `PipeGeometry`, needed for the fluxes and geometric correlations
- `gravity`: gravitational acceleration [m/s²]
- `index`: which saved time of a transient to read

# Returns
A `ChannelState` for that instant.

# Throws
- `ArgumentError`: for a transient with several saved times and no `index`, or a channel
  whose wall temperature did not survive compilation
"""
function ChannelState(sol, channel_sys; pipe=nothing, gravity=9.81, index=nothing)
    n = length(channel_sys.T)
    k = _instant(sol, index)
    value(sym) = k === nothing ? sol[sym] : sol[sym, k]
    cells(sym) = [value(sym[i]) for i in 1:n]

    # `velocity` is the unsigned speed and only ChannelAndContacts declares it. The other
    # variants expose the signed `v`, so read that and take the magnitude, which is what lets a
    # plain Channel be analyzed too.
    signed_velocity = !hasproperty(channel_sys, :velocity)
    velocity = cells(signed_velocity ? channel_sys.v : channel_sys.velocity)
    signed_velocity && (velocity = abs.(velocity))

    # Every variant declares T_wall_left/T_wall_right, but only the ones that also close them
    # keep them through mtkcompile, so the read is where a wall-less channel shows up. The bare
    # "not present in the system" that MTK raises does not say which channel or why.
    T_wall_left, T_wall_right = try
        cells(channel_sys.T_wall_left), cells(channel_sys.T_wall_right)
    catch err
        err isa ArgumentError || rethrow()
        throw(
            ArgumentError(
                "no wall temperature survived compilation in $(nameof(channel_sys)), so a " *
                "ChannelState cannot be built from it. ChannelHeatFlux prescribes its heat " *
                "flux and leaves T_wall_left and T_wall_right with no equation, which " *
                "mtkcompile then drops. Threshold analysis wants Channel or " *
                "ChannelAndContacts. MTK said: $(err.msg)",
            ),
        )
    end

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
        T_inlet=value(channel_sys.inlet.T),
        P=cells(channel_sys.P),
        q_flux=max.(q_flux_left, q_flux_right),
        q_flux_left=q_flux_left,
        q_flux_right=q_flux_right,
        ṁ=value(channel_sys.inlet.ṁ),
        velocity=velocity,
        pipe=pipe,
        gravity=gravity,
    )
end

"""
    threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...) -> NamedTuple

Apply named threshold functions to one channel of a solution.

Each keyword argument is a callable `fn(state::ChannelState)` returning a value per cell or
one for the whole channel. For a steady solution each runs once. For a transient each runs
on the [`ChannelState`](@ref) at every saved time, so a flow-dependent correlation sees the
flow at that time, and the results stack along a last axis: a per-cell result becomes an
`[n_cells, n_times]` matrix and a channel-level one a vector over time, both against
`sol.t`.

# Arguments
- `sol`: a `NonlinearSolution` (steady) or an `ODESolution` (transient)
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
result.chfr_mirshak                           # CHF ratio per cell, and per time
worst_case(result.chfr_mirshak; times=sol.t)  # the smallest, and where and when
```
"""
function threshold_analysis(sol, channel_sys; pipe=nothing, gravity=9.81, kwargs...)
    state_at(k) = ChannelState(sol, channel_sys; pipe=pipe, gravity=gravity, index=k)
    fns = Base.values(kwargs)
    results = if hasproperty(sol, :t) && length(sol.t) > 1
        states = [state_at(k) for k in eachindex(sol.t)]
        [stack(fn(s) for s in states) for fn in fns]
    else
        state = state_at(nothing)
        [fn(state) for fn in fns]
    end
    return NamedTuple{keys(kwargs)}(Tuple(results))
end

"""
    worst_case(margin; times=nothing) -> NamedTuple

The smallest value of a margin field, and where it sits.

Pass a quantity arranged so that larger is safer, such as a CHF ratio or `T_ONB - T_wall`,
in the shape [`threshold_analysis`](@ref) returns: a per-cell vector for a steady solution,
an `[n_cells, n_times]` matrix for a transient, or a vector over time for a channel-level
correlation. A vector is read as per-time when `times` is given and per-cell when it is not.

# Arguments
- `margin`: the field to search

# Keywords
- `times`: the saved times, `sol.t`

# Returns
`(value, cell, time)`: the minimum, the cell holding it (`nothing` for a per-time field),
and the time it occurs (its index when `times` is not given, `nothing` for a steady field).
"""
function worst_case(margin::AbstractMatrix; times=nothing)
    value, idx = findmin(margin)
    cell, k = Tuple(idx)
    return (value=value, cell=cell, time=times === nothing ? k : times[k])
end

function worst_case(margin::AbstractVector; times=nothing)
    value, i = findmin(margin)
    times === nothing && return (value=value, cell=i, time=nothing)
    return (value=value, cell=nothing, time=times[i])
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
        # Broadcast rather than zip: a channel-level correlation such as
        # q_CHF_sudo_kaminaga gives one number for the whole channel, and it has to divide
        # into the per-cell flux just the same.
        return ifelse.(q .> 0, chf_fn(state) ./ q, Inf)
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
for them. Results come back per cell; [`threshold_analysis`](@ref) stacks them over time.

`q_OFI_whittle_forgan` and `q_OSV_saha_zuber` return one number for the whole channel: the
first is a channel power, the second reports the most conservative cell. Those two and the
two geometry-dependent CHF correlations need `state.pipe`.

`q_OFI_whittle_forgan` reads its saturation temperature from the downstream cell, since
pressure falls along the channel and the outlet is what limits the margin. Under reversed
flow the downstream end is the other one, and it follows.

What each correlation computes is in its own docstring.
"""
# A wall that is not heating the coolant cannot boil it, and the correlation's fractional
# power has no real value for a negative flux, so those cells report no onset, as chfr does.
# After a scram the coolant rising through the core can run hotter than parts of the plate.
function bergles_rohsenow_t_onb(s::ChannelState)
    heating = s.q_flux .> 0
    T_ONB = bergles_rohsenow_t_onb.(s.P, max.(s.q_flux, 0.0), s.T_sat)
    return ifelse.(heating, T_ONB, Inf)
end

function q_boiling_onset(s::ChannelState; liquid::AbstractLiquid=H2O)
    return q_boiling_onset.(s.ṁ, s.T_sat, s.T_inlet, cₚ.(liquid, s.T_bulk))
end

q_CHF_mirshak(s::ChannelState) = q_CHF_mirshak.(s.T_bulk, s.T_sat, s.P, s.velocity)

q_CHF_fabrega(s::ChannelState) = q_CHF_fabrega.(s.T_inlet, s.T_sat, Ref(s.pipe))

# The correlation needs saturated-coolant properties, and this is where the coolant is
# known, so the snapshot is built here: one entry per cell at that cell's saturation state.
function q_CHF_sudo_kaminaga(s::ChannelState; liquid::AbstractLiquid=H2O)
    T_sat, P = collect(s.T_sat), collect(s.P)
    return q_CHF_sudo_kaminaga(collect(s.T_bulk), s.ṁ, s.pipe, s.gravity, liquid(T_sat, P))
end

# Mirrors Python STREAM's `pressure[-1 if mdot >= 0 else 0]`.
function q_OFI_whittle_forgan(s::ChannelState; liquid::AbstractLiquid=H2O)
    T_sat_out = s.ṁ >= 0 ? last(s.T_sat) : first(s.T_sat)
    return q_OFI_whittle_forgan(s.ṁ, T_sat_out, s.T_inlet, s.pipe; liquid=liquid)
end

q_OSV_saha_zuber(s::ChannelState) = q_OSV_saha_zuber(s.T_inlet, s.ṁ, s.pipe)

function twall_limit(s::ChannelState; inhomogeneity_factor=1.0)
    limit(T_wall) = twall_limit.(s.T_bulk, T_wall, inhomogeneity_factor)
    return max.(limit(s.T_wall_left), limit(s.T_wall_right))
end

function Base.show(io::IO, ::MIME"text/plain", s::ChannelState)
    rng(v) = "$(round(minimum(v); sigdigits=5))..$(round(maximum(v); sigdigits=5))"
    print(io, "ChannelState: ", s.n, " cells")
    print(io, "\n  ṁ        ", round(s.ṁ; sigdigits=5), " kg/s")
    print(io, "\n  T_bulk   ", rng(s.T_bulk), " °C")
    print(io, "\n  T_wall   ", rng(s.T_wall), " °C")
    print(io, "\n  T_sat    ", rng(s.T_sat), " °C")
    print(io, "\n  q_flux   ", rng(s.q_flux), " W/m^2")
    print(io, "\n  pipe     ", s.pipe === nothing ? "not given (q_flux is zero)" : "given")
end
