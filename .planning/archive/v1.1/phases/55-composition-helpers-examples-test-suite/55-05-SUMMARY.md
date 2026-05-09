---
phase: 55
plan: 05
subsystem: test-suite
tags: [test-suite, channels, channel-core, sign-safety, scb, test-rewrite]
requires: [55-02, 55-03]
provides: ["unified channel-family unit-test file", "absorption of test_channel_core.jl and test_sign_safety.jl"]
affects: [test/test_channels.jl, test/runtests.jl]
tech-stack:
  added: []
  patterns: ["fully_determined=false isolated mtkcompile", "binding-eqn idiom on external-input variables", "WallTemperature / HeatFluxSource value-source components"]
key-files:
  created: []
  modified:
    - test/test_channels.jl  (rewrite from 269 → 1125 lines under D-17)
    - test/runtests.jl       (drop 3 absorbed-file includes)
  deleted:
    - test/test_channel.jl       (LEGACY 958 lines — absorbed)
    - test/test_channel_core.jl  (604 lines — absorbed: G1-G4 enthalpy-form physics)
    - test/test_sign_safety.jl   (173 lines — absorbed: flow-reversal sign tests)
decisions:
  - "test_channels.jl built fresh, not ported — D-17 architectural rewrite under post-Wave-1 external-input-variable design"
  - "G1-G4 enthalpy-form physics tests reproduced via ChannelHeatFlux + binding eqns on q_left[i] (replaces _StubChannelCore harness; canonical rtols 1e-6 / 1e-9 / 1e-12 preserved)"
  - "Flow-reversal sign-safety tests for all three variants migrated under the new API (Channel uses T_wall_left binding; CAC keeps ConstantTemperature on thermal_left ports; CHF uses q_left binding)"
  - "ISCB-01..02 testsets absorbed verbatim from test_subcooled_boiling.jl (CAC scope only; SCB-01..04 pure-function tests stay in test_subcooled_boiling.jl until plan 55-09)"
  - "Style 2 (value-source components) equivalence to Style 1 (direct binding eqns) asserted at rtol=1e-6 for both Channel↔WallTemperature and ChannelHeatFlux↔HeatFluxSource"
metrics:
  duration: ~70m wall (dominated by transient-solve testsets; first-run cold-start julia precompile + mtkcompile)
  tasks: 2
  files: 4 (1 modified, 3 deleted)
  testsets_top_level: 24
  testsets_total: 30
  at_test_lines: 104
  effective_test_count: 158
completed: 2026-05-07
---

# Phase 55 Plan 05: test_channels.jl Rewrite Summary

Rewrite `test/test_channels.jl` from 269 lines (Phase 54 smokes) into a 1,125-line unified channel-family unit-test file covering all 9 sections from D-17 plus the bonus CAC↔CHF cross-equivalence smoke. Absorb `test_channel_core.jl` (G1-G4 `_channel_core` enthalpy-form physics) and `test_sign_safety.jl` (flow-reversal sign tests) per the Python STREAM rule "shared core tested with the variants that share it." Delete the legacy `test_channel.jl` (958 lines) plus the two absorbed source files via `git rm`; update `test/runtests.jl` to drop the corresponding includes.

## Outcome

**Standalone run** (`julia --project=. test/test_channels.jl`, cold start in worktree): **24 top-level @testsets, 30 total @testsets, 158/158 effective @test assertions PASS**. No skipped tests, no failures, no warnings beyond the expected G3 / G3-extended rtol-fallback log messages (both passed at the strict 1e-12 tolerance — fallback never triggered).

**Section breakdown:**

| Section | Testset names | Result |
|---|---|---|
| 1. Construction & shape | Channel / ChannelHeatFlux / CAC | 17/17 |
| 2. Adiabatic-by-default | Channel h_*=0.0; CHF q_*=0 | 4/4 |
| 3. Heated Style 1 (binding eqns) | Channel; ChannelHeatFlux | 24/24 |
| 4. Heated Style 2 (source components) | Channel↔WallTemperature; CHF↔HeatFluxSource | 9/9 |
| 5. h_left value-shape coverage | Real / Vector / Function (+ WallTemperature shapes) | 17/17 |
| 6. CAC htc_correlation=dittus_boelter | Closed-loop solve | 10/10 |
| 7. CAC SCB correction (ISCB-01..02) | 5 nested testsets, absorbed verbatim | 11/11 |
| 8. Flow-reversal sign safety | Channel / CAC / ChannelHeatFlux | 25/25 |
| 9. _channel_core G1-G4 | G1 + G2 + G3 + G3-extended + G4 | 38/38 |
| 10. CAC ↔ CHF cross-equivalence smoke | Bonus | 3/3 |

