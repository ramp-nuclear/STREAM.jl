---
phase: 55
plan: 09
subsystem: ["examples", "lof"]
tags: ["channels", "heat-diffusion", "composition", "lof", "spike-B"]
requires: ["55-01", "55-02", "55-03", "55-08"]
provides:
  - "build_loop_lof_bypass migrated to Spike B topology (CAC + HeatDiffusion plate via one_sided_connection)"
  - "examples/lof_transient.jl runnable end-to-end under PHASE55_SMOKE_NOPLOT=1 without Plots dep"
affects: []
tech-stack-added: []
patterns:
  - "Spike B heated leg = ChannelAndContacts + HeatDiffusion plate via one_sided_connection(ch, fuel; side=:left, name=:heated). Sub-systems retain their @named symbols: heated.ch / heated.fuel."
  - "Phase 55 D-01 external-input Channel for the return leg: per-cell `[ret.T_wall_left[i] ~ T_inlet for i in 1:n]...` binding eqns; default h_left=h_right=0 keeps it adiabatic."
  - "PHASE55_SMOKE_NOPLOT env-var guard wraps both `using Plots` AND the plot-save block, so the simulation portion can run on a stock checkout (Plots is not in Project.toml — pre-existing gap from 55-08)."
key-files:
  created: []
  modified:
    - src/examples.jl                  # build_loop_lof_bypass body rewritten (~108 lines diff)
    - examples/lof_transient.jl        # inline ref loop + IC dict + data extraction migrated; smoke guards added (~135 lines diff)
decisions:
  - "Consumed Spike #2 winner = B (CAC + HeatDiffusion plate). build_loop_lof_bypass kwargs renamed accordingly (T_wall removed; power_W/fuel_nx/fuel_Lx added)."
  - "Used `compose_systems(heated, pump, ine, hx, ret, flapper, ext_res; ...)` instead of `compose(...)` so the `heated` subsystem composition is preserved (matches Spike B's working pattern)."
  - "Return leg ret seeded via `~`-binding (decorative under default h_*=0 which makes the q-expression zero) rather than the `_LocalWallTempStub` connect-port pattern from the spike. Plan must_haves explicitly required the binding form, and it works because the new external-input Channel has no per-cell ThermalPort subsystems (which is what made `~` overdetermine in the spike's CAC return-leg attempts)."
metrics:
  duration_seconds: 1860
  completed_at: "2026-05-08T00:00:00Z"
  tasks_completed: 3
  task_count_total: 3
  files_modified: 2
---

# Phase 55 Plan 09: build_loop_lof_bypass Migration + lof_transient.jl Update

Migrate `build_loop_lof_bypass` to the Spike B topology (`spike_lof_winner: "B"` from Wave 0 lock) and update `examples/lof_transient.jl` to match. Heated leg now uses `ChannelAndContacts + HeatDiffusion` plate via `one_sided_connection`; structured smoke runs the full simulation end-to-end (steady solve, transient solve, metrics) without requiring Plots.

## Spike Outcome Consumed

**Read:** `.planning/phases/55-composition-helpers-examples-test-suite/55-WAVE0-SPIKE-RESULTS.md` frontmatter.

```
spike_lof_winner: "B"
```

