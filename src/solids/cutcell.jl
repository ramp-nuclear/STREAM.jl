# cutcell.jl — meshing a composed cross-section on an axis-aligned background grid.
#
# Cells that lie wholly inside the region are whole background cells. Cells the boundary
# passes through are clipped. The point of doing it this way rather than triangulating is
# that every interior face is a piece of a grid line, so the face normal is parallel to
# the line joining the two cell centroids and the two-point flux is orthogonal with no
# correction term. No mesh generator gives that for an arbitrary shape.
#
# Three quantities per cell, from three different places:
#
#   area, centroid   Meshes.clip against the cell. Exact, up to the polygon sampling of
#                    any curved boundary.
#   grid face length exact interval algebra along the grid line (`inside_length`). NOT read
#                    off the clipped polygon: Sutherland-Hodgman stitches its result with
#                    zero-width bridges, so a face wholly inside a hole comes back at full
#                    length instead of zero.
#   cut face         the divergence identity. Over a closed cell `Σ A·n̂ = 0`, so the cut
#                    face's `A·n̂` is minus the sum over the four grid faces. That gives
#                    its area and normal together, and closes the cell by construction.

struct _RawCell
    i::Int
    j::Int
    area::Float64
    cx::Float64
    cy::Float64
    boxes::Vector{NTuple{4,Float64}}
end

_x0(c::_RawCell) = c.boxes[1][1]
_y0(c::_RawCell) = c.boxes[1][2]
_x1(c::_RawCell) = c.boxes[1][3]
_y1(c::_RawCell) = c.boxes[1][4]

# A face is kept in this form until after merging, because merging moves centroids and the
# centroid-to-face distances have to be recomputed from the grid line's own coordinate.
struct _RawFace
    a::Int
    b::Int
    vertical::Bool
    coord::Float64
    len::Float64
end

# A boundary face is either a whole grid side with no cell on the far side, in which case
# its position is known exactly, or the curved remainder recovered from the divergence
# identity, whose distance has to come from the geometry instead.
struct _RawBoundary
    c::Int
    len::Float64
    tag::Symbol
    axis::Bool
    vertical::Bool
    coord::Float64
    nx::Float64
    ny::Float64
end

"""
    cut_cell_cross_section(domain; dx, dy, regions=(), boundaries=(), arc_segments=256,
                           merge_below=0.5) -> CrossSection

Mesh a composed region onto an axis-aligned background grid, keeping the parts of each
grid cell that lie inside `domain`.

# Arguments
- `domain`: the region, built from `Meshes` geometries with [`shape`](@ref) and `-`, `∪`, `∩`
- `dx`, `dy`: target background cell size [m]. The grid is snapped to the region's bounding
  box, so the sizes actually used are the nearest ones that divide it evenly.
- `regions`: `shape => material_index` pairs, applied to each cell centroid in order, last
  match winning. Cells matching nothing get material 1.
- `boundaries`: `shape => tag` pairs. A cut face is tagged with the nearest one, and a cut
  face further than a cell diagonal from every tagged shape is left untagged, which makes
  it adiabatic.
- `arc_segments`: how finely a curved boundary is sampled. The only approximation in the
  reported areas.
- `merge_below`: cells below this fraction of a full background cell are merged into a
  neighbour. Small cells carry proportionally small heat capacity and a proportionally
  short time constant, so leaving them in makes the system stiff for no physical reason.

# Returns
`CrossSection` ready for [`extrude`](@ref).
"""
function cut_cell_cross_section(domain::Shape; dx::Real, dy::Real,
                                regions=(), boundaries=(), arc_segments::Int=256,
                                merge_below::Real=0.5)
    dx > 0 && dy > 0 || throw(ArgumentError("dx and dy must be positive"))
    0 <= merge_below < 1 || throw(ArgumentError("merge_below must be in [0, 1)"))

    poly = outline(domain; arc_segments=arc_segments)
    bb = Meshes.boundingbox(poly)
    bx0, by0 = _xy(minimum(bb))
    bx1, by1 = _xy(maximum(bb))

    nx = max(1, round(Int, (bx1 - bx0) / dx))
    ny = max(1, round(Int, (by1 - by0) / dy))
    hx = (bx1 - bx0) / nx
    hy = (by1 - by0) / ny
    xs = [bx0 + i * hx for i in 0:nx]
    ys = [by0 + j * hy for j in 0:ny]
    full = hx * hy

    cells, index = _carve(domain, poly, xs, ys, full)
    isempty(cells) && throw(ArgumentError(
        "the mesh is empty; check that dx and dy are smaller than the region"))

    faces = _grid_faces(domain, cells, index, xs, ys)
    bnds = _cut_faces(domain, cells, index, xs, ys, hx, hy, boundaries)
    material = [_material_at(regions, c.cx, c.cy) for c in cells]

    cells, faces, bnds, material =
        _merge_small(cells, faces, bnds, material, full, merge_below)

    return _assemble(domain, cells, faces, bnds, material, boundaries, hx, hy)
