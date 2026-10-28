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
`Vector{Equation}`, which goes into an [`assembly`](@ref STREAM.Assemblies.assembly) connection list as is.

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
    chain = collect(systems)
    return connect.(_outlet.(chain[1:(end - 1)]), _inlet.(chain[2:end]))
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

"""
    _branch_systems(branch) -> Vector

The components along one branch of [`inparallel`](@ref): a tuple or vector of them in series,
or a single component.
"""
_branch_systems(branch::Union{Tuple,AbstractVector}) = collect(branch)
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
`Vector{Equation}`, which goes into an [`assembly`](@ref STREAM.Assemblies.assembly) connection list as is.

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
    @flowgraph a --> b --> c || (d --> e) --> a
    @flowgraph begin ... end

The connection equations of a flow path drawn with arrows: `-->` puts its two sides in
series, and `||` puts them in parallel, as branches between the steps before and after it.
`||` binds tighter than `-->`, so a branch of several components is written in parentheses.
A `begin ... end` block holds several paths, one per line, and gives all their equations.

A name in the path is a component, a `FlowPort`, or a path built outside: a tuple or vector of
components in series, such as the one [`weighted`](@ref) returns. A branch is a component, a
path built outside, or `(b --> c)`, and `paths... || d` adds every branch `paths` holds. A
parallel block needs a component or port on each side, and a branch holds no parallel block
of its own.

The equations are the ones [`inseries`](@ref) and [`inparallel`](@ref) give: the path above
is `inseries(a, b)`, `inparallel(b, [c, (d, e)], a)`. Inside [`@assembly`](@ref) an arrow
line needs no `@flowgraph`.

# Returns
`Vector{Equation}`.

# Throws
- `ArgumentError`: for a path of one component, a parallel block at either end of a path or
  next to another, a parallel block inside a branch, or a bracketed list in a path

# Example
```julia
hot = (hx_hot, riser)                     # a path built outside
@flowgraph pump --> hot || bypass || (hx_cold --> downcomer) --> pump
```
"""
macro flowgraph(ex)
    Meta.isexpr(ex, :block) || return esc(_flow_expr(ex))
    paths = [_flow_expr(line) for line in ex.args if !(line isa LineNumberNode)]
    return esc(:($vcat($Equation[], $(paths...))))
end

"""
    _flow_expr(ex) -> Expr

The call that builds the equations of the arrow path `ex`, as [`@flowgraph`](@ref) and
[`@assembly`](@ref) expand it.
"""
function _flow_expr(ex)
    steps = map(_split(ex, :-->)) do step
        Meta.isexpr(step, :vect) &&
            throw(ArgumentError("write a parallel block as `a || b`, not as a list"))
        Meta.isexpr(step, :||) || return step
        return :($_Parallel(Any[$(map(_branch_expr, _split(step, :||))...)]))
    end
    return :($_flow($(steps...)))
end

"""
    _split(ex, head) -> Vector

The operands of a chain of the binary syntax `head`, `a --> b --> c` giving `[a, b, c]`.
"""
function _split(ex, head)
    Meta.isexpr(ex, head) || return Any[ex]
    return [_split(first(ex.args), head); _split(last(ex.args), head)]
end

"""
    _branch_expr(ex)

One branch of a parallel block: `b --> c` becomes a call making the path `(b, c)`, and any
other expression is left as written.
"""
function _branch_expr(ex)
    steps = _split(ex, :-->)
    any(s -> Meta.isexpr(s, :||), steps) &&
        throw(ArgumentError("a branch of a parallel block cannot hold a parallel block"))
    return length(steps) == 1 ? ex : :($_path($(steps...)))
end

"""
    _Parallel(branches)

A parallel block in a flow path, between the steps on either side of it.
"""
struct _Parallel{T}
    branches::T
end

"""
    _steps(x) -> Vector

The components `x` stands for in a path: the elements of a tuple or vector, or `x` itself.
"""
_steps(x::Union{Tuple,AbstractVector}) = collect(Any, x)
_steps(x) = Any[x]

"""
    _path(steps...) -> Tuple

A branch's components in series, with paths built outside spliced in.
"""
_path(steps...) = Tuple(mapreduce(_steps, vcat, steps))

"""
    _flow(steps...) -> Vector{Equation}

The equations of a flow path: [`inseries`](@ref) along each stretch between parallel blocks,
and [`inparallel`](@ref) across each block from the step before it to the step after it.
"""
function _flow(steps...)
    stretches, blocks = [Any[]], _Parallel[]
    for step in steps
        if step isa _Parallel
            push!(blocks, step)
            push!(stretches, Any[])
        else
            append!(last(stretches), _steps(step))
        end
    end
    any(isempty, stretches) &&
        throw(ArgumentError("a parallel block needs a component on each side"))
    isempty(blocks) && length(only(stretches)) < 2 &&
        throw(ArgumentError("a flow path needs at least two components"))
    series = [inseries(s...) for s in stretches if length(s) > 1]
    parallel = [inparallel(last(stretches[i]), b.branches, first(stretches[i + 1]))
                for (i, b) in enumerate(blocks)]
    return reduce(vcat, [series; parallel]; init=Equation[])
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
[`inseries`](@ref), [`inparallel`](@ref) and [`assembly`](@ref STREAM.Assemblies.assembly) alike. It holds `components`
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
    return connect.(getproperty.(sources, source_port), port(target, face))
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
faces(mappings::Pair...) = _flat(map(faces, mappings))

function faces(mapping::Pair)
    left, right = port(mapping.first...), port(mapping.second...)
    length(left) == length(right) ||
        throw(ArgumentError("face sizes do not match: $(length(left)) != $(length(right))"))
    return connect.(left, right)
end

"""
    temperature_feedback(pk, components) -> Vector{Equation}

Bind each component's temperatures to the `pk.T_source_<name>` unknowns a
[`PointKinetics`](@ref) built with `temp_worth` reads its feedback from, closing the loop
between the neutronics and the thermal hydraulics.

# Arguments
- `pk`: uncompiled `PointKinetics` system built with `temp_worth`
- `components`: the components whose temperatures feed `pk`, as reached through the system
  that composes them, such as `[rods.cac]`, not the variables they were built in. Their
  feedback coefficients are in `temp_worth`, not here.

# Returns
`Vector{Equation}`, one equation per cell of every component: `pk.T_source_<name>[j] ~
comp.T[j]` for a channel, and the cells of a `HeatDiffusion` a row at a time,
`pk.T_source_<name>[(jz-1)*nx + jx] ~ comp.T[jz, jx]`.

# Example: a component wrapped inside `symmetric_plate`
```julia
rods = symmetric_plate(cac, fuel; name=:rods)
@named pk = PointKinetics(ctrl; temp_worth=Dict(rods.cac => alpha))
eqs = temperature_feedback(pk, [rods.cac])
# eqs has n equations binding pk.T_source_cac[j] ~ rods.cac.T[j]
```
"""
function temperature_feedback(pk, components)
    bind(comp) = getproperty(pk, Symbol(:T_source_, nameof(comp))) .~ _row_major(comp.T)
    return _flat(map(bind, components))
end
