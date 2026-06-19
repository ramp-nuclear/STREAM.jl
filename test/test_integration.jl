# Integration tests — a strict 1:1 port of Python STREAM's
# tests/test_general/test_integrations.py.
#
# Every testset below mirrors exactly one Python integration test (same system, same
# parameters, same analytic assertion) and nothing else lives here: Julia-only builder,
# solver, channel, and point-kinetics tests live in the files that mirror their source
# (test_examples.jl, test_solvers.jl, test_channels.jl, test_point_kinetics.jl).

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using OrdinaryDiffEq: ReturnCode
using STREAM
using STREAM: Channel, ChannelAndContacts, Pump, HeatExchanger, ConstantTemperature,
    PipeGeometry, PipeGeometry_circular, HeatDiffusion, ConstantFluid, PointKinetics,
    ReactivityController, connect_temperature_feedback, compose_systems, symmetric_plate,
    one_sided_connection, constant_Nusselt, point_kinetics_steady_state, port,
    solve_steady, solve_transient

# ============================================================================
# Python `tests/test_general/test_integrations.py` 1:1 ports.
#
# Each testset below mirrors one Python integration test: the same system with
# the same numeric parameters, asserting the same closed-form analytic solution.
# Where Python queries flows off its Kirchhoff/Junction graph, the same quantity
# is read through MTK port variables ("same system, queried through MTK").
# ============================================================================

@testset "pump + resistor in series follows analytic solution" begin
    # Python: test_pump_resistor_in_series_follows_analytic_solution
    # Ideal pump (dp) and ideal resistor (r): mdot = dp/r, resistor drops dp, T uniform.
    T = 300.0
    dp = 3.0e4
    r = 1.5e5
    @named pump = Pump(dp)
    @named hx = HeatExchanger(T)          # anchors the loop temperature (Python's Tin)
    @named R = Resistor(r)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, R.port_in),
        connect(R.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:pr_series), pump, hx, R)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.R.port_in.mdot => dp / r])
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.R.port_in.mdot], dp / r; rtol=1e-8)              # mdot = dp/r
    @test isapprox(sol[ssys.R.port_in.P] - sol[ssys.R.port_out.P], dp; rtol=1e-8)  # ΔP_R = dp
    @test isapprox(sol[ssys.R.port_in.T], T; rtol=1e-8)                      # Tin = T
end

@testset "parallel resistors with pump against analytic solution" begin
    # Python: test_parallel_resistors_with_pump_against_analytic_solution
    # Two resistors in parallel: total flow = p / (r1·r2/(r1+r2)) = p·(r1+r2)/(r1·r2).
    p = 2.0e4
    r1 = 1.0e5
    r2 = 3.0e5
    @named pump = Pump(p)
    @named hx = HeatExchanger(300.0)
    @named R1 = Resistor(r1)
    @named R2 = Resistor(r2)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, R1.port_in, R2.port_in),     # node J0
        connect(R1.port_out, R2.port_out, pump.port_in),  # node J1
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:par_res), pump, hx, R1, R2)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.R1.port_in.mdot => p / r1, ssys.R2.port_in.mdot => p / r2])
    @test sol.retcode == ReturnCode.Success
    total_R = (r1 * r2) / (r1 + r2)
    total_flow = sol[ssys.pump.port_out.mdot]
    @test isapprox(abs(total_flow), p / total_R; rtol=1e-8)
    @test isapprox(sol[ssys.R1.port_in.mdot], p / r1; rtol=1e-8)   # each branch drops p
    @test isapprox(sol[ssys.R2.port_in.mdot], p / r2; rtol=1e-8)
end

@testset "resistors in series against analytic solution" begin
    # Python: test_resistors_in_series_against_analytic_solution
    # N equal resistors (each total_r/N) in series carry the full flow; each drops p/N.
    N = 5
    pressure = 4.0e4
    total_r = 2.0e5
    r = total_r / N
    @named pump = Pump(pressure)
    @named hx = HeatExchanger(300.0)
    Rs = [Resistor(r; name=Symbol(:R, i)) for i in 1:N]
    series = Equation[connect(Rs[i].port_out, Rs[i + 1].port_in) for i in 1:(N - 1)]
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, Rs[1].port_in),
        series...,
        connect(Rs[N].port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:ser_res), pump, hx, Rs...)
    ssys = mtkcompile(sys)
    mdot_guess = pressure / total_r
    sol = solve_steady(ssys, [getproperty(ssys, Symbol(:R, 1)).port_in.mdot => mdot_guess])
    @test sol.retcode == ReturnCode.Success
    for i in 1:N
        Ri = getproperty(ssys, Symbol(:R, i))
        @test isapprox(sol[Ri.port_in.mdot], pressure / total_r; rtol=1e-8)        # full flow
        @test isapprox(sol[Ri.port_in.P] - sol[Ri.port_out.P], pressure / N; rtol=1e-8)  # each drops p/N
        @test isapprox(sol[Ri.port_in.T], 300.0; rtol=1e-8)
    end
end

@testset "pump and current source" begin
    # Python: test_pump_and_current_source
    # A fixed-pressure pump and a fixed-flow pump in a loop: the current source sets mdot.
    p = 1.5e4
    mdot = 0.7
    @named P1 = Pump(p)               # fixed-pressure
    @named P2 = Pump(; mdot0=mdot)    # fixed-flow (current source)
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(P1.port_out, hx.port_in),
        connect(hx.port_out, P2.port_in),
        connect(P2.port_out, P1.port_in),
        P1.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:pump_current), P1, P2, hx)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.P2.port_in.mdot => mdot])
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.P2.port_in.mdot], mdot; rtol=1e-8)              # current source wins
    @test isapprox(sol[ssys.P1.port_out.P] - sol[ssys.P1.port_in.P], p; rtol=1e-8)  # pump adds p
end

