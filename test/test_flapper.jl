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
        connect(pump.port_out, bypass.port_in, flapper.port_in),
        connect(bypass.port_out, flapper.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        flapper.ref_mdot ~ bypass.port_in.mdot,
        pump.port_in.P ~ 1.0e5,
    ]
    return compose(System(conns, t; name=name), pump, bypass, flapper, hx), bypass
end

@testset "Flapper closed admits no flow" begin
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0,
                             fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_closed)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[ssys.flapper.T_open => 1e30]   # never opens
    sol = solve_transient(ssys, op, range(0.0, 5.0; length=20))
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.port_in.mdot, end], 0.0; atol=1e-8)   # closed ⇒ no flow
    @test isapprox(sol[ssys.flapper.xi, end], 0.0; atol=1e-8)
    @test sol[ssys.bypass.port_in.mdot, end] > 0                          # bypass carries it
end

@testset "Flapper open is a quadratic resistor" begin
    f, area, rho = 1.0, 1.0, 1.0
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; open_at_current=0.01, f=f, area=area, open_rate=10.0,
                             fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_open)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[ssys.flapper.T_open => 0.0]   # open from t=0
    sol = solve_transient(ssys, op, range(0.0, 1.0; length=20))           # past the 1/open_rate ramp
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)             # fully open
    mf = sol[ssys.flapper.port_in.mdot, end]
    dp = sol[ssys.flapper.port_in.P - ssys.flapper.port_out.P, end]
    @test mf > 0
    @test isapprox(dp, f * mf * abs(mf) / (2 * rho * area^2); rtol=1e-6)  # quadratic law
end

@testset "Flapper opens when ref_mdot crosses threshold" begin
    # A weak (large-f) flapper in parallel with a decaying inertia+resistor branch: the loop
    # flow coasts down past the threshold, the callback latches T_open, and the ramp completes.
    threshold = 0.01
    L_over_A = 5.0e5     # tau = L_over_A / R = 5 s
    R = 1.0e5
    @named pump = Pump(0.0)
    @named ine = Inertia(L_over_A)
    @named res = Resistor(R)
    @named flapper = Flapper(; open_at_current=threshold, f=1.0e6, area=1.0, open_rate=1.0 / 3.0,
                             fluid=ConstantFluid())
    @named hx = HeatExchanger(300.0)
    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, res.port_in, flapper.port_in),
        connect(res.port_out, flapper.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        flapper.ref_mdot ~ ine.port_in.mdot,
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:flap_decay), pump, ine, res, flapper, hx)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[ssys.ine.port_in.mdot => 1.0, ssys.flapper.T_open => 1e30]
    sol = solve_transient(ssys, op, range(0.0, 60.0; length=600);
                          callbacks=flapper_callback(ssys, ssys.ine.port_in.mdot; threshold=threshold))
    @test sol.retcode == ReturnCode.Success
    T_open = sol[ssys.flapper.T_open, end]
    @test 0.0 < T_open < 1e10                         # event fired at a positive time
    @test isapprox(T_open, -5.0 * log(threshold); rtol=0.1)   # tau·ln(mdot0/threshold), mdot0=1
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)  # ramp completed by t_end
end

@testset "solve_transient passes user callbacks" begin
    @named pump = Pump(1.0e5)
    @named flapper = Flapper(; fluid=ConstantFluid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_cb)
    ssys = mtkcompile(sys; fully_determined=false)
    op = Pair{Any,Any}[ssys.flapper.T_open => 1e30]
    fired = Ref(false)
    user_cb = ContinuousCallback((u, t_val, integ) -> t_val - 5.0, integ -> (fired[] = true))
    sol = solve_transient(ssys, op, range(0.0, 20.0; length=200); callbacks=CallbackSet(user_cb))
    @test sol.retcode == ReturnCode.Success
    @test fired[]
end
