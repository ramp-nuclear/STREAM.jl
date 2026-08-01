using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using DelimitedFiles
using STREAM
using STREAM: Channel, HeatDiffusion, PipeGeometry_rectangular, PipeGeometry_circular


include(joinpath(@__DIR__, "parity_helpers.jl"))
include(joinpath(@__DIR__, "data", "python_parity_reference.jl"))

# CSV path + truncate-and-rewrite at file load: one fresh CSV per
# `julia --project=. test/test_validation.jl` run; the CSV in git represents the
# LAST run. Each parity testset thereafter calls append_csv(...; truncate=false).
# The 3 KEPT testsets do NOT touch the CSV.
const PARITY_CSV = joinpath(@__DIR__, "data", "parity_report.csv")
function __init_parity_csv()
    open(PARITY_CSV, "w") do io
        write(io, "scenario,quantity,julia,python,abs_err,rtol,tier,hard_ceiling,note\n")
    end
end
__init_parity_csv()  # called once at file load

# Effective channel HTC for parity, mirroring Python STREAM's `_other_if_none`:
# report the HTC of the HEAT-TRANSFERRING (connected) face — the side with nonzero
# wall heat flux. A dangling/adiabatic face has q_wall=0 and a physically-irrelevant
# HTC evaluated at bulk T; a naive max(h_left,h_right) wrongly picks that bulk-T value
# for a channel whose plate face is cooler than the bulk (the hot channel). Selecting
# by |q_wall| makes Julia's connected-face HTC match Python's reference exactly
# (verified to 0.000% — see the "HTC formula identity" testset below).
_h_eff(sol, cac, i) = abs(sol[cac.q_wall_left[i]]) >= abs(sol[cac.q_wall_right[i]]) ?
                      sol[cac.h_tc_left[i]] : sol[cac.h_tc_right[i]]

@testset "parity_helpers self-tests" begin
    # Self-test 1: identity → CLEAN, rtol=0
    r = parity_check("st", "q", 100.0, 100.0)
    @test r.tier == TIER_CLEAN
    @test r.rtol == 0.0
    # Self-test 2: sub-1e-6 drift → CLEAN
    r2 = parity_check("st", "q", 100.0, 100.0 * (1 + 1e-9))
    @test r2.tier == TIER_CLEAN
    # Self-test 3: 0.1% drift → GRAY
    r3 = parity_check("st", "q", 100.0, 100.0 * (1 + 1e-3))
    @test r3.tier == TIER_GRAY
    # Self-test 4: 5% drift → FAIL
    r4 = parity_check("st", "q", 100.0, 100.0 * (1 + 0.05))
    @test r4.tier == TIER_FAIL
    # Self-test 5: boundary at exactly hard_ceiling → FAIL (strict <)
    # rtol = abs_err/|python_ref| = 2/100 = 0.02 exactly == hard_ceiling → FAIL
    r5 = parity_check("st", "q", 102.0, 100.0)
    @test r5.tier == TIER_FAIL
    # Self-test 6: zero on both sides → CLEAN (abs_err=0)
    r6 = parity_check("st", "q", 0.0, 0.0)
    @test r6.tier == TIER_CLEAN
    # Self-test 7: zero-handling boundary (python_ref==0) — abs_err is 1e-6 ≤ gray_floor → CLEAN
    r7 = parity_check("st", "q", 1e-6, 0.0)
    @test r7.tier == TIER_CLEAN
    # Self-test 8: sign-safety
    r8 = parity_check("st", "q", -300.0, -300.0001)
    @test r8.tier == TIER_CLEAN
    # Self-test 9: CSV roundtrip preserves rtol within %.6e precision (~6 sig figs)
    tmp_csv = tempname() * ".csv"
    rows_test = [r, r3, r4]
    append_csv(tmp_csv, rows_test; truncate=true)
    @test isfile(tmp_csv)
    @test filesize(tmp_csv) > 100
    readback = readdlm(tmp_csv, ',', skipstart=1)
    @test size(readback, 1) == 3
    for (i, original) in enumerate(rows_test)
        recovered_rtol = readback[i, 6]
        if original.rtol == 0.0
            @test recovered_rtol == 0.0
        else
            @test isapprox(recovered_rtol, original.rtol; rtol=1e-5)
        end
    end
    rm(tmp_csv; force=true)
    # Self-test 10: append_csv truncate semantics
    tmp_csv2 = tempname() * ".csv"
    append_csv(tmp_csv2, rows_test; truncate=true)   # 1 header + 3 rows = 4 lines
    n1 = countlines(tmp_csv2)
    append_csv(tmp_csv2, rows_test; truncate=false)  # +3 rows = 7 lines
    n2 = countlines(tmp_csv2)
    @test n2 == n1 + 3
    append_csv(tmp_csv2, rows_test; truncate=true)   # reset to 1 header + 3 rows = 4 lines
    n3 = countlines(tmp_csv2)
    @test n3 == n1
    rm(tmp_csv2; force=true)
    # Self-test 11: print_drift_table on empty rows doesn't crash
    empty_rows = ParityRow[]
    buf = IOBuffer()
    print_drift_table(empty_rows; io=buf)   # a throw here would fail the testset on its own
    @test occursin("summary: 0 quantities", String(take!(buf)))
    # Self-test 12: the equivalence checklist mechanism fires on a wrong reference.
    # PYTHON_*_AT_REF are bit-identical to Julia at rtol=1e-12, so the native checklist passes;
    # this exercises the guard form `cond || error(...)` directly on a deliberately wrong value.
    @test_throws ErrorException (
        isapprox(STREAM.dittus_boelter(10_000.0, 1.0), 1e10; rtol=1e-12) || error("self-test 12")
    )
end

