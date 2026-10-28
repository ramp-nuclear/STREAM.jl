using Test
using ModelingToolkit
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components

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

const HX_T_HOT, HX_T_COLD = 80.0, 30.0
const HX_UA = 2.0e4

"""
    hx_loops(hx; dPp=2.0, dPs=4.0) -> System

Two loops joined by the two-stream exchanger `hx`. Each is a pump, an ideal `HeatExchanger`
that sets the temperature arriving at its side of `hx`, and a unit resistor, so the flows are
`dPp` and `dPs` [kg/s].
"""
function hx_loops(hx; dPp=2.0, dPs=4.0)
    @assembly sys begin
        pp = Pump(dPp)
        rp = Resistor(1.0)
        hot = HeatExchanger(HX_T_HOT)
        ps = Pump(dPs)
        rs = Resistor(1.0)
        cold = HeatExchanger(HX_T_COLD)
        pp --> hot --> hx.primary --> rp --> pp
        pp.inlet.p ~ 1.0e5
        ps --> cold --> hx.secondary --> rs --> ps
        ps.inlet.p ~ 2.0e5
    end
end

"""
    hand_hx(arrangement, ṁp, ṁs; UA=HX_UA) -> (Q, Tp_out, Ts_out)

The effectiveness-NTU answer for the loops of `hx_loops`, worked out without the model.
"""
function hand_hx(arrangement, ṁp, ṁs; UA=HX_UA)
    Cp, Cs = abs(ṁp) * cₚ(H2O, HX_T_HOT), abs(ṁs) * cₚ(H2O, HX_T_COLD)
    C_min, C_max = minmax(Cp, Cs)
    ε = HTC.effectiveness(arrangement, UA / C_min, C_min / C_max)
    Q = ε * C_min * (HX_T_COLD - HX_T_HOT)
    return Q, HX_T_HOT + Q / Cp, HX_T_COLD - Q / Cs
end

"""
    lmtd(ΔT1, ΔT2)

Log-mean temperature difference of the two end differences.
"""
lmtd(ΔT1, ΔT2) = (ΔT1 - ΔT2) / log(ΔT1 / ΔT2)

@testset "two-stream HeatExchanger" begin
    Q_by = Dict()
    for arr in (HTC.Counterflow(), HTC.ParallelFlow())
        @testset "$(nameof(typeof(arr))): outlets match ε-NTU" begin
            @named hx = HeatExchanger(; UA=HX_UA, arrangement=arr)
            ssys = hx_loops(hx)
            sol = solve_steady(ssys)
            @test SciMLBase.successful_retcode(sol)

            Q, Tp_out, Ts_out = hand_hx(arr, 2.0, 4.0)
            @test sol[ssys.hx.Q] ≈ Q rtol = 1e-8
            @test sol[ssys.hx.primary.outlet.T] ≈ Tp_out rtol = 1e-8
            @test sol[ssys.hx.secondary.outlet.T] ≈ Ts_out rtol = 1e-8
            Q_by[arr] = sol[ssys.hx.Q]

            # The same heat from the textbook LMTD, with its end differences taken from the
            # solved temperatures.
            ΔT1, ΔT2 = arr isa HTC.Counterflow ?
                (HX_T_HOT - Ts_out, Tp_out - HX_T_COLD) :
                (HX_T_HOT - HX_T_COLD, Tp_out - Ts_out)
            @test -sol[ssys.hx.Q] ≈ HX_UA * lmtd(ΔT1, ΔT2) rtol = 1e-8

            # What one side loses the other gains.
            @test sol[ssys.hx.primary.C] * sol[ssys.hx.primary.ΔT] ≈
                  -sol[ssys.hx.secondary.C] * sol[ssys.hx.secondary.ΔT] rtol = 1e-10
        end
    end
    @test abs(Q_by[HTC.Counterflow()]) > abs(Q_by[HTC.ParallelFlow()])

    @testset "no secondary flow, no heat removed" begin
        @named hx = HeatExchanger(; UA=HX_UA)
        ssys = hx_loops(hx; dPs=0.0)
        sol = solve_steady(ssys)
        @test SciMLBase.successful_retcode(sol)
        @test abs(sol[ssys.hx.Q]) < 1e-3
        @test sol[ssys.hx.primary.outlet.T] ≈ HX_T_HOT atol = 1e-6
    end

    @testset "reversed primary turns counterflow into parallel flow" begin
        @named hx = HeatExchanger(; UA=HX_UA, arrangement=HTC.Counterflow())
        ssys = hx_loops(hx; dPp=-2.0)
        sol = solve_steady(ssys)
        @test SciMLBase.successful_retcode(sol)
        @test sol[ssys.hx.primary.inlet.ṁ] ≈ -2.0
        @test sol[ssys.hx.primary.T_in] ≈ HX_T_HOT
        Q, Tp_out, _ = hand_hx(HTC.ParallelFlow(), -2.0, 4.0)
        @test sol[ssys.hx.Q] ≈ Q rtol = 1e-8
        # Reversed, the primary leaves through its inlet port.
        @test sol[ssys.hx.primary.inlet.T] ≈ Tp_out rtol = 1e-8
    end

    @testset "UA is a parameter a solve can override" begin
        @named hx = HeatExchanger(; UA=HX_UA)
        ssys = hx_loops(hx)
        sol = solve_steady(ssys, [ssys.hx.UA => 5.0e3])
        @test sol[ssys.hx.Q] ≈ first(hand_hx(HTC.Counterflow(), 2.0, 4.0; UA=5.0e3)) rtol = 1e-8
    end

    @testset "flow_scaled_UA is UA0 at the design flows" begin
        @named hx = HeatExchanger(; UA=HTC.flow_scaled_UA(HX_UA, 2.0, 4.0))
        ssys = hx_loops(hx)
        sol = solve_steady(ssys)
        @test sol[ssys.hx.UA_eff] ≈ HX_UA rtol = 1e-10
        @test sol[ssys.hx.Q] ≈ first(hand_hx(HTC.Counterflow(), 2.0, 4.0)) rtol = 1e-8

        # Half the secondary flow lowers UA, and less heat crosses than at fixed UA.
        ssys = hx_loops(hx; dPs=2.0)
        sol = solve_steady(ssys)
        @test sol[ssys.hx.UA_eff] < HX_UA
        @test abs(sol[ssys.hx.Q]) < abs(first(hand_hx(HTC.Counterflow(), 2.0, 2.0)))
    end
end

@testset "HeatExchanger to a fixed sink" begin
    function sink_loop(sink)
        @assembly ssys begin
            p = Pump(2.0)
            r = Resistor(1.0)
            hot = HeatExchanger(HX_T_HOT)
            p --> hot --> sink --> r --> p
            p.inlet.p ~ 1.0e5
        end
        return ssys, solve_steady(ssys)
    end

    @named sink = HeatExchanger(20.0; UA=1.0e4)
    ssys, sol = sink_loop(sink)
    @test SciMLBase.successful_retcode(sol)
    C = 2.0 * cₚ(H2O, HX_T_HOT)
    T_out = 20.0 + (HX_T_HOT - 20.0) * exp(-1.0e4 / C)
    @test sol[ssys.sink.outlet.T] ≈ T_out rtol = 1e-10
    @test sol[ssys.sink.Q] ≈ C * (T_out - HX_T_HOT) rtol = 1e-10

    # A large UA brings it to the ideal exchanger.
    @named sink = HeatExchanger(20.0; UA=1.0e9)
    ssys, sol = sink_loop(sink)
    @test sol[ssys.sink.outlet.T] ≈ 20.0 atol = 1e-8
end
