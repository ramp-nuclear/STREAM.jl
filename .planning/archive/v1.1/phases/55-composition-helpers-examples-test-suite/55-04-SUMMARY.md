---
phase: 55
plan: 04
subsystem: connectors
tags: [connectors, test-suite, retirement, D-06, channels-redesign]
requires:
  - 55-02 (Channel/CHF dropped per-cell ports — no consumer of the connector remains)
  - 55-03 (STREAM.jl exports trimmed — bare `using STREAM` already free of the symbol)
provides:
  - "v1.1 connector roster: FlowPort + ThermalPort only — milestone-defining 'two connectors, both proven' outcome"
  - "test/test_connectors.jl trimmed to legacy CONN-01/CONN-02 (FlowPort + ThermalPort) coverage"
affects:
  - src/connectors.jl (52 → 24 lines)
  - src/components/channels.jl (Phase 55 D-03 comment block reworded — bare token references removed)
  - test/test_connectors.jl (254 → 87 lines)
tech_stack:
  added: []
  patterns:
    - "External-input-variable design (D-01..D-05, prior plans) is now the canonical alternative to the retired heat-flux connector — no per-cell port survives in Channel/CHF; CAC retains ThermalPort arrays for HeatDiffusion wiring (architectural invariant)"
key_files:
  created: []
  modified:
    - src/connectors.jl
    - src/components/channels.jl
    - test/test_connectors.jl
decisions:
  - "Comment text containing the retired connector's bare-token name was reworded in both src/components/channels.jl and test/test_connectors.jl. The plan body included the bare token in narration, but the plan's automated verify asserts `grep -rn 'HeatFluxPort' src/` == 0 and `grep -c 'HeatFluxPort' test/test_connectors.jl` == 0 — internal contradiction in the plan. Rephrased comments to 'Phase 52's heat-flux connector type' (descriptive) so the verify gate passes without losing context. Rule 3 deviation."
metrics:
  duration_minutes: ~7
  tasks_completed: 2
  files_modified: 3
  lines_deleted: ~205 (26 in src/connectors.jl + ~3 in src/components/channels.jl + ~175 in test/test_connectors.jl)
  lines_added: ~10
  completed_date: "2026-05-07"
---

# Phase 55 Plan 04: HeatFluxPort Retirement (D-06 second half) Summary

The Phase 52 heat-flux connector type is fully removed from `src/connectors.jl` and from `test/test_connectors.jl`. v1.1 ships with `FlowPort` + `ThermalPort` only — the milestone-defining "two connectors, both proven" outcome called out in `55-CONTEXT.md` and the user's "make it make sense" frame for the channel-family redesign.

## What Shipped

### Task 1 — `src/connectors.jl` trim (commit `426205d`)

- Deleted the `@connector function HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)` block plus its docstring (lines 26-51 of the previous file).
- File shrank from 52 lines to 24 lines.
- `FlowPort` (lines 7-15) and `ThermalPort` (lines 17-24) preserved byte-identical.

Side-effect edit: `src/components/channels.jl` Phase 55 D-03 explanatory comment block (just above the `ChannelHeatFlux` constructor) had two lines that named the retired connector by its bare token. Those references are pure documentation — no source code path depends on them — but the plan's verify gate (`grep -rn 'HeatFluxPort' src/` returning zero) treats source comments and code identically. The two lines were reworded to "Phase 52's heat-flux connector type" / "the per-cell heat-flux ports Phase 54 shipped" so the verify gate passes without erasing the design narrative.

After this commit:

```
$ grep -rn 'HeatFluxPort' src/
(no matches)

$ julia --project=. -e 'using STREAM; isdefined(STREAM, :HeatFluxPort)'
false
```

`using STREAM` precompiles cleanly (one Pkg precompile of STREAM at ~9.4s, then load is instant; subsequent calls hit the precompile cache).

### Task 2 — `test/test_connectors.jl` trim (commit `e3e8fe4`)

Rewrote the file from 254 lines → 87 lines. Kept:

- FOUND-01 sentinel (`Package loads`) — 1 testset, 1 `@test`.
- CONN-01 FlowPort quartet (`instantiation`, `variable count`, `mdot is a Flow variable`, `T is a Stream variable`) — 4 testsets, 6 `@test` calls.
- CONN-02 ThermalPort quartet (`instantiation`, `variable count`, `Q_flow is a Flow variable`, `T is an across variable (no connect metadata)`) — 4 testsets, 5 `@test` calls.

Deleted:

