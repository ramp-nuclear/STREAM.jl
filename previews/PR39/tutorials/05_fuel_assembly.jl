using STREAM
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, ChannelAndContacts
using STREAM.Assemblies: inseries, inparallel, fuel_assembly
using STREAM.Utilities: cosine_shape
using ModelingToolkit: @named, mtkcompile, unknowns
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS

n_plates = 7
n_channels = n_plates + 1
n = 12                         # axial cells
L = 0.604                      # heated length [m]
gap = 0.0021                   # channel gap [m]
heated_width = 0.063           # width of the fuel meat [m]
thickness = 0.00127            # plate thickness [m]
P_plate = 15.0e6 / (24 * 7)    # 15 MW over a core of 24 assemblies of 7 plates [W]
T_in = 35.0                    # inlet temperature [°C]
p_out = 1.67e5                 # pressure at the channel outlets, under the pool [Pa]
dp_pump = 1.0e5                # pump head [Pa]

geometry = PipeGeometry_rectangular(L, 0.0666, gap, heated_width)

n_clad, n_meat = 1, 3
nx = n_meat + 2n_clad
z_edges = range(0.0, L; length=n + 1)
shape = zeros(n, nx)
shape[:, n_clad+1:n_clad+n_meat] .= cosine_shape(z_edges, π / 2) ./ n_meat
plates = [HeatDiffusion(; name=Symbol(:p, j), nz=n, nx, Lz=L, Lx=thickness, y=heated_width,
                        rho_s=2700.0, cp_s=900.0, k_s=180.0, power=P_plate,
                        power_shape=shape)
          for j in 1:n_plates];

channels = [ChannelAndContacts(; name=Symbol(:c, i), n, geometry, g=-G_EARTH)
            for i in 1:n_channels];

@named asm = fuel_assembly(channels, plates);

channel(i) = getproperty(asm, Symbol(:c, i))
@named pump = Pump(dp_pump)
@named hx = HeatExchanger(T_in)
connections = [
    inseries(pump, hx),
    inparallel(hx, [channel(i) for i in 1:n_channels], pump),
    pump.inlet.p ~ p_out,
]
@named loop = assembly(connections, pump, hx, asm)
sys = mtkcompile(loop)
length(unknowns(sys))

flows = filter(u -> occursin("ṁ", string(u)), unknowns(sys))
foreach(println, flows)

guess = [ṁ => 1.0 for ṁ in flows]
sol = solve_steady(sys, guess; solver=DynamicSS(Rodas5P()), abstol=1e-8, reltol=1e-8)
sol.retcode

C(i) = getproperty(sys.asm, Symbol(:c, i))
Pl(j) = getproperty(sys.asm, Symbol(:p, j))
Q = sum(sol[C(i).Q_wall_total] for i in 1:n_channels)
@assert isapprox(Q, n_plates * P_plate; rtol=1e-6)
Q

@assert all(isapprox(sol[C(i).T_out], sol[C(n_channels + 1 - i).T_out]; rtol=1e-6)
            for i in 1:n_channels)
[round(sol[C(i).inlet.ṁ]; digits=3) for i in 1:n_channels]

using CairoMakie
zc = (z_edges[1:end-1] .+ z_edges[2:end]) ./ 2
fig = Figure(size=(650, 400))
ax = Axis(fig[1, 1]; xlabel="distance from the inlet [m]", ylabel="coolant temperature [°C]")
for i in 1:n_channels÷2
    lines!(ax, zc, sol[C(i).T]; label="channel $i")
end
axislegend(ax; position=:lt)
fig

centre = n_clad + (n_meat + 1) ÷ 2
fig = Figure(size=(650, 400))
ax = Axis(fig[1, 1]; xlabel="distance from the inlet [m]",
          ylabel="plate centre temperature [°C]")
for j in 1:(n_plates+1)÷2
    lines!(ax, zc, [sol[Pl(j).T[k, centre]] for k in 1:n]; label="plate $j")
end
axislegend(ax; position=:lt)
fig

x_edges = [0.0]
columns = Vector{Vector{Float64}}()
for i in 1:n_channels
    push!(x_edges, x_edges[end] + gap)
    push!(columns, sol[C(i).T])
    i <= n_plates || continue
    for m in 1:nx
        push!(x_edges, x_edges[end] + thickness / nx)
        push!(columns, [sol[Pl(i).T[k, m]] for k in 1:n])
    end
end
fig = Figure(size=(650, 500))
ax = Axis(fig[1, 1]; xlabel="across the assembly [mm]", ylabel="distance from the inlet [m]")
hm = heatmap!(ax, 1000 .* x_edges, collect(z_edges), reduce(hcat, columns)'; colormap=:hot)
Colorbar(fig[1, 2], hm; label="temperature [°C]")
fig

T_max = [maximum(sol[Pl(j).T[k, m]] for k in 1:n, m in 1:nx) for j in 1:n_plates]
fig = Figure(size=(650, 350))
ax = Axis(fig[1, 1]; xlabel="plate", ylabel="hottest point [°C]", xticks=1:n_plates)
scatter!(ax, 1:n_plates, T_max; markersize=14)
fig

@assert all(all(sol[C(i).T_wall_right] .< sol[C(i).T_sat]) for i in 1:n_plates)
@assert all(all(sol[C(i).T_wall_left] .< sol[C(i).T_sat]) for i in 2:n_channels)
(hottest_wall=maximum(maximum(sol[C(i).T_wall_right]) for i in 1:n_plates),
 lowest_saturation=minimum(minimum(sol[C(i).T_sat]) for i in 1:n_channels))
