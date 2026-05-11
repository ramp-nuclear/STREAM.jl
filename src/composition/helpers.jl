# helpers.jl — QoL and composition helpers for STREAM.jl

"""
    port(sys, face, i) -> SubsystemPort

Access an indexed thermal port array element from a compiled subsystem.

# Arguments
- `sys`: MTK system instance
- `face`: port array name (Symbol), e.g. `:thermal_left`
- `i`: 1-based cell index (Int)

# Returns
The subsystem port object, suitable for use in `connect()` calls.
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))

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
    all_pars = try
        ModelingToolkit.parameters(sys)
    catch
        return :ok
    end

    local_name(p) = begin
        s = string(p)
        idx = findlast('₊', s)
        idx === nothing ? s : s[nextind(s, idx):end]
    end

    g_params = filter(p -> local_name(p) == "g_acc", all_pars)
    h_params = filter(p -> local_name(p) == "H", all_pars)

    g_vals = Float64[]
    for p in g_params
        try
            val = ModelingToolkit.getdefault(p)
            if val isa Real
                push!(g_vals, Float64(val))
            end
        catch
        end
    end

    h_vals = Float64[]
    for p in h_params
        try
            val = ModelingToolkit.getdefault(p)
            if val isa Real
                push!(h_vals, Float64(val))
            end
        catch
        end
    end

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

function _infer_n(sys)
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))
    n = count(s -> startswith(s, "thermal_left"), sub_names)
    n == 0 && error(
        "_infer_n: could not detect thermal port count in system $(ModelingToolkit.getname(sys)). Pass an uncompiled ChannelAndContacts instance.",
    )
    return n
end

"""
    symmetric_plate(cac, fuel; name) -> ODESystem

Wire one `HeatDiffusion` fuel plate symmetrically to one `ChannelAndContacts` channel.

# Arguments
- `cac`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance (`nz` must equal `cac.n`)
- `name`: system name (Symbol)

# Returns
Uncompiled `ODESystem` from `compose()`. Add boundary conditions, then `mtkcompile()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.cac`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function symmetric_plate(cac, fuel; name::Symbol)
    n = _infer_n(cac)
    connections = Equation[
        [
            connect(port(cac, :thermal_right, i), port(fuel, :thermal_left, i)) for i in 1:n
        ]...,
        [
            connect(port(cac, :thermal_left, i), port(fuel, :thermal_right, i)) for i in 1:n
        ]...,
    ]
    return compose(System(connections, t; name=name), cac, fuel)
end

"""
    plate(ch_left, ch_right, fuel; name) -> ODESystem

Wire a `HeatDiffusion` fuel plate between two `ChannelAndContacts` channels (left and right faces).

# Arguments
- `ch_left`: uncompiled `ChannelAndContacts` for left face
- `ch_right`: uncompiled `ChannelAndContacts` for right face
- `fuel`: uncompiled `HeatDiffusion` instance
- `name`: system name (Symbol)

# Returns
Uncompiled `ODESystem` from `compose()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `rods.ch_left`, `rods.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function plate(ch_left, ch_right, fuel; name::Symbol)
    n = _infer_n(ch_left)
    connections = Equation[
        [
            connect(port(ch_left, :thermal_right, i), port(fuel, :thermal_left, i)) for
            i in 1:n
        ]...,
        [
            connect(port(ch_right, :thermal_left, i), port(fuel, :thermal_right, i)) for
            i in 1:n
        ]...,
    ]
    return compose(System(connections, t; name=name), ch_left, ch_right, fuel)
end

"""
    one_sided_connection(channel, fuel; side=:left, name) -> ODESystem

Wire one face of a `HeatDiffusion` plate to a single `ChannelAndContacts` channel.

# Arguments
- `channel`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance
- `side`: `:left` or `:right`, which face of the fuel plate connects to the channel (default `:left`)
- `name`: system name (Symbol)

# Returns
Uncompiled `ODESystem` from `compose()`.

After calling this function, refer to sub-components exclusively via the returned system
(e.g. `osc.channel`, `osc.fuel`). The original component variables hold unscoped symbolic
names and should not be used in equations or connection dicts after composition.
"""
function one_sided_connection(channel, fuel; side::Symbol=:left, name::Symbol)
    side in (:left, :right) ||
        error("one_sided_connection: side must be :left or :right, got :$side")
    n = _infer_n(channel)
    connections = if side == :left
        Equation[[
            connect(port(channel, :thermal_left, i), port(fuel, :thermal_right, i)) for
            i in 1:n
        ]...]
    else
        Equation[[
            connect(port(channel, :thermal_right, i), port(fuel, :thermal_left, i)) for
            i in 1:n
        ]...]
    end
    return compose(System(connections, t; name=name), channel, fuel)
end

"""
    compose_systems(systems...; connections, name) -> ODESystem

