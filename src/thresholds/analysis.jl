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
- `T_bulk::Vector{T}`: bulk coolant temperature per cell [°C]
- `T_wall::Vector{T}`: the hottest face's wall temperature per cell [°C]
- `T_walls::NamedTuple`: each face's wall temperature per cell, by face name [°C]
- `T_sat::Vector{T}`: saturation temperature per cell [°C]
- `T_ONB::Vector{T}`: onset of nucleate boiling temperature per cell [°C]
- `T_inlet::T`: temperature of the coolant entering the channel, at whichever end is
  upstream, from the channel's `T_in` [°C]
- `P::Vector{T}`: absolute pressure per cell [Pa]
- `q_flux::Vector{T}`: the largest face heat flux per cell [W/m²]
- `q_fluxes::NamedTuple`: each face's heat flux per cell, by face name [W/m²]
- `ṁ::T`: mass flow rate from `inlet.ṁ` [kg/s]
- `velocity::Vector{T}`: absolute fluid velocity per cell [m/s]
- `duct::Union{Duct, Nothing}`: the channel's [`Duct`](@ref) in numbers, its design knobs at
  their solved values, or `nothing` for a state built by hand without one
- `gravity::T`: gravitational acceleration [m/s²]

`T` is the one number type of every field, `Float64` for a solved state and a ForwardDiff dual
for one read under [`UQ.local_sensitivities`](@ref STREAM.UQ.local_sensitivities). A state built
by hand takes the promotion of the numbers it is given.
"""
struct ChannelState{T<:Real,W<:NamedTuple,Q<:NamedTuple,G<:Union{Duct,Nothing}}
    n::Int
    T_bulk::Vector{T}
    T_wall::Vector{T}
    T_walls::W
    T_sat::Vector{T}
    T_ONB::Vector{T}
    T_inlet::T
    P::Vector{T}
    q_flux::Vector{T}
    q_fluxes::Q
    ṁ::T
    velocity::Vector{T}
    duct::G
    gravity::T
end

function ChannelState(;
    n,
    T_bulk,
    T_wall,
    T_walls=(;),
    T_sat,
    T_ONB,
    T_inlet,
    P,
    q_flux,
    q_fluxes=(;),
    ṁ,
    velocity,
    duct=nothing,
    gravity,
)
    T = promote_type(eltype.((T_bulk, T_wall, T_sat, T_ONB, T_inlet, P, q_flux, ṁ, velocity,
                              gravity))...)
    return ChannelState{T,typeof(T_walls),typeof(q_fluxes),typeof(duct)}(
        n, T_bulk, T_wall, T_walls, T_sat, T_ONB, T_inlet, P, q_flux, q_fluxes, ṁ, velocity,
        duct, gravity,
    )
end

"""
    _time_index(sol, index) -> Union{Int,Nothing}

Which saved time a [`ChannelState`](@ref) reads out of `sol`.

A steady solution is a single state with no time axis, so there is nothing to choose and this
returns `nothing`. A transient holds one state per saved time, and the caller picks one with
`index`. A transient that saved only one time needs no `index`, and gets `1`.

# Throws
- `ArgumentError`: for a transient with several saved times and no `index`, rather than
  guessing which one was meant
