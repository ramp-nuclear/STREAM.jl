---
phase: 16
slug: validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
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
| 16-01-01 | 01 | 1 | VAL-03 | unit assertion | `julia --project test/runtests.jl` | ❌ W0 (inline edit) | ⬜ pending |
| 16-01-02 | 01 | 1 | VAL-01 | integration | `julia --project test/runtests.jl` | ❌ W0 (new @testset) | ⬜ pending |
| 16-02-01 | 02 | 2 | VAL-02 | integration | `julia --project test/runtests.jl` | ❌ W0 (new @testset) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — inline T_max assertion + NOTE comment update at lines 1124-1126 (within existing VAL-03 @testset)
- [ ] `test/runtests.jl` — new `@testset "VAL-01: HeatDiffusion transient — Fourier series validation"` block after line 1585
- [ ] `test/runtests.jl` — new `@testset "VAL-02: Two-plate one-channel topology — both faces active"` block after VAL-01

No new source files needed — all implementation is test assertions in the existing runtests.jl file.

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
