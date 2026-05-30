---
phase: 55
slug: composition-helpers-examples-test-suite
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-07
---

# Phase 55 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `55-RESEARCH.md` Section 5 (Validation Architecture, Nyquist).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia base `Test` stdlib + `OrdinaryDiffEq.ReturnCode` for solver retcode assertions |
| **Config file** | None — `Project.toml` `[targets] test = ["Test"]` (verified `Project.toml:30`) |
| **Quick run command** | `bin/jl test/test_{file}.jl` (single file, ~3-12s warm on the daemon) |
| **Full suite command** | `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl` cold) |
| **Estimated runtime** | ~30-90s warm (full suite); ~3-12s warm per file |

---

## Sampling Rate

- **After every task commit:** Run `bin/jl test/test_{file_modified}.jl` (the test file mirroring the modified source file).
- **After every plan wave:** Run `bin/jl test/runtests.jl` — rejects regression in any of the 14 files.
- **Phase gate (TEST-05 close):** Full suite green per CONTEXT.md D-22 — "no NEW failures vs v1.0 baseline." Pre-existing flakies tolerated: VAL-01 (Fourier numerical) and NET-03 (Cube flow KINSOL convergence).
- **Max feedback latency:** ~12 seconds for a single test file warm; ~90s for full suite warm.

---

## Per-Task Verification Map

This map is filled in per-plan during planning. Below is the wave-level outline derived from RESEARCH.md §5; per-task rows are emitted by gsd-planner into each PLAN.md and aggregated here at execution time.

| Wave | Plan(s) | Requirements | Test Type | Automated Command | File Exists | Status |
|------|---------|--------------|-----------|-------------------|-------------|--------|
| 0 | spike: dangling-port hypothesis | (research lock) | spike | `bin/jl /tmp/spike_phase55_unbound.jl` | ❌ W0 | ⬜ pending |
| 0 | spike: build_loop_lof_bypass topology | (D-11) | spike | per RESEARCH.md §3 protocol | ❌ W0 | ⬜ pending |
| 1 | Channel/CHF redesign + sources.jl | TEST-01 | unit | `bin/jl test/test_channels.jl` | ⚠ rewritten | ⬜ pending |
| 1 | HeatFluxPort retirement | TEST-01 | unit | `bin/jl test/test_connectors.jl` | ✅ exists | ⬜ pending |
| 2 | test_channels.jl rewrite | TEST-01 | unit | `bin/jl test/test_channels.jl` | ⚠ rewritten | ⬜ pending |
| 2 | WallTemperature/HeatFluxSource unit tests | TEST-01 | unit | `bin/jl test/test_misc.jl` (or test_sources.jl) | ⚠ extended | ⬜ pending |
| 3 | composition helpers verify (likely no-change) | TEST-03 | compose-correctness | `bin/jl test/test_composition.jl` | ⚠ rewritten | ⬜ pending |
| 4 | builders + examples migration | TEST-02 | integration | `bin/jl test/test_integration.jl` | ❌ NEW | ⬜ pending |
| 5 | test_integration.jl absorbs 4 files + PK loops | TEST-02 | integration | `bin/jl test/test_integration.jl` | ❌ NEW | ⬜ pending |
| 6 | runtests.jl + test_thresholds.jl rename | TEST-05 | regression | `bin/jl test/runtests.jl` | ✅ exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

The four validation dimensions (per RESEARCH.md §5):