@testset "HTC formula identity vs Python STREAM (exact on shared inputs)" begin
    # PROOF that Julia's single-phase HTC — the Dittus-Boelter formula AND the water
    # property correlations (μ, k, cp) — is identical to Python STREAM's, isolated from
    # solver convergence: feed Python's CONVERGED (T_wall, T_cool, ṁ) into Julia's
    # `DittusBoelter` and require it to reproduce Python's reference h_tc to machine precision.
    # This is why the connected-face HTC matches Python to 0.000% in the live parity:
    # the formula is exact, and `_h_eff` selects the physically-meaningful (q≠0) face.
    geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    Dh = geom.Dh
    A = geom.A
    htc = DittusBoelter()
    for i in 1:length(PARITY_MTR_ASYM_H_TC_LEFT_R)
        h_julia = htc(
            PARITY_MTR_ASYM_T_WALL_LEFT_R[i],
            PARITY_MTR_ASYM_T_CELLS_R[i],
            PARITY_MTR_ASYM_ṁ_R,
            Dh,
            A,
            H2O,
        )
        @test isapprox(h_julia, PARITY_MTR_ASYM_H_TC_LEFT_R[i]; rtol=1e-6)
    end
end

@testset "parity harness" begin

# Python parity: simple loop
#
# Topology: Pump → HX → ChannelAndContacts → Pump (n=10, circular pipe).
# Built INLINE with CAC (NOT via build_loop, which uses Channel).
# Wall BCs imposed via ConstantTemperature + connect() — canonical pattern,
# mirrors HD Fourier testset. Avoids the raw `cac.thermal_left[i].T ~ T_wall`
# equation pattern that bypasses MTK's connector-flow accounting (WARNING #5).
#
# Tiers compared:
    #   (a) scalars  — T_out, ṁ, dP_loop
#   (b) per-cell — T[i] for i in 1:n
#   (c) per-cell wall (CAC-only) — T_wall_left[i], h_tc_left[i], q_density_*[i]
#
# KNOWN EQUIVALENCE GAPS:
#   Gap #1: circular heated_parts partition Python(πD,0) vs Julia(πD/2,πD/2).
#           Python's q_density emit is partition-INVARIANT — the pasted reference
#           shows PARITY_SIMPLE_Q_DENSITY_LEFT == PARITY_SIMPLE_Q_DENSITY_RIGHT,
#           the same W/m^2 value. Julia's split also yields equal L/R density,
#           so per-side density compares cleanly.
#   Gap #2: HTC fluid-property eval at T_film (Python) vs T_bulk (Julia) —
    #           may surface as drift on h_tc and propagate to ṁ. hard_ceiling
#           stays at 2%; FAIL surfaces honestly.
#   Gap #3: Sundials KINSOL vs scipy hybr solver tols — floor on CLEAN tier.
@testset "Python parity: simple loop" begin
    # Step 1: equivalence guard (5 asserts; abort testset on fail)
    assert_equivalence_fluid_props()
    assert_equivalence_dittus_boelter()
    assert_equivalence_blasius()
    geom_simple = PipeGeometry_circular(0.6, 0.01)
    assert_equivalence_geometry(geom_simple,
        0.01,                    # Dh
        π * 0.01^2 / 4,          # A
        π * 0.01,                # wet_perimeter
        (π * 0.01, 0.0);         # circular: full perimeter on one face, (πD, 0) — not annular
        rtol=1e-12)
    assert_equivalence_anchors()

    n = 10
    T_inlet = 40.0
    T_wall = 100.0
    @named pump = Pump(3.0e4)
    @named hx = HeatExchanger(T_inlet)
    @named cac = ChannelAndContacts(; n=n, geometry=geom_simple)
    ct_l = [ConstantTemperature(T_wall; name=Symbol(:ct_l_, i)) for i in 1:n]
    ct_r = [ConstantTemperature(T_wall; name=Symbol(:ct_r_, i)) for i in 1:n]
    conns = vcat(
            inseries(pump, hx, cac, pump),
            [pump.inlet.p ~ 1.0e5],
        connect_face(ct_l, cac, :thermal_left),
        connect_face(ct_r, cac, :thermal_right),
    )
    @named sys = compose(System(conns, t; name=:simple_loop_parity),
                          pump, hx, cac, ct_l..., ct_r...)
    ssys = mtkcompile(sys; fully_determined=true)

        T_guess = steady_state_guess(; T_inlet=T_inlet, Q_wall=1e4, ṁ_guess=0.5, n=n)
    op = vcat(
        [ssys.cac.T[i] => T_guess[i] for i in 1:n],
            [ssys.cac.inlet.ṁ => 0.5],
    )
    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test all(isfinite, [sol[ssys.cac.T[i]] for i in 1:n])
        @test isfinite(sol[ssys.cac.inlet.ṁ])
    rows = ParityRow[]

    push!(rows, parity_check("simple_loop", "T_out",
                             sol[ssys.cac.T_out], PARITY_SIMPLE_T_OUT))
        push!(
            rows,
            parity_check(
                "simple_loop",
                "ṁ",
                abs(sol[ssys.cac.inlet.ṁ]),
                PARITY_SIMPLE_ṁ,
            ),
        )
    push!(rows, parity_check("simple_loop", "dP_loop",
                             sol[ssys.cac.dP], PARITY_SIMPLE_DP))

    for i in 1:n
        push!(rows, parity_check("simple_loop", "T[$i]",
                                 sol[ssys.cac.T[i]], PARITY_SIMPLE_T_CELLS[i]))
    end

    dz = 0.6 / n
    heated_l = geom_simple.heated_parts[1]   # circular: full perimeter πD on one face
    heated_r = geom_simple.heated_parts[2]   # circular: 0 (no second heated face)
    full_perim = heated_l + heated_r          # πD
    for i in 1:n
        push!(rows, parity_check("simple_loop", "T_wall_left[$i]",
                                 sol[getproperty(ssys.cac, Symbol(:thermal_left, i)).T],
                                 PARITY_SIMPLE_T_WALL_LEFT[i]))
        push!(rows, parity_check("simple_loop", "T_wall_right[$i]",
                                 sol[getproperty(ssys.cac, Symbol(:thermal_right, i)).T],
                                 PARITY_SIMPLE_T_WALL_RIGHT[i]))
        push!(rows, parity_check("simple_loop", "h_tc_left[$i]",
                                 sol[ssys.cac.h_tc_left[i]],
                                 PARITY_SIMPLE_H_TC_LEFT[i];
                                 note="Gap #2 candidate (HTC film-T vs bulk-T)"))
        push!(rows, parity_check("simple_loop", "h_tc_right[$i]",
                                 sol[ssys.cac.h_tc_right[i]],
                                 PARITY_SIMPLE_H_TC_RIGHT[i];
                                 note="Gap #2 candidate (HTC film-T vs bulk-T)"))
        push!(rows, parity_check("simple_loop", "q_density_left[$i]",
                                 sol[ssys.cac.q_wall_left[i]] / (heated_l * dz),
                                 PARITY_SIMPLE_Q_DENSITY_LEFT[i]))
        # Circular geometry has no second heated face (heated_parts[2]=0), so a
        # per-face q_density_right is undefined (0/0). q_wall_right is identically 0;
        # the comparison is carried by q_density_left and q_density_total below.
        if heated_r > 0
            push!(rows, parity_check("simple_loop", "q_density_right[$i]",
                                     sol[ssys.cac.q_wall_right[i]] / (heated_r * dz),
                                     PARITY_SIMPLE_Q_DENSITY_RIGHT[i]))
        end
        q_total_julia = (sol[ssys.cac.q_wall_left[i]] + sol[ssys.cac.q_wall_right[i]]) /
                        (full_perim * dz)
        q_total_python = (PARITY_SIMPLE_Q_DENSITY_LEFT[i] + PARITY_SIMPLE_Q_DENSITY_RIGHT[i]) / 2
        push!(rows, parity_check("simple_loop", "q_density_total[$i]",
                                 q_total_julia, q_total_python;
                                 note="Gap #1 mitigated: total q (left+right) cancels partition difference"))
    end

    print_drift_table(rows)
    append_csv(PARITY_CSV, rows; truncate=false)

    for r in rows
        @test r.tier != TIER_FAIL
    end
