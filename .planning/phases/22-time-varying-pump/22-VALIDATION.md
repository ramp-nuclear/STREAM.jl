---
phase: 22
slug: time-varying-pump
status: complete
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-18
updated: 2026-03-18
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (no version — stdlib) |
| **Config file** | none — run via `include("test_pump.jl")` in runtests.jl |
| **Quick run command** | `julia --project=. -e 'include("test/test_pump.jl")'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'include("test/test_pump.jl")'` and `julia --project=. -e 'include("test/test_solvers.jl")'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File | Status |
|---------|------|------|-------------|-----------|-------------------|------|--------|
| 22-01-01 | 01 | 1 | PUMP-01 | unit | `julia --project=. -e 'include("test/test_pump.jl")'` | test/test_pump.jl:92 | ✅ green |
| 22-01-02 | 01 | 1 | PUMP-02 | regression | `julia --project=. -e 'include("test/test_pump.jl")'` | test/test_pump.jl:45,62 | ✅ green |
| 22-01-03 | 01 | 1 | PUMP-03 | integration+analytical | `julia --project=. -e 'include("test/test_pump.jl")'` | test/test_pump.jl:106 | ✅ green |
| 22-01-04 | 01 | 1 | SOLV-redesign | integration | `julia --project=. -e 'include("test/test_solvers.jl")'` | test/test_solvers.jl:53 | ✅ green |
| 22-02-01 | 02 | 2 | PUMP-01/02/03 | integration | `julia --project=. -e 'include("test/test_pump.jl")'` | test/test_pump.jl:92,45,106 | ✅ green |
| 22-02-02 | 02 | 2 | SOLV-02 | integration | `julia --project=. -e 'include("test/test_solvers.jl")'` | test/test_solvers.jl:53,59 | ✅ green |
| 22-02-03 | 02 | 2 | VAL-02 transient | integration | `julia --project=. -e 'include("test/test_validation.jl")'` | test/test_validation.jl:36 | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. New tests extend `test/test_pump.jl` and rewrite portions of `test/test_solvers.jl` and `test/test_validation.jl`.

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

**Approval:** complete

---

## Validation Audit 2026-03-18

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

All 3 requirements (PUMP-01, PUMP-02, PUMP-03) have automated tests. SOLV-02 and VAL-02 transient tests also verified. VALIDATION.md updated from stale draft to reflect actual green state after phase execution.
