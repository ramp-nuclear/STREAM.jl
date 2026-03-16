---
phase: 19
slug: docstrings-claude-md-and-final-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia's built-in `Test` stdlib |
| **Config file** | none — tests run via `julia --project test/runtests.jl` |
| **Quick run command** | `julia --project -e 'using STREAM'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'using STREAM'` — confirms package loads without error after each docstring batch
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 0 | QOL-05 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 19-01-02 | 01 | 1 | DOC-01 | manual | `julia --project -e 'using STREAM; @doc Channel'` | N/A | ⬜ pending |
| 19-01-03 | 01 | 1 | DOC-02 | manual | `julia --project -e 'using STREAM; @doc symmetric_plate'` | N/A | ⬜ pending |
| 19-01-04 | 01 | 1 | DOC-03 | manual | `julia --project -e 'using STREAM; @doc solve_steady'` | N/A | ⬜ pending |
| 19-01-05 | 01 | 1 | DOC-04 | manual | `julia --project -e 'using STREAM; @doc rho_water'` | N/A | ⬜ pending |
| 19-01-06 | 01 | 2 | QOL-03 | manual | n/a | N/A | ⬜ pending |
| 19-01-07 | 01 | 2 | QOL-04 | smoke | `julia --project -e 'import Pkg; Pkg.status()'` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_channel.jl` — add `@testset "ChannelHeatFlux"` dedicated block (covers QOL-05)

*(All other test infrastructure exists and is sufficient for this phase.)*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Component constructors have docstrings | DOC-01 | Docstrings are evaluated at REPL time; no automated assertion exists in the test suite | `julia --project -e 'using STREAM; @doc Channel'` (and repeat for all 11 components) |
| Composition/QoL helpers have docstrings | DOC-02 | Same reason as DOC-01 | `julia --project -e 'using STREAM; @doc symmetric_plate'` (and all 6 helpers) |
| Solver/example functions have docstrings | DOC-03 | Same reason as DOC-01 | `julia --project -e 'using STREAM; @doc solve_steady'` (and all 7 functions) |
| Fluid function docstrings have `# Arguments` and `# Returns` | DOC-04 | Same reason as DOC-01 | `julia --project -e 'using STREAM; @doc rho_water'` |
| CLAUDE.md has rationale + MTK patterns section | QOL-03 | Documentation content review | Open `CLAUDE.md`, verify each rule has a `Why:` line and MTK Patterns section exists |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
