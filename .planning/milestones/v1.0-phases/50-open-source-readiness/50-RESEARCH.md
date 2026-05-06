# Phase 50: Open-Source Readiness - Research

**Researched:** 2026-04-10
**Domain:** Julia package open-source conventions, GitHub Actions CI, test failure root causes
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Target audience is nuclear engineers / thermal-hydraulics physicists — lead with what STREAM.jl models, not MTK internals
- **D-02:** Include a runnable `build_loop` example as the quick-start
- **D-03:** Installation section must note that the sysimage (`build_sysimage.sh`) is aspirational — it currently does not work reliably and should not be presented as a prerequisite
- **D-04:** Include a component catalog table: Channel, Pump, HeatDiffusion, PointKinetics, ChannelAndContacts, HeatExchanger — one-line description of what each models
- **D-05:** Include a validation summary: "Validated within 1% of Python STREAM across steady-state, transient, and point kinetics benchmarks"
- **D-06:** Include a "Relationship to Python STREAM" section explaining why Julia/MTK was chosen and linking to the Python original
- **D-07:** MIT License, copyright `2026 Itay Benvenisti`
- **D-08:** No Documenter.jl in this phase — docstrings (all 28 exports, complete since v0.5) are sufficient for API reference
- **D-09:** Add `examples/simple_loop.jl` — minimal forced-convection loop using `build_loop`, solve_steady, plot T_out
- **D-10:** Add `examples/mtr_assembly.jl` — HeatDiffusion + ChannelAndContacts composition workflow
- **D-11:** Existing `examples/lof_transient.jl` stays as-is
- **D-12:** Add `.github/workflows/ci.yml` — Julia stable, Ubuntu latest, push and PR to main
- **D-13:** Fix VAL-01 (Fourier series flaky) and NET-03 (Cube KINSOL failure) before CI is active
- **D-14:** No branch protection rules — CI is informational
- **D-15:** Bump version to `0.9.0`
- **D-16:** Generate a real UUID (replace placeholder `a1b2c3d4-e5f6-7890-abcd-ef1234567890`)
- **D-17:** Set `authors = ["Itay Benvenisti <itaybnv@github.com>"]`
- **D-18:** Add `repo = "https://github.com/itaybnv/STREAM.jl"` field
- **D-19:** Move `PackageCompiler` out of `[deps]` into `[extras]`/`[targets]` or remove

### Claude's Discretion
- Exact README prose, section ordering, and formatting
- Component catalog table layout
- Whether to include a badges section (Julia version, CI status, license)
- CI workflow file details (cache config, timeout settings)

### Deferred Ideas (OUT OF SCOPE)
- **Sysimage fix** — sysimage diagnostics and repair is a dedicated future phase
- **Documenter.jl site** — full documentation site with API reference and tutorials
</user_constraints>

---

## Summary

Phase 50 prepares STREAM.jl for public GitHub discovery: README, MIT LICENSE, two new example scripts, GitHub Actions CI, and Project.toml metadata cleanup. Two pre-existing test failures (VAL-01 Fourier series flaky test and NET-03 Cube KINSOL convergence failure) must be fixed before CI goes live, or CI will be permanently red.

The standard Julia package CI stack is well-established: `julia-actions/setup-julia@v2`, `julia-actions/cache@v2`, `julia-actions/julia-buildpkg@v1`, `julia-actions/julia-runtest@v1`. The Phase 50 CI is intentionally minimal (Julia stable, ubuntu-latest, push+PR to main) per D-12. No codecov, no multi-OS matrix, no nightly — those are discretionary additions the planner may include.

The two test failures have different root causes and different fixes. NET-03 (Cube KINSOL) is a solver-selection problem: the cube's 12-resistor network is a pure nonlinear algebraic system with weaker structure than the thermal loops; switching to `RobustMultiNewton` from NonlinearSolve.jl or improving the initial guess is the correct fix. The VAL-01 Fourier series test uses `NoInit` on an ODE that starts with a non-smooth IC; the flakiness likely arises from time-step scheduling hitting the early checkpoints before the solution has been refined to the requested tolerance — tightening `reltol`/`abstol` or adding `dense=true` for interpolation is the likely fix.

