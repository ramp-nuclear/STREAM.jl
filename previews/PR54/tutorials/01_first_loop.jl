using STREAM
using STREAM.Components: Pump, HeatExchanger, Channel
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile, unknowns, equations

@named pump = Pump(3.0e4);

@named hx = HeatExchanger(40.0);

geometry = PipeGeometry_circular(0.6, 0.01)
@named ch = Channel(; n=10, geometry, h_left=5000.0);

connections = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.T_wall_left .~ 100.0,
];

@named loop = assembly(connections, pump, hx, ch)
length(equations(loop))

sys = mtkcompile(loop)
foreach(println, unknowns(sys))

sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5]);

ṁ = sol[sys.ch.inlet.ṁ]

T_out = sol[sys.ch.T_out]

using CairoMakie
z = ((1:10) .- 0.5) .* 0.6 ./ 10
fig = Figure(size=(600, 350))
ax = Axis(fig[1, 1]; xlabel="distance along the pipe [m]", ylabel="water temperature [°C]")
scatterlines!(ax, z, sol[sys.ch.T])
fig

Q_wall = sum(sol[sys.ch.q_wall])

T_in = 40.0
Q_flow = ṁ * cₚ(H2O, (T_in + T_out) / 2) * (T_out - T_in)
@assert isapprox(Q_wall, Q_flow; rtol=1e-6);

sol2 = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5, sys.pump.dP_pump => 4.0e4])
ṁ2 = sol2[sys.ch.inlet.ṁ]

@assert isapprox(ṁ2 / ṁ, (4 / 3)^(1 / 1.75); rtol=5e-3)
(ṁ2 / ṁ, (4 / 3)^(1 / 1.75))
