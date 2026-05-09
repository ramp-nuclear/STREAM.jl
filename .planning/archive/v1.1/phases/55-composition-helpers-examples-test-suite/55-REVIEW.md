---
phase: 55-composition-helpers-examples-test-suite
reviewed: 2026-05-08T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - CLAUDE.md
  - examples/lof_transient.jl
  - examples/simple_loop.jl
  - examples/spike_phase55_lof_topology.jl
  - examples/spike_phase55_unbound.jl
  - src/STREAM.jl
  - src/components/channels.jl
  - src/components/sources.jl
  - src/connectors.jl
  - src/examples.jl
  - test/runtests.jl
  - test/test_channels.jl
  - test/test_composition.jl
  - test/test_connectors.jl
  - test/test_integration.jl
  - test/test_misc.jl
  - test/test_point_kinetics.jl
  - test/test_pump.jl
  - test/test_thresholds.jl
findings:
  critical: 2
  warning: 8
  info: 5
  total: 15
status: issues_found
---

# Phase 55: Code Review Report

**Reviewed:** 2026-05-08
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

Phase 55 migrates `Channel` and `ChannelHeatFlux` from per-cell `ThermalPort` arrays to channel-level external-input variables (`T_wall_left[1:n]`, `T_wall_right[1:n]`, `q_left[1:n]`, `q_right[1:n]`), retires the legacy heat-flux connector, adds two value-source components (`WallTemperature`, `HeatFluxSource`), migrates all builders/examples, and consolidates the test suite to a 14-file canonical layout.

The core component implementations (`channels.jl`, `sources.jl`) are well-documented and consistent with the documented MTK patterns. However, the wave-0 spike scripts shipped under `examples/` are now broken or misleading because they were written against the pre-Phase-55 Channel shape and were never updated after the redesign landed. There is also a real docstring/contract mismatch in `build_loop_transient` (callable T_wall path) that points users at a non-existent symbolic path. Several minor code-quality issues (unused locals, unused parameter declaration, unused imports, brittle parameter lookup) are tracked as warnings/info.

No security defects were observed; this is a numerical simulation library with no input parsing, network surfaces, or persistent state.

## Critical Issues

### CR-01: `examples/spike_phase55_lof_topology.jl` — `Spike A` references non-existent `thermal_left/right` ports on the new `Channel`

**File:** `examples/spike_phase55_lof_topology.jl:91, 116-117`

**Issue:** The spike calls `@named ret = Channel(; n=N_LOF, geometry=geom, g=G_ACC)` (line 91) and then issues `connect(_p(wt_ret_left, :port, i), _p(ret, :thermal_left, i))` plus the same with `:thermal_right` (lines 116–117). After Phase 55 D-01, `Channel` has no `thermal_left*`/`thermal_right*` subsystems — those were retired in this phase and the test in `test_channels.jl:61-62` actively asserts their absence. `_p(ret, :thermal_left, i)` evaluates to `getproperty(ret, :thermal_left1)`, which will raise an MTK property-access error before MTK even sees the `connect()` call. Running `bin/jl examples/spike_phase55_lof_topology.jl` post-Phase-55 will throw on Spike A's first per-cell connect and on Spike B's `wt_ret_left`/`wt_ret_right` connects (lines 224-225).

This file is shipped (not under `.planning/` or otherwise excluded) and listed by `.planning/phases/55-composition-helpers-examples-test-suite/55-VALIDATION.md` as a "reproducible §3 spike". It is broken and will mislead anyone re-running it.

**Fix:** Either (a) delete the file (it served its Wave-0 decision purpose and the outcome `spike_lof_winner: "B"` is now baked into `build_loop_lof_bypass`), or (b) rewrite the `ret` wiring to match the new external-input API (`[ret.T_wall_left[i] ~ T_INLET for i in 1:N_LOF]...`, etc.) and remove the now-irrelevant `wt_ret_left`/`wt_ret_right` stubs. If keeping it, also fix the file header which still labels Q1 as testing the "Phase 54 (CURRENT) Channel" — that wording is also stale.

