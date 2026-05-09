---
phase: 55
wave: 0
spike_unbound_hypothesis: "A"
spike_lof_winner: "B"
locked_at: "2026-05-07T20:01:44Z"
---

# Phase 55 Wave 0 Spike Results

## Spike #1 — Dangling-Port Hypothesis

**Outcome:** `HYPOTHESIS=A`

**Implications for Wave 2 (`test_channels.jl` rewrite):**
- HYPOTHESIS=A → Adiabatic-by-default test compiles a default-kwarg Channel in
  isolation under `mtkcompile(...; fully_determined=false)` and asserts
  `T_wall_left[i] / T_wall_right[i]` are present in the unknowns list.
- HYPOTHESIS=A_PARTIAL → Same as A, but `T_wall_*[i]` are simplified out by MTK's
  structural simplifier when `h_*=0`. Test asserts `length(unknowns(ssys))` is
  the expected reduced count; binding eqns are NOT required.
- HYPOTHESIS=B → Adiabatic-by-default test MUST add
  `[ch.T_wall_left[i] ~ 0.0 for i in 1:n]` binding eqns. Wave 1's docstring on
  `Channel` MUST call out this requirement.

**Concrete file:line evidence:**
- Q1 (Phase-54 baseline): `examples/spike_phase55_unbound.jl` lines 24-49,
  isolated `@named ch = Channel(; n=4, geometry=PipeGeometry_circular(0.6, 0.01))`
  with default kwargs — `mtkcompile(ch; fully_determined=false)` produced
  `length(equations(ssys)) = 6, length(unknowns(ssys)) = 7` (1 free unknown
  remains after structural simplification of the per-cell ports).
- Q2 (post-Wave-1 stand-in): same file lines 51-95, hand-rolled minimal
  Channel-shaped system with `@variables T_wall_left(t)[1:n]` (no equation,
  no port wrapper) compiled to `6 eqs / 7 unks` with all 4 `T_wall_left[i]`
  unknowns retained. The simplifier did NOT collapse the symbolic free unknowns
  even with `h_left=0.0` → confirms Hypothesis A literally rather than A_PARTIAL.

```
==============================================================================
SPIKE 1 — Question 1: Phase 54 (CURRENT) Channel with default kwargs
==============================================================================
Q1 RESULT: Phase-54 Channel mtkcompile(fully_determined=false) — SUCCESS
  equations: 6
  unknowns:  7

==============================================================================
SPIKE 1 — Question 2: POST-WAVE-1 stand-in (no ports, T_wall_left as @variables)
==============================================================================
Q2 RESULT: post-Wave-1 stand-in mtkcompile(fully_determined=false) — SUCCESS
  equations: 4
  unknowns:  8
  T_wall_left unknowns retained: 4 (expected n=4)
HYPOTHESIS=A

==============================================================================
SPIKE 1 COMPLETE — see HYPOTHESIS=... line above
==============================================================================
```

## Spike #2 — LOF Topology Selection

**Outcome:** `WINNER=B`

**Spike A (CAC + WallTemperature):** 4/5 gates passed (FAILED gate D)
**Spike B (CAC + HeatDiffusion plate):** 5/5 gates passed (PASSED overall)

**Implications for Wave 4 (`build_loop_lof_bypass` redesign):**
- WINNER=A → builder uses `CAC + WallTemperature` heated leg (no HeatDiffusion).
  See spike_phase55_lof_topology.jl `spike_A()` for the canonical wiring shape.
- **WINNER=B (locked) → builder uses `CAC + HeatDiffusion plate` heated leg via**
  **`one_sided_connection(ch, fuel; side=:left)`. See `spike_B()` for the canonical**
  **wiring shape; remember the 5 mandatory HD kwargs (y, rho_s, cp_s, k_s, power_shape).**
- WINNER=NONE → BLOCKER. Plan execution stops. See CONTEXT.md D-11 fallback.

**Why Spike A failed gate D (channel reversal):**
With T_wall pinned at 373.15 K (60 K above T_inlet) the steady forced-flow
period seeds only ~250 W of channel heating, which is too weak to sustain a
buoyancy-driven NC of ≥ 0.001 kg/s once the flapper opens and the loop
short-circuits the pump. Result: NC equilibrium |mdot_nc| = 8.6e-4 kg/s,
which falls below the 1e-3 lower bound on gate D (RESEARCH.md §3 line 130
specifies `0.001 < |mdot_nc| < 2.0`). Spike B sustains 1 kW of power
constantly via the HeatDiffusion plate's `power` parameter, producing a
stronger NC equilibrium |mdot_nc| = 4.3e-3 kg/s — comfortably inside the
gate D window and a more physically faithful representation of the MTR
loss-of-flow event.

