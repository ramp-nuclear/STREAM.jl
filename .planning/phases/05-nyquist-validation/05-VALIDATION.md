---
phase: 5
slug: nyquist-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib `Test` (no install needed) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `grep "nyquist_compliant: true" .planning/phases/0{N}-*/0{N}-VALIDATION.md` |
| **Full suite command** | `julia --project=. -e "using Pkg; Pkg.test()"` |
| **Estimated runtime** | ~30 seconds (validate-phase per phase) |

---

## Sampling Rate

- **After every task commit:** Run `grep "nyquist_compliant: true" .planning/phases/0{N}-*/0{N}-VALIDATION.md`
- **After every plan wave:** Check all three phases are compliant
- **Before `/gsd:verify-work`:** All three VALIDATION.md files must have `nyquist_compliant: true`
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | Phase 01 Nyquist compliance | automated | `grep "nyquist_compliant: true" .planning/phases/01-foundation/01-VALIDATION.md` | ✅ | ⬜ pending |
| 5-01-02 | 01 | 1 | Phase 02 Nyquist compliance | automated | `grep "nyquist_compliant: true" .planning/phases/02-components/02-VALIDATION.md` | ✅ | ⬜ pending |
| 5-01-03 | 01 | 1 | Phase 03 Nyquist compliance | automated | `grep "nyquist_compliant: true" .planning/phases/03-integration-and-validation/03-VALIDATION.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

No new test files or framework setup required. All infrastructure pre-exists.

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

The validate-phase workflow handles compliance checking automatically. Downstream Manual-Only items (from phases 01–03 VALIDATION.md files) must be **preserved**, not automated:

| Behavior | Phase | Why Manual |
|----------|-------|------------|
| `@register_symbolic` at module top-level | 01 | Compile-time constraint |
| `observed(compiled_sys)` symbolic inspection | 02 | Requires post-mtkcompile symbolic API |
| Run `generate_reference.py` for Python reference values | 03 | Requires Python STREAM installed |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
