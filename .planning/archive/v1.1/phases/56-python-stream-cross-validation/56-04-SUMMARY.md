---
plan: 56-04
title: Run Python generators and paste regenerated references
status: complete
wave: 2
commits:
  - 94de795 fix(56-02): correct per-cell wall-temp extraction in simple-loop generator
  - 7d5fbb9 fix(56-03): correct per-cell wall-temp extraction in MTR generator
  - 87bd54a fix(56-02): bump fluid-prop emit precision to %.17g for 1e-12 round-trip
  - 6ece20f feat(56-04): paste regenerated Python parity references
created: 2026-05-08
---

# Plan 56-04 — Run Python generators and paste references

## What shipped

| File | Status | Lines |
|------|--------|-------|
| `test/data/python_parity_reference.jl` | NEW | 674 |
| `test/parity_helpers.jl` | UPDATED (4 PYTHON_*_AT_REF lines + comment cleanup) | 274 |
| `test/generate_reference.py` | FIXED (twall scalar broadcast + %.17g precision) | 142 |
| `test/generate_mtr_reference.py` | FIXED (connected-side extraction + adiabatic convention + Dh→hydraulic_diameter) | 555 |

`test/data/python_parity_reference.jl` contains 65 `const PARITY_*` declarations covering all 4 scenarios across D-07 tiers (a)+(b)+(c)+(d).

## Where the generators ran

Both generators ran end-to-end on the developer's `stream-env` conda environment (the standard Python STREAM env at `~/projects/STREAM`). The generators were NOT runnable in the orchestrator's base Python because `scikits.odes` requires SUNDIALS via conda — the env-activation `source ~/miniforge3/etc/profile.d/conda.sh && conda activate stream-env` is recorded for future regenerations.

## Real bugs discovered & fixed during this plan

This plan surfaced **three** real bugs that Plans 56-02 and 56-03 missed. All were fixed before paste — no rtol widening or fake-data masking.

### Bug 1 — Plan 56-02: scalar wall-temp not broadcast to per-cell array

`ch_state[ChannelVar.twall_left]` returns whatever the funcs lambda returned. When `funcs={"T_left": lambda x: T_WALL_C}` is a constant, the stored value is a scalar — not a per-cell array. Plan 56-02 assumed it was iterable. Fix: detect scalar and broadcast to `[T_WALL_C] * N`.

### Bug 2 — Plan 56-03: misread plate auto-wiring

Plan 56-03's SUMMARY claimed `plate()` / `symmetric_plate()` / `one_sided_connection()` auto-wire `T_left` AND `T_right` via `_pair_connection` graph edges. **Wrong.** Per `stream/composition/mtr_geometry.py:38-66`, each MTR channel is wired to fuel on exactly ONE side (channel_L's RIGHT, channel_R's LEFT); the opposite wall is adiabatic — its `ChannelVar.twall_*` key is absent from the state dict.

