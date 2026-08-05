# ogrid.jl — a body-fitted structured mesh for a bored cross-section.
#
# The topology is an O-grid: a ring of cells wrapped around the bore, indexed radially
# outward and angularly around, with the innermost faces lying on the bore and the outermost
# on the outer wall. Cells follow the geometry, so wall faces sit square on the surface,
# wall area is exact, and the near-wall region where the temperature gradient is steepest
# gets clean cells rather than clipped fragments.
#
# What it gives up, when the outer wall is not concentric with the bore, is exact
# two-point-flux orthogonality: the line joining two cell centroids is not quite parallel to
# the face normal between them.
#
# That is a limitation of this generator rather than of the geometry. A conformal map from
# an annulus to a bored square does exist and would be orthogonal everywhere except at the
# four corners, where the boundary has two normals and no grid line can meet both. Reaching
# it needs orthogonality-enforcing generation, sliding the boundary nodes along the wall so
# the incoming line arrives normal. What is here instead is elliptic smoothing, which
# relaxes the interior nodes toward a Laplace solution: that optimizes smoothness, and
# improves orthogonality only as a side effect, roughly halving the skew against the raw
# algebraic blend.
#
# Two things make the remainder tolerable for conduction. The skew is smallest at the bore,
# under 5 degrees, which is where the gradient is steepest. And it is largest on the
# diagonals out to the corners, where the flux is smallest because corner metal sits far
# from every channel.
#
# `mesh_skew` and `linear_patch_error` in mesh.jl report what is left, so the assumption is
# measured rather than asserted. Both read zero on a concentric annulus, where the mapping
# is conformal and this scheme is exact.

"""
    ogrid_cross_section(inner, outer; n_angular, n_radial=nothing, radial=nothing,
                        boundaries=(), regions=(), smoothing=300) -> CrossSection

Body-fitted O-grid between a bore and an outer wall.

# Arguments
- `inner`: the bore, a `Meshes` geometry. Its boundary carries the innermost faces.
- `outer`: the outer wall, a `Meshes` geometry enclosing `inner`.
- `n_angular`: cells around the ring.
- `n_radial`: cells across the ring, for uniform spacing.
- `radial`: alternatively, a vector of `n_radial + 1` fractions from 0 at the bore to 1 at
  the outer wall, for a graded mesh. Use it to put fine cells against a wall or to place a
  material interface exactly.
- `boundaries`: `shape => tag` pairs. Each wall face takes the tag of the nearest one, which
  is how the four flats of a square rod become four separately cooled surfaces. A face
  further than one cell from every tagged shape is left untagged and so adiabatic.
- `regions`: `shape => material_index` pairs, applied to cell centroids in order, last match
  winning.
- `smoothing`: elliptic smoothing sweeps. Zero leaves the raw algebraic blend.

# Returns
`CrossSection` ready for [`extrude`](@ref).
"""
function ogrid_cross_section(inner, outer; n_angular::Int, n_radial=nothing,
                             radial=nothing, boundaries=(), regions=(),
                             smoothing::Int=300)
    n_angular >= 8 || throw(ArgumentError("n_angular must be at least 8, got $n_angular"))
    s = if radial !== nothing
        v = collect(Float64, radial)
        (first(v) == 0 && last(v) == 1) ||
            throw(ArgumentError("radial fractions must run from 0 to 1"))
        all(>(0), diff(v)) || throw(ArgumentError("radial fractions must increase"))
        v
    elseif n_radial !== nothing
        n_radial >= 1 || throw(ArgumentError("n_radial must be at least 1"))
        collect(range(0, 1; length=n_radial + 1))
    else
        throw(ArgumentError("give either n_radial or radial"))
    end

    ring_in = _perimeter_points(inner, n_angular)
    ring_out = _perimeter_points(outer, n_angular)

    nodes = _transfinite(ring_in, ring_out, s)
    smoothing > 0 && _smooth!(nodes, smoothing)
    return _ogrid_section(nodes, boundaries, regions)
