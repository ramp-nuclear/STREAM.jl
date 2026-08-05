# test/test_solids.jl

using Test
using Meshes: Ball, Box, PolyArea, Triangle, measure, orientation, rings
using Unitful: ustrip
using STREAM
using STREAM.Solids
using STREAM.Solids: Leaf, ShapeDiff, ShapeUnion, ShapeInter, _idiff, _iintersect, _iunion

const BOX = Box((-3.0, -3.0), (3.0, 3.0))
const DISC = Ball((0.0, 0.0), 1.0)

# `≈` does not descend into a Vector of Tuples, so compare interval lists elementwise.
ivapprox(a, b; atol=1e-12) =
    length(a) == length(b) &&
    all(isapprox(x[1], y[1]; atol=atol) && isapprox(x[2], y[2]; atol=atol)
        for (x, y) in zip(a, b))

@testset "shape lifting and the combination operators" begin
    @test shape(BOX) isa Leaf
    @test shape(shape(BOX)) === shape(BOX)
    @test (shape(BOX) - DISC) isa ShapeDiff
    @test (BOX - shape(DISC)) isa ShapeDiff
    @test union(shape(BOX), DISC) isa ShapeUnion
    @test intersect(shape(BOX), DISC) isa ShapeInter
    # The ∪ and ∩ aliases route to the same constructors.
    @test (shape(BOX) ∪ DISC) isa ShapeUnion
    @test (shape(BOX) ∩ DISC) isa ShapeInter
end

@testset "inside: primitives, and each combinator" begin
    b, d = shape(BOX), shape(DISC)
    @test inside(b, 0.0, 0.0)
    @test !inside(b, 4.0, 0.0)
    @test inside(d, 0.5, 0.0)
    @test !inside(d, 1.5, 0.0)

    ring = b - DISC
    @test inside(ring, 2.0, 2.0)     # in the box, clear of the disc
    @test !inside(ring, 0.0, 0.0)    # in the hole
    @test !inside(ring, 9.0, 9.0)    # outside everything

    @test inside(b ∩ DISC, 0.5, 0.0)
    @test !inside(b ∩ DISC, 2.0, 2.0)

    far = Ball((10.0, 0.0), 1.0)
    @test inside(b ∪ far, 2.0, 0.0)
    @test inside(b ∪ far, 10.0, 0.0)
    @test !inside(b ∪ far, 6.0, 0.0)
end

@testset "dist_to_edge: analytic values on box and ball" begin
    b, d = shape(BOX), shape(DISC)
    @test dist_to_edge(d, 0.0, 0.0) ≈ 1.0       # centre to rim
    @test dist_to_edge(d, 2.0, 0.0) ≈ 1.0       # outside, to rim
    @test dist_to_edge(d, 1.0, 0.0) ≈ 0.0       # on the rim
    @test dist_to_edge(b, 0.0, 0.0) ≈ 3.0       # centre to nearest side
    @test dist_to_edge(b, 2.5, 0.0) ≈ 0.5
    @test dist_to_edge(b, 5.0, 0.0) ≈ 2.0       # outside, straight out from a side
    @test dist_to_edge(b, 6.0, 7.0) ≈ 5.0       # outside past a corner, 3-4-5

    # A composite reports the nearest leaf edge, so a hole rim stays findable even though
    # the region excludes the hole interior. That is what tag attribution needs.
    @test dist_to_edge(b - DISC, 0.0, 0.0) ≈ 1.0
    @test dist_to_edge(b - DISC, 2.9, 0.0) ≈ 0.1
end

@testset "dist_to_edge: unsupported geometry says so" begin
    @test_throws ArgumentError dist_to_edge(shape(Triangle((0.0,0.0),(1.0,0.0),(0.0,1.0))), 0.1, 0.1)
end

@testset "interval algebra" begin
    a = [(0.0, 0.5), (0.7, 1.0)]
    b = [(0.3, 0.8)]
    @test _iunion(a, b) == [(0.0, 1.0)]
    @test _iintersect(a, b) == [(0.3, 0.5), (0.7, 0.8)]
    @test _idiff(a, b) == [(0.0, 0.3), (0.8, 1.0)]
    @test _idiff(a, Tuple{Float64,Float64}[]) == a
    @test _iintersect(a, Tuple{Float64,Float64}[]) == Tuple{Float64,Float64}[]
    # Touching intervals merge; zero-width ones drop.
    @test _iunion([(0.0, 0.5)], [(0.5, 1.0)]) == [(0.0, 1.0)]
    @test _iunion([(0.2, 0.2)], Tuple{Float64,Float64}[]) == Tuple{Float64,Float64}[]
end

@testset "segment_inside: exact intervals against a ball" begin
    d = shape(DISC)
    # Along +x from the centre: inside until the rim at x=1, i.e. t <= 0.5 of a length-2 run.
    @test ivapprox(segment_inside(d, 0.0, 0.0, 2.0, 0.0), [(0.0, 0.5)])
    # A chord at y=0.6 cuts the unit circle at x = ±0.8.
    iv = segment_inside(d, -2.0, 0.6, 2.0, 0.6)
    @test length(iv) == 1
    @test iv[1][1] ≈ (2.0 - 0.8) / 4.0
    @test iv[1][2] ≈ (2.0 + 0.8) / 4.0
    # A line that misses entirely.
    @test isempty(segment_inside(d, -2.0, 1.5, 2.0, 1.5))
    # Tangent counts as a miss, since a zero-width interval carries no length.
    @test isempty(segment_inside(d, -2.0, 1.0, 2.0, 1.0))
