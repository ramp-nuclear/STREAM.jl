---
phase: 18
slug: test-split-and-api-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
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
| 18-01-01 | 01 | 1 | TEST-01 | structural | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |
| 18-01-02 | 01 | 1 | QOL-02 | structural | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |
| 18-02-01 | 02 | 2 | QOL-01 | smoke | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All Wave 0 gaps are the deliverables of this phase, not prerequisite infrastructure:

- [ ] `test/test_geometry.jl` — covers PHY-01
- [ ] `test/test_connectors.jl` — covers FOUND-01, CONN-01/02
- [ ] `test/test_fluids.jl` — covers FOUND-02
- [ ] `test/test_channel.jl` — covers COMP-01 (channel), GRAV-*, CHAN-*, THERM-*
- [ ] `test/test_pump.jl` — covers COMP-02, PHY-05
- [ ] `test/test_resistors.jl` — covers COMP-03/04, NET-*
- [ ] `test/test_misc.jl` — covers COMP-01/02 (Inertia/HeatExchanger)
- [ ] `test/test_heat_diffusion.jl` — covers HDIFF-01..05
- [ ] `test/test_correlations.jl` — covers PHY-02/03/04
- [ ] `test/test_composition.jl` — covers COMP-01..04, QOL-01..03
- [ ] `test/test_solvers.jl` — covers SYS-*, SOLV-*
- [ ] `test/test_validation.jl` — covers VAL-*
- [ ] `test/test_examples.jl` — covers COMPAT
- [ ] `test/runtests.jl` rewritten to thin orchestrator (include() calls only)
- [ ] `src/solvers.jl` solve_transient signature changed to keyword-only

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
