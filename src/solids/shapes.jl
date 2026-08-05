# shapes.jl — composing a cross-section out of Meshes.jl geometries.
#
# No primitives are defined here. `Meshes.Box` is the rectangle and `Meshes.Ball` is the
# circle. What Meshes does not supply is a combination tree you can ask "is this point
# inside", so that is what this file adds, along with the three queries the mesher needs:
# membership, distance to a named boundary, and the parameter intervals in which a straight
# segment lies inside a shape.

"""
    Shape

A cross-section region, either a single `Meshes` geometry or a combination of them.

Build one by lifting a geometry with [`shape`](@ref) and combining with `-`, `∪` and `∩`:

```julia
rod = shape(Box((-6e-3, -6e-3), (6e-3, 6e-3))) - Ball((0.0, 0.0), 3e-3)
```

Only the first term needs lifting; the operators accept a bare geometry on either side.
"""
abstract type Shape end

struct Leaf{G} <: Shape
    geom::G
end

struct ShapeUnion{A<:Shape,B<:Shape} <: Shape
    a::A
    b::B
end

struct ShapeDiff{A<:Shape,B<:Shape} <: Shape
    a::A
    b::B
end

struct ShapeInter{A<:Shape,B<:Shape} <: Shape
    a::A
    b::B
end

"""
    shape(geometry) -> Shape

Lift a `Meshes` geometry into a [`Shape`](@ref) so it can be combined. A `Shape` passes
through unchanged.
"""
shape(s::Shape) = s
shape(g::Meshes.Geometry) = Leaf(g)

const ShapeLike = Union{Shape,Meshes.Geometry}

Base.:-(a::Shape, b::ShapeLike) = ShapeDiff(a, shape(b))
Base.:-(a::Meshes.Geometry, b::Shape) = ShapeDiff(Leaf(a), b)
Base.union(a::Shape, b::ShapeLike) = ShapeUnion(a, shape(b))
Base.union(a::Meshes.Geometry, b::Shape) = ShapeUnion(Leaf(a), b)
Base.intersect(a::Shape, b::ShapeLike) = ShapeInter(a, shape(b))
Base.intersect(a::Meshes.Geometry, b::Shape) = ShapeInter(Leaf(a), b)

"""
    inside(s::Shape, p) -> Bool
    inside(s::Shape, x, y) -> Bool

Whether a point lies in the region. Points on a boundary follow `Meshes`' own convention
for the underlying geometry.
"""
inside(s::Leaf, p::Meshes.Point) = p ∈ s.geom
inside(s::ShapeUnion, p::Meshes.Point) = inside(s.a, p) || inside(s.b, p)
inside(s::ShapeDiff, p::Meshes.Point) = inside(s.a, p) && !inside(s.b, p)
inside(s::ShapeInter, p::Meshes.Point) = inside(s.a, p) && inside(s.b, p)
inside(s::Shape, x::Real, y::Real) = inside(s, Meshes.Point(x, y))

"""
    dist_to_edge(s::Shape, p) -> Float64
    dist_to_edge(s::Shape, x, y) -> Float64

Distance from a point to the nearest leaf boundary in `s`, in metres. Used to decide which
tagged shape a cut face belongs to, so it measures distance to the geometry's own edge
rather than to the composed region's edge: a hole's rim stays findable even though the
region excludes its interior.
"""
dist_to_edge(s::Leaf, p::Meshes.Point) = _edge_distance(s.geom, p)
dist_to_edge(s::ShapeUnion, p::Meshes.Point) = min(dist_to_edge(s.a, p), dist_to_edge(s.b, p))
dist_to_edge(s::ShapeDiff, p::Meshes.Point) = min(dist_to_edge(s.a, p), dist_to_edge(s.b, p))
dist_to_edge(s::ShapeInter, p::Meshes.Point) = min(dist_to_edge(s.a, p), dist_to_edge(s.b, p))
dist_to_edge(s::Shape, x::Real, y::Real) = dist_to_edge(s, Meshes.Point(x, y))

_xy(p::Meshes.Point) = (u -> Float64(u)).(Tuple(ustrip.(Meshes.to(p))))

function _edge_distance(b::Meshes.Box, p::Meshes.Point)
    x0, y0 = _xy(minimum(b))
    x1, y1 = _xy(maximum(b))
    x, y = _xy(p)
    outx = max(x0 - x, x - x1, 0.0)
    outy = max(y0 - y, y - y1, 0.0)
    (outx > 0 || outy > 0) && return hypot(outx, outy)
    return min(x - x0, x1 - x, y - y0, y1 - y)
