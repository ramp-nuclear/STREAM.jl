"""
    _carried(sys, key) -> Vector

The `key` metadata of `sys` and of every system nested in it, skipping those that carry none.
A compiled system is read through the system it was compiled from, which keeps the nesting.
"""
function _carried(sys, key)
    while ModelingToolkit.has_parent(sys) && ModelingToolkit.get_parent(sys) !== nothing
        sys = ModelingToolkit.get_parent(sys)
    end
    own = ModelingToolkit.getmetadata(sys, key, nothing)
    found = own === nothing ? Any[] : Any[own]
    for sub in ModelingToolkit.get_systems(sys)
        append!(found, _carried(sub, key))
    end
    return found
end

"""
    check_gravity_mismatch(sys) -> Symbol

Check whether the gravity terms of a hydraulic loop are balanced: when a channel runs with
`g > 0`, the loop needs a [`Gravity`](@ref) component with `H > 0` for the return leg.

# Arguments
- `sys`: the loop, compiled or not

# Returns
`:ok` if balanced, or if no channel carries gravity, and `:mismatch`, with a warning, if
channels carry gravity but there is no return-leg `Gravity` component.
"""
function check_gravity_mismatch(sys::ModelingToolkit.AbstractSystem)
    any(g -> g isa Real && g > 0, _carried(sys, _GravityKey)) || return :ok
    any(H -> H isa Real && H > 0, _carried(sys, _ElevationKey)) && return :ok
    @warn "check_gravity_mismatch: channels have g > 0 but no Gravity return component " *
          "found; loop gravity terms may be unbalanced"
    return :mismatch
end

"""
    _sole_face(channel) -> Symbol

The face of a channel whose duct is heated on one wall, or `:left` for one with more.
"""
function _sole_face(channel)
    faces = keys(duct(channel).heated)
    return length(faces) == 1 ? only(faces) : :left
end

"""
    _check_side(channel, side)

Throw an `ArgumentError` unless `side` is `:left` or `:right` and the channel has a face there.
"""
function _check_side(channel, side)
    side in (:left, :right) ||
        throw(ArgumentError("side must be :left or :right, got :$side"))
    faces = keys(duct(channel).heated)
    side in faces || throw(ArgumentError(
        "$(nameof(channel)) has no :$side face; its faces are $(join(repr.(faces), ", "))"))
    return nothing
end

"""
    symmetric_plate(cac, fuel; name) -> System

Wire one `HeatDiffusion` fuel plate symmetrically to one `ChannelAndContacts` channel.

# Arguments
- `cac`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance (`nz` must equal `cac.n`)
- `name`: system name (Symbol)

# Returns
Uncompiled `System` from [`assembly`](@ref). Add boundary conditions, then `mtkcompile()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.cac`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function symmetric_plate(cac, fuel; name::Symbol)
    connections = faces(
        (cac, :thermal_right) => (fuel, :thermal_left),
        (cac, :thermal_left) => (fuel, :thermal_right),
    )
    return assembly(connections, cac, fuel; name=name)
end

"""
    plate(ch_left, ch_right, fuel; name) -> System

Wire a `HeatDiffusion` fuel plate between two `ChannelAndContacts` channels (left and right faces).

# Arguments
- `ch_left`: uncompiled `ChannelAndContacts` for left face
- `ch_right`: uncompiled `ChannelAndContacts` for right face
- `fuel`: uncompiled `HeatDiffusion` instance
- `name`: system name (Symbol)

# Returns
Uncompiled `System` from [`assembly`](@ref).

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.ch_left`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function plate(ch_left, ch_right, fuel; name::Symbol)
    connections = faces(
        (ch_left, :thermal_right) => (fuel, :thermal_left),
        (ch_right, :thermal_left) => (fuel, :thermal_right),
    )
    return assembly(connections, ch_left, ch_right, fuel; name=name)
end

"""
    one_sided(channel, fuel; side, name) -> System

Wire one face of a `HeatDiffusion` plate to a single `ChannelAndContacts` channel. The
channel's face `side` meets the plate's opposite face, so `side=:left` joins the channel's
`thermal_left` to the plate's `thermal_right`, and the plate's other face is adiabatic.

A channel built on a duct heated on one wall, such as `heated=(left=0.063,)`, has that one
face and nothing left dangling.

# Arguments
- `channel`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance
- `side`: the channel's face, `:left` or `:right`. Defaults to the channel's only face when
  its duct is heated on one wall, and to `:left` otherwise.
- `name`: system name (Symbol)

# Throws
- `ArgumentError`: for a side other than `:left` or `:right`, or one the channel has no face on

# Returns
Uncompiled `System` from [`assembly`](@ref).

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `osc.channel`, `osc.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function one_sided(channel, fuel; side::Symbol=_sole_face(channel), name::Symbol)
    _check_side(channel, side)
    connections = if side == :left
        faces((channel, :thermal_left) => (fuel, :thermal_right))
    else
        faces((channel, :thermal_right) => (fuel, :thermal_left))
    end
    return assembly(connections, channel, fuel; name=name)