end

@testset "segment_inside: exact intervals against a box" begin
    b = shape(Box((0.0, 0.0), (1.0, 1.0)))
    @test ivapprox(segment_inside(b, -1.0, 0.5, 2.0, 0.5), [(1/3, 2/3)])
    @test isempty(segment_inside(b, -1.0, 2.0, 2.0, 2.0))
    # A segment running along the interior is wholly inside.
    @test ivapprox(segment_inside(b, 0.25, 0.5, 0.75, 0.5), [(0.0, 1.0)])
end

@testset "inside_length: the wetted length of a grid face" begin
    ring = shape(BOX) - DISC

    # The face x = 0.5, y from -0.5 to 0.5, is entirely inside the hole (the disc reaches
    # y = ±0.866 there), so no part of it is wetted. This is the exact case where reading
    # lengths off the clipped polygon reports 1.0 instead of 0.
    @test inside_length(ring, 0.5, -0.5, 0.5, 0.5) ≈ 0.0 atol=1e-12

    # The face x = 1.5 over the same span never meets the disc, so all of it is wetted.
    @test inside_length(ring, 1.5, -0.5, 1.5, 0.5) ≈ 1.0

    # The face y = 0.5, x from 0.5 to 1.5, is wetted from the rim (x = √0.75) outward.
    @test inside_length(ring, 0.5, 0.5, 1.5, 0.5) ≈ 1.5 - sqrt(0.75)

    # A face crossing the whole disc leaves two wetted pieces.
    @test length(segment_inside(ring, -2.0, 0.0, 2.0, 0.0)) == 2
    @test inside_length(ring, -2.0, 0.0, 2.0, 0.0) ≈ 2.0
end

@testset "outline: area matches the polygon it promises, not the smooth shape" begin
    n = 256
    poly = outline(shape(BOX) - DISC; arc_segments=n)
    @test poly isa PolyArea
    @test length(rings(poly)) == 2
    # A regular n-gon inscribed in the unit circle, not the circle itself.
    ngon = n / 2 * sin(2π / n)
    @test ustrip(measure(poly)) ≈ 36 - ngon rtol=1e-12
    # And it converges on the disc as the sampling rises.
    coarse = ustrip(measure(outline(shape(BOX) - DISC; arc_segments=16)))
    fine = ustrip(measure(outline(shape(BOX) - DISC; arc_segments=4096)))
    @test abs(fine - (36 - π)) < abs(coarse - (36 - π))
end

@testset "outline: hole winding is enforced, not trusted" begin
    # The failure this guards against is silent: a hole wound the same way as the outer
    # ring makes PolyArea add its area instead of subtracting it.
    poly = outline(shape(BOX) - DISC; arc_segments=64)
    outer, hole = rings(poly)[1], rings(poly)[2]
    @test orientation(outer) != orientation(hole)
    @test ustrip(measure(poly)) < 36
end

@testset "outline: several holes, and a plain body" begin
    two = shape(BOX) - (shape(Ball((-1.5, 0.0), 0.5)) ∪ Ball((1.5, 0.0), 0.5))
    poly = outline(two; arc_segments=256)
    @test length(rings(poly)) == 3
    @test ustrip(measure(poly)) < 36

    plain = outline(shape(BOX))
    @test length(rings(plain)) == 1
    @test ustrip(measure(plain)) ≈ 36
end

@testset "outline: unsupported compositions throw rather than mislead" begin
    @test_throws ArgumentError outline(shape(BOX) ∪ Ball((10.0, 0.0), 1.0))
    @test_throws ArgumentError outline(shape(BOX) ∩ DISC)
    @test_throws ArgumentError outline(shape(BOX) - (shape(BOX) ∩ DISC))
    @test_throws ArgumentError outline(shape(Triangle((0.0,0.0),(1.0,0.0),(0.0,1.0))))
    @test_throws ArgumentError outline(shape(DISC); arc_segments=2)
end

# ---------------------------------------------------------------------------
# Mesh layer
# ---------------------------------------------------------------------------

const STEEL = SolidMaterial(19300.0, 116.0, 174.0)

# A uniform slab, the shape the pre-mesh HeatDiffusion built by hand.
_slab(; nx=4, Lx=0.005, y=0.07, nz=5, Lz=0.6, axial=true) = extrude(
    slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y),
    [(i - 1) * Lz / nz for i in 1:(nz + 1)];
    axial=axial,
)

@testset "slab_cross_section: counts, areas and tags" begin
    cs = slab_cross_section([0.0, 1.0, 3.0, 6.0], 2.0)
    @test ncross(cs) == 3
    @test cs.area ≈ [2.0, 4.0, 6.0]
    @test sum(cs.area) ≈ 6.0 * 2.0
    @test [c[1] for c in cs.centroid] ≈ [0.5, 2.0, 4.5]
    @test length(cs.faces) == 2
    @test length(cs.boundary) == 2
    @test tags(cs) == [:left, :right]
    # Half-cell distances follow the graded mesh rather than a single dx.
    @test cs.faces[1].d1 ≈ 0.5 && cs.faces[1].d2 ≈ 1.0
    @test cs.faces[2].d1 ≈ 1.0 && cs.faces[2].d2 ≈ 1.5
    @test cs.boundary[1].d ≈ 0.5 && cs.boundary[2].d ≈ 1.5
    @test all(f -> f.r_contact == 0.0, cs.faces)
