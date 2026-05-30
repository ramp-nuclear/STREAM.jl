# Phase 55 — Deferred / Cross-Plan Issues

Issues discovered during execution that fall OUTSIDE the current plan's scope.
These are tracked here so subsequent plans/waves can pick them up.

## Discovered during 55-06 execution

### `test_misc.jl` COMP-02 build_loop regression test errors under Wave 1 architecture

**Status:** Pre-existing (introduced by Wave 1 plans 55-01..55-03 — Channel/CHF dropped per-cell `thermal_*` ports per CONTEXT D-01/D-03). Out of scope for plan 55-06.

**Symptom:** `julia --project=. test/test_misc.jl` fails the COMP-02 testset with:
```
ArgumentError: System ch: variable thermal does not exist
  build_loop at src/examples.jl:62
```

**Cause:** `src/examples.jl:62` (`build_loop`) still references `ch.thermal.T ~ T_wall` against the old single-`thermal` port API. The Channel rewrite in Wave 1 dropped that port; Channel now exposes `T_wall_left[1:n]` / `T_wall_right[1:n]` external-input variables (D-01) plus an `h_left` kwarg (D-02).

**Fix location:** Plan **55-08** — `src/examples.jl` builder migration (D-09, D-10). The plan author already scopes this fix to 55-08 with the new `h_wall` kwarg + `[ch.T_wall_left[i] ~ T_wall for i in 1:n]...` direct-binding-eqn idiom (D-10). The COMP-02 regression testset will pass again once 55-08 lands.

**Scope-boundary justification (Rule):** plan 55-06's `files_modified` is exclusively `test/test_misc.jl`; modifying `src/examples.jl` would (a) violate the plan's parallel-execution exclusivity contract, (b) overlap with plan 55-08's deliverable, and (c) require an unrelated architectural change. The 10 new testsets added in 55-06 pass cleanly in isolation (verified — see 55-06-SUMMARY.md).

## Discovered during 55-08 execution

### `Plots` package missing from project — `examples/simple_loop.jl` and `examples/mtr_assembly.jl` fail at `using Plots`

**Status:** Pre-existing (Plots was deliberately removed from `Project.toml` per git history — see commit message "removed Plots.jl as a dependency"). Out of scope for plan 55-08.

**Symptom:** `julia --project=. examples/simple_loop.jl` and `julia --project=. examples/mtr_assembly.jl` both fail with:
```
ERROR: LoadError: ArgumentError: Package Plots not found in current path.
- Run `import Pkg; Pkg.add("Plots")` to install the Plots package.
```
Both example scripts include `using Plots` in their preamble and call `plot(...)`/`savefig(...)` for output PNGs. Plots is in neither the project env nor the global env on this WSL2 box.

**Verification under plan 55-08:** the *simulation portions* of both scripts (sections 1-4: build, compile, solve, extract results) were exercised cold-start with Plots stubbed. Both produce sane physics — `simple_loop.jl` builds the migrated `build_loop(...)` API with `h_wall=H_WALL` and converges to T_rise=1.12 K with mdot=0.5986 kg/s; `mtr_assembly.jl` (zero source edits, D-16) converges to symmetric left/right channel outlets at 44.74°C with plate center at 49.18°C (T_plate > T_fluid as expected). The migrated builders compose and solve correctly under the new Channel API; only the plotting step is blocked.

**Fix location:** outside Phase 55. Either (a) re-add `Plots` to `[deps]` in `Project.toml` (and regenerate the manifest), (b) add an `examples/Project.toml` so example scripts use a separate environment, or (c) make the plotting step optional via `try/catch` so the simulation portion runs even without Plots. The decision is a project-level concern (binary size, CI cost, contributor onboarding) — not a Phase 55 architectural one.