end

"""
    single_channel(channel, fuel; fuel_side, name) -> System

Wire a `HeatDiffusion` plate to a single `ChannelAndContacts` as an *edge channel*.

The channel is heated on one face only, but the fuel plate is cooled on **both** faces: the
near face by conjugate coupling to the channel, the far face by a one-way convective sink
(`ConvectiveBoundary`) fed from the channel's near-face `h_tc` and coolant `T`.

This reproduces the half-symmetric reduced unit used for the last plate in an array: the
plate sits between two channels, so it loses heat on both faces, but only one channel is
modelled. The far face's heat flows into the unmodelled equivalent twin, so the subsystem
does not conserve energy, by design. For the truthful
one-face-insulated coupling, use [`one_sided`](@ref) instead.

# Arguments
- `channel`: uncompiled `ChannelAndContacts` instance.
- `fuel`: uncompiled `HeatDiffusion` instance (`nz` must equal `channel.n`).
- `fuel_side`: `:left` or `:right`, the near (conjugate) face, of the channel and the fuel
  alike. The fuel's opposite face gets the convective sink. Defaults to the channel's only
  face when its duct is heated on one wall, and to `:left` otherwise.
- `name`: system name (Symbol).

# Returns
Uncompiled `System` from [`assembly`](@ref) holding `channel`, `fuel`, and `n` per-cell
`ConvectiveBoundary` elements. Add boundary conditions, then `mtkcompile()`.

After composition, refer to sub-components through the returned system (e.g.
`scc.channel`, `scc.fuel`).
"""
function single_channel(channel, fuel; fuel_side::Symbol=_sole_face(channel), name::Symbol)
    _check_side(channel, fuel_side)
    near = fuel_side
    far = fuel_side == :left ? :right : :left
    near_port = Symbol(:thermal_, near)
    far_port = Symbol(:thermal_, far)
    geometry = duct(channel)
    n = var_length(channel, near_port)
    dz = geometry.L / n

    # The channel's far face, if it has one, is never connected, so its conductance is
    # undefined; Python's `_other_if_none` copies the connected (near) face's h to it. Cool
    # the fuel's far face with that same near-side h_tc and the channel's coolant T, over the
    # near face's area: the face of the equivalent twin.
    far_bcs = [
        ConvectiveBoundary(; name=Symbol(name, :_far, i), area=geometry.heated[near] * dz)
        for i in 1:n
    ]

    connections = [
        faces((channel, near_port) => (fuel, near_port)),
        face(far_bcs, fuel, far_port),
        getproperty.(far_bcs, :h) .~ scalarize(getproperty(channel, Symbol(:h_tc_, near))),
        getproperty.(far_bcs, :T_fluid) .~ scalarize(channel.T),
    ]
    return assembly(connections, channel, fuel, far_bcs...; name=name)
end


"""
    _walk_alternation(channels, plates, effective_bookend, start) -> Vector{Tuple{Symbol,Any}}

Order the channels and plates into the alternating chain [`fuel_assembly`](@ref) composes,
as `(kind, sys)` tuples with `kind` either `:c` for a channel or `:p` for a plate.

`effective_bookend` decides the pattern when the counts differ: `:channel` for `nc = np + 1`,
`:plate` for `np = nc + 1`. With equal counts `start` picks which kind leads.
"""
function _walk_alternation(channels, plates, effective_bookend::Symbol, start)
    C = tuple.(:c, channels)
    P = tuple.(:p, plates)
    if effective_bookend == :channel        # nc = np + 1  ->  c p c p ... c
        return [collect(Iterators.flatten(zip(C, P))); C[end]]
    elseif effective_bookend == :plate       # np = nc + 1  ->  p c p c ... p
        return [collect(Iterators.flatten(zip(P, C))); P[end]]
    elseif start == :plate                    # mixed, equal counts, plate first
        return collect(Iterators.flatten(zip(P, C)))
    else                                      # mixed, equal counts, channel first
        return collect(Iterators.flatten(zip(C, P)))
    end
end

"""
    _pair_connections(left, right, n) -> Vector{Equation}

Wire one adjacent pair of the chain, the left member's right face to the right member's left
face, one connection per cell. Both arguments are the `(kind, sys)` tuples
[`_walk_alternation`](@ref) produces; the kind tags do not change the wiring, so they are
ignored here, and [`Connect.faces`](@ref) reads the cell count off the ports itself.
"""
function _pair_connections(left::Tuple{Symbol,Any}, right::Tuple{Symbol,Any}, n::Int)
    _, lsys = left
    _, rsys = right
    return faces((lsys, :thermal_right) => (rsys, :thermal_left))
end

