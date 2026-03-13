---
phase: 7
slug: network-architecture
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`) |
| **Config file** | none — entry point: `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 0 | NET-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 7-01-02 | 01 | 1 | NET-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 7-02-01 | 02 | 0 | NET-02 | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 7-02-02 | 02 | 1 | NET-02 | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 7-02-03 | 02 | 1 | NET-03 | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — add Phase 7 `@testset` block with stubs for NET-01, NET-02, NET-03
- [ ] `src/components.jl` — add `Resistor()` function stub
- [ ] `src/solvers.jl` — add `build_cube()` utility stub
- [ ] `src/STREAM.jl` — add `export Resistor` and `export build_cube`

*Existing Test stdlib infrastructure is sufficient — no new framework needed.*

---

## Manual-Only Verifications

*If none: "All phase behaviors have automated verification."*

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