@testset "Tin jumps at resistor between two HXs at flow reversal" begin
    # Python: test_Tin_jumps_at_resistor_between_two_hxs_at_flow_reversal
    # HX1(20) -> R -> HX2(60), pump closes the loop. Forward flow: the resistor's fluid is
    # HX1's; reversed flow (pump flipped): it is HX2's.
    T1, T2 = 20.0, 60.0
    function build(dp)
        @named pump = Pump(dp)
        @named HX1 = HeatExchanger(T1)
        @named HX2 = HeatExchanger(T2)
        @named R = Resistor(1.0)
        conns = [
            connect(pump.port_out, HX1.port_in),
            connect(HX1.port_out, R.port_in),
            connect(R.port_out, HX2.port_in),
            connect(HX2.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
        ]
        @named sys = compose(System(conns, t; name=:tinjump), pump, HX1, HX2, R)
        return mtkcompile(sys)
    end
    fwd = build(1.0)
    sol_f = solve_steady(fwd, [fwd.R.port_in.mdot => 1.0])
    @test sol_f.retcode == ReturnCode.Success
    @test sol_f[fwd.R.port_in.mdot] > 0
    @test isapprox(sol_f[fwd.R.port_out.T], T1; rtol=1e-8)   # forward: HX1 fluid through R

    rev = build(-1.0)
    sol_r = solve_steady(rev, [rev.R.port_in.mdot => -1.0])
    @test sol_r.retcode == ReturnCode.Success
    @test sol_r[rev.R.port_in.mdot] < 0
    @test isapprox(sol_r[rev.R.port_in.T], T2; rtol=1e-8)    # reversed: HX2 fluid through R
end

@testset "inertia through RL circuit follows analytic solution" begin
    # Python: test_inertia_through_RL_circuit_follows_analytic_solution
    # An inertia L and resistor r in a loop. A pump holds a steady mdot0=1, then shuts off
    # (Python drops the pump head to 0); the flow coasts as mdot = mdot0·exp(-(r/L)·t). The
    # transient starts from the solved steady state — every state transplanted, not a hand-picked
    # subset — so the initial condition stays consistent no matter which variables MTK keeps as
    # states.
    L = 5.0
    r = 3.0
    mdot0 = 1.0
    @named pump = Pump(r * mdot0)        # linear drop r·mdot ⇒ head r·mdot0 holds mdot0 at steady
    @named L_el = Inertia(L)
    @named R = Resistor(r)
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, L_el.port_in),
        connect(L_el.port_out, R.port_in),
        connect(R.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:rl_circuit), pump, L_el, R, hx)
    ssys = mtkcompile(sys)
    sol_ss = solve_steady(ssys, [ssys.L_el.port_in.mdot => mdot0])
    @test sol_ss.retcode == ReturnCode.Success
    t_arr = range(0.0, 1.0; length=5)   # exactly [0, 0.25, 0.5, 0.75, 1.0]
    sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.pump.dP_pump => 0.0],
                          reltol=1e-10, abstol=1e-12)
    @test sol.retcode == ReturnCode.Success
    mdot = sol[ssys.L_el.port_in.mdot, :]
    for (i, tt) in enumerate(t_arr)
        @test isapprox(mdot[i], mdot0 * exp(-(r / L) * tt); rtol=1e-4)   # mdot = mdot0·exp(-(r/L)·t)
    end
end

@testset "inertia with friction in PCS coastdown" begin
    # Python: test_inertia_with_friction_in_PCS_coastdown
    # Inertia + quadratic friction, pump shutdown: mdot = mdot0/(1 + α·mdot0·t),
    # α = |dp_out(mdot=1)|/inertia. Python's fixed-f Friction has dp = (dp0/mdot0²)·mdot|mdot|
    # (the density cancels), so a VolumetricFlowResistor(k=dp0/mdot0², density=1) reproduces it.
    inertia = 8.0e3
    T = 293.15
    dp0 = 1.6e5
    rho0 = rho_water(T)
    mdot0 = (2000.0 / 3600.0) * rho0
    K = dp0 / mdot0^2
    alpha = K / inertia
    @named pump = Pump(K * mdot0^2)      # = dp0; holds mdot0 through the quadratic resistor
    @named L_el = Inertia(inertia)
    @named R = VolumetricFlowResistor(; k=K, density=1.0)
    @named hx = HeatExchanger(T)
    conns = [
        connect(pump.port_out, L_el.port_in),
        connect(L_el.port_out, R.port_in),
        connect(R.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:friction_coastdown), pump, L_el, R, hx)
    ssys = mtkcompile(sys)
    # Python solves the driven steady state, then shuts the pump (p=0) and coasts from it. Mirror
    # that: solve_steady with the pump on, then start the transient from the solved state with the
    # pump head overridden to 0 (a zero-head pump is a pass-through).
    sol_ss = solve_steady(ssys, [ssys.L_el.port_in.mdot => mdot0, ssys.R.port_in.mdot => mdot0])
    @test sol_ss.retcode == ReturnCode.Success
    t_arr = range(0.0, 300.0; length=7)   # includes 0, 50, 150, 300
    sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.pump.dP_pump => 0.0],
                          reltol=1e-10, abstol=1e-12)
    @test sol.retcode == ReturnCode.Success
    mdot = sol[ssys.L_el.port_in.mdot, :]
    for (i, tt) in enumerate(t_arr)
        mdota = mdot0 / (1 + alpha * mdot0 * tt)
        @test isapprox(mdot[i], mdota; rtol=1e-4)   # mdot = mdot0/(1 + α·mdot0·t)
    end
end

@testset "inertia with two parallel resistors" begin
    # Python: test_inertia_with_two_parallel_resistors
    # Inertia + two parallel quadratic resistors: total_k = k1·k2/(√k1+√k2)²,
    # coastdown mdot = mdot0/(1 + (total_k/inertia)·mdot0·t).
    inertia = 1.0e3
    mdot0 = 1.0
    k1 = 2.0
    k2 = 5.0
    total_k = k1 * k2 / (sqrt(k1) + sqrt(k2))^2
    alpha = total_k / inertia
    @named pump = Pump(total_k * mdot0^2)   # head that holds mdot0 through the parallel block
    @named L_el = Inertia(inertia)
    @named R1 = VolumetricFlowResistor(; k=k1, density=1.0)
    @named R2 = VolumetricFlowResistor(; k=k2, density=1.0)
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, L_el.port_in),
        connect(L_el.port_out, R1.port_in, R2.port_in),   # node J0
        connect(R1.port_out, R2.port_out, hx.port_in),    # node J1
        connect(hx.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:parallel_coastdown), pump, L_el, R1, R2, hx)
    ssys = mtkcompile(sys)
    # Python solves the driven steady state, then shuts the pump (p=0) and coasts. Solve_steady
    # with the pump on (the branch guesses seed the split m1/m2 = √(k2/k1)), then start the
    # transient from the solved state with the pump head overridden to 0.
    sol_ss = solve_steady(ssys,
                          [ssys.L_el.port_in.mdot => mdot0,
                           ssys.R1.port_in.mdot => mdot0 / (1 + sqrt(k1 / k2)),
                           ssys.R2.port_in.mdot => mdot0 / (1 + sqrt(k2 / k1))])
    @test sol_ss.retcode == ReturnCode.Success
    t_arr = range(0.0, 100.0; length=6)   # includes 0, 20, 60, 100
    sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.pump.dP_pump => 0.0],
                          reltol=1e-8, abstol=1e-10)
    @test sol.retcode == ReturnCode.Success
    mdot = sol[ssys.L_el.port_in.mdot, :]
    for (i, tt) in enumerate(t_arr)
        mdota = mdot0 / (1 + alpha * mdot0 * tt)
        @test isapprox(mdot[i], mdota; rtol=1e-4)   # mdot = mdot0/(1 + (total_k/inertia)·mdot0·t)
    end
