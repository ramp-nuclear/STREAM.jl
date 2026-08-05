# examples/conduction_meshes.jl
#
# Usage:
#   julia --project examples/conduction_meshes.jl
#
# Steady conduction on each of the three mesh generators, checked against a closed-form
# answer wherever one exists, and drawn as a temperature field over the mesh that produced
# it. Doubles as a tour of the API: every step a caller has to take appears once, in order,
# with nothing hidden in a helper except the boilerplate of pinning a wall temperature.
#
# Plotting needs a backend the package does not depend on. Install Plots to get the
# figures; without it the script still runs and prints every number.
#
#   julia --project -e 'using Pkg; Pkg.add("Plots")'

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq
using SteadyStateDiffEq
using Printf
using Meshes: Ball, Box
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Solids

const PLOTTING = try
    @eval using Plots
    @eval gr()
    true
catch
    @info "Plots not installed, printing numbers only. Add it with Pkg.add(\"Plots\")."
    false
end

const OUT = joinpath(@__DIR__, "conduction_meshes_output")
PLOTTING && mkpath(OUT)

# ---------------------------------------------------------------------------------------
# One helper, because pinning a wall temperature is boilerplate rather than API.
#
# Holds every face of `pinned` at `T_wall`, leaves every other tag adiabatic (an untagged
# or unconnected boundary carries no heat), and solves to steady state. Returns the
# per-cell temperatures of one axial layer.
# ---------------------------------------------------------------------------------------
function solve_conduction(mesh, materials, power_shape, power, T_wall;
                          pinned=tags(mesh), layer=1, name=:solid)
    @named solid = HeatDiffusion(mesh; materials=materials, power_shape=power_shape,
                                 power=power)
    nz = nlayers(mesh)
    walls = Any[]
    conns = Equation[]
    for tag in pinned
        v = [ConstantTemperature(T_wall; name=Symbol(name, :_, tag, i)) for i in 1:nz]
        append!(walls, v)
        append!(conns, [connect(v[i].thermal, port(solid, Symbol(:thermal_, tag), i))
                        for i in 1:nz])
    end
    push!(conns, solid.power ~ power)

    sys = compose(System(conns, t; name=Symbol(name, :_sys)), solid, walls...)
    ssys = mtkcompile(sys)
    guess = [ssys.solid.T[i, j] => T_wall + 10.0
             for i in 1:nz for j in 1:ncross(mesh)]
    sol = solve_steady(ssys, guess)
    return [sol[ssys.solid.T[layer, j]] for j in 1:ncross(mesh)]
end

# Share the power out by cell volume, so the source is uniform per unit volume.
uniform_power(cs, nz) =
    [cs.area[j] / (nz * sum(cs.area)) for i in 1:nz, j in 1:ncross(cs)]

report(label, got, want) = @printf("  %-34s %10.4f  vs %10.4f   rel %8.2e\n",
                                   label, got, want, abs(got - want) / abs(want))

const K = 20.0            # W/(m*K), the same solid throughout
const MAT = [SolidMaterial(1.0, 1.0, K)]
const T_WALL = 100.0

# ---------------------------------------------------------------------------------------
# 1. Flat plate. Exactly orthogonal, so the scheme is exact and only discretization error
#    remains. Analytic: T(x) - T_wall = q'''(L^2/4 - (x - L/2)^2) / 2k.
# ---------------------------------------------------------------------------------------
println("\n1. Flat plate, slab mesh")

Lx, y, nx = 0.02, 1.0, 40
plate = slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y)
plate_mesh = extrude(plate, [0.0, 1.0]; axial=false)
show(stdout, MIME"text/plain"(), plate_mesh)
println()

power = 5.0e3
T_plate = solve_conduction(plate_mesh, MAT, uniform_power(plate, 1), power, T_WALL;
                           name=:plate)
qppp = power / (Lx * y * 1.0)
report("peak rise [K]", maximum(T_plate) - T_WALL, qppp * Lx^2 / (8K))

worst = maximum(1:nx) do j
    x = (j - 0.5) * Lx / nx
    abs(T_plate[j] - (T_WALL + qppp * (Lx^2 / 4 - (x - Lx / 2)^2) / (2K)))
end
@printf("  %-34s %10.2e K\n", "worst cell error", worst)

# ---------------------------------------------------------------------------------------
# 2. Concentric annulus, body-fitted. Circle to circle is a conformal polar mapping, so
#    this mesh is exactly orthogonal too. Adiabatic bore, fixed outer wall:
#      T(r_i) - T(r_o) = q'''/(2k) * [ (r_o^2 - r_i^2)/2 - r_i^2 ln(r_o/r_i) ]
# ---------------------------------------------------------------------------------------
println("\n2. Concentric annulus, body-fitted O-grid")

ri, ro = 2.0e-3, 6.0e-3
bore = Ball((0.0, 0.0), ri)
wall = Ball((0.0, 0.0), ro)
# Only the outer wall is tagged, so the bore is adiabatic by omission.
ann = ogrid_cross_section(bore, wall; n_angular=48, n_radial=12,
                          boundaries=(wall => :wall,))
