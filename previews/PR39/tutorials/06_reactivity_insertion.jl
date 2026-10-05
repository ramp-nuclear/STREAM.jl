using STREAM
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, ChannelAndContacts, PointKinetics
using STREAM.Assemblies: inseries, symmetric_plate, temperature_feedback
using STREAM.Utilities: cosine_shape
using ModelingToolkit: @named, mtkcompile
using OrdinaryDiffEq: BrownFullBasicInit

L, n, nx = 0.6, 20, 4
P_rated = 2.5e4                                       # plate power [W]
geometry = PipeGeometry_rectangular(L, 0.067, 0.0024, 0.063)
shape = repeat(cosine_shape(range(0.0, L; length=n + 1), 1.4) ./ nx, 1, nx)

function unit_cell(; power)
    @named fuel = HeatDiffusion(; nz=n, nx, Lz=L, Lx=0.00127, y=0.063, rho_s=2700.0,
                                cp_s=900.0, k_s=180.0, power, power_shape=shape)
    @named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
    @named cell = symmetric_plate(ch, fuel)
    @named pump = Pump(; ṁ0=0.4)
    @named hx = HeatExchanger(40.0)
    return cell, pump, hx, [inseries(pump, hx, cell.ch, pump), pump.outlet.p ~ 1.7e5]
end;

cell, pump, hx, connections = unit_cell(; power=P_rated)
@named loop = assembly(connections, cell, pump, hx)
sys0 = mtkcompile(loop)
sol0 = solve_steady(sys0)
T_fuel0 = [sol0[sys0.cell.fuel.T[i, j]] for i in 1:n, j in 1:nx]
T_cool0 = sol0[sys0.cell.ch.T]
extrema(T_fuel0)

ρ_step = 0.001
insertion(t) = t < 1.0 ? 0.0 : ρ_step;

cell, pump, hx, connections = unit_cell(; power=nothing)
fuel, ch = cell.fuel, cell.ch
α_fuel = fill(-1.5e-4 / (n * nx), n, nx)
α_cool = fill(-1.0e-4 / n, n)
@named pk = PointKinetics(insertion;
    temp_worth=Dict(fuel => α_fuel, ch => α_cool),
    ref_temp=Dict(fuel => T_fuel0, ch => T_cool0));

connections = [
    connections,
    fuel.power ~ pk.P * P_rated,
    temperature_feedback(pk, [fuel, ch]),
]
@named reactor = assembly(connections, cell, pump, hx, pk)
sys = mtkcompile(reactor);

op = [sys.cell.ch.T => T_cool0, sys.cell.fuel.T => T_fuel0]
times = [0.0; 0.01:0.02:4.99; 5.0:1.0:600.0]
sol = solve_transient(sys, op, times; initializealg=BrownFullBasicInit(), tstops=[1.0])
sol.retcode

using CairoMakie
fig = Figure(size=(700, 560))
ax1 = Axis(fig[1, 1]; xscale=log10, ylabel="power / rated")
ax2 = Axis(fig[2, 1]; xscale=log10, xlabel="time [s]", ylabel="reactivity [pcm]")
linkxaxes!(ax1, ax2)
later = sol.t .> 0.5                     # a log axis cannot show t = 0
lines!(ax1, sol.t[later], sol[sys.pk.P, :][later])
lines!(ax2, sol.t[later], 1e5 .* sol[sys.pk.reactivity, :][later]; label="net")
lines!(ax2, sol.t[later], 1e5 .* insertion.(sol.t[later]); label="inserted", linestyle=:dash)
axislegend(ax2; position=:rb)
fig

ρ_end = sol[sys.pk.reactivity, end]
@assert abs(ρ_end) < 1e-2 * ρ_step
ρ_end

ΔT_fuel = sum(sol[sys.cell.fuel.T[i, j], end] - T_fuel0[i, j] for i in 1:n, j in 1:nx) / (n * nx)
ΔT_cool = sum(sol[sys.cell.ch.T[i], end] - T_cool0[i] for i in 1:n) / n
@assert isapprox(-1.5e-4 * ΔT_fuel - 1.0e-4 * ΔT_cool, ρ_end - ρ_step; rtol=1e-6)
(ΔT_fuel, ΔT_cool, sol[sys.pk.P, end])