end

@testset "kirchhoff significance in two in-series resistors" begin
    # Python: test_kirchhoff_significance_in_two_in_series_resistors
    # signify=s on R1 weights its Kirchhoff edge: m2 = s·m1, m1 = p/(r1 + s·r2). MTK has no
    # mass-conserving flow-gain element, so the faithful re-expression scales the resistance:
    # an R1 of r1/s carries the bundle flow (= m2 = s·m1) with the per-copy drop r1·m1; the
    # per-copy flow m1 is then bundle/s.
    r1 = 1.0e5
    r2 = 2.0e5
    p = 3.0e4
    s = 2.5
    @named pump = Pump(p)
    @named hx = HeatExchanger(300.0)
    @named R1 = Resistor(r1 / s)     # bundle resistance (s parallel copies of r1)
    @named R2 = Resistor(r2)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, R1.port_in),
        connect(R1.port_out, R2.port_in),
        connect(R2.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:signify_series), pump, hx, R1, R2)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.R1.port_in.mdot => p / (r1 / s + r2)])
    @test sol.retcode == ReturnCode.Success
    bundle = sol[ssys.R1.port_in.mdot]      # = m2 = s·m1
    m1 = bundle / s
    m2 = sol[ssys.R2.port_in.mdot]
    @test isapprox(m1 * s, m2; rtol=1e-8)
    @test isapprox(m1, p / (r1 + s * r2); rtol=1e-8)
end

@testset "kirchhoff significance for many parallel edges" begin
    # Python: test_kirchhoff_significance_for_many_parallel_edges
    # Integer signify ≡ `signify` parallel copies of R1 — native MTK parallel topology.
    # Each copy carries m1 = p/(r1 + signify·r2); R2 carries m2 = signify·m1.
    r1 = 1.0e5
    r2 = 2.0e5
    p = 3.0e4
    signify = 3
    @named pump = Pump(p)
    @named hx = HeatExchanger(300.0)
    R1s = [Resistor(r1; name=Symbol(:R1_, i)) for i in 1:signify]
    @named R2 = Resistor(r2)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, [R1.port_in for R1 in R1s]...),     # node J0
        connect([R1.port_out for R1 in R1s]..., R2.port_in),    # node J1
        connect(R2.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:signify_parallel), pump, hx, R1s..., R2)
    ssys = mtkcompile(sys)
    m1 = p / (r1 + signify * r2)
    guess = vcat([getproperty(ssys, Symbol(:R1_, i)).port_in.mdot => m1 for i in 1:signify],
                 [ssys.R2.port_in.mdot => signify * m1])
    sol = solve_steady(ssys, guess)
    @test sol.retcode == ReturnCode.Success
    for i in 1:signify
        @test isapprox(sol[getproperty(ssys, Symbol(:R1_, i)).port_in.mdot], m1; rtol=1e-8)
    end
    @test isapprox(sol[ssys.R2.port_in.mdot], signify * m1; rtol=1e-8)
end

@testset "local pressure with flow reversal" begin
    # Python: test_local_pressure_with_flow_reversal
    # A decaying current source mdot0(t) = 3 - t drives flow through a LocalPressureDrop
    # (A1=1, A2=2). The flow tracks the source down through zero and reverses; the
    # direction-dependent loss stays finite across the reversal.
    # No inertia ⇒ mdot is algebraic (the current source forces it), so the system is
    # quasi-static: solve the steady algebraic system at each time with mdot0 = 3 - t,
    # the MTK reading of Python's mdot0(t)=3-t current source over the transient.
    A1, A2 = 1.0, 2.0
    Tin = 293.15
    @named pump = Pump(; mdot0=3.0)
    @named hx = HeatExchanger(Tin)
    @named lpd = LocalPressureDrop(; A1=A1, A2=A2)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, lpd.port_in),
        connect(lpd.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:lpd_reversal), pump, hx, lpd)
    ssys = mtkcompile(sys)
    mdot = Float64[]
    for tt in 0.0:1.0:6.0
        m = 3.0 - tt
        sol = solve_steady(ssys, Pair{Any,Any}[ssys.pump.mdot0 => m, ssys.lpd.port_in.mdot => m])
        @test sol.retcode == ReturnCode.Success
        push!(mdot, sol[ssys.lpd.port_in.mdot])
    end
    @test all(mdot[1:4] .>= -1e-6)      # t = 0,1,2,3: forward (≥ 0)
    @test all(mdot[4:7] .<= 1e-5)       # t = 3,4,5,6: stopped / reversed
    for (i, tt) in enumerate(0.0:1.0:6.0)
        @test isapprox(mdot[i], 3.0 - tt; atol=1e-5)   # tracks the current source
    end
end

