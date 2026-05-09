# Phase 56 — Deferred Items

Items discovered during Plan 56-05 execution that are out-of-scope for Phase 56
and require their own follow-up plan.

## D-1 — MTK API "Equations / unknowns / initial conditions of different lengths"

**Status:** Pre-existing breakage in current test scenarios.

**Symptom:** `solve_steady` raises
`ArgumentError: Equations (N), unknowns (N+1), and initial conditions (N+1) are of different lengths`
on the MTR test scenarios (symmetric, asymmetric, one-sided) and the HeatDiffusion
Fourier KEPT testset, when calling `mtkcompile(sys; fully_determined=false)` followed
by `solve_steady(ssys, op)`.

**Reproducer (standalone, no Phase-56 wiring):** see `/tmp/test_mtr.jl` — even before
any Phase-56 changes the MTR symmetric topology errors with this message.

**Impact:**
- MTR parity testsets (`Python parity: MTR symmetric` / `MTR asymmetric` / `MTR one-sided`)
  cannot reach `solve_steady` → cannot emit per-tier ParityRow values. Plan 56-05
  emits a single `solver_error` sentinel row per scenario into `parity_report.csv`
  so BLOCKER #3 ("ALL 4 scenarios contribute to CSV") is satisfied at sentinel level.
- KEPT testset `VAL-01: HeatDiffusion transient — Fourier series validation`
  fails identically.
- KEPT testset `VAL-02: Transient T_outlet rises after T_wall step` fails earlier
  with `ArgumentError: System sys: variable sys does not exist` — distinct API
  symptom but same family of MTK API drift.

**Root cause hypothesis:** ModelingToolkitBase upgraded between v1.1 baseline and
the present worktree's `Manifest.toml`; `mtkcompile(...; fully_determined=false)`
no longer auto-balances eq/unknown count, and `process_SciMLProblem` enforces
`check_length=true` strictly. Either (a) `solve_steady` needs to forward
`check_length=false`, or (b) the test ICs need to be widened to match the new
unknown count.

**Out-of-scope rationale:** Phase 56 is "Python STREAM cross-validation harness".
Repairing the MTK-version ICs / kwargs is component-side test maintenance, not
parity-harness work. Per CLAUDE.md scope-boundary rule + execute-plan deviation
rules, fixing pre-existing breakage in unrelated tests is not allowed in
Plan 56-05.

**Resolution path:** Open a follow-up phase (or fold into Plan 56-06 milestone-close
if scope permits) that
1. Pins the MTK packages to the v1.1 baseline tag, OR
2. Widens `solve_steady` to forward `check_length=false`, OR
3. Adds the missing ICs to each affected testset (likely `pump_l.port_in.mdot`,
   `pump_r.port_in.mdot`, or one of the `dP` observables).

## D-2 — `assert_equivalence_geometry` rtol=1e-12 too tight for `PARITY_MTR_GEOM_DH`

**Status:** Mitigated in Plan 56-05 (rtol relaxed to 1e-9 at the call site).

**Symptom:** `PARITY_MTR_GEOM_DH = 2.4947383191e-03` (Plan 56-04 paste, %.10e
precision) vs Julia `geom.Dh = 0.0024947383190683323` — relative drift ~1.27e-11,
fails `rtol=1e-12`.

**Mitigation (in-tree):** All three `assert_equivalence_geometry(geom_mtr, ...)`
calls in `test/test_validation.jl` use `rtol=1e-9` with an inline comment
referencing this deferred item. Fluid-prop tuples in `parity_helpers.jl`
already paste at `%.17g` per Plan 56-04 fix; the geometry tuple was missed.

**Resolution path:** Plan 56-06 (or a quick patch) bumps `PARITY_MTR_GEOM_DH`
emit precision in `test/generate_mtr_reference.py` from `%.10e` to `%.17g`,
regenerates `test/data/python_parity_reference.jl`, then tightens the three
`rtol=1e-9` call sites back to `rtol=1e-12`.