end

function _edge_distance(d::Meshes.Ball, p::Meshes.Point)
    cx, cy = _xy(Meshes.center(d))
    x, y = _xy(p)
    return abs(hypot(x - cx, y - cy) - Float64(ustrip(Meshes.radius(d))))
end

_edge_distance(g, ::Meshes.Point) = throw(ArgumentError(
    "dist_to_edge has no method for $(nameof(typeof(g))); it is defined for Box and Ball. " *
    "Add a `_edge_distance` method for the geometry you want to tag."))

# ---------------------------------------------------------------------------
# Segment queries.
#
# The mesher needs the wetted length of a background-grid face, which is the measure of
# the set of parameters where the segment lies inside the domain. Solving that per leaf
# and combining with interval algebra is exact and needs no tolerance, which is why the
# face lengths do not come from the clipped polygon (Sutherland-Hodgman stitches its
# result with zero-width bridges, so its edge list double-counts).
# ---------------------------------------------------------------------------

const Interval = Tuple{Float64,Float64}

"""
    segment_inside(s::Shape, x0, y0, x1, y1) -> Vector{Interval}

The parameter intervals in `[0, 1]` along the segment from `(x0, y0)` to `(x1, y1)` where
the segment lies inside `s`, sorted and disjoint.

# Returns
`Vector{Tuple{Float64,Float64}}`, empty when the segment misses the shape entirely.
"""
segment_inside(s::ShapeUnion, x0, y0, x1, y1) =
    _iunion(segment_inside(s.a, x0, y0, x1, y1), segment_inside(s.b, x0, y0, x1, y1))
segment_inside(s::ShapeDiff, x0, y0, x1, y1) =
    _idiff(segment_inside(s.a, x0, y0, x1, y1), segment_inside(s.b, x0, y0, x1, y1))
segment_inside(s::ShapeInter, x0, y0, x1, y1) =
    _iintersect(segment_inside(s.a, x0, y0, x1, y1), segment_inside(s.b, x0, y0, x1, y1))
segment_inside(s::Leaf, x0, y0, x1, y1) = _segment_inside(s.geom, x0, y0, x1, y1)

function _segment_inside(b::Meshes.Box, x0, y0, x1, y1)
    bx0, by0 = _xy(minimum(b))
    bx1, by1 = _xy(maximum(b))
    lo, hi = 0.0, 1.0
    for (p, d, cmin, cmax) in ((x0, x1 - x0, bx0, bx1), (y0, y1 - y0, by0, by1))
        if d == 0
            (p < cmin || p > cmax) && return Interval[]
        else
            t1, t2 = (cmin - p) / d, (cmax - p) / d
            lo = max(lo, min(t1, t2))
            hi = min(hi, max(t1, t2))
        end
    end
    return hi > lo ? Interval[(lo, hi)] : Interval[]
end

function _segment_inside(d::Meshes.Ball, x0, y0, x1, y1)
    cx, cy = _xy(Meshes.center(d))
    r = Float64(ustrip(Meshes.radius(d)))
    dx, dy = x1 - x0, y1 - y0
    fx, fy = x0 - cx, y0 - cy
    a = dx * dx + dy * dy
    a == 0 && return hypot(fx, fy) <= r ? Interval[(0.0, 1.0)] : Interval[]
    b = 2 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - r * r
    disc = b * b - 4 * a * c
    disc <= 0 && return Interval[]
    sq = sqrt(disc)
    lo = max(0.0, (-b - sq) / (2a))
    hi = min(1.0, (-b + sq) / (2a))
    return hi > lo ? Interval[(lo, hi)] : Interval[]
end

_segment_inside(g, x0, y0, x1, y1) = throw(ArgumentError(
    "segment_inside has no method for $(nameof(typeof(g))); it is defined for Box and Ball."))

function _normalize(iv::Vector{Interval})
    isempty(iv) && return iv
    s = sort(filter(t -> t[2] > t[1], iv); by=first)
    isempty(s) && return Interval[]
    out = Interval[s[1]]
    for (lo, hi) in Iterators.drop(s, 1)
        plo, phi = out[end]
        if lo <= phi
            out[end] = (plo, max(phi, hi))
        else
            push!(out, (lo, hi))
        end
    end
    return out
end

_iunion(a::Vector{Interval}, b::Vector{Interval}) = _normalize(vcat(a, b))