@testset "flapper opens with ref_mdot" begin
    # Python: test_flapper_opens_with_ref_mdot
    # Pump(p·exp(-t)) drives a resistor in parallel with a flapper; ref_mdot = resistor flow.
    # The resistor flow mdot_R = exp(-t) (r=p=1), so the flapper opens when it hits 0.1, i.e.
    # at t_open = log(10). The flapper carries no flow before t_open and opens after.
    p = 1.0
    mdot0 = 1.0
    dp_fn = (tt) -> p * exp(-tt)   # one function object: passed to Pump AND the op (same type)
    @named pump = Pump(dp_fn)
    @named R = Resistor(p / mdot0)
    @named flapper = Flapper(; open_at_current=0.1 * mdot0, f=1.0, area=1.0, open_rate=10.0,
                             fluid=ConstantFluid())
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, R.port_in, flapper.port_in),
        connect(R.port_out, flapper.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        watch_flow(flapper, R.port_in.mdot),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:flapper_refmdot), pump, R, flapper, hx)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[
        ssys.R.port_in.mdot => 1.0,
        ssys.pump.dP_pump_fn => dp_fn,
    ]   # T_open defaults to Inf (flapper closed until the callback latches it)
    @test isinf(ModelingToolkit.getdefault(ssys.flapper.T_open))   # starts closed (Python: isinf(F.t_open))
    # ref_mdot is the resistor flow R.mdot = pump_dP/r = p·exp(-t), which mtkcompile leaves
    # purely algebraic (no inertia ⇒ no state). flapper_callback detects the crossing exactly
    # anyway: it root-finds the observed function for ref_mdot at the solver's trial state, so
    # the valve opens when the REAL wired flow reaches the threshold — no hardcoded analytic.
    cb = flapper_callback(ssys, ssys.flapper)
    t_arr = range(0.0, 5.0; length=500)
    sol = solve_transient(ssys, op, t_arr; callbacks=cb)
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol.ps[ssys.flapper.T_open], log(10.0); rtol=1e-3)   # detected open time = log(10)
    @test isapprox(sol(1.0; idxs=ssys.flapper.port_in.mdot), 0.0; atol=1e-8)  # closed before
    @test sol(4.0; idxs=ssys.flapper.port_in.mdot) > 1e-6                     # open after
end

@testset "flapper and pump" begin
    # Python: test_flapper_and_pump
    # A pre-timed flapper (open at t=2.5) in series with a decaying pump: no flow until the
    # flapper opens, then the quadratic flapper conducts and flow becomes nonzero.
    t_open = 2.5
    dp_fn = (tt) -> exp(-tt)   # one function object for Pump + op
    @named pump = Pump(dp_fn)
    @named flapper = Flapper(; open_at_current=0.1, f=1.0, area=1.0, open_rate=10.0,
                             fluid=ConstantFluid())
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, flapper.port_in),
        connect(flapper.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        watch_flow(flapper, pump.port_in.mdot),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:flapper_pump), pump, flapper, hx)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[
        ssys.flapper.T_open => t_open,            # pre-set open time (Python's F.open(2.5))
        ssys.pump.dP_pump_fn => dp_fn,
    ]
    sol = solve_transient(ssys, op, range(0.0, 5.0; length=500))
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol(2.0; idxs=ssys.pump.port_in.mdot), 0.0; atol=1e-8)   # closed ⇒ no flow
    @test abs(sol(4.5; idxs=ssys.pump.port_in.mdot)) > 1e-6                 # open ⇒ flow
end

@testset "inertia with flapper in PCS coastdown" begin
    # Python: test_inertia_with_flapper_in_PCS_coastdown
    # Inertia coasts down through a VolumetricFlowResistor (k=1) in parallel with a flapper (f=2k)
    # that opens at t=100. At full open both are quadratic with the same coefficient (R: dp=k·mdot²,
    # flapper: dp=f·mdot²/(2A²)=k·mdot²), so the split is even: mdot_R = mdot_flap. A pump holds the
    # steady mdot0=1 with the flapper still closed, then shuts off; the transient starts from that
    # solved state, so the coastdown initial condition is consistent across MTK versions.
    k = 1.0
    mdot0 = 1.0
    @named pump = Pump(k * mdot0^2)      # holds mdot0 through R while the flapper is closed
    @named ine = Inertia(1.0e3)
    @named R = VolumetricFlowResistor(; k=k, density=1.0)
    @named flapper = Flapper(; open_at_current=0.0, f=2 * k, area=1.0, open_rate=1.0,
                             fluid=ConstantFluid())
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, R.port_in, flapper.port_in),
        connect(R.port_out, flapper.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        watch_flow(flapper, ine.port_in.mdot),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:flapper_coastdown), pump, ine, R, flapper, hx)
    ssys = mtkcompile(sys; fully_determined=false)
    # Flapper default T_open=Inf ⇒ closed at the steady solve; override to 100 for the coast.
    sol_ss = solve_steady(ssys, [ssys.ine.port_in.mdot => mdot0, ssys.R.port_in.mdot => mdot0])
    @test sol_ss.retcode == ReturnCode.Success
    sol = solve_transient(ssys, sol_ss, range(0.0, 150.0; length=300);
                          overrides=[ssys.pump.dP_pump => 0.0, ssys.flapper.T_open => 100.0])
    @test sol.retcode == ReturnCode.Success
    mdot_R = sol[ssys.R.port_in.mdot, end]
    mdot_F = sol[ssys.flapper.port_in.mdot, end]
    @test mdot_R > 0 && mdot_F > 0
    @test isapprox(mdot_R, mdot_F; rtol=1e-3)    # even split at full open
end

@testset "inertia with transistor in PCS coastdown" begin
    # Python: test_inertia_with_transistor_in_PCS_coastdown — steady combined-resistance + convergence.
    # A time-dependent ("transistor") parabolic resistor that starts very stiff (k2) and
    # collapses to k_final after t_open, in parallel with a constant VolumetricFlowResistor.
    k1 = 1.0
    k2 = 1.0e7
    k_final = 1.0
    t_open = 100.0
    t_final = 300.0
    kfn = (tt) -> tt <= t_open ? k2 : (k2 - k_final) * exp(-50 * (tt - t_open) / t_final) + k_final
    total_k0 = k1 * k2 / (sqrt(k1) + sqrt(k2))^2   # combined coeff at t=0 (transistor still stiff)
    @named pump = Pump(total_k0)                    # holds mdot0=1 through the parallel block
    @named ine = Inertia(1.0e3)
    @named R = VolumetricFlowResistor(; k=k1, density=1.0)
    @named transistor = VolumetricFlowResistor(; k=kfn, density=1.0)
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, R.port_in, transistor.port_in),
        connect(R.port_out, transistor.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:transistor_coastdown), pump, ine, R, transistor, hx)
    ssys = mtkcompile(sys)
    sr(a, b) = 1 + sqrt(a / b)
    # Python solves the driven steady state (transistor stiff, near-all flow through R), then
    # shuts the pump and coasts as the transistor collapses. Solve_steady on, then coast from it.
    sol_ss = solve_steady(ssys, [
        ssys.ine.port_in.mdot => 1.0,
        ssys.R.port_in.mdot => 1.0 / sr(k1, k2),
        ssys.transistor.port_in.mdot => 1.0 / sr(k2, k1),
        ssys.transistor.k_fn => kfn,
    ])
    @test sol_ss.retcode == ReturnCode.Success
    sol = solve_transient(ssys, sol_ss, range(0.0, t_final; length=302);
                          overrides=[ssys.pump.dP_pump => 0.0, ssys.transistor.k_fn => kfn],
                          reltol=1e-6, abstol=1e-7)
    @test sol.retcode == ReturnCode.Success    # convergence is the gate
    # Two parallel quadratic resistors combine to an effective coefficient
    # k1·k2/(√k1+√k2)². At t=0 the loop sits at the steady split (mdot_total = 1), so
    # total_k = ΔP_block / mdot_total² reproduces that closed form (Python's total_k check).
    total_k = sol(0.0; idxs=ssys.R.port_in.P - ssys.R.port_out.P) /
              sol(0.0; idxs=ssys.ine.port_in.mdot)^2
    @test isapprox(total_k, k1 * k2 / (sqrt(k1) + sqrt(k2))^2; rtol=1e-3)
