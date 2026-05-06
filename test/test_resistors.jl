using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
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
    R_val = 1.0e4
    dP_val = 3.0e4
    ssys = build_cube(dP_pump=dP_val, R=R_val)

    mdot_analytical = dP_val / (5.0/6.0 * R_val)

    # Symmetric cube: 3 source branches from corner 0, 3 sink branches to corner 7
    # Body-diagonal paths: each of 3 "short" 1-resistor paths carries mdot/3
    # Each of 6 "long" 2-resistor paths carries mdot/6 (edge contribution)
    # For initial guess: pump.outlet = full mdot; each direct branch ~ mdot/3
    mdot_full = mdot_analytical

    op = [
        ssys.pump.outlet.mdot => mdot_full,
        # Three source edges from corner 0
        ssys.r01.inlet.mdot => mdot_full / 3.0,
        ssys.r02.inlet.mdot => mdot_full / 3.0,
        ssys.r04.inlet.mdot => mdot_full / 3.0,
        # Internal edges (rough equal split)
        ssys.r13.inlet.mdot => mdot_full / 6.0,
        ssys.r15.inlet.mdot => mdot_full / 6.0,
        ssys.r23.inlet.mdot => mdot_full / 6.0,
        ssys.r26.inlet.mdot => mdot_full / 6.0,
        ssys.r45.inlet.mdot => mdot_full / 6.0,
        ssys.r46.inlet.mdot => mdot_full / 6.0,
        # Three sink edges to corner 7
        ssys.r37.inlet.mdot => mdot_full / 3.0,
        ssys.r57.inlet.mdot => mdot_full / 3.0,
        ssys.r67.inlet.mdot => mdot_full / 3.0,
    ]
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    mdot_numerical = abs(sol[ssys.pump.outlet.mdot])
    @test isapprox(mdot_numerical, mdot_analytical; rtol=0.01)
end
