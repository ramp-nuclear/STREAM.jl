# geometry.jl — PipeGeometry descriptor for STREAM.jl
#

"""
    PipeGeometry{T}

Geometry descriptor for a heated channel or pipe. The flow-geometry fields are typed `T`,
which is `Float64` for a fixed geometry and `Num` when a dimension is a design knob (from
`@design_knob`); in the symbolic case the derived quantities carry the knob expression so
`remake` can scan them without rebuilding the model.

Fields:
- `L`                — channel length [m]
- `Dh`               — hydraulic diameter [m]: 4*area/wet_perimeter; drives Re, Nu, h_tc, Darcy-Weisbach dP
- `A`                — flow cross-section area [m²]
- `heated_perimeter` — total heated perimeter [m]: sum of both face contributions
- `wet_perimeter`    — total wetted perimeter [m]: used to derive Dh
- `heated_parts`     — heated perimeter per face [m]: (left_face, right_face)
- `width`            — longer cross-section dimension [m]: max(edge1, edge2) for rect; D for circular
- `depth`            — shorter cross-section dimension [m]: min(edge1, edge2) for rect; D for circular

The edge ordering for `width`/`depth` uses a symbolic `ifelse`, so a knob-driven edge scans
through them too (and through aspect-ratio / plate-gap correlations that read them).

Factory functions (preferred constructors):
- `PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)` — rectangular channel
- `PipeGeometry_circular(L, D)` — circular pipe
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

Construct a `PipeGeometry` for a rectangular channel.

- `L`            — channel length [m]
- `edge1`        — first cross-section edge [m] (e.g. plate width)
- `edge2`        — second cross-section edge [m] (e.g. channel gap)
- `heated_edge`  — width of each heated face [m]
- `one_sided`    — `:left`, `:right`, or `nothing` (default, both sides heated)

Any length may be a design knob. Dh = 4*area/wet_perimeter where area = edge1*edge2 and
wet_perimeter = 2*(edge1+edge2).
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

Construct a `PipeGeometry` for a circular pipe.

- `L` — channel length [m]
- `D` — pipe diameter [m]

Either length may be a design knob. Dh = D (exact for circular cross-section).
heated_parts = (perimeter, 0) because it is circular, not annular.
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