end

@testset "kirchhoff with decaying pump eventually flips flow direction (gravity)" begin
    # Python: test_kirchhoff_with_decaying_pump_eventually_flips_flow_direction_gravity
    # A decaying-head pump drives flow against two opposed gravity legs (hot up / cold down)
    # plus a resistor. Each leg's coolant temperature is pinned by a HeatExchanger (Python's
    # per-component Tin). At t=0 the resistor pressure drop is p0 - g·Δρ; as the head decays
    # past the buoyancy head g·Δρ the flow reverses. No inertia ⇒ the loop is quasi-static:
    # solve_steady per time-point with the pump head overridden, the MTK reading of Python's
    # decaying-pressure current source.
    p0 = 4000.0
    high_T = 333.15   # Python 60 C
    low_T = 293.15    # Python 20 C
    g_acc = 9.80665
    @named pump = Pump(p0)              # fixed-pressure; dP_pump overridden per t (quasi-static)
    @named HX_hot = HeatExchanger(high_T)
    @named HX_cold = HeatExchanger(low_T)
    # Gravity must oppose the pumped flow so the decay reverses it. Julia's Gravity drop is
    # +ρgH along flow ("drop along flow"), the opposite reference to Python's "positive-down"
    # pressure_diff, so the hot leg takes H=-1 and the cold leg H=+1 (Python's g1=+1, g2=-1).
    @named G1 = Gravity(-1.0)           # hot leg
    @named G2 = Gravity(1.0)            # cold leg
    @named R = Resistor(1.0e5)
    conns = [
        connect(pump.port_out, HX_hot.port_in),
        connect(HX_hot.port_out, G1.port_in),
        connect(G1.port_out, HX_cold.port_in),
        connect(HX_cold.port_out, G2.port_in),
        connect(G2.port_out, R.port_in),
        connect(R.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:decay_grav), pump, HX_hot, HX_cold, G1, G2, R)
    ssys = mtkcompile(sys)
    delta_rho = rho_water(low_T) - rho_water(high_T)   # = ρ(low_T) - ρ(high_T) > 0
    times = range(0.0, 10.0; length=10)
    mdot = Float64[]
    rdrop0 = 0.0
    for (i, tt) in enumerate(times)
        sol = solve_steady(ssys, Pair{Any,Any}[ssys.pump.dP_pump => p0 * exp(-tt),
                                               ssys.R.port_in.mdot => p0 / 1.0e5])
        @test sol.retcode == ReturnCode.Success
        push!(mdot, sol[ssys.R.port_in.mdot])
        i == 1 && (rdrop0 = sol[ssys.R.port_in.P] - sol[ssys.R.port_out.P])
    end
    # Python asserts r.pressure = g·Δρ - p0; its "pressure" is the negative of the Julia
    # in→out drop R·mdot, so the Julia drop is p0 - g·Δρ (same magnitude).
    @test isapprox(rdrop0, p0 - g_acc * delta_rho; rtol=1e-6)
    @test mdot[end] < 0    # flow reverses once the head decays past the buoyancy head
end

