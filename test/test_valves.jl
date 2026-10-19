using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using Statistics
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Substances
using STREAM.LocalLoss

# A closed flapper blocks all flow, so it sits in PARALLEL with a bypass resistor that
# carries the loop flow while the valve is shut.
function _flapper_parallel_loop(; flapper, pump, name)
    @named bypass = Resistor(1.0e5)
    @named hx = HeatExchanger(26.85)
    conns = [
        inparallel(pump, (bypass, flapper), hx),
        inseries(hx, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    return assembly(conns, pump, bypass, flapper, hx; name=name), bypass
end

@testset "Flapper closed admits no flow" begin
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; f=1.0, area=1.0, open_rate=1.0, liquid=Liquid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_closed)
    ssys = mtkcompile(sys)
    # A fresh machine stays :CLOSED, so the valve never opens.
    sol = solve_transient(ssys, range(0.0, 5.0; length=20))
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.inlet.ṁ, end], 0.0; atol=1e-8)   # closed ⇒ no flow
    @test isapprox(sol[ssys.flapper.xi, end], 0.0; atol=1e-8)
    @test sol[ssys.bypass.inlet.ṁ, end] > 0                          # bypass carries it
end

@testset "Flapper open is a quadratic resistor" begin
    f, area, rho = 1.0, 1.0, 1.0
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; f=f, area=area, open_rate=10.0,
                             machine=StateMachine(; initial_state=:OPEN), liquid=Liquid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_open)
    ssys = mtkcompile(sys)
    # The machine starts :OPEN at t = 0, and the run goes past the 1/open_rate ramp.
    sol = solve_transient(ssys, range(0.0, 1.0; length=20))
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)             # fully open
    mf = sol[ssys.flapper.inlet.ṁ, end]
    dp = sol[ssys.flapper.inlet.p - ssys.flapper.outlet.p, end]
    @test mf > 0
    @test isapprox(dp, f * mf * abs(mf) / (2 * rho * area^2); rtol=1e-6)  # quadratic law
end

@testset "Flapper closes along the curve it opened on" begin
    opening(machine) = STREAM.Components._Opening(machine, :OPEN, 2.0)   # 0.5 s each way

    # Fully open, then shut: closing retraces the opening in time.
    full = StateMachine(; initial_state=:CLOSED)
    trip!(full, 1.0; state=:OPEN)
    trip!(full, 2.0; state=:CLOSED)
    @test opening(full)(1.5) == 1.0
    @test opening(full)(2.0) == 1.0
    @test opening(full)(2.25) ≈ opening(full)(1.25)
    @test opening(full)(2.5) == 0.0

    # Shut part way through opening: no jump at the close, and shut again in the time it
    # took to get there.
    partial = StateMachine(; initial_state=:CLOSED)
    trip!(partial, 1.0; state=:OPEN)
    reached = opening(partial)(1.2)
    trip!(partial, 1.2; state=:CLOSED)
    @test opening(partial)(1.2) ≈ reached
    @test 0.0 < opening(partial)(1.3) < reached
    @test opening(partial)(1.4) == 0.0

    # Several transitions at one instant leave zero-length log entries, which add nothing.
    bounced = StateMachine(; initial_state=:CLOSED)
    trip!(bounced, 1.0; state=:OPEN)
    trip!(bounced, 1.0; state=:CLOSED)
    trip!(bounced, 1.0; state=:OPEN)
    @test opening(bounced)(1.25) ≈ opening(full)(1.25)
end

