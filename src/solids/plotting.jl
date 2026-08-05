# plotting.jl — looking at a mesh before trusting it.
#
# A conduction result computed on a wrong mesh looks entirely plausible, so the mesh gets
# checked by eye first. Two views matter: the cells against the geometry they are supposed
# to represent, and the boundary normals coloured by tag, which is what catches a face
# attributed to the wrong channel.
#
# `RecipesBase` carries no backend, so this adds a recipe without pulling a plotting stack
# into the package. `write_vtk` covers the third view, a real 3D one: it hands the extruded
# mesh and a field over it to ParaView, which is where rotation, slicing and isosurfaces
# come from.

"""
    fill_fraction(cs, i) -> Float64

How much of cell `i`'s background rectangle its area actually fills. One for a whole cell,
less for a cut one. This is what merging thresholds on and what the mesh plot shades by.
"""
function fill_fraction(cs::CrossSection, i::Int)
    covered = sum(first(_area_centroid(ring)) for ring in cs.patches[i])
    return cs.area[i] / covered
end

"""
    cell_polygons(cs) -> Vector{@NamedTuple{cell::Int, ring::Vector{NTuple{2,Float64}}}}

The background rectangles the mesh occupies, each closed and labelled with the cell that
owns it. A merged cell contributes one entry per rectangle it absorbed, so its footprint
draws truthfully instead of as a bounding box overhanging the region.

These are extents, not the clipped shapes: a cut cell draws as its full rectangle dimmed to
its fill fraction, and the region's real outline goes over the top. The plot then shows the
grid and the geometry separately rather than pretending to a boundary-fitted mesh.
"""
function cell_polygons(cs::CrossSection)
    out = @NamedTuple{cell::Int, ring::Vector{NTuple{2,Float64}}}[]
    for i in 1:ncross(cs), ring in cs.patches[i]
        push!(out, (; cell=i, ring=vcat(ring, ring[1:1])))
    end
    return out
end

"""
    boundary_segments(cs) -> Vector{NamedTuple}

One entry per boundary face: the cell centroid it leaves from, its outward normal, its
length, the centroid-to-face distance, and its tag.
"""
function boundary_segments(cs::CrossSection)
    return map(cs.boundary) do b
        cx, cy = cs.centroid[b.c]
        (; x=cx, y=cy, nx=b.nx, ny=b.ny, len=b.len, d=b.d, tag=b.tag)
    end
end

"""
    outline_rings(domain; arc_segments=256) -> Vector{Vector{NTuple{2,Float64}}}

The region's true boundary as closed rings, for drawing over a mesh plot. Curved parts are
sampled at `arc_segments`, matching what the mesher clipped against.
"""
function outline_rings(domain::Shape; arc_segments::Int=256)
    poly = outline(domain; arc_segments=arc_segments)
    return map(Meshes.rings(poly)) do r
        pts = [_xy(p) for p in Meshes.vertices(r)]
        push!(pts, pts[1])
        pts
    end
end

function Base.show(io::IO, ::MIME"text/plain", cs::CrossSection)
    n = ncross(cs)
    fills = [fill_fraction(cs, i) for i in 1:n]
    cut = count(f -> f < 0.999, fills)
    print(io, "CrossSection")
    print(io, "\n  cells      ", n, " (", cut, " cut)")
    print(io, "\n  area       ", sum(cs.area))
    if n > 0
        print(io, "\n  fill       min ", round(minimum(fills); sigdigits=4),
              ", mean ", round(sum(fills) / n; sigdigits=4))
        # The stiffness indicator: a cell far smaller than its neighbours has a far
        # shorter time constant, for no physical reason.
        print(io, "\n  size ratio ", round(minimum(cs.area) / (sum(cs.area) / n); sigdigits=4),
              " (smallest cell over mean)")
    end
    print(io, "\n  faces      ", length(cs.faces), " interior, ",
          length(cs.boundary), " boundary")
    if !isempty(cs.faces)
        sk = mesh_skew(cs)
        print(io, "\n  skew       mean ", round(sk.mean; digits=1),
              "°, p95 ", round(sk.p95; digits=1), "°, max ", round(sk.max; digits=1), "°")
    end
    print(io, "\n  materials  ", sort(unique(cs.material)))
    for tag in cs.tags
        len = sum((b.len for b in cs.boundary if b.tag == tag); init=0.0)
        cells = count(b -> b.tag == tag, cs.boundary)
        print(io, "\n  tag :", tag, "  length ", round(len; sigdigits=6),
              " over ", cells, " faces")
    end
    return nothing