end

@testset "slab_cross_section: too few boundaries errors" begin
    @test_throws ArgumentError slab_cross_section([0.0], 1.0)
end

@testset "extrude: volumes, graded dz, and the axial flag" begin
    m = _slab(; nx=4, Lx=0.005, y=0.07, nz=5, Lz=0.6)
    @test ncross(m) == 4
    @test nlayers(m) == 5
    @test ncells(m) == 20
    @test sum(cell_volume(m, iz, ic) for iz in 1:5, ic in 1:4) ≈ 0.005 * 0.07 * 0.6

    graded = extrude(slab_cross_section([0.0, 1.0], 1.0), [0.0, 0.5, 2.0])
    @test graded.dz ≈ [0.5, 1.5]
    @test cell_volume(graded, 1, 1) ≈ 0.5
    @test cell_volume(graded, 2, 1) ≈ 1.5
    @test length(graded.z_contact) == 1
    @test graded.axial
    @test !extrude(slab_cross_section([0.0, 1.0], 1.0), [0.0, 1.0]; axial=false).axial
end

@testset "extrude: z_contact length is checked" begin
    cs = slab_cross_section([0.0, 1.0], 1.0)
    @test_throws ArgumentError extrude(cs, [0.0, 0.5, 1.0]; z_contact=[0.0, 0.0])
    @test_throws ArgumentError extrude(cs, [0.0])
end

@testset "cellindex flattens row-major with the axial index outermost" begin
    m = _slab(; nx=3, nz=4)
    @test cellindex(m, 1, 1) == 1
    @test cellindex(m, 1, 3) == 3
    @test cellindex(m, 2, 1) == 4
    @test cellindex(m, 4, 3) == 12
    @test sort([cellindex(m, iz, ic) for iz in 1:4 for ic in 1:3]) == 1:12
end

@testset "conductances on a uniform slab match the closed forms" begin
    nx, Lx, y, nz, Lz = 4, 0.005, 0.07, 5, 0.6
    m = _slab(; nx=nx, Lx=Lx, y=y, nz=nz, Lz=Lz)
    mats = [STEEL]
    dx, dz = Lx / nx, Lz / nz
    k = STEEL.k

    # Interior: two half-cells in series is k·A/dx.
    @test interior_conductance(m, mats, m.cross.faces[1], 1) ≈ k * y * dz / dx
    # Boundary: one half-cell, so twice that.
    @test boundary_conductance(m, mats, m.cross.boundary[1], 1) ≈ 2 * k * y * dz / dx
    # Axial: the face is the cell cross-section, the distance is dz.
    @test axial_conductance(m, mats, 1, 1) ≈ k * (dx * y) / dz
    @test heat_capacity(m, mats, 1, 1) ≈ STEEL.rho * STEEL.cp * dx * y * dz
end

@testset "conductance is symmetric in the two cells of a face" begin
    m = _slab(; nx=4)
    mats = [STEEL]
    f = m.cross.faces[2]
    flipped = CrossFace(f.c2, f.c1, f.len, f.d2, f.d1, f.r_contact)
    @test interior_conductance(m, mats, f, 1) ≈ interior_conductance(m, mats, flipped, 1)
end

@testset "contact resistance adds in series, and set_contact! places it" begin
    m = _slab(; nx=4, Lx=0.005, y=0.07, nz=5, Lz=0.6)
    mats = [STEEL]
    dx, dz = 0.005 / 4, 0.6 / 5
    base = interior_conductance(m, mats, m.cross.faces[1], 1)

    # A resistance equal to the conduction path halves the conductance.
    r = dx / STEEL.k
    set_contact!(m.cross, r; where=(c1, c2) -> c1 == 1)
    @test m.cross.faces[1].r_contact ≈ r
    @test interior_conductance(m, mats, m.cross.faces[1], 1) ≈ base / 2
    # Only the selected face moved.
    @test m.cross.faces[2].r_contact == 0.0
    @test interior_conductance(m, mats, m.cross.faces[2], 1) ≈ base
end

@testset "two materials: the face resistance uses each cell's own k" begin
    cs = slab_cross_section([0.0, 1.0, 2.0], 1.0)
    cs.material[2] = 2
    m = extrude(cs, [0.0, 1.0])
    soft = SolidMaterial(1.0, 1.0, 1.0)
    hard = SolidMaterial(1.0, 1.0, 3.0)
    # d1/k1 + d2/k2 = 0.5/1 + 0.5/3
    @test interior_conductance(m, [soft, hard], m.cross.faces[1], 1) ≈ 1.0 / (0.5 + 0.5 / 3)
end

