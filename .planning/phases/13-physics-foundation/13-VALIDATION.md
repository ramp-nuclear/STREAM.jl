---
phase: 13
slug: physics-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (project standard) |
| **Config file** | none — single `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e "using Pkg; Pkg.test()"` |
| **Full suite command** | `julia --project=. -e "using Pkg; Pkg.test()"` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e "using Pkg; Pkg.test()"`
- **After every plan wave:** Run `julia --project=. -e "using Pkg; Pkg.test()"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-W0 | 01 | 0 | PHY-01 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 13-01-01 | 01 | 1 | PHY-01 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | PHY-01 | regression | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ⬜ pending |
| 13-01-03 | 01 | 1 | PHY-01 | integration | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ⬜ pending |
| 13-02-W0 | 02 | 0 | PHY-05 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 13-02-01 | 02 | 1 | PHY-05 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 13-02-02 | 02 | 1 | PHY-05 | integration | `julia --project=. -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 13-02-03 | 02 | 1 | PHY-05 | regression | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — add `@testset "PHY-01: PipeGeometry_rectangular geometry"` block (stub assertions for `Dh`, `wet_perimeter`, `area`)
- [ ] `test/runtests.jl` — add `@testset "PHY-01: PipeGeometry_circular geometry"` block (stub assertions for `Dh = D`, `wet_perimeter = π*D`)
- [ ] `test/runtests.jl` — add `@testset "PHY-05: Pump fixed-flow mode"` block (stub for assembly + solve)
- [ ] `test/runtests.jl` — add `@testset "PHY-05: Pump error cases"` block (both provided / neither provided)
- [ ] `test/generate_mtr_reference.py` — update `pipe_ch` to `EffectivePipe.rectangular(0.6, 0.07, 0.00127, 0.07)` and re-run to capture new VAL reference constants

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