```julia
# Replacement for ret per-cell wiring (option b):
[ret.T_wall_left[i]  ~ T_INLET for i in 1:N_LOF]...,
[ret.T_wall_right[i] ~ T_INLET for i in 1:N_LOF]...,
```

---

### CR-02: `build_loop_transient` callable-T_wall path — docstring directs callers to a non-existent symbolic path

**File:** `src/examples.jl:201-202`

**Issue:** The docstring says

> When using a callable `T_wall_fn`, the caller must include the callable parameter in `op`:
> `ssys.sys.T_wall_callable => T_wall_fn` (where `ssys` is the compiled system).

The implementation at line 262 builds the System as `@named sys = compose(System(connections, t, [], ps; name=:sys), pump, bc, ch)`. The result is itself the `:sys`-named system — there is no nested `sys.sys.T_wall_callable`. Callers who follow the docstring will get a `getproperty` error at runtime. The actual integration test (`test/test_integration.jl:192`) confirms this by *not* using the documented path; it works around the issue with `T_wall_sym = last(parameters(ssys))`. That fallback is itself fragile (see WR-04) and silently wrong if MTK ever reorders parameters.

Either the docstring or the implementation is incorrect, and the only test that exercises this path actively avoids the documented contract.

**Fix:** Pick one canonical access path and make both docstring and test use it. Either:

```julia
# Option 1 — make the parameter accessible at top level
push!(op_ic, ssys.T_wall_callable => T_wall_step)
# and update the docstring to: `ssys.T_wall_callable => T_wall_fn`
```

or, if the parameter actually lands under a subsystem post-compose, document the *actual* path (run the test once and read `string(parameters(ssys))` to find it), and replace `last(parameters(ssys))` in `test_integration.jl:192` with the explicit symbolic reference.

## Warnings

### WR-01: `examples/simple_loop.jl` — unguarded `using Plots` will fail on a stock checkout

**File:** `examples/simple_loop.jl:25-27`

**Issue:** `Plots` is not in `Project.toml` `[deps]` (verified — only `DaemonMode`, `ModelingToolkit`, `OrdinaryDiffEq`, `QuadGK`, `Revise`, `SteadyStateDiffEq`, `Sundials`). The file does `using Plots` and `gr()` unconditionally. `examples/lof_transient.jl` correctly guards this with `PHASE55_SMOKE_NOPLOT` and `@eval using Plots` (lines 49-58); `simple_loop.jl` does not. Anyone running `julia --project examples/simple_loop.jl` on a fresh clone will hit `ArgumentError: Package Plots not found in current path`. The Phase 55 deferred-items doc explicitly notes the pre-existing Plots dependency gap; this file should also gate the import.

**Fix:** Apply the same `PHASE55_SMOKE_NOPLOT` guard as `lof_transient.jl`, or split the script into a `_solve.jl` (no plotting) plus a separate plotting helper.

```julia
const PHASE55_SMOKE_NOPLOT = (get(ENV, "PHASE55_SMOKE_NOPLOT", "") == "1")
if !PHASE55_SMOKE_NOPLOT
    @eval using Plots
    ENV["GKSwstype"] = "100"
    Plots.gr()
end
# ... and gate the savefig/plot block at the bottom of the file similarly.
```

---

### WR-02: `examples/spike_phase55_unbound.jl` — Q1 description is now stale (file header claims to test "Phase 54 (CURRENT)" Channel but Channel has been redesigned)

**File:** `examples/spike_phase55_unbound.jl:1-17, 25, 41`

**Issue:** Q1 prints `"SPIKE 1 — Question 1: Phase 54 (CURRENT) Channel with default kwargs"` (line 25) and the comment block at the top describes the test as documenting the BASELINE "still-shipped Phase 54 code" (lines 7-9). But Phase 55 has already shipped — the `Channel` constructor used at line 30 is the *new* external-input shape, not the per-cell-port shape. Anyone running this spike now is testing the wrong thing relative to its labels and will likely mis-interpret the result. The HYPOTHESIS=A/B output line at the bottom is also misleading because the question was already answered for the post-Wave-1 code, not the pre-Wave-1 code.