Fix: extract from connected side only; emit `T_wall = T_cool` and `q_density = 0` for the adiabatic side (matches MTK's default zero-flux on unconnected thermal ports). `h` mirrors the connected side, matching Python STREAM's `_other_if_none` convention.

### Bug 3 — Plan 56-03: wrong attribute name `pipe_ch.Dh`

`EffectivePipe` exposes `hydraulic_diameter` (Python convention). `Dh` is the Julia `PipeGeometry` attribute. Was masked by Bug 2's KeyError until Bug 2 was fixed.

### Bug 4 — Plan 56-02: %.10f format truncates float64 below 1e-12 rtol

`mu(313.15)` Julia=6.5196977487873341e-04, Python-paste-via-%.10e=6.5196977488e-04. The 7-digit truncation creates a 1.27e-15 absolute / 1.94e-12 relative drift that masks as a real correlation disagreement. The fluid-prop correlations themselves agree bit-for-bit. Fix: `%.17g` for the 4 PYTHON_*_AT_REF tuples (per-cell arrays keep `%.10f` since parity_check tolerates much looser rtol there).

## Why the bugs slipped past Plans 56-02 and 56-03

Neither plan ran the generator end-to-end during execution. Plan 56-02's smoke check was Python-AST-parse + grep for const names — both pass with the buggy iteration. Plan 56-03's smoke check was the same. Without an end-to-end run against the actual `stream-env` conda environment, the runtime semantics of `ch_state` were never observed.

Lesson for future generator plans: include "execute and capture stdout" as a smoke step, not just "static parse".

## Verification

```
$ source ~/miniforge3/etc/profile.d/conda.sh && conda activate stream-env
$ cd test
$ python3 generate_reference.py     # exit 0, 139 lines stdout, 4 paste markers
$ python3 generate_mtr_reference.py # exit 0, 555 lines stdout, 8 paste markers
```

```
[Plan 56-04 smoke] python_parity_reference.jl loads cleanly with sane values
  T_out_simple    = 327.7894342808 K  (expected ~328 K, range 320-340) ✓
  mdot_simple     = 0.6092891722 kg/s (expected ~0.6, range 0.4-0.8) ✓
  T_plate_sym[5,2]= 322.1502242548 K  (expected ~322 K, range 318-330) ✓

[Plan 56-04 equiv] all 4 (of 5) equivalence checks pass at 1e-12 rtol
  ✓ assert_equivalence_fluid_props
  ✓ assert_equivalence_dittus_boelter
  ✓ assert_equivalence_blasius
  ✓ assert_equivalence_anchors
  (assert_equivalence_geometry deferred to Plan 05 — needs constructed PipeGeometry)
```

## Spot-check baseline (for future regeneration audits)

| Quantity | Value | Range |
|----------|-------|-------|
| `PARITY_SIMPLE_T_OUT` | 327.7894342808 K | 320–340 K |
| `PARITY_SIMPLE_MDOT` | 0.6092891722 kg/s | 0.4–0.8 kg/s |
| `PARITY_SIMPLE_DP` | (pump dP) | matches DP_PUMP closed-loop |
| `PARITY_MTR_SYM_T_PLATE[5,2]` | 322.1502242548 K | 318–330 K |
| `PYTHON_RHO_AT_REF[1]` | 991.3511479199999 kg/m³ (313.15 K) | bit-identical to Julia |

## Const names emitted (65 total)

- 4 geometry: `PARITY_MTR_GEOM_DH/AREA/WETPERIM/HEATED`
- 10 simple-loop: `PARITY_SIMPLE_T_OUT/MDOT/DP/T_CELLS/T_WALL_LEFT/T_WALL_RIGHT/H_TC_LEFT/H_TC_RIGHT/Q_DENSITY_LEFT/Q_DENSITY_RIGHT`
- 19 MTR symmetric: `PARITY_MTR_SYM_*` (×2 channels for tier b/c + plate matrix for tier d)
- 19 MTR asymmetric: `PARITY_MTR_ASYM_*`
- 11 MTR one-sided: `PARITY_MTR_ONESIDED_*`
- 4 fluid-prop tuples in `parity_helpers.jl`: `PYTHON_RHO/CP/MU/K_AT_REF`

Plan 56-05 will paste against these names.

## Adiabatic-side convention

For unconnected channel walls in MTR scenarios, the reference emits:

- `T_wall = T_cool` (steady-state physical BC under zero-flux)
- `q_density = 0`
- `h` mirrors the connected-side `h` (Python `_other_if_none` HTC convention)

This is NOT fabricated data — it is the documented physical BC at an adiabatic surface. Plan 05's parity_check should pass these quantities at CLEAN tier without any hard_ceiling widening.

## Deviations from plan

- Plan 56-04's task-text said to spawn a fix executor when generator bugs surface ("Return to Plan 56-02/56-03; do NOT patch in Task 1"). After consulting the user, all four bugs were fixed inline via a `general-purpose` investigator+fixer agent. The `fix(56-02)` and `fix(56-03)` commits cleanly attribute the fixes to the originating plans without retroactively rewriting Plan history.
- Plan 56-04 description said `assert_equivalence_fluid_props` MUST pass on first try at 1e-12 rtol. It did NOT — it caught Bug 4 (precision truncation). The fix (`%.17g`) was applied; the assertion now passes. This is a successful outcome of the equivalence checklist's purpose: catch generator-side issues BEFORE Plan 05's parity testsets surface them as confusing FAIL-tier rows.
