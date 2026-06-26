using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM

@testset "Flapper has no use_callback or threshold kwargs" begin
    @test_throws Exception Flapper(; name=:flap_ref, use_callback=true)
    @test_throws Exception Flapper(; name=:flap_ref, threshold=0.01)
    @test_nowarn Flapper(; name=:flap_plain)
end

# A closed flapper blocks all flow, so it sits in PARALLEL with a bypass resistor that
# carries the loop flow while the valve is shut (Python STREAM's usage).
function _flapper_parallel_loop(; flapper, pump, name)
    @named bypass = Resistor(1.0e5)
    @named hx = HeatExchanger(300.0)
    conns = [
        inparallel(pump, (bypass, flapper), hx)...,
        inseries(hx, pump)...,
        watch_flow(flapper, bypass.inlet.ṁ),
        pump.inlet.p ~ 1.0e5,
    ]
    return compose(System(conns, t; name=name), pump, bypass, flapper, hx), bypass
end

@testset "Flapper closed admits no flow" begin
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0,
                             fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_closed)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[]   # T_open defaults to Inf ⇒ never opens
    sol = solve_transient(ssys, op, range(0.0, 5.0; length=20))
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.inlet.ṁ, end], 0.0; atol=1e-8)   # closed ⇒ no flow
    @test isapprox(sol[ssys.flapper.xi, end], 0.0; atol=1e-8)
    @test sol[ssys.bypass.inlet.ṁ, end] > 0                          # bypass carries it
end

@testset "Flapper open is a quadratic resistor" begin
    f, area, rho = 1.0, 1.0, 1.0
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; open_at_current=0.01, f=f, area=area, open_rate=10.0,
                             fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_open)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[ssys.flapper.T_open => 0.0]   # pre-open from t=0 (Python's open(0.0))
    sol = solve_transient(ssys, op, range(0.0, 1.0; length=20))           # past the 1/open_rate ramp
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)             # fully open
    mf = sol[ssys.flapper.inlet.ṁ, end]
    dp = sol[ssys.flapper.inlet.p - ssys.flapper.outlet.p, end]
    @test mf > 0
    @test isapprox(dp, f * mf * abs(mf) / (2 * rho * area^2); rtol=1e-6)  # quadratic law
end

@testset "Flapper opens when ref_mdot crosses threshold" begin
    # A weak (large-f) flapper sits in parallel with a resistor branch. A pump holds the loop flow
    # at mdot0, then shuts off and the flow coasts down past the threshold; the callback latches
    # T_open and the ramp completes. Detection is end-to-end (no pre-set open time), so this
    # exercises flapper_callback. The transient starts from the full solved steady state, which
    # keeps the coastdown IC consistent across MTK versions. A hand-seeded partial IC left the flow
    # frozen at ṁ=0 on newer MTK, so it never crossed the threshold and the valve never opened.
    threshold = 0.01
    L_over_A = 5.0e5     # tau = L_over_A / R = 5 s
    R = 1.0e5
    mdot0 = 1.0
    @named pump = Pump(R * mdot0)   # head holds mdot0 through the resistor while the flapper is shut
    @named ine = Inertia(L_over_A)
    @named res = Resistor(R)
    @named flapper = Flapper(; open_at_current=threshold, f=1.0e6, area=1.0, open_rate=1.0 / 3.0,
                             fluid=ConstantFluid())
    @named hx = HeatExchanger(300.0)
    conns = [
        inseries(pump, ine)...,
        inparallel(ine, (res, flapper), hx)...,
        inseries(hx, pump)...,
        watch_flow(flapper, ine.inlet.ṁ),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:flap_decay), pump, ine, res, flapper, hx)
    ssys = mtkcompile(sys; fully_determined=false)
    # Flapper default T_open=Inf ⇒ shut at the steady solve, so all flow goes through the resistor.
    sol_ss = solve_steady(ssys, [ssys.ine.inlet.ṁ => mdot0, ssys.res.inlet.ṁ => mdot0])
    @test sol_ss.retcode == ReturnCode.Success
    # Shut the pump (head ⇒ 0) and coast; the callback detects the threshold crossing and latches
    # T_open. T_open stays at its Inf default through the steady solve, so the callback owns it.
    sol = solve_transient(ssys, sol_ss, range(0.0, 60.0; length=600);
                          overrides=[ssys.pump.dP_pump => 0.0],
                          callbacks=flapper_callback(ssys, ssys.flapper))
    @test sol.retcode == ReturnCode.Success
    T_open = sol.ps[ssys.flapper.T_open]
    @test 0.0 < T_open < 1e10                                   # event fired at a positive time
    @test isapprox(T_open, -5.0 * log(threshold); rtol=0.1)     # tau·ln(mdot0/threshold), mdot0=1
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)   # ramp completed by t_end
end

@testset "solve_transient passes user callbacks" begin
    @named pump = Pump(1.0e5)
    @named flapper = Flapper(; fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_cb)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[]   # T_open defaults to Inf
    fired = Ref(false)
    user_cb = ContinuousCallback((u, t_val, integ) -> t_val - 5.0, integ -> (fired[] = true))
    sol = solve_transient(ssys, op, range(0.0, 20.0; length=200); callbacks=CallbackSet(user_cb))
    @test sol.retcode == ReturnCode.Success
    @test fired[]
end