Compose multiple MTK systems with explicit connection equations into a single system.

# Arguments
- `systems`: positional varargs of uncompiled systems
- `connections`: vector of connection equations (`Vector{<:Equation}`)
- `name`: system name (Symbol)

# Returns
Uncompiled `ODESystem` ready for `mtkcompile()`.
"""
function compose_systems(systems...; connections::Vector{<:Equation}, name::Symbol)
    return compose(System(connections, t; name=name), systems...)
end

# ----------------------------------------------------------------
# fuel_assembly — Phase 60 (v1.2 §3.12)
# Walks the four variants of alternating CAC↔Plate chains and emits the
# per-cell connect(port(...), port(...)) chain (plus the wrap pair when
# closed=true). Returns the raw uncompiled ODESystem. Caller compiles.
#
# Variants:
#   1. Channel-bookended: k plates, k+1 channels  (bookend=:channel)
#   2. Plate-bookended:   k+1 plates, k channels  (bookend=:plate)
#   3. Mixed:             equal counts, start pins orientation (bookend=:mixed)
#   4. Closed annular:    equal counts, last wraps to first (closed=true)
#
# Wiring convention (matches `plate(...)` lines 217–230):
#   (channel-left, plate-right) → connect(channel.thermal_right[i], plate.thermal_left[i])
#   (plate-left,  channel-right) → connect(plate.thermal_right[i],  channel.thermal_left[i])
# Adjacent unconnected outer faces remain unconnected (MTK adiabatic default,
# same as one_sided_connection).
# ----------------------------------------------------------------

# Internal helper: build the alternation sequence as an ordered Vector of
# (kind, sys) tuples where kind ∈ (:c, :p). Private — `_` prefix, not exported.
function _walk_alternation(channels, plates, effective_bookend::Symbol, start)
    nc, np = length(channels), length(plates)
    seq = Tuple{Symbol,Any}[]
    if effective_bookend == :channel
        # c1, p1, c2, p2, …, pk, c_{k+1}   (nc = np + 1)
        for k in 1:np
            push!(seq, (:c, channels[k]))
            push!(seq, (:p, plates[k]))
        end
        push!(seq, (:c, channels[nc]))
    elseif effective_bookend == :plate
        # p1, c1, p2, c2, …, ck, p_{k+1}   (np = nc + 1)
        for k in 1:nc
            push!(seq, (:p, plates[k]))
            push!(seq, (:c, channels[k]))
        end
        push!(seq, (:p, plates[np]))
    else  # :mixed (equal counts)
        if start == :channel
            # c1, p1, c2, p2, …, ck, pk
            for k in 1:nc
                push!(seq, (:c, channels[k]))
                push!(seq, (:p, plates[k]))
            end
        else  # start == :plate
            # p1, c1, p2, c2, …, pk, ck
            for k in 1:nc
                push!(seq, (:p, plates[k]))
                push!(seq, (:c, channels[k]))
            end
        end
    end
    return seq
end

# Internal helper: emit the per-pair thermal-port comprehension between two
# adjacent (kind, sys) entries, choosing face orientation per the spatial-
# absolute L/R convention used throughout this file.
function _pair_connections(left::Tuple{Symbol,Any}, right::Tuple{Symbol,Any}, n::Int)
    lk, lsys = left
    rk, rsys = right
    if lk == :c && rk == :p
        return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
    elseif lk == :p && rk == :c
        return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
    else
        # Defense-in-depth: alternation invariant should make this unreachable.
        error("fuel_assembly: internal error — adjacent entries share kind :$lk")
    end
end

"""
    fuel_assembly(channels, plates; bookend=:auto, start=nothing, closed=false, name) -> ODESystem

Compose an alternating CAC↔Plate chain (fuel-assembly topology) from a vector of
`ChannelAndContacts` instances and a vector of `HeatDiffusion` plates.

Handles the four variants from the v1.2 design contract §3.12:

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
responsibility (same contract as `symmetric_plate` / `plate`). `_infer_n(channels[1])`
is called once for the per-cell port-loop bound. Mismatched `n` across the vector is
caught by MTK at `mtkcompile()` time.

