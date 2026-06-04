using Test
using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM: Channel, HeatDiffusion, ChannelAndContacts
import ModelingToolkit: compose

@testset "PointKinetics" begin
    @testset "PK-01a: component compiles with 7 state variables" begin
        @named pk = PointKinetics(rho=0.0)
        ssys = mtkcompile(pk)
        @test length(unknowns(ssys)) == 7
    end

    @testset "PK-02: steady-state IC formula" begin
        P0 = 1e6
        ic = point_kinetics_steady_state(P0)
        @test ic.P == P0
        @test length(ic.C_k) == 6
        for i in 1:6
            expected = U235_BETA_K[i] / (U235_LAMBDA_K[i] * U235_LAMBDA) * P0
            @test isapprox(ic.C_k[i], expected, rtol=1e-12)
        end
    end

    @testset "PK-01b: precursor-only decay matches analytical" begin
        lambda_k = U235_LAMBDA_K
        @named pk = PointKinetics(rho=0.0, Lambda=1.0, beta_k=zeros(6), lambda_k=lambda_k)
        ssys = mtkcompile(pk)

        P0 = 10.0
        C_k0 = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        op = [
            ssys.P => P0,
            ssys.C_1 => C_k0[1],
            ssys.C_2 => C_k0[2],
            ssys.C_3 => C_k0[3],
            ssys.C_4 => C_k0[4],
            ssys.C_5 => C_k0[5],
            ssys.C_6 => C_k0[6],
        ]

        t_span = range(0.0, 100.0, length=500)
        sol = solve_transient(ssys, op, t_span)

        # Analytical power: P(t) = P0 + sum_k C_k0[k] * (1 - exp(-lambda_k[k] * t))
        for (j, tj) in enumerate(t_span)
            P_analytical = P0 + sum(C_k0[k] * (1 - exp(-lambda_k[k] * tj)) for k in 1:6)
            @test isapprox(sol[ssys.P, j], P_analytical, rtol=1e-3, atol=1e-6)
        end

        for (j, tj) in enumerate(t_span)
            @test isapprox(
                sol[ssys.C_1, j], C_k0[1] * exp(-lambda_k[1] * tj), rtol=1e-3, atol=1e-6
            )
        end
    end

    @testset "PK-01c: zero ICs yield trivial P=0 solution" begin
        @named pk = PointKinetics(rho=0.0)
        ssys = mtkcompile(pk)
        op = [
            ssys.P => 0.0,
            ssys.C_1 => 0.0,
            ssys.C_2 => 0.0,
            ssys.C_3 => 0.0,
            ssys.C_4 => 0.0,
            ssys.C_5 => 0.0,
            ssys.C_6 => 0.0,
        ]
        t_span = range(0.0, 10.0, length=100)
        sol = solve_transient(ssys, op, t_span)
        # All-zero system stays at zero (trivial fixed point)
        @test all(abs.(sol[ssys.P, :]) .< 1e-10)
    end

    @testset "PK-01d: @observed variables accessible" begin
        @named pk = PointKinetics(rho=0.0)
        ssys = mtkcompile(pk)
        ic = point_kinetics_steady_state(1e6)
        op = [
            ssys.P => ic.P,
            ssys.C_1 => ic.C_k[1],
            ssys.C_2 => ic.C_k[2],
            ssys.C_3 => ic.C_k[3],
            ssys.C_4 => ic.C_k[4],
            ssys.C_5 => ic.C_k[5],
            ssys.C_6 => ic.C_k[6],
        ]
        t_span = range(0.0, 1.0, length=10)
        sol = solve_transient(ssys, op, t_span)

        # beta_total should equal sum of default beta_k
        @test isapprox(sol[ssys.beta_total, 1], sum(U235_BETA_K), rtol=1e-10)
        # reactivity should equal rho (=0.0 for this system)
        @test isapprox(sol[ssys.reactivity, 1], 0.0, atol=1e-10)
        # dPdt should be accessible and numeric
        @test isfinite(sol[ssys.dPdt, 1])
    end

    @testset "RC-01: ReactivityController" begin
        ctrl_default = ReactivityController()
        @test ctrl_default.state == :NORMAL
        @test ctrl_default.t_state == 0.0
        @test ctrl_default.log == [(:NORMAL, 0.0)]
        @test ctrl_default.abort_states == Set()
        @test worth(ctrl_default, 0.0) == 0.0
        @test worth(ctrl_default, 10.0) == 0.0
        @test worth(ctrl_default, 1e6) == 0.0

        fn_linear = (s, ts, t) -> 0.001 * t
        ctrl_fn = ReactivityController(fn_linear)
        @test worth(ctrl_fn, 0.0) == 0.0
        @test worth(ctrl_fn, 2.5) == 0.0025
        @test worth(ctrl_fn, 10.0) == 0.01

        @test ctrl_fn(0.0) == worth(ctrl_fn, 0.0)
        @test ctrl_fn(3.14) == worth(ctrl_fn, 3.14)
        @test ctrl_fn(100.0) == worth(ctrl_fn, 100.0)

        sm_flip = (s, t, p, dp) -> (p > 50.0 ? :SCRAM : s)
        ctrl_sm = ReactivityController((s, ts, t) -> 0.0; state_machine=sm_flip)
        @test ctrl_sm.state == :NORMAL
        @test length(ctrl_sm.log) == 1
        new1 = change_state(ctrl_sm, 0.5, 10.0, 1.0)
        @test new1 == :NORMAL
        @test ctrl_sm.state == :NORMAL
        @test ctrl_sm.t_state == 0.0
        @test length(ctrl_sm.log) == 1
        new2 = change_state(ctrl_sm, 1.5, 100.0, 5.0)
        @test new2 == :SCRAM
        @test ctrl_sm.state == :SCRAM
        @test ctrl_sm.t_state == 1.5
        @test ctrl_sm.log == [(:NORMAL, 0.0), (:SCRAM, 1.5)]
        new3 = change_state(ctrl_sm, 2.0, 200.0, 10.0)
        @test new3 == :SCRAM
        @test length(ctrl_sm.log) == 2

        ctrl_id = ReactivityController((s, ts, t) -> 0.0)  # default identity state_machine
        r = change_state(ctrl_id, 5.0, 999.0, 42.0)
        @test r == :NORMAL
        @test ctrl_id.state == :NORMAL
        @test ctrl_id.t_state == 0.0
        @test length(ctrl_id.log) == 1

        abort = Set([:SCRAM, :ABORT])
        ctrl_ab = ReactivityController((s, ts, t) -> 0.0; abort_states=abort)
        @test ctrl_ab.abort_states == Set([:SCRAM, :ABORT])
        @test :SCRAM in ctrl_ab.abort_states
        @test :NORMAL ∉ ctrl_ab.abort_states

        ctrl_init = ReactivityController(
            (s, ts, t) -> 0.0; initial_state=:STARTUP, initial_time=7.5
        )
        @test ctrl_init.state == :STARTUP
        @test ctrl_init.t_state == 7.5
        @test ctrl_init.log == [(:STARTUP, 7.5)]

        capture = Ref{Tuple{Symbol,Float64,Float64}}((:X, -1.0, -1.0))
        fn_capture = (s, ts, t) -> (capture[]=(s, ts, t); 0.0)
        ctrl_cap = ReactivityController(
            fn_capture; initial_state=:PHASE_A, initial_time=2.0
        )
        worth(ctrl_cap, 8.0)
        @test capture[] == (:PHASE_A, 2.0, 8.0)
    end

    @testset "PK-03: Callable Control Reactivity" begin
        fn_zero = t -> 0.0
        @named pk_a = PointKinetics(fn_zero; rho_val=0.0)
        ssys_a = mtkcompile(pk_a)
        @test length(unknowns(ssys_a)) == 7
        P0 = 1e6
        ic = point_kinetics_steady_state(P0)
        ctrl_zero = ReactivityController()
        @named pk_b = PointKinetics(ctrl_zero; rho_val=0.0)
        ssys_b = mtkcompile(pk_b)
        op_b = Pair{Any,Any}[
            ssys_b.rho_c_fn => ctrl_zero,
            ssys_b.P => ic.P,
            ssys_b.C_1 => ic.C_k[1],
            ssys_b.C_2 => ic.C_k[2],
            ssys_b.C_3 => ic.C_k[3],
            ssys_b.C_4 => ic.C_k[4],
            ssys_b.C_5 => ic.C_k[5],
            ssys_b.C_6 => ic.C_k[6],
        ]
        t_arr_b = range(0.0, 2.0, length=100)
        sol_b = solve_transient(ssys_b, op_b, t_arr_b)
        # At criticality with correct ICs, P stays within 1% of P0
        for j in 1:length(t_arr_b)
            @test isapprox(sol_b[ssys_b.P, j], P0; rtol=1e-2)
        end

        delta_rho = 0.002
        t_step = 1.0
        fn_step = (s, ts, t) -> (t >= t_step) * delta_rho
        ctrl_step = ReactivityController(fn_step)
        @named pk_c = PointKinetics(ctrl_step; rho_val=0.0)
        ssys_c = mtkcompile(pk_c)
        op_c = Pair{Any,Any}[
            ssys_c.rho_c_fn => ctrl_step,
            ssys_c.P => ic.P,
            ssys_c.C_1 => ic.C_k[1],
            ssys_c.C_2 => ic.C_k[2],
            ssys_c.C_3 => ic.C_k[3],
            ssys_c.C_4 => ic.C_k[4],
            ssys_c.C_5 => ic.C_k[5],
            ssys_c.C_6 => ic.C_k[6],
        ]
        t_sample = t_step + 0.028
        t_arr_c = range(0.0, t_sample, length=500)
        sol_c = solve_transient(ssys_c, op_c, t_arr_c; tstops=[t_step])

        beta_total = sum(U235_BETA_K)
        P_jump_expected = beta_total / (beta_total - delta_rho) * P0
        P_jump_numerical = sol_c[ssys_c.P, end]
        @test isapprox(P_jump_numerical, P_jump_expected; rtol=1e-2)
        # Before the step, P should be ≈ P0 (steady state)
        idx_pre = findfirst(tv -> tv >= 0.5, t_arr_c)
        @test isapprox(sol_c[ssys_c.P, idx_pre], P0; rtol=1e-2)

        # PK-03d: ramp insertion produces monotonically increasing P during ramp
        ramp_slope = 0.001  # 1/s -> reaches 0.002 at t=2s (still < beta/3)
        t_ramp_end = 2.0
        fn_ramp = (s, ts, t) -> ramp_slope * t
        ctrl_ramp = ReactivityController(fn_ramp)
        @named pk_d = PointKinetics(ctrl_ramp; rho_val=0.0)
        ssys_d = mtkcompile(pk_d)
        op_d = Pair{Any,Any}[
            ssys_d.rho_c_fn => ctrl_ramp,
            ssys_d.P => ic.P,
            ssys_d.C_1 => ic.C_k[1],
            ssys_d.C_2 => ic.C_k[2],
            ssys_d.C_3 => ic.C_k[3],
            ssys_d.C_4 => ic.C_k[4],
            ssys_d.C_5 => ic.C_k[5],
            ssys_d.C_6 => ic.C_k[6],
        ]
        t_arr_d = range(0.0, t_ramp_end, length=200)
        sol_d = solve_transient(ssys_d, op_d, t_arr_d)
        P_traj = sol_d[ssys_d.P, :]
        @test P_traj[end] > P_traj[1]
        @test P_traj[end] > P0  # positive ramp -> super-critical -> P grows above P0
        idx_start = findfirst(tv -> tv >= 0.1, t_arr_d)
        for j in (idx_start + 1):length(t_arr_d)
            @test P_traj[j] >= P_traj[j - 1] - 1e-3 * P0  # allow tiny solver noise
        end

        plain_fn = t -> (t >= t_step) * delta_rho
        @named pk_e = PointKinetics(plain_fn; rho_val=0.0)
        ssys_e = mtkcompile(pk_e)
        op_e = Pair{Any,Any}[
            ssys_e.rho_c_fn => plain_fn,
            ssys_e.P => ic.P,
            ssys_e.C_1 => ic.C_k[1],
            ssys_e.C_2 => ic.C_k[2],
            ssys_e.C_3 => ic.C_k[3],
            ssys_e.C_4 => ic.C_k[4],
            ssys_e.C_5 => ic.C_k[5],
            ssys_e.C_6 => ic.C_k[6],
        ]
        t_arr_e = range(0.0, t_sample, length=500)
        sol_e = solve_transient(ssys_e, op_e, t_arr_e; tstops=[t_step])
        @test isapprox(sol_e[ssys_e.P, end], sol_c[ssys_c.P, end]; rtol=1e-3)
    end

    @testset "TF-01..TF-03: Temperature Feedback Construction" begin
        # Shared fixtures
        ctrl_zero = ReactivityController()  # always returns 0.0

        pg5 = PipeGeometry_rectangular(1.0, 0.04, 0.01, 0.04)
        @named ch = Channel(; name=:ch, n=5, geometry=pg5)
        ps_3x2 = fill(1.0/(3*2), 3, 2)
        @named fuel = HeatDiffusion(
            nz=3,
            nx=2,
            Lz=0.6,
            Lx=0.005,
            y=0.07,
            rho_s=19300.0,
            cp_s=116.0,
            k_s=174.0,
            power_shape=ps_3x2,
        )

        @testset "TF-01a: default no temp_worth gives 7 state vars" begin
            @named pk = PointKinetics(ctrl_zero)
            @test length(unknowns(pk)) == 7
            unames = string.(ModelingToolkit.getname.(unknowns(pk)))
            @test !any(n -> occursin("T_source", n), unames)
        end

        @testset "TF-01b: temp_worth=nothing gives 7 state vars" begin
            @named pk = PointKinetics(ctrl_zero; temp_worth=nothing)
            @test length(unknowns(pk)) == 7
        end

        @testset "TF-02a: scalar alpha broadcasts to all channel cells" begin
            @named pk = PointKinetics(ctrl_zero; temp_worth=Dict(ch => -0.001))
            unames = string.(ModelingToolkit.getname.(unknowns(pk)))
            @test any(n -> occursin("T_source_ch", n), unames)
            # 7 original + 5 T_source_ch
            @test length(unknowns(pk)) == 7 + 5
        end

        @testset "TF-02b: 1D vector per channel cell" begin
            @named pk = PointKinetics(
                ctrl_zero; temp_worth=Dict(ch => [-0.001, -0.002, -0.003, -0.004, -0.005])
            )
            unames = string.(ModelingToolkit.getname.(unknowns(pk)))
            @test any(n -> occursin("T_source_ch", n), unames)
            @test length(unknowns(pk)) == 7 + 5
        end

        @testset "TF-02c: 2D matrix for HeatDiffusion (3x2=6 cells)" begin
            @named pk = PointKinetics(
                ctrl_zero; temp_worth=Dict(fuel => fill(-0.002, 3, 2))
            )
            unames = string.(ModelingToolkit.getname.(unknowns(pk)))
            @test any(n -> occursin("T_source_fuel", n), unames)
            @test length(unknowns(pk)) == 7 + 6
        end

        @testset "TF-02d: shape mismatch raises ArgumentError (vector)" begin
            @test_throws ArgumentError PointKinetics(
                ctrl_zero; name=:pk, temp_worth=Dict(ch => [1.0, 2.0])
            )
        end

        @testset "TF-02e: shape mismatch raises ArgumentError (matrix)" begin
            @test_throws ArgumentError PointKinetics(
                ctrl_zero; name=:pk, temp_worth=Dict(fuel => fill(0.0, 2, 2))
            )
        end

        @testset "TF-03a: ref_temp omitted — constructor succeeds" begin
            @test_nowarn PointKinetics(ctrl_zero; name=:pk, temp_worth=Dict(ch => -0.001))
        end

        @testset "TF-03b: ref_temp missing key — constructor succeeds" begin
            alpha1 = -0.001
            alpha2 = fill(-0.002, 3, 2)
            @test_nowarn PointKinetics(
                ctrl_zero;
                name=:pk,
                temp_worth=Dict(ch => alpha1, fuel => alpha2),
                ref_temp=Dict(ch => 293.0),
            )
        end

        @testset "TF-03c: ref_temp=nothing — constructor succeeds" begin
            @test_nowarn PointKinetics(
                ctrl_zero; name=:pk, temp_worth=Dict(ch => -0.001), ref_temp=nothing
            )
        end
    end

    @testset "TF-04: connect_temperature_feedback" begin
        ctrl_zero = ReactivityController()

        pg5 = PipeGeometry_rectangular(1.0, 0.04, 0.01, 0.04)
        @named ch = Channel(; name=:ch, n=5, geometry=pg5)
        ps_3x2 = fill(1.0/(3*2), 3, 2)
        @named fuel = HeatDiffusion(
            nz=3,
            nx=2,
            Lz=0.6,
            Lx=0.005,
            y=0.07,
            rho_s=19300.0,
            cp_s=116.0,
            k_s=174.0,
            power_shape=ps_3x2,
        )

        @testset "TF-04a: 1D channel generates 5 equations" begin
            @named pk = PointKinetics(ctrl_zero; temp_worth=Dict(ch => -0.001))
            eqs = connect_temperature_feedback(pk, [ch])
            @test eqs isa Vector{Equation}
            @test length(eqs) == 5
        end

        @testset "TF-04b: 2D HeatDiffusion generates 6 equations (row-major)" begin
            @named pk = PointKinetics(
                ctrl_zero; temp_worth=Dict(fuel => fill(-0.002, 3, 2))
            )
            eqs = connect_temperature_feedback(pk, [fuel])
            @test eqs isa Vector{Equation}
            @test length(eqs) == 6
        end

        @testset "TF-04c: multiple components generates 5+6=11 equations" begin
            tw = Dict(ch => -0.001, fuel => fill(-0.002, 3, 2))
            @named pk = PointKinetics(ctrl_zero; temp_worth=tw)
            eqs = connect_temperature_feedback(pk, [ch, fuel])
            @test length(eqs) == 11
        end
    end 

    @testset "TF-05: Components Unchanged (regression guard)" begin
        proj_root = pkgdir(STREAM)
        for relpath in (
            "src/components/channels.jl",
            "src/components/heat_diffusion.jl",
        )
            src = read(joinpath(proj_root, relpath), String)
            @test !occursin("T_source_", src)
            @test !occursin("temp_worth", src)
            @test !occursin("connect_temperature_feedback", src)
        end
    end  

    @testset "SCRAM-01: SCRAM_at_power struct and callable" begin
        sc = SCRAM_at_power(1.5)
        @test sc isa SCRAMCondition
        @test sc.power_limit == 1.5

        @test SCRAM_at_power(2).power_limit isa Float64

        @test sc(:NORMAL, 0.0, 1.0, 0.0) == :NORMAL
        @test sc(:NORMAL, 0.0, 2.0, 0.0) == :SCRAM
        @test sc(:SCRAM, 0.5, 2.0, 0.0) == :SCRAM
        @test sc(:NORMAL, 0.0, 2.0, -999.0) == :SCRAM
        @test sc(:NORMAL, 0.0, 1.5, 0.0) == :NORMAL
    end

    @testset "SCRAM-02: scram_callback terminates solver on SCRAM" begin
        P0 = 1.0
        plimit = 1.5
        t_step = 0.5
        # delta_rho = 0.005 > beta_total/3 (~0.0022): fast prompt-jump above plimit
        delta_rho = 0.005

        scram_ir =
            (state, t_state, t) -> state == :SCRAM ? -0.05 : (t >= t_step ? delta_rho : 0.0)
        ctrl = ReactivityController(
            scram_ir;
            initial_state=:NORMAL,
            state_machine=SCRAM_at_power(plimit),
            abort_states=Set([:SCRAM]),
        )

        @named pk = PointKinetics(ctrl; rho_val=0.0)
        ssys = mtkcompile(pk)
        cb = scram_callback(ssys, ssys.P, ctrl)

        ic = point_kinetics_steady_state(P0)
        op = Pair{Any,Any}[
            ssys.rho_c_fn => ctrl,
            ssys.P => ic.P,
            ssys.C_1 => ic.C_k[1],
            ssys.C_2 => ic.C_k[2],
            ssys.C_3 => ic.C_k[3],
            ssys.C_4 => ic.C_k[4],
            ssys.C_5 => ic.C_k[5],
            ssys.C_6 => ic.C_k[6],
        ]

        t_arr = range(0.0, 10.0; length=1000)
        sol = solve_transient(ssys, op, t_arr; tstops=[t_step], callbacks=cb)

        @test sol.t[end] < 10.0

        @test ctrl.state == :SCRAM
        @test any(entry -> entry[1] == :SCRAM, ctrl.log)

        t_scram = ctrl.log[end][2]
        @test t_scram > t_step
    end
end 
