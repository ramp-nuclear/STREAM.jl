using STREAM
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, ChannelAndContacts
using STREAM.Assemblies: inseries, symmetric_plate
using STREAM.Thresholds
using STREAM.Utilities: cosine_shape
using ModelingToolkit: @named, mtkcompile

L = 0.6                  # heated length [m]
n = 20                   # axial cells
nx = 4                   # cells across the plate
width = 0.067            # channel width [m]
gap = 0.0024             # channel gap [m]
heated_width = 0.063     # width of the fuel meat, heated part of each face [m]
thickness = 0.00127      # plate thickness [m]
P = 2.5e4                # plate power [W]
ṁ = 0.4                  # channel flow [kg/s]
T_in, p_in = 40.0, 1.7e5 # inlet temperature [°C] and pressure [Pa]

geometry = PipeGeometry_rectangular(L, width, gap, heated_width)

z_edges = range(0.0, L; length=n + 1)
shape = repeat(cosine_shape(z_edges, 1.4) ./ nx, 1, nx)
@named fuel = HeatDiffusion(; nz=n, nx, Lz=L, Lx=thickness, y=heated_width,
                            rho_s=2700.0, cp_s=900.0, k_s=180.0, power=P, power_shape=shape);

@named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH);

@named cell = symmetric_plate(ch, fuel);

@named pump = Pump(; ṁ0=ṁ)
@named hx = HeatExchanger(T_in)
connections = [inseries(pump, hx, cell.ch, pump), pump.outlet.p ~ p_in]
@named loop = assembly(connections, pump, hx, cell)
sys = mtkcompile(loop)
sol = solve_steady(sys)
sol.retcode

T_out = sol[sys.cell.ch.T_out]
@assert isapprox(P, ṁ * cₚ(H2O, (T_in + T_out) / 2) * (T_out - T_in); rtol=1e-3)
T_out

using CairoMakie
zc = (z_edges[1:end-1] .+ z_edges[2:end]) ./ 2
T_centre = [maximum(sol[sys.cell.fuel.T[i, j]] for j in 1:nx) for i in 1:n]
fig = Figure(size=(650, 400))
ax = Axis(fig[1, 1]; xlabel="distance from the inlet [m]", ylabel="temperature [°C]")
lines!(ax, zc, T_centre; label="plate centre")
lines!(ax, zc, sol[sys.cell.ch.T_wall_left]; label="wall")
lines!(ax, zc, sol[sys.cell.ch.T]; label="coolant")
lines!(ax, zc, sol[sys.cell.ch.T_sat]; label="saturation", linestyle=:dash)
axislegend(ax; position=:lt)
fig

T_plate = [sol[sys.cell.fuel.T[i, j]] for i in 1:n, j in 1:nx]
fig_map = Figure(size=(450, 500))
ax_map = Axis(fig_map[1, 1]; xlabel="across the plate [mm]",
              ylabel="distance from the inlet [m]")
hm = heatmap!(ax_map, range(0, 1000 * thickness; length=nx + 1), z_edges, T_plate';
              colormap=:jet)
Colorbar(fig_map[1, 2], hm; label="temperature [°C]")
fig_map

margins = threshold_analysis(sol, sys.cell.ch; pipe=geometry,
    onb = s -> bergles_rohsenow_t_onb(s) .- s.T_wall,
    osv = s -> q_OSV_saha_zuber(s) ./ s.q_flux,
    ofi = s -> q_OFI_whittle_forgan(s) / P,
    chf_mirshak = chfr(q_CHF_mirshak),
    chf_sudo_kaminaga = chfr(q_CHF_sudo_kaminaga),
)
margins.ofi

for key in (:onb, :osv, :chf_mirshak, :chf_sudo_kaminaga)
    w = worst_case(margins[key])
    println(rpad(key, 18), round(w.value; sigdigits=3), " at cell ", w.cell)
end