end

@testset "Transient T_outlet rises after T_wall step" begin
    n = 10
    T_inlet = 40.0

    T_wall_0 = 100.0
    T_wall_final = 120.0
    t_step = 10.0
    T_wall_step = t -> t < t_step ? T_wall_0 : T_wall_final

    ssys_ss = build_loop_transient(; T_inlet=T_inlet, T_wall_0=T_wall_0)
    ssys = build_loop_transient(; T_inlet=T_inlet, T_wall_fn=T_wall_step)

        T_guess = steady_state_guess(; T_inlet=T_inlet, Q_wall=1e4, ṁ_guess=0.490, n=n)
    op_guess = [ssys_ss.ch.T[i] => T_guess[i] for i in 1:n]
        push!(op_guess, ssys_ss.ch.inlet.ṁ => 0.490)
    sol_ss = solve_steady(ssys_ss, op_guess)
    op_ic = Pair{Any,Any}[ssys.ch.T[i] => sol_ss[ssys_ss.ch.T[i]] for i in 1:n]
        push!(op_ic, ssys.ch.inlet.ṁ => sol_ss[ssys_ss.ch.inlet.ṁ])
    T_wall_sym = ssys.T_wall_callable   # stable named access, immune to parameter reordering
    push!(op_ic, T_wall_sym => T_wall_step)

    t_arr = range(0.0, 60.0; length=600)
    sol = solve_transient(ssys, op_ic, t_arr)
    @test sol.retcode == ReturnCode.Success
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)
    @test T_ts[end] > T_ts[1]
end

