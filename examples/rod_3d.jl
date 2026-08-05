# examples/rod_3d.jl
#
# Usage:
#   julia --project examples/rod_3d.jl
#
# A square fuel rod with a central bore, cooled by five channels at known flow: one on each
# flat and one down the bore. Shows how a three-dimensional power distribution is built and
# what the coupled solution looks like, layer by layer.
#
# The three things this demonstrates, in order:
#
#   1. `power_shape` is an (nlayers, ncross) matrix, so the source varies axially and
#      in-plane independently. Here it is an axial cosine times a radial profile.
#   2. Each boundary tag becomes one thermal port per axial layer, so the five channels are
#      five independent thermal paths rather than one averaged surface.
#   3. The solution is genuinely 3D: heat moves azimuthally between channels and axially
#      along the rod, and starving one channel shows both.
#
# Plotting is optional; without Plots the script prints every number and skips the figures.

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
    @info "Plots not installed, printing numbers only."
    false
end

const OUT = joinpath(@__DIR__, "rod_3d_output")
PLOTTING && mkpath(OUT)

# ---------------------------------------------------------------------------------------
# Geometry. A 12 mm square with a 3 mm bore, meshed body-fitted so cells follow both the
# bore and the flats. Each flat is tagged separately by a thin box laid along it, which is
# what splits the outer wall into four independently cooled surfaces.
# ---------------------------------------------------------------------------------------
w, r_bore, L = 12.0e-3, 3.0e-3, 0.6
nz, n_ang, n_rad = 10, 32, 4

outer = Box((-w/2, -w/2), (w/2, w/2))
bore = Ball((0.0, 0.0), r_bore)
lip = w / 60
tagged = (
    bore => :bore,
    Box((-w/2, w/2 - lip), (w/2, w/2 + lip)) => :north,
    Box((w/2 - lip, -w/2), (w/2 + lip, w/2)) => :east,
    Box((-w/2, -w/2 - lip), (w/2, -w/2 + lip)) => :south,
    Box((-w/2 - lip, -w/2), (-w/2 + lip, w/2)) => :west,
)
cross = ogrid_cross_section(bore, outer; n_angular=n_ang, n_radial=n_rad, boundaries=tagged)

# Axial spacing is independent of the cross-section, and `axial=true` puts conduction
# between the layers. Without it the layers would be thermally independent.
mesh = extrude(cross, [(i - 1) * L / nz for i in 1:(nz + 1)]; axial=true)
show(stdout, MIME"text/plain"(), mesh)
println()

# ---------------------------------------------------------------------------------------
# 1. A three-dimensional power distribution.
#
# `power_shape[iz, ic]` is cell (iz, ic)'s share of the total, and the shares sum to one.
# Axial and in-plane profiles are separate and multiply, so any pair composes. Here:
# a cosine along the rod, and in-plane a profile that puts more power near the bore, as a
# hollow pellet with a flux depression toward the outside would.
# ---------------------------------------------------------------------------------------
axial = [cos(π * ((i - 0.5) / nz - 0.5)) for i in 1:nz]
axial ./= sum(axial)

radius(ic) = hypot(cross.centroid[ic]...)
r_in, r_out = extrema(radius.(1:ncross(cross)))
inplane = [cross.area[ic] * (1.4 - 0.4 * (radius(ic) - r_in) / (r_out - r_in))
           for ic in 1:ncross(cross)]
inplane ./= sum(inplane)

power_shape = [axial[iz] * inplane[ic] for iz in 1:nz, ic in 1:ncross(cross)]
@printf("\npower_shape %dx%d, sums to %.10f\n", size(power_shape)..., sum(power_shape))
@printf("  axial peak/end ratio        %.3f\n", maximum(axial) / axial[1])
@printf("  in-plane inner/outer ratio  %.3f\n",
        maximum(inplane ./ cross.area) / minimum(inplane ./ cross.area))

# ---------------------------------------------------------------------------------------
# 2. The rod, and five channels at known flow.
#
# `faces` connects a channel's thermal face to a solid tag index by index, one connection
# per axial layer. `adiabatic_face` closes the channel's other face, which carries no
# heated perimeter and so has no equation of its own.
# ---------------------------------------------------------------------------------------
POWER = 2.0e4
T_IN = 40.0
MDOT = (0.05, 0.05, 0.05, 0.05, 0.05)      # north, east, south, west, bore

