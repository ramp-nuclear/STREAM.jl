---
phase: 1
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
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
| 1-01-01 | 01 | 0 | FOUND-01 | smoke | `julia --project=. -e 'using STREAM'` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 0 | FOUND-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | FOUND-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | FOUND-02 | integration | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 1 | CONN-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 1 | CONN-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — stubs/tests for FOUND-01, FOUND-02, CONN-01, CONN-02
- [ ] `Project.toml` — package declaration with correct dependencies (MTK v11, Sundials v5, DifferentialEquations)
- [ ] `src/STREAM.jl` — package entry point stub
- [ ] `src/fluids.jl` — fluid property functions stub
- [ ] `src/connectors.jl` — connector definitions stub

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `@register_symbolic` placed at module top-level (not inside function/begin) | FOUND-02 | Compile-time constraint, not runtime verifiable | Code review: confirm all 4 `@register_symbolic` calls are at module scope in `src/fluids.jl` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
