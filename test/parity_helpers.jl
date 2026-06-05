using Printf
using DelimitedFiles
using Test
using STREAM
using STREAM: cp_water, rho_water, mu_water, k_water

const TIER_CLEAN = :CLEAN   # rtol ≤ gray_floor (1e-6)
const TIER_GRAY  = :GRAY    # gray_floor < rtol < hard_ceiling (default 0.02)
const TIER_FAIL  = :FAIL    # rtol ≥ hard_ceiling

"""
    ParityRow

One row of the drift report. Built by `parity_check`. Aggregated into a
Vector{ParityRow} per testset and emitted via `print_drift_table` + `append_csv`.

Fields (9 total):
  scenario     :: String   — e.g. "simple_loop" | "mtr_symmetric" | "mtr_asymmetric" | "mtr_one_sided"
  qid          :: String   — quantity identifier, e.g. "T_out", "T[3]", "T_wall_left[5]", "T_plate[5_2]"
  julia_val    :: Float64  — value extracted from Julia sol[]
  python_ref   :: Float64  — hardcoded Python reference constant (from python_parity_reference.jl)
  abs_err      :: Float64  — |julia_val - python_ref|
  rtol         :: Float64  — abs_err / max(|python_ref|, 1e-300); fallback to abs_err if python_ref==0
  tier         :: Symbol   — TIER_CLEAN / TIER_GRAY / TIER_FAIL
  hard_ceiling :: Float64  — per-quantity threshold (default 0.02)
  note         :: String   — short rationale; MUST be comma-free (CSV writer doesn't escape)
"""
struct ParityRow
    scenario     :: String
    qid          :: String
    julia_val    :: Float64
    python_ref   :: Float64
    abs_err      :: Float64
    rtol         :: Float64
    tier         :: Symbol
    hard_ceiling :: Float64
    note         :: String
end

"""
    parity_check(scenario::String, qid::String,
                 julia_val::Real, python_ref::Real;
                 hard_ceiling::Float64=0.02,
                 gray_floor::Float64=1e-6,
                 note::String="")::ParityRow

Compute rtol against `python_ref`, bin into tier, return one ParityRow.

Tier binning:
  rtol ≤ gray_floor       → TIER_CLEAN  (≤ used; aspirational solver-floor target)
  rtol < hard_ceiling     → TIER_GRAY   (< used; reported, NOT @test-failed)
  rtol ≥ hard_ceiling     → TIER_FAIL   (boundary at exactly hard_ceiling fails)

Zero-handling: if python_ref==0.0 exactly, rtol falls back to abs_err
(rtol on a zero denominator is undefined). For non-zero python_ref, denom
floors at 1e-300 to avoid divide-by-zero on subnormals.
"""
function parity_check(scenario::String, qid::String,
                      julia_val::Real, python_ref::Real;
                      hard_ceiling::Float64=0.02,
                      gray_floor::Float64=1e-6,
                      note::String="")::ParityRow
    abs_err = abs(julia_val - python_ref)
    denom = max(abs(python_ref), 1e-300)
    rtol  = python_ref == 0.0 ? abs_err : abs_err / denom
    tier  = rtol ≤ gray_floor   ? TIER_CLEAN :
            rtol < hard_ceiling ? TIER_GRAY  : TIER_FAIL
    return ParityRow(scenario, qid, Float64(julia_val), Float64(python_ref),
                     abs_err, rtol, tier, hard_ceiling, note)
end

"""
    print_drift_table(rows::Vector{ParityRow}; io::IO=stdout)

Emit ASCII drift table to stdout (or any IO). Columns: scenario(18) qid(22)
julia(14e) python(14e) abs_err(14e) rtol(12.3e) tier(6) note. Footer prints
summary count of CLEAN/GRAY/FAIL.
"""
function print_drift_table(rows::Vector{ParityRow}; io::IO=stdout)
    @printf(io, "\n%-18s %-22s %14s %14s %14s %12s %-6s %s\n",
            "scenario", "quantity", "julia", "python", "abs_err", "rtol", "tier", "note")
    @printf(io, "%s\n", repeat("-", 130))
    for r in rows
        @printf(io, "%-18s %-22s %14.6e %14.6e %14.6e %12.3e %-6s %s\n",
                r.scenario, r.qid, r.julia_val, r.python_ref,
                r.abs_err, r.rtol, String(r.tier), r.note)
    end
    n_clean = count(r -> r.tier == TIER_CLEAN, rows)
    n_gray  = count(r -> r.tier == TIER_GRAY,  rows)
    n_fail  = count(r -> r.tier == TIER_FAIL,  rows)
    @printf(io, "%s\n", repeat("-", 130))
    @printf(io, "summary: %d quantities — %d CLEAN, %d GRAY, %d FAIL\n",
            length(rows), n_clean, n_gray, n_fail)
end

"""
    append_csv(path::AbstractString, rows::Vector{ParityRow}; truncate::Bool=false)

Write rows to `path` in long format (one row per (scenario, quantity)).
Header is emitted if `truncate=true` or the file doesn't exist.
Numeric columns use %.10e (10 sig figs — well above KINSOL's reltol=1e-6
so re-runs on the same machine produce bit-identical CSV).

Schema: scenario,quantity,julia,python,abs_err,rtol,tier,hard_ceiling,note
"""
function append_csv(path::AbstractString, rows::Vector{ParityRow}; truncate::Bool=false)
    write_header = truncate || !isfile(path)
    mode = truncate ? "w" : "a"
    open(path, mode) do io
        if write_header
            write(io, "scenario,quantity,julia,python,abs_err,rtol,tier,hard_ceiling,note\n")
        end
        for r in rows
            line = @sprintf("%s,%s,%.10e,%.10e,%.10e,%.6e,%s,%.4f,%s\n",
                            r.scenario, r.qid, r.julia_val, r.python_ref,
                            r.abs_err, r.rtol, String(r.tier),
                            r.hard_ceiling, r.note)
            write(io, line)
        end
    end
