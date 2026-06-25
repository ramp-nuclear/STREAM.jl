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
    mdot0 = 1.0

    # A pump holds mdot0 through the linear resistor, then shuts off and the flow coasts as
    # ṁ = mdot0·exp(-(R/L)·t). Drive the loop to steady with the pump on, then start the
    # transient from the full solved state with the pump head overridden to 0. Transplanting every
    # state from the solved point keeps the IC consistent no matter which variables MTK keeps as
    # states.
    @named pump = Pump(R_val * mdot0)   # head R·mdot0 balances the linear drop R·ṁ at mdot0
    @named L_comp = Inertia(L_over_A)
    @named R_comp = Resistor(R_val)
    @named hx = HeatExchanger(300.0)
    connections = [
        connect(pump.outlet, L_comp.inlet),
        connect(L_comp.outlet, R_comp.inlet),
        connect(R_comp.outlet, hx.inlet),
        connect(hx.outlet, pump.inlet),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = compose(System(connections, t; name=:rl_sys), pump, L_comp, R_comp, hx)
    ssys = mtkcompile(sys)

    sol_ss = solve_steady(ssys, [ssys.L_comp.inlet.ṁ => mdot0])
    @test sol_ss.retcode == ReturnCode.Success
    sol = solve_transient(ssys, sol_ss, range(0.0, 5000.0; length=200);
                          overrides=[ssys.pump.dP_pump => 0.0])

    @test sol.retcode == ReturnCode.Success
    t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
    for tc in t_check
        mdot_num = sol(tc; idxs=ssys.L_comp.inlet.ṁ)
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

# Helper: solve a portless value source in isolation and read back the per-cell
# output it emits. The compiled system has no unknowns (every output is a pure
# algebraic RHS that mtkcompile lifts into observed), so a trivial solve just
# evaluates those observed quantities. Returns the n emitted values at the final
# saved point.
function _emitted(ssys, out, n; op=Pair[], tspan=(0.0, 1.0))
    sol = solve(ODEProblem(ssys, op, tspan), Rodas5P())
    return [sol[out[i]][end] for i in 1:n]
end

@testset "WallTemperature Real broadcast emits the scalar to every cell" begin
    n = 4
    @named wt = WallTemperature(; n=n, T_wall=350.0)
    @test wt isa ModelingToolkit.System
    var_names = string.(unknowns(wt))
    twl_count = count(s -> occursin("T_wall_out", s), var_names)
    @test twl_count == n
    @test length(equations(wt)) == n

    ssys = mtkcompile(wt; fully_determined=false)
    emitted = _emitted(ssys, ssys.T_wall_out, n)
    @test emitted == fill(350.0, n)
end

@testset "WallTemperature Vector emits the i-th element at cell i" begin
    n = 4
    # An asymmetric, non-monotone profile so a transpose, a reversal, or an
    # off-by-one would shift at least one cell and fail the exact match.
    profile = [301.0, 422.0, 333.0, 414.0]
    @named wt = WallTemperature(; n=n, T_wall=profile)
    @test wt isa ModelingToolkit.System
    @test length(equations(wt)) == n

    ssys = mtkcompile(wt; fully_determined=false)
    emitted = _emitted(ssys, ssys.T_wall_out, n)
    @test emitted == profile
    @test all(emitted[i] == profile[i] for i in 1:n)
end

@testset "WallTemperature Vector length mismatch errors" begin
    n = 4
    @test_throws DimensionMismatch WallTemperature(; name=:bad, n=n, T_wall=collect(1.0:3.0))
    @test_throws DimensionMismatch WallTemperature(; name=:bad, n=n, T_wall=collect(1.0:5.0))
end

@testset "WallTemperature Function emits f(t) at every cell" begin
    n = 4
    fn = (tt) -> 350.0 + 10.0 * tt   # linear so the read-back value is exact
    @named wt = WallTemperature(; n=n, T_wall=fn)
    @test wt isa ModelingToolkit.System
    @test length(equations(wt)) == n
    par_strs = string.(parameters(wt))
    @test any(s -> occursin("T_wall_fn", s), par_strs)

    ssys = mtkcompile(wt; fully_determined=false)
    t_eval = 2.0
    sol = solve(ODEProblem(ssys, [ssys.T_wall_fn => fn], (0.0, 3.0)), Rodas5P())
    @test all(sol(t_eval; idxs=ssys.T_wall_out[i]) == fn(t_eval) for i in 1:n)   # 370.0
    # Read at a second time to confirm the cells track the callable, not a frozen value.
    @test sol(0.5; idxs=ssys.T_wall_out[1]) == fn(0.5)             # 355.0
end

@testset "HeatFluxSource Real broadcast emits the scalar to every cell" begin
    n = 4
    @named hfs = HeatFluxSource(; n=n, q=1.0e5)
    @test hfs isa ModelingToolkit.System
    var_names = string.(unknowns(hfs))
    q_count = count(s -> occursin("q_out", s), var_names)
    @test q_count == n
    @test length(equations(hfs)) == n

    ssys = mtkcompile(hfs; fully_determined=false)
    emitted = _emitted(ssys, ssys.q_out, n)
    @test emitted == fill(1.0e5, n)
end

@testset "HeatFluxSource Vector emits the i-th element at cell i" begin
    n = 4
    # Asymmetric, non-monotone so a transpose / reversal / off-by-one is caught.
    profile = [1.0e4, 7.0e4, 3.0e4, 9.0e4]
    @named hfs = HeatFluxSource(; n=n, q=profile)
    @test hfs isa ModelingToolkit.System
    @test length(equations(hfs)) == n

    ssys = mtkcompile(hfs; fully_determined=false)
    emitted = _emitted(ssys, ssys.q_out, n)
    @test emitted == profile
    @test all(emitted[i] == profile[i] for i in 1:n)
end

@testset "HeatFluxSource Function emits f(t) at every cell" begin
    n = 4
    fn = (tt) -> 1.0e5 * (1.0 + 0.1 * tt)   # linear so the read-back is exact
    @named hfs = HeatFluxSource(; n=n, q=fn)
    @test hfs isa ModelingToolkit.System
    @test length(equations(hfs)) == n
    par_strs = string.(parameters(hfs))
    @test any(s -> occursin("q_fn", s), par_strs)

    ssys = mtkcompile(hfs; fully_determined=false)
    t_eval = 3.0
    sol = solve(ODEProblem(ssys, [ssys.q_fn => fn], (0.0, 4.0)), Rodas5P())
    @test all(sol(t_eval; idxs=ssys.q_out[i]) == fn(t_eval) for i in 1:n)   # 1.3e5
    @test sol(1.0; idxs=ssys.q_out[1]) == fn(1.0)             # 1.1e5
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
    T_wall = 350.0
    T_fluid = 313.15
    @named cb = ConvectiveBoundary(; area=area)
    @named wall = ConstantTemperature(T_wall)
    conns = [
        connect(cb.thermal, wall.thermal),
        cb.h ~ h_val,
        cb.T_fluid ~ T_fluid,
    ]
    @named s = compose(System(conns, t; name=:cbtest), cb, wall)
    ss = mtkcompile(s; fully_determined=true)
    prob = ODEProblem(ss, Pair[], (0.0, 1.0))
    sol = solve(prob, Rodas5P())
    @test sol[ss.cb.thermal.Q][end] ≈ h_val * area * (T_wall - T_fluid)
end

@testset "ConvectiveBoundary: heat leaves the wall when fluid is cooler" begin
    # Q into the element is positive (heat absorbed by the fluid) when the wall is
    # hotter than the fluid; the connected wall therefore sheds heat (one-way sink).
    area = 0.02
    @named cb = ConvectiveBoundary(; area=area)
    @named wall = ConstantTemperature(320.0)
    conns = [connect(cb.thermal, wall.thermal), cb.h ~ 4000.0, cb.T_fluid ~ 300.0]
    @named s = compose(System(conns, t; name=:cbsign), cb, wall)
    ss = mtkcompile(s; fully_determined=true)
    sol = solve(ODEProblem(ss, Pair[], (0.0, 1.0)), Rodas5P())
    @test sol[ss.cb.thermal.Q][end] > 0.0
    @test sol[ss.wall.thermal.Q][end] < 0.0
end