# Returns
Uncompiled `ODESystem` from `compose()`. Add boundary conditions (pump loop, pressure
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

    # 5. start cross-checks (D-03)
    if effective_bookend == :mixed && start === nothing && !closed
        throw(ArgumentError("fuel_assembly: bookend=:mixed requires start=:channel or start=:plate"))
    end
    if effective_bookend != :mixed && start !== nothing
        throw(ArgumentError("fuel_assembly: start=:$start is only valid when bookend=:mixed (got bookend=:$effective_bookend)"))
    end

    # 6. closed cross-checks (D-04)
    if closed && nc != np
        throw(ArgumentError("fuel_assembly: closed=true requires equal lengths, got channels=$nc, plates=$np"))
    end
    if closed && effective_bookend != :mixed
        # Defense-in-depth: equal lengths already resolved to :mixed in step 4.
        throw(ArgumentError("fuel_assembly: closed=true requires equal lengths (resolved bookend must be :mixed), got effective bookend :$effective_bookend"))
    end
    # Closed ring with no explicit start: pick :channel as canonical orientation.
    if closed && start === nothing
        start = :channel
    end

    # 7. Per-cell port count (caller-responsibility for homogeneity, D-05)
    n = _infer_n(channels[1])

    # 8. Build the alternation sequence + adjacent-pair connections.
    # Sequence is an alternation of (:c, ch) and (:p, pl). For each adjacent
    # pair (seq[m], seq[m+1]) we emit one per-cell connect() comprehension
    # over i in 1:n; for closed=true we also include the wrap pair
    # (seq[end], seq[1]). The flat Equation[] double-comprehension below
    # yields the same per-pair-per-cell shape as the splatted comprehensions
    # in `plate(...)` lines 219–228, generalized for a dynamic number of
    # adjacent pairs.
    seq = _walk_alternation(channels, plates, effective_bookend, start)
    pair_range = closed ? (1:length(seq)) : (1:length(seq)-1)
    next_idx(m) = m == length(seq) ? 1 : m + 1
    connections = Equation[
        eq
        for m in pair_range
        for eq in _pair_connections(seq[m], seq[next_idx(m)], n)
    ]

    return compose(System(connections, t; name=name), channels..., plates...)
end

"""
    connect_temperature_feedback(pk, components) -> Vector{Equation}

Generate binding equations that wire each component's existing `T` symbolic to the
corresponding `pk.T_source_<name>` unknowns inside `PointKinetics`. Used together
with `compose_systems` to close the neutronics<->thermal-hydraulics loop.

# Arguments
- `pk`: uncompiled `PointKinetics` system built with `temp_worth=...`
- `components`: list of scoped component references whose temperatures feed into `pk`
  (e.g. `[rods.cac]`, `[inter.ch_left, inter.ch_right]`). Pass scoped references
  (post-composition), not original component variables. Alpha coefficients belong in
  the `PointKinetics` constructor `temp_worth` dict — they are not needed here.

# Returns
`Vector{Equation}` -- one equation per cell, per component. Length equals the total
number of cells across all components. For 1D channel T: `pk.T_source_<name>[j] ~ comp.T[j]`.
For 2D HeatDiffusion T: `pk.T_source_<name>[(jz-1)*nx+jx] ~ comp.T[jz, jx]` (row-major).

# Note
Pass scoped references (post-composition), not original component variables. The
original component variables hold unscoped symbolic names and should not be used in
equations or connection dicts after composition.

# Example (scoped — component wrapped inside symmetric_plate)
```julia
rods = symmetric_plate(cac, fuel; name=:rods)
@named pk = PointKinetics(ctrl; temp_worth=Dict(rods.cac => alpha))
eqs = connect_temperature_feedback(pk, [rods.cac])
# eqs has n equations binding pk.T_source_cac[j] ~ rods.cac.T[j]
```
"""
function connect_temperature_feedback(pk, components)
    eqs = Equation[]
    for comp in components
        cname = nameof(comp)
        pk_T_source = getproperty(pk, Symbol(:T_source_, cname))
        T_sym = getproperty(comp, :T)
        if ndims(T_sym) == 1
            n = length(T_sym)
            for j in 1:n
                push!(eqs, pk_T_source[j] ~ T_sym[j])
            end
        else
            nz, nx = size(T_sym)
            for jz in 1:nz, jx in 1:nx
                j = (jz - 1) * nx + jx
                push!(eqs, pk_T_source[j] ~ T_sym[jz, jx])
            end
        end
    end
    return eqs
end