@testset "boundary_groups and contact_area" begin
    m = _slab(; nx=4, Lx=0.005, y=0.07, nz=5, Lz=0.6)
    g = boundary_groups(m)
    @test sort(collect(keys(g))) == [:left, :right]
    @test length(g[:left]) == 1
    @test length(g[:right]) == 1
    # One face of depth y, per layer of height dz.
    @test contact_area(m, :left, 1) ≈ 0.07 * (0.6 / 5)
    @test contact_area(m, :nonexistent, 1) ≈ 0.0
    # Summed over layers it is the whole plate face.
    @test sum(contact_area(m, :left, iz) for iz in 1:5) ≈ 0.07 * 0.6
end

# ---------------------------------------------------------------------------
# Cut-cell mesher
# ---------------------------------------------------------------------------

# The driving geometry: a square rod with a circular bore, four flats plus the bore.
function _rod(; w=12e-3, r=3e-3, dx=1e-3)
    box = Box((-w/2, -w/2), (w/2, w/2))
    bore = Ball((0.0, 0.0), r)
    dom = shape(box) - bore
    return cut_cell_cross_section(dom; dx=dx, dy=dx,
        boundaries=(bore => :bore, box => :wall))
end

@testset "cut cells: a grid-aligned rectangle produces no cut cells at all" begin
    box = Box((0.0, 0.0), (4.0, 2.0))
    cs = cut_cell_cross_section(shape(box); dx=1.0, dy=1.0, boundaries=(box => :wall,))
    @test ncross(cs) == 8
    @test sum(cs.area) ≈ 8.0
    @test all(c -> c ≈ 1.0, cs.area)
    # Interior faces: 3 vertical seams x 2 rows + 1 horizontal seam x 4 columns.
    @test length(cs.faces) == 10
    @test all(f -> f.len ≈ 1.0 && f.d1 ≈ 0.5 && f.d2 ≈ 0.5, cs.faces)
    # Every boundary cell reports wall, and the total perimeter is exact.
    @test sum(b.len for b in cs.boundary) ≈ 12.0
end

@testset "cut cells: area is exact at any mesh size, and only the arc sampling limits it" begin
    disc = Ball((0.0, 0.0), 1.0)

    # Clipping is exact, so refining the mesh does not improve the area. What is left is
    # the polygon standing in for the circle, and that error is the same at every h.
    errs = map((0.2, 0.1, 0.05)) do h
        cs = cut_cell_cross_section(shape(disc); dx=h, dy=h, arc_segments=2048,
                                    boundaries=(disc => :wall,))
        abs(sum(cs.area) - π) / π
    end
    @test all(e -> isapprox(e, errs[1]; rtol=1e-6), errs)
    # And that floor is the n-gon's own deficit, not a meshing error.
    ngon_err(n) = abs(n / 2 * sin(2π / n) - π) / π
    @test errs[1] ≈ ngon_err(2048) rtol=1e-6

    # Raising the sampling is what moves it.
    finer = let cs = cut_cell_cross_section(shape(disc); dx=0.1, dy=0.1, arc_segments=8192,
                                            boundaries=(disc => :wall,))
        abs(sum(cs.area) - π) / π
    end
    @test finer < errs[1] / 10

    # The rod-with-bore area, which is what the driving case depends on.
    cs = _rod(; dx=0.5e-3)
    @test sum(cs.area) ≈ 12e-3^2 - π * 3e-3^2 rtol=1e-4
end

@testset "cut cells: per-tag boundary length matches the analytic perimeter" begin
    cs = _rod(; dx=0.4e-3)
    bore_len = sum(b.len for b in cs.boundary if b.tag == :bore)
    wall_len = sum(b.len for b in cs.boundary if b.tag == :wall)
    @test bore_len ≈ 2π * 3e-3 rtol=5e-3
    @test wall_len ≈ 4 * 12e-3 rtol=5e-3
    @test sort(tags(cs)) == [:bore, :wall]
end

@testset "cut cells: every cell closes, Σ A n̂ ≈ 0" begin
    # The identity the cut face is derived from, checked independently by rebuilding the
    # per-cell normal sum from the finished CrossSection. A generator that produced a
    # geometrically inconsistent cell fails here.
    cs = _rod(; dx=0.8e-3)
    sx = zeros(ncross(cs))
    sy = zeros(ncross(cs))
    for f in cs.faces
        # The face normal points from the lower-centroid cell to the higher one.
        c1, c2 = cs.centroid[f.c1], cs.centroid[f.c2]
        vertical = abs(c2[1] - c1[1]) > abs(c2[2] - c1[2])
        if vertical
            s = sign(c2[1] - c1[1])
            sx[f.c1] += s * f.len
            sx[f.c2] -= s * f.len
        else
            s = sign(c2[2] - c1[2])
            sy[f.c1] += s * f.len
            sy[f.c2] -= s * f.len
        end
    end
    # Interior cells (no boundary face) must close on the grid faces alone.
    hasb = falses(ncross(cs))
    for b in cs.boundary
        hasb[b.c] = true
    end
    interior = findall(.!hasb)
    @test !isempty(interior)
    @test all(i -> hypot(sx[i], sy[i]) < 1e-9, interior)

    # Conversely, any cell whose grid faces fail to cancel must have been given boundary
    # face to close it. A leak here means heat vanishing at the wall.
    leaking = findall(i -> hypot(sx[i], sy[i]) > 1e-9 && !hasb[i], 1:ncross(cs))
    @test isempty(leaking)
end