@testset "Python parity: MTR symmetric" begin
    assert_equivalence_fluid_props()
    assert_equivalence_dittus_boelter()
    assert_equivalence_blasius()
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    assert_equivalence_geometry(geom_mtr,
        PARITY_MTR_GEOM_DH,
        PARITY_MTR_GEOM_AREA,
        PARITY_MTR_GEOM_WETPERIM,
        PARITY_MTR_GEOM_HEATED;
        rtol=1e-9)
    assert_equivalence_anchors()

    nz = 10
    nx = 3
    T_in = 40.0
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(T_in)
    @named cac_r = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(;
        nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps, power=1e4,
    )
    conns = [
            inseries(pump_l, hx_l, cac_l, pump_l)...,
            pump_l.inlet.p ~ 1.0e5,
            inseries(pump_r, hx_r, cac_r, pump_r)...,
            pump_r.inlet.p ~ 1.0e5,
        connect_faces((hd, :thermal_left) => (cac_l, :thermal_right))...,
        connect_faces((hd, :thermal_right) => (cac_r, :thermal_left))...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(
        System(conns, t; name=:mtr_sym_parity), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd
    )
    ssys = mtkcompile(sys; fully_determined=true)

    T_w = 41.85
    op = vcat(
        [ssys.hd.T[i, j] => T_w for i in 1:nz for j in 1:nx],
        [ssys.cac_l.T[i] => T_w for i in 1:nz],
        [ssys.cac_r.T[i] => T_w for i in 1:nz],
            [ssys.cac_l.inlet.ṁ => +0.250],
            [ssys.cac_r.inlet.ṁ => +0.250],
    )
    rows = ParityRow[]
    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test all(isfinite, [sol[ssys.hd.T[i, j]] for i in 1:nz for j in 1:nx])

    push!(rows, parity_check("mtr_symmetric", "T_out_l",
                             sol[ssys.cac_l.T_out], PARITY_MTR_SYM_T_OUT_L))
    push!(rows, parity_check("mtr_symmetric", "T_out_r",
                             sol[ssys.cac_r.T_out], PARITY_MTR_SYM_T_OUT_R))
        push!(
            rows,
            parity_check(
                "mtr_symmetric",
                "ṁ_l",
                abs(sol[ssys.cac_l.inlet.ṁ]),
                PARITY_MTR_SYM_ṁ_L,
            ),
        )
        push!(
            rows,
            parity_check(
                "mtr_symmetric",
                "ṁ_r",
                abs(sol[ssys.cac_r.inlet.ṁ]),
                PARITY_MTR_SYM_ṁ_R,
            ),
        )
    push!(rows, parity_check("mtr_symmetric", "dP_loop",
                             sol[ssys.cac_l.dP], PARITY_MTR_SYM_DP))

    for i in 1:nz
        push!(rows, parity_check("mtr_symmetric", "T_l[$i]",
                                 sol[ssys.cac_l.T[i]], PARITY_MTR_SYM_T_CELLS_L[i]))
        push!(rows, parity_check("mtr_symmetric", "T_r[$i]",
                                 sol[ssys.cac_r.T[i]], PARITY_MTR_SYM_T_CELLS_R[i]))
    end
    dz = 0.6 / nz
    heated_part = geom_mtr.heated_parts[1]   # 0.07 m
    for i in 1:nz
        # Left channel
        push!(rows, parity_check("mtr_symmetric", "T_wall_left_l[$i]",
                                 sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T],
                                 PARITY_MTR_SYM_T_WALL_LEFT_L[i]))
        push!(rows, parity_check("mtr_symmetric", "T_wall_right_l[$i]",
                                 sol[getproperty(ssys.cac_l, Symbol(:thermal_right, i)).T],
                                 PARITY_MTR_SYM_T_WALL_RIGHT_L[i]))
        h_eff_cac_l = _h_eff(sol, ssys.cac_l, i)
        push!(rows, parity_check("mtr_symmetric", "h_tc_left_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_SYM_H_TC_LEFT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_symmetric", "h_tc_right_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_SYM_H_TC_RIGHT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_symmetric", "q_left_l[$i]",
                                 sol[ssys.cac_l.q_wall_left[i]] / (heated_part * dz),
                                 PARITY_MTR_SYM_Q_LEFT_L[i]))
        push!(rows, parity_check("mtr_symmetric", "q_right_l[$i]",
                                 sol[ssys.cac_l.q_wall_right[i]] / (heated_part * dz),
                                 PARITY_MTR_SYM_Q_RIGHT_L[i]))
        # Right channel mirror
        push!(rows, parity_check("mtr_symmetric", "T_wall_left_r[$i]",
                                 sol[getproperty(ssys.cac_r, Symbol(:thermal_left, i)).T],
                                 PARITY_MTR_SYM_T_WALL_LEFT_R[i]))
        push!(rows, parity_check("mtr_symmetric", "T_wall_right_r[$i]",
                                 sol[getproperty(ssys.cac_r, Symbol(:thermal_right, i)).T],
                                 PARITY_MTR_SYM_T_WALL_RIGHT_R[i]))
        h_eff_cac_r = _h_eff(sol, ssys.cac_r, i)
        push!(rows, parity_check("mtr_symmetric", "h_tc_left_r[$i]",
                                 h_eff_cac_r,
                                 PARITY_MTR_SYM_H_TC_LEFT_R[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_symmetric", "h_tc_right_r[$i]",
                                 h_eff_cac_r,
                                 PARITY_MTR_SYM_H_TC_RIGHT_R[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_symmetric", "q_left_r[$i]",
                                 sol[ssys.cac_r.q_wall_left[i]] / (heated_part * dz),
                                 PARITY_MTR_SYM_Q_LEFT_R[i]))
        push!(rows, parity_check("mtr_symmetric", "q_right_r[$i]",
                                 sol[ssys.cac_r.q_wall_right[i]] / (heated_part * dz),
                                 PARITY_MTR_SYM_Q_RIGHT_R[i]))
    end

    for z in 1:nz, x in 1:nx
        push!(rows, parity_check("mtr_symmetric", "T_plate[$(z)_$(x)]",
                                 sol[ssys.hd.T[z, x]],
                                 PARITY_MTR_SYM_T_PLATE[z, x]))
    end

    print_drift_table(rows)
    append_csv(PARITY_CSV, rows; truncate=false)

    for r in rows
        @test r.tier != TIER_FAIL
    end
end

# Asymmetric MTR — right channel inlet at 90°C (90.0 °C)
# Right side of plate must be hotter than left side.
@testset "Python parity: MTR asymmetric" begin
    assert_equivalence_fluid_props()
    assert_equivalence_dittus_boelter()
    assert_equivalence_blasius()
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    assert_equivalence_geometry(geom_mtr,
        PARITY_MTR_GEOM_DH, PARITY_MTR_GEOM_AREA,
        PARITY_MTR_GEOM_WETPERIM, PARITY_MTR_GEOM_HEATED;
        rtol=1e-9)
    assert_equivalence_anchors()

    nz = 10
    nx = 3
    T_in_l = 40.0
    T_in_r = 90.0
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in_l)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(T_in_r)
    @named cac_r = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(;
        nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps, power=1e4,
    )
    conns = [
            inseries(pump_l, hx_l, cac_l, pump_l)...,
            pump_l.inlet.p ~ 1.0e5,
            inseries(pump_r, hx_r, cac_r, pump_r)...,
            pump_r.inlet.p ~ 1.0e5,
        connect_faces((hd, :thermal_left) => (cac_l, :thermal_right))...,
        connect_faces((hd, :thermal_right) => (cac_r, :thermal_left))...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(
        System(conns, t; name=:mtr_asym_parity), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd
    )
    ssys = mtkcompile(sys; fully_determined=true)

    op = vcat(
        [ssys.hd.T[i, j] => 45.0 for i in 1:nz for j in 1:(nx - 1)],
        [ssys.hd.T[i, nx] => 95.0 for i in 1:nz],
        [ssys.cac_l.T[i] => 45.0 for i in 1:nz],
        [ssys.cac_r.T[i] => 95.0 for i in 1:nz],
            [ssys.cac_l.inlet.ṁ => +0.250],
            [ssys.cac_r.inlet.ṁ => +0.250],
    )
    rows = ParityRow[]
    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test all(isfinite, [sol[ssys.hd.T[i, j]] for i in 1:nz for j in 1:nx])

    push!(rows, parity_check("mtr_asymmetric", "T_out_l",
                             sol[ssys.cac_l.T_out], PARITY_MTR_ASYM_T_OUT_L))
    push!(rows, parity_check("mtr_asymmetric", "T_out_r",
                             sol[ssys.cac_r.T_out], PARITY_MTR_ASYM_T_OUT_R))
        push!(
            rows,
            parity_check(
                "mtr_asymmetric",
                "ṁ_l",
                abs(sol[ssys.cac_l.inlet.ṁ]),
                PARITY_MTR_ASYM_ṁ_L,
            ),
        )
        push!(
            rows,
            parity_check(
                "mtr_asymmetric",
                "ṁ_r",
                abs(sol[ssys.cac_r.inlet.ṁ]),
                PARITY_MTR_ASYM_ṁ_R,
            ),
        )
    push!(rows, parity_check("mtr_asymmetric", "dP_loop",
                             sol[ssys.cac_l.dP], PARITY_MTR_ASYM_DP))

    for i in 1:nz
        push!(rows, parity_check("mtr_asymmetric", "T_l[$i]",
                                 sol[ssys.cac_l.T[i]], PARITY_MTR_ASYM_T_CELLS_L[i]))
        push!(rows, parity_check("mtr_asymmetric", "T_r[$i]",
                                 sol[ssys.cac_r.T[i]], PARITY_MTR_ASYM_T_CELLS_R[i]))
    end

    dz = 0.6 / nz
    heated_part = geom_mtr.heated_parts[1]
    for i in 1:nz
        # Left channel
        push!(rows, parity_check("mtr_asymmetric", "T_wall_left_l[$i]",
                                 sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T],
                                 PARITY_MTR_ASYM_T_WALL_LEFT_L[i]))
        push!(rows, parity_check("mtr_asymmetric", "T_wall_right_l[$i]",
                                 sol[getproperty(ssys.cac_l, Symbol(:thermal_right, i)).T],
                                 PARITY_MTR_ASYM_T_WALL_RIGHT_L[i]))
        h_eff_cac_l = _h_eff(sol, ssys.cac_l, i)
        push!(rows, parity_check("mtr_asymmetric", "h_tc_left_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_ASYM_H_TC_LEFT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_asymmetric", "h_tc_right_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_ASYM_H_TC_RIGHT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_asymmetric", "q_left_l[$i]",
                                 sol[ssys.cac_l.q_wall_left[i]] / (heated_part * dz),
                                 PARITY_MTR_ASYM_Q_LEFT_L[i]))
        push!(rows, parity_check("mtr_asymmetric", "q_right_l[$i]",
                                 sol[ssys.cac_l.q_wall_right[i]] / (heated_part * dz),
                                 PARITY_MTR_ASYM_Q_RIGHT_L[i]))
        push!(rows, parity_check("mtr_asymmetric", "T_wall_left_r[$i]",
                                 sol[getproperty(ssys.cac_r, Symbol(:thermal_left, i)).T],
                                 PARITY_MTR_ASYM_T_WALL_LEFT_R[i]))
        push!(rows, parity_check("mtr_asymmetric", "T_wall_right_r[$i]",
                                 sol[getproperty(ssys.cac_r, Symbol(:thermal_right, i)).T],
                                 PARITY_MTR_ASYM_T_WALL_RIGHT_R[i]))
        h_eff_cac_r = _h_eff(sol, ssys.cac_r, i)
        push!(rows, parity_check("mtr_asymmetric", "h_tc_left_r[$i]",
                                 h_eff_cac_r,
                                 PARITY_MTR_ASYM_H_TC_LEFT_R[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_asymmetric", "h_tc_right_r[$i]",
                                 h_eff_cac_r,
                                 PARITY_MTR_ASYM_H_TC_RIGHT_R[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_asymmetric", "q_left_r[$i]",
                                 sol[ssys.cac_r.q_wall_left[i]] / (heated_part * dz),
                                 PARITY_MTR_ASYM_Q_LEFT_R[i]))
        push!(rows, parity_check("mtr_asymmetric", "q_right_r[$i]",
                                 sol[ssys.cac_r.q_wall_right[i]] / (heated_part * dz),
                                 PARITY_MTR_ASYM_Q_RIGHT_R[i]))
    end

    for z in 1:nz, x in 1:nx
        push!(rows, parity_check("mtr_asymmetric", "T_plate[$(z)_$(x)]",
                                 sol[ssys.hd.T[z, x]],
                                 PARITY_MTR_ASYM_T_PLATE[z, x]))
    end

    print_drift_table(rows)
    append_csv(PARITY_CSV, rows; truncate=false)

    for r in rows
        @test r.tier != TIER_FAIL
    end
end

@testset "Python parity: MTR one-sided" begin
    # Edge-channel coupling via single_channel_connection: the channel is heated on its
    # connected (left) face only, while the fuel plate is cooled on BOTH faces — the near
    # face conjugately through the channel, the far face by a one-way ConvectiveBoundary
    # fed from the channel's connected-side h_tc and coolant T (the equivalent-twin
    # reduction Python's one_sided_connection models). With both faces cooled identically
    # the plate is symmetric and every row matches the Python reference at normal tolerance.
    assert_equivalence_fluid_props()
    assert_equivalence_dittus_boelter()
    assert_equivalence_blasius()
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    assert_equivalence_geometry(geom_mtr,
        PARITY_MTR_GEOM_DH, PARITY_MTR_GEOM_AREA,
        PARITY_MTR_GEOM_WETPERIM, PARITY_MTR_GEOM_HEATED;
        rtol=1e-9)  # PARITY_MTR_GEOM_DH pasted at %.10e (~10 sig figs) — 1e-12 too tight
    assert_equivalence_anchors()

    nz = 10
    nx = 3
    T_in = 40.0
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(;
        nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps, power=1e4,
    )
    scc = single_channel_connection(cac_l, hd, geom_mtr; fuel_side=:left, name=:scc)
    cac = scc.cac_l
    fuel = scc.hd
    conns = [
            inseries(pump_l, hx_l, cac, pump_l)...,
            pump_l.inlet.p ~ 1.0e5,
        fuel.power ~ 1e4,
    ]
    @named sys = compose(System(conns, t; name=:mtr_onesided_parity), pump_l, hx_l, scc)
    ssys = mtkcompile(sys; fully_determined=true)

    cac_s = ssys.scc.cac_l
    fuel_s = ssys.scc.hd
    T_w = 43.85
    op = vcat(
        [fuel_s.T[i, j] => T_w for i in 1:nz for j in 1:nx],
        [cac_s.T[i] => T_w for i in 1:nz],
            [cac_s.inlet.ṁ => +0.250],
    )
    rows = ParityRow[]
    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test all(isfinite, [sol[fuel_s.T[i, j]] for i in 1:nz for j in 1:nx])

    push!(rows, parity_check("mtr_one_sided", "T_out_l",
                             sol[cac_s.T_out], PARITY_MTR_ONESIDED_T_OUT_L))
        push!(
            rows,
            parity_check(
                "mtr_one_sided",
                "ṁ_l",
                abs(sol[cac_s.inlet.ṁ]),
                PARITY_MTR_ONESIDED_ṁ_L,
            ),
        )
    push!(rows, parity_check("mtr_one_sided", "dP_loop",
                             sol[cac_s.dP], PARITY_MTR_ONESIDED_DP))

    for i in 1:nz
        push!(rows, parity_check("mtr_one_sided", "T_l[$i]",
                                 sol[cac_s.T[i]], PARITY_MTR_ONESIDED_T_CELLS_L[i]))
    end

    dz = 0.6 / nz
    heated_part = geom_mtr.heated_parts[1]
    for i in 1:nz
        push!(rows, parity_check("mtr_one_sided", "T_wall_left_l[$i]",
                                 sol[getproperty(cac_s, Symbol(:thermal_left, i)).T],
                                 PARITY_MTR_ONESIDED_T_WALL_LEFT_L[i]))
        push!(rows, parity_check("mtr_one_sided", "T_wall_right_l[$i]",
                                 sol[getproperty(cac_s, Symbol(:thermal_right, i)).T],
                                 PARITY_MTR_ONESIDED_T_WALL_RIGHT_L[i]))
        h_eff_cac_l = _h_eff(sol, cac_s, i)
        push!(rows, parity_check("mtr_one_sided", "h_tc_left_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_ONESIDED_H_TC_LEFT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_one_sided", "h_tc_right_l[$i]",
                                 h_eff_cac_l,
                                 PARITY_MTR_ONESIDED_H_TC_RIGHT_L[i];
                                 note="connected-side h (heat-transferring face) — mirrors Python _other_if_none"))
        push!(rows, parity_check("mtr_one_sided", "q_left_l[$i]",
                                 sol[cac_s.q_wall_left[i]] / (heated_part * dz),
                                 PARITY_MTR_ONESIDED_Q_LEFT_L[i]))
        push!(rows, parity_check("mtr_one_sided", "q_right_l[$i]",
                                 sol[cac_s.q_wall_right[i]] / (heated_part * dz),
                                 PARITY_MTR_ONESIDED_Q_RIGHT_L[i]))
    end

    for z in 1:nz, x in 1:nx
        push!(rows, parity_check("mtr_one_sided", "T_plate[$(z)_$(x)]",
                                 sol[fuel_s.T[z, x]],
                                 PARITY_MTR_ONESIDED_T_PLATE[z, x]))
    end

    print_drift_table(rows)
    append_csv(PARITY_CSV, rows; truncate=false)
    for r in rows
        @test r.tier != TIER_FAIL
    end

    # Independent analytic anchor: with both faces cooled symmetrically the plate has a
    # parabolic lateral profile peaking at the centre column, rising power*Lx/(8*k*A)
    # above the wall (half-thickness conduction, both faces shedding equal flux).
    A_plate = 0.07 * 0.6
    mid = nz ÷ 2
    centre = nx ÷ 2 + 1
    T_centre_numerical = sol[fuel_s.T[mid, centre]]
    T_wall_mid = sol[getproperty(cac_s, Symbol(:thermal_left, mid)).T]
    T_centre_analytical = T_wall_mid + 1e4 * 0.00127 / (8 * 200.0 * A_plate)
    @test isapprox(T_centre_numerical, T_centre_analytical; atol=0.05)

    # Both-faces signature: each plate row is laterally symmetric (left col == right col).
    for z in 1:nz
        @test isapprox(sol[fuel_s.T[z, 1]], sol[fuel_s.T[z, nx]]; rtol=1e-6)
    end

end
end  # @testset "parity harness"

@testset "HeatDiffusion transient — Fourier series validation" begin
    nz_v01 = 10
    # nx_v01=13 lateral cells: the FD is O(dx^2), so the steepest early checkpoint needs
    # a fine-enough mesh to meet rtol=0.01 against the exact Fourier series. Convergence
    # was verified (max checkpoint error: nx=5 -> 1.38%, nx=9 -> 0.44%, nx=13 -> 0.10%),
    # confirming HeatDiffusion converges to the analytical solution.
    nx_v01 = 13
    k_s_v01 = 200.0
    rho_s_v01 = 2700.0
    cp_s_v01 = 900.0
    Lx_v01 = 0.00127
    Lz_v01 = 0.6
    y_v01 = 0.07
    T_wall = 26.85
    T0 = 126.85   # 100 K step-down for clear signal

    alpha_v01 = k_s_v01 / (rho_s_v01 * cp_s_v01)   # ≈ 8.23e-5 m²/s
    tau_v01 = Lx_v01^2 / (π^2 * alpha_v01)        # ≈ 0.002 s

    function fourier_T_center(t_val)
        result = T_wall
        for k in 0:49
            n = 2k + 1
            result +=
                (4 / π) *
                (T0 - T_wall) *
                ((-1)^k / n) *
                exp(-alpha_v01 * (n * π / Lx_v01)^2 * t_val)
        end
        return result
    end

    ps_v01 = fill(1.0 / (nz_v01 * nx_v01), nz_v01, nx_v01)
    @named hd_v01 = HeatDiffusion(;
        nz=nz_v01,
        nx=nx_v01,
        Lz=Lz_v01,
        Lx=Lx_v01,
        y=y_v01,
        rho_s=rho_s_v01,
        cp_s=cp_s_v01,
        k_s=k_s_v01,
        power_shape=ps_v01,
        power=0.0,
    )
    ct_l = [ConstantTemperature(T_wall; name=Symbol(:ct_l_, i)) for i in 1:nz_v01]
    ct_r = [ConstantTemperature(T_wall; name=Symbol(:ct_r_, i)) for i in 1:nz_v01]
    conns_v01 = [
        [
            connect(ct_l[i].thermal, getproperty(hd_v01, Symbol(:thermal_left, i))) for
            i in 1:nz_v01
        ]...,
        [
            connect(ct_r[i].thermal, getproperty(hd_v01, Symbol(:thermal_right, i))) for
            i in 1:nz_v01
        ]...,
        hd_v01.power ~ 0.0,
    ]
    @named sys_v01 = compose(
        System(conns_v01, t; name=:val01_sys), ct_l..., ct_r..., hd_v01
    )
    ssys_v01 = mtkcompile(sys_v01; fully_determined=true)

    op_ic_v01 = [ssys_v01.hd_v01.T[i, j] => T0 for i in 1:nz_v01 for j in 1:nx_v01]

    t_checkpoints = [0.5 * tau_v01, tau_v01, 2 * tau_v01, 5 * tau_v01]
    tspan_v01 = (0.0, 5.0 * tau_v01 * 1.01)
    prob_v01 = ODEProblem(ssys_v01, op_ic_v01, tspan_v01; warn_initialize_determined=false)
    # All plate cells are given consistent ICs (uniform T0); the only algebraic vars
    # (thermal-port Q) are explicit in those ICs. MTK's auto-generated OverrideInit
    # nonlinear solve is fragile for this all-differential structure, so verify IC
    # consistency (CheckInit) instead of re-solving it.
    sol_v01 = solve(prob_v01, Rodas5P(); initializealg=CheckInit(),
                    reltol=1e-8, abstol=1e-10, saveat=t_checkpoints)
    @test sol_v01.retcode == ReturnCode.Success

    T_center_sym = ssys_v01.hd_v01.T[nz_v01 ÷ 2, (nx_v01 + 1) ÷ 2]
    T_center_series = sol_v01[T_center_sym, :]
    # Tolerances are a fraction of the imposed step, not of the temperature itself. A
    # relative tolerance on a Celsius reading is measured against where the scale happens
    # to put its zero, so the same 1% would mean a different physical band here than it
    # does at, say, 300 °C. The step is the scale the problem actually sets.
    tol_v01 = 0.01 * abs(T0 - T_wall)
    for (k, t_k) in enumerate(t_checkpoints)
        T_num = T_center_series[k]
        T_ref = fourier_T_center(t_k)
        @test isapprox(T_num, T_ref; atol=tol_v01)
    end

    @test isapprox(T_center_series[end], T_wall; atol=tol_v01)
end

@testset "Two-plate one-channel topology — both faces active" begin
    nz_v02 = 10
    nx_v02 = 3
    T_in_v02 = 40.0
    power_per_plate = 1e4   # W each → 20 kW total to one channel

    @named pump_v02 = Pump(3.0e4)
    @named hx_v02 = HeatExchanger(T_in_v02)
    @named cac_v02 = ChannelAndContacts(;
        n=nz_v02, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    )
    ps_v02 = fill(1.0 / (nz_v02 * nx_v02), nz_v02, nx_v02)
    @named hd1 = HeatDiffusion(;
        nz=nz_v02,
        nx=nx_v02,
        Lz=0.6,
        Lx=0.00127,
        y=0.07,
        rho_s=2700.0,
        cp_s=900.0,
        k_s=200.0,
        power_shape=ps_v02,
        power=power_per_plate,
    )
    @named hd2 = HeatDiffusion(;
        nz=nz_v02,
        nx=nx_v02,
        Lz=0.6,
        Lx=0.00127,
        y=0.07,
        rho_s=2700.0,
        cp_s=900.0,
        k_s=200.0,
        power_shape=ps_v02,
        power=power_per_plate,
    )

    conns_v02 = [
        # Hydraulic loop
        inseries(pump_v02, hx_v02, cac_v02, pump_v02)...,
        pump_v02.inlet.p ~ 1.0e5,
        # hd1 left face → cac thermal_left (hd1 is on the left of the channel)
        [
            connect(
                getproperty(hd1, Symbol(:thermal_left, i)),
                getproperty(cac_v02, Symbol(:thermal_left, i)),
            ) for i in 1:nz_v02
        ]...,
        # hd2 left face → cac thermal_right (hd2 is on the right of the channel, facing inward)
        [
            connect(
                getproperty(hd2, Symbol(:thermal_left, i)),
                getproperty(cac_v02, Symbol(:thermal_right, i)),
            ) for i in 1:nz_v02
        ]...,
        hd1.power ~ power_per_plate,
        hd2.power ~ power_per_plate,
    ]
    @named sys_v02 = compose(
        System(conns_v02, t; name=:val02_sys), pump_v02, hx_v02, cac_v02, hd1, hd2
    )
    ssys_v02 = mtkcompile(sys_v02; fully_determined=true)

    # Initial guess: plate T slightly above T_in, ṁ +0.250 (rectangular MTR at 30 kPa)
    T_guess_v02 = T_in_v02 + 10.0
    op_v02 = vcat(
        [ssys_v02.hd1.T[i, j] => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
        [ssys_v02.hd2.T[i, j] => T_guess_v02 for i in 1:nz_v02 for j in 1:nx_v02],
        [ssys_v02.cac_v02.T[i] => T_guess_v02 for i in 1:nz_v02],
        [ssys_v02.cac_v02.inlet.ṁ => +0.250],
    )
    sol_v02 = solve_steady(ssys_v02, op_v02)

    # Assertion 1: solver converged
    @test sol_v02.retcode == ReturnCode.Success

    # Assertion 2: energy balance — both plates heat the single channel
    ṁ_v02 = sol_v02[ssys_v02.cac_v02.inlet.ṁ]
    cp_v02 = cₚ(H2O, T_in_v02)
    T_rise_expected_v02 = (power_per_plate + power_per_plate) / (ṁ_v02 * cp_v02)
    @test isapprox(
        sol_v02[ssys_v02.cac_v02.T_out] - T_in_v02, T_rise_expected_v02; rtol=0.05
    )

    # Assertion 3: each plate center hotter than fluid midpoint (plate has internal source)
    mid = nz_v02 ÷ 2
    lat = (nx_v02 + 1) ÷ 2
    @test sol_v02[ssys_v02.hd1.T[mid, lat]] > sol_v02[ssys_v02.cac_v02.T[mid]]
    @test sol_v02[ssys_v02.hd2.T[mid, lat]] > sol_v02[ssys_v02.cac_v02.T[mid]]

    # Assertion 4: Q < 0 on connected faces (heat flows FROM plate TO fluid, MTK convention)
    # hd1: thermal_left[i] is connected → Q < 0
    # hd2: thermal_left[i] is connected → Q < 0
    for i in 1:nz_v02
        @test sol_v02[getproperty(ssys_v02.hd1, Symbol(:thermal_left, i)).Q] < 0.0
        @test sol_v02[getproperty(ssys_v02.hd2, Symbol(:thermal_left, i)).Q] < 0.0
    end
end

@testset "PointKinetics validation" begin
    @testset "constant-power coolant temperature rises linearly" begin
        # Mirror Python STREAM test_integrations.py lines 201-267
        # (test_channel_point_kinetics): constant-power PK coupled loop, time-march
        # to thermal equilibrium, assert T_cool is strictly monotone along the channel
        # and approximately linear (second differences near zero).
        #
        # No temperature feedback: rho stays 0, so the critical PK holds P at P0=1 and
        # the channel sees a steady power. The genuine coupled physics is the transient
        # that settles to the steady coolant profile. A coupled feedback-PK solve_steady
        # is NOT used here: Julia's globalized nonlinear solver collapses critical point
        # kinetics to the trivial P=0 root (the dynamically stable fixed point), so the
        # steady channel would see no power. Time-marching reaches the real physical
        # steady state (P=1, linearly rising coolant), the same as the reference coupled
        # transients in test_point_kinetics.jl.
        n = 7
        T_inlet = 20.0
        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(ctrl; n=n, T_inlet=T_inlet, P0=1.0, power_scale=1e4)

        t_arr = range(0.0, 50.0; length=200)
        sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
        @test sol.retcode == ReturnCode.Success
        @test isapprox(sol[ssys.pk.P, end], 1.0; rtol=1e-3)   # critical PK holds power
        T_cool = [sol[ssys.rods.cac.T[i], end] for i in 1:n]

        dT = diff(T_cool)       # first differences  (should all be > 0)
        ddT = diff(dT)           # second differences (should be near zero for linear rise)

        @test all(dT .> 0)                                 # strictly rising along channel
        @test isapprox(ddT, zeros(length(ddT)); atol=0.5)  # approximately linear
    end

    @testset "negative fuel feedback suppresses power to near zero" begin
        # Mirror Python STREAM test_integrations.py lines 352-387:
        # negative alpha on fuel with ref_temp at the initial (boundary) temperature.
        # As power heats the fuel above T_inlet, feedback = alpha * (T_fuel - T_ref) goes
        # negative. Strong alpha=-0.1 over a ~120 K fuel rise gives feedback far past
        # -beta_total, so the coupled loop drives power to near zero.
        #
        # Run the live coupled feedback transient from the cold critical IC (reactivity = 0
        # at t=0), the same approach as the reference coupled tests in test_point_kinetics.jl.
        # A feedback-PK solve_steady is not used: Julia's nonlinear solver collapses the
        # coupled point kinetics to the trivial P=0 root regardless of guess, so it cannot
        # report the real feedback-balanced state. The transient settles onto it honestly.
        n = 7
        nz = 7
        nx = 2
        T_inlet = 20.0
        alpha_neg = -0.1    # strong negative feedback (same magnitude as Python STREAM)

        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(
            ctrl;
            n=n,
            nz=nz,
            nx=nx,
            T_inlet=T_inlet,
            P0=1.0,
            power_scale=1e4,
            temp_worth=Dict(:fuel => fill(alpha_neg, nz, nx)),     # nz×nx matrix for HeatDiffusion
            ref_temp=Dict(:fuel => fill(T_inlet, nz, nx)),       # ref = initial T; feedback negative as fuel heats up
        )

        t_arr = range(0.0, 200.0; length=500)
        sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
        @test sol.retcode == ReturnCode.Success
        P = sol[ssys.pk.P]
        @test all(isfinite, P)
        @test all(>(0.0), P)              # power positive throughout — decays, never goes negative
        @test abs(P[end]) < 1e-3          # feedback drives power negligible vs P0 = 1.0
    end

    @testset "negative coolant feedback suppresses power to near zero" begin
        # Mirror Python STREAM test_integrations.py lines 390-428:
        # negative alpha on coolant with ref_temp=T_inlet. Coolant heats above T_inlet, so
        # feedback goes negative and power collapses to near zero.
        #
        # Live coupled feedback transient from the cold critical IC, same as the fuel-feedback
        # case above and the reference coupled tests in test_point_kinetics.jl. The coupled
        # feedback solve_steady is not usable in Julia (it collapses to the trivial P=0 root),
        # so the transient is the honest way to reach the feedback-balanced state.
        n = 7
        T_inlet = 20.0
        alpha_neg = -0.1   # strong negative feedback on coolant

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

        t_arr = range(0.0, 200.0; length=500)
        sol = solve_transient(ssys, ic, t_arr; maxiters=1_000_000)
        @test sol.retcode == ReturnCode.Success
        P = sol[ssys.pk.P]
        @test all(isfinite, P)
        @test all(>(0.0), P)              # power positive throughout — decays, never goes negative
        @test abs(P[end]) < 1e-3          # feedback drives power negligible vs P0 = 1.0
    end

    @testset "reactivity observable accessible and correct at steady state" begin
        # Verify that sol[ssys.pk.reactivity, :] is accessible post-solve,
        # is a finite vector, and approaches zero at late time
        # (steady state requires net reactivity ≈ 0).
        n = 7
        T_inlet = 20.0
        alpha = -0.005   # mild negative feedback — allows some power at late time
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

        # Reactivity observable must be accessible and well-behaved
        rho_trace = sol[ssys.pk.reactivity, :]
        @test rho_trace isa AbstractVector
        @test length(rho_trace) > 1
        @test all(isfinite, rho_trace)

        # At late time (t=50s), reactivity should be near zero
        # (dP/dt=0 at steady state requires net reactivity ≈ 0)
        @test abs(rho_trace[end]) < 0.01
    end
end  # @testset "PointKinetics validation"