end

# Points spread evenly by arc length around a geometry's boundary, starting where the ray in
# the +x direction leaves the centre and running counter-clockwise. Starting both rings at
# the same place is what makes the connecting lines close to radial before smoothing.
function _perimeter_points(g::Meshes.Ball, n::Int)
    cx, cy = _xy(Meshes.center(g))
    r = Float64(ustrip(Meshes.radius(g)))
    return [(cx + r * cos(θ), cy + r * sin(θ)) for θ in range(0, 2π; length=n + 1)[1:n]]
end

function _perimeter_points(b::Meshes.Box, n::Int)
    x0, y0 = _xy(minimum(b))
    x1, y1 = _xy(maximum(b))
    ym = (y0 + y1) / 2
    corners = [(x1, ym), (x1, y1), (x0, y1), (x0, y0), (x1, y0), (x1, ym)]
    return _walk(corners, n)
end

_perimeter_points(g, ::Int) = throw(ArgumentError(
    "ogrid_cross_section handles Box and Ball boundaries; got $(nameof(typeof(g)))"))

# Sample a closed polyline at n equally spaced arc lengths.
function _walk(path, n::Int)
    seg = [hypot(path[k + 1][1] - path[k][1], path[k + 1][2] - path[k][2])
           for k in 1:(length(path) - 1)]
    total = sum(seg)
    out = NTuple{2,Float64}[]
    k, run = 1, 0.0
    for i in 0:(n - 1)
        target = total * i / n
        while k < length(seg) && run + seg[k] < target
            run += seg[k]
            k += 1
        end
        t = seg[k] == 0 ? 0.0 : (target - run) / seg[k]
        ax, ay = path[k]
        bx, by = path[k + 1]
        push!(out, (ax + t * (bx - ax), ay + t * (by - ay)))
    end
    return out
end

# Straight blend from bore to wall, the starting point smoothing improves on.
function _transfinite(ring_in, ring_out, s)
    nr1, nθ = length(s), length(ring_in)
    nodes = Array{NTuple{2,Float64}}(undef, nr1, nθ)
    for j in 1:nθ, i in 1:nr1
        f = s[i]
        ax, ay = ring_in[j]
        bx, by = ring_out[j]
        nodes[i, j] = (ax + f * (bx - ax), ay + f * (by - ay))
    end
    return nodes
end

# Winslow smoothing: solve the Laplace system for the mapping by Gauss-Seidel, holding both
# boundary rings fixed. Angular index wraps, radial index does not.
function _smooth!(nodes, sweeps::Int)
    nr1, nθ = size(nodes)
    nr1 <= 2 && return nodes
    wrap(j) = j > nθ ? j - nθ : (j < 1 ? j + nθ : j)
    for _ in 1:sweeps
        for i in 2:(nr1 - 1), j in 1:nθ
            jp, jm = wrap(j + 1), wrap(j - 1)
            xip, yip = nodes[i + 1, j]
            xim, yim = nodes[i - 1, j]
            xjp, yjp = nodes[i, jp]
            xjm, yjm = nodes[i, jm]
            xξ, yξ = (xip - xim) / 2, (yip - yim) / 2
            xη, yη = (xjp - xjm) / 2, (yjp - yjm) / 2
            α = xη^2 + yη^2
            β = xξ * xη + yξ * yη
            γ = xξ^2 + yξ^2
            denom = 2 * (α + γ)
            denom == 0 && continue
            xc = (nodes[i + 1, jp][1] - nodes[i + 1, jm][1] -
                  nodes[i - 1, jp][1] + nodes[i - 1, jm][1]) / 4
            yc = (nodes[i + 1, jp][2] - nodes[i + 1, jm][2] -
                  nodes[i - 1, jp][2] + nodes[i - 1, jm][2]) / 4
            nodes[i, j] = ((α * (xip + xim) + γ * (xjp + xjm) - 2β * xc) / denom,
                           (α * (yip + yim) + γ * (yjp + yjm) - 2β * yc) / denom)
        end
    end
    return nodes
