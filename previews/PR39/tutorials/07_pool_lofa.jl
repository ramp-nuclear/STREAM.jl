using STREAM
using STREAM.Components: Pump, Inertia, ResistorFromKnownPoint, HeatExchanger, Channel,
                         ChannelAndContacts, HeatDiffusion, Flapper, PointKinetics,
                         ReactivityController, StateMachine, machine_callbacks,
                         U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
using STREAM.Assemblies: inseries, inparallel, weighted, symmetric_plate
using STREAM.Thresholds
using STREAM.Utilities: cosine_shape
using ModelingToolkit: @named, mtkcompile
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS

case = (
    L=0.6, n=6, nx=2,                                  # heated length [m], axial and lateral cells
    rho_s=2700.0, cp_s=900.0, k_s=180.0,               # plate properties
    T_pool=35.0, p_pool=1.7e5,                         # pool temperature [°C], pressure at the core top [Pa]
    P_rated=2.0e6,                                     # rated power [W]
    dP_pump=3.9e4,                                     # pump head [Pa]
    flywheel_L_over_A=2.5e4,                           # flywheel inertia [1/m]
    primary_dp=3.0e4,                                  # primary piping drop at design flow [Pa]
    riser_L=0.6, riser_D=0.3,                          # riser height and diameter [m]
    flapper_open_at=1.5, flapper_f=1.0,                # primary flow that opens the flapper [kg/s]
    flapper_area=0.03, flapper_open_time=2.0,          # and its open loss, area [m²], opening time [s]
    trip_fraction=0.85,                                # low-flow trip, fraction of design flow
    types=(
        high=(N=40, width=0.066, gap=0.0027, heated_width=0.063, plate_thickness=0.00127,
              ppf=1.4, power_fraction=0.9, orifice_dp=2.0e3, design_ṁ=0.356),
        low=(N=10, width=0.066, gap=0.0027, heated_width=0.063, plate_thickness=0.00127,
             ppf=1.3, power_fraction=0.1, orifice_dp=7.9e3, design_ṁ=0.1),
    ),
);

rod(τ) = -0.06 * clamp((τ - 0.1) / 0.5, 0.0, 1.0)
ctrl = ReactivityController((state, t_state, t) -> state === :SCRAM ? rod(t - t_state) : 0.0;
                            machine=StateMachine());

heat = DecayHeat.U238CaptureChain(0.5) +
       DecayHeat.FissionProducts([1.0, 0.05, 1e-3, 1e-5], [3.0, 0.15, 3e-3, 3e-5])
source = DecayHeat.DecayHeatSource(heat, ctrl; P0=1.0)
source(0.0)

@named pk = PointKinetics(ctrl; power_input=source);

z_edges = range(0.0, case.L; length=case.n + 1)
core_parts = []
paths = []
channels = Dict{Symbol,Any}()
power_eqs = []
for (key, ty) in pairs(case.types)
    geom = PipeGeometry_rectangular(case.L, ty.width, ty.gap, ty.heated_width)
    htc = HTC.SubcooledBoiling(
        HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(),
                            natural=HTC.Elenbaas(geom), geom),
        HTC.regime_dependent_q_scb(),
    )
    darcy = Friction.RegimeDependent(; turbulent=Friction.blasius,
                                     k_R=Friction.rectangular_correction(geom.depth / geom.width))
    @named ch = ChannelAndContacts(; n=case.n, geometry=geom, g=-G_EARTH, htc, darcy)
    @named fuel = HeatDiffusion(; nz=case.n, nx=case.nx, Lz=case.L, Lx=ty.plate_thickness,
                                y=ty.heated_width, rho_s=case.rho_s, cp_s=case.cp_s, k_s=case.k_s,
                                power_shape=repeat(cosine_shape(z_edges, ty.ppf) ./ case.nx, 1, case.nx),
                                T0=case.T_pool)
    rods = symmetric_plate(ch, fuel; name=key)
    pool = HeatExchanger(case.T_pool; name=Symbol(:pool_, key))
    orifice = ResistorFromKnownPoint(; name=Symbol(:orifice_, key), dp=-ty.orifice_dp,
                                     ṁ=ty.design_ṁ, T=case.T_pool)
    path = weighted(ty.N, pool, orifice, rods.ch; name=key)
    append!(core_parts, [first(path), pool, orifice, rods, last(path)])
    push!(paths, path)
    channels[key] = (rods.ch, geom)
    push!(power_eqs, rods.fuel.power ~ pk.P * case.P_rated * ty.power_fraction / ty.N)
