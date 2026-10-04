"""
    PipeGeometry{T}

The cross-section and length of a channel or pipe. Build one with
[`PipeGeometry_rectangular`](@ref) or [`PipeGeometry_circular`](@ref).

The fields are `Float64` for a fixed geometry. When a dimension is a design knob (see
[`@design_knob`](@ref)) they are symbolic, so `remake` can change the geometry without
rebuilding the model.

# Fields
- `L`: length [m]
- `Dh`: hydraulic diameter `4A / wet_perimeter` [m]
- `A`: flow area [m²]
- `heated_perimeter`: total heated perimeter [m], the sum of `heated_parts`
- `wet_perimeter`: wetted perimeter [m]
- `heated_parts`: heated perimeter of the left and right faces [m]
- `width`: the longer cross-section edge [m], `D` for a circle
- `depth`: the shorter cross-section edge [m], `D` for a circle
"""
struct PipeGeometry{T<:Real}
    L                ::T
    Dh               ::T
    A                ::T
    heated_perimeter ::T
    wet_perimeter    ::T
    heated_parts     ::NTuple{2,T}
    width            ::T
    depth            ::T
end

# Coerce a length input: plain numbers become Float64 (the fixed-geometry behavior); a
# design knob or any other Num passes through so geometry derives symbolically.
_lenparam(x::Num) = x
_lenparam(x::Real) = Float64(x)

"""
    PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)

A rectangular channel, such as the gap between two fuel plates:

    A = edge1 · edge2,    P_wet = 2 (edge1 + edge2),    Dh = 4A / P_wet

Any length may be a design knob.

# Arguments
- `L`: length [m]
- `edge1`, `edge2`: the two cross-section edges [m], in either order, such as the plate width
  and the channel gap
- `heated_edge`: heated width of each face [m]
- `one_sided`: `:left` or `:right` to heat one face only, or `nothing` for both (default)

# Returns
A [`PipeGeometry`](@ref).

# Examples
A 70 mm by 1.27 mm MTR channel, 0.6 m long:
```jldoctest
julia> g = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
PipeGeometry
  L      0.6 m
  Dh     0.0024947 m
  A      8.89e-5 m^2
  width  0.07 m
  depth  0.00127 m
  perimeter  wet 0.14254 m, heated 0.14 m
  heated_parts  (0.07, 0.07) m

julia> g.Dh
0.0024947383190683323
```
"""
function PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)
    _L = _lenparam(L)
    _e1 = _lenparam(edge1)
    _e2 = _lenparam(edge2)
    _he = _lenparam(heated_edge)
    # If any length is symbolic, promote all flow lengths to Num so the struct fields share
    # one element type. A fixed (all-numeric) geometry never enters this branch.
    if any(x -> x isa Num, (_L, _e1, _e2, _he))
        _L, _e1, _e2, _he = Num(_L), Num(_e1), Num(_e2), Num(_he)
    end
    area = _e1 * _e2
    wet_perimeter = 2.0 * (_e1 + _e2)
    Dh = 4.0 * area / wet_perimeter
    if one_sided === nothing
        heated_perimeter = 2.0 * _he
        heated_parts = (_he, _he)
    elseif one_sided === :left
        heated_perimeter = _he
        heated_parts = (_he, zero(_he))
    elseif one_sided === :right
        heated_perimeter = _he
        heated_parts = (zero(_he), _he)
    else
        throw(ArgumentError("one_sided must be :left, :right, or nothing; got $one_sided"))
    end
    # Symbolic-safe ordering: ifelse evaluates correctly at any knob value, so a knob-driven
    # edge scans through width/depth (and the correlations that read them). For a fixed
    # geometry it folds to the same Float64 as max/min.
    _width = ifelse(_e1 >= _e2, _e1, _e2)
    _depth = ifelse(_e1 >= _e2, _e2, _e1)
    return PipeGeometry(
        _L, Dh, area, heated_perimeter, wet_perimeter, heated_parts, _width, _depth
    )
end

"""
    PipeGeometry_circular(L, D)

A circular pipe, `Dh = D`. Its whole perimeter counts as the left face, so
`heated_parts = (πD, 0)`. Either length may be a design knob.

# Arguments
- `L`: length [m]
- `D`: diameter [m]

# Returns
A [`PipeGeometry`](@ref).

# Examples
```jldoctest
julia> PipeGeometry_circular(1.0, 0.01).A
7.853981633974483e-5
```
"""
function PipeGeometry_circular(L, D)
    _L = _lenparam(L)
    _D = _lenparam(D)
    if _L isa Num || _D isa Num
        _L, _D = Num(_L), Num(_D)
    end
    area = π * _D^2 / 4
    perimeter = π * _D
    heated_parts = (perimeter, zero(perimeter))
    return PipeGeometry(_L, _D, area, perimeter, perimeter, heated_parts, _D, _D)
end

function Base.show(io::IO, ::MIME"text/plain", g::PipeGeometry)
    r(x) = x isa Real ? round(x; sigdigits=5) : x
    print(io, "PipeGeometry")
    print(io, "\n  L      ", r(g.L), " m")
    print(io, "\n  Dh     ", r(g.Dh), " m")
    print(io, "\n  A      ", r(g.A), " m^2")
    print(io, "\n  width  ", r(g.width), " m")
    print(io, "\n  depth  ", r(g.depth), " m")
    print(io, "\n  perimeter  wet ", r(g.wet_perimeter),
          " m, heated ", r(g.heated_perimeter), " m")
    print(io, "\n  heated_parts  (", r(g.heated_parts[1]), ", ", r(g.heated_parts[2]), ") m")
end