@testset "cut cells: faces reference distinct cells and appear once" begin
    cs = _rod(; dx=0.8e-3)
    @test all(f -> f.c1 != f.c2, cs.faces)
    @test all(f -> f.len > 0 && f.d1 > 0 && f.d2 > 0, cs.faces)
    pairs_seen = Set{Tuple{Int,Int}}()
    for f in cs.faces
        key = minmax(f.c1, f.c2)
        @test !(key in pairs_seen)
        push!(pairs_seen, key)
    end
end

@testset "cut cells: merging removes the slivers and conserves area" begin
    disc = Ball((0.0, 0.0), 1.0)
    dom = shape(disc)
    unmerged = cut_cell_cross_section(dom; dx=0.1, dy=0.1, merge_below=0.0,
                                      boundaries=(disc => :wall,))
    merged = cut_cell_cross_section(dom; dx=0.1, dy=0.1, merge_below=0.5,
                                    boundaries=(disc => :wall,))
    @test sum(merged.area) ≈ sum(unmerged.area) rtol=1e-12
    @test ncross(merged) < ncross(unmerged)

    @test minimum(fill_fraction(unmerged, i) for i in 1:ncross(unmerged)) < 0.5
    # The point of merging is stiffness, so measure what drives it: the smallest cell
    # relative to the mean, which is the ratio of the shortest time constant to the
    # typical one.
    ratio(cs) = minimum(cs.area) / (sum(cs.area) / ncross(cs))
    @test ratio(merged) > 3 * ratio(unmerged)
    @test all(f -> f.c1 != f.c2, merged.faces)
    # Merged cells keep one background rectangle per cell they absorbed.
    @test sum(length(p) for p in merged.patches) == ncross(unmerged)
end

@testset "cut cells: regions assign materials, last match winning" begin
    box = Box((0.0, 0.0), (4.0, 1.0))
    clad = Box((0.0, 0.0), (1.0, 1.0))
    cs = cut_cell_cross_section(shape(box); dx=1.0, dy=1.0,
                                regions=(clad => 2,), boundaries=(box => :wall,))
    @test ncross(cs) == 4
    # Only the leftmost cell sits inside the clad region.
    @test count(==(2), cs.material) == 1
    @test cs.material[argmin([c[1] for c in cs.centroid])] == 2
end

@testset "cut cells: an untagged boundary is left adiabatic" begin
    box = Box((0.0, 0.0), (2.0, 2.0))
    # No boundaries at all means no thermal ports anywhere.
    cs = cut_cell_cross_section(shape(box); dx=1.0, dy=1.0)
    @test isempty(cs.boundary)
    @test isempty(tags(cs))

    # A tagged shape far from this region does not capture its boundary.
    far = Ball((100.0, 100.0), 1.0)
    cs2 = cut_cell_cross_section(shape(box); dx=1.0, dy=1.0, boundaries=(far => :elsewhere,))
    @test isempty(cs2.boundary)
end

@testset "cut cells: the rod meshes and extrudes into a 3D mesh" begin
    cs = _rod(; dx=1e-3)
    m = extrude(cs, [(i - 1) * 0.6 / 10 for i in 1:11])
    @test nlayers(m) == 10
    @test ncells(m) == 10 * ncross(cs)
    @test sum(cell_volume(m, iz, ic) for iz in 1:10, ic in 1:ncross(cs)) ≈
          (12e-3^2 - π * 3e-3^2) * 0.6 rtol=5e-3
    g = boundary_groups(m)
    @test sort(collect(keys(g))) == [:bore, :wall]
    @test contact_area(m, :bore, 1) ≈ 2π * 3e-3 * 0.06 rtol=1e-2
end

@testset "cut cells: bad arguments are rejected" begin
    box = Box((0.0, 0.0), (1.0, 1.0))
    @test_throws ArgumentError cut_cell_cross_section(shape(box); dx=0.0, dy=1.0)
    @test_throws ArgumentError cut_cell_cross_section(shape(box); dx=1.0, dy=1.0, merge_below=1.0)
end

# ---------------------------------------------------------------------------
# Body-fitted O-grid
# ---------------------------------------------------------------------------

const W_ROD = 12e-3
const R_BORE = 3e-3
const OUTER_BOX = Box((-W_ROD/2, -W_ROD/2), (W_ROD/2, W_ROD/2))
const BORE = Ball((0.0, 0.0), R_BORE)

_flat(side) = (t = 0.2e-3; w = W_ROD/2;
    side === :north ? Box((-w, w - t), (w, w + t)) :
    side === :south ? Box((-w, -w - t), (w, -w + t)) :
    side === :east  ? Box((w - t, -w), (w + t, w)) :
                      Box((-w - t, -w), (-w + t, w)))

_rod_tags() = (BORE => :bore, _flat(:north) => :north, _flat(:south) => :south,
               _flat(:east) => :east, _flat(:west) => :west)

_ogrid(; nθ=48, nr=6, kw...) =
    ogrid_cross_section(BORE, OUTER_BOX; n_angular=nθ, n_radial=nr,
                        boundaries=_rod_tags(), kw...)

@testset "ogrid: cell count, and every cell fills its own patch" begin
    cs = _ogrid(; nθ=48, nr=6)
    @test ncross(cs) == 48 * 6
    # Body-fitted, so there are no cut cells: a cell is its patch.
    @test all(i -> fill_fraction(cs, i) ≈ 1.0, 1:ncross(cs))
    @test all(a -> a > 0, cs.area)