@testset "pump coastdown allows channels to reverse flow direction" begin
    # Python: test_pump_coastdown_allows_channels_to_reverse_flow_direction
    # Two vertical channels (one hot, one cold, opposite g) with a pump driving flow against
    # buoyancy. As the pump coasts down the gravitational head wins and the flow reverses; the
    # zero-crossing occurs when the pump head equals the buoyancy head L·g·Δρ. Python's #16 is
    # inertia-free (no KirchhoffWDerivatives ⇒ the channel mdot2 term is None), so the faithful
    # match is quasi-static: solve_steady per time-point with the head decaying. Julia channels
    # always carry distributed inertia, so the per-point solve uses DynamicSS to reach the true
    # quasi-static steady (the default root-finder converges to the spurious mdot=0 root).
    D_pipe = 0.10
    mdot0 = 1.0
    T_cold = 293.15
    T_hot = 353.15    # Python 80 C
    g_acc = 9.80665
    geom = PipeGeometry_circular(1.0, D_pipe)
    nz = 9            # Python z_boundaries = linspace(0, L, 10) -> 9 cells
    # Laminar friction f = 64/Re makes the loop drop linear in mdot, so the per-point
    # quasi-static guess below is exact and the coastdown stays well-behaved through the
    # zero-crossing. Python uses regime_dependent friction, but here that diverges: at this
    # operating point the per-point DynamicSS solve collapses to the spurious mdot=0 root at
    # every step (it needs a true transient, not a per-point steady). regime_dependent reduces
    # to laminar near mdot→0 anyway, and the asserted physics (crossing = buoyancy head, pinned
    # temps) is friction-independent — friction is tiny here (p_pump0≈grav_dp) — so the laminar
    # surrogate costs no fidelity. See WV notes; do not "restore" regime_dependent without
    # also switching this to a transient solve.
    fric = (Re) -> 64.0 / Re
    @named cold = Channel(; n=nz, geometry=geom, g=+g_acc, fluid=Water(), friction_correlation=fric)
    @named hot = Channel(; n=nz, geometry=geom, g=-g_acc, fluid=Water(), friction_correlation=fric)
    # Bracket each adiabatic channel with same-temperature HeatExchangers on BOTH ends so its
    # coolant stays pinned under reversal too (Python pins both Tin and Tin_minus per channel).
    @named HXc1 = HeatExchanger(T_cold)
    @named HXc2 = HeatExchanger(T_cold)
    @named HXh1 = HeatExchanger(T_hot)
    @named HXh2 = HeatExchanger(T_hot)
    function build_coastdown(pumpcomp)
        conns = [
            connect(pumpcomp.port_out, HXc1.port_in),
            connect(HXc1.port_out, cold.port_in),
            connect(cold.port_out, HXc2.port_in),
            connect(HXc2.port_out, HXh1.port_in),
            connect(HXh1.port_out, hot.port_in),
            connect(hot.port_out, HXh2.port_in),
            connect(HXh2.port_out, pumpcomp.port_in),
            pumpcomp.port_in.P ~ 1.0e5,
        ]
        return mtkcompile(compose(System(conns, t; name=:coastdown), pumpcomp,
                                  HXc1, HXc2, HXh1, HXh2, cold, hot))
    end

    # Forced-flow steady at mdot0 → the pump head that holds it (Python's steady pump pressure).
    @named pump = Pump(; mdot0=mdot0)
    ssys = build_coastdown(pump)
    guess = Pair{Any,Any}[ssys.cold.port_in.mdot => mdot0]
    append!(guess, [ssys.cold.T[i] => T_cold for i in 1:nz])
    append!(guess, [ssys.hot.T[i] => T_hot for i in 1:nz])
    sol0 = solve_steady(ssys, guess)
    @test sol0.retcode == ReturnCode.Success
    p_pump0 = sol0[ssys.pump.port_out.P] - sol0[ssys.pump.port_in.P]
    delta_rho = rho_water(T_cold) - rho_water(T_hot)
    grav_dp = 1.0 * g_acc * delta_rho   # L·g·Δρ, the buoyancy head

    # Coastdown: fixed-pressure pump, head = p_pump0·exp(-t) overridden per time-point.
    @named pump2 = Pump(p_pump0)
    ssys2 = build_coastdown(pump2)
    Dt = Differential(t)
    K_eff = p_pump0 - grav_dp           # laminar ⇒ loop drop linear: pump - grav = K_eff·mdot
    times = range(0.0, 0.05; length=150)
    mdot = Float64[]
    cold_cells = Float64[]   # every cell at every time (Python asserts allclose over the full T_cool array)
    hot_cells = Float64[]
    for tt in times
        op = Pair{Any,Any}[ssys2.pump2.dP_pump => p_pump0 * exp(-tt),
                           ssys2.cold.port_in.mdot => (p_pump0 * exp(-tt) - grav_dp) / K_eff,
                           Dt(ssys2.hot.port_in.mdot) => 0.0,
                           Dt(ssys2.cold.port_in.mdot) => 0.0]
        append!(op, [ssys2.cold.T[i] => T_cold for i in 1:nz])
        append!(op, [ssys2.hot.T[i] => T_hot for i in 1:nz])
        sol = solve_steady(ssys2, op; solver=DynamicSS(Rodas5P()))
        @test sol.retcode == ReturnCode.Success
        push!(mdot, sol[ssys2.cold.port_in.mdot])
        append!(cold_cells, sol[ssys2.cold.T])
        append!(hot_cells, sol[ssys2.hot.T])
    end
    @test mdot[1] > 0                       # starts forward
    @test all(diff(mdot) .< 0)              # monotonically decreasing
    @test mdot[1] > 0 > mdot[end]           # reverses
    @test all(isapprox.(cold_cells, T_cold; rtol=1e-4))   # all cells stay pinned (HX-bracketed) under reversal
    @test all(isapprox.(hot_cells, T_hot; rtol=1e-4))
    # Crossing occurs when the pump head equals the buoyancy head L·g·Δρ.
    p_cross = p_pump0 * exp(-times[argmin(abs.(mdot))])
    @test isapprox(p_cross, grav_dp; rtol=1e-3)
end

# ----------------------------------------------------------------------------
# Tier-B channel / point-kinetics ports (#4, #5, #8, #9).
#
# These assert Python's closed-form *analytic results* (linear coolant rise,
# h-weighted wall temperature, power driven negligible by negative feedback), not
# byte-identical numbers — Julia's models differ from Python's mocks in ways that
# are immaterial to those results:
#   - Julia `HeatDiffusion` is single-material; Python's MTR fuel is multi-material
#     (meat + clad). Used here with mock single-material solid (k_s=cp_s=rho_s=1).
#   - Julia `ChannelAndContacts` computes its HTC from a correlation (water-based);
#     Python prescribes a mock h. #4 reads Julia's computed `h_tc` into the same
#     wall-temperature balance Python checks against its prescribed h.
#   - Julia `PointKinetics` is fixed 6-group U-235; Python #8 uses a single group.
#     The "power → 0 under negative feedback" result is group-count-independent.
#   - Julia `HeatDiffusion` needs nx ≥ 2; Python uses nx = 1. The per-axial-slice
#     power (hence the linear coolant rise) is independent of the lateral count.
# `ConstantFluid()` is the Julia counterpart of Python's `mock_liquid_funcs` (all
# properties 1.0), which gives the clean closed-form coolant temperatures.
# ----------------------------------------------------------------------------

