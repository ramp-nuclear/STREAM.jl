---
phase: 25
slug: argument-structure-audit
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-26
updated: 2026-03-26
---

# Phase 25 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test (stdlib) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project test/runtests.jl` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project test/runtests.jl`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 25-01-01 | 01 | 1 | SC#1: positional component args | unit | `julia --project test/runtests.jl` | ✅ | ✅ green |
| 25-01-02 | 01 | 1 | SC#2: laminar_friction positional | unit | `julia --project test/runtests.jl` | ✅ | ✅ green |
| 25-01-03 | 01 | 1 | SC#3: full suite passes | integration | `julia --project test/runtests.jl` | ✅ | ✅ green |
| 25-01-04 | 01 | 1 | SC#4: CLAUDE.md two-tier rule | manual | n/a — doc update | ✅ | ✅ verified |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Coverage notes:**
- SC#1: `Resistor(1.0e5)`, `Inertia(1e3)`, `HeatExchanger(313.15)` positional call sites in test_resistors.jl, test_misc.jl; test_composition.jl; suite green.
- SC#2: `laminar_friction(0.01814)` positional call in test_correlations.jl; suite green.
- SC#3: All non-pre-existing tests pass. One pre-existing flaky test (`VAL-01: HeatDiffusion transient — Fourier series validation`) confirmed present before phase 25.
- SC#4: CLAUDE.md lines 61–67 contain the two-tier positional/keyword convention rule (verified manually).

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CLAUDE.md rule update | SC#4 | Documentation change | Read CLAUDE.md, verify new two-tier rule is present under §"Component authoring conventions" — lines 61–67 confirmed ✅ |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-26

---

## Validation Audit 2026-03-26

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Manual-only | 1 (SC#4 — doc change, not automatable) |
