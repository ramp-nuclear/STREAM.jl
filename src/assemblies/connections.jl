"""
    inseries(systems...) -> Vector{Equation}

Build the hydraulic connection equations for a simple series chain of two-port components,
connecting each component's `outlet` to the next component's `inlet`.

A two-port component exposes exactly one `inlet` and one `outlet` [`FlowPort`](@ref); see
`HydraulicTwoPort` for which components qualify. Channels also expose both ports and chain the
same way.

The chain may also start or end at a `FlowPort` of its own, such as a [`Tank`](@ref) nozzle
or an [`Environment`](@ref)'s `port`, which then connects to the first component's `inlet`
or the last one's `outlet`.

# Arguments
- `systems`: two or more uncompiled systems exposing `inlet` and `outlet` `FlowPort`s, the
  first and the last of which may be `FlowPort`s instead

# Returns
`Vector{Equation}`, which goes into an [`assembly`](@ref) connection list as is.

# Throws
- `ArgumentError`: for fewer than two systems, or a `FlowPort` anywhere but at an end

# Example
```julia
conns = [
    inseries(pump, hx, resistor, pump),
    pump.inlet.p ~ 1.0e5,
]
inseries(pool.bottom, breach, ambient.port)   # a pool drains through a break
```
"""
function inseries(systems...)
    length(systems) >= 2 ||
        throw(ArgumentError("inseries requires at least two systems"))
    for sys in systems[2:(end - 1)]
        _check_not_port(sys, "inside an inseries chain")
    end
    return Equation[
        connect(_outlet(systems[i]), _inlet(systems[i + 1])) for i in 1:(length(systems) - 1)
    ]
end

"""
    _inlet(x), _outlet(x)

The `inlet` or `outlet` of a component, or `x` itself when it is a connector such as a
`FlowPort`.
"""
_inlet(x) = ModelingToolkit.isconnector(x) ? x : getproperty(x, :inlet)
_outlet(x) = ModelingToolkit.isconnector(x) ? x : getproperty(x, :outlet)

"""
    _check_not_port(x, place)

Throw an `ArgumentError` when `x` is a connector. Between two components, a port would join
them both to whatever else it belongs to, making a tee where the call reads as a pipe.
"""
function _check_not_port(x, place)
    ModelingToolkit.isconnector(x) || return nothing
    throw(ArgumentError(
        "$(nameof(x)) is a port, and a port can only start or end the flow path, not sit " *
        "$place. Connect a junction with `connect` instead.",
    ))
end

_branch_systems(branch::Tuple) = collect(branch)
_branch_systems(branch::AbstractVector) = collect(branch)
_branch_systems(branch) = Any[branch]

"""
    inparallel(upstream, branches, downstream) -> Vector{Equation}

Build the hydraulic connection equations for a parallel block. `upstream.outlet` feeds every
branch inlet, each branch may be a single two-port component or a tuple/vector of components
connected in series internally, and all branch outlets merge into `downstream.inlet`.
`upstream` and `downstream` may be `FlowPort`s themselves, such as a [`Tank`](@ref) nozzle.

# Arguments
- `upstream`: uncompiled system exposing an `outlet` `FlowPort`, or a `FlowPort`
- `branches`: collection of branch paths; each branch is either one uncompiled two-port system
  or a tuple/vector of such systems
- `downstream`: uncompiled system exposing an `inlet` `FlowPort`, or a `FlowPort`

# Returns
`Vector{Equation}`, which goes into an [`assembly`](@ref) connection list as is.

# Throws
- `ArgumentError`: for no branches, or a `FlowPort` inside a branch

# Example
```julia
conns = [
    inseries(pump, hx),
    inparallel(hx, ((R1, G1), R2), pump),
    pump.inlet.p ~ 1.0e5,
]
```
"""
function inparallel(upstream, branches, downstream)
    length(branches) >= 1 ||
        throw(ArgumentError("inparallel requires at least one branch"))
    branch_paths = [_branch_systems(branch) for branch in branches]
    for path in branch_paths, sys in path
        _check_not_port(sys, "inside an inparallel branch")
    end
    branch_inlets = [getproperty(path[1], :inlet) for path in branch_paths]
    branch_outlets = [getproperty(path[end], :outlet) for path in branch_paths]
    eqs = Equation[
        connect(_outlet(upstream), branch_inlets...),
        connect(branch_outlets..., _inlet(downstream)),
    ]
    for path in branch_paths
        length(path) > 1 && append!(eqs, inseries(path...))
    end
    return eqs