@testset "channel stable state with uniform heating increases linearly" begin
    # Python: test_channel_stable_state_with_uniform_heating_increases_linearly
    # A channel heated on one face by a fuel plate under uniform power. With cp = 1
    # (ConstantFluid) the coolant rises linearly, Tc[i] = T0 + i·P/(nz·mdot), and the
    # conjugate wall temperature is the h-weighted mean Tw = (Tc·h + Tf·h_fw)/(h + h_fw).
    T0 = 313.15
    P = 10.0
    mdot = 1.0
    n = 10
    nz = 10
    nx = 2
    k_s = 1.0
    Lx = 1.0
    # Mock one-sided pipe (heated_parts = (0, 1), area 1) + mock solid (all 1).
    geom = PipeGeometry(1.0, 4.0, 1.0, 1.0, 1.0, (0.0, 1.0), 1.0, 1.0)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named cac = ChannelAndContacts(; n=n, geometry=geom, fluid=ConstantFluid(),
                                    htc_correlation=constant_Nusselt(; Nu=8.235))
    @named fuel = HeatDiffusion(; nz=nz, nx=nx, Lz=1.0, Lx=Lx, y=1.0,
                                rho_s=1.0, cp_s=1.0, k_s=k_s, power_shape=ps, T0=T0)
    osc = one_sided_connection(cac, fuel; side=:right, name=:osc)   # fuel heats the right face only
    @named pump = Pump(; mdot0=mdot)
    @named bc = HeatExchanger(T0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, osc.cac.port_in),
        connect(osc.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        osc.fuel.power ~ P,
        # Unheated left face (heated_parts[1]=0 ⇒ Q=0) has a floating wall T; pin it to the
        # coolant temp (an insulated wall carries no heat, so this is just a closure).
        [port(osc.cac, :thermal_left, i).T ~ osc.cac.T[i] for i in 1:n]...,
    ]
    full = compose_systems(osc, pump, bc; connections=conns, name=:sys4)
    ssys = mtkcompile(full)
    ic = Pair{Any,Any}[ssys.osc.cac.port_in.mdot => mdot]
    append!(ic, [ssys.osc.cac.T[i] => T0 for i in 1:n])
    append!(ic, [ssys.osc.fuel.T[i, j] => T0 for i in 1:nz for j in 1:nx])
    sol = solve_transient(ssys, ic, range(0.0, 200.0; length=50);
                          initializealg=BrownFullBasicInit(), maxiters=1_000_000)
    @test sol.retcode == ReturnCode.Success
    Tc = [sol[ssys.osc.cac.T[i], end] for i in 1:n]
    Tc_analytic = [T0 + i * (P / (nz * mdot)) for i in 1:nz]   # cp = 1 (ConstantFluid)
    @test all(isapprox.(Tc, Tc_analytic; rtol=1e-6))           # coolant rises linearly
    # h-weighted wall temperature, reading Julia's computed h_tc (Python prescribes h).
    h_fw = 2 * k_s / (Lx / nx)
    Tw = [sol[port(ssys.osc.cac, :thermal_right, i).T, end] for i in 1:n]
    Tf = [sol[ssys.osc.fuel.T[i, 1], end] for i in 1:nz]
    h = [sol[ssys.osc.cac.h_tc_right[i], end] for i in 1:n]
    Tw_pred = (Tc .* h .+ Tf .* h_fw) ./ (h .+ h_fw)
    @test all(isapprox.(Tw, Tw_pred; rtol=1e-6))               # conjugate wall-temp balance
end

@testset "channel point kinetics — per-channel coolant rises linearly" begin
    # Python: test_channel_point_kinetics — several channel+fuel loops share one PointKinetics with
    # temperature feedback (a worth on every channel and fuel cell, reference T0, inlet T0-10). The
    # feedback self-balances the reactor at a nonzero critical power, and each channel's coolant
    # rises linearly along its length; Python asserts that linearity.
    #
    # MTK's coupled solve_steady on a live feedback PointKinetics collapses to the trivial P=0 root
    # on every MTK version and solver — it zeros dP/dt by driving P->0 rather than by driving the
    # reactivity to zero, which is the (dynamically unstable) root Python's algebraic-Jacobian
    # Newton lands on. We reach the identical physical steady by continuation instead: with a
    # uniform temperature worth the critical condition (reactivity = 0) is exactly "the total
    # fed-back temperature excess over the reference T0 is zero", and each constant-power steady
    # solves robustly. So we bisect the shared power to that condition and assert the coolant
    # profile there. The live feedback PointKinetics -> channel path is exercised in #8/#9.
    T0 = 313.15
    Tin = T0 - 10.0
    n = 7
    nz = 7
    nx = 2
    mdots = [1.0, 0.7, 0.4]        # distinct mdots ⇒ distinct slopes off the shared power
    N = length(mdots)
    geom = PipeGeometry(1.2, 4.0, 1.0, 2.0, 1.0, (1.0, 1.0), 1.0, 1.0)
    ps = fill(1.0 / (nz * nx), nz, nx)
    # Shared reactor power as a parameter, so the continuation re-solves without recompiling.
    @parameters Pw
    Pw = ModelingToolkit.GlobalScope(Pw)
    cacs = [ChannelAndContacts(; n=n, geometry=geom, fluid=ConstantFluid(),
                               htc_correlation=constant_Nusselt(; Nu=8.235), name=:cac) for _ in 1:N]
    fuels = [HeatDiffusion(; nz=nz, nx=nx, Lz=1.2, Lx=1.0, y=1.0, rho_s=1.0, cp_s=1.0, k_s=1.0,
                           power_shape=ps, T0=T0, name=:fuel) for _ in 1:N]
    rodss = [symmetric_plate(cacs[i], fuels[i]; name=Symbol(:rods, i)) for i in 1:N]
    pumps = [Pump(; mdot0=mdots[i], name=Symbol(:pump, i)) for i in 1:N]
    bcs = [HeatExchanger(Tin; name=Symbol(:bc, i)) for i in 1:N]
    conns = Equation[]
    for i in 1:N
        append!(conns, Equation[
            connect(pumps[i].port_out, bcs[i].port_in),
            connect(bcs[i].port_out, rodss[i].cac.port_in),
            connect(rodss[i].cac.port_out, pumps[i].port_in),
            pumps[i].port_in.P ~ 1.0e5,
            rodss[i].fuel.power ~ Pw,               # all fuels share one reactor power
        ])
    end
    ssys = mtkcompile(compose_systems(rodss..., pumps..., bcs...; connections=conns, name=:sys5))
    guess = Pair{Any,Any}[]
    for i in 1:N
        rods = getproperty(ssys, Symbol(:rods, i))
        push!(guess, rods.cac.port_in.mdot => mdots[i])
        append!(guess, [rods.cac.T[j] => T0 for j in 1:n])
        append!(guess, [rods.fuel.T[j, k] => T0 for j in 1:nz for k in 1:nx])
    end
    solve_at(p) = solve_steady(ssys, Pair{Any,Any}[guess..., Pw => p])
    excess(sol) = sum(
        sum(sol[getproperty(ssys, Symbol(:rods, i)).cac.T[j]] - T0 for j in 1:n) +
        sum(sol[getproperty(ssys, Symbol(:rods, i)).fuel.T[j, k]] - T0 for j in 1:nz for k in 1:nx)
        for i in 1:N)
    # Bisect the shared power to the critical condition (feedback reactivity = 0 ⇔ excess = 0).
    # excess rises monotonically with power; excess(low) < 0 (cold), excess(high) > 0 (hot).
    lo, hi = 1.0, 40.0
    sol = solve_at(lo)
    for _ in 1:25
        pmid = (lo + hi) / 2
        sol = solve_at(pmid)
        @test sol.retcode == ReturnCode.Success
        excess(sol) > 0 ? (hi = pmid) : (lo = pmid)
    end
    @test (lo + hi) / 2 > 1.0                       # nonzero critical power (not the trivial P=0 root)
    for i in 1:N
        rods = getproperty(ssys, Symbol(:rods, i))
        Tc = [sol[rods.cac.T[j]] for j in 1:n]
        @test all(diff(Tc) .> 0)                    # strictly increasing
        @test all(abs.(diff(diff(Tc))) .< 1e-6)     # vanishing second difference (linear)
    end
    # Distinct mdots ⇒ distinct slopes off the shared power: the channels couple independently.
    rise(i) = (rods = getproperty(ssys, Symbol(:rods, i)); sol[rods.cac.T[2]] - sol[rods.cac.T[1]])
    @test rise(1) < rise(2) < rise(3)               # smaller mdot ⇒ steeper rise