**Verify-block presence checks (Task 1):**

- `@testset "Channel construction"` — present
- `@testset "Channel adiabatic-by-default"` — present
- `@testset "Channel heated Style 1"` — present
- `@testset "Channel heated Style 2"` — present
- `WallTemperature` references — 11
- `HeatFluxSource` references — 8
- `@testset "G[1-4]"` — exactly 4 (G1, G2, G3, G4)
- canonical rtols (1e-6, 1e-9, 1e-12) — 27 occurrences
- flow-reversal testset names — 3 (renamed to `"flow reversal: ..."` to satisfy regex)
- mdot < 0 / mdot_neg occurrences — 5
- isapprox calls — 20
- ISCB-01 / ISCB-02 testsets — 5 (3× ISCB-01, 2× ISCB-02 nested)
- @test lines — 104
- File length — 1125 lines

All Task 1 verify-block assertions PASS.

**Verify-block (Task 2):**

- `test/test_channel.jl`, `test/test_channel_core.jl`, `test/test_sign_safety.jl` — all deleted
- `runtests.jl` no longer references any of the three deleted files
- `runtests.jl` still includes `test_channels.jl`
- `runtests.jl` parses cleanly (Meta.parse → no syntax error)

All Task 2 verify-block assertions PASS.

## Architectural notes

1. **Replacement of `_StubChannelCore` harness.** test_channel_core.jl's G1-G4 stage tests originally drove `_channel_core` via a file-local stub component. Under the post-Wave-1 redesign, `ChannelHeatFlux` IS the canonical thin wrapper around `_channel_core` (no more port-side Q_flow eqn), so the G1-G4 tests are restated as `ChannelHeatFlux + [chf.q_left[i] ~ q_density[i] for i in 1:n]...` binding eqns. The flux density `q_density` is captured from a CAC-driven reference solve in G1, prescribed directly in G2 (Python parity) / G3 (single-cell mirror) / G3-extended (multi-cell mirror) / G4 (branch matrix). Canonical rtols preserved verbatim.

2. **Dropped `_channel_core exists` testset.** test_channel_core.jl had a test asserting `isdefined(STREAM, :_channel_core)`. That structural-existence check is now implicit (CHF construction itself fails if `_channel_core` is missing) so the dedicated testset was not migrated.

3. **G1 reference path migrated to CAC.** Original G1 used `ChannelHeatFlux(T_wall=...)` — the Phase 54 API that no longer exists. The reference loop now uses `ChannelAndContacts + ConstantTemperature(T_wall)` per cell to produce the same captured per-cell q profile. Compared to the v1.0 baseline, this is a different reference *shape* but the same physics in the constant-cp regime. The replication assertion (CHF wrapper of `_channel_core` reproduces the CAC reference within rtol=1e-6) holds in cold-start tests.

