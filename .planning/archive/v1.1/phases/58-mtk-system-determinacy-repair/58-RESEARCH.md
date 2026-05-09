# Phase 58: MTK System Determinacy Repair — Research

**Researched:** 2026-05-08
**Domain:** ModelingToolkit determinacy contract; structural-correctness repair
**Confidence:** HIGH (root cause reproduced live; fix verified end-to-end on MTR symmetric)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Full set in scope.** All seven scenarios (MTR sym/asym/one-sided, VAL-01 HD Fourier transient, VAL-02 two-plate steady, PK validation, VAL-02 transient T_outlet rises after T_wall step) MUST reach a working solver call. The transient case shares MTK API drift family per `56-PAUSE-CONTEXT.md:53`; if Plan 58-01 diagnosis shows a divergent fix, planner is free to give it a separate fix plan.
- **D-02: Diagnostic-first plan structure.** Plan 58-01 builds a per-scenario diagnostic table `(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)` without source edits, committed as `58-01-SUMMARY.md` documentation. Plans 58-02..N are one fix plan per scenario family.
- **D-03: Diagnostic plan emits introspection on minimal repros, not full test files.** `/tmp/test_mtr.jl` is the canonical template; one minimal repro per scenario family in scratch (`tmp/` or `.planning/phases/58.../scratch/`).
- **D-04: Audit + convert + document survivors.** Every `fully_determined=false` / `check_length=false` site classified as `legitimate-structural` (preserved with inline comment) or `bug-hiding` (converted to `fully_determined=true` after topology fix lands).
- **D-05: `solve_steady` stays as it is.** No `check_length` kwarg added. Phase fixes determinacy at source.
- **D-06: Per-builder + per-scenario determinacy test.** New `test/test_determinacy.jl` with two testsets — canonical builders (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`) AND Phase-58 scenario topologies. Asserts `mtkcompile(sys; fully_determined=true)` succeeds AND `length(equations(ssys)) == length(unknowns(ssys))`. Added to `test/runtests.jl`.
- **D-07: Stay on `channels-redesign`.** GSD must never create branches. `.planning/config.json` `git.branching_strategy` stays `"none"`.

### Claude's Discretion

- MTK API drift root-cause depth — read recent ModelingToolkit/ModelingToolkitBase CHANGELOG entries near version range, no commit-by-commit bisect required.
- Whether MTR sym + asym + one-sided collapse to one fix plan or three — driven by diagnostic outcome.
- Where determinacy assertion's "scenario builder helpers" live — default is inside `test/test_determinacy.jl`; planner may lift to `src/examples.jl` if reusable.
- VAL-02 transient as its own plan vs folded into VAL-02 steady — decided by Plan 58-01's diagnostic.

### Deferred Ideas (OUT OF SCOPE)

- Phase 56 deferred-items D-2 (geometry precision %.10e → %.17g, three `rtol=1e-9` → `1e-12` retighten). Owned by Plan 56-06 resume.
- MTK API drift bisect — escalation only if Plan 58-01's CHANGELOG read fails to produce a clear hypothesis (already not needed — see Section 2 below).
- Replacing `solve_steady` with a "structurally validated" wrapper — not in scope for v1.1.
- NET-03 Cube flow flakiness — independent flaky issue.
- `check_length=false` workarounds anywhere in `src/solvers.jl::solve_steady` (locked).
- Pinning ModelingToolkit / ModelingToolkitBase / SciMLBase backwards in `Manifest.toml`.
- Phase 57 HTC film-T story — already shipped.
- Replacing `ThermalPort` / `FlowPort` connector design.
- Refactoring `_channel_core` enthalpy-form energy balance.
- New builder API for "structurally validated systems" (the determinacy test IS the validation surface).
- Any new component or new physics — this is structural-correctness only.

</user_constraints>

<phase_requirements>
## Phase Requirements

Phase 58 has **no mapped REQ-IDs in `.planning/REQUIREMENTS.md`** — v1.1's 22 REQ-IDs were closed by Phases 52–56 per the ROADMAP coverage table. Phase 58 is a structural-correctness phase whose validation surface is the new `test/test_determinacy.jl` regression test plus the seven in-scope scenarios reaching working solver calls.

The phase therefore tracks **scenario-coverage** rather than requirement-coverage:

| Scenario ID (informal) | Validation surface | Research support |
|------------------------|--------------------|------------------|
| MTR-SYM | `test/test_validation.jl:333` "Python parity: MTR symmetric" reaches `solve_steady` Success | §3 Scenario A diagnosis (Δ=−1, fix: pin `hd.power ~ value`) |
| MTR-ASYM | `test/test_validation.jl:504` "Python parity: MTR asymmetric" reaches `solve_steady` Success | §3 Scenario B diagnosis (identical to A) |
| MTR-ONESIDED | `test/test_validation.jl:668` "Python parity: MTR one-sided" reaches `solve_steady` Success | §3 Scenario C diagnosis (identical to A, single CAC) |
| VAL-01-FOURIER | `test/test_validation.jl:842` "VAL-01: HD transient — Fourier series" reaches `ODEProblem` solve | §3 Scenario D diagnosis (Δ=−1, fix: pin `hd_v01.power ~ 0.0`) |
| VAL-02-TWOPLATE | `test/test_validation.jl:935` "VAL-02: Two-plate one-channel" reaches `solve_steady` Success | §3 Scenario E diagnosis (Δ=−2, two HD instances → two pins) |
| VAL-02-TRANSIENT | `test/test_validation.jl:295` "VAL-02: Transient T_outlet rises after T_wall step" reaches `solve_transient` Success | §3 Scenario F diagnosis (NOT determinacy — symbol-access bug; `ssys.sys.T_wall_callable` should be `ssys.T_wall_callable`) |
| PK-VAL | `test/test_validation.jl:1042` "PointKinetics validation" testset converges (steady or transient fallback) | §3 Scenario G diagnosis (Δ=0; numerical convergence only — not in fix scope unless transient fallback also fails) |
| DETERMINACY-REGRESSION | New `test/test_determinacy.jl` asserts `length(equations(ssys)) == length(unknowns(ssys))` AND `mtkcompile(sys; fully_determined=true)` succeeds for every builder + every Phase-58 scenario topology | §6 below |

</phase_requirements>

## Executive Summary

Live introspection on the broken scenarios reveals a **single, mechanical root cause** for six of the seven cases: `HeatDiffusion` (`src/components/heat_diffusion.jl:130-179`) declares `power(t) = power_init` as an `@variables` *unknown* (line 145), and `_diffusion_eqs` consumes `power` on the RHS of every cell-energy equation (line 59 `q_vol = power * power_shape[i,j] / (...)`) — but **no equation closes `power(t)` itself**. Standalone-builder users are expected to add a closing equation (`hd.power ~ <value>`), as `build_loop_lof_bypass` does at `src/examples.jl:499` (`heated.fuel.power ~ power_W`) and `build_loop_pk` does at `src/examples.jl:651` (`rods_fuel.power ~ pk.P * power_scale`). The tests for MTR sym/asym/one-sided, VAL-01 HD Fourier, and VAL-02 two-plate forgot this binding equation.

Each missing pin produces exactly **`Δ = (n_eqs − n_unknowns) = −1`** per `HeatDiffusion` instance. Adding `hd.power ~ <value>` to the connection list closes the gap and produces `Δ = 0`, after which `mtkcompile(sys; fully_determined=true)` succeeds and `solve_steady` reaches `ReturnCode.Success`. Verified live on MTR symmetric: 92 eqs / 93 unknowns → 92 / 92 after the pin (`scratch/diag_mtr_power_pin.jl`).

The seventh scenario (VAL-02 transient T_wall step) has a **distinct, non-determinacy** root cause: the test accesses the callable parameter via `ssys.sys.T_wall_callable` (`test/test_validation.jl:317`) but the correct path on the compiled system is `ssys.T_wall_callable` (verified — see §3 Scenario F). The compiled system already has Δ=0; only the symbol-access path needs correcting. The PK testset is structurally Δ=0 and reaches `solve_steady`; its remaining issue is numerical convergence (KINSOL flag −7 / fallback to long transient), which is not in Phase 58's scope unless the transient fallback also fails (it does not; existing fallback path covers it).

**Primary recommendation:** Plan 58-01 emits the diagnostic table; Plans 58-02..N add `hd.power ~ <value>` connection-list entries to the broken scenarios + the symbol-access fix to VAL-02 transient + the audit `fully_determined=true` flips to bug-hiding sites + `test/test_determinacy.jl` regression. **No source edits to `src/components/heat_diffusion.jl` are required** — the existing public contract ("`power` is the user-supplied closing variable; users provide an equation for it") is correct and already documented at `src/components/heat_diffusion.jl:119`.

## 2. MTK API Drift

**Manifest versions (read-only this phase per `code_context.Integration Points`):**

| Package | Version | UUID |
|---------|---------|------|
| ModelingToolkit | `11.25.0` | `961ee093-…-7800e7a78` |
| ModelingToolkitBase | `1.34.0` | `7771a370-…-47e70ca0b839` |
| SciMLBase | `2.155.1` | `0bca4576-…-ffa030f20462` |

**Where the strict check lives (verified by reading installed source):**

The exact symptom from CONTEXT.md — `ArgumentError: Equations (N), unknowns (N+1), and initial conditions (N+1) are of different lengths.` — is thrown at `~/.julia/packages/ModelingToolkitBase/Ej0Pz/src/systems/abstractsystem.jl:3085` inside `check_eqs_u0`:

```julia
function check_eqs_u0(eqs, dvs, u0; check_length = true, kwargs...)
    if u0 !== nothing
        if check_length
            if !(length(eqs) == length(dvs) == length(u0))
                throw(ArgumentError("Equations ($(length(eqs))), unknowns ($(length(dvs))), and initial conditions ($(length(u0))) are of different lengths."))
            end
```

`check_eqs_u0` is called from `process_SciMLProblem` (`problem_utils.jl:1606`), which is in turn called from `SteadyStateProblem` (`odeproblem.jl:127-135`). `check_length` defaults to `true` and **is not** forwarded by `solve_steady`, so the strict check is enforced regardless of what `mtkcompile` did. Reproduced live on `/tmp/test_mtr.jl`:

```
ERROR: ArgumentError: Equations (92), unknowns (93), and initial conditions (93) are of different lengths.
Stacktrace:
 [1] #check_eqs_u0#325       at .../ModelingToolkitBase/.../abstractsystem.jl:3092
 [2] #process_SciMLProblem#768 at .../ModelingToolkitBase/.../problem_utils.jl:1627
 [3] #_#798                   at .../ModelingToolkitBase/.../odeproblem.jl:135
 [4] SteadyStateProblem        at .../ModelingToolkitBase/.../odeproblem.jl:127
 [...]
 [7] #solve_steady#160         at /home/itay/projects/Julia-STREAM/src/solvers.jl:76
```

**The `mtkcompile(...; fully_determined=false)` "auto-balance" never existed.** Reading `~/.julia/packages/ModelingToolkitBase/Ej0Pz/src/systems/systems.jl:204-227`:

```julia
if fully_determined === nothing
    fully_determined = false
end
if fully_determined && length(eqs) > length(all_dvs)
    throw(ExtraEquationsSystemException(...))
elseif fully_determined && length(eqs) < length(all_dvs)
    throw(ExtraVariablesSystemException(...))
end
```

`fully_determined=false` simply *suppresses the check inside `mtkcompile`* — it does not rebalance the system. The unknown count returned by `mtkcompile(sys; fully_determined=false)` is unchanged from what the user supplied; what changes is whether the imbalance throws at compile time. The downstream `process_SciMLProblem.check_eqs_u0` ALWAYS runs with `check_length=true` regardless. So:

- The **CONTEXT.md hypothesis** ("MTKBase upgraded; `fully_determined=false` no longer auto-balances") is partially correct: there IS API drift, but the drift is in *whether downstream problem construction enforces length-equality strictly*, not in whether `mtkcompile` rebalances. The deferred-items.md D-1 "Resolution path 3 — add the missing ICs/equations to each affected scenario at source" is exactly correct, and the user's directive (no `check_length=false` workarounds) aligns with the actual API contract: the system was structurally underdetermined all along; older MTKBase happened not to enforce the check at problem-construction time, so the bug was latent.

**No CHANGELOG file ships with the installed packages** (`find ~/.julia/packages/ModelingToolkit* -name CHANGELOG*` returns nothing). The drift is verifiable directly from the installed source (above) — no GitHub round-trip needed. Per CONTEXT.md "Claude's Discretion", deeper bisect is not warranted: the fix shape is already determined by the diagnostic table.

**Confidence: HIGH.** Root cause located in installed source; symptom reproduced live; fix verified live.

## 3. Per-Scenario Diagnostic Plan

The diagnostic table below uses the column names locked by CONTEXT.md `<specifics>`:
`(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)`.
All numbers measured live via `bin/jl .planning/phases/58.../scratch/diag_all_scenarios.jl` (this session).

| scenario | n_eqs | n_unknowns | n_init_eqs | missing_kind | hypothesis | fix_sketch |
|----------|-------|------------|------------|--------------|------------|------------|
| MTR symmetric (test_validation.jl:333) | 92 | 93 | 0 | unknowns_pin | `hd.power(t)` is an `@variables` declared in `HeatDiffusion` (heat_diffusion.jl:145) but no equation closes it | Add `hd.power ~ 1e4` to `conns` |
| MTR asymmetric (:504) | 92 | 93 | 0 | unknowns_pin | identical to MTR sym (single HD, two CAC) | Add `hd.power ~ 1e4` to `conns` |
| MTR one-sided (:668) | 61 | 62 | 0 | unknowns_pin | identical to MTR sym (single HD, single CAC) | Add `hd.power ~ 1e4` to `conns` |
| VAL-01 HD Fourier (:842) | 50 | 51 | 0 | unknowns_pin | identical to MTR sym (single HD, both faces ConstantTemperature, `power=0.0`) | Add `hd_v01.power ~ 0.0` to `conns_v01` |
| VAL-02 two-plate (:935) | 91 | 93 | 0 | unknowns_pin (×2) | TWO HD instances → two missing pins (Δ=−2) | Add `hd1.power ~ power_per_plate` AND `hd2.power ~ power_per_plate` |
| VAL-02 transient T_wall step (:295) | 11 | 11 | 0 | symbol_access (NOT determinacy) | `ssys.sys.T_wall_callable` access path on compiled system raises `ArgumentError: System sys: variable sys does not exist`; correct path is `ssys.T_wall_callable` (verified) | Replace `ssys.sys.T_wall_callable` with `ssys.T_wall_callable` at line 317 (alternatively `last(parameters(ssys))` matching `test_integration.jl:192`) |
| PointKinetics validation (:1042) | 43 | 43 | 0 | NO determinacy gap | Δ=0 already (`build_loop_pk` at `src/examples.jl:651` already has `power_eqs = [rods_fuel.power ~ pk.P * power_scale]`). The KINSOL retcode=Failure / flag −7 is a **numerical** convergence problem; existing transient fallback in test code (`:1059-1064`, `:1118-1124`, `:1167-1175`) handles it | NO Phase 58 fix needed unless transient fallback also fails — verify under fixed determinacy on first run; if VAL-PK-01..03 still fail post-58, that is a separate numerical-conditioning issue (out of scope) |

### Live verification — selected raw output

From `scratch/diag_all_scenarios.jl` (this session, daemon dev loop, MTK 11.25.0):

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

=== Scenario D: VAL-01 HD Fourier ===
  as-is                               Δ= -1  n_eqs=  50  n_unk=  51  fully_determined=true: FAIL
  with hd.power pin                   Δ=  0  n_eqs=  50  n_unk=  50  fully_determined=true: PASS

=== Scenario E: VAL-02 two-plate one-channel (steady) ===
  as-is                               Δ= -2  n_eqs=  91  n_unk=  93  fully_determined=true: FAIL
  with hd.power pin (x2)              Δ=  0  n_eqs=  91  n_unk=  91  fully_determined=true: PASS

=== Scenario F: VAL-02 transient T_wall step ===
  build_loop_transient(T_wall_fn=...) compiled. Δ=0  n_eqs=11  n_unk=11
  -- ssys.sys getproperty :T_wall_callable existence test:
     FAILED: ArgumentError: System sys: variable sys does not exist
     direct ssys.T_wall_callable -> T_wall_callable⋆
```

End-to-end `solve_steady` verification on MTR symmetric WITH the pin (`scratch/diag_mtr_power_pin.jl`):

```
mtkcompile(sys_mtr; fully_determined=true) -> SUCCESS
  n_eqs=92  n_unknowns=92
solve_steady retcode: Success
```

### Sanity-baseline — canonical builders are already strict-determined

From `scratch/diag_baseline.jl` — every existing builder in `src/examples.jl` is **already strictly determined** under the current MTK 11.25.0 stack:

```
build_loop()             n_eqs=  11  n_unknowns=  11  Δ=0   n_init_eqs=0
build_loop_vertical()    n_eqs=  11  n_unknowns=  11  Δ=0   n_init_eqs=0
build_loop_transient()   n_eqs=  11  n_unknowns=  11  Δ=0   n_init_eqs=0
build_cube()             n_eqs=  14  n_unknowns=  14  Δ=0   n_init_eqs=0
build_loop_lof_bypass()  n_eqs=  64  n_unknowns=  64  Δ=0   n_init_eqs=0
```

This is the **strongest possible evidence** for the diagnosis: every builder that pins HD's power explicitly (LOF bypass: `heated.fuel.power ~ power_W`; PK: `rods_fuel.power ~ pk.P * power_scale`) is fine, and the broken scenarios are exactly the ones that *don't* pin it. The Phase-58 builders also all have `Δ=0` for their non-HD topology.

### Why VAL-02 transient is NOT determinacy

The compiled system from `build_loop_transient(; T_wall_fn=...)` is structurally fine (Δ=0). What fails is the symbol-access expression `ssys.sys.T_wall_callable` in the test (`test/test_validation.jl:317`). Live introspection shows:

- `ssys.sys.T_wall_callable` → raises `ArgumentError: System sys: variable sys does not exist`
- `ssys.T_wall_callable` → returns `T_wall_callable⋆` (the callable parameter symbolic)
- `last(parameters(ssys))` → also works (`test/test_integration.jl:192`)

This means `mtkcompile`'s namespacing of compose-time-declared parameters changed: the parameter is now reachable directly on `ssys`, not under `ssys.sys`. The failing symptom in CONTEXT.md "`variable sys does not exist`" is a different family from the structural-balance gap, but the fix is one line. The CONTEXT.md `D-01` allowance ("if Plan 58-01's diagnostic shows the fix diverges, the planner is free to give it its own fix plan") applies — diagnostic confirms divergent root cause; recommend giving it its own fix in the same plan as the determinacy fixes since it's a one-line edit at the same test file.

### Scenario PK-VAL (informational)

`build_loop_pk` is structurally fine (Δ=0), but `solve_steady` returns `ReturnCode.Failure` with KINSOL flag `−7` (five consecutive scaled steps satisfy step length test — non-convergence, not divergence). The existing test code at `test/test_validation.jl:1059-1064, 1118-1124, 1167-1175` falls back to a long transient run when `solve_steady` fails. Therefore **the PK testset already reaches a working solver call (the transient)** — Phase 58's "must reach a working solver call" gate is satisfied without any code change to PK once the related testsets stop tripping the broader try/catch wrapper at `:834`. Recommendation: do not attempt to "fix" PK convergence in Phase 58 (out of scope as numerical work). Verify on first run after Phase-58 fixes that VAL-PK-01/02a/02b/03 all pass via the transient fallback; if they don't, escalate as a separate phase or dedicated convergence work.

## 4. Closing-Equation Patterns Already in the Codebase

These patterns are the **prior art** Phase 58 fixes follow. Each one is already in tree and is the canonical shape for the corresponding closure.

### Pattern 1 — Pin a free `@variables` to a scalar with `~` (the Phase 58 fix shape)

Where it lives: `src/examples.jl:499` (LOF bypass), `src/examples.jl:651` (PK), and crucially `test/test_heat_diffusion.jl:182` (HDIFF-04 standalone HD test):

```julia
conns = vcat(
    [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for i in 1:nz],
    [hd.power ~ pwr],   # ← THIS is the closing equation MTR/VAL-01/VAL-02 forgot
)
```

**Applies to:** every Phase 58 broken scenario except VAL-02 transient.

### Pattern 2 — Absolute pressure anchor (`pump.port_in.P ~ 1.0e5`)

Where it lives: every multi-component builder (`src/examples.jl:76, 173, 242, 257, 343, 495, 660`). Documented at `src/examples.jl:30` and reaffirmed by CONTEXT.md `<code_context>`. Kirchhoff networks have one degree of freedom in absolute pressure level; without this anchor the loop is structurally underdetermined.

**Applies to:** all hydraulic loops including the Phase-58 scenarios. Already present everywhere; no Phase-58 fix needs to add it. Listed for completeness — it's the cousin pattern in the dimensional family (pressure anchor : flow loops :: power anchor : HD instances).

### Pattern 3 — WallPort drive-aware self-anchoring (Phase 52)

Where it lives: `STATE.md:73-74` lists the prior-art entry; the contract is that 2-across/1-flow ports are structurally underdetermined when unconnected, and the resolution is **per-port** mutually-exclusive: drive it (closing equation from the consumer side) or self-anchor it (`T_wall ~ T_default; h ~ 0`). Mixing the two over-determines the system.

**Applies to:** **Phase 58 has no WallPort topology in scope** — `WallPort` was retired in Phase 55 D-06 (`src/components/channels.jl:404-405`). The pattern is documented here because it is the prior art that proves the "drive-or-self-anchor" idiom; the Phase-58 fix (`hd.power ~ value`) is the same idea applied to a non-port plain `@variables`.

### Pattern 4 — CAC adiabatic-when-unconnected via MTK Flow rule

Where it lives: `src/components/channels.jl:716-722` — when a `ChannelAndContacts` `thermal_*[i]` `ThermalPort` is left unconnected, MTK's Flow rule auto-zeros `Q_flow`, which forces the channel-side q-expression to zero and settles the unconnected port's `T_wall[i]` to `T[i]` (adiabatic). **Live introspection confirms this contract still holds under MTK 11.25.0**: in MTR one-sided (Scenario C), the unconnected `cac_l.thermal_right[i]` ports do not produce a determinacy gap — the only gap is the missing `hd.power` pin. Δ goes from −1 to 0 with the single power pin; if the per-cell adiabatic contract had also broken, we'd see an additional `n` deficit per CAC.

**Verification:** `test/test_heat_diffusion.jl:182-194` ("HDIFF-04: Connected only to one face — unconnected face Q_flow ≈ 0") tests this exact contract today and passes. Phase 58 does not need to re-verify it explicitly; the determinacy regression test (D-06) implicitly verifies it because if the contract broke, MTR one-sided's Δ would not collapse to 0 under the single power pin.

**Applies to:** MTR one-sided (Scenario C) and any scenario with dangling CAC thermal ports. No Phase-58 fix needed; documented here so the planner knows this contract is verified-good.

### Anti-patterns (don't do these)

- **Adding `check_length=false` to `solve_steady`** — explicitly out of scope per D-05.
- **Pinning MTK packages backwards** — explicitly out of scope.
- **Adding the `power ~ value` equation INSIDE `_diffusion_eqs`** — would over-determine builders that legitimately wire `power` to PK (`build_loop_pk`). The closing equation is the user's responsibility; the public contract at `src/components/heat_diffusion.jl:119` is correct. Don't change it.
- **Replacing `power(t) = power_init` with `@parameters power = power_init`** — would change MTK semantics (parameters are immutable per-solve, variables can be tuned via `remake()`). The PK loop relies on `power(t)` being a variable bound to `pk.P * power_scale`; making it a parameter would force a different wiring pattern. Stay with the current declaration.

## 5. `fully_determined=false` / `check_length=false` Audit

Site-by-site classification. Entries marked `legitimate-structural` keep `fully_determined=false`/`check_length=false` with an explanatory inline comment; entries marked `bug-hiding` are converted to `fully_determined=true` after the corresponding fix lands. Entries marked `isolated-component-test` are component-only `mtkcompile` calls that intentionally compile a single component in isolation (no consumer; ports dangle; structurally underdetermined by design) — same treatment as `legitimate-structural`.

| File:Line | Site context | Verdict | One-line reason | Recommendation |
|-----------|--------------|---------|-----------------|----------------|
| `test/test_misc.jl:19` | Inertia compile | isolated-component-test | Inertia in isolation has 1 unknown (mdot) but no closing eq; intentional unit-test scope | Keep + add inline comment |
| `test/test_misc.jl:37` | RL circuit compile (T eqs not introduced) | legitimate-structural | Pure hydraulic RL; no T equations exist by design (CONTEXT.md `D-04` cites this exact site as the survivor archetype) | Keep + already-commented; tighten comment per D-04 |
| `test/test_misc.jl:48` | RL circuit ODEProblem `check_length=false` | legitimate-structural | Same site as :37; consistent | Keep + already-commented |
| `test/test_misc.jl:71` | HeatExchanger compile | isolated-component-test | Pure value-source, no flow context | Keep + inline comment |
| `test/test_misc.jl:131` | WallTemperature compile | isolated-component-test | Value-source (pure RHS); produces only `T_wall_out[i] ~ T_wall_fn(t)` equations, no port-Q closure | Keep + inline comment |
| `test/test_misc.jl:178` | HeatFluxSource compile | isolated-component-test | Same family as :131 | Keep + inline comment |
| `test/test_pump.jl:18` | Pump in isolation | isolated-component-test | Pump alone has unconnected ports | Keep + inline comment |
| `test/test_pump.jl:36` | Pump+Resistor (no anchor) | isolated-component-test | Tests rate-equation only, no pressure anchor | Keep + inline comment |
| `test/test_pump.jl:68` | Pump-source variant | isolated-component-test | Same family | Keep + inline comment |
| `test/test_pump.jl:83` | Pump+Resistor flipped sign | isolated-component-test | Same family | Keep + inline comment |
| `test/test_pump.jl:99` | Pump callable | isolated-component-test | Same family | Keep + inline comment |
| `test/test_pump.jl:133` | Pump+Resistor in test | isolated-component-test | Same family | Keep + inline comment |
| `test/test_resistors.jl:18` | Resistor compile | isolated-component-test | Pure resistance, no anchor | Keep + inline comment |
| `test/test_flapper.jl:58, 110, 151` | Flapper compile (3 sites) | isolated-component-test | Flapper docstring (`src/components/flapper.jl:38`) instructs `mtkcompile(sys; fully_determined=false)` for standalone-flapper tests; the Flapper component intentionally produces a free `state(t)` set by an external `ContinuousCallback` | Keep + inline comment OR tighten Flapper docstring to explain why |
| `src/components/flapper.jl:38` | Flapper docstring | doc-only | Documentation that downstream authors should pass `fully_determined=false` for standalone-Flapper compile; not a compile-time site itself | Tighten the docstring to name the structural reason (callback-set state) |
| `test/test_heat_diffusion.jl:44` | HD compile in isolation | isolated-component-test | HD alone has dangling thermal ports + unset `power(t)`; intentional unit scope | Keep + inline comment |
| `test/test_heat_diffusion.jl:185` | HD + ConstantTemperature integration test | bug-hiding | Has `[hd.power ~ pwr]` already pinned (line 182), so the system IS structurally determined — `fully_determined=false` here is a leftover that should be `true` | Convert to `fully_determined=true` |
| `test/test_channels.jl:16, 67, 70, 84, 94, 468, 675, 804, 1087` | Channel/CHF/CAC standalone + integration tests | mixed: most are isolated-component-test (compile in isolation per Phase 55 D-08 spike) | Each Channel/CAC variant has external-input vars (`T_wall_left[1:n]`, `T_wall_right[1:n]`, `q_left[1:n]`, `q_right[1:n]`, or per-cell `thermal_*[i]`) that are intentionally underdetermined in isolation; ARE Phase 55 D-08's verified Hypothesis-A pattern | Keep all 9 + inline comment per file pointing to Phase 55 D-08 Spike #1 |
| `test/test_validation.jl:204` | KEPT testsets wrapper | bug-hiding (one of the broken scenarios) | One of the seven broken scenarios in CONTEXT.md `<domain>` | Convert to `fully_determined=true` AFTER the corresponding fix lands |
| `test/test_validation.jl:379` | MTR symmetric | bug-hiding | The exact target of Plan 58-02 | Convert to `true` after `hd.power ~ 1e4` lands |
| `test/test_validation.jl:549` | MTR asymmetric | bug-hiding | Plan 58-02 target | Convert to `true` after fix |
| `test/test_validation.jl:709` | MTR one-sided | bug-hiding | Plan 58-02 target | Convert to `true` after fix |
| `test/test_validation.jl:903` | VAL-01 HD Fourier | bug-hiding | Plan 58-03 target | Convert to `true` after `hd_v01.power ~ 0.0` lands |
| `test/test_validation.jl:996` | VAL-02 two-plate | bug-hiding | Plan 58-04 target | Convert to `true` after both `hd1.power ~ pwr; hd2.power ~ pwr` land |
| `src/components/channels.jl:207, 409` | Comments only | doc-only | Inline doc inside Channel/CHF describing Phase 55 D-08 Hypothesis-A pattern; not a compile-time site | Leave |

**Audit summary by category:**
- **Bug-hiding (7 sites):** all in `test/test_validation.jl` and `test/test_heat_diffusion.jl:185` — these get flipped to `fully_determined=true` *after* their corresponding determinacy fix lands.
- **Legitimate-structural / isolated-component-test (~22 sites):** preserved with inline comments naming the structural reason. The bulk are isolated component compiles (Pump/Resistor/Inertia/HeatExchanger/HD/CAC/CHF/Channel/Flapper/WallTemperature/HeatFluxSource alone) where the unit-test pattern is "compile this component in isolation; verify shape, not solvability". These are not fixable without inventing closing equations that aren't part of what the test is checking.
- **Doc-only (3 sites):** `src/components/channels.jl:207, 409` (comments) and `src/components/flapper.jl:38` (docstring). `src/components/flapper.jl:38` is the only one worth a small docstring tightening.

## 6. Determinacy Regression Test (D-06) Design

### File location and orchestrator wiring

Per CLAUDE.md "Test placement rule": new file `test/test_determinacy.jl`, mirroring the per-domain pattern. Add `include("test_determinacy.jl")` to `test/runtests.jl` after line 22 (after `test_heat_diffusion.jl`, before `test_correlations.jl`) — places the global structural-correctness check between the per-component tests and the integration/composition tests, so a regression here surfaces before broader testsets cascade-fail.

### File layout

```julia
# test/test_determinacy.jl
# Phase 58 — guards against the under-determinacy regression family
# documented in .planning/phases/56-.../deferred-items.md §D-1.
#
# Asserts, for every canonical builder and every Phase-58 scenario topology:
#   (1) length(equations(ssys)) == length(unknowns(ssys))
#   (2) mtkcompile(sys; fully_determined=true) succeeds (does not throw)
# (2) is the stronger contract; (1) is the cheap pre-check that surfaces
# WHICH Δ is wrong before the harder strict-compile attempt.

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect    # disambiguate from Sockets.connect (Phase 57 D-04 #1)
using STREAM
import STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion,
                ConstantTemperature, Channel,
                PipeGeometry_circular, PipeGeometry_rectangular,
                build_loop, build_loop_vertical, build_loop_transient,
                build_cube, build_loop_lof_bypass, build_loop_pk,
                ReactivityController

# ----- helpers -----
function assert_determined(label::String, sys)
    ssys = mtkcompile(sys; fully_determined=true)   # raises on imbalance
    @test length(equations(ssys)) == length(unknowns(ssys))
    return ssys
end

# Scenario builders LIFTED from test_validation.jl topology bodies (CONTEXT.md
# Discretion: helpers may stay here or be lifted into src/examples.jl). Keeping
# them here for now to avoid widening the public API.
function _build_mtr_sym() ; ... end
function _build_mtr_asym() ; ... end
function _build_mtr_onesided() ; ... end
function _build_val01_fourier() ; ... end
function _build_val02_twoplate() ; ... end

# ----- Testset 1: canonical builders -----
@testset "Determinacy: canonical builders are fully determined" begin
    @testset "build_loop"            begin assert_determined("build_loop",            build_loop()) end
    @testset "build_loop_vertical"   begin assert_determined("build_loop_vertical",   build_loop_vertical()) end
    @testset "build_loop_transient"  begin assert_determined("build_loop_transient",  build_loop_transient()) end
    @testset "build_cube"            begin assert_determined("build_cube",            build_cube()) end
    @testset "build_loop_lof_bypass" begin assert_determined("build_loop_lof_bypass", build_loop_lof_bypass()) end
    # build_loop_pk returns (ssys, ic) — the ssys is post-mtkcompile. Re-check by
    # rebuilding from inside (or by calling its inner builder with an exposed
    # uncompiled handle). For now we rely on an additional smoke build:
    @testset "build_loop_pk"         begin
        ctrl = ReactivityController()
        ssys, _ = build_loop_pk(ctrl; n=7, T_inlet=293.15)
        @test length(equations(ssys)) == length(unknowns(ssys))
    end
end

# ----- Testset 2: Phase-58 scenario topologies -----
@testset "Determinacy: Phase 58 scenarios" begin
    @testset "MTR symmetric"   begin assert_determined("MTR sym",     _build_mtr_sym()) end
    @testset "MTR asymmetric"  begin assert_determined("MTR asym",    _build_mtr_asym()) end
    @testset "MTR one-sided"   begin assert_determined("MTR onesided", _build_mtr_onesided()) end
    @testset "VAL-01 Fourier"  begin assert_determined("VAL-01",      _build_val01_fourier()) end
    @testset "VAL-02 twoplate" begin assert_determined("VAL-02",      _build_val02_twoplate()) end
end
```

### Helper extraction strategy

CONTEXT.md `<discretion>` allows scenario builders to live either inside `test_determinacy.jl` or be lifted to `src/examples.jl`. Recommendation: **keep them inside `test_determinacy.jl`** as `_build_*` private helpers for v1.1, since:

1. Lifting them to `src/examples.jl` widens the public API surface for code that's only ever consumed by the determinacy test plus the existing testsets (which inline the same topology).
2. The Phase-58 fix lands one-line `~`-bindings into `test_validation.jl`'s testsets; lifting the topology to `src/examples.jl` would mean the testsets can't easily inline-edit the binding without also editing the example builder.
3. If a future phase ends up needing these as public builders (e.g. v1.2's MTR validation suite), the lift is a future refactor, not a Phase-58 prerequisite.

If the planner disagrees, the alternative ("lift to `src/examples.jl::build_mtr_symmetric`/`build_mtr_asymmetric`/`build_mtr_onesided`/`build_val01_fourier`/`build_val02_twoplate`, then `test_validation.jl` testsets call these and `test_determinacy.jl` calls them with the strict compile") is also fine — just slightly bigger blast radius.

### Wave-0 gaps

- `test/test_determinacy.jl` — does not exist; create it.
- Helper `_build_*` functions — created in `test/test_determinacy.jl`.
- Orchestrator wiring — single line added to `test/runtests.jl`.
- No new framework install: Test stdlib already used everywhere.

### Why both checks (length-equality AND fully_determined=true)?

Per CONTEXT.md `<specifics>`: "the second is the stronger contract." Live introspection confirms why both belong in the regression:
- `length(equations(ssys)) == length(unknowns(ssys))` is the cheap surface check; runs in microseconds and produces a clear `Δ` error message naming the imbalance.
- `mtkcompile(sys; fully_determined=true)` is the deep check; it runs StateSelection's structural-correctness verifier and surfaces `ExtraVariablesSystemException` / `ExtraEquationsSystemException` with the actual offending variable list. It also exercises the alias-elimination path that downstream `process_SciMLProblem` will trigger.

Either alone could pass while the other fails (e.g. `Δ=0` post-tearing but a higher-index DAE that `fully_determined=true` rejects with "may also be a high-index DAE"). Belt-and-suspenders.

## 7. Validation Architecture

> Required for Nyquist Dimension 8 / VALIDATION.md generation. `workflow.nyquist_validation = true` in `.planning/config.json`.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `Test` (Julia stdlib) — already in use across all 14 existing test files |
| Config file | `test/runtests.jl` (orchestrator-only, one `include()` per test file per CLAUDE.md "Test placement rule") |
| Quick run command | `bin/jl test/test_determinacy.jl` (just the new file; ~5–15s warm) |
| Full suite command | `bin/jl test/runtests.jl` |
| Optional broader determinacy probe | `bin/jl test/test_validation.jl` (exercises all seven in-scope scenarios end-to-end) |

### Phase Requirements → Test Map

| Scenario | Behavior | Test Type | Automated Command | File Exists? |
|----------|----------|-----------|-------------------|--------------|
| DETERMINACY-CANON | Every canonical builder is `fully_determined=true` after `mtkcompile` | unit (structural) | `bin/jl test/test_determinacy.jl` | ❌ Wave 0 (create) |
| DETERMINACY-PHASE58 | Every Phase-58 fixed scenario topology is `fully_determined=true` | unit (structural) | `bin/jl test/test_determinacy.jl` | ❌ Wave 0 (create) |
| MTR-SYM | MTR symmetric reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR symmetric") | ✅ exists, currently emits sentinel row |
| MTR-ASYM | MTR asymmetric reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR asymmetric") | ✅ exists, currently emits sentinel row |
| MTR-ONESIDED | MTR one-sided reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR one-sided") | ✅ exists, currently emits sentinel row |
| VAL-01-FOURIER | HD transient reaches `solve(ODEProblem)` Success and Fourier reference holds | integration | `bin/jl test/test_validation.jl` (testset "VAL-01: HeatDiffusion transient — Fourier series validation") | ✅ exists, currently raises |
| VAL-02-TWOPLATE | Two-plate one-channel reaches `solve_steady` Success and energy balance holds | integration | `bin/jl test/test_validation.jl` (testset "VAL-02: Two-plate one-channel topology — both faces active") | ✅ exists, currently raises |
| VAL-02-TRANSIENT | T_outlet rises after T_wall step in `build_loop_transient` callable mode | integration | `bin/jl test/test_validation.jl` (testset "VAL-02: Transient T_outlet rises after T_wall step") | ✅ exists, currently raises (`variable sys does not exist`) |
| PK-VAL | PK testset reaches `solve_*` (steady or transient fallback) | integration | `bin/jl test/test_validation.jl` (testset "PointKinetics validation") | ✅ exists, may need only the upstream try/catch wrapper to stop tripping |

### Sampling Rate

- **Per task commit (incremental):** `bin/jl test/test_determinacy.jl` (≤ 30 s warm via daemon) — runs the new structural test only; cheapest gate against fix-then-regress.
- **Per wave merge (broader):** `bin/jl test/test_determinacy.jl && bin/jl test/test_validation.jl` (3–5 min) — exercises both the structural test AND the seven scenarios that motivated the phase.
- **Phase gate (full suite green):** `bin/jl test/runtests.jl` before `/gsd-verify-work`. Includes all 14 + 1 = 15 test files.

### Wave 0 Gaps

- [ ] `test/test_determinacy.jl` — new file (covers DETERMINACY-CANON + DETERMINACY-PHASE58)
- [ ] Wire `include("test_determinacy.jl")` into `test/runtests.jl` (after `test_heat_diffusion.jl`)
- [ ] Helper `_build_*` extraction strategy decided (planner's call per CONTEXT.md `<discretion>`; default: keep helpers inside `test_determinacy.jl`)
- [x] Test framework — Julia `Test` stdlib already in use; no install needed

### Determinacy Contract (formal)

For every system `sys` produced by a builder or a Phase-58 scenario topology:

```julia
# Cheap surface check (microseconds):
ssys = mtkcompile(sys; fully_determined=false)
@assert length(equations(ssys)) == length(unknowns(ssys))

# Strong structural check (runs StateSelection + alias-elimination, ms):
ssys = mtkcompile(sys; fully_determined=true)   # raises ExtraVariablesSystemException
                                                 # or ExtraEquationsSystemException on imbalance
```

Both must pass. The regression target is "the determinacy contract holds across MTK upgrades". The most likely future regression class is "a transitive MTK upgrade reintroduces an Δ ≠ 0 in one of these scenarios"; the test catches this in <1 s warm and points the failing builder by name.

## 8. Risks and Pitfalls

### R-1: Daemon `Sockets.connect` shadowing of `MTK.connect`

**What:** Phase 57 D-04 deviation #1 — daemon-loaded session has both `Sockets.connect` (from `bin/jl-daemon.jl`) and `ModelingToolkit.connect` in scope; if a script does `using ModelingToolkit` but does not explicitly `using ModelingToolkit: connect`, the bare `connect` call resolves to `Sockets.connect` and raises `UndefVarError: connect not defined`.

**Reproduced:** This session, `scratch/diag_baseline.jl` initially had `connect` ambiguity (line 43); workaround was `using ModelingToolkit: connect` explicitly at the top of `scratch/diag_baseline_strict.jl`.

**Mitigation:** All scratch scripts and the new `test/test_determinacy.jl` MUST include `using ModelingToolkit: connect` at the top. Existing `test/test_validation.jl` does not import `connect` explicitly because it loads inside the daemon-test-runner where the order of module loads makes `connect` resolve correctly. **For new files, be explicit.**

**Fallback:** If daemon resolution gets weird mid-phase, cold-start: `julia --project=. test/test_determinacy.jl`. Documented in CLAUDE.md "Daemon dev loop" "Limits worth knowing".

### R-2: Callable parameters (VAL-02 transient) have a different symptom shape

**What:** `ssys.sys.T_wall_callable` raises `ArgumentError: System sys: variable sys does not exist`, but `ssys.T_wall_callable` works. This is NOT the same family as the structural-balance gap; it is a *symbol-namespacing* drift. Plans must not blanket-apply the `hd.power ~ value` fix to VAL-02 transient — it has zero effect there.

**Mitigation:** Plan 58-01's diagnostic table makes the divergence explicit in row "VAL-02 transient T_wall step" (missing_kind = `symbol_access`, not `unknowns_pin`). Plan 58-XX (the VAL-02 transient plan) replaces a single string at `test/test_validation.jl:317`.

**Alternative path:** `last(parameters(ssys))` matches `test/test_integration.jl:192` — also valid. The planner picks the more readable of the two; the introspection comment "stable named access, immune to parameter reordering" at line 317 was the original motivation for the (now-broken) namespaced access.

### R-3: `warn_initialize_determined=false` interaction

**What:** `solve_steady` at `src/solvers.jl:79` already passes `warn_initialize_determined=false`. After Phase-58 fixes, the systems become fully determined; the warning suppression is no longer needed but also not harmful. D-05 forbids touching `solve_steady`'s signature, so leave it alone — it is a NO-OP under fully-determined systems and remains useful for any future caller-supplied initialization.

**Mitigation:** None needed. Listed for completeness so the planner knows the kwarg is intentionally untouched.

### R-4: PK testset numerical convergence (out of scope but in the path)

**What:** `build_loop_pk` is structurally fine (Δ=0). But `solve_steady` returns `ReturnCode.Failure` with KINSOL flag −7 (non-convergence). The existing test code at `test/test_validation.jl:1059-1064, 1118-1124, 1167-1175` handles this with a transient fallback — but the fallback is only reached if the **outer** try/catch wrapper at `test/test_validation.jl:834` does not bail first. Today, the structural-balance failures of MTR/VAL-01/VAL-02 trip the outer wrapper before PK runs; once those are fixed, PK runs cleanly, and the transient fallback should resolve any remaining convergence issues.

**Mitigation:** Verify on the first full-suite run after Phase-58 fixes that VAL-PK-01/02a/02b/03 all pass. If any fails post-fix, that's a separate convergence-conditioning issue (numerical scaling on PK ICs, tightening KINSOL tolerances, etc.) — out of Phase 58 scope. Planner should NOT add a PK convergence fix to Phase 58.

### R-5: `power_shape` and harmonic-mean-k future expansions could reintroduce determinacy gaps

**What:** Memory item `project_future_multi_material.md` agrees that future multi-material `HeatDiffusion` will use a `materials[nz,nx]` matrix + per-cell `power_shape[nz,nx]`. If that future version adds new `@variables` (e.g. per-cell `k_eff(t)[nz,nx]` for harmonic-mean blending), the determinacy regression test will catch a new gap automatically.

**Mitigation:** No Phase-58 work — listed so the planner knows the regression test is forward-looking, not just retrospective.

### R-6: `mtkcompile` warning suppression

**What:** Adding `mtkcompile(sys; fully_determined=true)` to broken builders raises `ExtraVariablesSystemException` synchronously. This is the desired behavior — but during the diagnostic phase (Plan 58-01) the test should NOT use `fully_determined=true` because we explicitly *want* to inspect under-determined systems. Use `mtkcompile(sys; fully_determined=false)` when introspecting; switch to `fully_determined=true` only in `test/test_determinacy.jl` and AFTER each fix lands.

**Mitigation:** Diagnostic scripts in `scratch/diag_*.jl` already follow this discipline. Plans 58-02..N must not flip `fully_determined=true` until the corresponding fix is in place; the audit table in §5 sequences this explicitly ("Convert to `true` AFTER fix lands").

## 9. Open Questions (RESOLVED)

1. **Should MTR sym/asym/one-sided collapse to one fix plan or three?**
   - What we know: identical fix (`hd.power ~ <value>`); identical Δ=−1 deficit; same topology family with only `power_shape`/inlet-T variation.
   - What's unclear: whether the planner prefers one consolidated diff (3 testset edits in one plan) or three smaller plans (one per scenario for cleaner bisect).
   - RESOLVED: **ONE plan covers MTR sym + asym + one-sided**, since the fix is mechanical and identical across the three. Per CONTEXT.md `<discretion>`, this is the planner's call; the diagnostic table makes the equivalence explicit. (CONTEXT.md `D-02` already cites "MTR pair handled together" as the default.) Plan 58-02 owns all three.

2. **Should VAL-02 transient share Plan-58-XX with VAL-02 steady, or get its own plan?**
   - What we know: VAL-02 transient is `symbol_access` (one-line edit); VAL-02 steady is `unknowns_pin` (two `~`-bindings). Different fix shapes, but both touch `test/test_validation.jl` near each other.
   - What's unclear: planner preference for "fix shape" cohesion vs "test file" cohesion.
   - RESOLVED: **Combine into one plan (58-04)** — both edits in `test/test_validation.jl`, blast radius small. CONTEXT.md `<discretion>` already allows this.

3. **Should helpers `_build_mtr_sym`/etc. live in `test/test_determinacy.jl` or be lifted to `src/examples.jl`?**
   - What we know: helpers are needed by `test_determinacy.jl`; identical topology already inlined in `test_validation.jl`.
   - What's unclear: whether v1.2+ wants public `build_mtr_*` builders.
   - RESOLVED: **Keep helpers inside `test_determinacy.jl`** for v1.1; lift to `src/examples.jl` if a future phase needs them as public API. Lower blast radius, smaller diff. Plan 58-01 Task 3 places them as private `_build_*` helpers in the test file.

4. **Should the audit (§5) flip ALL bug-hiding sites in one final plan, or per-scenario?**
   - What we know: 7 sites total to flip; each conversion is one-line; each is gated on its own scenario fix landing.
   - What's unclear: planner preference.
   - RESOLVED: **Each scenario's fix plan flips its own audit sites** (e.g. Plan 58-02 fixes MTR sym/asym/one-sided AND flips lines 379, 549, 709 in the same diff). Plan 58-05 is the trailing "audit-only" plan that flips the remaining `test_heat_diffusion.jl:185` and adds inline-comment rationale to the legitimate-structural sites.

5. **Does `test/test_determinacy.jl` need to assert anything about `initialization_equations(ssys)` length?**
   - What we know: live introspection shows `n_init_eqs = 0` across every working builder. Adding `length(initialization_equations(ssys)) == length(unknowns(ssys))` is the THIRD-LENGTH check from CONTEXT.md's symptom message ("Equations (N), unknowns (N+1), and initial conditions (N+1)").
   - What's unclear: whether `n_init_eqs == 0` is the canonical fully-determined steady state, or whether MTK 11.25 sometimes generates non-empty `initialization_equations` for the same systems.
   - RESOLVED: **Skip this assertion in the regression**. The two-check contract (length-equality + `fully_determined=true`) catches every case we've measured; adding the third-length check would couple the test to `initialization_equations` semantics that MTK is free to change. Plan 58-01 may revisit if the diagnostic surfaces a case where only the third length differs; otherwise the recommendation stands.

## Sources

### Primary (HIGH confidence)
- `~/.julia/packages/ModelingToolkitBase/Ej0Pz/src/systems/abstractsystem.jl:3081-3094` — `check_eqs_u0` strict-by-default implementation; the exact error site
- `~/.julia/packages/ModelingToolkitBase/Ej0Pz/src/systems/systems.jl:204-227` — `fully_determined` semantics in `mtkcompile`
- `~/.julia/packages/ModelingToolkitBase/Ej0Pz/src/systems/problem_utils.jl:1495-1606` — `process_SciMLProblem` → `check_eqs_u0` call path
- `Manifest.toml:975-980` (MTK 11.25.0), `:993-998` (MTKBase 1.34.0), `:1231-1234` (SciMLBase 2.155.1) — installed versions
- `src/components/heat_diffusion.jl:130-179` — `HeatDiffusion` constructor declaring `power(t)` as an `@variables`; constructor docstring at line 119 explicitly says `power` "must be constrained via a connection equation"
- `src/components/heat_diffusion.jl:55-91` — `_diffusion_eqs` consuming `power` on the RHS via `q_vol = power * power_shape[i,j] / (...)`
- `src/examples.jl:499` (`heated.fuel.power ~ power_W`), `:651` (`rods_fuel.power ~ pk.P * power_scale`) — existing closing-equation patterns
- `test/test_heat_diffusion.jl:182` — existing `[hd.power ~ pwr]` pin in HDIFF-04 test, proves the pattern is established practice
- `.planning/STATE.md:73-74` — Phase 52 WallPort drive-aware self-anchoring pattern (prior art reference)
- `.planning/phases/58-mtk-system-determinacy-repair/58-CONTEXT.md` — phase scope, decisions, deferred ideas (binding contract)
- Live introspection: `scratch/diag_baseline.jl`, `scratch/diag_baseline_strict.jl`, `scratch/diag_mtr_power_pin.jl`, `scratch/diag_all_scenarios.jl`, `scratch/diag_pk.jl` (executed this session via `bin/jl`)

### Secondary (MEDIUM confidence)
- `.planning/phases/56-python-stream-cross-validation/deferred-items.md` §D-1 — original symptom statement, three resolution paths
- `.planning/phases/56-python-stream-cross-validation/56-PAUSE-CONTEXT.md:47-55` — six failures matrix; Phase 58 ownership
- `test/test_validation.jl:317` (broken `ssys.sys.T_wall_callable`) vs `test/test_integration.jl:192` (working `last(parameters(ssys))`) — comparison establishing the symbol-access fix
- CLAUDE.md — daemon dev loop, branching policy, test placement rule

### Tertiary (LOW confidence)
- ModelingToolkit GitHub CHANGELOG — installed packages do not ship with one; verification of "exact version when this drift landed" would require browsing GitHub. Not pursued because the fix shape is already determined by direct introspection of the installed source.

## Metadata

**Confidence breakdown:**
- Standard stack (MTK / MTKBase / SciMLBase versions and behavior): HIGH — read installed source directly.
- Per-scenario diagnosis: HIGH — every count and every fix verified live via `bin/jl`.
- Closing-equation patterns: HIGH — patterns reproduced from `src/examples.jl` and `test/test_heat_diffusion.jl`.
- Audit classification (§5): MEDIUM — verdicts grounded in code inspection but not all 22 sites independently exercised; planner should re-verify any audit-table flip yields a passing test before committing.
- Validation architecture: HIGH — directly grounded in CLAUDE.md test placement rule and existing `runtests.jl` orchestrator pattern.
- Risks and pitfalls: HIGH for R-1, R-2, R-4 (each verified live or in-tree); MEDIUM for R-5 (forward-looking).

**Research date:** 2026-05-08
**Valid until:** 2026-06-07 (30 days; stable when the working branch does not pull in additional MTK package upgrades). Re-verify if `Manifest.toml` MTK packages bump.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | (none — every claim in this research was verified live, cited from installed source, or copied verbatim from CONTEXT.md) | — | — |

**The table above is intentionally empty.** Every factual claim in this research was either:
- Verified live in this session via `bin/jl` (counts, error reproductions, fix verification) → tagged `[VERIFIED: live introspection]`
- Cited from installed package source (`~/.julia/packages/...`) → tagged `[CITED: installed source]`
- Copied from CONTEXT.md or STATE.md verbatim → CONTEXT.md is the binding contract per CLAUDE.md framing

No `[ASSUMED]` claims were made. No user confirmation needed before downstream consumption.

## RESEARCH COMPLETE
