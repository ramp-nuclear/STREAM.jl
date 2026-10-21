using STREAM
using STREAM.Components: Tank, Pump, Inertia, HeatExchanger, ChannelHeatFlux, Gravity,
                         ResistorFromKnownPoint
using STREAM.Assemblies: inseries, weighted
using ModelingToolkit: @named, @parameters, mtkcompile
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS

z_core_top, z_core_bottom = 1.6, 1.0      # the core, from the pool floor [m]
z_return = 5.0                            # where the return line enters the pool [m]
L_pool, A_pool = 6.0, 8.0                 # pool level [m] and surface area [m²]
@named pool = Tank(; area=A_pool, L0=L_pool, ports=(core=z_core_top, ret=z_return),
                   T0=40.0, fixed_temperature=false)
nothing #hide

N = 400
P_rated = 2.0e6                           # [W]
geometry = Duct(0.6, Rectangular(0.067, 0.0024); heated=0.063)
@parameters P_core = P_rated
q_wall = P_core / N / (2 * geometry.heated.left * geometry.L)   # each face [W/m²]
@named ch = ChannelHeatFlux(; n=10, geometry, g=-G_EARTH)
core = weighted(N, ch; name=:core)
nothing #hide

ṁ_primary = 50.0
@named pump = Pump(5.0e4)
@named lift = Gravity(z_return - z_core_bottom)
@named return_line = ResistorFromKnownPoint(; dp=-4.0e4, ṁ=ṁ_primary, T=45.0)
nothing #hide

UA = 1.2e5                                # [W/K]
@named hx = HeatExchanger(; UA, arrangement=HTC.Counterflow())
nothing #hide

ṁ_secondary = 60.0
T_tower = 25.0
@named spump = Pump(1.0e5)
@named flywheel = Inertia(1.7e4)
@named tower = HeatExchanger(T_tower)
@named sec_loss = ResistorFromKnownPoint(; dp=-1.0e5, ṁ=ṁ_secondary, T=30.0)
nothing #hide

function build_plant(hx)
    connections = [
        inseries(pool.core, core..., pump, hx.primary, lift, return_line, pool.ret),
        inseries(spump, flywheel, hx.secondary, tower, sec_loss, spump),
        spump.inlet.p ~ 2.0e5,
        ch.q_left .~ q_wall,
        ch.q_right .~ q_wall,
    ]
    @named plant = assembly(connections, pool, core..., pump, hx, lift, return_line, spump,
                            flywheel, tower, sec_loss)
    return mtkcompile(plant)
end
sys = build_plant(hx)
nothing #hide

op = [sys.ch.inlet.ṁ => ṁ_primary / N, sys.flywheel.inlet.ṁ => ṁ_secondary]
steady = (solver=DynamicSS(Rodas5P()), abstol=1e-10, reltol=1e-10)
sol_ss = solve_steady(sys, op; steady...)
sol_ss.retcode

Q_ss = sol_ss[sys.hx.Q]
@assert isapprox(Q_ss, -P_rated; rtol=1e-3)
(Q=Q_ss, pool=sol_ss[sys.pool.T], primary_flow=sol_ss[sys.hx.primary.inlet.ṁ],
 secondary_flow=sol_ss[sys.hx.secondary.inlet.ṁ])

C_p, C_s = sol_ss[sys.hx.primary.C], sol_ss[sys.hx.secondary.C]
C_min, C_max = minmax(C_p, C_s)
ε = HTC.effectiveness(HTC.Counterflow(), UA / C_min, C_min / C_max)
T_pool_hand = T_tower + P_rated / (ε * C_min) - P_rated / C_p
@assert isapprox(sol_ss[sys.pool.T], T_pool_hand; atol=0.1)
(effectiveness=ε, by_hand=T_pool_hand, solved=sol_ss[sys.pool.T])

@named hx = HeatExchanger(; UA, arrangement=HTC.ParallelFlow())
sys_parallel = build_plant(hx)
sol_parallel = solve_steady(sys_parallel, op; steady...)
@assert sol_parallel[sys_parallel.pool.T] > sol_ss[sys.pool.T]
(counterflow=sol_ss[sys.pool.T], parallel=sol_parallel[sys_parallel.pool.T])

times = range(0.0, 1800.0; length=901)
overrides = [sys.spump.dP_pump => 0.0, sys.pool.pinned => false]
sol = solve_transient(sys, sol_ss, times; overrides)
sol.retcode

using CairoMakie
fig = Figure(size=(750, 700))
ax1 = Axis(fig[1, 1]; ylabel="secondary flow [kg/s]", xscale=Makie.pseudolog10,
           xticks=[0, 1, 10, 100, 1000])
lines!(ax1, sol.t, sol[sys.hx.secondary.inlet.ṁ])
ax2 = Axis(fig[2, 1]; ylabel="heat removed [MW]", xscale=Makie.pseudolog10,
           xticks=[0, 1, 10, 100, 1000])
lines!(ax2, sol.t, -sol[sys.hx.Q] ./ 1e6)
ax3 = Axis(fig[3, 1]; ylabel="pool [°C]", xlabel="time after the trip [s]",
           xscale=Makie.pseudolog10, xticks=[0, 1, 10, 100, 1000])
lines!(ax3, sol.t, sol[sys.pool.T])
linkxaxes!(ax1, ax2, ax3)
fig

M = sol[sys.pool.M][end]
rate_bound = P_rated / (M * cₚ(H2O, sol[sys.pool.T][end]))
i0 = findfirst(>=(1200.0), sol.t)
rate = (sol[sys.pool.T][end] - sol[sys.pool.T][i0]) / (sol.t[end] - sol.t[i0])
residual = -sol[sys.hx.Q][end] / P_rated
@assert rate < rate_bound
@assert isapprox(rate, rate_bound * (1 - residual); rtol=0.05)
(rate=rate, adiabatic=rate_bound, still_removed=residual)

ṁp_0, ṁs_0 = sol_ss[sys.hx.primary.inlet.ṁ], sol_ss[sys.hx.secondary.inlet.ṁ]
ua = HTC.flow_scaled_UA(UA, ṁp_0, ṁs_0)
@named hx = HeatExchanger(; UA=ua)
sys_scaled = build_plant(hx)
sol_ss_scaled = solve_steady(sys_scaled, op; steady...)
sol_scaled = solve_transient(sys_scaled, sol_ss_scaled, times;
                             overrides=[sys_scaled.spump.dP_pump => 0.0,
                                        sys_scaled.pool.pinned => false])
sol_scaled.retcode

fig = Figure(size=(750, 420))
ax = Axis(fig[1, 1]; xlabel="time after the trip [s]", ylabel="heat removed [MW]",
          xscale=Makie.pseudolog10, xticks=[0, 1, 10, 100, 1000])
lines!(ax, sol.t, -sol[sys.hx.Q] ./ 1e6; label="fixed UA")
lines!(ax, sol_scaled.t, -sol_scaled[sys_scaled.hx.Q] ./ 1e6; label="UA following the flow")
axislegend(ax)
fig

@assert isapprox(sol_ss_scaled[sys_scaled.pool.T], sol_ss[sys.pool.T]; atol=1e-3)
@assert -sol_scaled[sys_scaled.hx.Q][end] < -sol[sys.hx.Q][end]
(fixed=sol[sys.pool.T][end], scaled=sol_scaled[sys_scaled.pool.T][end])
