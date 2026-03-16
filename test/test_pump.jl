using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Pump, Channel

# ─────────────────────────────────────────────────────────────────
# PHY-05: Pump fixed-flow mode (mdot0 dispatch)
# ─────────────────────────────────────────────────────────────────
@testset "PHY-05: Pump fixed-flow mode" begin
    # Test: Pump(mdot0=0.6) is callable and assembles as a System
    @named pump = Pump(mdot0=0.6)
    @test pump isa ModelingToolkit.System

    # Test: Pump(mdot0=0.6) mtkcompiles without error (bare, no connections)
    # fully_determined=false: isolated ports make system under-determined
    @test_nowarn mtkcompile(pump; fully_determined=false)

    # Test: Integration — Pump(mdot0=0.6) in a loop: Pump → HeatExchanger → Channel → back
    # HeatExchanger provides pressure closure (port_in.P - port_out.P ~ 0)
    # pump.port_in.P ~ 1e5 provides absolute pressure reference
    @named pump5  = Pump(mdot0=0.6)
    @named bc5    = HeatExchanger(T_bc=313.15)
    @named ch5    = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
    conns5 = [
        connect(pump5.port_out, bc5.port_in),
        connect(bc5.port_out,   ch5.port_in),
        connect(ch5.port_out,   pump5.port_in),
        pump5.port_in.P ~ 1e5,
        ch5.port_in.T  ~ 313.15,
        ch5.thermal.T  ~ 350.0,   # pin wall temperature (adiabatic not needed; mdot0 drives flow)
    ]
    @named sys5 = compose(System(conns5, t; name=:phy05_loop), pump5, bc5, ch5)
    ssys5 = mtkcompile(sys5; fully_determined=false)
    op5 = [ssys5.ch5.T[i] => 313.15 for i in 1:5]
    sol5 = solve_steady(ssys5, op5)
    @test sol5.retcode == ReturnCode.Success
    @test isapprox(sol5[ssys5.pump5.port_in.mdot], 0.6; rtol=1e-4)
end

@testset "PHY-05: Pump error cases" begin
    # Both args specified — must throw
    @test_throws ErrorException Pump(name=:p, dP_pump=1e5, mdot0=0.6)
    # No args — must throw
    @test_throws ErrorException Pump(name=:p)
end