"""
function _time_index(sol, index)
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
    ChannelState(sol, channel_sys; gravity=G_EARTH, index=nothing)

Read one channel's state at one instant out of a solution.

A steady solution has a single instant, so `index` is not needed. A transient needs `index`,
the position of a saved time in `sol.t`. To run the correlations over a whole transient, use
[`threshold_analysis`](@ref), which builds a `ChannelState` at every saved time.

The face fluxes divide each face's heat flow by its area, read off the channel's own
[`duct`](@ref): `q_fluxes.left[i] = q_wall_left[i] / (heated.left * dz)`. A duct built from
design knobs takes the values the solution was solved at, so the geometry follows the knobs
and, under [`UQ.local_sensitivities`](@ref STREAM.UQ.local_sensitivities), carries their
derivatives.

`channel_sys` must expose a wall temperature, so `Channel` or `ChannelAndContacts`.
`ChannelHeatFlux` prescribes its flux and leaves its wall temperatures unconstrained for
`mtkcompile` to drop.

# Arguments
- `sol`: a `NonlinearSolution` or an `ODESolution`
- `channel_sys`: the compiled channel subsystem, such as `ssys.ch`
- `gravity`: gravitational acceleration [m/s²]
- `index`: which saved time of a transient to read

# Returns
A `ChannelState` for that instant.

# Throws
- `ArgumentError`: for a transient with several saved times and no `index`, a system that is
  not a STREAM channel, or a channel whose wall temperature did not survive compilation
"""
function ChannelState(sol, channel_sys; gravity=G_EARTH, index=nothing)
    n = length(channel_sys.T)
    k = _time_index(sol, index)
    value(sym) = k === nothing ? sol[sym] : sol[sym, k]
    # A duct built from design knobs holds its lengths as expressions in them, `width * gap`,
    # so they are read off the solution like every other field, duals under UQ included. A
    # knob holds through a transient, and a transient refuses a time index on a parameter.
    geometry = _map_lengths(x -> x isa Num ? sol[x] : x, duct(channel_sys))
    cells(sym) = value(scalarize(sym))

    # `velocity` is the unsigned speed and only ChannelAndContacts declares it. The other
    # variants expose the signed `v`, so read that and take the magnitude, which is what lets a
    # plain Channel be analyzed too.
    signed_velocity = !hasproperty(channel_sys, :velocity)
    velocity = cells(signed_velocity ? channel_sys.v : channel_sys.velocity)
    signed_velocity && (velocity = abs.(velocity))

    # Every variant declares a wall temperature per face, but only the ones that also close
    # it keep it through mtkcompile, so the read is where a wall-less channel shows up. The
    # bare "not present in the system" that MTK raises does not say which channel or why.
    faces = keys(geometry.heated)
    T_walls = try
        NamedTuple{faces}(map(f -> cells(getproperty(channel_sys, Symbol(:T_wall_, f))), faces))
    catch err
        err isa ArgumentError || rethrow()
        throw(
            ArgumentError(
                "no wall temperature survived compilation in $(nameof(channel_sys)), so a " *
                "ChannelState cannot be built from it. ChannelHeatFlux prescribes its heat " *
                "flux and leaves its wall temperatures with no equation, which mtkcompile " *
                "then drops. Threshold analysis wants Channel or ChannelAndContacts. " *
                "MTK said: $(err.msg)",
            ),
        )
    end

    # q_wall is a heat flow [W]; dividing by the face's area gives the flux the correlations
    # want.
    dz = geometry.L / n
    q_fluxes = NamedTuple{faces}(map(faces) do f
        cells(getproperty(channel_sys, Symbol(:q_wall_, f))) ./ (geometry.heated[f] * dz)
    end)
    # The conservative face: whichever is hotter, and whichever carries more flux.
    hottest(per_face, none) = isempty(per_face) ? fill(none, n) :
                                                  reduce((a, b) -> max.(a, b), per_face)

    return ChannelState(;
        n=n,
        T_bulk=cells(channel_sys.T),
        T_wall=hottest(T_walls, NaN),
        T_walls=T_walls,
        T_sat=cells(channel_sys.T_sat),
        T_ONB=cells(channel_sys.T_ONB),
        T_inlet=value(channel_sys.T_in),
        P=cells(channel_sys.P),
        q_flux=hottest(q_fluxes, 0.0),
        q_fluxes=q_fluxes,
        ṁ=value(channel_sys.inlet.ṁ),
        velocity=velocity,
        duct=geometry,
        gravity=gravity,
    )
end

"""
    threshold_analysis(sol, channel_sys; gravity=G_EARTH, kwargs...) -> NamedTuple

Apply named threshold functions to one channel of a solution.

Each keyword argument is a callable `fn(state::ChannelState)` returning a value per cell or
one for the whole channel. For a steady solution each runs once. For a transient each runs
on the [`ChannelState`](@ref) at every saved time, so a flow-dependent correlation sees the
flow at that time, and the results stack along a last axis: a per-cell result becomes an
`[n_cells, n_times]` matrix and a channel-level one a vector over time, both against
`sol.t`.

# Arguments
- `sol`: a `NonlinearSolution` (steady) or an `ODESolution` (transient)
- `channel_sys`: the compiled channel subsystem, such as `ssys.ch`
- `gravity`: gravitational acceleration [m/s²] (default `G_EARTH`)
- `kwargs...`: named analysis functions

# Returns
`NamedTuple` with the same keys as `kwargs`, each holding that function's result.

# Example
```julia
result = threshold_analysis(sol, ssys.cac;
    gravity=G_EARTH,
    chfr_mirshak = chfr(q_CHF_mirshak),
    onb          = bergles_rohsenow_t_onb,
)
result.chfr_mirshak                           # CHF ratio per cell, and per time
worst_case(result.chfr_mirshak; times=sol.t)  # the smallest, and where and when
```
"""
function threshold_analysis(sol, channel_sys; gravity=G_EARTH, kwargs...)
    state_at(k) = ChannelState(sol, channel_sys; gravity=gravity, index=k)
    results = if hasproperty(sol, :t) && length(sol.t) > 1
        states = state_at.(eachindex(sol.t))
        map(fn -> stack(fn.(states)), values(kwargs))
    else
        state = state_at(nothing)
        map(fn -> fn(state), values(kwargs))
    end
    return NamedTuple{keys(kwargs)}(results)
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
    cavitation(sol, orifices...) -> Vector{NamedTuple}

