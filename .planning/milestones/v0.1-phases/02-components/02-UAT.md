---
status: resolved
phase: 02-components
source: [02-01-SUMMARY.md, 02-02-SUMMARY.md, 02-03-SUMMARY.md]
started: 2026-03-12T01:45:00Z
updated: 2026-03-12T04:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. STREAM loads with all four component exports
expected: Run `using STREAM; import STREAM: Channel, Pump, Friction, Gravity` in a Julia session. No error is thrown. All four names resolve without UndefVarError or method conflict with Base.Channel.
result: pass

### 2. Channel instantiates with correct equation count
expected: |
  Run:
  ```julia
  using STREAM; import STREAM: Channel
  ch = Channel(name=:ch, n=5, L=1.0, D=0.01, A=7.85e-5, mdot_0=0.1, cp_0=4182.0)
  length(equations(ch))
  ```
  Returns 36 (6×5 + 6 port-wiring/scalar equations). Exactly 5 equations are ODEs (contain a Differential term).
result: issue
reported: "MethodError: Channel only accepts (name, n, L, D, A) — mdot_0 and cp_0 are unsupported keyword arguments. Corrected call Channel(name=:ch, n=5, L=1.0, D=0.01, A=7.85e-5) works and returns 36 equations."
severity: major

### 3. Channel compiles in isolation and exposes per-cell observables
expected: |
  Run:
  ```julia
  sys = mtkcompile(ch; fully_determined=false)
  obs = observed(sys)
  ```
  Completes without error. `obs` contains per-cell variables Re[i], Nu[i], h_tc[i], v[i], q_wall[i] for i=1..5, plus scalar T_out and dP.
result: pass

### 4. Pump instantiates and imposes constant pressure rise
expected: |
  Run:
  ```julia
  import STREAM: Pump
  p = Pump(name=:p, dP_pump=1000.0)
  eqs = equations(p)
  ```
  Instantiates without error. One equation sets `port_out.P - port_in.P ~ dP_pump` (or equivalent). `mtkcompile(p; fully_determined=false)` completes without error.
result: issue
reported: "UndefKeywordError: keyword argument `dP` not assigned — Pump uses `dP` not `dP_pump`"
severity: major

### 5. Friction instantiates with Darcy-Weisbach and Blasius observables
expected: |
  Run:
  ```julia
  import STREAM: Friction
  f = Friction(name=:f, L=1.0, D=0.01, A=7.85e-5)
  sys = mtkcompile(f; fully_determined=false)
  obs = observed(sys)
  ```
  Instantiates without error. Observed variables include Re and f (friction factor). Equations include Blasius correlation `0.3164 * Re^(-0.25)` and Darcy-Weisbach pressure drop.
result: pass

### 6. Gravity instantiates with hydrostatic pressure equation
expected: |
  Run:
  ```julia
  import STREAM: Gravity
  g = Gravity(name=:g, H=1.0, A_grav=7.85e-5)
  mtkcompile(g; fully_determined=false)
  ```
  Instantiates without error. Equations contain `rho_water(...) * 9.80665 * H` hydrostatic term. mtkcompile succeeds.
result: issue
reported: "UndefKeywordError: keyword argument `A` not assigned — Gravity uses `A` not `A_grav`"
severity: major

### 7. Full test suite passes (34/34 green)
expected: |
  Run `julia --project=. -e 'using Pkg; Pkg.test()'` from the project root.
  Output shows 34 tests pass, 0 failures, 0 errors. Both Phase 1 (25 tests) and Phase 2 (9 tests) sections are green.
result: pass

## Summary

total: 7
passed: 6
issues: 3
pending: 0
skipped: 0

## Gaps

- truth: "Channel constructor kwarg names match PLAN documentation (mdot_0, cp_0 available or clearly absent by design)"
  status: resolved
  reason: "User reported: MethodError: Channel only accepts (name, n, L, D, A) — mdot_0 and cp_0 are unsupported keyword arguments"
  severity: major
  test: 2
  root_cause: "Channel(; name, n, L, D, A) is the actual signature — mdot_0 and cp_0 were test authoring errors (never in the PLAN spec). Not a code bug; UAT test was wrong. No fix needed for Channel."
  artifacts:
    - path: "src/components.jl"
      issue: "Channel signature line 15: (name, n, L, D, A) — correct as implemented"
  missing: []
  debug_session: ""

- truth: "Pump constructor kwarg is named consistently with its MTK parameter (dP_pump at construction site)"
  status: resolved
  reason: "User reported: UndefKeywordError: keyword argument `dP` not assigned — Pump uses `dP` not `dP_pump`"
  severity: major
  test: 4
  root_cause: "Pump(; name, dP) uses `dP` as constructor kwarg but stores it as MTK parameter `dP_pump` internally (line 86). Constructor arg name `dP` is ambiguous — Phase 3 users assembling a loop need to know to pass `dP=` not `dP_pump=`. API inconsistency: internal MTK param name differs from constructor arg name."
  artifacts:
    - path: "src/components.jl"
      issue: "line 84: function Pump(; name, dP) — kwarg is `dP`, but line 86 creates parameter `dP_pump = dP`"
  missing:
    - "Either rename constructor kwarg to `dP_pump` to match the MTK parameter, or document the discrepancy"
  debug_session: ""

- truth: "Gravity constructor kwarg is named consistently with its MTK parameter (A_grav at construction site)"
  status: resolved
  reason: "User reported: UndefKeywordError: keyword argument `A` not assigned — Gravity uses `A` not `A_grav`"
  severity: major
  test: 6
  root_cause: "Gravity(; name, H, A) uses `A` as constructor kwarg but stores it as MTK parameter `A_grav` internally (line 126-127). Same API inconsistency as Pump: constructor arg name differs from MTK param name. Also inconsistent with Friction which uses `A` → `A_f`, and Channel which uses `A` → `A_ch`."
  artifacts:
    - path: "src/components.jl"
      issue: "line 124: function Gravity(; name, H, A) — kwarg is `A`, but line 127 creates parameter `A_grav = A`"
  missing:
    - "Standardize: either all constructors use descriptive kwarg names (dP_pump, A_grav) or all use short names (dP, A) — currently mixed"
  debug_session: ""
