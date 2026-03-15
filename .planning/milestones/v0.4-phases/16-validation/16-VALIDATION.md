---
phase: 16
slug: validation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-15
audited: 2026-03-15
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test.jl (stdlib) |
| **Config file** | none — single runtests.jl |
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
| 16-01-01 | 01 | 1 | VAL-03 | unit assertion | `julia --project test/runtests.jl` | ✅ test/runtests.jl:1124 | ✅ green |
| 16-01-02 | 01 | 1 | VAL-01 | integration | `julia --project test/runtests.jl` | ✅ test/runtests.jl:1612 | ✅ green |
| 16-02-01 | 02 | 2 | VAL-02 | integration | `julia --project test/runtests.jl` | ✅ test/runtests.jl:1679 | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — inline T_max assertion at line 1138 (within existing VAL-03 @testset)
- [x] `test/runtests.jl` — `@testset "VAL-01: HeatDiffusion transient — Fourier series validation"` at line 1612
- [x] `test/runtests.jl` — `@testset "VAL-02: Two-plate one-channel topology — both faces active"` at line 1679

All 30 tests in `Phase 16: Validation` testset pass (confirmed 2026-03-15).

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-15 — 30/30 tests green, 0 gaps

---

## Validation Audit 2026-03-15

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
