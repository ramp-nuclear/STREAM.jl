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
