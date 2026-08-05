# mesh.jl — the mesh a conduction component consumes.
#
# A mesh is a 2D cross-section swept along z. The cross-section is stored once and the
# axial spacing once, so a 20-layer mesh holds one copy of the in-plane faces rather than
# twenty. The conduction it describes is still fully 3D: cells are (cross-section cell,
# axial layer) pairs, and `axial_conductance` links a cell to the same cell one layer up.
#
# Nothing here knows about ModelingToolkit. Every quantity is a plain number, or a `Num`
# when a dimension is a design knob, which works because `Num <: Real`.

"""
    SolidMaterial(rho, cp, k)

Solid properties: density [kg/m³], specific heat [J/(kg·K)], thermal conductivity
[W/(m·K)]. A mesh carries a material index per cell, so a clad plate is two materials and
one index vector rather than three arrays the size of the mesh.
"""
struct SolidMaterial{T<:Real}
    rho::T
    cp::T
    k::T
end

SolidMaterial(rho, cp, k) = SolidMaterial(promote(rho, cp, k)...)

"""
    CrossFace

An in-plane face between two cross-section cells, identical in every axial layer.

`len` is the wetted face length in the plane [m]; `d1` and `d2` are the normal distances
from each cell centroid to the face [m]; `r_contact` is the interface resistance
[m²·K/W], zero for perfect contact.

Contact resistance is stored rather than conductance so that perfect contact is `0` and
not `Inf`. An `Inf` reaching a symbolic trace poisons the whole expression, and a
knob-driven mesh does get traced.
"""
struct CrossFace{T<:Real}
    c1::Int
    c2::Int
    len::T
    d1::T
    d2::T
    r_contact::T
end

"""
    CrossBoundary

A cross-section cell's face on the outer boundary, carrying the `tag` that says which
channel cools it. An untagged part of the boundary is simply absent from this list, which
is how a surface is made adiabatic.
"""
struct CrossBoundary{T<:Real}
    c::Int
    len::T
    d::T
    r_contact::T
    nx::T
    ny::T
    tag::Symbol
end

CrossBoundary(c, len, d, r_contact, tag::Symbol) =
    CrossBoundary(c, len, d, r_contact, zero(len), zero(len), tag)

"""
    CrossSection

The 2D cross-section: per-cell area, centroid, bounding box and material index, plus the
in-plane interior faces and the tagged boundary faces.

`patches` holds the footprint a cell is drawn as, one or more closed rings of points. A
body-fitted cell has a single ring which is the cell itself. A cut cell has the background
rectangle it was clipped from, and a merged cut cell keeps one rectangle per cell it
absorbed, so its footprint is honest rather than a bounding box that overhangs the region.
The ratio of `area` to the total patch area is the fill fraction, which is one throughout a
body-fitted mesh and is what cut-cell merging thresholds on.
"""
struct CrossSection{T<:Real}
    area::Vector{T}
    centroid::Vector{NTuple{2,T}}
    patches::Vector{Vector{Vector{NTuple{2,T}}}}
    material::Vector{Int}
    faces::Vector{CrossFace{T}}
    boundary::Vector{CrossBoundary{T}}
    tags::Vector{Symbol}
end

