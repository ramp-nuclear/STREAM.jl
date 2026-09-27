using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Substances

# A closed flapper blocks all flow, so it sits in PARALLEL with a bypass resistor that
# carries the loop flow while the valve is shut.
function _flapper_parallel_loop(; flapper, pump, name)
    @named bypass = Resistor(1.0e5)
    @named hx = HeatExchanger(26.85)
    conns = [
        inparallel(pump, (bypass, flapper), hx)...,
        inseries(hx, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    return compose(System(conns, t; name=name), pump, bypass, flapper, hx), bypass
end

@testset "Flapper closed admits no flow" begin
    @named pump = Pump(3.0e4)
    @named flapper = Flapper(; f=1.0, area=1.0, open_rate=1.0, liquid=Liquid())
    sys, _ = _flapper_parallel_loop(; flapper=flapper, pump=pump, name=:flap_closed)
    ssys = mtkcompile(sys)
    op = Pair{Any,Any}[]   # a fresh machine stays :CLOSED ⇒ never opens
    sol = solve_transient(ssys, op, range(0.0, 5.0; length=20))
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
    op = []   # the machine starts :OPEN at t = 0
    sol = solve_transient(ssys, op, range(0.0, 1.0; length=20))           # past the 1/open_rate ramp
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
    sol = solve_transient(ssys, [], range(0.0, 1.0; length=101);
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
        inseries(pump, ine)...,
        inparallel(ine, (res, flapper), hx)...,
        inseries(hx, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    sys = compose(System(conns, t, [], [ṁ_open_at]; name=:flap_param), pump, ine, res,
                  flapper, hx)
    ssys = mtkcompile(sys)
    sol_ss = solve_steady(ssys, [ssys.ine.inlet.ṁ => 1.0, ssys.res.inlet.ṁ => 1.0])
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
    op = []   # a fresh machine stays shut
    fired = Ref(false)
    user_cb = ContinuousCallback((u, t_val, integ) -> t_val - 5.0, integ -> (fired[] = true))
    sol = solve_transient(ssys, op, range(0.0, 20.0; length=200); callbacks=CallbackSet(user_cb))
    @test sol.retcode == ReturnCode.Success
    @test fired[]
end
