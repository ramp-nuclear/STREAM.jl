using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
# ─────────────────────────────────────────────────────────────────
@testset "FLAP-REF: Flapper has no use_callback or threshold kwargs" begin
    # Passing use_callback kwarg must raise MethodError
    @test_throws Exception Flapper(; name=:flap_ref, use_callback=true)
    # Passing threshold kwarg must raise MethodError
    @test_throws Exception Flapper(; name=:flap_ref, threshold=0.01)
    # Plain constructor (without those kwargs) must succeed
    @test_nowarn Flapper(; name=:flap_plain)
end

function _build_flapper_scalar_loop(dP_val)
    @named pump = Pump(dP_val)
    @named res = Resistor(1e5)
    @named flapper = Flapper()

    conns = [
        connect(pump.port_out, res.port_in),
        connect(res.port_out, flapper.port_in),
        connect(flapper.port_out, pump.port_in),
        flapper.ref_mdot ~ pump.port_in.mdot,
        pump.port_in.P ~ 1e5,
        pump.port_in.T ~ 313.15,
        res.port_out.T ~ 313.15,
    ]
    @named sys = compose(System(conns, t; name=:flap_scalar_loop), pump, res, flapper)
    return sys
end

@testset "FLAP-05: Flapper remains closed under positive ref_mdot" begin
    sys = _build_flapper_scalar_loop(1e5)
    ssys = mtkcompile(sys; fully_determined=false)  # legitimate-structural: Flapper state(t) is set by ContinuousCallback, not an MTK equation

    op = Pair{Any,Any}[ssys.flapper.T_open => 1e30,]

    t_arr = range(0.0, 20.0; length=200)
    sol = solve_transient(
        ssys,
        op,
        t_arr;
        callbacks=flapper_callback(ssys, ssys.pump.port_in.mdot; threshold=1e-6),
    )

    @test sol.retcode == ReturnCode.Success
    # T_open must stay at 1e30 sentinel (event never fired — ref_mdot > threshold all run)
    @test isapprox(sol[ssys.flapper.T_open, end], 1e30; rtol=1e-6)
    # xi must remain 0 (no ramp triggered)
    @test isapprox(sol[ssys.flapper.xi, end], 0.0; atol=1e-8)
end

# ─────────────────────────────────────────────────────────────────
# FLAP-06: Flapper opens when ref_mdot crosses threshold
#
# Topology: Pump(0) → Inertia(L_over_A=5e5) → Resistor(1e5) → Flapper → Pump
# With dP=0, the loop decays under inertia+resistance: tau = L/A / R = 5e5/1e5 = 5s
# Initial condition: ine.port_in.mdot = 1.0 kg/s
# ref_mdot wired to ine.port_in.mdot, threshold=1e-4 kg/s
# mdot decays exponentially: mdot(t) ~ mdot_0 * exp(-t / tau_eff)
# The event fires when mdot drops below threshold.
# T_open is recorded at the crossing time; after T_open + dt=3s, xi = 1.0.
# ─────────────────────────────────────────────────────────────────
@testset "FLAP-06: Flapper opens when ref_mdot crosses threshold" begin
    threshold_val = 1e-4   # kg/s; well below the initial mdot of 1.0 kg/s
    dt_ramp = 3.0    # s; ramp duration
    L_over_A = 5e5   # m^{-1}; tau_eff = L_over_A / R_eff ~ 5s

    @named pump = Pump(0.0)   # zero pressure: loop decays under inertia
    @named ine = Inertia(L_over_A)
    @named res = Resistor(1e5)
    @named flapper = Flapper(; dt=dt_ramp, R_closed=1e8, R_open=100.0)

    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, res.port_in),
        connect(res.port_out, flapper.port_in),
        connect(flapper.port_out, pump.port_in),
        # wire ref_mdot to the inertia mdot (the loop flow rate)
        flapper.ref_mdot ~ ine.port_in.mdot,
        pump.port_in.P ~ 1e5,
        pump.port_in.T ~ 313.15,
        ine.port_out.T ~ 313.15,
    ]
    @named sys = compose(System(conns, t; name=:flap06_decay), pump, ine, res, flapper)
    ssys = mtkcompile(sys; fully_determined=false)  # legitimate-structural: Flapper state(t) set by callback (see flapper.jl:38)

    mdot_0 = 1.0   # initial mdot (kg/s); well above threshold

    op = Pair{Any,Any}[ssys.ine.port_in.mdot => mdot_0, ssys.flapper.T_open => 1e30]

    t_arr = range(0.0, 100.0; length=1000)
    sol = solve_transient(
        ssys,
        op,
        t_arr;
        callbacks=flapper_callback(ssys, ssys.ine.port_in.mdot; threshold=threshold_val),
    )

    @test sol.retcode == ReturnCode.Success

    T_open_val = sol[ssys.flapper.T_open, end]

    # Event must have fired: T_open is no longer the 1e30 sentinel
    @test T_open_val < 1e10

    # Event must have fired at a positive time (not at t=0 where mdot was above threshold)
    @test T_open_val > 0.0

    # After T_open + dt_ramp, the ramp is complete: xi should reach 1.0
    # t_end = 100s >> T_open + dt_ramp, so xi should be 1.0 at the final time
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-6)

    # At t_end, mdot should be near zero (decay complete; pump dP = 0)
    @test abs(sol[ssys.ine.port_in.mdot, end]) < 1e-6 * mdot_0
end

@testset "SOLV-01: solve_transient passes user callbacks" begin
    sys = _build_flapper_scalar_loop(1e5)
    ssys = mtkcompile(sys; fully_determined=false)  # legitimate-structural: Flapper state(t) set by callback (see flapper.jl:38)

    op = Pair{Any,Any}[ssys.flapper.T_open => 1e30,]

    fired = Ref(false)
    user_cb = ContinuousCallback(
        (u, t_val, integ) -> t_val - 5.0, integ -> (fired[] = true)
    )

    t_arr = range(0.0, 20.0; length=200)
    sol = solve_transient(ssys, op, t_arr; callbacks=CallbackSet(user_cb))

    @test sol.retcode == ReturnCode.Success
    @test fired[]
end