end

function Base.show(io::IO, ::MIME"text/plain", m::SolidMesh)
    print(io, "SolidMesh  ", ncross(m), " x ", nlayers(m), " = ", ncells(m), " cells")
    print(io, "\n  axial conduction ", m.axial ? "on" : "off")
    print(io, "\n  dz         ", length(unique(m.dz)) == 1 ? string(m.dz[1]) :
          string(minimum(m.dz), " to ", maximum(m.dz)))
    print(io, "\n  volume     ",
          sum(cell_volume(m, iz, ic) for iz in 1:nlayers(m), ic in 1:ncross(m)))
    print(io, "\n")
    show(io, MIME"text/plain"(), m.cross)
    return nothing
end

RecipesBase.@recipe function _meshplot(cs::CrossSection, domain=nothing)
    aspect_ratio --> 1
    legend --> false
    xguide --> "x [m]"
    yguide --> "y [m]"

    polys = cell_polygons(cs)
    fills = [fill_fraction(cs, p.cell) for p in polys]
    # On a body-fitted mesh every cell fills its own patch, so shading by fill fraction says
    # nothing and the cell edges carry the information instead. Only colour by it when there
    # is a spread to show, which means a cut-cell mesh.
    graded = maximum(fills) - minimum(fills) > 1e-6

    RecipesBase.@series begin
        seriestype := :shape
        linewidth --> 0.5
        linecolor --> :gray55
        if graded
            fill_z := permutedims(fills)
            # Forced, not a default: a fill fraction is definitionally in [0, 1], and
            # letting the limits autoscale turns 1e-15 of rounding on a uniform mesh into
            # a full spread of colour.
            clims := (0.0, 1.0)
            seriescolor --> :viridis
        else
            fillcolor --> :gray90
            fillalpha --> 0.55
        end
        [first.(p.ring) for p in polys], [last.(p.ring) for p in polys]
    end

    if domain !== nothing
        for ring in outline_rings(domain)
            RecipesBase.@series begin
                seriestype := :path
                linewidth --> 2
                linecolor --> :black
                first.(ring), last.(ring)
            end
        end
    end
end

"""
    boundarynormals(cs)

Plot recipe drawing one arrow per boundary face, coloured by tag. Use it to confirm every
face went to the channel it should have and that the normals point out of the solid.
"""
RecipesBase.@userplot BoundaryNormals

RecipesBase.@recipe function _normalsplot(bn::BoundaryNormals)
    cs = bn.args[1]::CrossSection
    aspect_ratio --> 1
    xguide --> "x [m]"
    yguide --> "y [m]"

    scale = 0.6 * sqrt(sum(cs.area) / max(ncross(cs), 1))
    for tag in cs.tags
        idx = [i for (i, b) in pairs(cs.boundary) if b.tag == tag]
        isempty(idx) && continue
        xs = Float64[]
        ys = Float64[]
        for i in idx
            b = cs.boundary[i]
            cx, cy = cs.centroid[b.c]
            # Start at the face rather than the centroid, so a corner cell's two faces draw
            # as two arrows on their own sides instead of one arrow along their diagonal.
            fx, fy = cx + b.d * b.nx, cy + b.d * b.ny
            append!(xs, (fx, fx + scale * b.nx, NaN))
            append!(ys, (fy, fy + scale * b.ny, NaN))
        end
        RecipesBase.@series begin
            seriestype := :path
            linewidth --> 1.5
            label := string(tag)
            xs, ys
        end
    end
end


"""
    meshheatmap(cs, values)
    meshheatmap(cs, values, domain)

Plot recipe shading each cell by a per-cell value, so a temperature field can be read
against the mesh that produced it. `values` has one entry per cross-section cell; for a
solved 3D mesh take one axial layer, `sol[sys.rod.T[iz, :]]`.

Pass `domain` to draw the region's true outline over the top, which is how a cut-cell mesh
gets read: its cells are background rectangles, and only the outline says where the
material actually stops.
"""
RecipesBase.@userplot MeshHeatmap

