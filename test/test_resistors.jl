using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Resistor

# ─────────────────────────────────────────────────────────────────
# NET-01: Resistor component — linear pressure drop dp ~ R * mdot
# ─────────────────────────────────────────────────────────────────
@testset "NET-01: Resistor stub callable" begin
    @named r = Resistor(1.0e5)
    @test r isa ModelingToolkit.System
end

@testset "NET-01: Resistor mtkcompile" begin
    @named r = Resistor(1.0e5)
    @test_nowarn mtkcompile(r; fully_determined=false)
end


# ─────────────────────────────────────────────────────────────────
# NET-02: Cube problem — 12 Resistors + 1 Pump assembled via multi-port connect()
# Topology: 8 corners (0-7 binary), 12 edges, pump drives corner 0 -> corner 7
# ─────────────────────────────────────────────────────────────────
@testset "NET-02: build_cube assembles and mtkcompiles" begin
    ssys = build_cube()
    @test ssys isa ModelingToolkit.AbstractSystem
end

# ─────────────────────────────────────────────────────────────────
# NET-03: Cube flow distribution matches analytical 5/6 R equivalent resistance
# Analytical: R_eq = 5/6 * R => mdot_total = dP_pump / (5/6 * R)
# Tolerance: 1% (consistent with GRAV-02 and VAL-01)
# ─────────────────────────────────────────────────────────────────
@testset "NET-03: Cube flow matches 5/6 R analytical within 1%" begin
    R_val    = 1.0e4
    dP_val   = 3.0e4
    ssys = build_cube(dP_pump=dP_val, R=R_val)

    mdot_analytical = dP_val / (5.0/6.0 * R_val)
    mdot_guess = mdot_analytical / 3.0   # each source branch carries ~1/3

    op = [ssys.pump.port_out.mdot => mdot_guess]
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    mdot_numerical = abs(sol[ssys.pump.port_out.mdot])
    @test isapprox(mdot_numerical, mdot_analytical; rtol=0.01)
end