end

ṁ_design = sum(ty.N * ty.design_ṁ for ty in case.types)
@named pump = Pump(case.dP_pump)
@named flywheel = Inertia(case.flywheel_L_over_A)
@named primary = ResistorFromKnownPoint(; dp=-case.primary_dp, ṁ=ṁ_design, T=case.T_pool)
@named riser = Channel(; n=case.n, geometry=PipeGeometry_circular(case.riser_L, case.riser_D),
                       g=G_EARTH)
@named pool_flapper = HeatExchanger(case.T_pool);

valve = StateMachine(; initial_state=:CLOSED)
@named flapper = Flapper(; machine=valve, f=case.flapper_f, area=case.flapper_area,
                         open_rate=1 / case.flapper_open_time)
valve.transitions = [(:CLOSED => :OPEN, flywheel.inlet.ṁ < case.flapper_open_at,
                      "primary flow below the flapper setpoint")];

push!(ctrl.machine, (:NORMAL => :SCRAM, flywheel.inlet.ṁ < case.trip_fraction * ṁ_design,
                     "low primary flow"))

connections = [
    inparallel(flywheel, paths, riser),
    inparallel(flywheel, [(pool_flapper, flapper)], primary),
    inseries(riser, primary, pump, flywheel),
    flywheel.outlet.p ~ case.p_pool,
    power_eqs,
]
@named plant = assembly(connections, pk, pump, flywheel, primary, riser, pool_flapper, flapper,
                        core_parts...)
sys = mtkcompile(plant)
ch_high, ch_low = (getproperty(sys, key).ch for key in keys(case.types));

guess = [sys.primary.inlet.ṁ => ṁ_design,
         ch_high.inlet.ṁ => case.types.high.design_ṁ,
         ch_low.inlet.ṁ => case.types.low.design_ṁ]
sol_ss = solve_steady(sys, guess; solver=DynamicSS(Rodas5P()), abstol=1e-10, reltol=1e-10)
sol_ss.retcode

@assert isapprox(sol_ss[ch_high.inlet.ṁ], case.types.high.design_ṁ; rtol=0.02)
@assert isapprox(sol_ss[ch_low.inlet.ṁ], case.types.low.design_ṁ; rtol=0.02)
@assert isapprox(sol_ss[sys.pk.P], 1.0; rtol=1e-9)
@assert isapprox(sol_ss[sys.pk.P_neutron], 1.0 - source(0.0); rtol=1e-9)
(high=sol_ss[ch_high.inlet.ṁ], low=sol_ss[ch_low.inlet.ṁ])

times = range(0.0, 1200.0; length=601)
sol = solve_transient(sys, sol_ss, times; overrides=[sys.pump.dP_pump => 0.0],
                      callbacks=machine_callbacks(sys, ctrl.machine, valve), tstops=times)
sol.retcode

ctrl.machine.log

valve.log

@assert ctrl.machine.state === :SCRAM && ctrl.machine.log[end].cause == "low primary flow"
@assert valve.state === :OPEN && valve.t_state > ctrl.machine.t_state

using CairoMakie
t_scram, t_open = ctrl.machine.t_state, valve.t_state
fig = Figure(size=(760, 600))
ax1 = Axis(fig[1, 1]; xscale=log10, ylabel="flow per channel [kg/s]")
ax2 = Axis(fig[2, 1]; xscale=log10, xlabel="time after the pump trip [s]",
           ylabel="primary flow [kg/s]")
later = sol.t .> 0
for (key, ch) in (:high => ch_high, :low => ch_low)
    lines!(ax1, sol.t[later], sol[ch.inlet.ṁ, :][later]; label=string(key))
