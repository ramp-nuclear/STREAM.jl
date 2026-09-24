# Checks for the pool LOFA model, run by hand rather than by the package test suite:
#   julia --project=. examples/lofa_pool/test.jl
# A data-free stand-in replaces the decay heat standards, so no tables are needed.
using Test
using STREAM
using STREAM.Components
using ModelingToolkit
using OrdinaryDiffEq: ReturnCode

include(joinpath(@__DIR__, "model.jl"))
include(joinpath(@__DIR__, "test_case.jl"))

@testset "build_pool_lofa is fully determined" begin
    model = build_pool_lofa(ReactivityController(), t -> 0.0; case=POOL_LOFA_TEST_CASE)
    @test length(equations(model.ssys)) == length(unknowns(model.ssys))
end

@testset "Pool LOFA: two assembly types, pool sink, low-flow SCRAM" begin
    case = POOL_LOFA_TEST_CASE
    # Rods enter 0.1 s after the trip signal and are fully in 0.5 s later.
    rod(τ) = -0.06 * clamp((τ - 0.1) / 0.5, 0.0, 1.0)
    ctrl = ReactivityController((s, ts, tt) -> s === :SCRAM ? rod(tt - ts) : 0.0;
                                machine=StateMachine())
    # Data free, so this runs without the standards package. About 6% of rated at shutdown.
    heat = DecayHeat.U238CaptureChain(0.5) +
        DecayHeat.FissionProducts([1.0, 0.05, 1e-3, 1e-5], [3.0, 0.15, 3e-3, 3e-5])
    source = DecayHeat.DecayHeatSource(heat, ctrl; P0=1.0)
    model = build_pool_lofa(ctrl, source; case=case)
    ssys = model.ssys
    sol_ss = solve_pool_lofa_steady(model)

    @testset "the steady state is the design point" begin
        for key in keys(case.types)
            @test sol_ss[model.channels[key].inlet.ṁ] ≈ case.types[key].design_ṁ rtol = 0.02
        end
        @test sol_ss[ssys.pk.P] ≈ 1.0 rtol = 1e-9
        @test sol_ss[ssys.pk.P_neutron] ≈ 1.0 - source(0.0) rtol = 1e-9
    end

    times = range(0.0, 1200.0; length=241)
    sol = solve_transient(
        ssys, sol_ss, times; overrides=model.trip, callbacks=model.callbacks
    )
    @test sol.retcode == ReturnCode.Success

    @testset "the reactor trips on low flow and decay heat is what remains" begin
        protection = model.protection
        @test protection.state === :SCRAM
        @test protection.log[end].cause == "low primary flow"
        # It trips when the primary flow falls through its setpoint, not before.
        primary = sol[ssys.flywheel.inlet.ṁ, :]
        @test all(primary[sol.t .< protection.t_state] .> case.trip_fraction * model.design_ṁ)
        @test sol[ssys.pk.P_neutron, end] < 1e-6
        @test sol[ssys.pk.P, end] ≈ source(times[end]) rtol = 1e-4
    end

    @testset "the flapper opens and both types turn around" begin
        @test model.valve.state === :OPEN
        # The flywheel keeps the flow up well past the trip before the flapper can open.
        @test model.valve.t_state > model.protection.t_state
        for key in keys(case.types)
            ṁ = sol[model.channels[key].inlet.ṁ, :]
            @test ṁ[1] > 0     # downward forced flow
            @test ṁ[end] < 0   # upward natural circulation
        end
    end

    @testset "the pool carries the decay heat away" begin
        # With no sink on the recirculation path the coolant keeps warming for as long as
        # the run lasts. With the pool there, the hottest coolant late in the run falls with
        # the decay heat instead.
        for key in keys(case.types)
            ch = model.channels[key]
            T_hot(k) = maximum(sol[ch.T[i], k] for i in 1:case.n)
            @test T_hot(241) < T_hot(121)   # t = 1200 s against t = 600 s
        end
        # Upward flow leaves each channel through its top cell into the pool and enters from
        # the riser at pool temperature, so the pool takes out N·|ṁ|·cp·(T[1] - T_pool) per
        # type. Late in the run that has to match the decay heat, up to the slow cooling of
        # the plates.
        cp = cₚ(H2O, case.T_pool)
        Q_pool = sum(
            case.types[key].N * abs(sol[model.channels[key].inlet.ṁ, end]) * cp *
            (sol[model.channels[key].T[1], end] - case.T_pool) for key in keys(case.types)
        )
        @test Q_pool ≈ sol[ssys.pk.P, end] * case.P_rated rtol = 0.05
    end
end
