---
phase: 26
slug: nc-regime-htc-lof-cleanup
status: verified
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-26
audited: 2026-03-27
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e "include(\"test/test_correlations.jl\")"` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~60–90 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e "include(\"test/test_correlations.jl\")"`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 26-01-01 | 01 | 1 | NATCONV-01 | unit | `julia --project -e "include(\"test/test_correlations.jl\")"` | ✅ | ✅ green |
| 26-01-02 | 01 | 1 | NATCONV-01 | unit | `julia --project -e "include(\"test/test_correlations.jl\")"` | ✅ | ✅ green |
| 26-01-03 | 01 | 1 | NATCONV-01 | integration | `julia --project -e "include(\"test/test_channel.jl\")"` | ✅ | ✅ green |
| 26-01-04 | 01 | 1 | NATCONV-01 | integration | `julia --project test/runtests.jl` | ✅ | ✅ green |
| 26-02-01 | 02 | 2 | VAL-02 | integration | `julia --project -e "include(\"test/test_loss_of_flow.jl\")"` | ✅ | ✅ green |
| 26-02-02 | 02 | 2 | VAL-02 | integration | `julia --project -e "include(\"test/test_loss_of_flow.jl\")"` | ✅ | ✅ green |
| 26-02-03 | 02 | 2 | — | lint | `grep -n "build_loop_lof" src/examples.jl src/STREAM.jl` (expect 0 matches) | ✅ | ✅ green |
| 26-02-04 | 02 | 2 | — | lint | `grep -n "Re, Pr)" src/components/channel.jl src/components/thermal_channel.jl` (expect 0 old-style docstring hits) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

*No new test files or stubs are needed — all assertions are additions to existing testsets.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `24.1-VERIFICATION.md` accurately describes HEAD state | — | Document audit, no automated checker | Read `.planning/phases/24.1-bypass-lof-topology/24.1-VERIFICATION.md` and confirm SC1/SC2/VAL-02 are marked PASS with correct rationale |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-27

---

## Validation Audit 2026-03-27

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

All 8 tasks verified green. No missing tests. Phase is Nyquist-compliant.