**Primary recommendation:** Execute the six deliverables in order: fix tests first (unblocks CI), then Project.toml metadata, then LICENSE, then README, then CI workflow, then examples.

---

## Standard Stack

### Core Julia Actions (CI)
| Action | Version | Purpose | Why Standard |
|--------|---------|---------|--------------|
| `actions/checkout` | `v4` | Clone repository | GitHub standard |
| `julia-actions/setup-julia` | `v2` | Install Julia, set version | Official Julia Actions org |
| `julia-actions/cache` | `v2` | Cache deps/registry | Official Julia Actions org |
| `julia-actions/julia-buildpkg` | `v1` | Run `Pkg.instantiate()` | Official Julia Actions org |
| `julia-actions/julia-runtest` | `v1` | Run `Pkg.test()` | Official Julia Actions org |

[VERIFIED: github.com/julia-actions org and JuliaLang/Example.jl ci.yml observed structure]

### Optional CI Additions (Claude's Discretion)
| Action | Version | Purpose | When to Use |
|--------|---------|---------|-------------|
| `julia-actions/julia-processcoverage` | `v1` | Generate lcov.info | If codecov is enabled |
| `codecov/codecov-action` | `v5` | Upload coverage | If coverage tracking is desired |

[ASSUMED: version numbers v5 for codecov — verify at time of writing]

### Julia CI Version Matrix (Minimal vs Full)
| Strategy | julia-version | os | Notes |
|----------|--------------|-----|-------|
| Phase 50 (D-12) | `['1']` | `ubuntu-latest` | Minimal — just stable |
| Standard full | `['lts', '1', 'pre']` | ubuntu + windows + macOS | What PkgTemplates generates |

**D-12 is explicit:** only Julia stable + ubuntu-latest. No multi-version matrix required.

---

## Architecture Patterns

### CI Workflow Structure
```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - uses: julia-actions/cache@v2
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```
[VERIFIED: consistent with JuliaLang/Example.jl and julia-actions org pattern]

**Key detail for STREAM.jl:** The test suite uses `DifferentialEquations`, `Sundials`, and `ModelingToolkit` — each with non-trivial precompilation time. The `julia-actions/cache@v2` step caches the depot (downloaded packages) across runs, cutting cold CI time from ~10 minutes to ~3 minutes. Without it, CI will be slow but functional.

**Concurrency (optional):** Add a `concurrency` block to cancel in-flight PR runs when new commits arrive:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```
[ASSUMED: concurrency syntax — verify against GitHub Actions docs]

### Project.toml Metadata Layout
```toml
name = "STREAM"
uuid = "<generated-uuid>"          # replace placeholder
version = "0.9.0"                  # D-15
authors = ["Itay Benvenisti <itaybnv@github.com>"]  # D-17

[deps]
DifferentialEquations = "..."
ModelingToolkit = "..."
OrdinaryDiffEq = "..."
Plots = "..."
QuadGK = "..."
Sundials = "..."
Symbolics = "..."
# PackageCompiler REMOVED from [deps]

[compat]
# keep as-is

