---
phase: 49
slug: full-loop-integration-validation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-08
---

# Phase 49 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`) |
| **Config file** | none — Julia test discovery via `test/runtests.jl` |
| **Quick run command** | `test -f stream.so && julia --sysimage stream.so --project=. test/runtests.jl || julia --project=. test/runtests.jl` |
| **Full suite command** | `test -f stream.so && julia --sysimage stream.so --project=. test/runtests.jl || julia --project=. test/runtests.jl` |
| **Estimated runtime** | ~60-120 seconds (without sysimage), ~10 seconds (with sysimage) |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 49-01-01 | 01 | 1 | LOOP-01 | — | N/A | integration | `julia --project=. test/test_examples.jl` | ✅ | ✅ green |
| 49-01-02 | 01 | 1 | LOOP-02 | — | N/A | integration | `julia --project=. test/test_examples.jl` | ✅ | ✅ green |
| 49-01-03 | 01 | 1 | LOOP-03 | — | N/A | integration | `julia --project=. test/test_examples.jl` | ✅ | ✅ green |
| 49-01-04 | 01 | 1 | LOOP-04 | — | N/A | integration | `julia --project=. test/test_examples.jl` | ✅ | ✅ green |
| 49-02-01 | 02 | 2 | VAL-PK-01 | — | N/A | validation | `julia --project=. test/test_validation.jl` | ✅ | ✅ green |
| 49-02-02 | 02 | 2 | VAL-PK-02a | — | N/A | validation | `julia --project=. test/test_validation.jl` | ✅ | ✅ green |
| 49-02-03 | 02 | 2 | VAL-PK-02b | — | N/A | validation | `julia --project=. test/test_validation.jl` | ✅ | ✅ green |
| 49-02-04 | 02 | 2 | VAL-PK-03 | — | N/A | validation | `julia --project=. test/test_validation.jl` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/test_examples.jl` — LOOP-01..04 `@testset` blocks present and passing (all 4 pass)
- [x] `test/test_validation.jl` — `@testset "PointKinetics validation"` block for VAL-PK-01..03 present and passing (all 8 assertions pass)

*Both files verified passing via Nyquist audit (2026-04-10). Note: VAL-02 has a pre-existing error (`ssys.sys.T_wall_callable` missing) unrelated to Phase 49; VAL-PK tests were verified in isolation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Python STREAM cross-check | VAL-PK-01 | Reference inspection only | Run `~/projects/STREAM/tests/test_general/test_integrations.py::test_channel_point_kinetics` and compare T_cool profile shape |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** complete (Nyquist audit 2026-04-10)
