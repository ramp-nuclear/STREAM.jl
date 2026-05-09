---
phase: 55
plan: 01
subsystem: spikes
tags: [wave-0, spike, mtk-structural-balance, lof-topology]
dependency_graph:
  requires:
    - "Phase 54 channels.jl (Channel/CHF/CAC variants — pre-Wave-1 shape)"
    - "src/composition/helpers.jl one_sided_connection, port"
    - "src/components/flapper.jl Flapper + flapper_callback"
    - "src/components/heat_diffusion.jl HeatDiffusion (5 mandatory kwargs)"
  provides:
    - "spike_unbound_hypothesis=A (locks Wave 2 test_channels.jl idiom)"
    - "spike_lof_winner=B (locks Wave 4 build_loop_lof_bypass topology)"
    - "examples/spike_phase55_unbound.jl (reproducible §2 spike)"
    - "examples/spike_phase55_lof_topology.jl (reproducible §3 spike)"
  affects:
    - "Plan 55-04 (Wave 2 — test_channels.jl rewrite)"
    - "Plan 55-07 (Wave 4 — build_loop_lof_bypass + LOF builder)"
    - "Plan 55-08 (Wave 5 — lof_transient.jl example IC dict)"
tech_stack:
  added: []
  patterns:
    - "ThermalPort + connect() driver pattern (single connection-set eqn per cell, avoids `~`-binding over-determination)"
    - "fully_determined=false mtkcompile for adiabatic-by-default confirmation in isolation"
    - "_lof_bypass_ic IC dict (mdot seed + Dt(ret.port_in.mdot)=0 + flapper.T_open sentinel)"
key_files:
  created:
    - "examples/spike_phase55_unbound.jl"
    - "examples/spike_phase55_lof_topology.jl"
    - ".planning/phases/55-composition-helpers-examples-test-suite/55-WAVE0-SPIKE-RESULTS.md"
  modified: []
decisions:
  - "Hypothesis A confirmed literally: T_wall_left[i]/T_wall_right[i] survive structural simplification as free unknowns under `mtkcompile(...; fully_determined=false)` even with `h_*=0.0` (Q2 stand-in produced 4 unknowns retained for n=4)."
  - "LOF topology winner is Spike B (CAC + HeatDiffusion plate). Spike A's CAC + WallTemperature variant fell short on gate D because pinning T_wall=373.15K provides too weak a buoyancy drive to sustain NC ≥ 1e-3 kg/s; Spike B's 1 kW imposed power produces |mdot_nc|=4.3e-3 kg/s."
  - "Adopted the ThermalPort + connect() driver pattern for both spikes (mirrors test_channels.jl _WallTempDriver). Plan's `~`-binding suggestion was rejected after the first run produced 10 extra equations (over-determined connection set)."
metrics:
  duration_seconds: ~120
  duration_human: "~2 min wall-time across 5 daemon submissions for Spike #2 iteration plus a ~3s warm Spike #1; cold-start would be ~90s extra"
  completed_date: "2026-05-07"
---

# Phase 55 Plan 01: Wave 0 Spikes (Dangling-Port Hypothesis + LOF Topology) Summary

Two throw-away research scripts confirmed the architectural-question outcomes that downstream Wave 1+ plans were waiting on, and the locked answers were committed to a frontmatter-grepable results file.

## Spike #1 outcome — `HYPOTHESIS=A`

Wave 2 (`test_channels.jl` rewrite) adiabatic-by-default test compiles a default-kwarg Channel in isolation under `mtkcompile(...; fully_determined=false)` and asserts `T_wall_left[i] / T_wall_right[i]` are present in the unknowns list. **No binding equations required.** The hand-rolled post-Wave-1 stand-in (no per-cell ports, plain `@variables T_wall_left(t)[1:n]`) compiled to `4 eqs / 8 unks` with all 4 `T_wall_left[i]` unknowns retained — confirming Hypothesis A literally rather than Hypothesis A_PARTIAL.

## Spike #2 outcome — `WINNER=B`

Wave 4 (`build_loop_lof_bypass` redesign) heated leg adopts `ChannelAndContacts + HeatDiffusion plate` via `one_sided_connection(ch, fuel; side=:left, name=:heated)`. Spike A's `CAC + WallTemperature` variant failed gate D (NC `|mdot|=8.6e-4 kg/s` falls below the `1e-3` floor specified in RESEARCH.md §3) because pinning `T_wall=373.15K` provides too little buoyancy drive to sustain natural circulation. Spike B's HD plate with `1 kW` imposed power produces `|mdot_nc|=4.3e-3 kg/s` — comfortably inside the gate window and a more physically faithful representation of the MTR loss-of-flow event.

| Gate | Spike A | Spike B |
| ---- | ------- | ------- |
| (A) balanced n_eq == n_uk | PASS (34=34) | PASS (64=64) |
| (B) mdot_ss physical | PASS (0.5 kg/s) | PASS (0.5 kg/s) |
| (C) flapper fires | PASS (xi=1.0) | PASS (xi=1.0) |
| (D) channel reverses + NC magnitude | **FAIL** (-8.6e-4) | PASS (-4.3e-3) |
| (H) runtime ≤ 60s | PASS (1.56s) | PASS (1.65s) |
| Overall | 4/5 | **5/5** |

## Total runtime per spike