end
hlines!(ax1, [0.0]; color=:black, linewidth=0.5)
lines!(ax2, sol.t[later], sol[sys.flywheel.inlet.ṁ, :][later]; label="primary")
lines!(ax2, sol.t[later], sol[sys.flapper.inlet.ṁ, :][later]; label="through the flapper")
for ax in (ax1, ax2)
    vlines!(ax, [t_scram, t_open]; color=:gray, linestyle=:dash)
end
axislegend(ax1; position=:lb); axislegend(ax2; position=:lb)
fig

for (key, ch) in (:high => ch_high, :low => ch_low)
    @assert sol[ch.inlet.ṁ, 1] > 0 && sol[ch.inlet.ṁ, end] < 0
end

fig = Figure(size=(760, 600))
ax1 = Axis(fig[1, 1]; xscale=log10, yscale=log10, ylabel="power / rated")
lines!(ax1, sol.t[later], sol[sys.pk.P, :][later]; label="total")
lines!(ax1, sol.t[later], max.(sol[sys.pk.P_neutron, :][later], 1e-6); label="fission")
lines!(ax1, sol.t[later], source.(sol.t[later]); label="decay heat", linestyle=:dash)
axislegend(ax1; position=:lb)
ax2 = Axis(fig[2, 1]; xscale=log10, xlabel="time after the pump trip [s]",
           ylabel="hottest temperature [°C]")
for (key, ch) in (:high => ch_high, :low => ch_low)
    fuel = getproperty(sys, key).fuel
    T_fuel = [maximum(sol[fuel.T[i, j], k] for i in 1:case.n, j in 1:case.nx) for k in eachindex(sol.t)]
    T_cool = [maximum(sol[ch.T[i], k] for i in 1:case.n) for k in eachindex(sol.t)]
    lines!(ax2, sol.t[later], T_fuel[later]; label="$(key) fuel")
    lines!(ax2, sol.t[later], T_cool[later]; label="$(key) coolant", linestyle=:dash)
end
axislegend(ax2; position=:lt)
fig

@assert sol[sys.pk.P_neutron, end] < 1e-6
@assert isapprox(sol[sys.pk.P, end], source(times[end]); rtol=1e-4)

cp = cₚ(H2O, case.T_pool)
Q_pool = sum(case.types[key].N * abs(sol[ch.inlet.ṁ, end]) * cp * (sol[ch.T[1], end] - case.T_pool)
             for (key, ch) in (:high => ch_high, :low => ch_low))
@assert isapprox(Q_pool, sol[sys.pk.P, end] * case.P_rated; rtol=0.05)
(Q_pool, sol[sys.pk.P, end] * case.P_rated)

fig = Figure(size=(760, 600))
ax1 = Axis(fig[1, 1]; xscale=log10, ylabel=L"min $T_\mathrm{ONB} - T_w$ [K]")
ax2 = Axis(fig[2, 1]; xscale=log10, yscale=log10, xlabel="time after the pump trip [s]",
           ylabel="min CHF ratio, Sudo-Kaminaga")
for (key, (ch, geom)) in channels
    chsys = getproperty(sys, key).ch
    m = threshold_analysis(sol, chsys; pipe=geom,
                           onb = s -> bergles_rohsenow_t_onb(s) .- s.T_wall,
                           chfr = chfr(q_CHF_sudo_kaminaga))
    lines!(ax1, sol.t[later], vec(minimum(m.onb; dims=1))[later]; label=string(key))
    lines!(ax2, sol.t[later], vec(minimum(m.chfr; dims=1))[later]; label=string(key))
    w = worst_case(m.chfr; times=sol.t)
    println(rpad(key, 5), " worst CHF ratio ", round(w.value; sigdigits=3),
            " at t = ", round(w.time; digits=1), " s, cell ", w.cell)
end
for ax in (ax1, ax2)
    vlines!(ax, [t_scram, t_open]; color=:gray, linestyle=:dash)
end
axislegend(ax1; position=:lb)
fig