end

# Clip every background cell against the region, dropping the empty ones.
function _carve(domain, poly, xs, ys, full)
    cells = _RawCell[]
    index = Dict{Tuple{Int,Int},Int}()
    floor_area = 1e-12 * full
    for j in 1:(length(ys) - 1), i in 1:(length(xs) - 1)
        x0, x1 = xs[i], xs[i + 1]
        y0, y1 = ys[j], ys[j + 1]
        area, cx, cy = _clip_cell(domain, poly, x0, y0, x1, y1, full)
        area <= floor_area && continue
        push!(cells, _RawCell(i, j, area, cx, cy, [(x0, y0, x1, y1)]))
        index[(i, j)] = length(cells)
    end
    return cells, index
end

function _clip_cell(domain, poly, x0, y0, x1, y1, full)
    # A cell further from every edge than its own half-diagonal cannot be cut, so skip the
    # clip and take the exact rectangle. This is the common case away from the boundary.
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    half_diag = hypot(x1 - x0, y1 - y0) / 2
    if dist_to_edge(domain, cx, cy) > half_diag
        return inside(domain, cx, cy) ? ((x1 - x0) * (y1 - y0), cx, cy) : (0.0, cx, cy)
    end

    quad = Meshes.Quadrangle((x0, y0), (x1, y0), (x1, y1), (x0, y1))
    clipped = Meshes.clip(poly, quad, Meshes.SutherlandHodgmanClipping())
    clipped === nothing && return (0.0, cx, cy)
    area = Float64(ustrip(Meshes.measure(clipped)))
    area <= 1e-12 * full && return (0.0, cx, cy)
    gx, gy = _xy(Meshes.centroid(clipped))
    return (area, gx, gy)
end

# Interior faces: the wetted part of each grid line shared by two surviving cells.
function _grid_faces(domain, cells, index, xs, ys)
    faces = _RawFace[]
    for (n, c) in pairs(cells)
        # Only look right and up, so each face is visited once.
        right = get(index, (c.i + 1, c.j), 0)
        if right != 0
            len = inside_length(domain, _x1(c), _y0(c), _x1(c), _y1(c))
            len > 0 && push!(faces, _RawFace(n, right, true, _x1(c), len))
        end
        up = get(index, (c.i, c.j + 1), 0)
        if up != 0
            len = inside_length(domain, _x0(c), _y1(c), _x1(c), _y1(c))
            len > 0 && push!(faces, _RawFace(n, up, false, _y1(c), len))
        end
    end
    return faces
end

# Boundary faces come in two kinds and both are needed.
#
# A grid side with no surviving cell on the far side lies on the region's boundary, and its
# length and normal are exact. This is the whole story when the region is grid-aligned: a
# square meshed on its own grid has no curved boundary at all, and the divergence residual
# below is zero precisely because the four sides are fully wetted and cancel.
#
# The curved remainder is what the identity recovers: over the closed cell `Σ A·n̂ = 0`, so
# whatever the four grid sides fail to cancel is the arc.
function _cut_faces(domain, cells, index, xs, ys, hx, hy, boundaries)
    out = _RawBoundary[]
    isempty(boundaries) && return out
    diag = hypot(hx, hy)
    for (n, c) in pairs(cells)
        sides = (
            (inside_length(domain, _x0(c), _y0(c), _x0(c), _y1(c)), true, _x0(c), -1.0, (c.i - 1, c.j)),
            (inside_length(domain, _x1(c), _y0(c), _x1(c), _y1(c)), true, _x1(c), 1.0, (c.i + 1, c.j)),
            (inside_length(domain, _x0(c), _y0(c), _x1(c), _y0(c)), false, _y0(c), -1.0, (c.i, c.j - 1)),
            (inside_length(domain, _x0(c), _y1(c), _x1(c), _y1(c)), false, _y1(c), 1.0, (c.i, c.j + 1)),
        )
        sx = sy = 0.0
        for (len, vertical, coord, sgn, nb) in sides
            len <= 0 && continue
            vertical ? (sx += sgn * len) : (sy += sgn * len)
            haskey(index, nb) && continue
            mx = vertical ? coord : (_x0(c) + _x1(c)) / 2
            my = vertical ? (_y0(c) + _y1(c)) / 2 : coord
            tag = _nearest_tag(boundaries, mx, my, diag)
            tag === nothing && continue
            nx = vertical ? sgn : 0.0
            ny = vertical ? 0.0 : sgn
            push!(out, _RawBoundary(n, len, tag, true, vertical, coord, nx, ny))
        end

        curved = hypot(sx, sy)
        curved <= 1e-9 * diag && continue
        tag = _nearest_tag(boundaries, c.cx, c.cy, diag)
        tag === nothing && continue
        # A·n̂ = −Σ over the grid sides, so the arc's outward normal is the negated residual.
        push!(out, _RawBoundary(n, curved, tag, false, false, 0.0, -sx / curved, -sy / curved))
    end
    return out
