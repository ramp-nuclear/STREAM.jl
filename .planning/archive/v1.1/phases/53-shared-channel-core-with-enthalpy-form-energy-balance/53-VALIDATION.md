---
phase: 53
slug: shared-channel-core-with-enthalpy-form-energy-balance
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-06
---

# Phase 53 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source of truth: 53-RESEARCH.md §"Validation Architecture" (line 540) and 53-CONTEXT.md D-11.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib (existing project convention) |
| **Config file** | `test/runtests.jl` (orchestrator; @testset per `include()`) |
| **Quick run command** | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. -e 'using Pkg; Pkg.test(test_args=["test_channel_core"])'` |
| **Full suite command** | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. test/runtests.jl` |
| **Estimated runtime** | ~30s quick (single test file with sysimage) / ~2-4 min full suite |

> **Note:** sysimage usage per CLAUDE.md §"Performance — Sysimage". Persistent REPL with Revise.jl is the dev-loop fastpath; CI uses the sysimage-or-cold-start command above.

---

## Sampling Rate

- **After every task commit:** Run quick command (single-file `test_channel_core` testset)
- **After every plan wave:** Run full suite (verifies existing CHAN-* / GRAV-* / THERM-* / PHY-* tests still pass — per D-13, variants must compile and pass at every commit boundary)
- **Before `/gsd-verify-work`:** Full suite green
- **Max feedback latency:** ~30 seconds (quick) / ~4 min (full)

---

## Per-Task Verification Map

> Plans are not yet written. This table is a placeholder for the planner to fill in by mapping each task to one of the four validation gates below. Test types are constrained to: `unit`, `single-cell-mirror`, `stage1-baseline`, `stage2-python-parity`, `branch-coverage`, `regression-existing-suite`.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 53-XX-XX | XX | X | CORE-01..05, NRG-01..04 | — | N/A (scientific code, no security surface) | (planner-assigned) | (planner-assigned) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Validation Gates (from 53-RESEARCH.md §"Validation Architecture")

The four gates below are MANDATORY. Every plan in Phase 53 must contribute to at least one. Together they discharge ROADMAP success criteria #4 (mirror) and #5 (branch coverage), plus the CONTEXT.md D-11 two-stage analytical verification.

### Gate G1 — Stage 1: Constant-cp limit sanity check (CORE-01..05, NRG-01)

- **Requirement:** New `_channel_core` driven by placeholder `q_*_expr` over a small ΔT (~1 K) must agree with v1.0 `_channel_base_eqs` baseline values to **rtol = 1e-6**.
- **Mechanism:** Capture v1.0 baseline `T_out`, `mdot`, per-cell `T[i]` from a current `Channel` solve on a fixed geometry BEFORE the energy-balance switch. Re-run on `_channel_core` after the switch with constant-cp-equivalent driving. Assert `≈` within rtol.
- **Catches:** Wrong indexing, wrong sign, wrong port wiring, broken composition.
- **Test type:** `stage1-baseline`

### Gate G2 — Stage 2: Realistic cp-variation Python parity (NRG-01, NRG-02, NRG-03)

- **Requirement:** New `_channel_core` driven over a ~30 K rise (real cp(T) variation, ~3% at typical reactor conditions) must match hand-computed `T_out` values produced by Python STREAM's exact `pair_mean_1d` formula on the same geometry/q profile to **rtol = 1e-9**.
- **Mechanism:** Reference values produced by a one-off Python helper script (recommended placement: `test/data/stage2_reference.py`). Resulting Float64 array is committed as a Julia `const` in the test file with regen comment.
- **Catches:** Drift in cp-averaging itself (the regime where enthalpy form differs from constant-cp-effective). This is the gate that prevents Python-parity drift from compounding into Phase 54/55 before Phase 56 catches it.
- **Test type:** `stage2-python-parity`

### Gate G3 — Single-cell forward/reverse mirror test (NRG-04, ROADMAP §4)

- **Requirement:** On a single-cell channel with matched stub `q_left_expr`/`q_right_expr` profiles and opposite mdot signs:
  ```
  T_out_forward(T_in_forward) - T_in_forward  ≈  -(T_out_reverse(T_in_reverse) - T_in_reverse)
  ```
  to **rtol = 1e-12** (analytical mirror, not numerical-precision-limited).
