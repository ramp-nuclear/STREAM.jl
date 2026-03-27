---
phase: 20
slug: sign-safety
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-17
audited: 2026-03-17
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + TestItems |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e 'include("test/test_sign_safety.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_sign_safety.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-01 | 01 | 1 | SIGN-01 | integration | `julia --project -e 'include("test/test_sign_safety.jl")'` | ✅ | ✅ green |
| 20-01-02 | 01 | 1 | SIGN-02 | integration | `julia --project -e 'include("test/test_sign_safety.jl")'` | ✅ | ✅ green |
| 20-01-03 | 01 | 1 | SIGN-03 | integration | `julia --project -e 'include("test/test_sign_safety.jl")'` | ✅ | ✅ green |
| 20-02-01 | 02 | 2 | SIGN-04 | integration | `julia --project -e 'include("test/test_sign_safety.jl")'` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Test file: `test/test_sign_safety.jl` — 168 lines, 17 tests across 3 testsets.
Wired into: `test/runtests.jl` line 7.

---

## Requirement Coverage Detail

| Requirement | Testset | Assertions |
|-------------|---------|------------|
| SIGN-01 | "SIGN-01/04: Channel reversed flow" | retcode==Success, T[1]>T[n], monotone decreasing, all Re>0, T[1]>T_inlet, T[n]<T_wall |
| SIGN-02 | "SIGN-02/04: ChannelAndContacts reversed flow" | retcode==Success, T[1]>T[n], monotone decreasing, all Re>0, all velocity>0, energy balance rtol=0.01 |
| SIGN-03 | "SIGN-03/04: ChannelHeatFlux reversed flow" | retcode==Success, T[1]>T[n], monotone decreasing, all Re>0, energy balance rtol=0.01 |
| SIGN-04 | All three testsets | Same as SIGN-01/02/03 — SIGN-04 is the integration test requirement |

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-17 — all 17 tests green, 0 gaps

---

## Validation Audit 2026-03-17

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

All requirements (SIGN-01..04) covered by `test/test_sign_safety.jl`. Tests run green: 6+6+5=17 passing.
