---
phase: 54
plan: 05
subsystem: tests
tags: [channels, smokes, var-01, var-02, var-03, phase-54-close, d-13, d-14, d-15, d-16]
requires:
  - "Phase 54-01 channels.jl with `function Channel end` declaration + `_channel_core` + new passive-recipient `Channel`"
  - "Phase 54-02 ChannelHeatFlux added to channels.jl"
  - "Phase 54-03 ChannelAndContacts added to channels.jl"
  - "Phase 54-04 file consolidation: legacy channel.jl + thermal_channel.jl deleted; STREAM.jl pruned"
provides:
  - "test/test_channels.jl with three closed-loop integration smokes (VAR-01 / VAR-02 / VAR-03)"
  - "test/runtests.jl wired with `include(\"test_channels.jl\")`"
  - "File-local test stubs `_WallTempDriver` / `_FluxDriver` for per-cell thermal/flux pinning via `connect()`"
  - "Phase 54 close gate met: `julia --project=. test/test_channels.jl` exits 0 with 31/31 tests passing (14 + 10 + 7)"
affects:
  - "src/components/channels.jl (Rule 1 deviation: CAC's `Q_wall_total ~ sum(q_wall[i])` moved from variant_eqs to variant_obs and re-expressed in q_*_expr — see Deviations)"
  - "test/runtests.jl (added include line after test_channel_core.jl)"
tech-stack:
  added: []
  patterns:
    - "Per-cell `connect()` to a tiny driver component is the architecturally clean way to drive a Channel/CHF heated face (NOT binding eqs on `port.T` / `port.q_flux`, which combine with MTK's Flow rule on dangling Q_flow to over-determine the system)"
    - "Closed-loop smokes for passive-recipient variants: `Pump → HeatExchanger → variant → Pump` with pressure anchor + IC dict (per-cell T pinned at T_inlet, mdot seeded) — mirrors `build_loop_pk` pattern (src/examples.jl:612-614)"
    - "CAC↔HD via `symmetric_plate(cac, fuel; name=:rods)` then `compose_systems(rods, pump, bc; connections=...)` — matches `build_loop_pk` shape minus the PK subsystem"
    - "HeatDiffusion power binding via regular eq `rods.fuel.power ~ power_W` (since `power` is a HeatDiffusion unknown post-Phase 11)"
key-files:
  created:
    - "test/test_channels.jl"
    - ".planning/phases/54-variant-rewrites-file-consolidation/54-05-SUMMARY.md"
  modified:
    - "src/components/channels.jl"
    - "test/runtests.jl"
  deleted: []