end

@testset "power is negligible for negative Tfuel feedback (ref = boundary)" begin
    # Python: test_power_is_negligible_for_negative_Tfuel_feedback_and_ref_temp_is_boundary
    # A fuel plate tied to a T0 thermal bath, with PointKinetics fuel-temperature feedback whose
    # reference is that same T0. Negative feedback drives the steady power to zero and every fuel
    # temperature back to T0. (Julia's stabilizing feedback uses a negative coefficient, the
    # opposite sign convention to Python's positive worth.)
    T0 = 308.15
    nz = 10
    nx = 2
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named fuel = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                                rho_s=3000.0, cp_s=800.0, k_s=100.0, power_shape=ps, T0=T0)
    bathsL = [ConstantTemperature(T0; name=Symbol(:bathL, i)) for i in 1:nz]
    bathsR = [ConstantTemperature(T0; name=Symbol(:bathR, i)) for i in 1:nz]
    ctrl = ReactivityController()
    @named pk = PointKinetics(ctrl; temp_worth=Dict(fuel => fill(-0.1, nz, nx)),
                              ref_temp=Dict(fuel => fill(T0, nz, nx)))
    fb = connect_temperature_feedback(pk, [fuel])
    bath_conns = vcat(
        [connect(port(fuel, :thermal_left, i), bathsL[i].thermal) for i in 1:nz],
        [connect(port(fuel, :thermal_right, i), bathsR[i].thermal) for i in 1:nz],
    )
    conns = Equation[fb...; fuel.power ~ pk.P * 1.0e3; bath_conns...]
    full = compose_systems(fuel, pk, bathsL..., bathsR...; connections=conns, name=:sys8)
    ssys = mtkcompile(full)
    pk_ic = point_kinetics_steady_state(1.0e5)
    ic = Pair{Any,Any}[
        ssys.pk.rho_c_fn => ctrl,
        ssys.pk.P => 1.0e5,
        ssys.pk.C_1 => pk_ic.C_k[1], ssys.pk.C_2 => pk_ic.C_k[2], ssys.pk.C_3 => pk_ic.C_k[3],
        ssys.pk.C_4 => pk_ic.C_k[4], ssys.pk.C_5 => pk_ic.C_k[5], ssys.pk.C_6 => pk_ic.C_k[6],
    ]
    append!(ic, [ssys.fuel.T[i, j] => 2 * T0 for i in 1:nz for j in 1:nx])   # start hot
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.pk.P] < 1e-3                                              # power → 0
    @test all(isapprox(sol[ssys.fuel.T[i, j]], T0; atol=1e-3) for i in 1:nz for j in 1:nx)
end

@testset "power is negligible for negative Tcool feedback (ref = inlet)" begin
    # Python: test_power_is_negligible_for_negative_Tcool_feedback_and_ref_temp_is_inlet
    # A channel + fuel plate with PointKinetics coolant-temperature feedback whose reference is
    # the inlet T0. Negative feedback drives the steady power to zero and the coolant back to T0.
    T0 = 308.15
    n = 7
    nz = 7
    nx = 2
    geom = PipeGeometry(1.2, 4.0, 1.0, 2.0, 1.0, (1.0, 1.0), 1.0, 1.0)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named cac = ChannelAndContacts(; n=n, geometry=geom, fluid=ConstantFluid(),
                                    htc_correlation=constant_Nusselt(; Nu=8.235))
    @named fuel = HeatDiffusion(; nz=nz, nx=nx, Lz=1.2, Lx=1.0, y=1.0,
                                rho_s=1.0, cp_s=1.0, k_s=1.0, power_shape=ps, T0=T0)
    rods = symmetric_plate(cac, fuel; name=:rods)
    ctrl = ReactivityController()
    @named pk = PointKinetics(ctrl; temp_worth=Dict(rods.cac => fill(-0.1, n)),
                              ref_temp=Dict(rods.cac => fill(T0, n)))
    fb = connect_temperature_feedback(pk, [rods.cac])
    mdot0 = 0.1
    @named pump = Pump(; mdot0=mdot0)
    @named bc = HeatExchanger(T0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ pk.P * 1.0e3,
        fb...,
    ]
    full = compose_systems(rods, pk, pump, bc; connections=conns, name=:sys9)
    ssys = mtkcompile(full)
    pk_ic = point_kinetics_steady_state(1.0e5)
    ic = Pair{Any,Any}[
        ssys.pk.rho_c_fn => ctrl,
        ssys.pk.P => 1.0e5,
        ssys.pk.C_1 => pk_ic.C_k[1], ssys.pk.C_2 => pk_ic.C_k[2], ssys.pk.C_3 => pk_ic.C_k[3],
        ssys.pk.C_4 => pk_ic.C_k[4], ssys.pk.C_5 => pk_ic.C_k[5], ssys.pk.C_6 => pk_ic.C_k[6],
        ssys.rods.cac.port_in.mdot => mdot0,
    ]
    append!(ic, [ssys.rods.cac.T[i] => 2 * T0 for i in 1:n])    # start hot
    append!(ic, [ssys.rods.fuel.T[i, j] => 2 * T0 for i in 1:nz for j in 1:nx])
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.pk.P] < 1e-3                                 # power → 0
    @test all(isapprox(sol[ssys.rods.cac.T[i]], T0; atol=1e-3) for i in 1:n)
end
