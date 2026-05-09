# Plan 58-05 — standalone PK validation proof
#
# The full `julia test/test_validation.jl` file run cannot reach the PK
# validation testset because it short-circuits in the VAL-01 Fourier
# `Rodas5P` `InitialFailure` branch (pre-existing flaky documented in STATE.md
# "Blockers/Concerns" line 100, deferred-items.md D-1, and 58-04 SUMMARY).
#
# This script re-runs ONLY the four VAL-PK-* sub-testsets in isolation,
# using the same logic as test_validation.jl:1053-1224, so we can prove
# Phase-58 acceptance criterion: "PK testset reaches solve_* (steady or
# transient fallback)".
#
# Usage:
#   julia --project=. .planning/phases/58-mtk-system-determinacy-repair/scratch/pk_validation_proof.jl

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using OrdinaryDiffEq: ReturnCode

@testset "PointKinetics validation (standalone proof — Plan 58-05)" begin
    @testset "VAL-PK-01: steady-state coolant temperature rises linearly" begin
        n = 7
        T_inlet = 293.15
        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(ctrl; n=n, T_inlet=T_inlet, P0=1.0, power_scale=1e4)

        local T_cool
        ss_sol = solve_steady(ssys, ic)
        if ss_sol.retcode == ReturnCode.Success
            T_cool = [ss_sol[ssys.rods.cac.T[i]] for i in 1:n]
        else
            t_arr = range(0.0, 50.0; length=200)
            sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
            T_cool = [sol[ssys.rods.cac.T[i], end] for i in 1:n]
        end

        dT  = diff(T_cool)
        ddT = diff(dT)

        @test all(dT .> 0)
        @test isapprox(ddT, zeros(length(ddT)); atol=0.5)
    end

    @testset "VAL-PK-02a: negative fuel feedback suppresses power to near zero" begin
        n = 7
        nz = 7
        nx = 2
        T_inlet = 293.15
        alpha_neg = -0.1

        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(
            ctrl;
            n=n,
            nz=nz,
            nx=nx,
            T_inlet=T_inlet,
            P0=1.0,
            power_scale=1e4,
            temp_worth=Dict(:fuel => fill(alpha_neg, nz, nx)),
            ref_temp=Dict(:fuel => fill(T_inlet, nz, nx)),
        )

        ic_high = copy(ic)
        for (idx, pair) in enumerate(ic_high)
            if pair.first === ssys.pk.P
                ic_high[idx] = ssys.pk.P => 1e3
            end
            for k in 1:6
                sym = getproperty(ssys.pk, Symbol(:C_, k))
                if pair.first === sym
                    ic_high[idx] = sym => 1e3
                end
            end
        end

        local P_final
        ss_sol2a = solve_steady(ssys, ic_high)
        P_candidate = ss_sol2a.retcode == ReturnCode.Success ? ss_sol2a[ssys.pk.P] : NaN
        if isfinite(P_candidate)
            P_final = P_candidate
        else
            t_arr = range(0.0, 200.0; length=500)
            sol = solve_transient(ssys, ic_high, t_arr; maxiters=1_000_000)
            P_final = sol[ssys.pk.P, end]
        end

        @test abs(P_final) < 0.1
    end

    @testset "VAL-PK-02b: negative coolant feedback suppresses power to near zero" begin
        n = 7
        T_inlet = 293.15
        alpha_neg = -0.1

        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(
            ctrl;
            n=n,
            T_inlet=T_inlet,
            P0=1.0,
            power_scale=1e4,
            temp_worth=Dict(:cac => fill(alpha_neg, n)),
            ref_temp=Dict(:cac => fill(T_inlet, n)),
        )

        ic_high = copy(ic)
        for (idx, pair) in enumerate(ic_high)
            if pair.first === ssys.pk.P
                ic_high[idx] = ssys.pk.P => 1e3
            end
            for k in 1:6
                sym = getproperty(ssys.pk, Symbol(:C_, k))
                if pair.first === sym
                    ic_high[idx] = sym => 1e3
                end
            end
        end

        local P_final
        ss_sol2b = solve_steady(ssys, ic_high)
        P_candidate = ss_sol2b.retcode == ReturnCode.Success ? ss_sol2b[ssys.pk.P] : NaN
        if isfinite(P_candidate)
            P_final = P_candidate
        else
            t_arr = range(0.0, 200.0; length=500)
            sol = solve_transient(ssys, ic_high, t_arr; maxiters=1_000_000)
            P_final = sol[ssys.pk.P, end]
        end

        @test abs(P_final) < 0.1
    end

    @testset "VAL-PK-03: reactivity observable accessible and correct at steady state" begin
        n = 7
        T_inlet = 293.15
        alpha = -0.005
        ctrl = ReactivityController()

        ssys, ic = build_loop_pk(
            ctrl;
            n=n,
            T_inlet=T_inlet,
            P0=1.0,
            power_scale=1e4,
            temp_worth=Dict(:cac => fill(alpha, n)),
            ref_temp=Dict(:cac => fill(T_inlet, n)),
        )

        t_arr = range(0.0, 50.0; length=200)
        sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)

        rho_trace = sol[ssys.pk.reactivity, :]
        @test rho_trace isa AbstractVector
        @test length(rho_trace) > 1
        @test all(isfinite, rho_trace)
        @test abs(rho_trace[end]) < 0.01
    end
end