_rect_patch(x0::T, y0::T, x1::T, y1::T) where {T} =
    [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

# Signed shoelace area and the polygon centroid that goes with it.
function _area_centroid(pts::AbstractVector{<:NTuple{2,Any}})
    n = length(pts)
    a = zero(pts[1][1])
    cx = zero(a)
    cy = zero(a)
    for k in 1:n
        x1, y1 = pts[k]
        x2, y2 = pts[k == n ? 1 : k + 1]
        cross = x1 * y2 - x2 * y1
        a += cross
        cx += (x1 + x2) * cross
        cy += (y1 + y2) * cross
    end
    a /= 2
    return (abs(a), cx / (6a), cy / (6a))
end

"""
    SolidMesh

A [`CrossSection`](@ref) swept along `dz` axial layers.

`z_contact` holds the interface resistance between consecutive layers (length `nz - 1`),
and `axial` switches axial conduction on. Turning it off leaves the layers thermally
independent, which is what the pre-mesh `HeatDiffusion` did and what Python STREAM's
`x_diffusion` does.
"""
struct SolidMesh{T<:Real}
    cross::CrossSection{T}
    dz::Vector{T}
    z_contact::Vector{T}
    axial::Bool
end

ncross(cs::CrossSection) = length(cs.area)
ncross(m::SolidMesh) = ncross(m.cross)
nlayers(m::SolidMesh) = length(m.dz)
ncells(m::SolidMesh) = ncross(m) * nlayers(m)

"""
    cellindex(mesh, iz, ic) -> Int

Flat index of the cell in cross-section slot `ic` of axial layer `iz`. The ordering is
row-major with the axial index outermost, matching how a `(nz, ncross)` temperature array
flattens.
"""
cellindex(m::SolidMesh, iz::Int, ic::Int) = (iz - 1) * ncross(m) + ic

"""
    tags(mesh) -> Vector{Symbol}

The boundary tags present, in a stable order. One thermal port is built per tag per axial
layer.
"""
tags(cs::CrossSection) = cs.tags
tags(m::SolidMesh) = tags(m.cross)

cell_volume(m::SolidMesh, iz::Int, ic::Int) = m.cross.area[ic] * m.dz[iz]

"""
    heat_capacity(mesh, materials, iz, ic) -> Real

Cell heat capacity `ρ·cp·V` [J/K].
"""
function heat_capacity(m::SolidMesh, materials::AbstractVector{<:SolidMaterial}, iz::Int, ic::Int)
    mat = materials[m.cross.material[ic]]
    return mat.rho * mat.cp * cell_volume(m, iz, ic)
end

_k(m::SolidMesh, materials, ic::Int) = materials[m.cross.material[ic]].k

"""
    interior_conductance(mesh, materials, f::CrossFace, iz) -> Real

Conductance [W/K] across an in-plane face in layer `iz`:

    G = A / (d1/k1 + d2/k2 + r_contact),   A = len · dz

The two half-cell resistances in series, plus any interface resistance. Because the face
is axis-aligned on a cut-cell mesh, `d1` and `d2` are exact normal distances and the flux
is orthogonal with no correction term.
"""
function interior_conductance(m::SolidMesh, materials::AbstractVector{<:SolidMaterial},
                              f::CrossFace, iz::Int)
    area = f.len * m.dz[iz]
    return area / (f.d1 / _k(m, materials, f.c1) + f.d2 / _k(m, materials, f.c2) + f.r_contact)
end

"""
    boundary_conductance(mesh, materials, b::CrossBoundary, iz) -> Real

Conductance [W/K] from a cell centroid to its boundary face in layer `iz`:

    G = A / (d/k + r_contact),   A = len · dz
"""
function boundary_conductance(m::SolidMesh, materials::AbstractVector{<:SolidMaterial},
                              b::CrossBoundary, iz::Int)
    area = b.len * m.dz[iz]
    return area / (b.d / _k(m, materials, b.c) + b.r_contact)
end

"""
    axial_conductance(mesh, materials, ic, iz) -> Real

Conductance [W/K] between cross-section cell `ic` in layer `iz` and the same cell in layer
`iz + 1`. The face area is the cell's cross-sectional area and the two half-distances are
`dz/2` on each side.
"""
function axial_conductance(m::SolidMesh, materials::AbstractVector{<:SolidMaterial},
                           ic::Int, iz::Int)
    k = _k(m, materials, ic)
    area = m.cross.area[ic]
    return area / (m.dz[iz] / (2k) + m.dz[iz + 1] / (2k) + m.z_contact[iz])
end

"""
    boundary_groups(mesh) -> Dict{Symbol,Vector{Int}}

Indices into `mesh.cross.boundary`, grouped by tag. Each group becomes one thermal port
per axial layer, and the port's heat flow is the sum over the group. That summation is the
reduction that lets an arbitrary boundary shape meet a channel carrying one wall
temperature per axial cell.
"""
function boundary_groups(cs::CrossSection)
    groups = Dict{Symbol,Vector{Int}}(tag => Int[] for tag in cs.tags)
    for (i, b) in pairs(cs.boundary)
        push!(groups[b.tag], i)
    end
    return groups
end

boundary_groups(m::SolidMesh) = boundary_groups(m.cross)

"""
    contact_area(mesh, tag, iz) -> Real

Wall area [m²] that one boundary tag presents to its channel in axial layer `iz`. This is
the number a channel's `heated_parts[side] * dz` has to agree with.
"""
function contact_area(m::SolidMesh, tag::Symbol, iz::Int)
    per_length = sum((b.len for b in m.cross.boundary if b.tag == tag);
                     init=zero(eltype(m.dz)))
    return per_length * m.dz[iz]
end

"""
    slab_cross_section(x_boundaries, y; tags=(:left, :right), material=1) -> CrossSection

A one-dimensional stack of cells across a flat plate of depth `y`, cooled on both lateral
faces. This is the cross-section the original `HeatDiffusion` used, and it is the only
generator that accepts a design knob: it needs no coordinate tests, so a `Num` passes
straight through into the face lengths and distances.

# Arguments
- `x_boundaries`: cell boundaries across the plate [m], ascending, length `nx + 1`
- `y`: plate depth into the page [m]
- `tags`: boundary tags for the low-x and high-x faces
- `material`: material index for every cell

# Returns
`CrossSection` with `nx` cells, `nx - 1` interior faces and two boundary faces.
"""
function slab_cross_section(x_boundaries::AbstractVector, y;
                            tags::NTuple{2,Symbol}=(:left, :right), material::Int=1)
    nx = length(x_boundaries) - 1
    nx >= 1 || throw(ArgumentError("need at least two x boundaries, got $(length(x_boundaries))"))
    T = promote_type(eltype(x_boundaries), typeof(y))
    x = collect(T, x_boundaries)
    yT = convert(T, y)

    dx = [x[j + 1] - x[j] for j in 1:nx]
    area = [d * yT for d in dx]
    centroid = [((x[j] + x[j + 1]) / 2, yT / 2) for j in 1:nx]
    patches = [[_rect_patch(x[j], zero(T), x[j + 1], yT)] for j in 1:nx]

    faces = [CrossFace(j, j + 1, yT, dx[j] / 2, dx[j + 1] / 2, zero(T)) for j in 1:(nx - 1)]
    boundary = [
        CrossBoundary(1, yT, dx[1] / 2, zero(T), -one(T), zero(T), tags[1]),
        CrossBoundary(nx, yT, dx[nx] / 2, zero(T), one(T), zero(T), tags[2]),
    ]
    return CrossSection(area, centroid, patches, fill(material, nx), faces, boundary,
                        collect(unique(tags)))
end

"""
    extrude(cross, z_boundaries; z_contact=nothing, axial=true) -> SolidMesh

Sweep a cross-section along the axial direction.

# Arguments
- `cross`: the `CrossSection` to sweep
- `z_boundaries`: axial cell boundaries [m], ascending, length `nz + 1`. Spacing may be
  non-uniform and is independent of the cross-section mesh.
- `z_contact`: interface resistance between consecutive layers [m²·K/W], length `nz - 1`,
  default zero
- `axial`: whether axial conduction is present

# Returns
`SolidMesh`.
"""
function extrude(cross::CrossSection, z_boundaries::AbstractVector;
                 z_contact=nothing, axial::Bool=true)
    nz = length(z_boundaries) - 1
    nz >= 1 || throw(ArgumentError("need at least two z boundaries, got $(length(z_boundaries))"))
    T = promote_type(eltype(cross.area), eltype(z_boundaries))
    z = collect(T, z_boundaries)
    dz = [z[i + 1] - z[i] for i in 1:nz]

    zc = if z_contact === nothing
        zeros(T, max(nz - 1, 0))
    else
        length(z_contact) == nz - 1 ||
            throw(ArgumentError("z_contact must have length nz-1 = $(nz-1), got $(length(z_contact))"))
        collect(T, z_contact)
    end

    cs = T === eltype(cross.area) ? cross : _convert_cross(T, cross)
    return SolidMesh(cs, dz, zc, axial)
end

function _convert_cross(::Type{T}, cs::CrossSection) where {T<:Real}
    return CrossSection(
        collect(T, cs.area),
        [(convert(T, c[1]), convert(T, c[2])) for c in cs.centroid],
        [[[(convert(T, q[1]), convert(T, q[2])) for q in ring] for ring in ps]
         for ps in cs.patches],
        cs.material,
        [CrossFace(f.c1, f.c2, convert(T, f.len), convert(T, f.d1), convert(T, f.d2),
                   convert(T, f.r_contact)) for f in cs.faces],
        [CrossBoundary(b.c, convert(T, b.len), convert(T, b.d), convert(T, b.r_contact),
                       convert(T, b.nx), convert(T, b.ny), b.tag) for b in cs.boundary],
        cs.tags,
    )
end

"""
    set_contact!(cs::CrossSection, r; where) -> CrossSection

Set the interface resistance [m²·K/W] on every interior face for which the predicate
`where(c1, c2)` holds, given the two cells the face separates. This is how a fuel-to-clad
gap is expressed: mesh the clad and the meat as one body with different material indices,
then put the gap resistance on the faces between them.

Returns the cross-section, mutated in place.
"""
function set_contact!(cs::CrossSection, r; where)
    for (i, f) in pairs(cs.faces)
        where(f.c1, f.c2) || continue
        cs.faces[i] = CrossFace(f.c1, f.c2, f.len, f.d1, f.d2, convert(eltype(cs.area), r))
    end
    return cs
end

# ---------------------------------------------------------------------------
# Mesh quality.
#
# Two-point flux assumes the line joining two cell centroids is parallel to the face normal
# between them. No mesh of a bored square satisfies that everywhere: a body-fitted grid is
# skewed where it turns the corner, and a cut-cell grid is skewed at the boundary cells
# whose centroids have moved off the grid line. These two functions measure it rather than
# leave it as an assumption.
# ---------------------------------------------------------------------------

"""
    mesh_skew(cs) -> NamedTuple

Non-orthogonality of the interior faces, in degrees: the angle between each face normal and
the line joining the two cell centroids across it. Zero is exactly orthogonal, where the
two-point flux is exact.

Reported as `(; max, mean, p95)`. This is a geometric measure; for what it costs the
physics, use [`linear_patch_error`](@ref).
"""
function mesh_skew(cs::CrossSection)
    isempty(cs.faces) && return (; max=0.0, mean=0.0, p95=0.0)
    angles = map(cs.faces) do f
        ax, ay = cs.centroid[f.c1]
        bx, by = cs.centroid[f.c2]
        v = hypot(bx - ax, by - ay)
        # d1 + d2 is the centroid separation projected on the face normal, so their ratio
        # to the true separation is the cosine of the skew angle.
        acosd(clamp((f.d1 + f.d2) / v, -1.0, 1.0))
    end
    sorted = sort(angles)
    return (; max=last(sorted),
            mean=sum(sorted) / length(sorted),
            p95=sorted[max(1, ceil(Int, 0.95 * length(sorted)))])
end

"""
    linear_patch_error(cs) -> Float64

The standard patch test, and the honest measure of what a mesh costs. Impose `T = x`, which
satisfies the heat equation exactly, and sum the conductive flux into every cell that does
not touch a boundary. An exact scheme gives zero everywhere.

Reported as `(; max, p95)`, each the residual as a fraction of the individual fluxes being
summed: 0.05 means a cell whose net flux is 5% of the traffic through it. The maximum is
dominated by a single worst cell and is noisy, so `p95` is the more stable comparison.

Refinement does not drive it to zero, because non-orthogonality is a property of the
mapping rather than of how finely it is discretized. It is zero for a slab and for a
concentric annulus, where the mapping is conformal and the scheme is exact.
"""
function linear_patch_error(cs::CrossSection)
    m = extrude(cs, [0.0, 1.0])
    # One uniform material per index the mesh uses: the test is about geometry, and a
    # conductivity jump would put a real kink in the field rather than an error.
    mats = fill(SolidMaterial(1.0, 1.0, 1.0), maximum(cs.material))
    T = [c[1] for c in cs.centroid]
    net = zeros(ncross(cs))
    traffic = zeros(ncross(cs))
    for f in cs.faces
        q = interior_conductance(m, mats, f, 1) * (T[f.c2] - T[f.c1])
        net[f.c1] += q
        traffic[f.c1] += abs(q)
        net[f.c2] -= q
        traffic[f.c2] += abs(q)
    end
    onwall = falses(ncross(cs))
    for b in cs.boundary
        onwall[b.c] = true
    end
    interior = findall(i -> !onwall[i] && traffic[i] > 0, 1:ncross(cs))
    isempty(interior) && return (; max=0.0, p95=0.0)
    e = sort([abs(net[i]) / traffic[i] for i in interior])
    return (; max=last(e), p95=e[max(1, ceil(Int, 0.95 * length(e)))])
end
