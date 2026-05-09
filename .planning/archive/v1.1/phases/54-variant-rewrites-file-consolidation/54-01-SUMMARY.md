---
phase: 54
plan: 01
subsystem: components
tags: [channels, connectors, wallport-removal, var-01]
requires:
  - "Phase 53 _channel_core (q_left_expr/q_right_expr API contract)"
  - "v0.9 PointKinetics MTK callable-parameter pattern (FType + @parameters (fn::FType)(..))"
  - "ThermalPort connector (kept unchanged from Phase 52 D-04)"
provides:
  - "src/components/channels.jl with `function Channel end` declaration, _channel_core, and the new passive-recipient Channel"
  - "Channel(; name, n, geometry, g, h_left, h_right, friction_correlation) constructor accepting Real | AbstractVector | Function for h_left/h_right"
  - "Adiabatic-by-default Channel (h kwargs default 0.0; ports dangle ⇒ MTK Flow rule auto-zeros Q_flow)"
affects:
  - "src/components/channel.jl (gutted: legacy Channel + _channel_core removed; file remains as a near-empty marker until 54-04)"
  - "src/connectors.jl (WallPort @connector function block deleted)"
  - "src/STREAM.jl (WallPort dropped from exports; channels.jl include added after thermal_channel.jl)"
  - "test/test_connectors.jl (WallPort testsets and _StubWallDriver removed; _StubRecipient port_type kwarg removed; HeatFluxPort branches kept)"
tech-stack:
  added: []
  patterns:
    - "Passive-recipient channel: per-cell ThermalPort arrays + h kwarg (no internal htc correlation)"
    - "h_left/h_right kwarg type-dispatch (Real → broadcast; Vector → per-cell static; Function → MTK callable parameter)"
    - "Adiabatic-by-default via channel-side Q_flow ~ q_*_expr eqn + MTK Flow rule on dangling port"
key-files:
  created:
    - "src/components/channels.jl"
    - ".planning/phases/54-variant-rewrites-file-consolidation/54-01-SUMMARY.md"
  modified:
    - "src/components/channel.jl"
    - "src/connectors.jl"
    - "src/STREAM.jl"
    - "test/test_connectors.jl"
  deleted: []
decisions:
  - "Followed plan D-01: WallPort fully removed (verified by /tmp/spike_input_true.jl in the discuss phase; spike justified the walk-back)"
  - "Followed plan D-02/D-03/D-04: new Channel constructor signature, h-value semantics, q-expression construction"
  - "Followed plan D-10 (partial): channels.jl created with `function Channel end` first, then _channel_core, then Channel; CHF/CAC come in 54-02/03"
  - "DEVIATION (Rule 3): The plan's prescribed approach of leaving the legacy `Channel(; ..., htc_correlation)` body in channel.jl and letting the new one 'shadow' it does NOT work — Julia precompilation rejects same-signature method overwriting (hard error, not a warning). Fix: gut channel.jl (legacy Channel + _channel_core removed); file kept as a near-empty marker so `include('components/channel.jl')` in STREAM.jl continues to work. 54-04 deletes the file outright. This is consistent with plan success criterion 6 (the codebase loads end-to-end at every commit boundary)."
  - "DEVIATION (callable-parameter pattern): The plan's <action> showed `@parameters ($(Symbol(...))::FType)(..) = h` with dynamic Symbol interpolation AND a callable default value. Implementation chose the safer fallback path the plan explicitly allowed: separate fixed-name `if h isa Function` branches with `@parameters (h_left_fn::FType_L)(..)` (no default; user passes the function via solve `op` dict), mirroring v0.9 PointKinetics' verified pattern."
metrics:
  tasks_completed: 1
  tasks_total: 1
  duration_minutes: 12
  commits: 1
  completed: "2026-05-07"
---

# Phase 54 Plan 01: Channel Rewrite + WallPort Removal Summary