ann_mesh = extrude(ann, [0.0, 1.0]; axial=false)
show(stdout, MIME"text/plain"(), ann_mesh)
println()

power = 800.0
T_ann = solve_conduction(ann_mesh, MAT, uniform_power(ann, 1), power, T_WALL; name=:ann)
qppp = power / sum(ann.area)
report("bore rise [K]", maximum(T_ann) - T_WALL,
       qppp / (2K) * ((ro^2 - ri^2) / 2 - ri^2 * log(ro / ri)))
@printf("  %-34s %10.2e K\n", "azimuthal spread (should be 0)",
        maximum(T_ann[1:48]) - minimum(T_ann[1:48]))

# ---------------------------------------------------------------------------------------
# 3. Solid cylinder, cut cells. No bore, so the O-grid's ring topology does not apply and
#    the cut-cell mesher covers it. Analytic: T_centre - T_wall = q''' R^2 / 4k.
# ---------------------------------------------------------------------------------------
println("\n3. Solid cylinder, cut-cell mesh")

R = 6.0e-3
disc = Ball((0.0, 0.0), R)
for h in (0.6e-3, 0.3e-3)
    cs = cut_cell_cross_section(shape(disc); dx=h, dy=h, boundaries=(disc => :wall,))
    m = extrude(cs, [0.0, 1.0]; axial=false)
    local pwr = 800.0
    T = solve_conduction(m, MAT, uniform_power(cs, 1), pwr, T_WALL;
                         name=Symbol(:disc, round(Int, 1e5h)))
    local q = pwr / sum(cs.area)
    @printf("  h = %.1f mm, %4d cells:\n", 1e3h, ncross(cs))
    report("    centre rise [K]", maximum(T) - T_WALL, q * R^2 / (4K))
    global T_disc, disc_cs = T, cs
end

# ---------------------------------------------------------------------------------------
# 4. Square rod with a central bore, on both meshes. No closed form here, so the two
#    generators are compared against each other. This is the case where two-point flux is
#    not exact on either mesh, and the gap between them is the honest measure of it.
# ---------------------------------------------------------------------------------------
println("\n4. Bored square rod, both meshes")

w, rb = 12.0e-3, 3.0e-3
outer_box = Box((-w/2, -w/2), (w/2, w/2))
rod_bore = Ball((0.0, 0.0), rb)
rod_domain = shape(outer_box) - rod_bore
rod_tags = (rod_bore => :bore, outer_box => :wall)

rod_og = ogrid_cross_section(rod_bore, outer_box; n_angular=48, n_radial=8,
                             boundaries=rod_tags)
rod_cut = cut_cell_cross_section(rod_domain; dx=0.4e-3, dy=0.4e-3, boundaries=rod_tags)

power = 2.0e3
results = Dict{Symbol,Any}()
for (label, cs) in ((:ogrid, rod_og), (:cutcell, rod_cut))
    m = extrude(cs, [0.0, 1.0]; axial=false)
    sk = mesh_skew(cs)
    pe = linear_patch_error(cs)
    T = solve_conduction(m, MAT, uniform_power(cs, 1), power, T_WALL; name=label)
    results[label] = (; cs, T)
    @printf("  %-8s %4d cells  skew mean %4.1f°  patch p95 %7.2e  peak rise %8.4f K\n",
            label, ncross(cs), sk.mean, pe.p95, maximum(T) - T_WALL)
end
og_peak = maximum(results[:ogrid].T) - T_WALL
cut_peak = maximum(results[:cutcell].T) - T_WALL
@printf("  %-34s %10.2f %%\n", "peak disagreement between meshes",
        100 * abs(og_peak - cut_peak) / cut_peak)

# ---------------------------------------------------------------------------------------
# Figures. `meshheatmap(cs, values)` shades each cell by a per-cell number; pass the domain
# as a third argument to draw the region's true edge over the top, which is what a cut-cell
# mesh needs since its cells are background rectangles.
# ---------------------------------------------------------------------------------------
if PLOTTING
    println("\nwriting figures to ", OUT)

    p1 = meshheatmap(plate, T_plate; title="1. plate, T [°C]", size=(700, 260))
    png(p1, joinpath(OUT, "1_plate.png"))

    p2 = meshheatmap(ann, T_ann, shape(wall) - bore;
                     title="2. annulus, T [°C]", size=(600, 540))
    png(p2, joinpath(OUT, "2_annulus.png"))

    p3 = meshheatmap(disc_cs, T_disc, shape(disc);
                     title="3. solid cylinder, cut cells, T [°C]", size=(600, 540))
    png(p3, joinpath(OUT, "3_cylinder.png"))

    for (label, r) in results
        p = meshheatmap(r.cs, r.T, rod_domain;
                        title="4. bored rod, $label, T [°C]", size=(600, 540))
        png(p, joinpath(OUT, "4_rod_$label.png"))
        pm = plot(r.cs, rod_domain; title="4. bored rod, $label, mesh", size=(600, 540))
        png(pm, joinpath(OUT, "4_rod_$(label)_mesh.png"))
    end
end

println("\ndone")
