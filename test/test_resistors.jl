using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Examples

@testset "Cube flow matches 5/6 R analytical within 1%" begin
    R_val = 1.0e4
    dP_val = 3.0e4
    ssys = build_cube(dP_pump=dP_val, R=R_val)

    ṁ_analytical = dP_val / (5.0 / 6.0 * R_val)

    # Symmetric cube: 3 source branches from corner 0, 3 sink branches to corner 7
    # Body-diagonal paths: each of 3 "short" 1-resistor paths carries ṁ/3
    # Each of 6 "long" 2-resistor paths carries ṁ/6 (edge contribution)
    # For initial guess: pump.outlet = full ṁ; each direct branch ~ ṁ/3
    ṁ_full = ṁ_analytical

    op = [
        ssys.pump.outlet.ṁ => ṁ_full,
        # Three source edges from corner 0
        ssys.r01.inlet.ṁ => ṁ_full / 3.0,
        ssys.r02.inlet.ṁ => ṁ_full / 3.0,
        ssys.r04.inlet.ṁ => ṁ_full / 3.0,
        # Internal edges (rough equal split)
        ssys.r13.inlet.ṁ => ṁ_full / 6.0,
        ssys.r15.inlet.ṁ => ṁ_full / 6.0,
        ssys.r23.inlet.ṁ => ṁ_full / 6.0,
        ssys.r26.inlet.ṁ => ṁ_full / 6.0,
        ssys.r45.inlet.ṁ => ṁ_full / 6.0,
        ssys.r46.inlet.ṁ => ṁ_full / 6.0,
        # Three sink edges to corner 7
        ssys.r37.inlet.ṁ => ṁ_full / 3.0,
        ssys.r57.inlet.ṁ => ṁ_full / 3.0,
        ssys.r67.inlet.ṁ => ṁ_full / 3.0,
    ]
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    ṁ_numerical = abs(sol[ssys.pump.outlet.ṁ])
    @test isapprox(ṁ_numerical, ṁ_analytical; rtol=0.01)
end

@testset "VolumetricFlowResistor — quadratic drop dP = k*ṁ^2 (rho=1)" begin
    dP = 3.0e4
    k = 1.0e5
    @named pump = Pump(dP)
    @named hx = HeatExchanger(26.85)
    @named vfr = VolumetricFlowResistor(; k=k, density=1.0)
    conns = [
        inseries(pump, hx, vfr, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:vfr_loop), pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.vfr.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    ṁ = sol[ssys.vfr.inlet.ṁ]
    @test isapprox(ṁ, sqrt(dP / k); rtol=1e-6)         # k*Q^2 = dP, Q = ṁ (rho=1)
    @test isapprox(
        sol[ssys.vfr.inlet.p] - sol[ssys.vfr.outlet.p],
        k * ṁ * abs(ṁ);
                   rtol=1e-6)
end

@testset "VolumetricFlowResistor — klow linear term contributes" begin
    dP = 1.0e4
    k = 5.0e4
    klow = 2.0e3
    @named pump = Pump(dP)
    @named hx = HeatExchanger(26.85)
    @named vfr = VolumetricFlowResistor(; k=k, klow=klow, density=1.0)
    conns = [
        inseries(pump, hx, vfr, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:vfr_klow), pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.vfr.inlet.ṁ => 0.4])
    @test sol.retcode == ReturnCode.Success
    q = sol[ssys.vfr.inlet.ṁ]                         # rho=1 ⇒ Q = ṁ
    @test isapprox(
        sol[ssys.vfr.inlet.p] - sol[ssys.vfr.outlet.p],
                   k * q * abs(q) + klow * q; rtol=1e-6)
    @test isapprox(k * q^2 + klow * q, dP; rtol=1e-6)      # closed-form force balance
end

@testset "VolumetricFlowResistor — callable k (transistor pattern) compiles with k_fn" begin
    kfn = (t) -> 1.0e5 * (1.0 + t)
    @named vfr = VolumetricFlowResistor(; k=kfn, density=1.0)
    @test vfr isa ModelingToolkit.System
    par_strs = string.(parameters(vfr))
    @test any(s -> occursin("k_fn", s), par_strs)
end