The orifices whose throat reached saturation during a run, with when and how far.

Only an `Orifice` built with a contraction coefficient `cc` reports its throat subcooling, the
saturation temperature at the vena contracta pressure less the liquid temperature. A siphon
crest is checked by putting the orifice there. [Model a break](@ref) shows it on a siphon.

# Arguments
- `sol`: a steady (`NonlinearSolution`) or transient (`ODESolution`) solution
- `orifices`: the orifices to check, as subsystems of the compiled model, such as `ssys.breach`

# Returns
One `(site, time, margin)` per orifice whose subcooling fell to zero or below: its name, the
first saved time it did (`nothing` for a steady solution), and the smallest subcooling [K].
Orifices that stayed subcooled are left out, so an empty vector means no cavitation.

# Throws
- `ArgumentError`: for an orifice built without `cc`, or another component
"""
function cavitation(sol, orifices...)
    crossings = @NamedTuple{site::Symbol, time::Union{Float64,Nothing}, margin::Float64}[]
    transient = hasproperty(sol, :t)
    for orifice in orifices
        hasproperty(orifice, :subcooling) || throw(ArgumentError(
            "$(nameof(orifice)) reports no subcooling: build the Orifice with a contraction " *
            "coefficient `cc`",
        ))
        margins = transient ? sol[orifice.subcooling] : [sol[orifice.subcooling]]
        worst = minimum(margins)
        worst <= 0 || continue
        time = transient ? Float64(sol.t[findfirst(<=(0), margins)]) : nothing
        push!(crossings, (site=nameof(orifice), time=time, margin=Float64(worst)))
    end
    return crossings
end

"""
    chfr(chf_fn; face=:max) -> Function

Factory that returns a CHF ratio (CHFR) closure, dividing by the heat flux on one face or the
largest, with a guard for zero or negative flux.

The returned closure has signature `(state::ChannelState) -> AbstractArray`.

# Arguments
- `chf_fn`: a callable `(state::ChannelState) -> AbstractArray`, i.e. any of
  `q_CHF_mirshak`, `q_CHF_sudo_kaminaga`, `q_CHF_fabrega`
- `face`: whose heat flux to divide by: a face of the channel, such as `:left`, or `:max`
  (default) for the largest face flux, the conservative choice

# Returns
Closure `(state::ChannelState) -> Vector{Float64}` where each entry is `CHF[i] / q[i]`,
with `q[i] <= 0 → Inf` (no boiling risk when wall is not being heated).
"""
function chfr(chf_fn; face=:max)
    return function (state::ChannelState)
        q = _face_flux(state, face)
        # Broadcast rather than zip: a channel-level correlation such as
        # q_CHF_sudo_kaminaga gives one number for the whole channel, and it has to divide
        # into the per-cell flux just the same.
        return ifelse.(q .> 0, chf_fn(state) ./ q, Inf)
    end
end

"""
    _face_flux(s::ChannelState, face) -> AbstractArray

The heat flux per cell on `face`, or the largest face flux for `:max`.

# Throws
- `ArgumentError`: for a face the channel does not have
"""
function _face_flux(s::ChannelState, face::Symbol)
    face === :max && return s.q_flux
    haskey(s.q_fluxes, face) && return s.q_fluxes[face]
    throw(ArgumentError("face must be :max or one of the channel's faces, " *
                        "$(join(repr.(keys(s.q_fluxes)), ", ")); got :$face"))
end

"""
    bergles_rohsenow_t_onb(state::ChannelState; face=:max, onb_factor=1.0,
                           inhomogeneity_factor=1.0)
    q_boiling_onset(state::ChannelState; liquid=H2O)
    q_CHF_mirshak(state::ChannelState)
    q_CHF_fabrega(state::ChannelState)
    q_CHF_sudo_kaminaga(state::ChannelState; liquid=H2O)
    q_OFI_whittle_forgan(state::ChannelState; liquid=H2O)
    q_OSV_saha_zuber(state::ChannelState; face=:max, liquid=H2O, inhomogeneity_factor=1.0)
    twall_limit(state::ChannelState; inhomogeneity_factor=1.0)

Every threshold correlation also accepts a solved channel, taking its arguments out of the
`ChannelState` the way Python STREAM's analysis wrapper of the same name does. These are
methods on the correlations themselves, not a second set of names for them. Results come back
per cell, except `q_OFI_whittle_forgan`, which is one power for the channel.
[`threshold_analysis`](@ref) stacks them over time. `q_OFI_whittle_forgan`,
`q_OSV_saha_zuber` and the two geometry-dependent CHF correlations need `state.duct`.