function _iintersect(a::Vector{Interval}, b::Vector{Interval})
    out = Interval[]
    for (alo, ahi) in a, (blo, bhi) in b
        lo, hi = max(alo, blo), min(ahi, bhi)
        hi > lo && push!(out, (lo, hi))
    end
    return _normalize(out)
end

function _idiff(a::Vector{Interval}, b::Vector{Interval})
    out = Interval[]
    for (alo, ahi) in a
        pieces = Interval[(alo, ahi)]
        for (blo, bhi) in b
            next = Interval[]
            for (lo, hi) in pieces
                lo < blo && push!(next, (lo, min(hi, blo)))
                hi > bhi && push!(next, (max(lo, bhi), hi))
            end
            pieces = next
            isempty(pieces) && break
        end
        append!(out, pieces)
    end
    return _normalize(out)
end

"""
    inside_length(s::Shape, x0, y0, x1, y1) -> Float64

Length of the part of the segment from `(x0, y0)` to `(x1, y1)` that lies inside `s`, in
metres. This is the wetted length of a background-grid face.
"""
function inside_length(s::Shape, x0, y0, x1, y1)
    total = hypot(x1 - x0, y1 - y0)
    return total * sum(t -> t[2] - t[1], segment_inside(s, x0, y0, x1, y1); init=0.0)
end

# ---------------------------------------------------------------------------
# Polygon outline, for the clipping the areas and centroids come from.
# ---------------------------------------------------------------------------

"""
    outline(s::Shape; arc_segments=256) -> Meshes.PolyArea

The region as a polygon, with curved boundaries sampled at `arc_segments` points. This is
the domain handed to `Meshes.clip`, so every area the mesher reports carries the polygon
approximation error and nothing else. Raising `arc_segments` reduces it.

Supported forms are one outer body, optionally minus holes: `shape(box)`,
`shape(box) - ball`, `shape(box) - (ball1 ∪ ball2)`. Anything else throws, because a
general union of overlapping bodies needs a polygon boolean that `Meshes` does not
provide.

Hole rings are wound opposite to the outer ring here rather than trusting the caller.
Getting that backwards makes `PolyArea` add the hole area instead of subtracting it, which
is silent and poisons every downstream area.
"""
function outline(s::Shape; arc_segments::Int=256)
    outer, holes = _outer_and_holes(s)
    oring = _ring(outer, arc_segments)
    isempty(holes) && return Meshes.PolyArea(oring)
    want = Meshes.orientation(oring) == :CCW ? :CW : :CCW
    hrings = map(holes) do h
        r = _ring(h, arc_segments)
        Meshes.orientation(r) == want ? r : Meshes.Ring(reverse(collect(Meshes.vertices(r)))...)
    end
    return Meshes.PolyArea(oring, hrings...)
end

_outer_and_holes(s::Leaf) = (s.geom, Any[])

function _outer_and_holes(s::ShapeDiff)
    outer, holes = _outer_and_holes(s.a)
    return (outer, vcat(holes, _leaves(s.b)))
end

_outer_and_holes(s::Shape) = throw(ArgumentError(
    "outline supports one outer body optionally minus holes, e.g. `shape(box) - ball`; " *
    "got a $(nameof(typeof(s))) at the top level. Intersections and unions of overlapping " *
    "bodies need a polygon boolean that Meshes does not provide."))

_leaves(s::Leaf) = Any[s.geom]
_leaves(s::ShapeUnion) = vcat(_leaves(s.a), _leaves(s.b))
_leaves(s::Shape) = throw(ArgumentError(
    "a subtracted region must be a body or a union of bodies; got $(nameof(typeof(s)))"))

function _ring(b::Meshes.Box, ::Int)
    x0, y0 = _xy(minimum(b))
    x1, y1 = _xy(maximum(b))
    return Meshes.Ring((x0, y0), (x1, y0), (x1, y1), (x0, y1))
end

function _ring(d::Meshes.Ball, arc_segments::Int)
    arc_segments >= 3 || throw(ArgumentError("arc_segments must be at least 3"))
    cx, cy = _xy(Meshes.center(d))
    r = Float64(ustrip(Meshes.radius(d)))
    θs = range(0, 2π; length=arc_segments + 1)[1:arc_segments]
    return Meshes.Ring([Meshes.Point(cx + r * cos(θ), cy + r * sin(θ)) for θ in θs]...)
end

_ring(g, ::Int) = throw(ArgumentError(
    "outline has no method for $(nameof(typeof(g))); it is defined for Box and Ball."))