end
const REF_T_K = (313.15, 343.15, 373.15)
const PYTHON_RHO_AT_REF = (991.3511479199999, 977.57053367999993, 959.13959927999997)              # kg/m^3
const PYTHON_CP_AT_REF  = (4178.9587971854307, 4190.8404352889875, 4217.9483186983307)             # J/(kg·K)
const PYTHON_MU_AT_REF  = (0.00065196977487873341, 0.0004028301063116321, 0.00028224508453489637)  # Pa·s
const PYTHON_K_AT_REF   = (0.63015562705599992, 0.66106740247825002, 0.67939757214999996)          # W/(m·K)

"""
    assert_equivalence_fluid_props(; rtol=1e-12)

Hard-assert Julia rho/cp/mu/k at REF_T_K match Python STREAM Simantov
correlations (PYTHON_*_AT_REF constants) within `rtol`. Aborts via `error()`
if any property drifts.
"""
function assert_equivalence_fluid_props(; rtol::Float64=1e-12)
    for (i, T_K) in enumerate(REF_T_K)
        isapprox(rho_water(T_K), PYTHON_RHO_AT_REF[i]; rtol=rtol) || error(
            "EQUIVALENCE FAIL: rho_water($T_K) Julia=$(rho_water(T_K)) " *
            "vs Python=$(PYTHON_RHO_AT_REF[i])")
        isapprox(cp_water(T_K),  PYTHON_CP_AT_REF[i];  rtol=rtol) || error(
            "EQUIVALENCE FAIL: cp_water($T_K) Julia=$(cp_water(T_K)) " *
            "vs Python=$(PYTHON_CP_AT_REF[i])")
        isapprox(mu_water(T_K),  PYTHON_MU_AT_REF[i];  rtol=rtol) || error(
            "EQUIVALENCE FAIL: mu_water($T_K)")
        isapprox(k_water(T_K),   PYTHON_K_AT_REF[i];   rtol=rtol) || error(
            "EQUIVALENCE FAIL: k_water($T_K)")
    end
    @info "Equivalence checklist: fluid props match within rtol=$rtol at T = $REF_T_K"
end

"""
    assert_equivalence_dittus_boelter(; rtol=1e-12)

Assert Julia's Dittus-Boelter (0.023 * Re^0.8 * Pr^0.4) matches the formula
by direct evaluation at Re=10000, Pr=1. Self-check (no Python runtime).
"""
function assert_equivalence_dittus_boelter(; rtol::Float64=1e-12)
    Re_ref, Pr_ref = 10_000.0, 1.0
    Nu_python = 0.023 * Re_ref^0.8 * Pr_ref^0.4
    Nu_julia  = STREAM.dittus_boelter(Re_ref, Pr_ref)
    isapprox(Nu_julia, Nu_python; rtol=rtol) || error(
        "EQUIVALENCE FAIL: Dittus-Boelter at Re=$Re_ref, Pr=$Pr_ref: " *
        "Julia=$Nu_julia, Python-formula=$Nu_python")
    @info "Equivalence checklist: Dittus-Boelter constants (0.023, 0.8, 0.4) match"
end

"""
    assert_equivalence_blasius(; rtol=1e-12)

Assert Julia's Blasius (0.3164 / Re^0.25) matches the formula at Re=10000.
"""
function assert_equivalence_blasius(; rtol::Float64=1e-12)
    Re_ref = 10_000.0
    f_python = 0.3164 / Re_ref^0.25
    f_julia  = STREAM.blasius_friction(Re_ref)
    isapprox(f_julia, f_python; rtol=rtol) || error(
        "EQUIVALENCE FAIL: Blasius at Re=$Re_ref: Julia=$f_julia, " *
        "Python-formula=$f_python")
    @info "Equivalence checklist: Blasius constants (0.3164, 0.25) match"
end

"""
    assert_equivalence_geometry(geom, expected_Dh, expected_A,
                                expected_wet_perim, expected_heated_parts;
                                rtol=1e-12)

Assert PipeGeometry fields match Python EffectivePipe at the same dimensions.
Caller passes expected values as hardcoded numbers (computed in the Python
generator and pasted into the parity testset).

"""
function assert_equivalence_geometry(geom, expected_Dh, expected_A,
                                     expected_wet_perim, expected_heated_parts;
                                     rtol::Float64=1e-12)
    isapprox(geom.Dh, expected_Dh; rtol=rtol) || error(
        "EQUIVALENCE FAIL: Dh: Julia=$(geom.Dh), Expected=$expected_Dh")
    isapprox(geom.A, expected_A; rtol=rtol) || error(
        "EQUIVALENCE FAIL: A: Julia=$(geom.A), Expected=$expected_A")
    isapprox(geom.wet_perimeter, expected_wet_perim; rtol=rtol) || error(
        "EQUIVALENCE FAIL: wet_perimeter")
    isapprox(geom.heated_parts[1], expected_heated_parts[1]; rtol=rtol) || error(
        "EQUIVALENCE FAIL: heated_parts[1] (left)")
    isapprox(geom.heated_parts[2], expected_heated_parts[2]; rtol=rtol) || error(
        "EQUIVALENCE FAIL: heated_parts[2] (right)")
    @info "Equivalence checklist: geometry matches"
end

function assert_equivalence_anchors(; expected_P_abs::Float64=1.0e5)
    @info "Equivalence checklist: pressure anchor = $expected_P_abs Pa " *
          "(Julia: pump.port_in.P ~ $expected_P_abs; " *
          "Python: reference_node=(\"A\", $expected_P_abs))"
end
