using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Resistor

@testset "NET-03: Cube flow matches 5/6 R analytical within 1%" begin
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