@testset "Flapper shuts when its machine leaves the open state" begin
    # This loop has no dynamics, so the solver takes the whole run in one step and the close
    # at 0.5 s is found by looking back inside it.
    machine = StateMachine(; initial_state=:OPEN)
    push!(machine, (:OPEN => :CLOSED, t > 0.5, "close at 0.5 s"))
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; open_rate=10.0, machine=machine, liquid=Liquid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_shuts)
    ssys = mtkcompile(sys)
    sol = solve_transient(ssys, range(0.0, 1.0; length=101);
                          callbacks=machine_callbacks(ssys, machine))
    @test sol.retcode == ReturnCode.Success
    @test machine.log[end].cause == "close at 0.5 s"
    @test machine.t_state ≈ 0.5
    xi = sol[ssys.flapper.xi, :]
    ṁ = sol[ssys.flapper.inlet.ṁ, :]
    @test all(xi[0.1 .<= sol.t .<= 0.5] .≈ 1.0)       # open until the close
    @test all(0.0 .< xi[0.5 .< sol.t .< 0.6] .< 1.0)  # closing over 1/open_rate
    @test all(xi[sol.t .> 0.6] .== 0.0)               # shut after it
    @test all(ṁ[sol.t .> 0.6] .== 0.0)
end

@testset "Flapper opens where the flow it watches crosses the threshold" begin
    # A weak (large-f) flapper in parallel with a resistor branch. The pump holds the flow at
    # 1 kg/s through the resistor, then shuts off, and the flow coasts down as exp(-t/5), so
    # it crosses a threshold ṁ₀ at 5·ln(1/ṁ₀). The threshold is a parameter of the model, so
    # a second threshold needs no recompile, only a reset of the latched machine.
    @parameters ṁ_open_at = 0.01
    @named pump = Pump(1.0e5)
    @named ine = Inertia(5.0e5)
    @named res = Resistor(1.0e5)
    machine = StateMachine(; initial_state=:CLOSED)
    @named flapper = Flapper(; f=1.0e6, area=1.0, open_rate=1.0 / 3.0, machine=machine,
                             liquid=Liquid())
    push!(machine, (:CLOSED => :OPEN, ine.inlet.ṁ < ṁ_open_at))
    @named hx = HeatExchanger(26.85)
    conns = [
        inseries(pump, ine),
        inparallel(ine, (res, flapper), hx),
        inseries(hx, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    sys = assembly(conns, pump, ine, res, flapper, hx;
                   parameters=[ṁ_open_at], name=:flap_param)
    ssys = mtkcompile(sys)
    sol_ss = solve_steady(ssys)
    coast(threshold) = solve_transient(
        ssys, sol_ss, range(0.0, 30.0; length=301);
        overrides=[ssys.pump.dP_pump => 0.0, ṁ_open_at => threshold],
        callbacks=machine_callbacks(ssys, machine),
    )
    sol = coast(0.01)
    @test machine.state === :OPEN
    @test machine.t_state ≈ 5.0 * log(1 / 0.01) rtol = 0.1
    @test sol[ssys.flapper.xi, end] ≈ 1.0 atol = 1e-6   # the ramp completes
    coast(0.05)   # a latched machine never opens twice, so this run changes nothing
    @test machine.t_state ≈ 5.0 * log(1 / 0.01) rtol = 0.1
    reset!(machine)
    coast(0.05)
    @test machine.t_state ≈ 5.0 * log(1 / 0.05) rtol = 0.1
end

@testset "solve_transient passes user callbacks" begin
    @named pump = Pump(1.0e5)
    @named flapper = Flapper(; liquid=Liquid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_cb)
    ssys = mtkcompile(sys)
    fired = Ref(false)
    user_cb = ContinuousCallback((u, t_val, integ) -> t_val - 5.0, integ -> (fired[] = true))
    sol = solve_transient(ssys, range(0.0, 20.0; length=200); callbacks=CallbackSet(user_cb))
    @test sol.retcode == ReturnCode.Success
    @test fired[]
end

const T_POOL, A_TANK, L_POOL, A_HOLE = 30.0, 2.0, 4.0, 5e-4
const CD_SHARP = discharge_cd(:sharp)

"""An orifice between two ambients `dp` apart, compiled."""
function _orifice_between_ambients(orifice; dp=2e4)
    @named upstream = Environment(; p=ATM + dp, T=T_POOL)
    @named downstream = Environment()
    @named sys = assembly(inseries(upstream.port, orifice, downstream.port),
                          upstream, orifice, downstream)
    return mtkcompile(sys)
end

"""Saved times fine over the opening ramp, then spread over the drain."""
_opening_grid(t_end; points=300) =
    vcat(range(0.0, 4.0; length=21), range(4.0, t_end; length=points)[2:end])

"""
A pool emptying over a crest: the line leaves at 1.5 m, climbs to 5 m, where the break sits,
and falls to an outlet at -3 m. `breaker` is a level at which the break latches shut.
Returns the compiled model, the solution, the break's machine, the machine that stops the run
at uncovery, and one that moves to `:FLASHING` when the crest reaches saturation. `kwargs` go
to `solve_transient`.
"""
function _siphon(; T0=T_POOL, breaker=nothing, open_rate=10.0, kwargs...)
    z_intake, z_crest, z_outlet = 1.5, 5.0, -3.0
    @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(intake=z_intake,), T0=T0)
    line = StateMachine(; initial_state=:OPEN, initial_time=0.0)
    @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP, cc=CD_SHARP, dp_linear=1e-3,
                            open_rate=open_rate, machine=line)
    breaker === nothing ||
        push!(line, (:OPEN => :SHUT, pool.L < breaker, "siphon breaker"))
    @named climb = Gravity(z_crest - z_intake)
    @named fall = Gravity(z_outlet - z_crest)
    @named ambient = Environment(; T=T0)
    @named sys = assembly(inseries(pool.intake, climb, breach, fall, ambient.port),
                          pool, climb, breach, fall, ambient)
    watch = StateMachine(; initial_state=:INTACT, abort_states=(:UNCOVERED,))
    push!(watch, (:INTACT => :UNCOVERED, pool.L < 0.2, "uncovered"))
    throat = StateMachine(; initial_state=:LIQUID)
    push!(throat, (:LIQUID => :FLASHING, breach.subcooling < 0, "crest at saturation"))
    ssys = mtkcompile(sys)
    sol = solve_transient(ssys, solve_steady(ssys), _opening_grid(3500.0);
                          overrides=[ssys.pool.pinned => false],
                          callbacks=machine_callbacks(ssys, line, watch, throat), kwargs...)
    return ssys, sol, line, watch, throat
