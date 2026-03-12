---
phase: 1
slug: foundation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
audited: 2026-03-13
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib `Test` (no install needed) |
| **Config file** | none — triggered by `] test` in Pkg REPL mode |
| **Quick run command** | `julia --project=. -e 'using STREAM'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 seconds (first run; ~10s cached) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'using STREAM'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 0 | FOUND-01 | smoke | `julia --project=. -e 'using STREAM'` | ✅ | ✅ green |
| 1-01-02 | 01 | 0 | FOUND-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ✅ green |
| 1-01-03 | 01 | 1 | FOUND-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ✅ green |
| 1-01-04 | 01 | 1 | FOUND-02 | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ✅ green |
| 1-02-01 | 02 | 1 | CONN-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ✅ green |
| 1-02-02 | 02 | 1 | CONN-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — stubs/tests for FOUND-01, FOUND-02, CONN-01, CONN-02
- [x] `Project.toml` — package declaration with correct dependencies (MTK v11, Sundials v5, DifferentialEquations)
- [x] `src/STREAM.jl` — package entry point stub
- [x] `src/fluids.jl` — fluid property functions stub
- [x] `src/connectors.jl` — connector definitions stub

---

## Requirement Coverage

| Requirement | Test Location | Test Name | Status |
|-------------|---------------|-----------|--------|
| FOUND-01 | test/runtests.jl | `FOUND-01: Package loads` | ✅ COVERED |
| FOUND-02 | test/runtests.jl | `FOUND-02: rho_water`, `cp_water`, `mu_water`, `k_water`, `MTK smoke test` | ✅ COVERED |
| CONN-01 | test/runtests.jl | `CONN-01: FlowPort instantiation`, `variable count`, `mdot is Flow`, `T is Stream` | ✅ COVERED |
| CONN-02 | test/runtests.jl | `CONN-02: ThermalPort instantiation`, `variable count`, `Q_flow is Flow`, `T is across` | ✅ COVERED |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `@register_symbolic` placed at module top-level (not inside function/begin) | FOUND-02 | Compile-time constraint, not runtime verifiable | Code review: confirm all 4 `@register_symbolic` calls are at module scope in `src/fluids.jl` |

**Manual review status:** Confirmed — all 4 `@register_symbolic` calls are at module top-level in `src/fluids.jl` (Plan 01-01 execution verified this pattern; the MTK smoke test `rho_water(T_sym) isa Symbolics.Num` provides runtime evidence the registration is active).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** Complete — all 4 requirements COVERED by automated tests in `test/runtests.jl`. 25 Phase 1 tests pass.

---

## Validation Audit 2026-03-13

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated to manual-only | 0 |
| Requirements COVERED | 4/4 |
| Requirements PARTIAL | 0/4 |
| Requirements MISSING | 0/4 |

All Phase 1 requirements (FOUND-01, FOUND-02, CONN-01, CONN-02) have automated test coverage in `test/runtests.jl`. The 25 Phase 1 tests pass in the current 54-test suite.
