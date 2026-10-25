using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components

@testset "a cube of equal resistors is 5/6 R between opposite corners" begin
    # Corners 0 to 7, an edge wherever two corner numbers differ in one bit, and flow from
    # corner 0 to corner 7. By symmetry the flow splits in three leaving corner 0, in two at
    # the next corners, and joins in threes at corner 7.
    R, dP = 1.0e4, 3.0e4
    @named pump = Pump(dP)
    edges = [(i, j) for i in 0:7 for j in (i + 1):7 if count_ones(i ⊻ j) == 1]
    r = Dict(e => Resistor(R; name=Symbol(:r, e...)) for e in edges)
    corner(k) = connect(
        (k == 0 ? [pump.outlet] : [])..., (k == 7 ? [pump.inlet] : [])...,
        (r[e].outlet for e in edges if e[2] == k)..., (r[e].inlet for e in edges if e[1] == k)...,
    )
    @named sys = assembly([corner.(0:7); pump.inlet.p ~ 1.0e5], pump, values(r)...)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success

    ṁ = dP / (5 / 6 * R)
    @test sol[ssys.pump.inlet.ṁ] ≈ ṁ rtol = 1e-6
    share(e) = 0 in e || 7 in e ? 1 / 3 : 1 / 6
    @test [sol[getproperty(ssys, Symbol(:r, e...)).inlet.ṁ] for e in edges] ≈ ṁ .* share.(edges) rtol = 1e-6
end

@testset "VolumetricFlowResistor — quadratic drop dP = k*ṁ^2 (rho=1)" begin
    dP = 3.0e4
    k = 1.0e5
    @named pump = Pump(dP)
    @named hx = HeatExchanger(26.85)
    @named vfr = VolumetricFlowResistor(; k=k, density=1.0)
    conns = [
        inseries(pump, hx, vfr, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(conns, pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)
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
        inseries(pump, hx, vfr, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(conns, pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)
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
        inseries(pump, hx, vfr, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(conns, pump, hx, vfr)
    ssys = mtkcompile(sys)

    # The loop is purely algebraic in flow (no inertia), so the flow tracks the instantaneous
    # k(t): at each t, k(t)*Q*|Q| = dP_head. Solve the steady balance at t=0, then integrate
    # the transient with k_fn active.
    # DynamicSS(Rodas5P()): this loop is purely algebraic in the flow (no inertia), and the
    # default steady solver goes unstable relaxing it; the stiff explicit relaxation settles
    # cleanly (same choice as the callable-pump ramp test).
    sol_ss = solve_steady(ssys, [ssys.vfr.k_fn => k_hold]; solver=DynamicSS(Rodas5P()))
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
        inseries(pump, hx, lpd, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(conns, pump, hx, lpd)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    A = min(A1, A2)
    f = STREAM.LocalLoss.factor(ṁ, A1, A2, μ(H2O, Tin))
    dp_expected = f * ṁ * abs(ṁ) / (2 * ρ(H2O, Tin) * A^2)
    @test isapprox(sol[ssys.lpd.inlet.p] - sol[ssys.lpd.outlet.p], dp_expected; rtol=1e-6)
    @test dp_expected > 0.0   # forward flow drops pressure
end

@testset "ResistorFromKnownPoint reproduces its known point" begin
    # Apply a head across the resistor at a fixed coolant temperature and read the flow it
    # passes. A head of -dp has to drive exactly the known ṁ.
    function flow_through(make_resistor; head, T, guess)
        @named pump = Pump(head)
        @named hx = HeatExchanger(T)
        r = make_resistor(:r)
        conns = [inseries(pump, hx, r, pump), pump.inlet.p ~ 1.0e5]
        @named sys = assembly(conns, pump, hx, r)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys)
        @test sol.retcode == ReturnCode.Success
        return sol[ssys.r.inlet.ṁ]
    end

    dp, ṁ, T = -2.0e4, 0.3, 40.0
    parabolic(name) = ResistorFromKnownPoint(; name=name, dp=dp, ṁ=ṁ, T=T)
    @test flow_through(parabolic; head=-dp, T=T, guess=0.1) ≈ ṁ rtol = 1e-8

    # Away from the known temperature the drop scales with 1/ρ, so the flow with √ρ.
    T_hot = 80.0
    @test flow_through(parabolic; head=-dp, T=T_hot, guess=0.1) ≈
        ṁ * sqrt(ρ(H2O, T_hot) / ρ(H2O, T)) rtol = 1e-8

    # Direction-correct: a reversed head drives the known flow backwards.
    @test flow_through(parabolic; head=dp, T=T, guess=-0.1) ≈ -ṁ rtol = 1e-8

    # Python's doctest: linear through (-1 Pa, 1 kg/s) gives -3 Pa at 3 kg/s. Read the other
    # way, a 3 Pa head drives 3 kg/s.
    linear(name) = ResistorFromKnownPoint(; name=name, dp=-1.0, ṁ=1.0, behavior=:linear)
    @test flow_through(linear; head=3.0, T=T, guess=1.0) ≈ 3.0 rtol = 1e-10

    @testset "arguments it cannot use are rejected" begin
        @test_throws ArgumentError ResistorFromKnownPoint(; name=:r)
        @test_throws ArgumentError ResistorFromKnownPoint(; name=:r, dp=1.0, ṁ=1.0, T=40.0)
        @test_throws ArgumentError ResistorFromKnownPoint(; name=:r, dp=-1.0, ṁ=1.0)
        @test_throws ArgumentError ResistorFromKnownPoint(;
            name=:r, dp=-1.0, behavior=:linear
        )
        @test_throws ArgumentError ResistorFromKnownPoint(;
            name=:r, dp=-1.0, ṁ=1.0, behavior=:cubic
        )
        # Constant is a source rather than a resistor.
        @test ResistorFromKnownPoint(; name=:c, dp=-1.0, behavior=:constant) isa
            ModelingToolkit.System
    end
end
