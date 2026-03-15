---
phase: 13
slug: physics-foundation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-14
audited: 2026-03-15
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
| 13-01-W0 | 01 | 0 | PHY-01 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-01-01 | 01 | 1 | PHY-01 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-01-02 | 01 | 1 | PHY-01 | regression | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-01-03 | 01 | 1 | PHY-01 | integration | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-02-W0 | 02 | 0 | PHY-05 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-02-01 | 02 | 1 | PHY-05 | unit | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-02-02 | 02 | 1 | PHY-05 | integration | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |
| 13-02-03 | 02 | 1 | PHY-05 | regression | `julia --project=. -e "using Pkg; Pkg.test()"` | ✅ exists | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — `@testset "PHY-01: PipeGeometry_rectangular geometry"` (lines 120-139: 8 assertions)
- [x] `test/runtests.jl` — `@testset "PHY-01: PipeGeometry_circular geometry"` (lines 141-152: 5 assertions)
- [x] `test/runtests.jl` — `@testset "PHY-05: Pump fixed-flow mode"` (lines 157-186: callable + mtkcompile + integration)
- [x] `test/runtests.jl` — `@testset "PHY-05: Pump error cases"` (lines 188-193: 2 @test_throws)
- [x] `test/generate_mtr_reference.py` — uses `EffectivePipe.rectangular(length=LZ, edge1=Y_LEN, edge2=LX, heated_edge=Y_LEN)` (line 82)

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved (2026-03-15 — retroactive audit, 0 gaps found)

---

## Validation Audit 2026-03-15

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| All tasks | 8/8 COVERED |

All Wave 0 stubs were implemented during phase execution. PHY-01 has 2 testsets (13 assertions). PHY-05 has 2 testsets (callable + mtkcompile + integration loop + 2 error cases). No test gaps remain.
