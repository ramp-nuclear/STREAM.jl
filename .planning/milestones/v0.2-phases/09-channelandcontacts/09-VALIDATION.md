---
phase: 9
slug: channelandcontacts
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-13
audited: 2026-03-13
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e "include(\"test/runtests.jl\")"` |
| **Full suite command** | `julia --project -e "include(\"test/runtests.jl\")"` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e "include(\"test/runtests.jl\")"`
- **After every plan wave:** Run `julia --project -e "include(\"test/runtests.jl\")"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 9-01-01 | 01 | 1 | THERM-01 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-01-02 | 01 | 1 | THERM-01 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-01-03 | 01 | 2 | THERM-01 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-01-04 | 01 | 2 | THERM-02 | regression | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-02-01 | 02 | 1 | THERM-03 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-02-02 | 02 | 2 | THERM-03 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |
| 9-02-03 | 02 | 2 | THERM-03 | integration | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — Phase 9 testset with THERM-01 (callable, mtkcompile, n ThermalPorts), THERM-02 (regression), THERM-03 (steady-state match within 0.1%)
- [x] RED stubs written first, then replaced by full GREEN implementations in Plan 02

*Existing test infrastructure (`test/runtests.jl`) covers all existing phase requirements; Wave 0 adds stubs only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | — | — | — |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-13 — all 86 tests pass (75 prior + 11 Phase 9 tests), zero regressions; v0.2 milestone complete

## Validation Audit 2026-03-13
| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Pre-existing tests | 11 (THERM-01 ×3, THERM-02 ×1, THERM-03 ×1 + sub-assertions) |
