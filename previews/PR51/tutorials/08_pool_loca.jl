using STREAM
using STREAM.Components: Tank, Environment, Orifice, Pump, ChannelHeatFlux, Gravity,
                         ResistorFromKnownPoint, StateMachine, machine_callbacks, trip!,
                         reset!
using STREAM.Assemblies: inseries, weighted
using STREAM.LocalLoss: discharge_cd
using ModelingToolkit: @named, @parameters, connect, mtkcompile, unknowns
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS

z_core_top, z_core_bottom = 1.6, 1.0      # the core, from the pool floor [m]
z_return = 5.0                            # where the return line enters the pool [m]
z_pipe = -4.8                             # the basement pipe, and the break in it [m]
z_tank_floor = -5.0                       # the decay tank's floor [m]
tank_inlet, tank_suction = 0.5, 0.2       # decay tank nozzles, from its floor [m]

L_pool, A_pool = 6.0, 8.0                 # pool level [m] and surface area [m²]
A_tank = 4.0                              # decay tank surface area [m²]
T_pool = 35.0                             # [°C]
nothing #hide

@named pool = Tank(; area=A_pool, L0=L_pool, ports=(core=z_core_top, ret=z_return),
                   T0=T_pool)
@named dtank = Tank(; area=A_tank, L0=2.0, ports=(inlet=tank_inlet, suction=tank_suction),
                    T0=T_pool, fixed_temperature=false)
nothing #hide

N = 400
P_rated = 2.0e6                           # [W]
geometry = Duct(0.6, Rectangular(0.067, 0.0024); heated=0.063)
n = 10
@parameters P_core = P_rated
q_wall = P_core / N / (2 * geometry.heated.left * geometry.L)   # each face [W/m²]
@named ch = ChannelHeatFlux(; n, geometry, g=-G_EARTH)
core = weighted(N, ch; name=:core)
nothing #hide

ṁ_design = 50.0
@named down = Gravity(z_pipe - z_core_bottom)
@named down_loss = ResistorFromKnownPoint(; dp=-6.6e4, ṁ=ṁ_design, T=45.0)
@named tank_line = ResistorFromKnownPoint(; dp=-2.0e4, ṁ=ṁ_design, T=45.0)
@named tank_rise = Gravity((z_tank_floor + tank_inlet) - z_pipe)
@named pump = Pump(1.2e5)
@named lift = Gravity(z_return - (z_tank_floor + tank_suction))
@named return_line = ResistorFromKnownPoint(; dp=-3.0e4, ṁ=ṁ_design, T=45.0)
nothing #hide

isolation = StateMachine(; initial_state=:OPEN, initial_time=-100.0)
@named return_valve = Orifice(; area=0.03, cd=0.9, machine=isolation, open_rate=0.2)
@named tank_valve = Orifice(; area=0.03, cd=0.9, machine=isolation, open_rate=0.2)
nothing #hide

hole = StateMachine(; initial_state=:SHUT)
@named breach = Orifice(; area=0.03, cd=discharge_cd(:sharp), machine=hole, open_rate=1.0,
                        dp_linear=1e-3)
@named room = Environment(; T=T_pool)
nothing #hide

connections = [
    inseries(pool.core, core..., down, down_loss),
    connect(down_loss.outlet, tank_line.inlet, breach.inlet),
    inseries(tank_line, tank_rise, tank_valve, dtank.inlet),
    inseries(dtank.suction, pump, lift, return_line, return_valve, pool.ret),
    inseries(breach, room.port),
    ch.q_left .~ q_wall,
    ch.q_right .~ q_wall,
]
@named plant = assembly(connections, pool, dtank, core..., down, down_loss, tank_line,
                        tank_rise, tank_valve, pump, lift, return_line, return_valve, breach,
                        room)
sys = mtkcompile(plant)
foreach(println, unknowns(sys))

flows = filter(u -> occursin("ṁ", string(u)), unknowns(sys))
op = [[f => ṁ_design for f in flows]; sys.dtank.pinned => false]
sol_ss = solve_steady(sys, op; solver=DynamicSS(Rodas5P()), abstol=1e-10, reltol=1e-10)
sol_ss.retcode

(level=sol_ss[sys.dtank.L], inflow=sol_ss[sys.tank_line.inlet.ṁ],
 pumped=sol_ss[sys.pump.inlet.ṁ])

@assert isapprox(sol_ss[sys.tank_line.inlet.ṁ], sol_ss[sys.pump.inlet.ṁ]; rtol=1e-6)
@assert tank_inlet < sol_ss[sys.dtank.L] < 4.0

