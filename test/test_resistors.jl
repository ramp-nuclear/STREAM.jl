using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM: Resistor, VolumetricFlowResistor

@testset "Cube flow matches 5/6 R analytical within 1%" begin
    R_val = 1.0e4
    dP_val = 3.0e4
    ssys = build_cube(dP_pump=dP_val, R=R_val)

    mdot_analytical = dP_val / (5.0/6.0 * R_val)

    # Symmetric cube: 3 source branches from corner 0, 3 sink branches to corner 7
    # Body-diagonal paths: each of 3 "short" 1-resistor paths carries mdot/3
    # Each of 6 "long" 2-resistor paths carries mdot/6 (edge contribution)
    # For initial guess: pump.port_out = full mdot; each direct branch ~ mdot/3
    mdot_full = mdot_analytical

    op = [
        ssys.pump.port_out.mdot => mdot_full,
        # Three source edges from corner 0
        ssys.r01.port_in.mdot => mdot_full / 3.0,
        ssys.r02.port_in.mdot => mdot_full / 3.0,
        ssys.r04.port_in.mdot => mdot_full / 3.0,
        # Internal edges (rough equal split)
        ssys.r13.port_in.mdot => mdot_full / 6.0,
        ssys.r15.port_in.mdot => mdot_full / 6.0,
        ssys.r23.port_in.mdot => mdot_full / 6.0,
        ssys.r26.port_in.mdot => mdot_full / 6.0,
        ssys.r45.port_in.mdot => mdot_full / 6.0,
        ssys.r46.port_in.mdot => mdot_full / 6.0,
        # Three sink edges to corner 7
        ssys.r37.port_in.mdot => mdot_full / 3.0,
        ssys.r57.port_in.mdot => mdot_full / 3.0,
        ssys.r67.port_in.mdot => mdot_full / 3.0,
    ]
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    mdot_numerical = abs(sol[ssys.pump.port_out.mdot])
    @test isapprox(mdot_numerical, mdot_analytical; rtol=0.01)
end

@testset "VolumetricFlowResistor — quadratic drop dP = k*mdot^2 (rho=1)" begin
    dP = 3.0e4
    k = 1.0e5
    @named pump = Pump(dP)
    @named hx = HeatExchanger(300.0)
    @named vfr = VolumetricFlowResistor(; k=k, density=1.0)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, vfr.port_in),
        connect(vfr.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:vfr_loop), pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.vfr.port_in.mdot => 0.5])
    @test sol.retcode == ReturnCode.Success
    mdot = sol[ssys.vfr.port_in.mdot]
    @test isapprox(mdot, sqrt(dP / k); rtol=1e-6)         # k*Q^2 = dP, Q = mdot (rho=1)
    @test isapprox(sol[ssys.vfr.port_in.P] - sol[ssys.vfr.port_out.P], k * mdot * abs(mdot);
                   rtol=1e-6)
end

@testset "VolumetricFlowResistor — klow linear term contributes" begin
    dP = 1.0e4
    k = 5.0e4
    klow = 2.0e3
    @named pump = Pump(dP)
    @named hx = HeatExchanger(300.0)
    @named vfr = VolumetricFlowResistor(; k=k, klow=klow, density=1.0)
    conns = [
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, vfr.port_in),
        connect(vfr.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:vfr_klow), pump, hx, vfr)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.vfr.port_in.mdot => 0.4])
    @test sol.retcode == ReturnCode.Success
    q = sol[ssys.vfr.port_in.mdot]                         # rho=1 ⇒ Q = mdot
    @test isapprox(sol[ssys.vfr.port_in.P] - sol[ssys.vfr.port_out.P],
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