end

@testset "Orifice" begin
    @testset "a shut break holds back a pressure difference" begin
        @named sealed = Orifice(; area=A_HOLE, cd=CD_SHARP)
        ssys = _orifice_between_ambients(sealed; dp=2e4)
        sol = solve_transient(ssys, range(0.0, 1.0; length=11))
        @test all(iszero, sol[ssys.sealed.inlet.ṁ])
    end

    @testset "a Reynolds-dependent cd lets a break open from rest" begin
        # Lichtarowicz's cd falls to zero with the Reynolds number, so without the floor on
        # the throat Reynolds number, zero flow would solve the open orifice's law.
        @named breach = Orifice(; area=A_HOLE, cd=Re -> lichtarowicz_cd(Re, 2.0),
                                machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        ssys = _orifice_between_ambients(breach; dp=2e4)
        sol = solve_transient(ssys, range(0.0, 1.0; length=11))
        ṁ = sol[ssys.breach.inlet.ṁ]
        @test SciMLBase.successful_retcode(sol)
        @test all(isfinite, ṁ)
        # Fully open, the flow is a sizeable fraction of the ideal cd = 1 discharge.
        @test ṁ[end] > 0.5 * A_HOLE * sqrt(2 * ρ(H2O, T_POOL) * 2e4)
    end

    @testset "a latching upper break shuts as the level passes it" begin
        z_high, z_low, area = 2.5, 0.5, 5e-3
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(high=z_high, low=z_low), T0=T_POOL)
        upper = StateMachine(; initial_state=:OPEN, initial_time=0.0)
        @named high = Orifice(; area=area, cd=CD_SHARP, dp_linear=100.0, machine=upper)
        push!(upper, (:OPEN => :SHUT, pool.L < z_high, "surface below the upper break"))
        @named low = Orifice(; area=area, cd=CD_SHARP, dp_linear=100.0,
                             machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        @named ambient_high = Environment()
        @named ambient_low = Environment()
        conns = [
            inseries(pool.high, high, ambient_high.port),
            inseries(pool.low, low, ambient_low.port),
        ]
        @named sys = assembly(conns, pool, high, low, ambient_high, ambient_low)
        ssys = mtkcompile(sys)
        sol = solve_transient(ssys, solve_steady(ssys), range(0.0, 700.0; length=301);
                              overrides=[ssys.pool.pinned => false],
                              callbacks=machine_callbacks(ssys, upper))
        m_high, m_low = sol[ssys.high.inlet.ṁ], sol[ssys.low.inlet.ṁ]
        t_close = upper.t_state
        @test upper.state === :SHUT
        @test maximum(m_high[sol.t .< t_close]) > 0.1 * maximum(m_low)
        @test sol(t_close; idxs=ssys.pool.L) ≈ z_high atol = 1e-3
        @test m_high[end] ≈ 0.0 atol = 1e-9
        @test m_low[end] < 1e-4 * maximum(m_low)
        @test sol[ssys.pool.L][end] ≈ z_low atol = 1e-3
    end

    @testset "a siphon drains past its intake until a breaker shuts it" begin
        ssys, sol, _, watch = _siphon()
        level, m_break = sol[ssys.pool.L], sol[ssys.breach.inlet.ṁ]
        below = level .< 1.5
        @test any(below)
        @test minimum(m_break[below]) > 0.5 * maximum(m_break)
        @test watch.state === :UNCOVERED
        @test level[end] ≈ 0.2 atol = 1e-3

        # How far the level may still fall while a break closes at `rate`.
        function allowance(rate)
            rho = ρ(H2O, T_POOL)
            ṁ = CD_SHARP * A_HOLE * sqrt(2 * rho * rho * G_EARTH * (2.0 + 3.0))
            return 3 * ṁ / (rho * A_TANK) / rate
        end
        # The allowance is under a millimetre of a 2 m level, finer than the default reltol.
        ssys, quick, line, watch = _siphon(; breaker=2.0, open_rate=5.0, reltol=1e-6)
        @test line.state === :SHUT
        @test watch.state === :INTACT
        @test quick[ssys.pool.L][end] ≈ 2.0 atol = allowance(5.0)
        @test quick[ssys.breach.inlet.ṁ][end] ≈ 0.0 atol = 1e-9
        ssys, lazy, _, _ = _siphon(; breaker=2.0, open_rate=0.05, reltol=1e-6)
        @test lazy[ssys.pool.L][end] < quick[ssys.pool.L][end] - 1e-3
    end

    @testset "cavitation names a hot siphon's crest and passes a cold one" begin
        ssys, sol, _, _, throat = _siphon(; T0=90.0)
        crossings = Thresholds.cavitation(sol, ssys.breach)
        @test [c.site for c in crossings] == [:breach]
        @test 0.0 < crossings[1].time < sol.t[end]
        @test crossings[1].margin < 0.0
        # A transition on the subcooling finds the crossing during the run.
        @test throat.state === :FLASHING
        @test throat.t_state <= crossings[1].time

        ssys, sol, _, _, throat = _siphon(; T0=20.0)
        @test isempty(Thresholds.cavitation(sol, ssys.breach))
        @test throat.state === :LIQUID
        @test_throws ArgumentError Thresholds.cavitation(sol, ssys.pool)
    end
end

"""
A pump head that holds at `dp0` and, from `t = 0`, decays with time constant `τ`. With
`τ = Inf` it holds for good, which is what a steady solve needs: it reads the head at
`t = Inf`, where `exp(-t/τ)` is not a number.
"""
struct _Coastdown
    dp0::Float64
    τ::Float64
end
(c::_Coastdown)(t) = isinf(c.τ) ? c.dp0 : c.dp0 * exp(-t / c.τ)

"""
    _drain_pool(; break_at=:bottom, t_break=0.0, coast=Inf) -> (ssys, sol, watch)

A pool circulating through a core (`core`) and a pump, both connections at its floor, with a
break (`breach`) to the room that opens at `t_break`. With `break_at=:bottom` the break sits
between the core and the pump. With `:suction` the pool feeds the pump through a suction line
and the break draws from the pump inlet, so the core is downstream of the pump. The pump
drives 1 kg/s through the intact loop and, from `t = 0`, its head decays with time constant
`coast`. Solves the intact loop with the level pinned, then drains it to core uncovery at 1 m.
"""
function _drain_pool(; break_at=:bottom, t_break=0.0, coast=Inf)
    R_core, R_suction = 5e3, 2e3
    dp0 = break_at === :suction ? R_core + R_suction : R_core
    @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(suction=0.0, inflow=0.0), T0=T_POOL)
    @named core = Resistor(R_core)
    @named pump = Pump(_Coastdown(dp0, coast))
    @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_linear=1e-3,
                            machine=StateMachine(; initial_state=:OPEN, initial_time=t_break))
    @named ambient = Environment(; T=T_POOL)
    parts = Any[pool, core, pump, breach, ambient]
    connections = if break_at === :bottom
        [inseries(pool.suction, core), connect(core.outlet, pump.inlet, breach.inlet),
         inseries(pump, pool.inflow)]
    else
        @named suction_line = Resistor(R_suction)
        push!(parts, suction_line)
        [inseries(pool.suction, suction_line),
         connect(suction_line.outlet, pump.inlet, breach.inlet), inseries(pump, core, pool.inflow)]
    end
    @named sys = assembly([connections; inseries(breach, ambient.port)], parts...)
    watch = StateMachine(; initial_state=:INTACT, abort_states=(:UNCOVERED,))
    push!(watch, (:INTACT => :UNCOVERED, pool.L < 1.0, "core uncovered"))
    ssys = mtkcompile(sys)

    sol_ss = solve_steady(ssys, [ssys.pump.dP_pump_fn => _Coastdown(dp0, Inf)])
    # Fine over the break's opening ramp, then spread to the end.
    times = unique!(vcat(0.0, range(t_break, t_break + 4.0; length=21),
                         range(t_break + 4.0, 4000.0; length=400)[2:end]))
    sol = solve_transient(ssys, sol_ss, times;
                          overrides=[ssys.pool.pinned => false,
                                     ssys.pump.dP_pump_fn => _Coastdown(dp0, coast)],
                          callbacks=machine_callbacks(ssys, watch))
    return ssys, sol, watch
