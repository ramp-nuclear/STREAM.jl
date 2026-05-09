# Phase 58 — Per-Scenario Diagnostic Table

> Locked column names per CONTEXT.md `<specifics>`:
> `(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)`
>
> All counts measured live this session via `julia --project=. scratch/diag_*.jl`
> against MTK 11.25.0 / MTKBase 1.34.0 / SciMLBase 2.155.1.

| scenario | n_eqs | n_unknowns | n_init_eqs | missing_kind | hypothesis | fix_sketch |
| -------- | ----- | ---------- | ---------- | ------------ | ---------- | ---------- |
| MTR symmetric (test_validation.jl:333) | 92 | 93 | 0 | unknowns_pin | `hd.power(t)` declared as `@variables` in `HeatDiffusion` (heat_diffusion.jl:145) but no equation closes it | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:374 |
| MTR asymmetric (test_validation.jl:504) | 92 | 93 | 0 | unknowns_pin | identical to MTR sym (single HD, two CAC, asymmetric inlet T) | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:544 |
| MTR one-sided (test_validation.jl:668) | 61 | 62 | 0 | unknowns_pin | identical to MTR sym (single HD, single CAC) | Add `hd.power ~ 1e4` to `conns` at test_validation.jl:706 |
| VAL-01 HD Fourier (test_validation.jl:842) | 50 | 51 | 0 | unknowns_pin | identical pattern; HD-only with `power=0.0`; no closing eq | Add `hd_v01.power ~ 0.0` to `conns_v01` at test_validation.jl:898 |
| VAL-02 two-plate (test_validation.jl:935) | 91 | 93 | 0 | unknowns_pin (×2) | TWO HD instances → two missing pins (Δ=-2) | Add `hd1.power ~ power_per_plate` AND `hd2.power ~ power_per_plate` at test_validation.jl:991 |
| VAL-02 transient T_wall step (test_validation.jl:295) | 11 | 11 | 0 | symbol_access (NOT determinacy) | `ssys.sys.T_wall_callable` access path raises `ArgumentError: System sys: variable sys does not exist`; correct path on compiled system is `ssys.T_wall_callable` (verified live) | Replace `ssys.sys.T_wall_callable` → `ssys.T_wall_callable` at test_validation.jl:317 |
| PointKinetics validation (test_validation.jl:1042) | 43 | 43 | 0 | NO_GAP | Δ=0 already (`build_loop_pk` has `power_eqs = [rods_fuel.power ~ pk.P * power_scale]` at examples.jl:651). KINSOL retcode=Failure / flag −7 is **numerical** non-convergence; existing transient fallback in test code (:1059, :1118, :1167) covers it. Out of Phase 58 scope. | No fix; verify VAL-PK-01..03 pass after upstream try/catch wrapper at :834 stops tripping |

---

## Live diagnostic output (verbatim)

### Canonical-builder baseline — `scratch/diag_baseline.jl`

```
=== Phase 58 — canonical builder determinacy baseline ===

build_loop()                    n_eqs=  11  n_unknowns=  11  Δ=0
                                n_init_eqs=0
build_loop_vertical()           n_eqs=  11  n_unknowns=  11  Δ=0
                                n_init_eqs=0
build_loop_transient()          n_eqs=  11  n_unknowns=  11  Δ=0
                                n_init_eqs=0
build_cube()                    n_eqs=  14  n_unknowns=  14  Δ=0
                                n_init_eqs=0
build_loop_lof_bypass()         n_eqs=  64  n_unknowns=  64  Δ=0
                                n_init_eqs=0

=== Determinacy contract test on build_loop() ===

mtkcompile(sys; fully_determined=true) — SUCCESS
  n_eqs=11
  n_unknowns=11
```

### Consolidated A/B/C/D/E/F — `scratch/diag_all_scenarios.jl`

```
=== Scenario A: MTR symmetric ===
  as-is                               Δ= -1  n_eqs=  92  n_unk=  93  fully_determined=true: FAIL
  with hd.power pin                   Δ=  0  n_eqs=  92  n_unk=  92  fully_determined=true: PASS

=== Scenario B: MTR asymmetric (different inlet T) ===
  as-is                               Δ= -1  n_eqs=  92  n_unk=  93  fully_determined=true: FAIL
  with hd.power pin                   Δ=  0  n_eqs=  92  n_unk=  92  fully_determined=true: PASS

=== Scenario C: MTR one-sided ===
  as-is                               Δ= -1  n_eqs=  61  n_unk=  62  fully_determined=true: FAIL
  with hd.power pin                   Δ=  0  n_eqs=  61  n_unk=  61  fully_determined=true: PASS

=== Scenario D: VAL-01 HD Fourier (HD only, both faces ConstantTemperature) ===
  as-is                               Δ= -1  n_eqs=  50  n_unk=  51  fully_determined=true: FAIL
  with hd.power pin                   Δ=  0  n_eqs=  50  n_unk=  50  fully_determined=true: PASS

=== Scenario E: VAL-02 two-plate one-channel (steady) ===
  as-is                               Δ= -2  n_eqs=  91  n_unk=  93  fully_determined=true: FAIL
  with hd.power pin (x2)              Δ=  0  n_eqs=  91  n_unk=  91  fully_determined=true: PASS

=== Scenario F: VAL-02 transient T_wall step (build_loop_transient) ===
  build_loop_transient(T_wall_fn=...) compiled. Δ=0  n_eqs=11  n_unk=11
  -- ssys.sys getproperty :T_wall_callable existence test:
     FAILED: ArgumentError: System sys: variable sys does not exist
     direct ssys.T_wall_callable -> T_wall_callable⋆
```

### Standalone Scenario D — `scratch/diag_val01_fourier.jl`

```
=== Scenario D: VAL-01 HD Fourier ===

-- as-is (no hd_v01.power pin) --
  Δ=-1  n_eqs=50  n_unknowns=51  n_init_eqs=0
  fully_determined=true: FAIL — StateSelection.ExtraVariablesSystemException

-- with hd_v01.power ~ 0.0 pin --
  Δ=0  n_eqs=50  n_unknowns=50  n_init_eqs=0
  fully_determined=true: PASS
```

### Standalone Scenario E — `scratch/diag_val02_twoplate.jl`

```
=== Scenario E: VAL-02 two-plate one-channel (steady) ===

-- as-is (no pins) --
  Δ=-2  n_eqs=91  n_unknowns=93  n_init_eqs=0
  fully_determined=true: FAIL — StateSelection.ExtraVariablesSystemException

-- with hd1.power ~ pwr AND hd2.power ~ pwr --
  Δ=0  n_eqs=91  n_unknowns=91  n_init_eqs=0
  fully_determined=true: PASS
```

### Standalone Scenario F — `scratch/diag_val02_transient.jl`

```
=== Scenario F: VAL-02 transient T_wall step ===

  Δ=0  n_eqs=11  n_unknowns=11  n_init_eqs=0   (NOT determinacy — Δ=0 already)

-- ssys.sys.T_wall_callable access path (test_validation.jl:317) --
  FAILED: ArgumentError: System sys: variable sys does not exist

-- ssys.T_wall_callable direct access (the working alternative) --
  OK — found T_wall_callable⋆

-- last(parameters(ssys)) (test_integration.jl:192 alt) --
  OK — found T_wall_callable
```

### MTR power-pin end-to-end verification — `scratch/diag_mtr_power_pin.jl`

(Already in tree; results recorded in 58-RESEARCH.md §3:)

```
mtkcompile(sys_mtr; fully_determined=true) -> SUCCESS
  n_eqs=92  n_unknowns=92
solve_steady retcode: Success
```
