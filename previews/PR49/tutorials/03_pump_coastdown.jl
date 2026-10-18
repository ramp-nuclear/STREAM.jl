using STREAM
using STREAM.Components: Pump, Inertia, ResistorFromKnownPoint, HeatExchanger
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile, unknowns

dp0, ṁ0, L_over_A = 3.0e4, 50.0, 2.0e4      # Pa, kg/s, 1/m
@named pump = Pump(dp0)
@named flywheel = Inertia(L_over_A)
@named loss = ResistorFromKnownPoint(; dp=-dp0, ṁ=ṁ0, T=40.0)
@named hx = HeatExchanger(40.0)

connections = [inseries(pump, flywheel, loss, hx, pump), pump.inlet.p ~ 1.5e5]
@named loop = assembly(connections, pump, flywheel, loss, hx)
sys = mtkcompile(loop);

foreach(println, unknowns(sys))

sol_ss = solve_steady(sys, [sys.loss.inlet.ṁ => 40.0])
sol_ss[sys.flywheel.inlet.ṁ]

times = range(0.0, 60.0; length=301)
sol = solve_transient(sys, sol_ss, times; overrides=[sys.pump.dP_pump => 0.0])
sol.retcode

k = dp0 / ṁ0^2
α = k / L_over_A
ṁ_exact(t) = ṁ0 / (1 + ṁ0 * α * t)
ṁ_sim = sol[sys.flywheel.inlet.ṁ, :]
@assert maximum(abs.(ṁ_sim .- ṁ_exact.(sol.t)) ./ ṁ_exact.(sol.t)) < 1e-4
maximum(abs.(ṁ_sim .- ṁ_exact.(sol.t)) ./ ṁ_exact.(sol.t))

using CairoMakie
fig = Figure(size=(650, 380))
ax = Axis(fig[1, 1]; xlabel="time after the trip [s]", ylabel="mass flow [kg/s]")
lines!(ax, sol.t, ṁ_exact.(sol.t); label="exact", linewidth=4, color=(:gray, 0.5))
lines!(ax, sol.t, ṁ_sim; label="STREAM")
axislegend(ax)
fig

dp_loss = sol[sys.loss.inlet.p - sys.loss.outlet.p, :]
dp_flywheel = sol[sys.flywheel.outlet.p - sys.flywheel.inlet.p, :]
@assert maximum(abs.(dp_loss .- dp_flywheel)) < 1e-6 * dp0

fig_dp = Figure(size=(650, 560))
ax_dp = Axis(fig_dp[1, 1]; ylabel="pressure difference [bar]")
lines!(ax_dp, sol.t, dp_loss ./ 1e5; label="drop across the loss", linewidth=4,
       color=(:gray, 0.5))
lines!(ax_dp, sol.t, dp_flywheel ./ 1e5; label="rise across the flywheel")
axislegend(ax_dp)
ax_err = Axis(fig_dp[2, 1]; xlabel="time after the trip [s]",
              ylabel="error in the flow [%]")
lines!(ax_err, sol.t, 100 .* (ṁ_sim .- ṁ_exact.(sol.t)) ./ ṁ_exact.(sol.t))
linkxaxes!(ax_dp, ax_err)
fig_dp

τ = 5.0
head(t) = dp0 * exp(-t / τ)
@named pump2 = Pump(head)
@named flywheel2 = Inertia(L_over_A)
@named loss2 = ResistorFromKnownPoint(; dp=-dp0, ṁ=ṁ0, T=40.0)
@named hx2 = HeatExchanger(40.0)
connections2 = [inseries(pump2, flywheel2, loss2, hx2, pump2), pump2.inlet.p ~ 1.5e5]
@named loop2 = assembly(connections2, pump2, flywheel2, loss2, hx2)
sys2 = mtkcompile(loop2);

sol2 = solve_transient(sys2, [sys2.loss2.inlet.ṁ => ṁ0, sys2.pump2.dP_pump_fn => head], times)
sol2.retcode

lines!(ax, sol2.t, sol2[sys2.flywheel2.inlet.ṁ, :]; label="pump coasting down, τ = 5 s")
axislegend(ax)
fig