Established the new `src/components/channels.jl` file with the `function Channel end` Base.Channel{T} disambiguation declaration, moved `_channel_core` (Phase 53's shared physics helper) into it, and added the new passive-recipient `Channel(; name, n, geometry, g, h_left, h_right, friction_correlation)` constructor (D-02..D-04). `WallPort` removed from `src/connectors.jl`, `src/STREAM.jl` exports, and `test/test_connectors.jl` (D-01).

## What Shipped

### 1. `src/components/channels.jl` (new file)

In order:

1. Header comment block describing the file's purpose (private `_channel_core`, public `Channel`; CHF/CAC arrive in 54-02/03).
2. `function Channel end` — Base.Channel{T} disambiguation declaration. Without it, after 54-04 deletes legacy `channel.jl`, the new `function Channel(; name, n, ...)` body would attempt to extend `Base.Channel{T}` (Julia stdlib's task-communication channel) and break module load. Verified at `src/components/channels.jl:21`.
3. `_channel_core(; n, T, dp, port_in, port_out, geometry, g_acc, friction_correlation, q_left_expr, q_right_expr, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP)` — Phase 53's helper, byte-for-byte identical to its previous home (we only changed the file path).
4. The new `Channel(; ...)` constructor implementing D-02 / D-03 / D-04.

The new `Channel`:

- Declares `pars_base = @parameters L D_h A g_acc` and a Julia-level `extra_pars = Any[]` collector for the callable case.
- `h_left` / `h_right` resolve via `if isa(...)` chains:
  - `Real` → `fill(Num(h), n)` (uniform per-cell scalar, no parameter declared).
  - `AbstractVector` → length-checked, `Num.(h)` (per-cell static profile, no parameter declared).
  - `Function` → `@parameters (h_left_fn::FType)(..)` (per-side; uniform across cells, time-varying); the parameter symbol is appended to `extra_pars`. Caller passes `ch.h_left_fn => fn` in the solve `op` dict (mirrors v0.9 PointKinetics D-10).
- Builds `q_left_expr[i] = hL_per_cell[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T - T[i])` and analogous for right; emits the channel-side closure `thermal_left[i].Q_flow ~ q_left_expr[i]` so dangling ports (MTK Flow rule auto-zero Q_flow) reduce the eqn to either `h=0` (default IC ⇒ adiabatic) or `T_wall=T[i]` (no driving ΔT).
- Hands `q_left_expr`/`q_right_expr` and all `@variables` (`T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP`) to `_channel_core` for energy balance, friction, momentum, port wiring, and observables.

`function Channel end` is the FIRST top-level declaration in `channels.jl` (above `_channel_core` and the new `Channel(; ...)` body), per the plan's success criterion 7.

### 2. `src/components/channel.jl` (gutted, file remains as marker)

The legacy `Channel(; ..., htc_correlation, ...)` body was removed. The plan's <action> said putting `channels.jl` AFTER `channel.jl` would let the new `Channel` "shadow" the old one with method-overwriting warnings. In practice, **Julia precompilation rejects same-signature method overwriting as a hard error**, so the module fails to precompile. This is a Rule 3 (Auto-fix blocking issue) deviation — the plan's prescribed approach prevents `using STREAM` from succeeding.

The fix: vacate the legacy `Channel(; ...)` body. The file now contains only a header comment describing the migration; `include("components/channel.jl")` in `src/STREAM.jl` continues to work, and 54-04 deletes the file outright.

`_channel_core` was also removed here (it now lives in `channels.jl`); CHF and CAC in `thermal_channel.jl` already inline their own physics post-Phase 53 and don't depend on `_channel_core`.

Stale call sites (`test/test_channel.jl`, `test/test_correlations.jl`, `test/test_composition.jl`, `src/examples.jl:410,515`, etc.) that still reference the old `Channel(; htc_correlation, ...)` API will fail at run time. This is **explicitly accepted per Phase 54 D-12 / D-13** — the test/example rewrite happens in Phase 55. The codebase still loads end-to-end (precompiles, `using STREAM` succeeds) at this commit boundary.

### 3. `src/connectors.jl` (WallPort deleted)

The `@connector function WallPort(; name, T_wall, h, Q_flow)` block (28 lines) and its docstring deleted. `FlowPort`, `ThermalPort`, `HeatFluxPort` unchanged.

### 4. `src/STREAM.jl`

- `export FlowPort, ThermalPort, WallPort, HeatFluxPort` ⇒ `export FlowPort, ThermalPort, HeatFluxPort` (`WallPort` dropped).
- Added `include("components/channels.jl")` AFTER `include("components/thermal_channel.jl")`. Both legacy includes (`channel.jl`, `thermal_channel.jl`) preserved per plan; 54-04 deletes them.

### 5. `test/test_connectors.jl`

- Deleted `_StubWallDriver` function entirely.
- `_StubRecipient`: removed `port_type::Symbol` kwarg; removed all `port_type === :wall` branches; `PortType = HeatFluxPort` is hardcoded; the function now only supports `HeatFluxPort` for both sides. (`_StubFluxDriver` retained.)
- Deleted 9 WallPort-specific testsets (CONN-01 instantiation/variable count/Flow/across × 5; CONN-01 adiabatic when unconnected; CONN-01 driven case heats stub; CONN-04 connect()/instream × 2).
- Kept all `HeatFluxPort` testsets (5 instantiation/metadata + 2 smokes + 1 instream coexistence).

Final tally: **33 tests, all passing** (`julia --project=. test/test_connectors.jl` exits 0).

## Verification

| Acceptance criterion | Result |
| --- | --- |
| `test -f src/components/channels.jl` | OK |
| `grep -q "^function Channel end" src/components/channels.jl` | OK |
| `! grep -q "@connector function WallPort" src/connectors.jl` | OK |
| `! grep -q "WallPort" src/STREAM.jl` | OK |
| `grep -q 'include("components/channels.jl")' src/STREAM.jl` | OK |
| `grep -q 'include("components/channel.jl")' src/STREAM.jl` | OK (legacy preserved) |
| `grep -q 'include("components/thermal_channel.jl")' src/STREAM.jl` | OK (legacy preserved) |
| `grep -q "function _channel_core" src/components/channels.jl` | OK |
| `grep -q "function Channel(;" src/components/channels.jl` | OK |
| `grep -q "h_left::Union{Real, AbstractVector{<:Real}, Function}" src/components/channels.jl` | OK |
| `grep -q "thermal_left  = \[ThermalPort(; name=Symbol(:thermal_left" src/components/channels.jl` | OK |
| `! grep -q "_StubWallDriver" test/test_connectors.jl` | OK |
| `! grep -q "WallPort" test/test_connectors.jl` | OK |
| `julia --project=. test/test_connectors.jl` exits 0 | OK (33/33) |
| `Channel(; name=:t, n=4, geometry=PipeGeometry_circular(0.6, 0.01))` constructs | OK (default adiabatic) |
| `Channel(...; h_left=fill(5000.0, 4))` constructs | OK (vector path) |
| `Channel(...; h_left=t -> 5000.0)` constructs | OK (callable path) |
| Vector length mismatch errors | OK (`Channel: h_left vector length 3 ≠ n=4`) |

## Plan-Specified Output Items

- **`function Channel end` declaration in place at the top of channels.jl, above `_channel_core`:** Yes, line 21 of `src/components/channels.jl` (immediately after the header comment block, before `_channel_core` at line 84 and the new `Channel(; ...)` at line 219).
- **Whether the callable-parameter `@parameters` interpolation worked or required the fallback:** Used the **fallback path** (separate fixed-name `if h_left isa Function` / `if h_right isa Function` branches with `@parameters (h_left_fn::FType_L)(..)` and `@parameters (h_right_fn::FType_R)(..)`). Reasoning: the plan's <action> note explicitly authorized this fallback. The dynamic `Symbol(:h_, side_label, :_fn)` interpolation inside `@parameters` is unproven in this codebase, while the fixed-name pattern is the verified v0.9 PointKinetics PK-01 pattern. Caller must pass `ch.h_left_fn => fn` (and/or `ch.h_right_fn => fn`) in the solve `op` dict.
- **Method-overwriting warnings observed when loading STREAM:** Initially YES (the plan's "shadowing" approach triggered a HARD precompilation error: `ERROR: Method overwriting is not permitted during Module precompilation`). This is the Rule 3 deviation documented above. After gutting `src/components/channel.jl`, **module precompiles cleanly with zero warnings** — `using STREAM` succeeds in 7.9 s cold (this worktree, no daemon).
- **New Channel mtkcompile size on a 4-cell smoke (n_eq, n_unknowns):** Standalone Channel does NOT mtkcompile in isolation (its FlowPorts and ThermalPort arrays dangle, leaving the system underdetermined — same behavior as the original Channel constructor). `mtkcompile` size is therefore only measurable inside a closed loop, which Phase 54-05 will smoke. Constructor calls succeed for all four signature shapes (Real, Vector, Function, default-adiabatic).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Same-signature method overwriting breaks precompilation**

- **Found during:** Task 1, after writing `channels.jl` and including it after legacy `channel.jl`.
- **Issue:** `julia --project=. -e 'using STREAM'` failed precompilation with `ERROR: Method overwriting is not permitted during Module precompilation` because both `channel.jl:26` and `channels.jl:219` define `function Channel(; ...)` — Julia treats kwargs-only constructors as the same method signature regardless of kwarg names, so the new one tries to overwrite the legacy one inside the same module.
- **Fix:** Removed the legacy `Channel(; ..., htc_correlation, ...)` body from `src/components/channel.jl` (the new `Channel` in `channels.jl` is now the only definition). Also removed `_channel_core` from `channel.jl` (the new home is `channels.jl`). The file remains as a near-empty marker so `include("components/channel.jl")` in `STREAM.jl` continues to succeed; 54-04 deletes the file outright.
- **Files modified:** `src/components/channel.jl`
- **Commit:** e9de41d
- **Plan implication:** The plan's <action> step B and success criterion 6 assumed Julia would emit overwriting *warnings* and continue. In practice, precompilation rejects this as a hard error. The fix preserves all of the plan's other invariants (legacy file still exists, legacy includes preserved, channels.jl shipped). Stale callers of the old `Channel(; htc_correlation, ...)` API (test_channel.jl, test_correlations.jl, test_composition.jl, build_loop_pk in examples.jl, test_point_kinetics.jl) will fail at run time — explicitly accepted per Phase 54 D-12 / D-13.

**2. [Rule 3 - Blocking issue] Type mismatch in callable extra_pars vector**

- **Found during:** Task 1, after first compile attempt of `Channel(; h_left=t->5000.0)`.
- **Issue:** `pL = @parameters (h_left_fn::FType_L)(..)` returns `Vector{Symbolics.CallAndWrap{Num}}`, not `Vector{Num}`. The plan's prescribed `extra_pars = Num[]` collector therefore failed `append!(extra_pars, pL)` with a `MethodError` on the convert path.
- **Fix:** Changed `extra_pars = Num[]` to `extra_pars = Any[]`, and the final params splice from `pars = [pars_base...; extra_pars...]` to `pars = Any[pars_base...; extra_pars...]`. MTK accepts `Vector{Any}` parameter lists; the `Any` typing only carries the symbolic reference, not runtime values.
- **Files modified:** `src/components/channels.jl`
- **Commit:** e9de41d
- **Plan implication:** None for the design contract; the callable-parameter pattern works as the plan intended, just with the right Julia container type.

### Architectural Decisions Asked

None — both deviations were Rule 3 (blocking issue) auto-fixes; no architectural change needed.

## Authentication Gates

None encountered.

## Known Stubs

None.

## Test File Status (information for downstream plans)

Tests under the OLD Channel API (`Channel(; htc_correlation, ...)` and the single-`thermal` `ThermalPort` connection pattern) WILL FAIL until Phase 55 rewrites them:

- `test/test_channel.jl` (old API)
- `test/test_correlations.jl` lines 119, 183, 251 (Channel calls with `htc_correlation` kwarg)
- `test/test_composition.jl` (multiple, all using `htc_correlation` — these target CAC, not Channel, so they may still work; CAC is unchanged in this plan)
- `test/test_point_kinetics.jl` lines 478, 562 (these target CAC, similar)

`test/test_connectors.jl` PASSES (33/33). The phase boundary in D-12 / D-13 explicitly accepts the wider test failures until Phase 55's TEST-01 rewrite. `using STREAM` and `Channel(...)` construction succeed; the codebase loads end-to-end.

## Self-Check: PASSED

- File `src/components/channels.jl` exists: OK
- File `.planning/phases/54-variant-rewrites-file-consolidation/54-01-SUMMARY.md` exists: OK (this file)
- Commit e9de41d exists in `git log --oneline`: OK
- All 13 plan acceptance criteria satisfied: OK