end

@testset "A break in a pumped pool" begin
    rho = ρ(H2O, T_POOL)

    @testset "a bottom break leaves the circulation alone and carries what the pool loses" begin
        ssys, sol, watch = _drain_pool()
        m_core, m_break = sol[ssys.core.inlet.ṁ], sol[ssys.breach.inlet.ṁ]
        level, inventory = sol[ssys.pool.L], sol[ssys.pool.M]
        @test watch.state === :UNCOVERED
        @test level[end] ≈ 1.0 atol = 1e-3
        @test m_core ≈ ones(length(m_core)) rtol = 1e-4
        # Non-strict: the run saves the instant it stops twice.
        @test all(diff(m_break[sol.t .> 5.0]) .<= 0.0)
        driving = rho * G_EARTH * level[end] - 5e3
        @test m_break[end] ≈ CD_SHARP * A_HOLE * sqrt(2 * rho * driving) rtol = 1e-3
        discharged = sum((m_break[i] + m_break[i + 1]) / 2 * (sol.t[i + 1] - sol.t[i])
                         for i in 1:(length(sol.t) - 1))
        @test discharged ≈ inventory[1] - inventory[end] rtol = 1e-3
    end

    @testset "a suction break reverses the core and uncovers sooner than a bottom break" begin
        t_break = 20.0
        ssys, sol, watch = _drain_pool(; break_at=:suction, t_break, coast=3.0)
        m_core = sol[ssys.core.inlet.ṁ]
        @test m_core[1] ≈ 1.0 rtol = 1e-6
        @test minimum(m_core) < 0.0
        @test sol.t[findfirst(<(0.0), m_core)] > t_break
        @test watch.state === :UNCOVERED

        _, bottom, _ = _drain_pool(; t_break)
        @test sol.t[end] < bottom.t[end]
    end