end

"""
    _FlowWeight(k; name) -> System

Scale the mass flow between two ports. [`weighted`](@ref) is the only caller, and places one
of these at each end of a branch.

    outlet.ṁ = -k·inlet.ṁ,    outlet.p = inlet.p

Pressure and temperature pass through unchanged. Mass does not: the component holds no fluid
and adds no heat, and the imbalance is the whole point. That is also why it stays private.

`k` has to be an `Integer` or a `Rational`, and it enters the equations as a fixed number
rather than a parameter, so that `mtkcompile` can find the loop's free flow by exact linear
elimination over integer coefficients.

# Arguments
- `k`: flow ratio, outlet to inlet, such as `1//N`
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`.
"""
function _FlowWeight(k::Union{Integer,Rational}; name)
    q = Rational(k)
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[
        # Written as a cross-multiplied integer ratio rather than as k*inlet.ṁ. A Float or a
        # symbolic k hides the loop's free flow from mtkcompile's exact elimination, and the
        # loop then fails to compile as over-determined.
        denominator(q) * outlet.ṁ ~ -numerator(q) * inlet.ṁ,
        outlet.p ~ inlet.p,
        outlet.T ~ instream(inlet.T),
        inlet.T ~ instream(outlet.T),
    ]
    return compose(System(eqs, t, [], []; name=name), inlet, outlet)
end

"""
    weighted(N, components...; name) -> Tuple

One branch standing for `N` identical copies of itself.

A core with fifty identical assemblies is fifty copies of the same equations. Model one and
tell the junctions at either end that it counts fifty times, and the solve carries a single
channel's unknowns:

```julia
branch = weighted(50, pool, orifice, ch; name=:hot)
conns = [inparallel(flywheel, [branch], riser), flywheel.outlet.p ~ ATM]
@named core = assembly(conns, flywheel, riser, branch...)
```

The returned tuple is both the path to wire and the systems to compose, so it splats into
[`inseries`](@ref), [`inparallel`](@ref) and [`assembly`](@ref) alike. It holds `components`
in flow order between two private flow weights, one of `1//N` and one of `N`, named
`<name>_weight_in` and `<name>_weight_out`.

`ch` carries one assembly's flow and reaches one assembly's wall temperature. The junctions
see `N` times that flow, and since a junction mixes temperatures weighted by the flow
through it, the branch also counts `N` times in the energy balance.

# Arguments
- `N`: how many identical copies the branch stands for, a positive integer
- `components`: the branch, uncompiled systems with `inlet` and `outlet`, in flow order

# Keywords
- `name`: required, the prefix the two weights are named from

# Returns
A tuple of systems, first to last.

# Throws
- `ArgumentError`: for no components, or `N` not a positive integer
- `UndefKeywordError`: when `name` is left out
"""
function weighted(N::Integer, components...; name::Symbol)
    isempty(components) && throw(ArgumentError("weighted needs at least one component"))
    N > 0 || throw(ArgumentError("N must be positive, got $N"))
    return (
        _FlowWeight(1//N; name=Symbol(name, :_weight_in)),
        components...,
        _FlowWeight(N; name=Symbol(name, :_weight_out)),
    )
end

function weighted(N, components...; name::Symbol)
    throw(ArgumentError("N must be a positive integer, got $N"))
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
    n_left = var_length(left_sys, left_face)
    n_right = var_length(right_sys, right_face)
    n_left == n_right ||
        throw(ArgumentError("face sizes do not match: $n_left != $n_right"))
    return Equation[
        connect(port(left_sys, left_face, i), port(right_sys, right_face, i)) for i in 1:n_left
    ]
end

"""
    temperature_feedback(pk, components) -> Vector{Equation}

Generate binding equations that wire each component's existing `T` symbolic to the
corresponding `pk.T_source_<name>` unknowns inside `PointKinetics`. Used together
with [`assembly`](@ref) to close the neutronics<->thermal-hydraulics loop.

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
