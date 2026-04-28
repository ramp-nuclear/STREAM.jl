using Test
using STREAM
using ModelingToolkit
using OrdinaryDiffEq: ReturnCode

# ─────────────────────────────────────────────────────────────────
# COMPAT: Full suite runs via Pkg.test() (confirmed by reaching here)
# ─────────────────────────────────────────────────────────────────
@testset "COMPAT: Test suite runs automatically via Pkg.test()" begin
    @test true
end

# ─────────────────────────────────────────────────────────────────
# LOOP-01: build_loop_pk compiles and returns (ssys, ic)
# ─────────────────────────────────────────────────────────────────
@testset "LOOP-01: build_loop_pk compiles and returns (ssys, ic)" begin
    ctrl = ReactivityController()
    ssys, ic = build_loop_pk(ctrl)
    @test length(equations(ssys)) > 0
    @test length(unknowns(ssys)) > 0
    @test ic isa Vector{Pair{Any,Any}}
    @test length(ic) > 0
end

# ─────────────────────────────────────────────────────────────────
# LOOP-02: quiescent stability — P within 1% of P0 over 10 seconds
# ReactivityController() returns 0.0 always; no temp feedback.
# At criticality (rho=0) with correct PK ICs, power must be stable.
# ─────────────────────────────────────────────────────────────────
@testset "LOOP-02: quiescent stability P within 1% of P0 over 10s" begin
    P0   = 1.0
    ctrl = ReactivityController()
    ssys, ic = build_loop_pk(ctrl; P0=P0, power_scale=1e4)

    t_arr = range(0.0, 10.0; length=200)
    sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
    @test sol.retcode == ReturnCode.Success

    P_trace = sol[ssys.pk.P, :]
    @test all(isfinite, P_trace)
    @test all(p -> abs(p - P0) / P0 < 0.01, P_trace)
end

# ─────────────────────────────────────────────────────────────────
# LOOP-03: step reactivity with negative temperature feedback.
# After step insertion: power rises (P_max > P0) then feedback damps
# the excursion (P[end] < P_max).
# ─────────────────────────────────────────────────────────────────
@testset "LOOP-03: step reactivity with temperature feedback" begin
    P0        = 1.0
    t_step    = 0.5
    delta_rho = 0.003   # 0.003 > beta/2; strong enough for visible prompt rise
    alpha     = -1e-4   # weak negative feedback (same magnitude as TF-06)
    T_inlet   = 293.15

    # ReactivityController.input_reactivity has signature (state, t_state, t) -> Float64
    step_fn = (state, t_state, t) -> (t >= t_step ? delta_rho : 0.0)
    ctrl = ReactivityController(step_fn)

    ssys, ic = build_loop_pk(ctrl;
        P0=P0, power_scale=1e4,
        temp_worth = Dict(:cac => fill(alpha, 7)),
        ref_temp   = Dict(:cac => fill(T_inlet, 7)),
    )

    t_arr = range(0.0, 5.0; length=500)
    sol = solve_transient(ssys, ic, t_arr; tstops=[t_step], maxiters=1_000_000)
    @test sol.retcode == ReturnCode.Success

    P_trace = sol[ssys.pk.P, :]
    P_max   = maximum(P_trace)

    @test P_max > P0                     # power rises after step
    @test P_trace[end] < P_max          # feedback damps the excursion
    @test all(isfinite, P_trace)        # no NaN/Inf
end

# ─────────────────────────────────────────────────────────────────
# LOOP-04: SCRAM terminates coupled loop.
# Large step reactivity drives P above plimit; SCRAM_at_power fires,
# transitions ctrl to :SCRAM, and scram_callback terminates the solver
# before t=10s.
# ─────────────────────────────────────────────────────────────────
@testset "LOOP-04: SCRAM terminates coupled loop" begin
    P0        = 1.0
    plimit    = 1.2
    t_step    = 0.5
    delta_rho = 0.005   # large enough to exceed plimit quickly
    alpha     = -0.01
    T_inlet   = 293.15

    scram_ir = (state, t_state, t) -> state == :SCRAM ? -0.05 : (t >= t_step ? delta_rho : 0.0)
    ctrl = ReactivityController(scram_ir;
        initial_state = :NORMAL,
        state_machine = SCRAM_at_power(plimit),
        abort_states  = Set([:SCRAM]))

    ssys, ic = build_loop_pk(ctrl;
        P0=P0, power_scale=1e4,
        temp_worth = Dict(:cac => fill(alpha, 7)),
        ref_temp   = Dict(:cac => fill(T_inlet, 7)),
    )

    cb = scram_callback(ssys, ssys.pk.P, ctrl)

    t_arr = range(0.0, 10.0; length=1000)
    sol = solve_transient(ssys, ic, t_arr; tstops=[t_step], callbacks=cb, maxiters=1_000_000)

    @test sol.retcode == ReturnCode.Terminated   # DiffEq terminate! sets this
    @test sol.t[end] < 10.0                      # early stop confirmed by time
    @test ctrl.state == :SCRAM         # state machine transitioned
    @test any(entry -> entry[1] == :SCRAM, ctrl.log)  # SCRAM logged
end