end

function _ogrid_section(nodes, boundaries, regions)
    nr1, nθ = size(nodes)
    nr = nr1 - 1
    wrap(j) = j > nθ ? j - nθ : j
    idx(i, j) = (i - 1) * nθ + j

    area = Vector{Float64}(undef, nr * nθ)
    centroid = Vector{NTuple{2,Float64}}(undef, nr * nθ)
    patches = Vector{Vector{Vector{NTuple{2,Float64}}}}(undef, nr * nθ)
    for i in 1:nr, j in 1:nθ
        jn = wrap(j + 1)
        ring = [nodes[i, j], nodes[i + 1, j], nodes[i + 1, jn], nodes[i, jn]]
        a, cx, cy = _area_centroid(ring)
        n = idx(i, j)
        area[n] = a
        centroid[n] = (cx, cy)
        patches[n] = [ring]
    end
    material = [_material_at(regions, c[1], c[2]) for c in centroid]

    faces = CrossFace{Float64}[]
    for j in 1:nθ
        jn = wrap(j + 1)
        # Radial seams: cell (i,j) meets cell (i+1,j) across the node ring at i+1.
        for i in 1:(nr - 1)
            push!(faces, _interior_face(idx(i, j), idx(i + 1, j),
                                        nodes[i + 1, j], nodes[i + 1, jn], centroid))
        end
        # Angular seams, which wrap all the way round.
        for i in 1:nr
            push!(faces, _interior_face(idx(i, j), idx(i, jn),
                                        nodes[i, jn], nodes[i + 1, jn], centroid))
        end
    end

    reach = 2 * sqrt(sum(area) / (nr * nθ))
    boundary = CrossBoundary{Float64}[]
    for j in 1:nθ
        jn = wrap(j + 1)
        _push_boundary!(boundary, idx(1, j), nodes[1, j], nodes[1, jn],
                        centroid, boundaries, reach)
        _push_boundary!(boundary, idx(nr, j), nodes[nr1, j], nodes[nr1, jn],
                        centroid, boundaries, reach)
    end

    seen = Symbol[]
    for (_, tag) in boundaries
        tag in seen || (any(b -> b.tag == tag, boundary) && push!(seen, tag))
    end
    return CrossSection(area, centroid, patches, material, faces, boundary, seen)
end

# Face metrics from the two endpoints of the shared edge. `d` is the distance from each
# centroid to the face plane measured along the face normal, which is the two-point-flux
# form; any skew between that normal and the centroid-to-centroid line is what `mesh_skew`
# reports.
function _interior_face(a::Int, b::Int, p, q, centroid)
    ex, ey = q[1] - p[1], q[2] - p[2]
    len = hypot(ex, ey)
    nx, ny = ey / len, -ex / len
    mx, my = (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
    d1 = abs((centroid[a][1] - mx) * nx + (centroid[a][2] - my) * ny)
    d2 = abs((centroid[b][1] - mx) * nx + (centroid[b][2] - my) * ny)
    return CrossFace(a, b, len, d1, d2, 0.0)
end

function _push_boundary!(out, c::Int, p, q, centroid, boundaries, reach)
    isempty(boundaries) && return out
    ex, ey = q[1] - p[1], q[2] - p[2]
    len = hypot(ex, ey)
    len == 0 && return out
    nx, ny = ey / len, -ex / len
    mx, my = (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
    # Point the normal away from the cell.
    if (mx - centroid[c][1]) * nx + (my - centroid[c][2]) * ny < 0
        nx, ny = -nx, -ny
    end
    tag = _nearest_tag(boundaries, mx, my, reach)
    tag === nothing && return out
    d = abs((centroid[c][1] - mx) * nx + (centroid[c][2] - my) * ny)
    push!(out, CrossBoundary(c, len, d, 0.0, nx, ny, tag))
    return out
end