- `face` picks the face flux, as in [`chfr`](@ref): a face of the channel, or `:max` for
  the largest.
- `inhomogeneity_factor` makes the local flux worse, for fuel inhomogeneity, as the scalar
  [`twall_limit`](@ref) does. In `bergles_rohsenow_t_onb` it raises the flux the ONB superheat
  is taken at. Compare the result with `twall_limit(state; inhomogeneity_factor)`, the wall
  temperature at that same flux: their difference is Python STREAM's ONB margin.
- `onb_factor` scales the Bergles-Rohsenow superheat `T_ONB - T_sat`, for the uncertainty of
  the correlation itself.
- `q_boiling_onset` takes `cₚ` at the inlet temperature.
- `q_CHF_mirshak` takes the signed velocity, so reversed flow lowers the limit.
- `q_OFI_whittle_forgan` reads its saturation temperature from the downstream cell, since
  pressure falls along the channel and the outlet is what limits the margin. Under reversed
  flow the downstream end is the other one, and it follows.

What each correlation computes is in its own docstring.
"""
# A wall that is not heating the coolant cannot boil it, and the correlation's fractional
# power has no real value for a negative flux, so those cells report no onset, as chfr does.
# After a scram the coolant rising through the core can run hotter than parts of the plate.
function bergles_rohsenow_t_onb(
    s::ChannelState; face=:max, onb_factor=1.0, inhomogeneity_factor=1.0
)
    q = _face_flux(s, face) .* inhomogeneity_factor
    T_ONB = s.T_sat .+ onb_factor .* _bergles_rohsenow_dT_ONB.(s.P, max.(q, 0.0))
    return ifelse.(q .> 0, T_ONB, Inf)
end

function q_boiling_onset(s::ChannelState; liquid::AbstractLiquid=H2O)
    return q_boiling_onset.(s.ṁ, s.T_sat, s.T_inlet, cₚ(liquid, s.T_inlet))
end

q_CHF_mirshak(s::ChannelState) =
    q_CHF_mirshak.(s.T_bulk, s.T_sat, s.P, copysign.(s.velocity, s.ṁ))

q_CHF_fabrega(s::ChannelState) = q_CHF_fabrega.(s.T_inlet, s.T_sat, s.duct)

# The correlation needs saturated-coolant properties, and this is where the coolant is
# known, so the snapshot is built here: one entry per cell at that cell's saturation state.
function q_CHF_sudo_kaminaga(s::ChannelState; liquid::AbstractLiquid=H2O)
    return q_CHF_sudo_kaminaga(s.T_bulk, s.ṁ, s.duct, s.gravity, liquid(s.T_sat, s.P))
end

# Flow instability is judged at the outlet, where the coolant is hottest and nearest boiling:
# the last cell in forward flow and the first in reversed flow.
function q_OFI_whittle_forgan(s::ChannelState; liquid::AbstractLiquid=H2O)
    T_sat_out = s.ṁ >= 0 ? last(s.T_sat) : first(s.T_sat)
    return q_OFI_whittle_forgan(s.ṁ, T_sat_out, s.T_inlet, s.duct; liquid=liquid)
end

function q_OSV_saha_zuber(
    s::ChannelState; face=:max, liquid::AbstractLiquid=H2O, inhomogeneity_factor=1.0
)
    coolant = liquid(s.T_bulk, s.P)
    return q_OSV_saha_zuber(
        s.T_inlet, s.ṁ, s.duct, coolant;
        flux_shape=_face_flux(s, face), dz=fill(s.duct.L / s.n, s.n),
        inhomogeneity_factor,
    )
end

# The limit rises with the wall temperature, so the hottest face sets it.
twall_limit(s::ChannelState; inhomogeneity_factor=1.0) =
    twall_limit.(s.T_bulk, s.T_wall, inhomogeneity_factor)

function Base.show(io::IO, ::MIME"text/plain", s::ChannelState)
    rng(v) = "$(round(minimum(v); sigdigits=5))..$(round(maximum(v); sigdigits=5))"
    print(io, "ChannelState: ", s.n, " cells")
    print(io, "\n  ṁ        ", round(s.ṁ; sigdigits=5), " kg/s")
    print(io, "\n  T_bulk   ", rng(s.T_bulk), " °C")
    print(io, "\n  T_wall   ", rng(s.T_wall), " °C")
    print(io, "\n  T_sat    ", rng(s.T_sat), " °C")
    print(io, "\n  q_flux   ", rng(s.q_flux), " W/m^2")
    s.duct === nothing || print(io, "\n  duct     ", s.duct.shape, ", ", s.duct.L, " m")
end