@testset "VolumetricFlowResistor callable k makes the resistance rise with time" begin
    # The "transistor pattern" name promises the resistance varies in time. Drive a fixed-dP
    # loop with k_fn(t) = k0*(1+t) and run a transient: as k(t) climbs, the quadratic drop
    # dP = k(t)*Q*|Q| at fixed pump head forces the flow down. Check the defining relation
    # dP = k_fn(t)*q*|q| holds at two distinct times AND that the flow actually fell, so the
    # time-varying behavior the name evokes is exercised, not just compiled.
    dP_head = 3.0e4   # Pa, fixed pump head
    k0 = 1.0e5        # Pa*s^2/kg^2 at t=0 (density=1 -> Q = ṁ)
    # Build the ramp and the constant seed from one factory so they share a closure type.
    # The resistor stores k as an MTK callable parameter typed to the function it was built
    # with, so the steady-solve seed and the transient override must be the same type to be
    # interchangeable in the operating point (same gotcha as the callable-pump ramp test).
    make_k = rate -> (tt -> k0 * (1.0 + rate * tt))
    kfn = make_k(1.0)     # the ramp k0*(1+t)
    k_hold = make_k(0.0)  # constant k0, for the steady seed

    @named pump = Pump(dP_head)
    @named hx = HeatExchanger(26.85)
    @named vfr = VolumetricFlowResistor(; k=kfn, density=1.0)
    conns = [
        inseries(pump, hx, vfr, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:vfr_kfn_loop), pump, hx, vfr)
    ssys = mtkcompile(sys)

    # The loop is purely algebraic in flow (no inertia), so the flow tracks the instantaneous
    # k(t): at each t, k(t)*Q*|Q| = dP_head. Seed and solve the steady balance at t=0, then
    # integrate the transient with k_fn active. Q(t=0) = sqrt(dP/k0).
    q0 = sqrt(dP_head / k0)
    # DynamicSS(Rodas5P()): this loop is purely algebraic in the flow (no inertia), and the
    # default steady solver goes unstable relaxing it; the stiff explicit relaxation settles
    # cleanly (same choice as the callable-pump ramp test).
    sol_ss = solve_steady(
        ssys,
        Pair{Any,Any}[ssys.vfr.inlet.ṁ => q0, ssys.vfr.k_fn => k_hold];
        solver=DynamicSS(Rodas5P()),
    )
    @test sol_ss.retcode == ReturnCode.Success

    t_arr = range(0.0, 3.0; length=4)
    sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.vfr.k_fn => kfn])
    @test sol.retcode == ReturnCode.Success

    # Defining relation at two distinct times: the measured drop equals k_fn(t)*q*|q|.
    # rtol=1e-4 because q here is a transient-integrated state carrying the Rodas5P solver's
    # reltol (1e-6) and the algebraic dP is reconstructed from it, so a few-ppm residual is
    # expected; 1e-4 stays far tighter than the 4x resistance change being verified.
    for ti in (2, length(t_arr))
        tt = t_arr[ti]
        q = sol[ssys.vfr.inlet.ṁ, ti]
        dP_meas = sol[ssys.vfr.inlet.p, ti] - sol[ssys.vfr.outlet.p, ti]
        @test isapprox(dP_meas, kfn(tt) * q * abs(q); rtol=1e-4)
        # And the flow magnitude matches the closed form sqrt(dP_head / k(t)).
        @test isapprox(abs(q), sqrt(dP_head / kfn(tt)); rtol=1e-4)
    end

    # The time-varying resistance must drive the flow strictly down between the first and
    # last sample (k roughly quadruples from t=0 to t=3, so Q halves).
    q_first = abs(sol[ssys.vfr.inlet.ṁ, 1])
    q_last = abs(sol[ssys.vfr.inlet.ṁ, length(t_arr)])
    @test q_last < q_first
    @test isapprox(q_last / q_first, sqrt(kfn(0.0) / kfn(t_arr[end])); rtol=1e-4)
end

@testset "LocalPressureDrop — sudden expansion ΔP matches Idelchik closed form" begin
    A1, A2 = 1.0, 2.0
    Tin = 20.0
    ṁ = 3.0
    @named pump = Pump(; ṁ0=ṁ)        # fixed-flow so ṁ is exact
    @named hx = HeatExchanger(Tin)
    @named lpd = LocalPressureDrop(; A1=A1, A2=A2)
    conns = [
        inseries(pump, hx, lpd, pump)...,
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:lpd_loop), pump, hx, lpd)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.lpd.inlet.ṁ => ṁ])
    @test sol.retcode == ReturnCode.Success
    A = min(A1, A2)
    f = STREAM.LocalLoss.factor(ṁ, A1, A2, μ(H2O, Tin))
    dp_expected = f * ṁ * abs(ṁ) / (2 * ρ(H2O, Tin) * A^2)
    @test isapprox(sol[ssys.lpd.inlet.p] - sol[ssys.lpd.outlet.p], dp_expected; rtol=1e-6)
    @test dp_expected > 0.0   # forward flow drops pressure
end