end

@testset "ogrid: area is exact given the bore's polygon sampling" begin
    # The bore is sampled at n_angular points, so the mesh models an n-gon bore, not a
    # circle. Everything else is exact, which pins the error to a closed form.
    for nθ in (32, 64, 128)
        cs = _ogrid(; nθ=nθ, nr=5)
        ngon = nθ / 2 * sin(2π / nθ) * R_BORE^2
        @test sum(cs.area) ≈ W_ROD^2 - ngon rtol=1e-12
    end
    # And it converges on the true annulus area as the sampling rises.
    err(nθ) = abs(sum(_ogrid(; nθ=nθ, nr=5).area) - (W_ROD^2 - π * R_BORE^2))
    @test err(128) < err(32) / 10
end

@testset "ogrid: the flats are exact and the bore matches its polygon" begin
    cs = _ogrid(; nθ=64, nr=6)
    for side in (:north, :south, :east, :west)
        got = sum(b.len for b in cs.boundary if b.tag == side)
        @test got ≈ W_ROD rtol=1e-12
    end
    bore = sum(b.len for b in cs.boundary if b.tag == :bore)
    @test bore ≈ 64 * 2R_BORE * sin(π / 64) rtol=1e-12
    @test sort(tags(cs)) == [:bore, :east, :north, :south, :west]
end

@testset "patch test: exact where the mapping is conformal" begin
    # A slab and a concentric annulus are the two cases where the mapping to the mesh is
    # conformal, so two-point flux reproduces a linear field exactly. These are the
    # controls that prove the diagnostic is measuring skew and not something else.
    slab = slab_cross_section([(j - 1) * 5e-3 / 8 for j in 1:9], 70e-3)
    @test mesh_skew(slab).max ≈ 0 atol=1e-4   # acosd near 1 floors at ~1e-6 degrees
    @test linear_patch_error(slab).max < 1e-12

    disc = Ball((0.0, 0.0), W_ROD / 2)
    ann = ogrid_cross_section(BORE, disc; n_angular=48, n_radial=6,
                              boundaries=(BORE => :bore, disc => :wall))
    @test mesh_skew(ann).max ≈ 0 atol=1e-4
    @test linear_patch_error(ann).max < 1e-10
end

@testset "patch test: a bored square is skewed on both meshes" begin
    # Neither mesh is exact here, because no mapping from a circle to a square is
    # conformal. Recorded so a regression in either generator has to be looked at.
    cut = cut_cell_cross_section(shape(OUTER_BOX) - BORE; dx=0.5e-3, dy=0.5e-3,
                                 boundaries=(BORE => :bore, OUTER_BOX => :wall))
    og = _ogrid(; nθ=48, nr=6)

    # Cut-cell is orthogonal in its interior but not at the boundary cells, whose
    # centroids move off the grid line when they are clipped.
    @test mesh_skew(cut).mean < 3
    @test 1e-3 < linear_patch_error(cut).p95 < 0.1

    # The body-fitted mesh carries its skew where it turns the corner instead.
    @test 5 < mesh_skew(og).mean < 12
    @test 1e-3 < linear_patch_error(og).p95 < 0.2
end

@testset "ogrid: boundary normals point out of the solid" begin
    dom = shape(OUTER_BOX) - BORE
    cs = _ogrid(; nθ=48, nr=6)
    for b in cs.boundary
        cx, cy = cs.centroid[b.c]
        step = 1.2 * b.d
        @test !inside(dom, cx + step * b.nx, cy + step * b.ny)
    end
end

@testset "ogrid: smoothing reduces skew, refinement does not" begin
    raw = mesh_skew(_ogrid(; nθ=48, nr=6, smoothing=0))
    smoothed = mesh_skew(_ogrid(; nθ=48, nr=6, smoothing=400))
    @test smoothed.mean < raw.mean / 2

    # Non-orthogonality is a property of the circle-to-square mapping, not of how finely
    # it is discretized, so refining the mesh leaves it where it was. This is the reason
    # the O-grid trades exactness for body fitting rather than converging to it.
    coarse = mesh_skew(_ogrid(; nθ=32, nr=4))
    fine = mesh_skew(_ogrid(; nθ=64, nr=16))
    @test isapprox(coarse.mean, fine.mean; atol=1.0)

    # The bore is where the gradient is steepest, and it is nearly orthogonal there.
    cs = _ogrid(; nθ=48, nr=6)
    near = filter(cs.faces) do f
        r = hypot(((cs.centroid[f.c1] .+ cs.centroid[f.c2]) ./ 2)...)
        r < R_BORE + (W_ROD / 2 - R_BORE) / 4
    end
    worst = maximum(near) do f
        v = hypot((cs.centroid[f.c2] .- cs.centroid[f.c1])...)
        acosd(clamp((f.d1 + f.d2) / v, -1, 1))
    end
    @test worst < 8
end

