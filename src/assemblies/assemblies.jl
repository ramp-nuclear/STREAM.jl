function _real_defaults(params)
    vals = Float64[]
    for p in params
        ModelingToolkit.hasdefault(p) || continue
        d = ModelingToolkit.getdefault(p)
        d isa Real && push!(vals, Float64(d))
    end
    return vals
end

"""
    check_gravity_mismatch(sys) -> Symbol

Check whether gravity pressure contributions in a hydraulic loop are balanced.

# Arguments
- `sys`: compiled `AbstractSystem` to inspect

# Returns
`:ok` if balanced (or gravity disabled), `:mismatch` if channels have gravity but no
return-leg `Gravity` component.
"""
function check_gravity_mismatch(sys::ModelingToolkit.AbstractSystem)
    all_pars = ModelingToolkit.parameters(sys)

    local_name = p -> begin
        s = string(p)
        idx = findlast('₊', s)
        idx === nothing ? s : s[nextind(s, idx):end]
    end

    g_vals = _real_defaults(filter(p -> local_name(p) == "g_acc", all_pars))
    h_vals = _real_defaults(filter(p -> local_name(p) == "H", all_pars))

    if isempty(g_vals) || all(iszero, g_vals)
        return :ok
    end

    active_g = any(v -> v > 0.0, g_vals)
    has_return = !isempty(h_vals) && any(v -> v > 0.0, h_vals)

    if active_g && !has_return
        @warn "check_gravity_mismatch: channels have g_acc > 0 but no Gravity return component found — loop gravity terms may be unbalanced"
        return :mismatch
    end

    return :ok
end

"""
    compose_systems(systems...; connections, name) -> System

Compose multiple MTK systems with explicit connection equations into a single system.

# Arguments
- `systems`: positional varargs of uncompiled systems
- `connections`: vector of connection equations (`Vector{<:Equation}`)
- `name`: system name (Symbol)

# Returns
Uncompiled `System` ready for `mtkcompile()`.
"""
function compose_systems(systems...; connections::Vector{<:Equation}, name::Symbol)
    return compose(System(connections, t; name=name), systems...)
end


"""
    symmetric_plate(cac, fuel; name) -> System

Wire one `HeatDiffusion` fuel plate symmetrically to one `ChannelAndContacts` channel.

# Arguments
- `cac`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance (`nz` must equal `cac.n`)
- `name`: system name (Symbol)

# Returns
Uncompiled `System` from `compose()`. Add boundary conditions, then `mtkcompile()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.cac`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function symmetric_plate(cac, fuel; name::Symbol)
    connections = faces(
        (cac, :thermal_right) => (fuel, :thermal_left),
        (cac, :thermal_left) => (fuel, :thermal_right),
    )
    return compose(System(connections, t; name=name), cac, fuel)
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
Uncompiled `System` from `compose()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.ch_left`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function plate(ch_left, ch_right, fuel; name::Symbol)
    connections = faces(
        (ch_left, :thermal_right) => (fuel, :thermal_left),
        (ch_right, :thermal_left) => (fuel, :thermal_right),
    )
    return compose(System(connections, t; name=name), ch_left, ch_right, fuel)
end

"""
    one_sided(channel, fuel; side=:left, name) -> System

Wire one face of a `HeatDiffusion` plate to a single `ChannelAndContacts` channel.

# Arguments
- `channel`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance
- `side`: `:left` or `:right`, which face of the fuel plate connects to the channel (default `:left`)
- `name`: system name (Symbol)

# Returns
Uncompiled `System` from `compose()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `osc.channel`, `osc.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function one_sided(channel, fuel; side::Symbol=:left, name::Symbol)
    side in (:left, :right) ||
        throw(ArgumentError("side must be :left or :right, got :$side"))
    connections = if side == :left
        faces((channel, :thermal_left) => (fuel, :thermal_right))
    else
        faces((channel, :thermal_right) => (fuel, :thermal_left))
    end
    return compose(System(connections, t; name=name), channel, fuel)