end

function _nearest_tag(boundaries, x, y, reach)
    best, bestd = nothing, Inf
    for (s, tag) in boundaries
        d = dist_to_edge(shape(s), x, y)
        if d < bestd
            best, bestd = tag, d
        end
    end
    return bestd <= reach ? best : nothing
end

function _material_at(regions, x, y)
    m = 1
    for (s, idx) in regions
        inside(shape(s), x, y) && (m = idx)
    end
    return m
end

# Merge cells below the size threshold into the neighbour they share the most face with,
# never across a material change. Union-find, then rebuild.
function _merge_small(cells, faces, bnds, material, full, merge_below)
    n = length(cells)
    parent = collect(1:n)
    root(a) = (parent[a] == a ? a : (parent[a] = root(parent[a])))

    if merge_below > 0
        neighbours = [Tuple{Int,Float64}[] for _ in 1:n]
        for f in faces
            push!(neighbours[f.a], (f.b, f.len))
            push!(neighbours[f.b], (f.a, f.len))
        end
        small = [i for i in 1:n if cells[i].area < merge_below * full]
        sort!(small; by=i -> cells[i].area)
        for i in small
            root(i) == i || continue
            best, bestlen = 0, 0.0
            for (nb, len) in neighbours[i]
                r = root(nb)
                (r == root(i) || material[r] != material[i]) && continue
                len > bestlen && ((best, bestlen) = (r, len))
            end
            best != 0 && (parent[root(i)] = best)
        end
    end

    roots = sort(unique(root(i) for i in 1:n))
    remap = Dict(r => k for (k, r) in pairs(roots))
    m = length(roots)

    area = zeros(Float64, m)
    wx = zeros(Float64, m)
    wy = zeros(Float64, m)
    boxes = [NTuple{4,Float64}[] for _ in 1:m]
    newmat = zeros(Int, m)
    for (i, c) in pairs(cells)
        k = remap[root(i)]
        area[k] += c.area
        wx[k] += c.area * c.cx
        wy[k] += c.area * c.cy
        append!(boxes[k], c.boxes)
        newmat[k] = material[i]
    end
    merged = [_RawCell(0, 0, area[k], wx[k] / area[k], wy[k] / area[k], boxes[k]) for k in 1:m]

    # Faces internal to a merged cell vanish; the rest coalesce by (pair, line).
    facemap = Dict{NTuple{4,Any},Float64}()
    for f in faces
        a, b = remap[root(f.a)], remap[root(f.b)]
        a == b && continue
        lo, hi = minmax(a, b)
        key = (lo, hi, f.vertical, f.coord)
        facemap[key] = get(facemap, key, 0.0) + f.len
    end
    newfaces = [_RawFace(k[1], k[2], k[3], k[4], v) for (k, v) in facemap]

    # Grid-side faces keep their line, so their distance stays exact after the merge; the
    # curved remainder for a cell collapses to one entry per tag.
    bndmap = Dict{NTuple{7,Any},Float64}()
    for b in bnds
        key = (remap[root(b.c)], b.tag, b.axis, b.vertical, b.coord, b.nx, b.ny)
        bndmap[key] = get(bndmap, key, 0.0) + b.len
    end
    newbnds = [_RawBoundary(k[1], v, k[2], k[3], k[4], k[5], k[6], k[7]) for (k, v) in bndmap]

    return merged, newfaces, newbnds, newmat
end

# Turn the raw records into a CrossSection, measuring every centroid-to-face distance from
# the final (post-merge) centroids.
function _assemble(domain, cells, faces, bnds, material, boundaries, hx, hy)
    area = [c.area for c in cells]
    centroid = [(c.cx, c.cy) for c in cells]
    patches = [[_rect_patch(b...) for b in c.boxes] for c in cells]

    cfaces = map(faces) do f
        ca, cb = cells[f.a], cells[f.b]
        d1, d2 = if f.vertical
            (abs(ca.cx - f.coord), abs(cb.cx - f.coord))
        else
            (abs(ca.cy - f.coord), abs(cb.cy - f.coord))
        end
        CrossFace(f.a, f.b, f.len, d1, d2, 0.0)
    end

    bytag = Dict(tag => shape(s) for (s, tag) in boundaries)
    cbnds = map(bnds) do b
        c = cells[b.c]
        d = if b.axis
            abs((b.vertical ? c.cx : c.cy) - b.coord)
        else
            dist_to_edge(bytag[b.tag], c.cx, c.cy)
        end
        CrossBoundary(b.c, b.len, d, 0.0, b.nx, b.ny, b.tag)
    end

    seen = Symbol[]
    for (s, tag) in boundaries
        tag in seen || (any(b -> b.tag == tag, cbnds) && push!(seen, tag))
    end
    return CrossSection(area, centroid, patches, material, cfaces, cbnds, seen)
end
