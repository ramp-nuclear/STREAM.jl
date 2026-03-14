---
phase: 12
slug: mtr-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`, `@test_nowarn`) |
| **Config file** | none — standard `test/runtests.jl` |
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
| 12-01-01 | 01 | 1 | VAL-01, VAL-02, VAL-03 | integration | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | VAL-01 | integration | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | VAL-02 | integration | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 12-01-04 | 01 | 1 | VAL-03 | integration | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 12-01-05 | 01 | 1 | HDIFF-03 gap | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/generate_mtr_reference.py` — Python STREAM MTR reference script (run once manually; extracts constants for VAL-01, VAL-02, VAL-03)
- [ ] `test/runtests.jl` — Phase 12 `@testset "STREAM Phase 12 Tests"` block with VAL-01, VAL-02, VAL-03, and HDIFF-03 gap test; hardcoded reference constants from `generate_mtr_reference.py` output

*Python reference script is a generator, not an automated test — run manually, extract constants, hardcode into runtests.jl.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Python STREAM reference script produces valid outputs | VAL-01, VAL-02, VAL-03 | Generator script must be run manually to extract hardcoded constants | Run `python test/generate_mtr_reference.py` from project root; verify T_outlet and T_plate values are physically reasonable (T > 313.15 K, monotonically increasing axially) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