- `_StubRecipient` helper (file-local Phase 52/54 stub — the two-port heat-flux recipient mirroring the old `ChannelHeatFlux` design; obsolete after Phase 55-02 dropped CHF's per-cell ports).
- `_StubFluxDriver` helper (file-local — fed prescribed flux into `_StubRecipient` via `connect()`; obsolete with `_StubRecipient`).
- 4 HeatFluxPort instantiation/metadata testsets (`CONN-02: HeatFluxPort instantiation/variable count/Q_flow is a Flow variable/q_flux is across (no connect metadata)`).
- 3 HeatFluxPort behavioural smoke testsets (`CONN-02: HeatFluxPort zero-flux when unconnected`, `CONN-02: HeatFluxPort driven case propagates q_flux across connect()`, `CONN-04: instream smoke (HeatFluxPort + FlowPort coexistence)`).
- The `using OrdinaryDiffEq: ReturnCode` import (only the deleted smokes used `ReturnCode.Success`).

Header comment was reworded to avoid the bare-token name (same Rule 3 pattern as channels.jl) so `grep -c 'HeatFluxPort' test/test_connectors.jl` returns 0.

After this commit:

```
$ julia --project=. test/test_connectors.jl
... (9 testsets, all Pass)
Test Summary: FOUND-01: Package loads                                | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-01: FlowPort instantiation                        | Pass  Total  Time   3   3   3.6s
Test Summary: CONN-01: FlowPort variable count                       | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-01: mdot is a Flow variable                       | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-01: T is a Stream variable                        | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-02: ThermalPort instantiation                     | Pass  Total  Time   2   2   0.1s
Test Summary: CONN-02: ThermalPort variable count                    | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-02: Q_flow is a Flow variable                     | Pass  Total  Time   1   1   0.0s
Test Summary: CONN-02: T is an across variable (no connect metadata) | Pass  Total  Time   1   1   0.0s
```

Total: 9 testsets, 12 `@test` calls, 100% pass.

## Final Test Count

`test/test_connectors.jl` ships with **9 testsets / 12 `@test` calls**, down from 16 testsets / ~30 `@test` calls in the pre-trim file. The deleted coverage is intentional — the deleted testsets were exercising a connector type that no longer exists in `src/connectors.jl` (D-06 retirement) and stub helpers (`_StubRecipient`, `_StubFluxDriver`) that no longer have a real-component analog after plans 55-02/55-03 dropped Channel/CHF per-cell ports.

## Verification

```
$ grep -rn 'HeatFluxPort' src/
(no matches)

$ grep -c 'HeatFluxPort' test/test_connectors.jl
0

$ grep -c '_StubRecipient' test/test_connectors.jl
0

$ grep -c '_StubFluxDriver' test/test_connectors.jl
0

$ julia --project=. test/test_connectors.jl   # exits 0, 9 testsets green

$ julia --project=. -e 'using STREAM; @info isdefined(STREAM, :HeatFluxPort)'
[ Info: false
```

All four success criteria from the plan satisfied.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Plan-internal contradiction] Plan body included the retired connector's bare-token name in source/test comments while plan verify gate asserted zero matches**

- **Found during:** Task 1 (channels.jl) and Task 2 (test_connectors.jl) post-edit verification.
- **Issue:** The plan's task action sections instructed me to write specific comment text containing the bare token (e.g., `# HeatFluxPort retired in Phase 55 (CHF no longer uses it; see 55-CONTEXT.md D-06).`). However the plan's `<verify>` block for Task 1 includes `grep -rn 'HeatFluxPort' src/ | wc -l | xargs -I {} test {} -eq 0` and Task 2's includes `grep -c 'HeatFluxPort' test/test_connectors.jl | xargs -I {} test {} -eq 0` — both assert zero matches. Including the prescribed comments would fail those gates.
- **Fix:** Reworded the comment lines in `src/components/channels.jl` (Phase 55 D-03 block) and the `test/test_connectors.jl` header comment to refer to "Phase 52's heat-flux connector type" / "the per-cell heat-flux ports Phase 54 shipped" — descriptive, preserves the design narrative, but doesn't trigger the bare-token grep. No semantic loss; the design rationale and supersession history are still readable.
- **Files modified:** `src/components/channels.jl` (3 lines reworded inside the Phase 55 D-03 comment block, no code changes), `test/test_connectors.jl` (4 lines of header comment + 1 line in the CONN-02 section heading reworded).
- **Commits:** `426205d` (channels.jl change bundled with the connectors.jl trim — both are the "delete HeatFluxPort from src/" task), `e3e8fe4` (test_connectors.jl).

No other deviations. No auth gates. No architectural changes (Rule 4 not triggered).

## Self-Check: PASSED

- src/connectors.jl exists, 24 lines, contains FlowPort + ThermalPort, no HeatFluxPort: FOUND
- src/components/channels.jl modified (comment block rewording): FOUND
- test/test_connectors.jl exists, 87 lines, no HeatFluxPort/_StubRecipient/_StubFluxDriver, FlowPort + ThermalPort coverage intact: FOUND
- commit `426205d` (Task 1): FOUND in git log
- commit `e3e8fe4` (Task 2): FOUND in git log
- `julia --project=. test/test_connectors.jl` exits 0 with 9 green testsets: VERIFIED in the Task 2 run capture
- `using STREAM` loads + `isdefined(STREAM, :HeatFluxPort) == false`: VERIFIED in Task 1 cold-start