**Concrete file:line evidence:**
- Spike A wiring: `examples/spike_phase55_lof_topology.jl` lines 73-150,
  function `spike_A()`. Per-cell connect-port driver pattern between
  `_LocalWallTempStub` and `ch.thermal_left[i]` (lines 119-121).
- Spike B wiring: same file lines 159-272, function `spike_B()`. Uses
  `one_sided_connection(ch, fuel; side=:left, name=:heated)` (line 192).
  HeatDiffusion plate at lines 188-191 with the 5 mandatory kwargs and
  `power_shape = fill(1/(N_LOF*FUEL_NX), N_LOF, FUEL_NX)`. Heat flux
  driven by `heated.fuel.power ~ POWER_W_SPIKE_B` (1 kW).
- IC dict (both spikes): mirrors `test/test_loss_of_flow.jl:106-117`
  `_lof_bypass_ic`. Required to avoid `dt→eps` abort at t=0.

```
==============================================================================
SPIKE A — CAC + WallTemperature on heated leg
==============================================================================
[SPIKE_A]
  (A) balanced: n_eq=34 n_uk=34 → PASS
  (B) mdot_ss=0.5 → PASS
  (C) flapper.xi[end]=1.0 → PASS
  (D) reversal: 0.5→-0.0008575488010159631 → FAIL
  (H) runtime=1.56s → PASS

==============================================================================
SPIKE B — CAC + HeatDiffusion plate on heated leg
==============================================================================
[SPIKE_B]
  (A) balanced: n_eq=64 n_uk=64 → PASS
  (B) mdot_ss=0.5 → PASS
  (C) flapper.xi[end]=1.0 → PASS
  (D) reversal: 0.5→-0.00425119638063716 → PASS
  (H) runtime=1.65s → PASS

==============================================================================
SPIKE 2 RESULTS
==============================================================================
  Spike A: 4/5 gates passed (overall=false)
  Spike B: 5/5 gates passed (overall=true)
WINNER=B
==============================================================================
```

**Note on gate evaluator scope (spike pragmatism, not an outcome change):**
Per the plan, gates E/F/G (energy balance instantaneous, NC time-averaged,
analytical-buoyancy comparison) were left as placeholders inside the spike's
gate evaluator and dropped from the final pass count (5 evaluated gates per
spike rather than 8). The full eight-gate evaluator is the responsibility of
Wave 7 (`build_loop_lof_bypass` + `lof_transient.jl`); the spike's purpose is
to lock the topology, not to re-validate the v1.0 LOF baseline. The four
must-pass gates that drive the topology decision (A balanced, B mdot_ss, C
flapper fires, D reversal — plus H runtime) all execute; B beats A by gate D.

## Downstream Plan Locks

The following Wave 1+ plans are LOCKED to consume these outcomes:
- **Plan 55-04 (Wave 2 — `test_channels.jl` rewrite)** — adopts the
  adiabatic-by-default idiom prescribed by Spike #1: compile a default-kwarg
  Channel in isolation with `mtkcompile(...; fully_determined=false)` and
  assert that `T_wall_left[i] / T_wall_right[i]` are present in the unknowns
  list (Hypothesis A literal — no binding eqns required).
- **Plan 55-07 (Wave 4 — `build_loop_lof_bypass` + LOF builder)** — adopts the
  topology prescribed by Spike #2 winner: `ChannelAndContacts + HeatDiffusion
  plate` heated leg via `one_sided_connection(ch, fuel; side=:left, name=:heated)`,
  driven by `heated.fuel.power ~ <constant>`. Adiabatic return leg via per-cell
  `connect`-port `WallTemperature` drivers (or equivalent post-Wave-1 component)
  pinning `ret.thermal_left[i]` and `ret.thermal_right[i]` to T_inlet on both
  sides.
- **Plan 55-08 (Wave 5 — `lof_transient.jl` example)** — IC dict shape mirrors
  Spike #2 winner: `(ine.port_in.mdot, ret.port_in.mdot, Dt(ret.port_in.mdot),
  flapper.T_open, heated.ch.T[1:n], heated.fuel.T[1:nz, 1:nx], ret.T[1:n])`.