end

@testset "A loss of flow opens a bypass flapper into natural circulation" begin
    # A plate-heated leg running down (`heated`) and an unheated one running up (`ret`), fed
    # by a branch holding the pump, the heat exchanger and an inertia, with a flapper in
    # parallel. When the pump head falls the flapper opens and the two legs circulate alone.
    n, L, D, T_in, power, t_trip = 10, 1.0, 0.01, 40.0, 1.0e3, 10.0
    geom = Duct(L, Circular(D))
    # 200 kPa, falling to zero over 5 s from `t_trip` on a C1 cubic. A trip at Inf holds for
    # good and is the same closure type, so one callable parameter takes both.
    head(t_trip) = tt -> (ξ = clamp((tt - t_trip) / 5.0, 0.0, 1.0); 2.0e5 * (1 - (3ξ^2 - 2ξ^3)))
    # The heated leg switches regime on its own, so the run stays physical once the pump
    # stops.
    htc = HTC.RegimeDependent(; laminar=HTC.ConstantNusselt(; Nu=8.235),
                              turbulent=HTC.DittusBoelter())
    darcy = Friction.RegimeDependent(; turbulent=Friction.blasius)
    machine = StateMachine(; initial_state=:CLOSED)

    @named pump = Pump(head(t_trip))
    @named ine = Inertia(1.75e5)
    @named hx = HeatExchanger(T_in)
    @named ext_res = Resistor(1.0e6)
    @named ch = ChannelAndContacts(; n, geometry=geom, g=-G_EARTH, htc, darcy)
    @named ret = Channel(; n, geometry=geom, g=G_EARTH)
    @named flapper = Flapper(; machine, f=50.0, area=0.01, open_rate=1 / 5.0)
    push!(machine, (:CLOSED => :OPEN, ine.inlet.ṁ < 0.01))
    slab = Slab(; x=range(0, 0.005, 3), z=range(0, L, n + 1), y=0.07,
                material=Solid(19300.0, 116.0, 174.0))
    @named fuel = HeatDiffusion(slab; power)
    @named heated = assembly(faces((ch, :thermal_outer) => (fuel, :thermal_right)), ch, fuel)
    connections = [
        inseries(ext_res, hx, pump, ine),
        inparallel(ine, ((heated.ch, ret), flapper), ext_res),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(connections, heated, pump, ine, hx, ret, flapper, ext_res)
    ssys = mtkcompile(sys)
    C = ssys.heated.ch

    # Pump on, flapper shut, integrated to steady. The flows start from their guesses; the
    # dummy derivative has no default and needs a value.
    ss = solve_steady(ssys, [ssys.pump.dP_pump_fn => head(Inf), Differential(t)(C.inlet.ṁ) => 0.0];
                      solver=DynamicSS(Rodas5P()))
    valve_at_steady = machine.state
    # Every unknown, not a subset: a `Dt(ṁ) => 0` guess does not reach the dummy-derivative
    # state, which the latest packages would otherwise start at NaN.
    op = Pair{Any,Any}[u => ss[u] for u in unknowns(ssys)]
    push!(op, ssys.pump.dP_pump_fn => head(t_trip))
    t_arr = range(0.0, 300.0; length=3001)
    sol = solve_transient(ssys, op, t_arr; callbacks=machine_callbacks(ssys, machine))
    Q_wall(idx) = sum(sol[C.q_wall[i], idx] for i in 1:n)

    @testset "the forced-flow steady state is physical, with the flapper shut" begin
        # Reproduces across package sets to well under 1%.
        @test ss[ssys.ine.inlet.ṁ] ≈ 0.187 atol = 0.005
        @test valve_at_steady === :CLOSED
    end

    @testset "the flapper opens after the trip and ramps fully open" begin
        # The inertia branch flow decays through the threshold at about 14.5 s.
        @test sol.retcode == ReturnCode.Success
        @test machine.state === :OPEN
        @test t_trip < machine.t_state < 300.0
        @test sol[ssys.flapper.xi, end] ≈ 1.0 atol = 1e-4
    end

    @testset "the coolant stores part of the wall heat and carries the rest away" begin
        # Once the flapper opens, the only heat sink is bypassed, so the coolant keeps warming
        # and there is no thermal steady state to compare with. The coolant stores enthalpy at
        # a positive rate below the wall heat it absorbs, which is what conservation leaves.
        # From t = 100 s, past the startup swing, the wall passes no more than the plate makes.
        @test maximum(abs(Q_wall(idx)) for idx in 1001:3001) <= power
        nc = 2001:3000   # t = 200..300 s, natural circulation established
        @test minimum(Q_wall(idx) for idx in nc) > 0
        v_cell = π * (D / 2)^2 * L / n
        store(idx) = sum(ρ(H2O, sol[C.T[i], idx]) * cₚ(H2O, sol[C.T[i], idx]) * v_cell *
                         (sol[C.T[i], idx + 1] - sol[C.T[i], idx - 1]) /
                         (t_arr[idx + 1] - t_arr[idx - 1]) for i in 1:n)
        ratio = mean(store, nc) / mean(abs ∘ Q_wall, nc)
        # Not analytically forced: a regression value, 0.499 on both package sets, the band
        # its per-sample spread.
        @test 0.49 < ratio < 0.51
    end

    @testset "the natural-circulation flow balances buoyancy against friction" begin
        # Around heated -> ret -> flapper -> heated the pressure differences telescope, so at
        # equilibrium friction balances the buoyancy head, with both read off the solved cell
        # temperatures and the friction each leg applies. The flapper's open drop (~0.005 Pa
        # against ~14 Pa) and the idle pump branch do not reach the balance. At Re ~ 4800 the
        # heated leg blends laminar and turbulent at f ~ 0.036, against Blasius's 0.038, which
        # is worth 1.5% in ṁ. The model lands on the root to 0.03%.
        nc = 2701:3001
        dz = L / n
        T_ch = [mean(sol[C.T[i], nc]) for i in 1:n]
        T_ret = [mean(sol[ssys.ret.T[i], nc]) for i in 1:n]
        dP_buoy = sum(G_EARTH * dz * (ρ(H2O, T_ret[i]) - ρ(H2O, T_ch[i])) for i in 1:n)
        leg(T, f, md) = Friction.darcy_weisbach_dp(md, ρ(H2O, T), f(T, T, md, H2O, geom), dz,
                                                   hydraulic_diameter(geom), flow_area(geom))
        dP_fric(md) = sum(leg(T_ch[i], darcy, md) + leg(T_ret[i], Friction.Blasius(), md)
                          for i in 1:n)
        lo, hi = 1.0e-6, 1.0   # bisect in log space
        for _ in 1:200
            mid = sqrt(lo * hi)
            dP_fric(mid) < dP_buoy ? (lo = mid) : (hi = mid)
        end
        ṁ_nc = sol[C.inlet.ṁ, nc]

        @test dP_buoy > 0.0   # the cooler return leg is the denser one
        @test mean(abs, ṁ_nc) ≈ sqrt(lo * hi) rtol = 0.02
        # Reversed against the forced flow.
        @test sol[C.inlet.ṁ, 1] > 0.0
        @test mean(ṁ_nc) < 0.0
        @test 0.0 < mean(abs ∘ Q_wall, nc) <= power
        # Single phase only, with the sink bypassed, so the coolant creeps up past saturation.
        # No thermal runaway: a regression value of 233.6 °C, the band the spread between
        # package sets, and well below the critical 373.95 °C.
        T_max = mean(maximum(sol[C.T, idx]) for idx in nc)
        @test T_max > T_in
        @test 231.85 < T_max < 236.85
    end
end
