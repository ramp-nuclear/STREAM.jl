---
phase: 9
slug: channelandcontacts
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
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
| 9-01-01 | 01 | 1 | THERM-01 | unit (RED stub) | `julia --project -e "include(\"test/runtests.jl\")"` | ❌ W0 | ⬜ pending |
| 9-01-02 | 01 | 1 | THERM-01 | unit (RED stub) | `julia --project -e "include(\"test/runtests.jl\")"` | ❌ W0 | ⬜ pending |
| 9-01-03 | 01 | 2 | THERM-01 | unit (GREEN) | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |
| 9-01-04 | 01 | 2 | THERM-02 | regression | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |
| 9-02-01 | 02 | 1 | THERM-03 | unit (RED stub) | `julia --project -e "include(\"test/runtests.jl\")"` | ❌ W0 | ⬜ pending |
| 9-02-02 | 02 | 2 | THERM-03 | unit (GREEN) | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |
| 9-02-03 | 02 | 2 | THERM-03 | integration | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — add RED stubs for ChannelAndContacts and ChannelHeatFlux tests (THERM-01, THERM-03)
- [ ] Stubs should fail with `error("not implemented")` or similar so they are clearly RED before implementation

*Existing test infrastructure (`test/runtests.jl`) covers all existing phase requirements; Wave 0 adds stubs only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | — | — | — |

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