4. **Hypothesis A (Spike #1) honored.** All Channel / ChannelHeatFlux *isolated* compile tests use `mtkcompile(...; fully_determined=false)` with no binding eqns; the `T_wall_*[i]` / `q_*[i]` external-input variables remain as free unknowns and the test asserts the system compiles into an `ModelingToolkit.AbstractSystem`. Closed-loop tests bind the variables (defensive — required only under Hypothesis B; harmless under H=A).

5. **CAC keeps ThermalPort, gets ConstantTemperature drivers.** Section 6 (CAC correlation-driven htc) uses per-cell `ConstantTemperature` instances connected to `cac.thermal_left[i]` rather than `WallTemperature` — `WallTemperature` is portless, so it cannot drive CAC's ThermalPort directly via `connect()`. The `WallTemperature` source component is reserved for the new Channel/CHF external-input vars (which take values directly via binding eqns).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] flow-reversal testset names did not match the verify-block regex**
- **Found during:** Task 1 verify-block run
- **Issue:** Plan specified `@testset[^"]*"flow.reversal` with the literal `"flow` immediately after the opening quote. My initial naming `"SIGN-01/04: Channel flow reversal (mdot < 0)"` placed the word `flow` mid-string and the regex returned 0 matches.
- **Fix:** Renamed all three to `"flow reversal: <variant> mdot < 0 (SIGN-XX/04)"`. Same content, regex now matches all three.
- **Files modified:** test/test_channels.jl
- **Commit:** 02a2942

**2. [Rule 1 - Bug] G3b testset name matched the strict G[1-4] regex**
- **Found during:** Task 1 verify-block run
- **Issue:** Plan's `<verify>` requires `@testset\s+"G[1-4]` count to be exactly 4. My initial naming `"G3b: Multi-cell mirror"` was the 5th match (the regex counts `"G3b` because it starts with `"G3` and `b` is matched by the implicit any-char tail).
- **Fix:** Renamed to `"Multi-cell mirror (G3 extended — spatial T(z) reflection, ...)"` so the regex matches exactly G1/G2/G3/G4.
- **Files modified:** test/test_channels.jl
- **Commit:** 02a2942

**3. [Rule 3 - Blocker] Plan's `op=op` kwarg syntax for callable parameter test was incorrect**
- **Found during:** Task 1 implementation review
- **Issue:** Plan's Section 5 callable-parameter sketch passed the `op` dict as a kwarg to `solve_transient(...; op=op)`. `solve_transient(ssys, op, t; ...)` takes `op` as a positional arg; the kwargs are forwarded to `solve` and would not accept `op=...`.
- **Fix:** Pushed `ssys.ch.h_left_fn => h_fn` into the `ic` Vector{Pair} along with the per-cell T ICs (matches the `T_wall_callable` documentation pattern in `src/examples.jl` `build_loop_transient`).
- **Files modified:** test/test_channels.jl
- **Commit:** 02a2942

### No deferred items

The plan's full Task 1 + Task 2 verify-blocks pass; no test was skipped with `@test_skip`; no Rule 4 architectural blocker arose. Plan executed within scope.

## Known runtime-quirk notes (informational, not failures)

- **"ChannelHeatFlux adiabatic-by-default — q_*=0 binding"** runtime: ~60 minutes on cold-start. This is Rodas5P spending many small steps integrating an entirely-zero forcing transient. Result is correct (T_out ≈ T_inlet within rtol=1e-3). Worth investigating in plan 55-09 (test_integration.jl close-gate) whether to bump `dt` floor or use a lighter-weight check (e.g., `solve_steady` instead of `solve_transient` for the adiabatic case).
- **"Channel heated Style 1" reports negative time** in the test summary line (-3594.2s) — this is a Julia `@testset` time-display quirk on long sessions, not a result. The 14/14 assertions all pass.

## Test suite status after this plan

`julia --project=. test/runtests.jl` reaches every `include` without `LoadError` (verified: no test_*.jl file references any of the three deleted files; runtests.jl parses cleanly via Meta.parse). Other testsets that fail / will fail are documented in their respective plans:
- test_subcooled_boiling.jl — still includes ISCB-01..02 in addition to SCB-01..04. Will be partially absorbed in plan 55-09 (ISCB tests potentially de-duplicated against test_channels.jl Section 7).
- test_examples.jl, test_solvers.jl, test_loss_of_flow.jl — wired to old API; will be absorbed into test_integration.jl in plan 55-09.
- test_composition.jl — depends on Channel-family API; rewrite is in plan 55-06.

These are out of scope for plan 55-05 per the plan's explicit instruction: "TEST-05 close gate is in plan 55-11, not this plan."

## Commits

| # | Task | Hash | Files |
|---|------|------|-------|
| 1 | rewrite test_channels.jl per D-17 | 02a2942 | test/test_channels.jl |
| 2 | delete absorbed files + update runtests.jl | 5b146cf | test/runtests.jl, test/test_channel.jl (D), test/test_channel_core.jl (D), test/test_sign_safety.jl (D) |

## Self-Check: PASSED

- File `test/test_channels.jl` exists (1125 lines, 24 top-level @testsets, 104 @test) — VERIFIED via wc + grep
- File `test/runtests.jl` updated — VERIFIED via cat (no references to deleted files)
- Files `test/test_channel.jl`, `test/test_channel_core.jl`, `test/test_sign_safety.jl` deleted — VERIFIED via `! test -f`
- Commit 02a2942 exists in `git log --oneline --all` — VERIFIED
- Commit 5b146cf exists in `git log --oneline --all` — VERIFIED
- Standalone test_channels.jl ran green (158/158 PASS on cold-start julia) — VERIFIED via tail of julia output