end

"""
    single_channel(channel, fuel, geometry; fuel_side=:left, name) -> System

Wire a `HeatDiffusion` plate to a single `ChannelAndContacts` as an *edge channel*: the
channel is heated on one face only, but the fuel plate is cooled on **both** faces — the
near face by conjugate coupling to the channel, the far face by a one-way convective sink
(`ConvectiveBoundary`) fed from the channel's far-side `h_tc` and coolant `T`.

This reproduces the half-symmetric reduced unit used for the last plate in an array: the
plate sits between two channels, so it loses heat on both faces, but only one channel is
modelled. The far face's heat flows into the unmodelled equivalent twin, so the subsystem
does not conserve energy — that is the modelling choice, not a defect. For the truthful
one-face-insulated coupling, use [`one_sided`](@ref) instead.

# Arguments
- `channel`: uncompiled `ChannelAndContacts` instance.
- `fuel`: uncompiled `HeatDiffusion` instance (`nz` must equal `channel.n`).
- `geometry`: the `PipeGeometry` the channel was built with (supplies `L` and
  `heated_parts` for the far-face areas).
- `fuel_side`: `:left` or `:right` — which fuel face is the near (conjugate) face
  (default `:left`). The opposite face gets the convective sink.
- `name`: system name (Symbol).

# Returns
Uncompiled `System` from `compose()` holding `channel`, `fuel`, and `n` per-cell
`ConvectiveBoundary` elements. Add boundary conditions, then `mtkcompile()`.

After composition, refer to sub-components through the returned system (e.g.
`scc.channel`, `scc.fuel`).
"""
function single_channel(channel, fuel, geometry::PipeGeometry; fuel_side::Symbol=:left, name::Symbol)
    fuel_side in (:left, :right) ||
        throw(ArgumentError("fuel_side must be :left or :right, got :$fuel_side"))
    n = var_length(channel, :thermal_left)
    dz = geometry.L / n

    near = fuel_side
    far = fuel_side == :left ? :right : :left
    far_idx = far == :left ? 1 : 2

    near_port = Symbol(:thermal_, near)
    far_port = Symbol(:thermal_, far)
    # The channel's far face is never connected, so its conductance is undefined; Python's
    # `_other_if_none` copies the connected (near) face's h to it. Cool the fuel's far face
    # with that same near-side h_tc and the channel's coolant T — the equivalent-twin proxy.
    h_near = near == :left ? :h_tc_left : :h_tc_right

    far_bcs = [
        ConvectiveBoundary(; name=Symbol(name, :_far, i), area=geometry.heated_parts[far_idx] * dz)
        for i in 1:n
    ]

    near_conns = [connect(port(channel, near_port, i), port(fuel, near_port, i)) for i in 1:n]
    far_conns = [connect(far_bcs[i].thermal, port(fuel, far_port, i)) for i in 1:n]
    h_channel = getproperty(channel, h_near)
    T_channel = getproperty(channel, :T)
    bindings = Equation[
        [far_bcs[i].h ~ h_channel[i] for i in 1:n]...,
        [far_bcs[i].T_fluid ~ T_channel[i] for i in 1:n]...,
    ]

    connections = Equation[near_conns...; far_conns...; bindings...]
    return compose(System(connections, t; name=name), channel, fuel, far_bcs...)
end


# The helpers below build the alternating chain [`fuel_assembly`](@ref) composes.

# Build the alternation as an ordered Vector of (kind, sys) tuples, kind :c or :p.
function _walk_alternation(channels, plates, effective_bookend::Symbol, start)
    C = [(:c, ch) for ch in channels]
    P = [(:p, pl) for pl in plates]
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

# Wire one adjacent pair: left member's right face to right member's left face,
# per cell. The kind tags don't change the wiring, so they're ignored here.
function _pair_connections(left::Tuple{Symbol,Any}, right::Tuple{Symbol,Any}, n::Int)
    _, lsys = left
    _, rsys = right
    return faces((lsys, :thermal_right) => (rsys, :thermal_left))
