---
phase: 17
slug: file-structure-reorganization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib |
| **Config file** | none — single `test/runtests.jl` monolith |
| **Quick run command** | `julia --project=. -e 'using STREAM; println("load ok")'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'using STREAM; println("load ok")'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | STR-01 | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :PipeGeometry)'` | ✅ | ⬜ pending |
| 17-01-02 | 01 | 1 | STR-02 | smoke+unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ⬜ pending |
| 17-01-03 | 01 | 1 | STR-03 | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :dittus_boelter)'` | ✅ | ⬜ pending |
| 17-01-04 | 01 | 1 | STR-04 | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :symmetric_plate)'` | ✅ | ⬜ pending |
| 17-01-05 | 01 | 1 | STR-05 | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :build_loop)'` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* No new test files needed — this phase adds no new functionality. The existing 161-test suite exercises every public symbol that is being reorganized.

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
