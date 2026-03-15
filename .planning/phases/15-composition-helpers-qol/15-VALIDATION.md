---
phase: 15
slug: composition-helpers-qol
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (Test.jl) |
| **Config file** | none — `julia --project test/runtests.jl` |
| **Quick run command** | `julia --project test/runtests.jl` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project test/runtests.jl`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | QOL-01 | integration | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |
| 15-01-02 | 01 | 1 | QOL-02, QOL-03 | unit | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |
| 15-02-01 | 02 | 2 | COMP-01, COMP-02, COMP-03, COMP-04 | integration | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |
| 15-02-02 | 02 | 2 | COMP-01, COMP-02, COMP-03, COMP-04 | integration | `julia --project test/runtests.jl` | ❌ Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All new tests belong in `test/runtests.jl` appended after the PHY-02/03/04 test block:

- [ ] `@testset "QOL-01: @observed Re/Nu accessible via sol" begin` — covers QOL-01
- [ ] `@testset "QOL-02: check_gravity_mismatch — balanced loop" begin` — covers QOL-02
- [ ] `@testset "QOL-03: port() helper" begin` — covers QOL-03
- [ ] `@testset "COMP-01: symmetric_plate — builds and solves" begin` — covers COMP-01
- [ ] `@testset "COMP-02: plate — two-channel wiring" begin` — covers COMP-02
- [ ] `@testset "COMP-03: one_sided_connection — single face" begin` — covers COMP-03
- [ ] `@testset "COMP-04: compose_systems — variadic wrapper" begin` — covers COMP-04

No framework install required — Test.jl is already in `[extras]`. No new test files needed.

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