[extras]
PackageCompiler = "9b87118b-4619-50d2-8e1e-99f35a4d4d9d"
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[targets]
test = ["Test"]
# Note: PackageCompiler NOT in test target — it is only listed in [extras]
# to document its presence without making it a test dependency.
```

**D-18 (repo field):** The Julia `Project.toml` spec does not define a `repo` field at the TOML level — Pkg ignores unknown fields. It is safe to add as metadata but has no functional effect. It is a documentation convention, not a Pkg feature. [VERIFIED: pkgdocs.julialang.org/v1/toml-files/ — no `repo` key mentioned in spec]

**D-16 (UUID):** Run `uuidgen` in bash. A sample run produced `ae5c9bb4-48ea-4b56-afca-b6a09d239d22` — do NOT use this value; generate a fresh one at implementation time.

**D-19 (PackageCompiler):** PackageCompiler is a build tool, not a runtime dependency. The correct treatment per Julia convention is to list it in `[extras]` (so it is recognized as a valid package reference) but NOT in the `[targets]` test list (it is not needed for testing). Alternatively, remove it from Project.toml entirely since `build_sysimage.sh` can be run by any developer who independently installs PackageCompiler. [VERIFIED: Julia Pkg.jl docs on [extras]/[targets] pattern]

### README Structure (Nuclear Engineering Audience)

Standard Julia package READMEs follow this ordering:
1. Badges row (CI, license, Julia compat)
2. One-sentence tagline
3. Short description / what it models
4. Quick-start code block
5. Component catalog
6. Validation summary
7. Installation
8. Relationship to Python STREAM
9. Contributing / license footer

**Badges:**
```markdown
[![CI](https://github.com/itaybnv/STREAM.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/itaybnv/STREAM.jl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
```
[ASSUMED: badge URLs — GitHub Actions badge URL format is well-known but verify repo URL matches D-18]

### Example Script Conventions

From `examples/lof_transient.jl` (canonical existing example):
- Header block: filename, brief description, `# Usage:` with exact `julia --project examples/FILE.jl` command
- `using STREAM` at top, explicit `using ModelingToolkit`, `using Plots` etc.
- `ENV["GKSwstype"] = "100"` + `gr()` for headless plot rendering
- Constants block clearly labeled
- Named sections (SECTION 1, SECTION 2, ...) for complex scripts
- `@info` / `println` for key result metrics

New examples (D-09, D-10) must follow this style.

### MIT License Text

Standard MIT License for D-07:
```
MIT License

Copyright (c) 2026 Itay Benvenisti

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
[VERIFIED: standard MIT License text from opensource.org]

---

## Test Failure Root Cause Analysis

### NET-03: Cube KINSOL Convergence Failure

**What the test does:** Assembles a 12-resistor cube network, solves steady state with `solve_steady` (which calls `SSRootfind(KINSOL())`), and checks that total mdot matches the analytical 5/6 R result.

**Root cause:** The initial guess `op = [ssys.pump.outlet.mdot => mdot_guess]` provides only one variable guess for a system with 12 resistors (12+ flow variables). KINSOL receives an under-specified initial point. For pure hydraulic networks (no thermal coupling), the Jacobian condition number is poorer than coupled thermal-hydraulic loops — KINSOL's line-search Newton can wander.

**Confirmed from codebase:** `solve_steady` calls `SSRootfind(KINSOL())` unconditionally. The test's `op` only sets `ssys.pump.outlet.mdot`. The cube's body-diagonal symmetry means there are three equivalent 1-resistor paths and six 2-resistor paths; without symmetric initialization, KINSOL may not find the symmetric solution.

**Fix options (in order of preference):**

1. **Solver swap:** Replace `KINSOL()` with `RobustMultiNewton()` from NonlinearSolve.jl for the cube test only, by passing `solver=SSRootfind(RobustMultiNewton())` to `solve_steady`. This avoids modifying the default solver used by all other tests. [VERIFIED: NonlinearSolve.jl docs — RobustMultiNewton is the recommended fallback for difficult nonlinear systems; CITED: docs.sciml.ai/NonlinearSolve/stable/solvers/nonlinear_system_solvers/]

2. **Improved initial guess:** Provide symmetry-aware guesses for all 12 edge flows, not just the pump outlet. Each of the three body-diagonal paths should carry `mdot_analytical/3`.

3. **Modify `solve_steady` to accept solver kwarg:** Already supported per the docstring (`solver=nothing` kwarg exists in signature). Pass `solver=SSRootfind(RobustMultiNewton())` in the test.

**Recommended fix for Phase 50:** Option 1 + Option 2 combined. In `test_resistors.jl` NET-03: expand the `op` dict with symmetric guesses for all 12 resistors, and pass `solver=SSRootfind(RobustMultiNewton())` to `solve_steady`.

**Dependency note:** `RobustMultiNewton` is in `NonlinearSolve.jl`, which is already an indirect dependency via `DifferentialEquations`. No new `[deps]` entry needed. [ASSUMED: NonlinearSolve is already available via DifferentialEquations transitive deps — verify with `using NonlinearSolve` in the Julia REPL]

### VAL-01 Fourier Series Flaky Test

**What the test does:** Builds an isolated `HeatDiffusion` plate with `ConstantTemperature` BCs, starts at uniform T0=400 K, lets it decay to T_wall=300 K, and compares `T_center(t)` at 4 checkpoints against the analytical Fourier series. Uses `Rodas5P` with `NoInit`, `reltol=1e-6`, `abstol=1e-8`, `saveat=t_checkpoints`.

**Root cause of flakiness:** The `saveat` mechanism in DifferentialEquations causes the solver to hit each checkpoint exactly. However, with `NoInit` the solver starts from a potentially non-smooth initial state (uniform plate IC). At the first checkpoint `t = 0.5*tau_v01 ≈ 0.001 s`, the plate is still in a steep transient. The adaptive Rodas5P step-size control may take a large initial step (driven by the smooth ODE structure) that overshoots the first checkpoint. After dense output interpolation, the interpolated value may differ from the ODE solution by more than the 1% tolerance at this early time.

The flakiness is version-dependent because the adaptive step controller behavior has changed across OrdinaryDiffEq versions (the project has `⌃ [1dea7af3] OrdinaryDiffEq v6.109.0` with newer versions available).

**Fix options:**

1. **Tighten tolerances:** Change `reltol=1e-7`, `abstol=1e-9`. At 1% tolerance on a 100 K drop, the absolute error budget is 1 K — tight tolerances should absorb early-checkpoint sensitivity. [ASSUMED: tightening alone may be sufficient — needs empirical verification]

2. **Add dense output:** Pass `dense=true` (default for ODE solvers) and ensure interpolation is smooth at early times. Actually the default is `dense=true` unless overridden; the existing test does not disable it. The issue is that `NoInit` skips initialization — the very first step's "consistent IC" assumption may not hold for the pure diffusion DAE structure.

3. **Replace `NoInit` with `ShampineCollocationInit()`:** `NoInit` is documented as causing "unstable steps following initialization." For a pure ODE (no algebraic constraints in the plate-only system), removing `NoInit` and letting the solver initialize normally is correct and safer. [CITED: DifferentialEquations.jl docs on NoInit warning]

4. **Loosen the early-checkpoint assertion:** Assert only the later checkpoints (tau, 2*tau, 5*tau) where the Fourier series has converged enough that solver accuracy dominates. The 0.5*tau checkpoint is most sensitive and drives the flakiness.

**Recommended fix for Phase 50:** Option 3 + Option 1. Remove `NoInit` from the Fourier test (it is not needed for a pure ODE — only DAE initialization problems require it), and tighten tolerances to `reltol=1e-8`, `abstol=1e-10`. The plate-only test has no DAE constraints so the default initialization is correct.

**Critical constraint:** The fix must not regress VAL-02 (transient T_outlet rises after T_wall step) which uses `NoInit` legitimately for a mixed ODE/parameter system. Change only the Fourier test.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CI workflow setup | Custom Docker + shell scripts | `julia-actions` (setup-julia, cache, buildpkg, runtest) | Maintained by julia-actions org, handles Julia-specific caching |
| Badge generation | Manual SVG | shields.io URLs | Dynamic, auto-updates with CI status |
| UUID generation | Any deterministic algorithm | `uuidgen` (system command) | UUIDs must be globally unique; `uuidgen` uses RFC 4122 |
| Nonlinear system fallback | Custom Newton iteration | `RobustMultiNewton` from NonlinearSolve.jl | Polyalgorithm with trust-region + line-search; already available |

**Key insight:** The julia-actions stack is maintained by the JuliaCI organization and is what PkgTemplates generates automatically — there is no reason to diverge from it.

---

## Common Pitfalls

### Pitfall 1: CI Runs But Never Passes (KINSOL / Flaky Tests)
**What goes wrong:** CI is added before pre-existing test failures are fixed. CI immediately goes red and stays red, training developers to ignore it.
**Why it happens:** NET-03 and VAL-01 are known failures; adding CI exposes them to every push.
**How to avoid:** Fix both tests in the same wave or prior wave as CI addition. D-13 is a locked decision for this reason.
**Warning signs:** If `julia --project=. test/runtests.jl` locally shows any non-Success retcodes, do not add CI yet.

### Pitfall 2: Placeholder UUID in Released Package
**What goes wrong:** `a1b2c3d4-e5f6-7890-abcd-ef1234567890` is a known placeholder. If the package is ever submitted to the Julia General Registry, this UUID will conflict or be rejected.
**Why it happens:** The UUID was set during early project scaffolding and never updated.
**How to avoid:** Run `uuidgen` and replace the placeholder. This must be done before any public release. [VERIFIED: JuliaRegistries/General requires unique UUID per package]

### Pitfall 3: PackageCompiler in [deps] Inflates User Install
**What goes wrong:** Users who `Pkg.add("STREAM")` (or `Pkg.dev(...)`) will have PackageCompiler installed as a runtime dependency. PackageCompiler is a large build tool; it has LLVM as a transitive dependency.
**Why it happens:** It was added to `[deps]` during sysimage development.
**How to avoid:** Remove from `[deps]`, add only to `[extras]` if needed as a documented optional tool.

### Pitfall 4: README Quick-Start That Requires Sysimage
**What goes wrong:** If the README presents `./build_sysimage.sh` as Step 1, users on non-WSL2 systems (or who encounter the OOM issue) cannot proceed.
**Why it happens:** Sysimage is a performance optimization, not a functional requirement.
**How to avoid:** D-03 is explicit: sysimage is "optional performance optimization, currently in progress." The quick-start must work with plain `julia --project=.`.

### Pitfall 5: julia-actions/cache Permissions Failure
**What goes wrong:** The `julia-actions/cache` action requires write permission to the GitHub Actions cache. Without the `permissions: contents: read` and `packages: write` block, caching silently fails on some repo configurations.
**Why it happens:** GitHub Actions default permissions may be restrictive for some org settings.
**How to avoid:** Add explicit `permissions` block to the CI job. [ASSUMED: specific permissions required — verify against julia-actions/cache README]

### Pitfall 6: NoInit on Pure ODE Causes Flaky Assertions
**What goes wrong:** `SciMLBase.NoInit()` is correct for DAE initialization but degrades accuracy for pure ODEs — the first adaptive step may be too large, causing interpolation error at early-time checkpoints.
**Why it happens:** `NoInit` was copied from the transient solver pattern where it is needed.
**How to avoid:** Use `NoInit` only when there are algebraic constraints (DAE systems). Remove it from the Fourier plate test which is a pure ODE.

---

## Code Examples

### Minimal CI Workflow (D-12)
```yaml
# Source: julia-actions org pattern, JuliaLang/Example.jl structure
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - uses: julia-actions/cache@v2
      - uses: julia-actions/julia-buildpkg@v1
      - uses: julia-actions/julia-runtest@v1
```

### NET-03 Fix Pattern
```julia
# In test/test_resistors.jl, NET-03 testset
# Expanded initial guess (symmetric cube: each path carries mdot/3)
mdot_analytical = dP_val / (5.0/6.0 * R_val)
mdot_per_branch = mdot_analytical / 3.0
op = [
    ssys.pump.outlet.mdot => mdot_analytical,
    ssys.r01.inlet.mdot  => mdot_per_branch,
    ssys.r02.inlet.mdot  => mdot_per_branch,
    ssys.r04.inlet.mdot  => mdot_per_branch,
    # ... remaining resistors
]
# Use RobustMultiNewton as fallback solver
using NonlinearSolve
sol = solve_steady(ssys, op; solver=SSRootfind(RobustMultiNewton()))
```
[ASSUMED: exact variable names in ssys — verify by inspecting build_cube return value]

### VAL-01 Fourier Fix Pattern
```julia
# In test/test_validation.jl, VAL-01 Fourier testset
# Remove NoInit — pure ODE (HeatDiffusion plate with ConstantTemperature BCs)
prob_v01 = ODEProblem(ssys_v01, op_ic_v01, tspan_v01; warn_initialize_determined=false)
sol_v01 = solve(prob_v01, Rodas5P();   # NoInit removed
                reltol=1e-8, abstol=1e-10,  # tightened
                saveat=t_checkpoints)
```
[ASSUMED: removing NoInit is sufficient — empirical verification needed at implementation time]

### Example Script Header Pattern
```julia
# examples/simple_loop.jl
# Minimal forced-convection loop: steady-state solve and outlet temperature plot.
#
# Usage:
#   julia --project examples/simple_loop.jl
#
# What this script demonstrates:
#   1. Build a single-channel loop with build_loop().
#   2. Solve steady state with solve_steady().
#   3. Print T_out and mdot; save a temperature profile plot.

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using Plots

ENV["GKSwstype"] = "100"
gr()
```

---

## Runtime State Inventory

This is a documentation/metadata phase — no runtime state is being renamed or migrated. Section is not applicable.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All | Yes | 1.10+ (Manifest.toml) | — |
| git / GitHub Actions | CI workflow | Yes (remote) | — | — |
| uuidgen | D-16 UUID generation | Yes (linux) | — | `python3 -c "import uuid; print(uuid.uuid4())"` |
| NonlinearSolve.jl | NET-03 fix (RobustMultiNewton) | Yes (transitive via DifferentialEquations) | bundled | — |

**Missing dependencies with no fallback:** None.

**Note on NonlinearSolve availability:** NonlinearSolve.jl is a transitive dependency of DifferentialEquations.jl which is already in `[deps]`. It does not need to be added explicitly. `using NonlinearSolve` in a test or in `solvers.jl` will resolve from the existing depot. [ASSUMED: verify with `]status NonlinearSolve` in the STREAM project environment]

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` (no version — stdlib) |
| Config file | none — tests invoked via `Pkg.test()` which runs `test/runtests.jl` |
| Quick run command | `julia --project=. test/runtests.jl` (with sysimage if available) |
| Full suite command | `julia --project=. test/runtests.jl` |

### Phase Deliverables Verification Map

| Deliverable | Verification Method | Automated? |
|-------------|--------------------|-----------:|
| NET-03 fix | `julia --project=. test/test_resistors.jl` — retcode Success + 1% tolerance | Yes |
| VAL-01 Fourier fix | `julia --project=. test/test_validation.jl` — all 4 checkpoints pass | Yes |
| Full test suite still passes | `julia --project=. test/runtests.jl` — no regressions | Yes |
| Project.toml metadata | `julia -e 'using Pkg; Pkg.status()'` shows version 0.9.0; grep UUID not placeholder | Manual |
| LICENSE file | `cat LICENSE` — MIT text with 2026 Itay Benvenisti | Manual |
| README.md | Human review: badges render, build_loop example is runnable, component catalog complete | Manual |
| CI workflow | Push a commit to main (or open a PR) — GitHub Actions tab shows green | Manual (push) |
| examples/simple_loop.jl | `julia --project=. examples/simple_loop.jl` exits 0 | Manual |
| examples/mtr_assembly.jl | `julia --project=. examples/mtr_assembly.jl` exits 0 | Manual |

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. The fixes are changes to existing test files, not new files.

---

## Open Questions (RESOLVED)

1. **Does `RobustMultiNewton` require explicit `using NonlinearSolve`?**
   - **RESOLVED:** Plan 50-02 Task 1 adds `using NonlinearSolve` explicitly to `test_resistors.jl`. Safe regardless of re-export status.

2. **Is `repo` a recognized Project.toml field?**
   - **RESOLVED:** Plan 50-01 adds it as D-18 specifies. Pkg ignores unknown fields; the entry is harmless documentation.

3. **Will removing `NoInit` from VAL-01 break anything?**
   - **RESOLVED:** Plan 50-02 Task 1 removes `NoInit` and tightens tolerances to `reltol=1e-8, abstol=1e-10`. The plate-only system is a pure ODE with no algebraic constraints — NoInit is unnecessary and harmful per DifferentialEquations.jl docs.

4. **Do the example scripts need `Pkg.activate` calls?**
   - **RESOLVED:** Plan 50-03 follows `lof_transient.jl` convention — no `Pkg.activate`, rely on `julia --project=.` from repo root, documented in script header.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `RobustMultiNewton` is available via transitive NonlinearSolve dep — no new [deps] entry needed | NET-03 fix, Environment Availability | Would need to add NonlinearSolve to [deps] |
| A2 | Removing `NoInit` from the Fourier plate test is sufficient to resolve flakiness | VAL-01 fix, Code Examples | May need additional tolerance tightening or solver change |
| A3 | NET-03 fix requires both better initial guess AND solver change | Code Examples | May only need one; over-engineering if solver change alone works |
| A4 | `concurrency` block syntax for CI is correct | Architecture Patterns (CI) | Workflow may fail to parse if syntax is wrong — verify against GitHub Actions docs |
| A5 | Codecov action version is v5 | Standard Stack (Optional CI) | Wrong version pin causes CI warning |
| A6 | `julia-actions/cache@v2` requires no special permissions block for public repos | Common Pitfalls | Cache silently fails, CI is slow but functional |

---

## Sources

### Primary (HIGH confidence)
- [julia-actions org](https://github.com/julia-actions) — setup-julia@v2, cache@v2, buildpkg@v1, runtest@v1 action names and versions
- [JuliaLang/Example.jl ci.yml structure](https://github.com/JuliaLang/Example.jl/blob/master/.github/workflows/ci.yml) — confirmed workflow structure
- [pkgdocs.julialang.org/v1/toml-files/](https://pkgdocs.julialang.org/v1/toml-files/) — Project.toml required/optional fields
- [NonlinearSolve.jl docs — RobustMultiNewton](https://docs.sciml.ai/NonlinearSolve/stable/solvers/nonlinear_system_solvers/) — solver recommendation
- Codebase inspection: `test/test_validation.jl` (Fourier test code, NoInit usage), `test/test_resistors.jl` (NET-03 code), `src/solvers.jl` (KINSOL call), `src/STREAM.jl` (exports)

### Secondary (MEDIUM confidence)
- [DifferentialEquations.jl docs on NoInit](https://docs.sciml.ai/DiffEqDocs/stable/basics/common_solver_opts/) — NoInit warning about unstable steps
- [Steady State Solvers](https://docs.sciml.ai/DiffEqDocs/stable/solvers/steady_state_solve/) — SSRootfind + KINSOL pattern

### Tertiary (LOW confidence)
- A1-A6 in Assumptions Log — inferences from code + docs, not directly verified in this session

---

## Metadata

**Confidence breakdown:**
- Standard stack (CI actions): HIGH — verified against JuliaLang/Example.jl and julia-actions org
- Architecture (CI workflow): HIGH — consistent with observed examples
- Project.toml fields: HIGH — verified against pkgdocs.julialang.org
- Test failure root causes: MEDIUM — analysis from code inspection; fix approach is ASSUMED pending empirical verification
- Pitfalls: MEDIUM-HIGH — based on combination of codebase inspection and Julia ecosystem knowledge

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (stable ecosystem — julia-actions versions change rarely)
