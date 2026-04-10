---
status: diagnosed
phase: 50-open-source-readiness
source: [50-01-SUMMARY.md, 50-02-SUMMARY.md, 50-03-SUMMARY.md, 50-04-SUMMARY.md]
started: 2026-04-10T08:00:00Z
updated: 2026-04-10T08:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. MIT LICENSE file
expected: A file named LICENSE exists at the repo root. Opening it shows standard MIT License text with "Copyright (c) 2026 Itay Benvenisti" and no placeholder or generic author.
result: pass

### 2. Project.toml metadata
expected: Project.toml has version = "0.9.0", a real 36-char UUID (not a placeholder like "a1b2c3d4-..."), authors = ["Itay Benvenisti <itaybnv@github.com>"], a repo field pointing to GitHub, and PackageCompiler only in [extras] (not in [deps] or [compat]).
result: pass

### 3. CI workflow file
expected: .github/workflows/ci.yml exists. Opening it shows a workflow triggered on push/PR to main, using julia-actions/setup-julia with version "1" (stable), ubuntu-latest, and no multi-version/multi-platform matrix.
result: pass

### 4. All tests pass (NET-03 Cube flow + VAL-01 Fourier)
expected: Running the test suite (julia --project=. test/runtests.jl) completes with all tests passing — specifically NET-03 Cube flow test and VAL-01 Fourier series transient test that were previously failing no longer error out.
result: issue
reported: "ERROR: Package NonlinearSolve not found in current path. Running julia --project=. test/runtests.jl fails because NonlinearSolve is in [extras] not [deps] — not available outside Pkg.test(). CI passes via julia-actions/julia-runtest but local direct invocation (documented in CLAUDE.md) fails."
severity: major

### 5. simple_loop.jl example runs
expected: Running `julia --project=. examples/simple_loop.jl` completes without error, prints T_outlet, mdot, and T_rise values, and saves a PNG to examples/output/. The output directory is created automatically if it doesn't exist.
result: pass

### 6. mtr_assembly.jl example runs
expected: Running `julia --project=. examples/mtr_assembly.jl` completes without error, prints plate center temperature and fluid outlet temperatures, and saves an axial temperature profile PNG to examples/output/.
result: issue
reported: "ERROR: Equations (92), unknowns (93), and initial conditions (93) are of different lengths. System is under-determined — one equation is missing. Fails at solve_steady call in mtr_assembly.jl:117."
severity: major

### 7. README.md content and structure
expected: README.md exists at repo root with at least 8 sections including: badges (CI + MIT), physics-first "What STREAM.jl Models" description, Quick Start with build_loop code example, Component Catalog table (6 components), Validation claim (1% tolerance), and a "Relationship to Python STREAM" section. No internal paths or credentials referenced.
result: pass

## Summary

total: 7
passed: 5
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Running julia --project=. test/runtests.jl completes with all tests passing"
  status: failed
  reason: "User reported: ERROR: Package NonlinearSolve not found in current path. NonlinearSolve is in [extras] not [deps] — unavailable outside Pkg.test(). CI passes but local direct invocation fails."
  severity: major
  test: 4
  root_cause: "No test/Project.toml exists. The [extras]/[targets] mechanism in root Project.toml only activates via Pkg.test(). Direct invocation (julia --project=. test/runtests.jl) only sees [deps], so using NonlinearSolve in test_resistors.jl fails. Fix: create test/Project.toml declaring NonlinearSolve and Test as deps."
  artifacts:
    - path: "test/Project.toml"
      issue: "missing — needs to be created with NonlinearSolve = 8913a72c-1f9b-4ce2-8d82-65094dcecaec and Test"
  missing:
    - "Create test/Project.toml with NonlinearSolve and Test deps"
  debug_session: ""

- truth: "Running julia --project=. examples/mtr_assembly.jl completes without error"
  status: failed
  reason: "User reported: ERROR: Equations (92), unknowns (93), and initial conditions (93) are of different lengths. System is under-determined — one equation is missing. Fails at solve_steady call in mtr_assembly.jl:117."
  severity: major
  test: 6
  root_cause: "HeatDiffusion declares `power` as an MTK @variables unknown (not a parameter). The constructor arg only sets its initial value, not a governing equation. mtr_assembly.jl conns never includes `rods.hd.power ~ POWER`, leaving power unconstrained. Fix: add `rods.hd.power ~ POWER` to the conns array."
  artifacts:
    - path: "examples/mtr_assembly.jl"
      issue: "conns array (lines 90-99) missing rods.hd.power ~ POWER equation"
    - path: "src/components/heat_diffusion.jl"
      issue: "power declared as @variables unknown at lines 111-114 — requires explicit governing equation at call site"
  missing:
    - "Add `rods.hd.power ~ POWER` to conns in examples/mtr_assembly.jl"
  debug_session: ""
