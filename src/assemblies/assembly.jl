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