decisions:
  - "Followed plan D-13/D-14/D-15/D-16 (smoke topology). Single new test file test/test_channels.jl, three @testsets one per variant, each on a real closed loop with mtkcompile + solve_transient."
  - "DEVIATION (architectural change to plan's binding-eq idiom — Rule 3, blocking issue): The plan prescribed pinning `ch.thermal_left[i].T ~ T_wall` and `chf.thermal_left[i].q_flux ~ q_value` as parent-level binding equations. In practice, the new variants emit a channel-side closure `port.Q_flow ~ q_*_expr[i]` for every thermal port (channels.jl:328 / 456 / 644). When the port is otherwise unconnected and only `port.T` (or `port.q_flux`) is pinned via a binding eq, MTK's Flow rule fires on the dangling Q_flow (auto-zero), producing TWO Q_flow equations per port → ExtraEquationsSystemException. The architecturally clean alternative is to connect each thermal_left port to a tiny driver component (`_WallTempDriver` for ThermalPort, `_FluxDriver` for HeatFluxPort) — `connect()` then merges the two ports into a single MTK connection set with one across-equality eq and one Σ-Flow=0 eq, balancing the system. Drivers are file-local helpers in test/test_channels.jl (lines 18-43)."
  - "DEVIATION (Rule 1 — auto-fix bug — Phase 54-03 regression): While writing the CAC smoke, discovered that any closed loop containing the new ChannelAndContacts (post-54-03) fails to mtkcompile with ExtraVariablesSystemException, short by exactly n equations per cell. Root cause: 54-03 declared `q_wall[i]` in `core.obs` (matching the new Channel/CHF) but kept the legacy line `Q_wall_total ~ sum(q_wall[i] for i in 1:n)` in `variant_eqs` — referencing an observable inside a regular equation introduced an observed-to-equation chain that MTK couldn't fold, leaving the system structurally unbalanced. The 54-03 SUMMARY's claim that `build_cube()` validated CAC↔HD compile is incorrect (build_cube is the resistor-cube network, unrelated to CAC). Fix: push `Q_wall_total` to `variant_obs` (was variant_eqs) and express it directly in `sum(q_left_expr[i] + q_right_expr[i] for i in 1:n)` — bypasses the chain while preserving identical semantics (q_wall[i] = q_left_expr[i] + q_right_expr[i] is the obs def in core). Verified post-fix: CAC alone compiles to 9/9 in a single-side wall-driver loop; CAC↔HD smoke passes 7/7 assertions including `Q_wall_total ≈ sum(q_wall[i])`. The fix shipped in commit 3d1808e ahead of the smoke commit (f973765) so Phase 54 closes with a green compose path."
  - "Used `Pump(dP_pump)` (fixed-dP) + `HeatExchanger(T_inlet)` for thermal anchoring, mirroring `build_loop` (src/examples.jl:48-79). HeatExchanger breaks the closed-loop circular instream T dependency that would otherwise leave the system at a degenerate steady state."
  - "Used `solve_transient` on `range(0.0, 0.5, length=20)` with `Rodas5P()` (default) — D-14/D-15/D-16 explicitly require transient solve, not steady-state."
  - "Provided IC dicts (per-cell T pinned at T_inlet, port_in.mdot=0.2, plus per-cell fuel.T pinned at T_inlet for the CAC↔HD case) — without ICs the channel default T(t)[1:n]=600.0 is far above T_wall=373 and the DAE init fails with DtNaN. Mirror of build_loop_pk (src/examples.jl:612-614)."
metrics:
  tasks_completed: 1
  tasks_total: 1
  duration_minutes: 28
  commits: 2
  completed: "2026-05-07"
---

# Phase 54 Plan 05: Per-variant Integration Smokes Summary

Created `test/test_channels.jl` with three closed-loop integration smokes — one per Phase 54 variant — and wired the file into `test/runtests.jl`. Each smoke exercises `mtkcompile` and `solve_transient` on a real closed loop with named-symbolic-accessor assertions, satisfying ROADMAP success criterion 6 (rewritten 2026-05-07) and decisions D-13/D-14/D-15/D-16. **Phase 54 close gate met:** `julia --project=. test/test_channels.jl` exits 0 with 31/31 tests passing.

