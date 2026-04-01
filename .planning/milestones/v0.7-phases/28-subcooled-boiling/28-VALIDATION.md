---
phase: 28
slug: subcooled-boiling
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test (stdlib) + TestSetExtras |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_subcooled_boiling.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 28-01-01 | 01 | 1 | SCB-01 | unit | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |
| 28-01-02 | 01 | 1 | SCB-02 | unit | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |
| 28-01-03 | 01 | 1 | SCB-03 | unit | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |
| 28-01-04 | 01 | 1 | SCB-04 | unit | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |
| 28-02-01 | 02 | 2 | ISCB-01 | integration | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |
| 28-02-02 | 02 | 2 | ISCB-02 | integration | `julia --project -e 'include("test/test_subcooled_boiling.jl")'` | W0 (Plan 01 Task 2) | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [x] `test/test_subcooled_boiling.jl` — created by Plan 01 Task 2 with unit test stubs for SCB-01..04
- [x] `src/physical_models/subcooled_boiling.jl` — created by Plan 01 Task 1

*Wave 0 is satisfied by Plan 01 Task 2 which creates the test file. All subsequent tasks (Plan 02) append to the same test file.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SCB-corrected HTC measurably higher than uncorrected when T_wall >> T_sat | ISCB-02 | Requires visual/numerical inspection of solution values | Run ChannelAndContacts with scb_correction=true at high wall temp, compare h_tc vs uncorrected |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved
