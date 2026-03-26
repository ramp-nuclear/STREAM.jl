using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Inertia, HeatExchanger
const SciMLBase = DifferentialEquations.SciMLBase

# ─────────────────────────────────────────────────────────────────
# COMP-01: Inertia — ODE pressure-drop component
# Equation: port_in.P - port_out.P ~ L_over_A * D(mdot)
# ─────────────────────────────────────────────────────────────────
@testset "COMP-01: Inertia stub callable" begin
    @named L = Inertia(1e3)
    @test L isa ModelingToolkit.System
end

@testset "COMP-01: Inertia mtkcompile" begin
    @named L = Inertia(1e3)
    @test_nowarn mtkcompile(L; fully_determined=false)
end

@testset "COMP-01: RL-decay transient matches exp(-(R/L_over_A)*t) within 1%" begin
    # Topology: Inertia + Resistor in a closed loop (no pump)
    # IC: mdot(0) = 1.0 kg/s. Analytical: mdot(t) = exp(-t/tau), tau = L_over_A/R = 1000s
    R_val     = 1.0
    L_over_A  = 1e3
    tau       = L_over_A / R_val   # 1000 s

    @named L_comp = Inertia(L_over_A)
    @named R_comp = Resistor(R_val)
    connections = [
        connect(L_comp.port_out, R_comp.port_in),
        connect(R_comp.port_out, L_comp.port_in),
        L_comp.port_in.P ~ 1.0e5,   # pressure gauge anchor
    ]
    @named sys = compose(System(connections, t; name=:rl_sys), L_comp, R_comp)
    ssys = mtkcompile(sys; fully_determined=false)  # T eqs underdetermined (no heat exchange in RL circuit)

    # Initial condition: mdot = 1.0 kg/s
    # T variables are free (no heat exchange in RL circuit); provide ICs for all unknowns
    # check_length=false required because T unknowns are underdetermined (no T equations in pure RL circuit)
    op = [
        ssys.L_comp.port_in.mdot => 1.0,
        ssys.L_comp.port_out.T   => 300.0,
        ssys.L_comp.port_in.T    => 300.0,
    ]
    prob = ODEProblem(ssys, op, (0.0, 5000.0); warn_initialize_determined=false, check_length=false)
    sol  = solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit())

    @test sol.retcode == ReturnCode.Success
    t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
    for tc in t_check
        mdot_num = sol(tc, idxs=ssys.L_comp.port_in.mdot)
        mdot_ana = exp(-tc / tau)
        @test isapprox(mdot_num, mdot_ana; rtol=0.01)
    end
end

# ─────────────────────────────────────────────────────────────────
# COMP-02: HeatExchanger stubs (RED — implemented in Plan 02)
# ─────────────────────────────────────────────────────────────────
@testset "COMP-02: HeatExchanger stub callable" begin
    @named hx = HeatExchanger(313.15)
    @test hx isa ModelingToolkit.System
end

@testset "COMP-02: HeatExchanger mtkcompile" begin
    @named hx = HeatExchanger(313.15)
    @test_nowarn mtkcompile(hx; fully_determined=false)
end

@testset "COMP-02: HeatExchanger exported from STREAM" begin
    @test isdefined(STREAM, :HeatExchanger)
end

@testset "COMP-02: build_loop compiles after HeatExchanger rename (regression)" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
end