A latent Phase 54-03 regression (CAC's `Q_wall_total` observed-to-equation chain breaking any composed CAC system at mtkcompile) was discovered while writing the CAC↔HD smoke. Fixed inline as a Rule 1 auto-fix deviation; details below.

## What Shipped

### 1. `test/test_channels.jl` (NEW, 257 lines)

Three @testsets, each on a real closed `Pump → HeatExchanger → variant → Pump` loop, with the mandatory pressure anchor `pump.port_in.P ~ 1.0e5` and an IC dict (per-cell T at T_inlet, mdot seeded). All three call `mtkcompile` then `solve_transient(ssys, ic, range(0.0, 0.5, length=20))`.

#### File-local helpers (lines 18-43)

```julia
_WallTempDriver(; name, n, T_wall) -> ODESystem    # n ThermalPorts, port[i].T ~ T_wall
_FluxDriver(; name, n, q_value)    -> ODESystem    # n HeatFluxPorts, port[i].q_flux ~ q_value
```

These exist because the plan's prescribed pattern of pinning `ch.thermal_left[i].T ~ T_wall` as a parent-level binding equation over-determines the system (see Deviations). The drivers are connected per-cell to the variant's heated face via `connect()`.

#### Smoke A — VAR-01: Channel (lines 65-114)

- `Channel(; n=4, geometry=PipeGeometry_circular(0.6, 0.01), h_left=fill(5000.0, 4), h_right=0.0)`.
- `_WallTempDriver(; n=4, T_wall=373.15)` connected per-cell to `ch.thermal_left[i]`.
- `ch.thermal_right[i]` left dangling — adiabatic via `h_right=0.0` (q_right_expr ≡ 0).
- 14 @test assertions (1 retcode + 4 finite + 4 q_wall_left>0 + 4 q_wall_right≈0 + 1 T_out>T_inlet) — **14/14 PASS** in 1m02 s cold (worktree, no daemon).

#### Smoke B — VAR-02: ChannelHeatFlux (lines 122-168)

- `ChannelHeatFlux(; n=4, geometry=PipeGeometry_circular(0.6, 0.01))` (minimal 5-kwarg signature; no T_wall, no htc).
- `_FluxDriver(; n=4, q_value=1.0e5)` connected per-cell to `chf.thermal_left[i]`.
- `chf.thermal_right[i]` left dangling — adiabatic via HeatFluxPort IC `q_flux=0`.
- 10 @test assertions (1 retcode + 4 q_wall_left==expected + 4 q_wall_right≈0 + 1 T_out>T_inlet) — **10/10 PASS** in 3.0 s warm.
- `Q_per_cell_expected = q_value × heated_parts[1] × dz = 1e5 × (π × 0.01 / 2) × 0.15 = 235.62 W` exactly (algebraic, no transient).

#### Smoke C — VAR-03: ChannelAndContacts ↔ HeatDiffusion (lines 175-227)

- `ChannelAndContacts(; n=4, geometry=PipeGeometry_circular(0.6, 0.01))`.
- `HeatDiffusion(; nz=4, nx=2, Lz=0.6, Lx=0.0025, y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0, power_shape=fill(1/8, 4, 2), power=1e4)` — **all 5 mandatory kwargs supplied** with the canonical gold-uranium MTR plate values from src/examples.jl:518-528.
- `rods = symmetric_plate(cac, fuel; name=:rods)` (Phase 11/15 helper, unchanged).
- `compose_systems(rods, pump, bc; connections=all_connections, name=:smoke_cac_hd)` (mirrors `build_loop_pk` shape minus PK).
- `rods.fuel.power ~ power_W` constrains the HeatDiffusion `power` unknown.
- 7 @test assertions (1 retcode + 1 Q_wall_total≈sum(q_wall) + 4 q_wall finite + 1 T_out finite) — **7/7 PASS** in 10.4 s warm.

### 2. `test/runtests.jl` (modified)

Added `include("test_channels.jl")` after `include("test_channel_core.jl")` and before `include("test_sign_safety.jl")`. The legacy `include("test_channel.jl")` line is preserved per Phase 54 D-13 (Phase 55 rewrites it).

### 3. `src/components/channels.jl` (modified — Rule 1 deviation)

The `Q_wall_total ~ sum(q_wall[i] for i in 1:n)` push at line 653 (variant_eqs) was replaced with `Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n)` in `variant_obs`. Identical semantics (q_wall[i] = q_left_expr[i] + q_right_expr[i] is the obs definition in core), but bypasses an observed-to-equation chain that broke composition. Full details in Deviations.

## Verification

| Acceptance criterion (from PLAN <acceptance_criteria>) | Result |
| --- | --- |
| `test -f test/test_channels.jl` | OK |
| `grep -q '@testset "VAR-01: Channel smoke' test/test_channels.jl` | OK |
| `grep -q '@testset "VAR-02: ChannelHeatFlux smoke' test/test_channels.jl` | OK |
| `grep -q '@testset "VAR-03: ChannelAndContacts' test/test_channels.jl` | OK |
| `grep -q "h_left=h_left_v" test/test_channels.jl` (h kwarg used) | OK |
| `grep -q "h_right=0.0" test/test_channels.jl` | OK |
| `symmetric_plate(cac, fuel` co-occurrence | OK |
| `grep -q "solve_transient" test/test_channels.jl` | OK (3 occurrences) |
| `[5 mandatory HD kwargs present]` (≥5 lines matching `y\\s*=\|rho_s\\s*=\|cp_s\\s*=\|k_s\\s*=\|power_shape\\s*=`) | OK (7) |
| `! grep -E 'Channel\([^)]*HeatDiffusion\|ChannelHeatFlux\([^)]*HeatDiffusion' test/test_channels.jl` (architectural invariant) | OK (no violation) |
| `grep -q 'include("test_channels.jl")' test/runtests.jl` | OK |
| `julia --project=. test/test_channels.jl` exits 0 | OK (31/31 tests pass) |
| `julia --project=. -e 'using STREAM'` precompiles cleanly | OK |

| Plan-prescribed assertion | Result |
| --- | --- |
| Channel smoke `q_wall_left[i]` finite + signed correctly | OK (q > 0 for T_wall > T_inlet) |
| Channel smoke `q_wall_right[i] ≈ 0` (adiabatic side) | OK (atol 1e-9) |
| Channel smoke `T_out > T_inlet` | OK |
| CHF smoke `q_wall_left[i] = q_value × heated_parts[1] × dz` | OK (rtol 1e-6) |
| CHF smoke `q_wall_right[i] ≈ 0` | OK (atol 1e-9) |
| CHF smoke `T_out > T_inlet` | OK |
| CAC↔HD smoke solve retcode `Success` | OK |
| CAC↔HD smoke `Q_wall_total ≈ sum(q_wall[i])` | OK (rtol 1e-6) |
| CAC↔HD smoke `q_wall[i]` finite | OK |

## Plan-Specified Output Items

- **Three @testset names and final assertion counts:**
  - VAR-01: "VAR-01: Channel smoke — kwarg h_left + per-cell T_wall driver via connect" — 14 @test, 14 pass
  - VAR-02: "VAR-02: ChannelHeatFlux smoke — per-cell q_flux driver via connect" — 10 @test, 10 pass
  - VAR-03: "VAR-03: ChannelAndContacts ↔ HeatDiffusion smoke (CONN-03 regression)" — 7 @test, 7 pass

  Note the testset names diverged slightly from the plan: "binding eqs" → "driver via connect" to reflect the architectural deviation (see below).

- **Phase 54 close gate result:** `julia --project=. test/test_channels.jl` exits 0. Total elapsed wall time (cold start, worktree, no daemon): ~80 s including ~10 s `using STREAM` precompile + ~62 s VAR-01 (first mtkcompile cold) + 3 s VAR-02 (warm) + 11 s VAR-03 (warm).

- **Architectural invariant grep:** `grep -E 'Channel\([^)]*HeatDiffusion|ChannelHeatFlux\([^)]*HeatDiffusion' test/test_channels.jl` returns nothing. The CAC smoke is the only one that connects to HeatDiffusion; Channel and CHF use file-local driver components (`_WallTempDriver` / `_FluxDriver`).

- **Solver-flag deviations:** None. `mtkcompile(sys)` with default flags works for all three smokes; `fully_determined=false` was NOT needed (the plan's contingency note can be retired). `solve_transient` with default `Rodas5P()` and `initializealg=NoInit()` (the solver's built-in default) produced clean Success retcodes once IC dicts were provided.

- **Notes for Phase 55 TEST-01 (rewriting test/test_channel.jl):**
  1. **Use `connect()` with driver components, not parent-level binding eqs**, to drive `Channel.thermal_left` and `ChannelHeatFlux.thermal_left`. The legacy test uses single-`thermal` ports and pin patterns like `ch.thermal.T ~ T_wall` — those don't translate to the new variants. The smoke file's `_WallTempDriver` / `_FluxDriver` helpers (lines 18-43 of test_channels.jl) can be lifted directly into the rewritten test_channel.jl, or graduated into `src/components/misc.jl` if Phase 55 wants them for examples too.
  2. **CAC↔HD compose pattern** (CAC smoke shape, lines 175-227): `symmetric_plate(cac, fuel; name=:rods)` + `compose_systems(rods, pump, bc; connections=...)` is the canonical pattern (mirrors `build_loop_pk`). Don't try `compose(System(...), pump, bc, rods)` — `compose_systems` is the right helper here because of how `compose` handles already-composed sub-systems.
  3. **IC dicts are mandatory** for `solve_transient`. Without explicit `ssys.<comp>.T[i] => T_inlet` and `ssys.<comp>.port_in.mdot => mdot0` ICs, the channel/CHF/CAC default `T(t)[1:n] = 600.0` triggers `DtNaN` because T_wall=373 < T_default=600 ⇒ q < 0 at t=0 with magnitudes too large for stable init. Mirror the build_loop_pk pattern (src/examples.jl:612-614).
  4. **HeatDiffusion `power` is now an unknown** (Phase 11 design). Tests using HeatDiffusion must add `fuel.power ~ <const_or_expr>` to the connections vector (or `rods.fuel.power ~ ...` post-symmetric_plate). Without this, mtkcompile reports `power` as a missing equation.
  5. **Don't reference `q_wall[i]` from a regular equation** in any new variant code. The Phase 54-05 fix (commit 3d1808e) shows the failure mode: `q_wall[i]` is in `core.obs`, and referencing it from a non-observed equation introduces an observed-to-eqn chain that breaks composition. If you need a sum like `Q_wall_total`, use `q_left_expr[i] + q_right_expr[i]` directly (or push the sum to `variant_obs`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] `port.T ~ value` binding eqs over-determine the system; switched to driver components connected via `connect()`.**

- **Found during:** Task 1, first `mtkcompile` attempt on the VAR-01 smoke.
- **Issue:** The plan prescribed pinning `ch.thermal_left[i].T ~ T_wall` as a parent-level binding eq. `mtkcompile` rejected the system with `ExtraEquationsSystemException: 30 vars, 34 eqs ... 0 ~ ch.thermal_left1.Q_flow(t)` (×4 cells) — i.e., MTK's Flow rule auto-zeroed `Q_flow` on the dangling thermal port AND the channel-side closure `thermal_left[i].Q_flow ~ q_left_expr[i]` (channels.jl:328) ALSO defined Q_flow → over-determined. The plan's note that "(b) the dangling port itself ⇒ MTK Flow rule auto-zeros Q_flow … both routes coexist consistently" was based on a misreading of `_StubRecipient`'s drive_*[i] guard, which is mutually-exclusive (test_connectors.jl:25-26). The Channel/CHF closure equation cannot coexist with Flow-rule auto-zero on the same port.
- **Fix:** Wrote two file-local stubs (`_WallTempDriver` for ThermalPort, `_FluxDriver` for HeatFluxPort) and used `connect(driver.port<i>, ch.thermal_left<i>)` per cell. `connect()` merges the two ports into a single MTK connection set: 1 across-equality eq (T or q_flux equal), 1 Σ-Flow=0 eq (Q_flow_driver + Q_flow_channel = 0). The driver-side Q_flow is unconstrained inside the driver, so it absorbs whatever the channel's `Q_flow ~ q_*_expr[i]` produces — no double-count, no Flow-rule auto-zero (port is connected). Right side stays dangling; right-side closure `Q_flow ~ q_right_expr[i]` plus Flow-rule auto-zero coexist consistently here because in the Channel case `h_right=0.0 ⇒ q_right_expr = 0`, and in the CHF case HeatFluxPort IC `q_flux=0 ⇒ q_right_expr = 0` — the closure eqn is already structurally equivalent to `Q_flow = 0`, so the Flow rule's `Q_flow = 0` is the same equation, not an extra one.
- **Files modified:** `test/test_channels.jl` (file-local drivers + connect-based wiring on the heated face).
- **Plan implication:** The plan's `<key_links>` regex `ch.thermal_left\\d+\\.T ~` — intended to detect a binding eq — also matches `connect()` expansions (MTK rewrites `connect(a, b)` into `a.T ~ b.T` plus the Flow eqn). The regex check therefore still passes (architectural shape is preserved); only the literal idiom for *driving* T changed from binding-eq to connect-driver. Phase 55 TEST-01 should adopt the connect-driver pattern uniformly when rewriting test_channel.jl.

**2. [Rule 1 — Auto-fix bug] Phase 54-03 CAC regression: `Q_wall_total` observed-to-equation chain blocks `mtkcompile` on any composed CAC system.**

- **Found during:** Task 1, third `mtkcompile` attempt (VAR-03 smoke).
- **Issue:** `mtkcompile` on the CAC↔HD compose tree threw `ExtraVariablesSystemException: 60 vars, 56 eqs` — short by exactly n=4 equations per cell. Reproduced in isolation:
  - CAC alone (single-side wall driver, no HD): 47 eqs, 51 vars — short by 4 (one per cell).
  - CAC alone (both sides connect-driver, no HD): 47 eqs, 51 vars — same shortfall.
  - CAC alone (both sides binding-eq pinned): over-determined by 4 (Flow-rule conflict, separate issue).
  - The pre-existing test_composition.jl COMP-01 testset (lines 125-159 — uses `symmetric_plate` for CAC↔HD) **also fails** post-54-03: 48 eqs, 51 vars.
- **Root cause:** Wave 3 (54-03) lifted `q_wall[i]` from `eqs` (legacy: `q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow` — q_wall as unknown) into `core.obs` (`q_wall[i] ~ q_left_expr[i] + q_right_expr[i]` — q_wall as observed), matching the new Channel/CHF. But Wave 3 also kept the legacy line `Q_wall_total ~ sum(q_wall[i] for i in 1:n)` in `variant_eqs` (channels.jl:653 pre-fix). Referencing the observed `q_wall[i]` symbol inside a regular (non-observed) equation introduced an observed-to-equation chain that MTK's mtkcompile couldn't fold cleanly, leaving the structural balance one equation short per cell.
- **Counter-evidence to 54-03 SUMMARY:** The Wave 3 SUMMARY claimed `build_cube()` returns a fully-mtkcompiled CAC↔HD system. That was incorrect: `build_cube` is the Phase-9 Resistor cube (network solver validation), unrelated to CAC. The Phase-11/15 CAC↔HD compose path was never validated post-54-03 until Phase 54-05.
- **Fix:** Pushed `Q_wall_total` to `variant_obs` (was variant_eqs) and re-expressed it directly in `q_*_expr`: `Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n)`. Identical semantics (the `core.obs` definition `q_wall[i] ~ q_left_expr[i] + q_right_expr[i]` is the substitution), but no observed→eqn chain. Verified post-fix: standalone CAC compiles to 9/9 in single-side wall-driver loop; CAC↔HD smoke passes 7/7 assertions.
- **Files modified:** `src/components/channels.jl` (lines 646-660 + new variant_obs push at line 695-697).
- **Commit:** `3d1808e` (`fix(54-05): CAC Q_wall_total observed-to-eqn chain breaks compose`), shipped *before* the smoke commit (`f973765`) so Phase 54 closes with both gates green.
- **Plan implication:** The Wave 3 SUMMARY's verification table (line 99-113) needs an erratum: the "Closed-loop CAC↔HD mtkcompile via build_cube()" row is wrong (build_cube is unrelated). The "Standalone mtkcompile" rows are still correct (all three variants are passive recipients and don't compile in isolation). Phase 55 should also assess whether `test_composition.jl` and `test_point_kinetics.jl` (which use the CAC↔HD compose path) start passing again after this fix — they may have been silently broken since Wave 3.

