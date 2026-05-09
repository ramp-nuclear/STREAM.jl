---
phase: 55-composition-helpers-examples-test-suite
plan: 08
subsystem: testing
tags: [mtk, channel, examples, builders, args-funcs, callable-parameter]

# Dependency graph
requires:
  - phase: 55-composition-helpers-examples-test-suite
    provides: "Wave 1 (55-01..55-03) — Channel/CHF dropped per-cell thermal_* ports; new external-input variables T_wall_left[1:n] / T_wall_right[1:n] on Channel; h_left / h_right kwargs accept Real | Vector | Function"
  - phase: 55-composition-helpers-examples-test-suite
    provides: "Wave 2 (55-04..55-05) — HeatFluxPort retired; test_channels.jl + test_connectors.jl rebuilt"
  - phase: 55-composition-helpers-examples-test-suite
    provides: "Wave 3 (55-06..55-07) — composition helpers verified byte-identical (D-08); test_misc.jl + test_composition.jl green"
provides:
  - "build_loop / build_loop_vertical / build_loop_transient migrated to new Channel API (D-09 / D-10)"
  - "h_wall::Real = 5000.0 kwarg added to all three simple-loop builders (Discretion #3)"
  - "build_loop_transient retains v0.9 callable-parameter pattern for time-varying T_wall (Discretion #4 path b)"
  - "build_loop_pk verified zero-edit under new Channel/CHF + CAC architecture (D-12)"
  - "examples/simple_loop.jl refreshed kwarg list with explicit h_wall=H_WALL"
  - "examples/mtr_assembly.jl verified zero source edits required (D-16)"
affects: [55-09, 55-10, 55-11, phase-56]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "args.funcs idiom in Julia: per-cell `[ch.T_wall_left[i] ~ value for i in 1:n]...` direct binding eqns (D-05 Style 1) — binds external-input vector variables at compose time"
    - "MTK callable-parameter at builder level: `@parameters (T_wall_callable::FType)(..)` + `[ch.T_wall_left[i] ~ ps[1](t) for i in 1:n]...` broadcasts a single closure value across all n cells"
    - "Equation[] type assertion on connection vector — disambiguates equation construction when the vector contains both `connect()` calls and per-cell binding splats"

key-files:
  created: []
  modified:
    - "src/examples.jl"
    - "examples/simple_loop.jl"
    - ".planning/phases/55-composition-helpers-examples-test-suite/deferred-items.md"

key-decisions:
  - "build_loop_transient time-varying T_wall mechanism: kept builder-level callable parameter (path b in Discretion #4). Rationale: preserves the v0.9 PointKinetics pattern, requires no WallTemperature source component dependency, and broadcasts the same `ps[1](t)` value across all n cells which matches the original semantic (single wall temperature for the whole channel)."
  - "h_right=0.0 (default) on all three builders, with decorative `[ch.T_wall_right[i] ~ T_inlet for i in 1:n]...` bindings. Rationale: q_right_expr[i] = 0 regardless of T_wall_right[i], so the right-face binding has no physics impact — but supplying it keeps the variable bound and avoids any free-unknown ambiguity under `mtkcompile` (defensive — the unbound case may or may not collapse depending on Hypothesis A / A_PARTIAL outcome from Wave 0 spike)."
  - "build_loop_pk verified with zero source edits — CAC API was untouched in Wave 1, the symmetric_plate / connect_temperature_feedback helpers are byte-identical (D-08), and the PK callable-parameter pattern was carried forward unchanged."
  - "examples/simple_loop.jl edit was kwarg-list-only (added explicit `h_wall=H_WALL`). Without this edit, the call still works because the new `h_wall=5000.0` default propagates — the explicit pass is for documentation/clarity only."

patterns-established:
  - "External-input variable closure pattern: when a variant exposes `(T_wall_left(t))[1:n]` as a free unknown (no internal equation), callers close it via `[ch.T_wall_left[i] ~ value for i in 1:n]...` splat inside the connections vector"
  - "Decorative-binding pattern: when h_*=0.0 makes the q-expression zero regardless of T_wall_*, still bind T_wall_* explicitly to avoid free-unknown ambiguity (defensive against MTK simplification edge cases)"

