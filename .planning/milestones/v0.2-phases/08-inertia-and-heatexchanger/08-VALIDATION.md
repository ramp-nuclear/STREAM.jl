---
phase: 8
slug: inertia-and-heatexchanger
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-13
audited: 2026-03-13
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + `@testset` |
| **Config file** | none — tests run via `Pkg.test()` or `julia test/runtests.jl` |
| **Quick run command** | `julia --project -e 'include("test/runtests.jl")'` |
| **Full suite command** | `julia --project -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/runtests.jl")'`
- **After every plan wave:** Run `julia --project -e 'import Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | COMP-01, COMP-02 | stub | `julia --project -e 'include("test/runtests.jl")'` | ✅ | ✅ green |
| 8-02-01 | 01 | 1 | COMP-01 | unit | `julia --project -e 'include("test/runtests.jl")'` | ✅ | ✅ green |
| 8-02-02 | 01 | 1 | COMP-01 | integration | `julia --project -e 'include("test/runtests.jl")'` | ✅ | ✅ green |
| 8-03-01 | 02 | 1 | COMP-02 | unit | `julia --project -e 'include("test/runtests.jl")'` | ✅ | ✅ green |
| 8-03-02 | 02 | 1 | COMP-02 | regression | `julia --project -e 'include("test/runtests.jl")'` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` Phase 8 testset — COMP-01 (Inertia callable, mtkcompile, RL-decay) and COMP-02 (HeatExchanger callable, mtkcompile, export check, build_loop regression) — all green

*Existing test infrastructure covers all prior requirements. Only new Phase 8 testset stubs needed.*

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

**Approval:** 2026-03-13 — all 75 tests pass (63 prior + 12 Phase 8 tests), zero regressions

## Validation Audit 2026-03-13
| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Pre-existing tests | 12 (COMP-01: Inertia ×3; COMP-02: HeatExchanger ×4 incl. regression) |
