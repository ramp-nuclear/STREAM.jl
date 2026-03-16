# geometry.jl — PipeGeometry descriptor for STREAM.jl
#
# Design note (q_wall indirection):
# Channel uses a single ThermalPort carrying total Q_wall (W), then splits
# internally: q_wall[i] = thermal.Q_flow / n per cell. This indirection
# exists so that a future refactor to per-cell ThermalPorts only changes
# the port declaration and q_wall binding — the energy balance loop
# D(T[i]) ~ ... is untouched.
#
# Note: `Channel` is declared as a new generic function here to avoid
# conflict with Base.Channel (Julia's built-in concurrency channel type).

"""
    PipeGeometry

Geometry descriptor for a heated channel or pipe.

Fields:
- `L`                — channel length [m]
- `Dh`               — hydraulic diameter [m]: 4*area/wet_perimeter; drives Re, Nu, h_tc, Darcy-Weisbach dP
- `A`                — flow cross-section area [m²]
- `heated_perimeter` — total heated perimeter [m]: sum of both face contributions
- `wet_perimeter`    — total wetted perimeter [m]: used to derive Dh
- `heated_parts`     — heated perimeter per face [m]: (left_face, right_face)
- `width`            — longer cross-section dimension [m]: max(edge1, edge2) for rect; D for circular
- `depth`            — shorter cross-section dimension [m]: min(edge1, edge2) for rect; D for circular

Factory functions (preferred constructors):
- `PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)` — rectangular channel
- `PipeGeometry_circular(L, D)` — circular pipe

Do NOT call the inner positional constructor directly.
"""
struct PipeGeometry
    L                ::Float64                   # channel length [m]
    Dh               ::Float64                   # hydraulic diameter [m]: 4*area/wet_perimeter
    A                ::Float64                   # flow cross-section area [m²]
    heated_perimeter ::Float64                   # total heated perimeter [m]
    wet_perimeter    ::Float64                   # total wetted perimeter [m]
    heated_parts     ::NTuple{2,Float64}         # heated perimeter per face [m]: (left, right)
    width            ::Float64                   # longer cross-section dimension [m]: max(e1,e2) or D
    depth            ::Float64                   # shorter cross-section dimension [m]: min(e1,e2) or D
end

"""
    PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)

Construct a `PipeGeometry` for a rectangular channel.

- `L`            — channel length [m]
- `edge1`        — first cross-section edge [m] (e.g. plate width)
- `edge2`        — second cross-section edge [m] (e.g. channel gap)
- `heated_edge`  — width of each heated face [m]
- `one_sided`    — `:left`, `:right`, or `nothing` (default, both sides heated)

Dh = 4*area/wet_perimeter where area = edge1*edge2 and wet_perimeter = 2*(edge1+edge2).
"""
function PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)
    _L    = Float64(L)
    _e1   = Float64(edge1)
    _e2   = Float64(edge2)
    _he   = Float64(heated_edge)
    area          = _e1 * _e2
    wet_perimeter = 2.0 * (_e1 + _e2)
    Dh            = 4.0 * area / wet_perimeter
    if one_sided === nothing
        heated_perimeter = 2.0 * _he
        heated_parts     = (_he, _he)
    elseif one_sided === :left
        heated_perimeter = _he
        heated_parts     = (_he, 0.0)
    elseif one_sided === :right
        heated_perimeter = _he
        heated_parts     = (0.0, _he)
    else
        error("one_sided must be :left, :right, or nothing; got $one_sided")
    end
    _width = max(_e1, _e2)
    _depth = min(_e1, _e2)
    PipeGeometry(_L, Dh, area, heated_perimeter, wet_perimeter, heated_parts, _width, _depth)
end

"""
    PipeGeometry_circular(L, D)

Construct a `PipeGeometry` for a circular pipe.

- `L` — channel length [m]
- `D` — pipe diameter [m]

Dh = D (exact for circular cross-section). heated_parts = (π*D/2, π*D/2) (symmetric split).
"""
function PipeGeometry_circular(L, D)
    _L         = Float64(L)
    _D         = Float64(D)
    area       = π * _D^2 / 4
    perimeter  = π * _D
    heated_parts = (perimeter / 2, perimeter / 2)
    # Dh = 4*(π*D²/4)/(π*D) = D — exact
    PipeGeometry(_L, _D, area, perimeter, perimeter, heated_parts, _D, _D)
end
