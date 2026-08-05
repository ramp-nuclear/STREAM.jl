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
    face(sources, target, face; source_port=:thermal) -> Vector{Equation}

Connect one per-cell source array to one thermal face of a target system.

# Arguments
- `sources`: vector of systems exposing the connector `source_port`
- `target`: system exposing an indexed thermal face such as `:thermal_left` or `:thermal_right`
- `face`: target face symbol (`:thermal_left` or `:thermal_right`)
- `source_port`: connector name on each source system (default `:thermal`)

# Returns
`Vector{Equation}` with one `connect(...)` equation per cell.
"""
function face(sources, target, face::Symbol; source_port::Symbol=:thermal)
    return Equation[
        connect(getproperty(sources[i], source_port), port(target, face, i)) for
        i in eachindex(sources)
    ]
end

"""
    faces(mapping::Pair) -> Vector{Equation}
    faces(mappings::Pair...) -> Vector{Equation}

Connect indexed thermal faces cell-by-cell between systems.

# Arguments
- `mapping`: face mapping written as `(left_system, :left_face) => (right_system, :right_face)`
- `mappings...`: one or more such mappings

# Returns
Flattened `Vector{Equation}` with one `connect(...)` equation per cell for each mapping.

# Example
```julia
eqs = faces(
    (cac, :thermal_right) => (fuel, :thermal_left),
    (cac, :thermal_left) => (fuel, :thermal_right),
)
```
"""
function faces(mappings::Pair...)
    eqs = Equation[]
    for mapping in mappings
        append!(eqs, faces(mapping))
    end
    return eqs
end

function faces(mapping::Pair)
    (left_sys, left_face) = mapping.first
    (right_sys, right_face) = mapping.second
    n_left = _infer_n(left_sys, left_face)
    n_right = _infer_n(right_sys, right_face)
    n_left == n_right ||
        throw(ArgumentError("face sizes do not match: $n_left != $n_right"))
    return Equation[
        connect(port(left_sys, left_face, i), port(right_sys, right_face, i)) for i in 1:n_left
    ]
end

"""
    adiabatic_face(channel, face) -> Vector{Equation}

Close an unheated channel face. A face whose heated perimeter is zero carries no heat, so
its port `Q` collapses to `0 ~ 0` and the wall temperature is left with no equation of its
own. This pins it to the local coolant temperature, which is what an insulated wall settles
at anyway.

`PipeGeometry_circular` produces exactly this situation: `heated_parts` is `(perimeter, 0)`,
so the right face of a circular channel always needs closing.

# Arguments
- `channel`: uncompiled system carrying an indexed thermal face and a per-cell `T`
- `face`: face symbol, `:thermal_left` or `:thermal_right`

# Returns
`Vector{Equation}` with one equation per cell.
"""
function adiabatic_face(channel, face::Symbol)
    n = _infer_n(channel, face)
    T = getproperty(channel, :T)
    return Equation[port(channel, face, i).T ~ T[i] for i in 1:n]
end

# Count the ports on one indexed thermal face. The match is anchored: `thermal_left` counts
# `thermal_left1`, never `thermal_left_inner1`, which a bare prefix test would fold in.
function _infer_n(sys, face::Symbol)
    prefix = string(face)
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))
    n = count(sub_names) do name
        startswith(name, prefix) || return false
        suffix = SubString(name, ncodeunits(prefix) + 1)
        !isempty(suffix) && all(isdigit, suffix)
    end
    n == 0 && throw(
        ArgumentError(
            "no `$face` ports on system $(ModelingToolkit.getname(sys)); pass an uncompiled system that carries that face",
        ),
    )
    return n
end

_infer_n(sys) = _infer_n(sys, :thermal_left)




"""
    temperature_feedback(pk, components) -> Vector{Equation}

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
eqs = temperature_feedback(pk, [rods.cac])
# eqs has n equations binding pk.T_source_cac[j] ~ rods.cac.T[j]
```
"""
function temperature_feedback(pk, components)
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