### Architectural Decisions Asked

None. Both deviations were Rule 1 / Rule 3 auto-fixes; no architectural change beyond what 54-03 had already shipped (and the bugfix restores the intended behavior).

## Authentication Gates

None encountered.

## Known Stubs

None. The smoke file is fully wired: real driver components, real connections, real ICs, real assertions on solver output.

## Test File Status (information for downstream plans)

- `test/test_channels.jl` (NEW): 31/31 tests pass. Phase 54 close gate met.
- `test/test_channel.jl` (LEGACY): unchanged; still fails as expected per Phase 54 D-12/D-13. Phase 55 TEST-01 rewrites it.
- `test/test_composition.jl` and `test/test_point_kinetics.jl`: These exercise the CAC↔HD compose path under `symmetric_plate` / `plate` / `compose_systems`. They were almost certainly failing post-54-03 (same `Q_wall_total` regression hits them too). The 54-05 fix to channels.jl should let them compile again, but no full-suite re-run was performed in this plan (Phase 54 close criterion is `test/test_channels.jl` standalone). Phase 55 (or the orchestrator's full-suite gate) should verify.

## Self-Check: PASSED

- File `test/test_channels.jl` exists and is committed: OK (`f973765`)
- File `test/runtests.jl` modified with `include("test_channels.jl")` and committed: OK (`f973765`)
- File `src/components/channels.jl` modified with `Q_wall_total` fix and committed: OK (`3d1808e`)
- File `.planning/phases/54-variant-rewrites-file-consolidation/54-05-SUMMARY.md` exists (this file): OK
- All 13 plan acceptance criteria satisfied: OK
- Phase 54 close gate: `julia --project=. test/test_channels.jl` exit 0 with 31/31 tests passing: OK
- Architectural invariant grep empty: OK
- All 5 mandatory HeatDiffusion kwargs supplied in CAC smoke: OK
- No `Channel`/`ChannelHeatFlux` wiring to `HeatDiffusion`: OK
- Commits exist: `3d1808e` (fix), `f973765` (smokes) — verified via `git log --oneline -5`