requirements-completed: [TEST-02]

# Metrics
duration: 18min
completed: 2026-05-08
---

# Phase 55 Plan 08: Three Simple-Loop Builders + Examples Migration Summary

**Three simple-loop builders (build_loop, build_loop_vertical, build_loop_transient) migrated to new Channel API with per-cell `T_wall_left[i] ~ T_wall` binding eqns + `h_wall=5000.0` kwarg; build_loop_pk verified zero-edit; examples/simple_loop.jl + examples/mtr_assembly.jl verified end-to-end (simulation portion)**

## Performance

- **Duration:** ~18 min wall-clock (3 cold-start julia invocations: precompile ~9s × 3 = 27s; first compile ~15s × 3 = 45s; first solve ~negligible after compile)
- **Started:** 2026-05-07T20:48:00Z (approximate — start of Task 1 edit)
- **Completed:** 2026-05-07T21:05:37Z
- **Tasks:** 3
- **Files modified:** 3 (1 src, 1 example, 1 deferred-items)

## Accomplishments

- **Three simple-loop builders rewritten** to consume the new Channel API. All three compile cleanly under cold-start; build_loop solves a 0.5s transient with `T_out=314.27 K > T_inlet=313.15 K` (heating works) and `retcode=ReturnCode.Success`.
- **build_loop_transient time-varying T_wall preserved** via the v0.9 callable-parameter pattern (Discretion #4 path b — no `WallTemperature` source component dependency). Compiles cleanly both with and without `T_wall_fn`.
- **build_loop_pk smoke-tested with the positive-marker assertion** (revision 1 of plan): `bin/jl ... | tee /tmp/build_loop_pk_smoke.log` followed by `grep -q "build_loop_pk solves OK"` PASSES. Zero source edits required — the CAC API and composition helpers are byte-identical post-Wave-1 (D-08, D-12).
- **examples/mtr_assembly.jl confirmed zero-edit** (D-16) — the script is pure CAC + HeatDiffusion via `plate()` and converges to symmetric T_out_l = T_out_r = 44.74°C, plate center 49.18°C, T_plate > T_fluid as expected.

## Task Commits

Each task was committed atomically (in worktree on `worktree-agent-a92ef4f072e9b3798`):

1. **Task 1: Rewrite build_loop, build_loop_vertical, build_loop_transient** — `f52b41d` (refactor)
   - +57 lines / -26 lines on src/examples.jl
   - All four compile-smokes (`build_loop`, `build_loop_vertical`, `build_loop_transient` with and without `T_wall_fn`) print their `compile time: ...s` line and emit `compile OK` info messages.
   - `build_loop` solves 0.5s transient with `T_out_end=314.27 K`, `retcode=Success`.

2. **Task 2: Verify build_loop_pk under new design (zero edits)** — *no commit (verification-only)*
   - Smoke command: `bin/jl -e '... build_loop_pk(ctrl); sol = solve_transient(...); @assert sol.retcode == ReturnCode.Success; println("build_loop_pk solves OK")' 2>&1 | tee /tmp/build_loop_pk_smoke.log; grep -q "build_loop_pk solves OK" /tmp/build_loop_pk_smoke.log`
   - Marker line `build_loop_pk solves OK` recorded in `/tmp/build_loop_pk_smoke.log`.
   - Compile time 14.88s; solver returned `ReturnCode.Success` on `range(0.0, 0.1, length=5)`.
   - Zero source edits — the CAC API was unchanged in Wave 1, helpers are byte-identical (D-08), and the PK callable-parameter pattern was carried forward unchanged.

3. **Task 3: Refresh examples/simple_loop.jl + verify examples/mtr_assembly.jl** — `607e9c1` (docs)
   - +2 lines on examples/simple_loop.jl (added `H_WALL = 5000.0` const + `h_wall=H_WALL` in build_loop call).
   - examples/mtr_assembly.jl: zero edits (D-16 confirmed).
   - +20 lines on .planning/phases/55-composition-helpers-examples-test-suite/deferred-items.md (logged pre-existing Plots dependency gap — see "Issues Encountered" below).

**Plan metadata:** included in SUMMARY commit (forthcoming).

## Files Created/Modified

- `src/examples.jl` — `build_loop` (lines 48-79 before, ~91 lines after), `build_loop_vertical` (lines 124-169 before, ~52 lines after), `build_loop_transient` (lines 194-241 before, ~76 lines after) all rewritten. `build_cube`, `build_loop_lof_bypass`, `build_loop_pk` untouched.
- `examples/simple_loop.jl` — added `H_WALL = 5000.0` const and `h_wall=H_WALL` kwarg to the build_loop(...) call. Diff is +2 lines / 0 deletions.
- `.planning/phases/55-composition-helpers-examples-test-suite/deferred-items.md` — appended a `## Discovered during 55-08 execution` section documenting the pre-existing Plots dependency gap.

## Decisions Made

1. **build_loop_transient time-varying T_wall mechanism: builder-level callable parameter (path b).** The plan offered two paths in Discretion #4: (a) bind `[ch.T_wall_left[i] ~ T_wall_fn(t)]` directly with the closure; (b) the v0.9 callable-parameter pattern `@parameters (T_wall_callable::FType)(..)` + `[ch.T_wall_left[i] ~ ps[1](t) for i in 1:n]...`. Picked (b) because (i) it's the established pattern in `build_loop_pk` and the existing PK builder works with it, (ii) it requires no source-component dependency, (iii) it broadcasts a single callable value across all n cells which preserves the original "single wall temperature" semantic, and (iv) it reuses the existing `ssys.sys.T_wall_callable => T_wall_fn` op-dict caller idiom from the legacy build_loop_transient.

2. **Decorative right-face binding `[ch.T_wall_right[i] ~ T_inlet for i in 1:n]...`** even though `h_right=0.0` makes `q_right_expr[i] = 0` regardless. Rationale: defensive against MTK simplification edge cases — the new external-input-variable design (Wave 1) leaves `T_wall_right[i]` as a free unknown when unbound, and depending on Hypothesis A / A_PARTIAL outcome from the Wave 0 spike, this might or might not collapse cleanly under `mtkcompile`. Binding it eliminates the ambiguity at the cost of two negligible decorative equations.

3. **`Equation[]` type assertion on connections vector.** Without the type annotation, the vector mixes `connect(...)` return values, scalar binding eqns (`pump.port_in.P ~ 1.0e5`), and per-cell splats (`[ch.T_wall_left[i] ~ T_wall for i in 1:n]...`). The implicit element type would be `Any`, which doesn't satisfy `System(...)`'s eq-list contract. `Equation[]` makes the contract explicit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] cwd drift to main repo on initial Task 1 edits**
- **Found during:** Task 1 (initial smoke test failed with stale stack trace pointing to `examples.jl:62`, but my edits had moved that content)
- **Issue:** I supplied absolute paths starting with `/home/itay/projects/Julia-STREAM/src/...` for the first three Edit calls. Those paths resolved to the **main repo** (`channels-redesign` branch), not the worktree (`worktree-agent-a92ef4f072e9b3798`). The agent's cwd was correct (worktree), but absolute paths bypassed cwd.
- **Fix:** (a) Reverted the errant edits in the main repo via `git checkout -- src/examples.jl` (cd'd into `/home/itay/projects/Julia-STREAM` deliberately, then executed `git checkout`). (b) Re-applied all three rewrites against the correct worktree path `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a92ef4f072e9b3798/src/examples.jl`. (c) Re-ran the cold-start smoke test — all four compile-smokes passed and build_loop transient solve succeeded with retcode=Success.
- **Files modified:** `src/examples.jl` (in worktree only — main repo restored to clean state).
- **Verification:** `git diff` against main repo shows no uncommitted changes; `git diff HEAD~2 HEAD --stat` against worktree HEAD shows the +57/-26 line delta on src/examples.jl as expected.
- **Committed in:** f52b41d (Task 1 commit) — the recovery happened before any commit was attempted, so no fixup was needed.

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** No scope creep. The recovery was precautionary — the bug was caught immediately by the very first smoke test (which referenced stale line numbers, exposing the path mismatch).

## Issues Encountered

**1. examples/simple_loop.jl and examples/mtr_assembly.jl fail at `using Plots` (pre-existing, out-of-scope).**
The plan's verify step `bin/jl examples/simple_loop.jl > /dev/null 2>&1` exits non-zero because `Plots` is not in `Project.toml`. Git history confirms Plots was deliberately removed in an earlier commit ("removed Plots.jl as a dependency"). This blocker is unrelated to plan 55-08's Channel API migration — it would have manifested identically before the plan started.

**Workaround / verification under plan 55-08:** the simulation portions of both scripts (sections 1-4: build, compile, solve, extract results) were exercised cold-start with Plots stubbed via inline julia scripts that mirror the constants and call sequence of each example. Both produce sane physics:
- **simple_loop.jl** — T_rise = 1.12 K, T_outlet = 41.12°C, mdot = 0.5986 kg/s (heating works under the migrated Channel API).
- **mtr_assembly.jl** — symmetric L/R outlets at 44.74°C, plate center 49.18°C, T_plate > T_fluid as expected (CAC + HD via `plate()` works under the byte-identical helpers).

**Logged to:** `.planning/phases/55-composition-helpers-examples-test-suite/deferred-items.md` under `## Discovered during 55-08 execution`. The fix (re-add Plots to deps, or split into examples-env, or make plotting optional) is a project-env concern, not a Phase 55 architectural one.

## User Setup Required

None — no external service configuration required. The plan's `user_setup: []` frontmatter held; no auth gates or secrets needed.

## Next Phase Readiness

**Ready for plan 55-09 (Wave 4 sibling):**
- `build_cube` / `build_loop_lof_bypass` left untouched — 55-09 owns the LOF builder migration.
- `src/examples.jl` line ranges shifted slightly due to new docstrings/kwargs; the `build_loop_lof_bypass` function body now lives at lines ~410-480 (previously 378-448). Plan 55-09's `read_first` references should resolve via function name, not line numbers.

**Ready for plan 55-10 (Wave 5 — test_integration.jl consolidation):**
- All three simple-loop builders compile + solve under cold-start. The `§Builders smokes` section of test_integration.jl (D-19) can rely on `build_loop()`, `build_loop_vertical()`, `build_loop_transient()` building cleanly with sane defaults.
- `build_loop_pk` zero-edit verified — the `§Point-kinetics + thermal-feedback loops` section can use the existing builder unchanged.
- `examples/mtr_assembly.jl` zero-edit verified — D-16 hold confirmed; no MTR-related test rework needed for this plan.

**Concerns / handoff notes:**
- `examples/lof_transient.jl` (D-15, ~1008 lines) is **not** in this plan's scope — it has an inline reference loop using the old `ChannelHeatFlux(T_wall=, ...)` API. Plan 55-09 (LOF builder migration) needs to address it.
- The Plots dependency gap (logged in deferred-items.md) blocks both example scripts' plotting steps. Future work should pick a resolution (re-add to deps, split env, or make plotting optional) — but it does not block the phase 55 close gate (TEST-05).

## Self-Check: PASSED

- **Files exist:** SUMMARY.md (this file), src/examples.jl, examples/simple_loop.jl — all present.
- **Commits exist:** f52b41d (Task 1), 607e9c1 (Task 3) — both reachable from HEAD.
- **Builders rewritten:** `[ch.T_wall_left[i] ~ T_wall ...]` and `[ch.T_wall_left[i] ~ T_wall_0 ...]` patterns present in src/examples.jl.
- **h_wall=5000.0 default:** 6 occurrences in src/examples.jl (3 in docstrings + 3 in function signatures × 2 references each — one per builder).
- **Callable parameter:** `T_wall_callable::FType` declaration retained in build_loop_transient.
- **build_loop_pk smoke marker:** "build_loop_pk solves OK" present in `/tmp/build_loop_pk_smoke.log`.
- **simple_loop.jl h_wall kwarg:** explicit `h_wall=H_WALL` present in build_loop call site.
- **mtr_assembly.jl:** zero edits (no diff lines).
- **build_cube / build_loop_lof_bypass untouched:** function-body diffs against HEAD~2 contain no edits inside cube/lof.

---
*Phase: 55-composition-helpers-examples-test-suite*
*Completed: 2026-05-08*
