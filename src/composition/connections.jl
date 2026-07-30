# connections.jl -- wiring primitives and the checks that go with them.
#
# Everything here is about joining components that already exist: series and parallel
# hydraulic chains, per-cell thermal faces, the composed System itself, and the
# point-kinetics temperature-feedback bindings. Assemblies built out of these live in
# assemblies.jl.

"""
    inseries(systems...) -> Vector{Equation}

Build the hydraulic connection equations for a simple series chain of two-port components,
connecting each component's `outlet` to the next component's `inlet`.

# Arguments
- `systems`: two or more uncompiled systems exposing `inlet` and `outlet` `FlowPort`s

# Returns
`Vector{Equation}` suitable for splicing into a `conns = [...]` list or passing to
`System(conns, t; name=...)`.

# Example
```julia
conns = [
    inseries(pump, hx, resistor, pump)...,
    pump.inlet.p ~ 1.0e5,
]
```
"""
function inseries(systems...)
    length(systems) >= 2 ||
        throw(ArgumentError("inseries requires at least two systems"))
    return Equation[
        connect(getproperty(systems[i], :outlet), getproperty(systems[i + 1], :inlet)) for
        i in 1:(length(systems) - 1)
    ]
end

_branch_systems(branch::Tuple) = collect(branch)
_branch_systems(branch::AbstractVector) = collect(branch)
_branch_systems(branch) = Any[branch]

"""
    inparallel(upstream, branches, downstream) -> Vector{Equation}

Build the hydraulic connection equations for a parallel block. `upstream.outlet` feeds every
branch inlet, each branch may be a single two-port component or a tuple/vector of components
connected in series internally, and all branch outlets merge into `downstream.inlet`.

# Arguments
- `upstream`: uncompiled system exposing an `outlet` `FlowPort`
- `branches`: collection of branch paths; each branch is either one uncompiled two-port system
  or a tuple/vector of such systems
- `downstream`: uncompiled system exposing an `inlet` `FlowPort`

# Returns
`Vector{Equation}` suitable for splicing into a `conns = [...]` list or passing to
`System(conns, t; name=...)`.

# Example
```julia
conns = [
    inseries(pump, hx)...,
    inparallel(hx, ((R1, G1), R2), pump)...,
    pump.inlet.p ~ 1.0e5,
]
```
"""
function inparallel(upstream, branches, downstream)
    length(branches) >= 1 ||
        throw(ArgumentError("inparallel requires at least one branch"))
    branch_paths = [_branch_systems(branch) for branch in branches]
    branch_inlets = [getproperty(path[1], :inlet) for path in branch_paths]
    branch_outlets = [getproperty(path[end], :outlet) for path in branch_paths]
    eqs = Equation[
        connect(getproperty(upstream, :outlet), branch_inlets...),
        connect(branch_outlets..., getproperty(downstream, :inlet)),
    ]
    for path in branch_paths
        length(path) > 1 && append!(eqs, inseries(path...))
    end
    return eqs
end

"""
    port(sys, face, i)

Access an indexed thermal port array element from a compiled subsystem.

# Arguments
- `sys`: MTK system instance
- `face`: port array name (Symbol), e.g. `:thermal_left`
- `i`: 1-based cell index (Int)

# Returns
The namespaced connector subsystem (e.g. `sys.thermal_left3`), suitable for `connect()`.
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))

"""
    connect_face(sources, target, face; source_port=:thermal) -> Vector{Equation}

Connect one per-cell source array to one thermal face of a target system.

# Arguments
- `sources`: vector of systems exposing the connector `source_port`
- `target`: system exposing an indexed thermal face such as `:thermal_left` or `:thermal_right`
- `face`: target face symbol (`:thermal_left` or `:thermal_right`)
- `source_port`: connector name on each source system (default `:thermal`)

# Returns
`Vector{Equation}` with one `connect(...)` equation per cell.
"""
function connect_face(sources, target, face::Symbol; source_port::Symbol=:thermal)
    return Equation[
        connect(getproperty(sources[i], source_port), port(target, face, i)) for
        i in eachindex(sources)
    ]
end

"""
    connect_faces(mapping::Pair) -> Vector{Equation}
    connect_faces(mappings::Pair...) -> Vector{Equation}

Connect indexed thermal faces cell-by-cell between systems.

# Arguments
- `mapping`: face mapping written as `(left_system, :left_face) => (right_system, :right_face)`
- `mappings...`: one or more such mappings

# Returns
Flattened `Vector{Equation}` with one `connect(...)` equation per cell for each mapping.

# Example
```julia
eqs = connect_faces(
    (cac, :thermal_right) => (fuel, :thermal_left),
    (cac, :thermal_left) => (fuel, :thermal_right),
)
```
"""
function connect_faces(mappings::Pair...)
    eqs = Equation[]
    for mapping in mappings
        append!(eqs, connect_faces(mapping))
    end
    return eqs
end

function connect_faces(mapping::Pair)
    (left_sys, left_face) = mapping.first
    (right_sys, right_face) = mapping.second
    n_left = _infer_n(left_sys)
    n_right = _infer_n(right_sys)
    n_left == n_right ||
        throw(ArgumentError("face sizes do not match: $n_left != $n_right"))
    return Equation[
        connect(port(left_sys, left_face, i), port(right_sys, right_face, i)) for i in 1:n_left
    ]
end

# Real-valued defaults of `params`, skipping parameters with no default or a
# non-Real default.
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

function _infer_n(sys)
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))
    n = count(s -> startswith(s, "thermal_left"), sub_names)
    n == 0 && throw(
        ArgumentError(
            "could not detect thermal port count in system $(ModelingToolkit.getname(sys)); pass an uncompiled ChannelAndContacts instance",
        ),
    )
    return n
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
        comp_eqs = if ndims(T_sym) == 1
            n = length(T_sym)
            [pk_T_source[j] ~ T_sym[j] for j in 1:n]
        else
            nz, nx = size(T_sym)
            [pk_T_source[(jz - 1) * nx + jx] ~ T_sym[jz, jx] for jz in 1:nz for jx in 1:nx]
        end
        append!(eqs, comp_eqs)
    end
    return eqs
end