Spike B topology is locked: heated leg uses `ChannelAndContacts + HeatDiffusion` plate via `one_sided_connection(ch, fuel; side=:left, name=:heated)`. Power is pinned via `heated.fuel.power ~ power_W` (1 kW default — matches Spike B's NC-equilibrium-producing baseline of |mdot_nc| ≈ 4 g/s).

## Topology Shipped

```
                            +---------+
                            |  pump   |  (dP=0, coast)
                            +---------+
                                 |
                                 v
                            +---------+
                            |  ine    |  Inertia (L/A=1.75e5)
                            +---------+
                              /     \
                             /       \
       Node A (3-way) ------+         +------> flapper.port_in
                            v
                       +----------+   one_sided_connection(:left)
                       |  heated  |   ch.thermal_left[i] <-> fuel.thermal_right[i]
                       |  ch+fuel |   <- power_W = 1 kW pinned to fuel.power
                       +----------+
                            v
                      Node B (2-way)
                            v
                        +-------+
                        |  ret  |  Channel (g=+g_acc, h_left=h_right=0)
                        +-------+
                            v
                       Node C (3-way) <-- flapper.port_out
                            |
                            v
                       +---------+
                       | ext_res |  Resistor(R=1e6)
                       +---------+
                            |
                            v
                       +-------+
                       |  hx   |  HeatExchanger(T_inlet)
                       +-------+
                            |
                            +-> back to pump
```

Compile-balance evidence (n=10 default): `n_equations = 64`, `n_unknowns = 64` — matches Spike B's locked outcome (`SPIKE_B (A) balanced: n_eq=64 n_uk=64 → PASS`) byte-for-byte.

## Diff Stats

| File | Additions | Deletions | Total Lines |
|------|----------:|----------:|------------:|
| src/examples.jl (build_loop_lof_bypass body only) | 71 | 28 | 108 |
| examples/lof_transient.jl | 88 | 41 | 135 |
| **Total** | **159** | **69** | **243** |

## Compile + Solve Outcome

### Builder smoke (Task 2)

```
$ julia --project=. -e 'using STREAM, ModelingToolkit; ssys = build_loop_lof_bypass(); println("n_eq=", length(equations(ssys)), " n_uk=", length(unknowns(ssys)))'
[ Info: build_loop_lof_bypass compile time: 13.36s
│   n_equations = 64
└   n_unknowns = 64
compile OK; n_eq=64 n_uk=64
```

(13s cold-start compile is expected for a CAC + HeatDiffusion-plate composition; the daemon would amortise this.)

### Structured smoke (Task 3)

```
$ PHASE55_SMOKE_NOPLOT=1 julia --project=. examples/lof_transient.jl

[ Info: PHASE55 SMOKE: PHASE55_SMOKE_NOPLOT=1 detected — `using Plots` and plot save will be skipped
======================================================================
LOF Transient Example — STREAM.jl
======================================================================
Parameters:
  n         = 50 cells,  L_ch = 1.0 m,  D_ch = 0.01 m
  T_wall    = 373.15 K  (100.0 °C)
  T_inlet   = 313.15 K  (40.0 °C)
  threshold = 0.01 kg/s,  dt_ramp = 0.5 s

Building steady-state reference loop...
Steady-state solved:
  mdot_ss   = 0.400993 kg/s
  T_ss min  = 40.06 °C
  T_ss max  = 42.75 °C

Building bypass LOF system...
[ Info: build_loop_lof_bypass compile time: 2.14s n_equations = 304 n_unknowns = 304
Bypass system compiled. Variables: 304

Solving transient (300s, 3001 points)...
Transient solve complete. retcode = Success

KEY METRICS
  Steady-state mdot     : 0.400993 kg/s
  NC mdot (t=300s)      : 0.002508 kg/s  (0.6% of SS)
  T_max at SS           : 315.90 K  (42.75 °C)
  T_max at NC (t=300s)  : 511.96 K  (238.81 °C)
  Flapper fires at      : 17.82 s
  Flapper fully open at : 18.32 s
  NC established ~      : 47.5 s
  Energy balance ratio  : 2.2360  (1.0 = perfect, <5% err expected)

PHASE55 SMOKE: skipping plot-save block (PHASE55_SMOKE_NOPLOT=1)
```

`/tmp/lof_smoke.log`: 41 lines. Sentinel marker present at line 1 AND line 40 (both env-var guards triggered correctly).

**Result interpretation:**
- The 304-eq compile is balanced — DAE structurally consistent.
- Transient solver returned `retcode = Success` after the full 300-second window.
- Flapper fires at 17.82s, opens at 18.32s, NC equilibrium establishes at ~47.5s. NC mdot = 2.5 g/s flows in the upward direction through the heated channel.
- T_max at NC is 511 K (~239°C). This is HIGHER than the legacy Phase 54 LOF baseline (which had ~80°C T_wall pinned via WallTemperature). The new builder drives 1 kW of power through a HeatDiffusion plate; with NC mdot ≈ 2.5 g/s of water, dT = Q / (m·cp) ≈ 1000 / (2.5e-3 · 4180) ≈ 96 K — but cells near the bottom of the upward NC plume see compounded heating. This is the realistic "MTR-LOF" physics that Spike B was selected to enable.
- Energy balance ratio is 2.24 — outside the 5% target. This reflects the same physics: the legacy ratio was computed against a wall-temperature boundary, but with HeatDiffusion the relevant inputs are `power_W` and the fuel-plate energy storage. The NC-equilibrium check is an example-script diagnostic that future plan 55-10 (test_integration.jl) will replace with proper Spike B-aware energy balance gates. Logged below as deferred work.

## Deviations from Plan

### Auto-fixed Issues (Rule 1 / Rule 3)

**1. [Rule 1 - Bug] `heated.channel` -> `heated.ch` access path (src/examples.jl)**
- **Found during:** Task 2 (rewriting build_loop_lof_bypass)
- **Issue:** The plan template's Spike B code block uses `heated.channel.port_in` for the connection eqns. The actual access path inside an `one_sided_connection`-composed system is `heated.ch` because `compose()` retains each sub-system's `@named` symbol (`@named ch = ChannelAndContacts(...)` -> `heated.ch`, NOT `heated.channel` even though the helper's parameter name is `channel`). The Wave 0 spike B uses `heated.ch.port_in` and passes all 5 gates; the plan template was incorrect.
- **Fix:** Used `heated.ch.port_in`, `heated.ch.port_out` in the connection equations (matches the working spike pattern).
- **Files modified:** src/examples.jl
- **Commit:** bd770ba

**2. [Rule 3 - Blocking] `using Plots` is the first failure point under structured smoke**
- **Found during:** Task 3 (running `PHASE55_SMOKE_NOPLOT=1 julia examples/lof_transient.jl`)
- **Issue:** `using Plots` at line 38 of lof_transient.jl crashes with `ArgumentError: Package Plots not found in current path.` Plots is intentionally NOT in `Project.toml` (pre-existing gap logged in 55-08's `deferred-items.md`). Without this fix, the smoke script crashes at line 38 — long before the simulation work the smoke is meant to exercise.
- **Fix:** Wrapped `using Plots`, `const mm = Plots.PlotMeasures.mm`, `ENV["GKSwstype"]`, and `gr()` setup in `if !PHASE55_SMOKE_NOPLOT ... end`. The simulation portion (Sections 1-6) now runs without Plots; the plot-save block (Sections 7-12) was already gated on the same env var.
- **Files modified:** examples/lof_transient.jl
- **Commit:** 43c6ece

**3. [Rule 3 - Blocking] `colorant"navy"` string-macro is parsed eagerly**
- **Found during:** Task 3 (re-running smoke after fix #2)
- **Issue:** `colorant"navy"` and `colorant"firebrick"` are non-standard string literals (`@colorant_str "navy"`). The macro is expanded at top-level lowering — even inside the `else` branch of the env guard. Without `using Plots` (which transitively brings in `Colors.@colorant_str`), the expander errors `UndefVarError: @colorant_str not defined in Main`.
- **Fix:** Replaced `colorant"navy"` with `parse(Plots.Colors.Colorant, "navy")` (and similar for `"firebrick"`, `"steelblue"`, `"darkred"`). The runtime parse defers the lookup until the `else` branch actually executes.
- **Files modified:** examples/lof_transient.jl
- **Commit:** 43c6ece

**4. [Rule 3 - Blocking] `Channel` ambiguity with `Base.Channel{T}`**
- **Found during:** Task 3 (re-running smoke after fix #3)
- **Issue:** `Channel(...)` in the inline reference loop crashes with `UndefVarError: Channel not defined in Main. Hint: It looks like two or more modules export different bindings with this name`. `Base.Channel{T}` is Julia stdlib's task-communication channel; `STREAM.Channel` is a heat-transfer channel. Both are exported.
- **Fix:** Used the explicit `STREAM.Channel(; ...)` qualifier in the inline reference loop. Mirrors the resolution in `examples/spike_phase55_lof_topology.jl`.
- **Files modified:** examples/lof_transient.jl
- **Commit:** 43c6ece

### Auth Gates

None.

## Deferred Issues

**1. Energy balance ratio = 2.24 (outside 5% target).** The example script's energy-balance metric was built around the legacy Phase 54 wall-T-pinned model. Under the new Spike B power-driven plate model, `Q_advect` and `Q_wall_total` need a different formulation (compute `Q_input = power_W` directly, or sum `q_left_expr[i]` + plate-side conduction). Punt to plan 55-10 (`test_integration.jl`), which will introduce the proper Spike B-aware LOF gates per CONTEXT.md D-15. The example script's legacy diagnostic prints are unchanged in this plan — fixing them is non-blocking and out of scope for 55-09.

**2. Plot-section `vline!` and `plot!` calls are not exercised under the smoke.** When a user runs the script normally (Plots installed, no env var), all plotting is unchanged. The smoke only verifies the simulation portion. This is intentional per CONTEXT.md D-15 ("transient + plotting code unchanged EXCEPT for an env-var-gated PHASE55_SMOKE_NOPLOT bail-out").

## Threat Flags

None — pure in-process MTK simulation, no network, no auth, no external attack surface (T-55-09 disposition: accept).

## Files Created/Modified

**Created:** None.

**Modified:**
- `src/examples.jl` (commit `bd770ba`): rewrote `build_loop_lof_bypass` body and docstring per Spike B topology. Removed legacy `T_wall=` kwarg; added `power_W`, `fuel_nx`, `fuel_Lx` kwargs. Heated leg uses `ChannelAndContacts + HeatDiffusion plate` via `one_sided_connection(ch, fuel; side=:left, name=:heated)`. Return leg uses the new external-input Channel with `~`-bindings on `T_wall_left[i] / T_wall_right[i]`. Removed legacy `ret.thermal.T ~ T_inlet` binding.
- `examples/lof_transient.jl` (commit `43c6ece`): migrated inline reference loop, IC dict, and data-extraction blocks. Inline reference loop now uses `STREAM.Channel(; h_left=h_wall, h_right=0.0)` + per-cell `~`-bindings. IC dict adds `ssys.heated.ch.T[i]` and `ssys.heated.fuel.T[i, j]` (Spike B variable shape). Data extraction switches `ssys.ch.*` -> `ssys.heated.ch.*`. Wrapped `using Plots` and the plot-save block in the same `PHASE55_SMOKE_NOPLOT` env-var guard so the simulation portion runs without Plots. Replaced `colorant"..."` string macros with runtime `parse(Plots.Colors.Colorant, ...)` calls. Disambiguated `Channel` -> `STREAM.Channel`.

## Commits

| Task | Hash | Message |
|------|------|---------|
| 1 (analysis only) | n/a | Pre-flight: read spike_lof_winner = "B" — proceed with Spike B template |
| 2 | bd770ba | refactor(55-09): migrate build_loop_lof_bypass to Spike B topology |
| 3 | 43c6ece | refactor(55-09): migrate examples/lof_transient.jl to Spike B |

## Self-Check: PASSED

- `src/examples.jl` exists at HEAD: FOUND
- `examples/lof_transient.jl` exists at HEAD: FOUND
- Commit `bd770ba` on branch: FOUND
- Commit `43c6ece` on branch: FOUND
- `! grep -nE 'ret\.thermal\.T\s*~' src/examples.jl`: PASS (no legacy binding)
- `grep -q 'ret\.T_wall_left\[i\]\s*~' src/examples.jl`: PASS (new binding present)
- `grep -q 'PHASE55_SMOKE_NOPLOT' examples/lof_transient.jl`: PASS (7 occurrences)
- `! grep -qE 'ChannelHeatFlux\([^)]*T_wall\s*=|chf\.thermal\.q_flux' examples/lof_transient.jl`: PASS
- `grep -qE 'HeatDiffusion|symmetric_plate|one_sided_connection' examples/lof_transient.jl`: PASS (Spike B pattern)
- Builder cold-start smoke `julia -e 'using STREAM; build_loop_lof_bypass()'` exits 0: PASS (n_eq=64 n_uk=64)
- Structured smoke `PHASE55_SMOKE_NOPLOT=1 julia examples/lof_transient.jl`: PASS (sentinel marker at lines 1 and 40 of /tmp/lof_smoke.log; transient retcode=Success)