**Scope-boundary justification (Rule):** plan 55-08's `files_modified` is `src/examples.jl`, `examples/simple_loop.jl`, `examples/mtr_assembly.jl`. Editing `Project.toml` to add Plots would violate the plan's exclusivity contract and is unrelated to the Channel API migration this plan delivers. The migration itself is fully verified — Task 1 build_loop solves with retcode=Success (commit f52b41d); Task 2 build_loop_pk emits the positive marker line; Task 3 simple_loop.jl + mtr_assembly.jl simulation portions converge.

## Discovered during 55-10 execution

### `test_pump.jl` PHY-05 errors at top-level — old `ch.thermal.T ~ ...` API

**Status:** Pre-existing (introduced by Wave 1 plans 55-01..55-03 — Channel dropped its single `thermal` port in favor of per-cell `T_wall_left[i]` external-input variables per CONTEXT D-01). Out of scope for plan 55-10.

**Symptom:** `julia --project=. test/runtests.jl` errors at `test/test_pump.jl:13` during PHY-05 "Pump fixed-flow mode" with:
```
ArgumentError: System ch5: variable thermal does not exist
```
The PHY-05 testset constructs an integration loop via `Channel(n=5, ...)` and pins the wall temperature via the legacy `ch5.thermal.T ~ 350.0` form (line 31). After Phase 55 D-01 the Channel has no `thermal` port; the new form is per-cell `[ch5.T_wall_left[i] ~ 350.0 for i in 1:n]...`.

**Fix location:** outside Phase 55 plan 55-10. The miss is symmetric to the COMP-02 issue logged in the 55-06 entry above (which 55-08 fixed for `src/examples.jl`). A future test-files-only sweep should also migrate `test/test_pump.jl` PHY-05 and any other test that still uses the legacy `ch.thermal.T ~ ...` pattern.

**Scope-boundary justification (Rule):** plan 55-10's `files_modified` is `test/test_integration.jl`, `test/test_point_kinetics.jl`, `test/runtests.jl`. Editing `test/test_pump.jl` would violate the plan's exclusivity contract. Plan 55-10 was authored to do exactly three things — create test_integration.jl, trim test_point_kinetics.jl, delete the four absorbed files & update runtests.jl — and all three completed cleanly. test_integration.jl runs green standalone (`julia --project=. test/test_integration.jl` exits 0 with 86 tests passing). test_point_kinetics.jl runs green standalone (`julia --project=. test/test_point_kinetics.jl` exits 0 with 1382 tests passing). Every `include()` in runtests.jl is reachable (the test_pump.jl error is a pre-existing top-level API mismatch *inside* the included file, not an `include()` LoadError).

### Sundials KINSOL segfault inside test_channels.jl

**Status:** Pre-existing native crash inside `kinLsDenseDQJac` (libsundials_kinsol.so) triggered by a `solve_steady` call from `test/test_channels.jl:699`. Non-deterministic — a re-run reached `test_pump.jl` (entry above) without segfaulting. Out of scope for plan 55-10.

**Symptom:** `julia --project=. test/runtests.jl` produces a `signal 11 (2): Segmentation fault` deep in Sundials' Jacobian-difference-quotient routine when test_channels.jl exercises a CAC isolation steady solve. The faulty stack ends in `_start` — a hard process death, not a Julia-level error. Native libraries (Sundials, KINSOL, libc) are involved; the code path is `solve_steady → SteadyStateDiffEq → NonlinearSolveBase → Sundials → KINSol → kinLsDenseDQJac` and the segfault sits inside the library.

**Fix location:** outside Phase 55. Likely a Sundials-version / Julia-1.12 native issue. Workaround: re-run `runtests.jl` (the crash is non-deterministic) or run individual test files. This is an environmental flake of the same family as VAL-01 Fourier numerical and NET-03 Cube KINSOL convergence (already documented in CONTEXT.md D-22 as tolerated pre-existing flakies).

**Scope-boundary justification (Rule):** Same as test_pump.jl above — `test/test_channels.jl` is outside plan 55-10's `files_modified`.