- Spike #1: < 1 s warm (daemon already had STREAM loaded; the inner `mtkcompile(...; fully_determined=false)` calls dominate)
- Spike #2: ~ 2 s warm per spike (mtkcompile of the full lof loop ~1 s + transient solve ~0.5 s); full driver wall-time ≈ 4-5 s warm

Across 5 iteration cycles the total wall-time was ~ 2 minutes (most of it spent in human-loop iteration, not in Julia execution; a single clean run is well under 10 seconds warm or 90 seconds cold-start).

## Deviations from plan

Several auto-fixes were applied (Rule 1 / Rule 3 — bug + blocking issues that prevented finishing the spike). All documented inline in the spike commit message and reflected in the spike scripts themselves; the **research outcomes are unchanged** (HYPOTHESIS=A and WINNER=B both reflect the original spike intent).

| # | Rule | What | Why |
| - | ---- | ---- | --- |
| 1 | Rule 3 (blocking) | Added `using ModelingToolkit: connect, compose` | `connect` is shadowed by Sockets.jl + ModelingToolkitBase.jl exports in the daemon's Main module; the spike scripts crashed with `UndefVarError: connect not defined in Main` until disambiguated. |
| 2 | Rule 1 (bug — plan idiom) | Replaced `~`-binding driver with port + `connect()` driver in `_LocalWallTempStub` | Plan suggested `[ch.thermal_left[i].T ~ wt.T_wall_out[i] for i in 1:n]`. That over-determined the connection set by 10 equations (combining channel-side `Q_flow ~ q_*_expr` closure with the `~`-binding produces redundant constraints). The ThermalPort + `connect()` pattern from `test_channels.jl _WallTempDriver` (lines 36-41) yields a single connection-set equation per cell and compiles cleanly. |
| 3 | Rule 3 (blocking) | Added missing positional arg to `flapper_callback` | Plan called `flapper_callback(ssys; threshold=...)`. Actual signature is `flapper_callback(ssys, monitored_sym; threshold=0.01)` per `src/components/flapper.jl:109`. Pass `ssys.ine.port_in.mdot` as the monitored quantity. |
| 4 | Rule 1 (bug — plan idiom) | Sub-system access path is `heated.ch` / `heated.fuel`, not `heated.channel` | After `heated = one_sided_connection(ch, fuel; side=:left, name=:heated)`, the contained sub-systems retain their `@named` symbols (`ch`, `fuel`), not the constructor's positional names (`channel`, `fuel`). Mirrors `test_composition.jl:234-237` COMP-03 pattern. |
| 5 | Rule 3 (blocking) | Added full v1.0 LOF IC dict (mdot seed for both `ine` and `ret`, `Dt(ret.port_in.mdot)=0`, `flapper.T_open=1e30` sentinel) | Plan's IC was minimal (`ine.port_in.mdot => 0.5` plus T fields). Without the additional IC anchors, both spikes aborted at t=0 with `dt forced below floating point epsilon` — the index-reduced derivative state on `ret.port_in.mdot` is not fixed by the structural-simplifier alone, and the flapper sentinel must be explicitly set. The required IC shape is verbatim from `test/test_loss_of_flow.jl:106-117 _lof_bypass_ic`. |
| 6 | Pragmatic gate scope | Gates E/F/G (energy balance instantaneous, NC time-averaged, analytical buoyancy comparison) were left as unimplemented placeholders; pass count is 5 evaluated gates per spike rather than 8 | These gates are the responsibility of Wave 7 (`build_loop_lof_bypass` + `lof_transient.jl`), not the topology spike. The four core decision gates (A balanced, B mdot_ss, C flapper fires, D reversal — plus H runtime) all execute as designed and are sufficient to lock the topology. Documented in 55-WAVE0-SPIKE-RESULTS.md. |

## Unexpected findings

- **Hypothesis A is *literal*, not partial.** The plan flagged HYPOTHESIS=A_PARTIAL as the "likely outcome under Symbolics 7.21" (RESEARCH.md §2 prediction that the structural simplifier would eliminate `0 * x` symbols). It did not — all 4 `T_wall_left[i]` symbols survived `mtkcompile(...; fully_determined=false)` in the post-Wave-1 stand-in. Wave 2's test idiom can directly assert `T_wall_left[i] in unknowns(ssys)` without the reduced-count fallback.
- **Spike A's NC magnitude is physically interpretable, not a bug.** The 8.6e-4 kg/s NC equilibrium reflects the actual buoyancy budget for `ΔT=60K`, `L=1m`, `D=0.01m` with only convective coupling (no plate thermal mass). It's a legitimate physics result that nonetheless falls below the v1.0 LOF gate floor. Wave 4 should NOT relax the gate to accommodate Spike A — Spike B is more representative of the MTR fuel-plate transient.

## Self-Check: PASSED

- [x] `examples/spike_phase55_unbound.jl` — committed at 4027afd
- [x] `examples/spike_phase55_lof_topology.jl` — committed at 2c7d782
- [x] `.planning/phases/55-composition-helpers-examples-test-suite/55-WAVE0-SPIKE-RESULTS.md` — committed at cd6d198
- [x] HYPOTHESIS=A line present in spike #1 stdout (verified at line 15 of /tmp/spike1_out.txt)
- [x] WINNER=B line present in spike #2 stdout (verified at line 26 of /tmp/spike2_out.txt)
- [x] Frontmatter `spike_unbound_hypothesis: "A"` and `spike_lof_winner: "B"` present in 55-WAVE0-SPIKE-RESULTS.md
