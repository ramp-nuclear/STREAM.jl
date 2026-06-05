using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM: Inertia, HeatExchanger, WallTemperature, HeatFluxSource

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

    @named L_comp = Inertia(L_over_A)
    @named R_comp = Resistor(R_val)
    connections = [
        connect(L_comp.port_out, R_comp.port_in),
        connect(R_comp.port_out, L_comp.port_in),
        L_comp.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(connections, t; name=:rl_sys), L_comp, R_comp)
    ssys = mtkcompile(sys; fully_determined=false)


    op = [
        ssys.L_comp.port_in.mdot => 1.0,
        ssys.L_comp.port_out.T => 300.0,
        ssys.L_comp.port_in.T => 300.0,
    ]
    prob = ODEProblem(
        ssys, op, (0.0, 5000.0); warn_initialize_determined=false, check_length=false
    )
    sol = solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit())

    @test sol.retcode == ReturnCode.Success
    t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
    for tc in t_check
        mdot_num = sol(tc, idxs=ssys.L_comp.port_in.mdot)
        mdot_ana = exp(-tc / tau)
        @test isapprox(mdot_num, mdot_ana; rtol=0.01)
    end
end

@testset "HeatExchanger stub callable" begin
    @named hx = HeatExchanger(313.15)
    @test hx isa ModelingToolkit.System
end

@testset "HeatExchanger mtkcompile" begin
    @named hx = HeatExchanger(313.15)
    @test_nowarn mtkcompile(hx; fully_determined=false)  # isolated component: HX is value-source, no port closure needed
end

@testset "HeatExchanger exported from STREAM" begin
    @test isdefined(STREAM, :HeatExchanger)
end

@testset "build_loop compiles after HeatExchanger rename (regression)" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "WallTemperature: Real (broadcast) instantiation" begin
    n = 4
    @named wt = WallTemperature(; n=n, T_wall=350.0)
    @test wt isa ModelingToolkit.System
    var_names = string.(unknowns(wt))
    twl_count = count(s -> occursin("T_wall_out", s), var_names)
    @test twl_count == n
    eqs = equations(wt)
    @test length(eqs) == n
end

@testset "WallTemperature: Vector instantiation + per-cell binding" begin
    n = 4
    profile = collect(range(300.0, 400.0, length=n))
    @named wt = WallTemperature(; n=n, T_wall=profile)
    @test wt isa ModelingToolkit.System
    eqs = equations(wt)
    @test length(eqs) == n
end

@testset "WallTemperature: Vector length mismatch errors" begin
    n = 4
    @test_throws DimensionMismatch WallTemperature(; name=:bad, n=n, T_wall=collect(1.0:3.0))
    @test_throws DimensionMismatch WallTemperature(; name=:bad, n=n, T_wall=collect(1.0:5.0))
end

@testset "WallTemperature: Function (callable parameter) instantiation" begin
    n = 4
    fn = (t) -> 350.0 + 10.0 * sin(t)
    @named wt = WallTemperature(; n=n, T_wall=fn)
    @test wt isa ModelingToolkit.System
    eqs = equations(wt)
    @test length(eqs) == n
    par_strs = string.(parameters(wt))
    @test any(s -> occursin("T_wall_fn", s), par_strs)
end

@testset "WallTemperature: mtkcompile in isolation succeeds (Real branch)" begin
    n = 4
    @named wt = WallTemperature(; n=n, T_wall=350.0)
    ssys = mtkcompile(wt; fully_determined=false)
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "HeatFluxSource: Real (broadcast) instantiation" begin
    n = 4
    @named hfs = HeatFluxSource(; n=n, q=1.0e5)
    @test hfs isa ModelingToolkit.System
    var_names = string.(unknowns(hfs))
    q_count = count(s -> occursin("q_out", s), var_names)
    @test q_count == n
    eqs = equations(hfs)
    @test length(eqs) == n
end

@testset "HeatFluxSource: Vector instantiation + per-cell binding" begin
    n = 4
    profile = collect(range(1.0e4, 1.0e5, length=n))
    @named hfs = HeatFluxSource(; n=n, q=profile)
    @test hfs isa ModelingToolkit.System
    eqs = equations(hfs)
    @test length(eqs) == n
end


@testset "HeatFluxSource: Function (callable parameter) instantiation" begin
    n = 4
    fn = (t) -> 1.0e5 * (1.0 + 0.1 * cos(t))
    @named hfs = HeatFluxSource(; n=n, q=fn)
    @test hfs isa ModelingToolkit.System
    eqs = equations(hfs)
    @test length(eqs) == n
    par_strs = string.(parameters(hfs))
    @test any(s -> occursin("q_fn", s), par_strs)
end

@testset "HeatFluxSource: mtkcompile in isolation succeeds (Real branch)" begin
    n = 4
    @named hfs = HeatFluxSource(; n=n, q=1.0e5)
    ssys = mtkcompile(hfs; fully_determined=false)  # isolated component: value-source, only RHS-driven port equations
    @test ssys isa ModelingToolkit.AbstractSystem
end
