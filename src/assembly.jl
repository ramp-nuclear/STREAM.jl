"""
    assembly(connections, components...; name, parameters=[], t=t_nounits) -> System

Compose `components` into one system joined by `connections`.

`connections` may nest freely: a list can hold single equations next to the vectors
[`inseries`](@ref), [`inparallel`](@ref), [`face`](@ref) and [`faces`](@ref) return, and
broadcast equations such as `ch.T_wall_left .~ T_wall`, with no splatting.

# Arguments
- `connections`: an `Equation`, or any vector or tuple of equations and nested collections
  of them
- `components`: the uncompiled systems to compose

# Keywords
- `name`: required, the system name. `@named sys = assembly(...)` supplies it.
- `parameters`: parameters the connections do not mention but the model needs, such as one
  a callback reads
- `t`: the independent variable

# Returns
Uncompiled `System`, ready for `mtkcompile`.

# Example
```julia
conns = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.T_wall_left .~ 100.0,
]
@named sys = assembly(conns, pump, hx, ch)
```
"""
function assembly(connections, components...; name, parameters=[],
                  t=ModelingToolkit.t_nounits)
    eqs = _flatten_eqs!(Equation[], connections)
    sys = isempty(parameters) ? System(eqs, t; name=name) :
          System(eqs, t, [], parameters; name=name)
    return compose(sys, components...)
end

"""
    _flatten_eqs!(eqs, x) -> Vector{Equation}

Append every equation in `x` to `eqs`, descending into vectors, tuples and symbolic arrays.
"""
_flatten_eqs!(eqs, x::Equation) = push!(eqs, x)
# Iterating a symbolic array yields bare symbolic terms; collect materialises the equations.
_flatten_eqs!(eqs, x::ModelingToolkit.Symbolics.Arr) = _flatten_eqs!(eqs, collect(x))
function _flatten_eqs!(eqs, x::Union{AbstractArray,Tuple})
    foreach(e -> _flatten_eqs!(eqs, e), x)
    return eqs
end
_flatten_eqs!(eqs, x) = throw(ArgumentError("expected an equation or a collection of them, got $(typeof(x))"))

"""
    port(sys, face, i::Int)
    port(sys, face, var::Symbol)
    port(ports::AbstractVector, var::Symbol)

Reach one element of an indexed connector array, or one variable across all of its elements.

Per-cell thermal faces are separate subsystems named `thermal_left1 … thermal_leftn`, so
reaching cell `i` means building the name. [`face`](@ref) and [`faces`](@ref) are built on this.

# Arguments
- `sys`: MTK system instance
- `face`: connector array name (Symbol), such as `:thermal_left`
- `i`: 1-based cell index (Int)
- `var`: connector variable name (Symbol), such as `:T` or `:Q`
- `ports`: a vector of connectors not yet composed into a system, as a component holds them
  while it writes its equations

# Returns
With `i`, the namespaced connector subsystem (for example `sys.thermal_left3`), ready to pass
to `connect`. With `var`, a vector holding that variable of every cell, in cell order, ready
for broadcast equations and for indexing a solution.

# Example
```julia
connect(port(cac, :thermal_right, 3), port(fuel, :thermal_left, 3))
port(cac, :thermal_left, :T) .~ cac.T      # pin every left wall to the coolant
sol[port(cac, :thermal_right, :T), end]    # wall temperatures at the last time
```
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
port(sys, face::Symbol, var::Symbol) = port(port.(Ref(sys), face, 1:var_length(sys, face)), var)
port(ports::AbstractVector, var::Symbol) = getproperty.(ports, var)

"""
    var_length(sys, prefix) -> Int

Count the subsystems of `sys` whose name starts with `prefix`, giving the width of an indexed
connector array.

A component with `n` thermal faces per side carries `n` separate subsystems named
`thermal_left1 … thermal_leftn` rather than one array-valued connector, so the count comes from
the names.

`ChannelAndContacts` and `HeatDiffusion` carry such arrays. `Channel` and `ChannelHeatFlux` do
not, and raise.

# Arguments
- `sys`: an uncompiled system. Compilation flattens away the subsystem names this reads.
- `prefix`: a `Symbol` naming the connector family, such as `:thermal_left` or `:thermal_right`

# Returns
The number of matching subsystems, at least 1.

# Throws
`ArgumentError` when nothing matches.

# Example
```julia
@named cac = ChannelAndContacts(; n=4, geometry=geom)
var_length(cac, :thermal_left)    # 4
```
"""
function var_length(sys, prefix)
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))
    n = count(s -> startswith(s, string(prefix)), sub_names)
    n == 0 && throw(
        ArgumentError(
            "found no subsystem named $(prefix)* in $(ModelingToolkit.getname(sys)), so its " *
            "$(prefix) count cannot be read. Pass an uncompiled component that carries " *
            "per-cell connector arrays, such as ChannelAndContacts or HeatDiffusion.",
        ),
    )
    return n
end