| Dim | Concern | Files where tests live |
|-----|---------|------------------------|
| **i. Component-level unit** | Each Channel/CHF/CAC variant instantiates and `mtkcompile`s cleanly under the new API; per-cell external-input vars exist; observable surface is correct; `_channel_core` G1-G4 enthalpy-form physics holds; flow-reversal sign safety; WallTemperature/HeatFluxSource unit behavior. | `test_channels.jl` (rewritten); `test_misc.jl` (extended); `test_connectors.jl` (HeatFluxPort tests removed) |
| **ii. Compose-correctness** | CAC↔HD assemblies via helpers compile cleanly across `(n, nz, nx)` shapes; balanced eqn/unknown counts; lightweight solve-to-verify yields meaningful steady states (NOT physics validation); `connect_temperature_feedback` equation-counting (TF-04); `_infer_n` correctness on CAC. | `test_composition.jl` (rewritten) |
| **iii. End-to-end integration** | Each builder + example builds, mtkcompiles, and runs `solve_steady`/`solve_transient` to physically meaningful endpoints. LOF (LOF-01..03) + VAL-01..02 + ISCB-01..02 + PK loops (LOOP-01..04, TF-06, TF-07) + builder smokes + solver wrappers. | `test_integration.jl` (NEW; absorbs `test_examples.jl`, `test_solvers.jl`, `test_loss_of_flow.jl`, `test_subcooled_boiling.jl`, parts of `test_point_kinetics.jl`) |
| **iv. Regression gate** | `bin/jl test/runtests.jl` green; no NEW failures vs v1.0 baseline; existing flakies (VAL-01 Fourier, NET-03 Cube flow KINSOL) tolerated per D-22. v1.0 baseline = whichever commit was tagged before `channels-redesign` opened. | All 14 test files via `test/runtests.jl` |

---

## Wave 0 Requirements

- [ ] `/tmp/spike_phase55_unbound.jl` — 5-line spike resolving hypothesis A vs B (does `mtkcompile(...; fully_determined=false)` eliminate unbound `T_wall_*[i]` or leave it as a free unknown?). Locks the adiabatic-by-default test idiom in `test_channels.jl` Wave 2.
- [ ] `/tmp/spike_phase55_lof_topology.jl` (or in-tree under `examples/spike_lof_*.jl`) — runs both Spike A (CAC + WallTemperature) and Spike B (CAC + HeatDiffusion plate) against the eight quantitative gates from RESEARCH.md §3. Picks the heated-leg topology for `build_loop_lof_bypass` BEFORE Wave 4 plan-locks.
- [ ] `test/test_channels.jl` — rewrite under new design (Wave 2). File exists today (replaces 31 Phase-54 tests).
- [ ] `test/test_composition.jl` — rewrite, expand CAC↔HD coverage (Wave 3).
- [ ] `test/test_integration.jl` — NEW file (Wave 5).
- [ ] `test/test_thresholds.jl` — pure rename of `test_analysis.jl` (Wave 6, trivial git mv + runtests.jl edit).
- [ ] `test/test_misc.jl` — add WallTemperature / HeatFluxSource testsets (Wave 1 or 2).
- [ ] `test/test_connectors.jl` — remove HeatFluxPort tests + `_StubFluxDriver` stub (Wave 1).
- [ ] `test/test_point_kinetics.jl` — TRIM (move LOOP-* + TF-06/07 to `test_integration.jl`; Wave 5).
- [ ] `test/runtests.jl` — update `include` lines for the 14-file layout (Wave 6).

Framework install: none — `Test` is a Julia stdlib, already wired via `Project.toml:30`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| LOF NC-reversal qualitative behavior reproduced under chosen heated-leg topology | TEST-02 (D-11 spike acceptance) | Quantitative tolerances live in spike script (Wave 0); but the *qualitative* "looks like the v1.0 trace" judgment is human-on-the-loop. | After Wave 0 spike, eyeball `lof_transient.jl`'s mdot(t) and T_wall(t) plots vs the v1.0 baseline plot. If they're the same shape (sign of mdot reverses, NC equilibrium reached), pass. |
| v1.0 baseline regression interpretation | TEST-05 | "No NEW failures vs baseline" requires diff-ing against the v1.0 tag's test output. Tooling is `git log main` + manual review of which failures pre-existed. | Before Wave 6 close: run `bin/jl test/runtests.jl` on current HEAD and on the v1.0 tag (or `main` HEAD if v1.0 tag absent), diff the failure lists, confirm `channels-redesign` adds zero new ones. |

---

## Validation Sign-Off

- [ ] All tasks have an `<automated>` test command or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers both spikes (dangling-port hypothesis + LOF topology) and all MISSING test files
- [ ] No watch-mode flags (Julia `Test` doesn't have one; daemon dev loop already covers fast iteration)
- [ ] Feedback latency < 12s per file warm; < 90s full suite warm
- [ ] `nyquist_compliant: true` set in frontmatter once all gates above are checked

**Approval:** pending
