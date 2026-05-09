---
phase: 52
slug: channel-connectors
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-05
---

# Phase 52 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib `Test` (`@test`, `@testset`, `@test_nowarn`) |
| **Config file** | `test/runtests.jl` (orchestrator; `test_connectors.jl` already wired in line 4) |
| **Quick run command** | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. -e 'using Test; include("test/test_connectors.jl")'` |
| **Full suite command** | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. test/runtests.jl` |
| **Estimated runtime** | Quick: ~10s (with sysimage) / ~60s (cold); Full suite: ~90s (with sysimage) / ~5min (cold) |

---

## Sampling Rate

- **After every task commit:** Run quick `test/test_connectors.jl` (~10s, sysimage)
- **After every plan wave:** Run full `test/runtests.jl` to confirm CONN-03 non-regression of `ChannelAndContacts`, `Channel`, composition helpers, examples
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~10s per task (with sysimage); ~90s per wave

---

## Per-Task Verification Map

> The planner will fill this table once `*-PLAN.md` files exist with task IDs.
> Each row maps a task to the `@testset` that proves it. Source: research §"Phase Requirements → Test Map".

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 52-01-T1 | 01 | 1 | CONN-01, CONN-02 | T-52-01..04 | N/A | structural (in-source grep + REPL @named) | `grep -c "^@connector function" src/connectors.jl` returns `4` | ❌ W0 (this task IS the work) | ⬜ pending |
| 52-01-T2 | 01 | 1 | CONN-01, CONN-02 | T-52-05 | N/A | existence (export reachability) | `julia --project=. -e 'using STREAM; @named wp = WallPort(); @named hf = HeatFluxPort()'` exits 0 | ❌ W0 | ⬜ pending |
| 52-02-T1 | 02 | 2 | CONN-01, CONN-02, CONN-04 | T-52-06 | N/A | scaffolding (stubs added; existing testsets still pass) | `julia --project=. -e 'using Test; include("test/test_connectors.jl")'` exits 0 | ❌ W0 | ⬜ pending |
| 52-02-T2 | 02 | 2 | CONN-01 (structural) | — | N/A | structural (variable count + Flow/across annotations) | testset "CONN-01: WallPort variable count" + 3 sister testsets pass | ❌ W0 | ⬜ pending |
| 52-02-T2 | 02 | 2 | CONN-02 (structural) | — | N/A | structural (variable count + Flow/across annotations) | testset "CONN-02: HeatFluxPort variable count" + 2 sister testsets pass | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-01 (behavioural) | T-52-06 | N/A | behavioural (rtol=1e-8 adiabatic hold) | testset "CONN-01: WallPort adiabatic when unconnected" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-01 (driven) | — | N/A | behavioural (driven heat-rise) | testset "CONN-01: WallPort driven case heats stub" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-02 (behavioural) | — | N/A | behavioural (rtol=1e-8 zero-flux hold) | testset "CONN-02: HeatFluxPort zero-flux when unconnected" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-02 (driven) | — | N/A | behavioural (q_flux propagation across connect()) | testset "CONN-02: HeatFluxPort driven case propagates q_flux" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-04 (connect) | — | N/A | structural (equation count) | testset "CONN-04: connect() equation count" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-04 (instream) | T-52-06, T-52-08 | N/A | integration (no MTK warnings, finite unknowns, adiabatic hold) | testset "CONN-04: instream smoke (WallPort)" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-04 (instream) | T-52-06, T-52-08 | N/A | integration (no MTK warnings, finite unknowns, adiabatic hold) | testset "CONN-04: instream smoke (HeatFluxPort)" passes | ❌ W0 | ⬜ pending |
| 52-02-T3 | 02 | 2 | CONN-03 | — | N/A | regression (full suite incl. existing FlowPort/ThermalPort + ChannelAndContacts) | `julia --project=. test/runtests.jl` exits 0 | ✅ exists (legacy FlowPort/ThermalPort testsets in `test_connectors.jl:17-82`) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_connectors.jl` — append three inline stubs at top-of-file (after imports):
      `_StubRecipient(; n, port_type)`, `_StubWallDriver(; n, T_w, h_v)`, `_StubFluxDriver(; n, q_v)`
- [ ] `test/test_connectors.jl` — append ~14 new `@testset`s (per the table above) covering CONN-01, CONN-02, CONN-04 sub-criteria; CONN-03 leans on existing testsets + full-suite regression
- [ ] No new test file (D-11 keeps everything in `test_connectors.jl`)
- [ ] No conftest / shared fixtures (Julia `Test` doesn't have conftest; stubs are file-local)
- [ ] No framework install (`Test` is stdlib, already loaded by `test/runtests.jl:1`)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `using STREAM; @named wp = WallPort()` succeeds at the REPL | CONN-01 | Smoke for the export contract — the `@named` macro path through the public re-export. Functional check covered by automated existence testset, but a one-shot REPL check confirms `Pkg.precompile` produced a usable artefact. | `julia --project=. -e 'using STREAM; @named wp = WallPort(); println(wp)'` — exits 0. |
| `using STREAM; @named hf = HeatFluxPort()` succeeds at the REPL | CONN-02 | Same as above for the second connector. | `julia --project=. -e 'using STREAM; @named hf = HeatFluxPort(); println(hf)'` — exits 0. |

*Both manual checks are covered redundantly by automated existence testsets; listed here only for the Phase 52 success-criterion #1 ("constructing a connector instance succeeds at the REPL").*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (verified by gsd-plan-checker 2026-05-05)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (verified by gsd-plan-checker 2026-05-05)
- [x] Wave 0 covers all MISSING references — Plan 02 itself supplies the test scaffolding (stubs + testsets) it later runs
- [x] No watch-mode flags (Julia `Test` runs once and exits)
- [x] Feedback latency < 90s for full suite, ~10s for connector-only
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-05-05 by gsd-plan-checker (`## VERIFICATION PASSED`)