RecipesBase.@recipe function _meshheat(h::MeshHeatmap)
    cs = h.args[1]::CrossSection
    vals = h.args[2]
    length(vals) == ncross(cs) || throw(ArgumentError(
        "values must have one entry per cell, got $(length(vals)) for $(ncross(cs)) cells"))
    domain = length(h.args) >= 3 ? h.args[3] : nothing

    aspect_ratio --> 1
    legend --> false
    xguide --> "x [m]"
    yguide --> "y [m]"
    colorbar --> true

    polys = cell_polygons(cs)
    RecipesBase.@series begin
        seriestype := :shape
        linewidth --> 0.2
        linecolor --> :gray60
        fill_z := permutedims([vals[p.cell] for p in polys])
        seriescolor --> :inferno
        [first.(p.ring) for p in polys], [last.(p.ring) for p in polys]
    end

    if domain !== nothing
        for ring in outline_rings(domain)
            RecipesBase.@series begin
                seriestype := :path
                linewidth --> 2
                linecolor --> :white
                first.(ring), last.(ring)
            end
        end
    end
end

"""
    write_vtk(path, mesh, values; name="T", layer_values=false) -> String

Write the extruded mesh and a field over it as a legacy ASCII VTK unstructured grid, for
opening in ParaView or any VTK viewer. That is where slicing, clipping, isosurfaces and
rotation come from; nothing here tries to reproduce them.

# Arguments
- `path`: output file, `.vtk` appended if missing
- `mesh`: the `SolidMesh` that was solved on
- `values`: either one value per cross-section cell, repeated down every layer, or an
  `(nlayers, ncross)` matrix for a genuinely three-dimensional field
- `name`: the field's name in the file

Each cell contributes one hexahedron per axial layer, built from its footprint patches. A
merged cut cell has several patches and so several hexahedra, all carrying its one value,
which is the same convention the mesh plots use.

# Returns
The path written.
"""
function write_vtk(path::AbstractString, mesh::SolidMesh, values; name::AbstractString="T")
    file = endswith(path, ".vtk") ? path : path * ".vtk"
    cs = mesh.cross
    nz = nlayers(mesh)
    field = if values isa AbstractMatrix
        size(values) == (nz, ncross(mesh)) || throw(ArgumentError(
            "values must be $(nz)x$(ncross(mesh)), got $(size(values))"))
        values
    else
        length(values) == ncross(mesh) || throw(ArgumentError(
            "values must have one entry per cross-section cell, got $(length(values))"))
        [values[ic] for _ in 1:nz, ic in 1:ncross(mesh)]
    end

    z = cumsum([zero(eltype(mesh.dz)); mesh.dz])
    pts = NTuple{3,Float64}[]
    hexes = Vector{Int}[]
    cellval = Float64[]
    for ic in 1:ncross(mesh), ring in cs.patches[ic]
        length(ring) == 4 || throw(ArgumentError(
            "write_vtk handles four-sided cell patches; cell $ic has $(length(ring))"))
        for iz in 1:nz
            base = length(pts)
            for (x, y) in ring
                push!(pts, (Float64(x), Float64(y), Float64(z[iz])))
            end
            for (x, y) in ring
                push!(pts, (Float64(x), Float64(y), Float64(z[iz + 1])))
            end
            push!(hexes, collect(base:(base + 7)))
            push!(cellval, field[iz, ic])
        end
    end

    open(file, "w") do io
        println(io, "# vtk DataFile Version 3.0")
        println(io, "STREAM.jl solid mesh")
        println(io, "ASCII")
        println(io, "DATASET UNSTRUCTURED_GRID")
        println(io, "POINTS ", length(pts), " double")
        for p in pts
            println(io, p[1], " ", p[2], " ", p[3])
        end
        println(io, "CELLS ", length(hexes), " ", 9 * length(hexes))
        for h in hexes
            println(io, "8 ", join(h, " "))
        end
        println(io, "CELL_TYPES ", length(hexes))
        for _ in hexes
            println(io, 12)          # VTK_HEXAHEDRON
        end
        println(io, "CELL_DATA ", length(cellval))
        println(io, "SCALARS ", name, " double 1")
        println(io, "LOOKUP_TABLE default")
        for v in cellval
            println(io, v)
        end
    end
    return file
end