@testset "ogrid: graded radial spacing and material regions" begin
    # Fine cells against the bore, and a clad layer as the outer fifth.
    frac = [0.0, 0.05, 0.15, 0.35, 0.65, 0.8, 1.0]
    clad = shape(OUTER_BOX) - Ball((0.0, 0.0), R_BORE + 0.8 * (W_ROD/2 - R_BORE))
    cs = ogrid_cross_section(BORE, OUTER_BOX; n_angular=32, radial=frac,
                             boundaries=_rod_tags(), regions=(clad => 2,))
    @test ncross(cs) == 32 * 6
    @test 2 in cs.material
    @test count(==(2), cs.material) < ncross(cs)
    # The innermost ring is the thinnest, which is what grading was asked for.
    inner = [cs.area[i] for i in 1:32]
    outer = [cs.area[i] for i in (5 * 32 + 1):(6 * 32)]
    @test sum(inner) < sum(outer)
end

@testset "ogrid: bad arguments are rejected" begin
    @test_throws ArgumentError ogrid_cross_section(BORE, OUTER_BOX; n_angular=4, n_radial=4)
    @test_throws ArgumentError ogrid_cross_section(BORE, OUTER_BOX; n_angular=32)
    @test_throws ArgumentError ogrid_cross_section(BORE, OUTER_BOX; n_angular=32,
                                                   radial=[0.0, 0.5])
    @test_throws ArgumentError ogrid_cross_section(BORE, OUTER_BOX; n_angular=32,
                                                   radial=[0.0, 0.7, 0.3, 1.0])
    @test_throws ArgumentError ogrid_cross_section(
        Triangle((0.0,0.0),(1.0,0.0),(0.0,1.0)), OUTER_BOX; n_angular=32, n_radial=3)
end

@testset "ogrid: extrudes into a 3D mesh with five tag groups" begin
    cs = _ogrid(; nθ=48, nr=6)
    m = extrude(cs, [(i - 1) * 0.6 / 10 for i in 1:11])
    @test ncells(m) == 10 * 48 * 6
    @test sort(collect(keys(boundary_groups(m)))) == [:bore, :east, :north, :south, :west]
    @test contact_area(m, :north, 1) ≈ W_ROD * 0.06 rtol=1e-12
    @test sum(cell_volume(m, iz, ic) for iz in 1:10, ic in 1:ncross(m)) ≈
          sum(cs.area) * 0.6 rtol=1e-12
end

# ---------------------------------------------------------------------------
# Mesh inspection
# ---------------------------------------------------------------------------

@testset "fill_fraction: one for whole cells, less for cut ones" begin
    box = Box((0.0, 0.0), (4.0, 2.0))
    aligned = cut_cell_cross_section(shape(box); dx=1.0, dy=1.0, boundaries=(box => :wall,))
    @test all(i -> fill_fraction(aligned, i) ≈ 1.0, 1:ncross(aligned))

    disc = Ball((0.0, 0.0), 1.0)
    cut = cut_cell_cross_section(shape(disc); dx=0.2, dy=0.2, merge_below=0.0,
                                 boundaries=(disc => :wall,))
    @test minimum(fill_fraction(cut, i) for i in 1:ncross(cut)) < 1.0
    @test all(i -> 0 < fill_fraction(cut, i) <= 1.0 + 1e-12, 1:ncross(cut))
end

@testset "cell_polygons and boundary_segments describe the mesh" begin
    cs = _rod(; dx=1e-3)
    polys = cell_polygons(cs)
    @test length(polys) >= ncross(cs)
    @test sort(unique(p.cell for p in polys)) == 1:ncross(cs)
    @test all(p -> length(p.ring) == 5 && p.ring[1] == p.ring[end], polys)

    segs = boundary_segments(cs)
    @test length(segs) == length(cs.boundary)
    @test all(s -> s.len > 0 && s.d > 0, segs)
    @test all(s -> isapprox(hypot(s.nx, s.ny), 1.0; atol=1e-9), segs)
    @test sort(unique(s.tag for s in segs)) == [:bore, :wall]
end

@testset "boundary normals point out of the solid" begin
    # Stepping from the centroid along the stored normal by the stored distance has to
    # land on or beyond the region's edge, never back inside it.
    w, r = 12e-3, 3e-3
    dom = shape(Box((-w/2, -w/2), (w/2, w/2))) - Ball((0.0, 0.0), r)
    cs = _rod(; dx=0.8e-3)
    for b in cs.boundary
        cx, cy = cs.centroid[b.c]
        step = 1.05 * b.d
        @test !inside(dom, cx + step * b.nx, cy + step * b.ny)
    end
end

@testset "every cell closes once boundary faces are counted" begin
    # The full divergence identity, now that boundary normals are stored: over each cell,
    # interior faces plus boundary faces sum to zero. This is the check that no wall area
    # went missing and none points the wrong way.
    cs = _rod(; dx=0.8e-3)
    sx = zeros(ncross(cs))
    sy = zeros(ncross(cs))
    for f in cs.faces
        c1, c2 = cs.centroid[f.c1], cs.centroid[f.c2]
        vertical = abs(c2[1] - c1[1]) > abs(c2[2] - c1[2])
        s = vertical ? sign(c2[1] - c1[1]) : sign(c2[2] - c1[2])
        if vertical
            sx[f.c1] += s * f.len
            sx[f.c2] -= s * f.len
        else
            sy[f.c1] += s * f.len
            sy[f.c2] -= s * f.len
        end
    end
    for b in cs.boundary
        sx[b.c] += b.nx * b.len
        sy[b.c] += b.ny * b.len
    end
    scale = maximum(f.len for f in cs.faces)
    @test maximum(hypot(sx[i], sy[i]) for i in 1:ncross(cs)) < 1e-9 * scale
