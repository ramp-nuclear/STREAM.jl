---
phase: 18
slug: test-split-and-api-cleanup
status: compliant
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-16
audited: 2026-03-16
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Test stdlib (built-in Julia) |
| **Config file** | none — driven by `test/runtests.jl` |
| **Quick run command** | `julia --project test/runtests.jl` |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project test/runtests.jl`
- **After every plan wave:** Run `julia --project -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | TEST-01 | structural | `julia --project test/runtests.jl` | ✅ | ✅ green |
| 18-01-02 | 01 | 1 | QOL-02 | structural | `grep "VAL-03" test/test_validation.jl` | ✅ | ✅ green |
| 18-02-01 | 02 | 2 | QOL-01 | smoke | `julia --project test/runtests.jl` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All Wave 0 deliverables confirmed complete:

- [x] `test/test_geometry.jl` — covers PHY-01
- [x] `test/test_connectors.jl` — covers FOUND-01, CONN-01/02
- [x] `test/test_fluids.jl` — covers FOUND-02
- [x] `test/test_channel.jl` — covers COMP-01 (channel), GRAV-*, CHAN-*, THERM-*
- [x] `test/test_pump.jl` — covers COMP-02, PHY-05
- [x] `test/test_resistors.jl` — covers COMP-03/04, NET-*
- [x] `test/test_misc.jl` — covers COMP-01/02 (Inertia/HeatExchanger)
- [x] `test/test_heat_diffusion.jl` — covers HDIFF-01..05
- [x] `test/test_correlations.jl` — covers PHY-02/03/04
- [x] `test/test_composition.jl` — covers COMP-01..04, QOL-01..03
- [x] `test/test_solvers.jl` — covers SYS-*, SOLV-*
- [x] `test/test_validation.jl` — covers VAL-*
- [x] `test/test_examples.jl` — covers COMPAT
- [x] `test/runtests.jl` rewritten to thin orchestrator (13 include() calls, 15 lines total)
- [x] `src/solvers.jl` solve_transient signature is keyword-only (`function solve_transient(; ssys, ...`)

---

## Gap Analysis

**Result: No gaps.** All 3 requirements have automated verification targeting the correct behavior.

| Requirement | Evidence | Status |
|-------------|----------|--------|
| TEST-01 | `runtests.jl` has 13 `include()` calls; 13 `test_*.jl` files exist; 0 `using`/`@testset` in runtests.jl | COVERED |
| QOL-01 | `solve_transient(; ssys, ...)` keyword-only in `src/solvers.jl`; both call sites use `ssys=ssys` form | COVERED |
| QOL-02 | `test_validation.jl` line 219: `@testset "VAL-03: ..."` with 5 substantive `@test` assertions | COVERED |

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-16 — Nyquist audit by gsd-nyquist-auditor (retroactive)

---

## Validation Audit 2026-03-16

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Requirements covered | 3/3 |
| Wave 0 items complete | 15/15 |
