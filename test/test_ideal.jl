using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Examples
using STREAM.Assemblies: var_length

@testset "Inertia stub callable" begin
    @named L = Inertia(1e3)
    @test L isa ModelingToolkit.System
end

@testset "Inertia mtkcompile" begin
    @named L = Inertia(1e3)
    @test_nowarn mtkcompile(L; fully_determined=false)  # isolated component: dangling ports
end

@testset "RL-decay transient matches exp(-(R/L_over_A)*t) within 1%" begin
    R_val = 1.0
    L_over_A = 1e3
    tau = L_over_A / R_val   # 1000 s
    ṁ0 = 1.0

    # A pump holds ṁ0 through the linear resistor, then shuts off and the flow coasts as
    # ṁ = ṁ0·exp(-(R/L)·t). Drive the loop to steady with the pump on, then start the
    # transient from the full solved state with the pump head overridden to 0. Transplanting every
    # state from the solved point keeps the IC consistent no matter which variables MTK keeps as
    # states.
    @named pump = Pump(R_val * ṁ0)   # head R·ṁ0 balances the linear drop R·ṁ at ṁ0
    @named L_comp = Inertia(L_over_A)
    @named R_comp = Resistor(R_val)
    @named hx = HeatExchanger(26.85)
    connections = [
        inseries(pump, L_comp, R_comp, hx, pump),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(connections, pump, L_comp, R_comp, hx)
    ssys = mtkcompile(sys)

    sol_ss = solve_steady(ssys, [ssys.L_comp.inlet.ṁ => ṁ0])
    @test sol_ss.retcode == ReturnCode.Success
    sol = solve_transient(ssys, sol_ss, range(0.0, 5000.0; length=200);
                          overrides=[ssys.pump.dP_pump => 0.0])

    @test sol.retcode == ReturnCode.Success
    t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
    for tc in t_check
        ṁ_num = sol(tc; idxs=ssys.L_comp.inlet.ṁ)
        ṁ_ana = exp(-tc / tau)
        @test isapprox(ṁ_num, ṁ_ana; rtol=0.01)
    end
end

@testset "HeatExchanger stub callable" begin
    @named hx = HeatExchanger(40.0)
    @test hx isa ModelingToolkit.System
end

@testset "HeatExchanger mtkcompile" begin
    @named hx = HeatExchanger(40.0)
    @test_nowarn mtkcompile(hx; fully_determined=false)  # isolated component: HX is value-source, no port closure needed
end

@testset "HeatExchanger exported from STREAM" begin
    @test isdefined(STREAM.Components, :HeatExchanger)
end

@testset "build_loop compiles after HeatExchanger rename (regression)" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "ConstantTemperature: n ports, each held at its temperature" begin
    @named wall = ConstantTemperature(40.0; n=3)
    @test var_length(wall, :thermal) == 3
    profile = [30.0, 55.0, 42.0]    # asymmetric, so a reversal or shift would show
    @named prof = ConstantTemperature(profile)
    @test var_length(prof, :thermal) == 3
    @test_throws DimensionMismatch ConstantTemperature(profile; n=4, name=:bad)

    # Tie each port of the profile to its own sink so every port carries heat.
    sinks = [ConvectiveBoundary(; area=1.0, name=Symbol(:sink, i)) for i in 1:3]
    conns = [
        face(sinks, prof, :thermal),
        [s.h for s in sinks] .~ 10.0,
        [s.T_fluid for s in sinks] .~ 20.0,
    ]
    @named s = assembly(conns, prof, sinks...)
    ss = mtkcompile(s)
    sol = solve(ODEProblem(ss, Pair[], (0.0, 1.0)), Rodas5P())
    @test sol[port(ss.prof, :thermal, :T)][end] == profile
    @test sol[port(ss.prof, :thermal, :Q)][end] ≈ -10.0 .* (profile .- 20.0)
end

@testset "ConvectiveBoundary: construction + single Q equation" begin
    @named cb = ConvectiveBoundary(; area=0.01)
    @test cb isa ModelingToolkit.System
    var_strs = string.(unknowns(cb))
    @test any(s -> occursin("h(t)", s), var_strs)
    @test any(s -> occursin("T_fluid(t)", s), var_strs)
end

@testset "ConvectiveBoundary: imposes Q = h*area*(T_wall - T_fluid)" begin
    area = 0.07 * 0.06
    h_val = 5000.0
    T_wall = 76.85
    T_fluid = 40.0
    @named cb = ConvectiveBoundary(; area=area)
    @named wall = ConstantTemperature(T_wall)
    conns = [
        connect(cb.thermal, wall.thermal1),
        cb.h ~ h_val,
        cb.T_fluid ~ T_fluid,
    ]
    @named s = assembly(conns, cb, wall)
    ss = mtkcompile(s)
    prob = ODEProblem(ss, Pair[], (0.0, 1.0))
    sol = solve(prob, Rodas5P())
    @test sol[ss.cb.thermal.Q][end] ≈ h_val * area * (T_wall - T_fluid)
end

@testset "ConvectiveBoundary: heat leaves the wall when fluid is cooler" begin
    # Q into the element is positive (heat absorbed by the fluid) when the wall is
    # hotter than the fluid; the connected wall therefore sheds heat (one-way sink).
    area = 0.02
    @named cb = ConvectiveBoundary(; area=area)
    @named wall = ConstantTemperature(46.85)
    conns = [connect(cb.thermal, wall.thermal1), cb.h ~ 4000.0, cb.T_fluid ~ 26.85]
    @named s = assembly(conns, cb, wall)
    ss = mtkcompile(s)
    sol = solve(ODEProblem(ss, Pair[], (0.0, 1.0)), Rodas5P())
    @test sol[ss.cb.thermal.Q][end] > 0.0
    @test sol[ss.wall.thermal1.Q][end] < 0.0
end