**Fix:** Either delete the file (the spike outcome is recorded in `55-WAVE0-SPIKE-RESULTS.md` and no longer needs reproducing), or rewrite the headers/print strings so the script is self-describing as a *post-Phase-55* sanity check rather than a pre-Phase-55 baseline.

---

### WR-03: `Channel`, `ChannelHeatFlux`, `ChannelAndContacts` — declared parameter `D_h` is never read

**File:** `src/components/channels.jl:281, 470, 600`

**Issue:** All three variant constructors include `D_h = Dh` in their `@parameters` block:

```julia
pars_base = @parameters begin
    L = L
    D_h = Dh   # ← declared, never used
    A = A
    g_acc = g
end
```

Inside the constructors, the friction/HTC equations use the local Julia binding `Dh = geometry.Dh` directly (e.g. line 139 `Re_i_for_friction = abs(port_in.mdot) * Dh / ...`) — the symbolic parameter `D_h` never appears in any equation. It survives `mtkcompile` as a dead parameter that downstream code can `setp` without effect. This is wasted bookkeeping and slightly confusing for anyone reading the file (`D_h` looks load-bearing but isn't).

**Fix:** Remove the `D_h = Dh` line from all three `@parameters` blocks — the local `Dh` binding is what actually drives the equations. If the parameter is intentionally exposed for runtime tuning, then change the equations to reference `D_h` (the symbol) instead of `Dh` (the local Float64).

---

### WR-04: `test_integration.jl` — `last(parameters(ssys))` relies on undocumented MTK parameter ordering

**File:** `test/test_integration.jl:192`

**Issue:** `T_wall_sym = last(parameters(ssys))   # T_wall_callable is the last parameter`. MTK does not contract that `parameters(ssys)` preserves declaration order across mtkcompile + index reduction; future MTK versions or unrelated edits to `build_loop_transient` (e.g. adding any parameter to pump or HX) could silently shuffle the list and pick up the wrong symbol. The test would still compile, but `op_ic` would push `(some-other-param) => T_wall_step`, the actual T_wall callable would default to its `(..)` placeholder, and the solve might "succeed" with garbage. The assertion `T_ts[end] > T_ts[1]` (line 201) is loose enough that a silent mis-binding could go undetected.

This is also the symptom that exposed CR-02 (the doc says `ssys.sys.T_wall_callable`, the test grabs by index) — both pieces of code are working around the same unresolved question of "what is the public path to this parameter?".

**Fix:** Once CR-02 is resolved, replace the `last(parameters(...))` lookup with the canonical symbolic path:

```julia
push!(op_ic, ssys.T_wall_callable => T_wall_step)   # if top-level
# or whatever the documented post-compose path is
```

Until CR-02 is resolved, at minimum add a `nameof`-based assertion to fail loudly on order drift:

```julia
T_wall_sym = last(parameters(ssys))
@assert occursin("T_wall_callable", string(T_wall_sym))
```

---

### WR-05: `Channel`, `ChannelHeatFlux`, `ChannelAndContacts` — unused `Dt = Differential(t)` local in variant body

**File:** `src/components/channels.jl:272, 466, 596`

**Issue:** Each variant constructor binds `Dt = Differential(t)` immediately after parameter setup (lines 272, 466, 596) but never uses `Dt` in the variant body — the only `Dt(...)` calls live in `_channel_core` which has its own `Dt = Differential(t)` at line 103. The locals are dead. Not a correctness issue, but ugly and a cargo-culted holdover from the pre-Phase-53 inlined code.

**Fix:** Delete the three `Dt = Differential(t)` assignments at lines 272, 466, 596. Keep only the one inside `_channel_core` at line 103 where it is actually used.

---

### WR-06: `test_integration.jl` — `Channel` and `ChannelHeatFlux` imported but never instantiated

**File:** `test/test_integration.jl:35-38`

**Issue:** `import STREAM: Channel, ChannelAndContacts, ChannelHeatFlux, ...`. Searching the file:

- `Channel` (the constructor) is never called — only the bare word `Channel` appears in comments at lines 100, 543, etc.
- `ChannelHeatFlux` is never called either; the only hit at line 215 is inside a comment string.

These imports add nothing to the file and may suggest to a reader that these constructors are exercised here when the actual integration logic uses `ChannelAndContacts` exclusively (post-Spike-B).

**Fix:** Trim the import to the symbols actually used:

```julia
import STREAM: ChannelAndContacts, Pump, HeatExchanger,
    ConstantTemperature, PipeGeometry_circular, PipeGeometry_rectangular,
    HeatDiffusion, solve_steady, solve_transient, steady_state_guess,
    regime_dependent_q_scb, _bergles_rohsenow_dT_ONB
```

---

### WR-07: `test_pump.jl` PHY-05/PUMP-02 — relies on KINSOL converging a system with free `T_wall_left/right` unknowns and no equation pinning them

**File:** `test/test_pump.jl:25-41, 73-88`

**Issue:** The test constructs `Channel(n=5, geometry=...)` with default `h_left=h_right=0.0` and *no* binding on `ch5.T_wall_left[i]` / `ch5.T_wall_right[i]`. It then `mtkcompile(...; fully_determined=false)` and immediately calls `solve_steady`. After mtkcompile, the system has 10 free `T_wall_*[i]` unknowns with no constraint (the q-expression collapses to `0 * (T_wall - T) = 0`, which structurally drops the symbol but may or may not be eliminated by MTK's simplifier depending on `Hypothesis A` vs `A_PARTIAL`). KINSOL is being asked to solve a system with possibly unconstrained variables; convergence is non-deterministic across MTK versions.

The Phase 55 plan (`55-CONTEXT.md` D-01 commentary) acknowledges this is brittle: "Whether T_wall_*[i] is a free unknown after mtkcompile(...; fully_determined=false) (Hypothesis A) or is collapsed by structural simplification (Hypothesis A_PARTIAL) is recorded in 55-WAVE0-SPIKE-RESULTS.md". The test relies on whichever hypothesis is in force on the current MTK version. A regression in MTK's variable-elimination pass could turn this from "passes" to "KINSOL diverges with ReturnCode.MaxIters" without any change to STREAM.

**Fix:** Add defensive `T_wall_*[i] ~ T_inlet` bindings to make the system fully constrained, even though h_*=0 makes them physically irrelevant. Mirrors the pattern used in `build_loop_lof_bypass:505-506` for the `ret` channel:

```julia
conns5 = [
    connect(pump5.port_out, bc5.port_in),
    connect(bc5.port_out, ch5.port_in),
    connect(ch5.port_out, pump5.port_in),
    pump5.port_in.P ~ 1e5,
    [ch5.T_wall_left[i]  ~ 313.15 for i in 1:5]...,
    [ch5.T_wall_right[i] ~ 313.15 for i in 1:5]...,
]
```

Then the `fully_determined=false` flag can also be dropped — making the test less reliant on MTK's structural-simplification details.

---

### WR-08: `test_point_kinetics.jl` TF-01..04 fixtures — duplicate `name` kwarg in `@named ch = Channel(; name=:ch, ...)`

**File:** `test/test_point_kinetics.jl:305, 405`

**Issue:** Both lines do `@named ch = Channel(; name=:ch, n=5, geometry=pg5)`. Inspecting MTK's `_named` macro (`ModelingToolkit/.../abstractsystem.jl:2644`), the macro skips inserting `name=...` when the user already supplied one — so the line currently happens to compile. But this idiom is unidiomatic and easy to break: if MTK changes `_named` to error on duplicate `name`, or if a future `@named` consumer (e.g. a refactor wrapping `@named` in another macro) inserts before checking, both testsets would error. The pattern also misleads readers about what `@named` does.

**Fix:** Drop the explicit `name=:ch` kwarg — the `@named ch = ...` macro already handles naming.

```julia
@named ch = Channel(; n=5, geometry=pg5)
```

## Info

### IN-01: `examples/lof_transient.jl` — silent `solve_transient` wraps don't propagate solver warnings to the smoke greppable output

**File:** `examples/lof_transient.jl:246-250`

**Issue:** The script checks `sol.retcode != ReturnCode.Success` and `error()`s on failure, but partial-success retcodes (`MaxIters`, `Unstable`, callback-induced terminations the user didn't expect) all surface as a single string in the error path. The structured smoke that consumes this script grep's for a sentinel "ALL PLOTS SAVED" line in non-NOPLOT mode and for printf totals in NOPLOT mode; an early termination would print KEY METRICS with garbage values and never reach the sentinel.

**Fix:** When checking retcode, also `flush(stdout)` and explicitly print `SMOKE_FAIL: <retcode>` so the wrapper has a deterministic failure marker.

---

### IN-02: `Channel` / `ChannelHeatFlux` / `ChannelAndContacts` docstrings — claim "Returns Uncompiled `ODESystem`" but the implementation returns the result of `compose(System(...), port_in, port_out)`

**File:** `src/components/channels.jl:258, 454, 582`

**Issue:** The actual return type is whatever MTK 11's `compose` returns (a `System` from the new `ModelingToolkitBase`), which is not literally `ODESystem` — that name was deprecated. Other docstrings in the codebase use the same phrasing, so this is consistent rather than uniquely wrong. Worth normalizing across the API for clarity.

**Fix:** Sweep replacement of "ODESystem" → "System" (or whatever the canonical user-facing name is) in docstrings, in a follow-up cleanup phase.

---

### IN-03: `src/STREAM.jl` — `STREAM.jl` exports list is partly redundant with the `export Channel,` block

**File:** `src/STREAM.jl:29-45`

**Issue:** `Channel` is in the multi-line export block that begins on line 29, but `Channel` is also covered by `import STREAM: Channel` in test files for Base ambiguity disambiguation. This isn't a bug — just a reminder that exporting `Channel` in `STREAM.jl` is the right call, and the `import STREAM: Channel` in tests is necessary precisely because `Channel` is exported but ambiguous with `Base.Channel{T}`. A short comment on the export line would help future readers understand why the test files keep doing this.

**Fix:** Add a one-line comment next to `export Channel,` noting the Base.Channel ambiguity:

```julia
export Channel,           # NOTE: ambiguous with Base.Channel{T}; tests do `import STREAM: Channel`.
```

---

### IN-04: `test/test_integration.jl` LOF-01 — `findfirst(p -> isequal(p.first, ssys.flapper.T_open), op)` is brittle on MTK symbolic equality

**File:** `test/test_integration.jl:359-360`

**Issue:** MTK symbolic objects do not always compare equal across re-fetched references — `ssys.flapper.T_open` evaluated twice may produce two different `Symbolics.CallWithMetadata`-style objects that `isequal` rejects. The construction of `op` two lines up uses `ssys.flapper.T_open` once, but the search uses a fresh `ssys.flapper.T_open`. The test currently passes only because MTK's `isequal` for namespaced unknowns happens to work. If a future MTK version changes that, the `findfirst` would return `nothing` and the next `.second` call would throw.

**Fix:** Either capture the symbol once at IC-build time and reuse it, or assert the property by index (the IC list is built deterministically so `op[4]` is always the `T_open` entry given the construction sequence). The cleanest option is to cache:

```julia
T_open_sym = ssys.flapper.T_open
op = Pair{Any,Any}[..., T_open_sym => 1.0e30, ...]
# later:
T_open_init = op[findfirst(p -> isequal(p.first, T_open_sym), op)].second
```

---

### IN-05: `examples/lof_transient.jl` — `dt_ramp = 0.5` constant clashes with `build_loop_lof_bypass` default `dt_ramp = 5.0`

**File:** `examples/lof_transient.jl:75` vs `src/examples.jl:440`

**Issue:** The example sets `const dt_ramp = 0.5` and passes it through `build_loop_lof_bypass(...; dt_ramp = dt_ramp, ...)`, but the build function's default is `5.0` (a 10x difference). Anyone reading both files in succession (the example to learn the workflow, then the builder to understand the API) might assume 5.0 is the canonical NC value when the example actually exercises 0.5. Not incorrect — different scenarios — but the comment block in the example doesn't explain the deliberate divergence.

**Fix:** Add a one-line comment next to `const dt_ramp = 0.5` explaining the choice (e.g. `# Faster ramp than build_loop_lof_bypass default (5.0s) to compress the transient for plotting`).

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