function build(mdot)
    @named rod = HeatDiffusion(mesh; materials=[SolidMaterial(19300.0, 116.0, 174.0)],
                               power_shape=power_shape, power=POWER)

    side_geom = PipeGeometry_rectangular(L, w, 2.0e-3, w; one_sided=:left)
    bore_geom = PipeGeometry_circular(L, 2 * r_bore)
    order = (:north, :east, :south, :west, :bore)

    chans = [ChannelAndContacts(; name=Symbol(:ch_, s), n=nz,
                                geometry=(s === :bore ? bore_geom : side_geom),
                                htc=HTC.DittusBoelter(),
                                darcy=(s === :bore ? Friction.Blasius() :
                                       Friction.RectangularLaminar(side_geom)))
             for s in order]
    pumps = [Pump(; name=Symbol(:pump_, s), ṁ0=ṁ) for (s, ṁ) in zip(order, mdot)]
    hxs = [HeatExchanger(T_IN; name=Symbol(:hx_, s)) for s in order]

    conns = Equation[]
    for (ch, s) in zip(chans, order)
        append!(conns, faces((ch, :thermal_left) => (rod, Symbol(:thermal_, s))))
        append!(conns, adiabatic_face(ch, :thermal_right))
    end
    for (ch, pu, hx) in zip(chans, pumps, hxs)
        append!(conns, inseries(pu, ch, hx, pu))
        push!(conns, pu.inlet.p ~ ATM)
    end
    push!(conns, rod.power ~ POWER)
    return compose(System(conns, t; name=:rod3d), rod, chans..., pumps..., hxs...)
end

function run(mdot, label)
    @printf("\nsolving (%s) ...\n", label)
    ssys = mtkcompile(build(mdot))
    guess = vcat(
        [ssys.rod.T[i, j] => 60.0 for i in 1:nz for j in 1:ncross(cross)],
        [getproperty(ssys, Symbol(:ch_, s)).T[i] => 45.0
         for s in (:north, :east, :south, :west, :bore) for i in 1:nz],
    )
    println("  system compiled, ", length(equations(ssys)), " equations")
    sol = solve_steady(ssys, guess)
    T = [sol[ssys.rod.T[i, j]] for i in 1:nz, j in 1:ncross(cross)]
    duty = Dict(s => sol[getproperty(ssys, Symbol(:ch_, s)).Q_wall_total]
                for s in (:north, :east, :south, :west, :bore))
    Tout = Dict(s => sol[getproperty(ssys, Symbol(:ch_, s)).T[nz]]
                for s in (:north, :east, :south, :west, :bore))
    return (; T, duty, Tout)
end

even = run(MDOT, "all channels at 0.05 kg/s")

@printf("  deposited %.1f W, removed %.1f W, closure %.2e\n",
        POWER, sum(values(even.duty)), abs(sum(values(even.duty)) - POWER) / POWER)
println("  channel        duty [W]   T_out [C]")
for s in (:north, :east, :south, :west, :bore)
    @printf("    %-6s %11.1f %10.2f\n", s, even.duty[s], even.Tout[s])
end

println("\n  axial profile of the solid:")
println("    layer   power [W]   T_max [C]   T_mean [C]")
for iz in 1:nz
    @printf("    %3d %11.1f %11.2f %11.2f\n", iz, POWER * sum(power_shape[iz, :]),
            maximum(even.T[iz, :]), sum(even.T[iz, :]) / ncross(cross))
end

# ---------------------------------------------------------------------------------------
# 3. Starve the north channel. Its neighbours have to pick up the load, which they can only
#    do by conducting around the rod, and the axial profile shifts because heat also moves
#    along it. This is the check that the five tags are five independent paths.
# ---------------------------------------------------------------------------------------
starved = run((0.004, 0.05, 0.05, 0.05, 0.05), "north starved to 0.004 kg/s")

println("  channel      duty even    duty starved     change")
for s in (:north, :east, :south, :west, :bore)
    @printf("    %-6s %11.1f %14.1f %10.1f%%\n", s, even.duty[s], starved.duty[s],
            100 * (starved.duty[s] - even.duty[s]) / even.duty[s])
end
@printf("  peak solid temperature  %.2f C -> %.2f C\n",
        maximum(even.T), maximum(starved.T))

if PLOTTING
    println("\nwriting figures to ", OUT)
    dom = shape(outer) - bore
    lims = extrema(vcat(vec(even.T), vec(starved.T)))

    # Cross-sections at the inlet, the axial peak, and the outlet.
    for iz in (1, nz ÷ 2, nz)
        p = meshheatmap(cross, even.T[iz, :], dom; clims=lims,
                        title=@sprintf("layer %d of %d, z = %.2f m", iz, nz, (iz-0.5)*L/nz),
                        size=(560, 500))
        png(p, joinpath(OUT, @sprintf("even_layer%02d.png", iz)))
    end

    p = meshheatmap(cross, starved.T[nz ÷ 2, :], dom; clims=lims,
                    title="north starved, mid-plane", size=(560, 500))
    png(p, joinpath(OUT, "starved_midplane.png"))

    # Axial view: peak and mean solid temperature, and each channel's bulk temperature.
    z = [(i - 0.5) * L / nz for i in 1:nz]
    p = plot(z, [maximum(even.T[i, :]) for i in 1:nz]; label="solid peak",
             lw=2, xlabel="z [m]", ylabel="T [°C]", title="axial profiles", size=(640, 440))
    plot!(p, z, [sum(even.T[i, :]) / ncross(cross) for i in 1:nz]; label="solid mean", lw=2)
    plot!(p, z, [maximum(starved.T[i, :]) for i in 1:nz]; label="solid peak, north starved",
          lw=2, ls=:dash)
    png(p, joinpath(OUT, "axial_profiles.png"))
end

println("\ndone")