ṁ_core = N * sol_ss[sys.ch.inlet.ṁ]
T_out = sol_ss[sys.ch.T_out]
@assert isapprox(sol_ss[sys.dtank.T], T_out; atol=1e-6)
@assert isapprox(P_rated, ṁ_core * cₚ(H2O, (T_pool + T_out) / 2) * (T_out - T_pool);
                 rtol=1e-3)
(decay_tank=sol_ss[sys.dtank.T], core_outlet=T_out)

push!(isolation, (:OPEN => :SHUT, pool.L < L_pool - 0.2, "low pool level"))
push!(isolation, (:OPEN => :SHUT, dtank.L < 1.0, "low decay tank level"))
watch = StateMachine(; initial_state=:COVERED, abort_states=(:UNCOVERED,))
push!(watch, (:COVERED => :UNCOVERED, pool.L < z_core_top, "core uncovered"))
trip!(hole, 0.0; state=:OPEN, cause="pipe break")
nothing #hide

times = range(0.0, 1000.0; length=2001)
overrides = [sys.pool.pinned => false, sys.dtank.pinned => false, P_core => 0.04P_rated]
tolerances = (abstol=1e-8, reltol=1e-8)
sol = solve_transient(sys, sol_ss, times; overrides, tolerances...,
                      callbacks=machine_callbacks(sys, hole, isolation, watch))
isolation.log

watch.log

t_isolated = isolation.t_state
using CairoMakie
fig = Figure(size=(850, 650))
ax1 = Axis(fig[1, 1]; ylabel="level [m]")
lines!(ax1, sol.t, sol[sys.pool.L]; label="pool")
lines!(ax1, sol.t, sol[sys.dtank.L]; label="decay tank")
hlines!(ax1, [z_core_top]; color=:gray, linestyle=:dash, label="top of the core")
Legend(fig[1, 2], ax1; framevisible=false)
ax2 = Axis(fig[2, 1]; xlabel="time after the break [s]", ylabel="mass flow [kg/s]")
lines!(ax2, sol.t, sol[sys.breach.inlet.ṁ]; label="out of the break")
lines!(ax2, sol.t, N .* sol[sys.ch.inlet.ṁ]; label="down through the core")
lines!(ax2, sol.t, -sol[sys.tank_line.inlet.ṁ]; label="back out of the decay tank")
lines!(ax2, sol.t, sol[sys.pump.inlet.ṁ]; label="pumped to the pool")
Legend(fig[2, 2], ax2; framevisible=false)
for ax in (ax1, ax2)
    vlines!(ax, [t_isolated]; color=:black, linewidth=1)
end
linkxaxes!(ax1, ax2)
fig

spilled = [0.0; cumsum((sol[sys.breach.inlet.ṁ][1:end-1] .+ sol[sys.breach.inlet.ṁ][2:end])
                       ./ 2 .* diff(sol.t))]
inventory = sol[sys.pool.M] .+ sol[sys.dtank.M]
@assert maximum(abs.(inventory .+ spilled .- inventory[1])) < 1e-4 * inventory[1]
(start=inventory[1], spilled=spilled[end], left=inventory[end])

extrema(sol[sys.dtank.T])

reset!.((hole, isolation, watch))
trip!(hole, 0.0; state=:OPEN, cause="pipe break")
small = solve_transient(sys, sol_ss, times; overrides=[overrides; sys.breach.area => 0.004],
                        tolerances..., callbacks=machine_callbacks(sys, hole, isolation, watch))
isolation.log

fig = Figure(size=(700, 600))
ax1 = Axis(fig[1, 1]; ylabel="into the decay tank [kg/s]")
lines!(ax1, sol.t, sol[sys.tank_line.inlet.ṁ]; label="severed pipe, 300 cm²")
lines!(ax1, small.t, small[sys.tank_line.inlet.ṁ]; label="small break, 40 cm²")
hlines!(ax1, [0.0]; color=:gray, linewidth=1)
axislegend(ax1; position=:rt)
ax2 = Axis(fig[2, 1]; xlabel="time after the break [s]", ylabel="pool level [m]")
lines!(ax2, sol.t, sol[sys.pool.L])
lines!(ax2, small.t, small[sys.pool.L])
linkxaxes!(ax1, ax2)
fig

isolated_small = isolation.t_state
before = small.t .< isolated_small
@assert all(small[sys.tank_line.inlet.ṁ][before] .> 0)
@assert isolation.log[end].cause == "low pool level"
@assert watch.state === :COVERED
@assert minimum(sol[sys.tank_line.inlet.ṁ]) < 0