- **Mechanism:** Two `solve_steady` runs on the same stub system, opposite `mdot` signs, identical |ΔT| magnitudes. Subtract.
- **Catches:** Asymmetric flow-reversal handling — a missing `ifelse` for cp, a half-flipped boundary face, a sign error in the `instream` boundary value.
- **Tolerance fallback:** If KINSOL solver default tolerances make 1e-12 flaky, planner may set explicit `abstol=1e-12, reltol=1e-12` on `solve_steady`, or relax to `1e-9` with rationale.
- **Test type:** `single-cell-mirror`

### Gate G4 — Code-path coverage matrix (CORE-05, ROADMAP §5)

- **Requirement:** Every `if` / `ifelse` / branching kwarg dispatch in `_channel_core` is exercised by at least one placeholder configuration in Phase 53. No dead branches.
- **Mechanism:** Test-matrix table (branches × configurations × triggering test). Phase 53 satisfies this via placeholder scaffolds only — variants are wired in Phase 54. Recommended matrix shape (research §Code-Path Coverage Matrix):

  | Branch | Triggering configuration | Triggering test |
  |--------|-------------------------|-----------------|
  | `mdot ≥ 0` (forward boundary face) | mdot > 0, q_left_expr non-zero | G3 forward leg |
  | `mdot < 0` (reverse boundary face) | mdot < 0, q_left_expr non-zero | G3 reverse leg |
  | adiabatic (q_left = q_right = 0) | mdot > 0, both q exprs zero | G1 baseline subset |
  | one-sided heating (q_right = 0) | mdot > 0, q_right_expr = fill(0, n) | G1 / G2 |
  | right-only heating (q_left = 0) | mdot > 0, q_left_expr = fill(0, n) | symmetric to above |
  | two-sided heating | mdot > 0, both q exprs non-zero | G2 |
  | (planner extends with any new branches introduced inside core) | | |

  Planner finalizes the matrix once `_channel_core`'s exact branch list is locked.
- **Test type:** `branch-coverage`

### Gate G5 — Existing-suite regression (D-13)

- **Requirement:** All existing CHAN-*, GRAV-*, THERM-*, PHY-*, COMP-*, NET-*, SOLV-*, SYS-*, VAL-* tests stay green at every commit boundary in Phase 53. Variants still call `_channel_base_eqs` until Phase 54.
- **Mechanism:** Full suite `julia $SYSIMG --project=. test/runtests.jl` after each commit.
- **Catches:** Accidental mutation of variant behavior, unintended export changes, dispatch ambiguity from coexisting `_channel_core` and `_channel_base_eqs`.
- **Test type:** `regression-existing-suite`

---

## Wave 0 Requirements

- [ ] `test/test_channel_core.jl` — new test file (placement decision per 53-RESEARCH.md): single dedicated home for stub harness + G1 + G2 + G3 + G4 ≈ 250 LOC. Naming survives Phase 54's file consolidation cleanly.
- [ ] `test/data/stage2_reference.py` — Python helper that generates Stage-2 reference values from `~/projects/STREAM/`. Committed to repo with regen instructions.
- [ ] Wire new `test_channel_core.jl` into `test/runtests.jl` orchestrator (one `@testset begin include("test_channel_core.jl") end` block).
- [ ] Stub harness inside `test_channel_core.jl`: minimal Pump → stub `_channel_core` → Pump loop matching the Phase 52 `_StubRecipient` / `_StubWallDriver` / `_StubFluxDriver` pattern (precedent: `test/test_connectors.jl`).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `_channel_base_eqs` deletion is total | CORE-01..02 | grep-based negative test; covered in G4 / acceptance criteria, not a behavior assertion | `grep -rn '_channel_base_eqs' src/ test/` returns no hits at end of phase |
| `observed_mode` / `skip_htc` / `T_wall_cells` flags removed | CORE-03..05 | grep-based negative test; covered in plan acceptance criteria | `grep -rn 'observed_mode\|skip_htc\|T_wall_cells' src/` returns empty |

> All scientific behavior has automated verification via G1-G5. Manual entries above are grep-audits the executor performs at task completion, not user-driven UAT.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify mapped to G1, G2, G3, G4, or G5
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers `test_channel_core.jl`, `test/data/stage2_reference.py`, `runtests.jl` wiring
- [ ] No watch-mode flags (Julia testing is one-shot per `Pkg.test` / `runtests.jl` invocation)
- [ ] Feedback latency < 30s quick / < 4 min full
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