end

"""
    fuel_assembly(channels, plates; bookend=:auto, start=nothing, closed=false, name) -> System

Compose an alternating CAC↔Plate chain (fuel-assembly topology) from a vector of
`ChannelAndContacts` instances and a vector of `HeatDiffusion` plates.

Each adjacent pair connects the left member's right face to the right member's left face, as in
[`plate`](@ref). Outer faces left dangling stay adiabatic, as in [`one_sided`](@ref).

There are four chain shapes:

1. **Channel-bookended** — `length(channels) == length(plates) + 1`. Both ends are CACs;
   plates sit between adjacent channels. Inferred when `bookend=:auto`.
2. **Plate-bookended** — `length(plates) == length(channels) + 1`. Both ends are plates.
   Inferred when `bookend=:auto`.
3. **Mixed** — equal counts. One end is a channel, the other a plate; orientation pinned
   by `start=:channel` or `start=:plate`. Requires `bookend=:mixed` (or `:auto` with equal
   counts) plus an explicit `start`.
4. **Closed annular ring** — equal counts with `closed=true`. Last element wraps to the
   first; `start` defaults to `:channel` (canonical orientation for the wrap pair).

# Arguments
- `channels::Vector{<:AbstractSystem}`: uncompiled `ChannelAndContacts` instances.
- `plates::Vector{<:AbstractSystem}`: uncompiled `HeatDiffusion` instances.
- `bookend::Symbol = :auto`: one of `:auto | :channel | :plate | :mixed`. `:auto` infers
  from `(length(channels), length(plates))`. An explicit value that contradicts the
  inferred value raises `ArgumentError`.
- `start::Union{Symbol,Nothing} = nothing`: required when `bookend=:mixed`. Values
  `:channel` (chain starts with `channels[1]`) or `:plate` (chain starts with `plates[1]`).
  Must be `nothing` for non-mixed bookends. Defaults to `:channel` when `closed=true`
  and no explicit value is provided (the ring is rotationally symmetric — the choice
  only picks which neighbour the wrap pair attaches to first).
- `closed::Bool = false`: when true, wrap the chain into a ring (variant 4). Requires
  equal lengths; raises `ArgumentError` otherwise.
- `name::Symbol`: system name (kwarg-only; supplied by `@named` macro).

Per-pair `n` matching (`cac.n == plate.nz` for every adjacent pair) is the caller's
responsibility (same contract as `symmetric_plate` / `plate`). The per-cell port count
is taken from `channels[1]`; a mismatch across the vector is caught by MTK at
`mtkcompile()` time.

# Returns
Uncompiled `System` from `compose()`. Add boundary conditions (pump loop, pressure
anchor, power binding), then `mtkcompile(...; build_initializeprob=false)`.

After composition, sub-components are reachable through their original `@named` names
(`assembly.c1`, `assembly.p1`, …). The helper does NOT synthesize index-based names.

# Examples
```julia
# Variant 1 — channel-bookended (k=2 plates, k+1=3 channels)
assembly = fuel_assembly([c1, c2, c3], [p1, p2]; name=:asm)
# bookend defaults to :auto → resolves to :channel

# Variant 2 — plate-bookended (k=1 channel, k+1=2 plates)
assembly = fuel_assembly([c1], [p1, p2]; name=:asm)

# Variant 3 — mixed (k=2 of each), channel-first
assembly = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm)

# Variant 4 — closed annular ring (k=3 of each)
assembly = fuel_assembly([c1, c2, c3], [p1, p2, p3]; closed=true, name=:asm)
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
        throw(ArgumentError("fuel_assembly: cannot infer bookend from lengths channels=$nc, plates=$np — must be equal, or differ by exactly 1"))
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
    connections = Equation[
        eq
        for m in pair_range
        for eq in _pair_connections(seq[m], seq[next_idx(m)], n)
    ]

    return compose(System(connections, t; name=name), channels..., plates...)
end