end

@testset "outline_rings closes every ring and matches the domain" begin
    dom = shape(Box((-1.0, -1.0), (1.0, 1.0))) - Ball((0.0, 0.0), 0.4)
    rings = outline_rings(dom; arc_segments=32)
    @test length(rings) == 2
    @test all(r -> r[1] == r[end], rings)
    @test length(rings[1]) == 5          # a box, closed
    @test length(rings[2]) == 33         # 32 arc points, closed
end

@testset "show reports the numbers a mesh review needs" begin
    cs = _rod(; dx=1e-3)
    s = sprint(show, MIME"text/plain"(), cs)
    @test occursin("CrossSection", s)
    @test occursin("cells", s)
    @test occursin("bore", s)
    @test occursin("wall", s)

    m = extrude(cs, [0.0, 0.3, 0.6])
    ms = sprint(show, MIME"text/plain"(), m)
    @test occursin("SolidMesh", ms)
    @test occursin("axial conduction on", ms)
    @test occursin("CrossSection", ms)
    off = sprint(show, MIME"text/plain"(), extrude(cs, [0.0, 0.6]; axial=false))
    @test occursin("axial conduction off", off)
end

@testset "a design knob survives the slab path" begin
    # test_knobs.jl drives HeatDiffusion with a Num Lx, so the slab generator has to
    # carry symbolic lengths through without touching a coordinate comparison.
    @design_knob gap = 0.005
    cs = slab_cross_section([(j - 1) * gap / 4 for j in 1:5], 0.07)
    @test eltype(cs.area) <: Real
    @test !(eltype(cs.area) <: AbstractFloat)
    m = extrude(cs, [(i - 1) * 0.6 / 5 for i in 1:6])
    @test ncross(m) == 4
    @test nlayers(m) == 5
    # The knob is still in the expression rather than folded to a number.
    @test occursin("gap", string(cell_volume(m, 1, 1)))
end

@testset "write_vtk emits a well-formed grid with the right counts" begin
    mktempdir() do dir
        cs = _rod(; dx=1.5e-3)
        m = extrude(cs, [0.0, 0.3, 0.6])
        nz, nc = nlayers(m), ncross(m)
        npatch = sum(length(p) for p in cs.patches)

        f = write_vtk(joinpath(dir, "rod"), m, collect(1.0:nc))
        @test endswith(f, ".vtk")
        txt = read(f, String)
        lines = split(txt, '\n')

        # One hexahedron per patch per layer, eight points each.
        ncell = npatch * nz
        @test occursin("CELLS $ncell $(9 * ncell)", txt)
        @test occursin("CELL_TYPES $ncell", txt)
        @test occursin("POINTS $(8 * ncell) double", txt)
        @test occursin("CELL_DATA $ncell", txt)
        @test count(==("12"), strip.(lines)) == ncell

        # A 3D field is carried through per layer rather than flattened.
        vals = [10.0 * iz + ic for iz in 1:nz, ic in 1:nc]
        f2 = write_vtk(joinpath(dir, "rod3d.vtk"), m, vals)
        body = read(f2, String)
        @test occursin("SCALARS T double 1", body)
        @test occursin("\n$(10.0 * 2 + 1)\n", body)

        @test_throws ArgumentError write_vtk(joinpath(dir, "bad"), m, collect(1.0:(nc + 1)))
        @test_throws ArgumentError write_vtk(joinpath(dir, "bad2"), m, zeros(nz + 1, nc))
    end
end

@testset "ogrid: the outer polygon is the box, at any n_angular" begin
    # Walking the perimeter by arc length alone only lands on a corner when n divides it
    # that way. Every other n cuts the corners off, shrinking the domain silently: at
    # n = 20 the four sides came to 45.2 mm of a true 48, and the four flats split
    # 11.3/11.3/9.6/13.0 instead of 12 each.
    for nθ in (20, 24, 30, 33, 48, 50)
        cs = _ogrid(; nθ=nθ, nr=3)
        @test sum(cs.area) ≈ W_ROD^2 - nθ / 2 * sin(2π / nθ) * R_BORE^2 rtol=1e-12
        walls = sum(b.len for b in cs.boundary if b.tag != :bore)
        @test walls ≈ 4 * W_ROD rtol=1e-12
    end
end

@testset "ogrid: each flat gets its own share of the wall" begin
    # With the corners pinned and n_angular a multiple of 8, the four flats are equal.
    # This is what makes four identical channels see identical duty.
    cs = _ogrid(; nθ=48, nr=4)
    for side in (:north, :south, :east, :west)
        @test sum(b.len for b in cs.boundary if b.tag == side) ≈ W_ROD rtol=1e-12
    end
end

@testset "ogrid: eight angular points is exactly enough for a box" begin
    # Four corners and four midpoints, the coarsest ring that still traces the box.
    cs = _ogrid(; nθ=8, nr=2)
    @test sum(b.len for b in cs.boundary if b.tag != :bore) ≈ 4 * W_ROD rtol=1e-12
end