"""
    fuel_assembly(channels, plates; bookend=:auto, start=nothing, closed=false, name) -> System

Join `ChannelAndContacts` channels and `HeatDiffusion` plates into an alternating chain, the
layout of a plate-fuel assembly. Each element's right face is joined to the next one's left
face, cell by cell, as in [`plate`](@ref). Faces at the ends of an open chain stay unconnected,
which makes them adiabatic, as in [`one_sided`](@ref).

The chain has one of four shapes, inferred from the counts when `bookend=:auto`:

1. **Channel-bookended**: one more channel than plates, so both ends are channels.
2. **Plate-bookended**: one more plate than channels, so both ends are plates.
3. **Mixed**: equal counts, one end of each. Needs `bookend=:mixed` (or `:auto`) and
   `start=:channel` or `start=:plate` to say which comes first.
4. **Closed**: equal counts with `closed=true`. The last element wraps around to the first,
   as in an annular assembly. `start` defaults to `:channel`.

Each plate's `nz` must equal the `n` of the channels it touches. The components keep the
names they were built with, so the chain built from `c1` and `p1` is reached as `asm.c1` and
`asm.p1`. See [Build a fuel assembly](@ref).

# Arguments
- `channels`: uncompiled `ChannelAndContacts`, in chain order
- `plates`: uncompiled `HeatDiffusion`, in chain order

# Keywords
- `bookend`: `:auto` (default), `:channel`, `:plate` or `:mixed`. An explicit value that
  contradicts the counts raises.
- `start`: `:channel` or `:plate` for a mixed or closed chain, `nothing` otherwise
- `closed`: wrap the chain into a ring
- `name`: system name, supplied by `@named`

# Returns
Uncompiled `System` from [`assembly`](@ref). Add the hydraulics, a pressure anchor and, for a
plate built with `power=nothing`, its power, then `mtkcompile`.

# Throws
- `ArgumentError`: for counts that fit no shape, or keywords that contradict them

# Examples
```julia
fuel_assembly([c1, c2, c3], [p1, p2]; name=:asm)                       # channel-bookended
fuel_assembly([c1], [p1, p2]; name=:asm)                               # plate-bookended
fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm)
fuel_assembly([c1, c2, c3], [p1, p2, p3]; closed=true, name=:asm)      # a ring
```
"""
function fuel_assembly(
    channels::Vector{<:ModelingToolkit.AbstractSystem},
    plates::Vector{<:ModelingToolkit.AbstractSystem};
    bookend::Symbol = :auto,
    start::Union{Symbol,Nothing} = nothing,
    closed::Bool = false,
    name::Symbol,
)
    # 1. bookend kwarg validation (fail fast)
    bookend in (:auto, :channel, :plate, :mixed) ||
        throw(ArgumentError("fuel_assembly: bookend must be :auto, :channel, :plate, or :mixed, got :$bookend"))

    # 2. start kwarg value validation
    (start === nothing || start in (:channel, :plate)) ||
        throw(ArgumentError("fuel_assembly: start must be :channel, :plate, or nothing, got :$start"))

    # 3. Length sanity
    nc, np = length(channels), length(plates)
    (nc >= 1 && np >= 1) ||
        throw(ArgumentError("fuel_assembly: channels and plates must each contain at least one element, got channels=$nc, plates=$np"))

    # 4. Resolve effective bookend (auto-infer or check explicit-vs-inferred)
    inferred = if nc == np + 1
        :channel
    elseif np == nc + 1
        :plate
    elseif nc == np
        :mixed
    else
        throw(ArgumentError("fuel_assembly: cannot infer bookend from lengths channels=$nc, plates=$np; they must be equal, or differ by exactly 1"))
    end
    effective_bookend = if bookend == :auto
        inferred
    else
        bookend == inferred ||
            throw(ArgumentError("fuel_assembly: bookend=:$bookend contradicts lengths channels=$nc, plates=$np (would infer :$inferred)"))
        bookend
    end

    # 5. start cross-checks
    if effective_bookend == :mixed && start === nothing && !closed
        throw(ArgumentError("fuel_assembly: bookend=:mixed requires start=:channel or start=:plate"))
    end
    if effective_bookend != :mixed && start !== nothing
        throw(ArgumentError("fuel_assembly: start=:$start is only valid when bookend=:mixed (got bookend=:$effective_bookend)"))
    end

    # 6. closed cross-checks
    if closed && nc != np
        throw(ArgumentError("fuel_assembly: closed=true requires equal lengths, got channels=$nc, plates=$np"))
    end
    # A closed ring needs no explicit start (it's rotationally symmetric); default it.
    if closed && start === nothing
        start = :channel
    end

    # 7. Per-cell port count (homogeneity is the caller's responsibility).
    n = var_length(channels[1], :thermal_left)

    # 8. Build the alternation and wire each adjacent pair per cell. For a closed
    #    ring we also wire the wrap pair (seq[end] -> seq[1]).
    seq = _walk_alternation(channels, plates, effective_bookend, start)
    pair_range = closed ? (1:length(seq)) : (1:length(seq)-1)
    next_idx = m -> m == length(seq) ? 1 : m + 1
    connections = [_pair_connections(seq[m], seq[next_idx(m)], n) for m in pair_range]
    return assembly(connections, channels..., plates...; name=name)
end

