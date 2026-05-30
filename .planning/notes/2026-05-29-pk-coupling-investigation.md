# Point-Kinetics ↔ Thermal-Feedback Coupling — Investigation Findings

**Date:** 2026-05-29
**Branch:** `channels-redesign`
**Julia:** validated on `1.12.6` (CI version) — all reproductions below
**Charter:** `project_pk_tests_investigation` memory — understand the PK tests' physics,
whether the coupled model is correct, what to test but don't, and which tests are hollow.
**Status:** Diagnosis complete **and fix implemented** (2026-05-30) — see RESOLUTION below.

---

## RESOLUTION (implemented 2026-05-30, on `channels-redesign`)

Decisions taken with the user: **full scope** (fix + new physics tests), **seed boundary cells in
IC construction** (not a global connector-default change), **folded into `channels-redesign`**.

**Model fix — `src/examples.jl` `build_loop_pk`.** The returned IC now seeds every port/contact
temperature to `T_inlet`: `cac.port_in.T`, `cac.port_out.T`, all `cac.thermal_left/right{i}.T`
(i=1..n) and all `fuel.thermal_left/right{i}.T` (i=1..nz). Verified: `reactivity[0] = 0.0` (exactly)
for no-feedback, coolant feedback, and fuel feedback. The per-cell `cac.T[i]`/`fuel.T[i,j]` seeds
alone never pinned the boundary cells because they alias to the 300 K port representatives — seeding
the ports is what works (confirmed empirically: cac ports fix the coolant path, the cac+fuel contact
nodes together fix the fuel path). No global connector-default change; zero blast radius.

The separate "consistent-steady-IC helper" sketched below turned out **unnecessary**: a consistent
*cold* IC (all temps + ports = `T_inlet`, `ref_temp = T_inlet`) starts the loop exactly critical, and
the prompt-jump→turnover physics is reached via **settle-then-step** in the transient (PK-FB-02), which
sidesteps the criticality degeneracy without a steady solve.

**Tests — `test/test_integration.jl` §5.** Retired **TF-06** (hollow `isfinite`-only) and **TF-07**
(artifact-only + mis-mirrored Python). Added three meaningful tests (all green on 1.12.6):
- **PK-IC-01** — consistent cold IC ⇒ `reactivity[0] ≈ 0` for both coolant and fuel feedback. The
  one-line guard that would have caught the whole bug.
- **PK-FB-01** — coolant feedback suppresses power to a self-consistent low equilibrium
  (`P_end≈2e-4`, `rho_end≈-5e-5`). The *corrected* mirror of Python `test_integrations.py:390-428`.
- **PK-FB-02** — settle-then-step: textbook prompt jump (`ratio 1.0825` vs `β/(β−δρ)=1.0833`), bounded
  excursion, feedback turns reactivity back to a new critical equilibrium.
- LOOP-01..04 kept (now meaningful with the consistent IC). VAL-PK-01/02a/02b/03 (`test_validation.jl`)
  unchanged — they consume the fixed `build_loop_pk` and are now backstopped by PK-IC-01 against the
  artifact silently returning. Standalone `test_point_kinetics.jl` (incl. the well-designed prompt-jump
  PK-03c) untouched.

**Verification:** `test_integration.jl` §5 = 34/34; full `test_integration.jl` green; authoritative
`Pkg.test()` on 1.12.6 green. Sign-convention divergence (P2) and any VAL-PK strengthening left as
optional follow-ups — PK-IC-01 already provides the cross-cutting artifact guard.

*The original diagnosis and recommendation list follow unchanged for the record.*

---

## TL;DR

The PK kinetics math and the feedback **wiring are correct**. The pathological TF-07
behavior that triggered this session (power "drops 2.5 % in 10 µs, no prompt jump, settles
to 0.682") is **100 % an initial-condition artifact**, not reactor physics and not
"over-damping."

**Root cause (one sentence):** the boundary coolant cells `cac.T[1]` and `cac.T[n]` are
aliased to `FlowPort` stream temperatures that **default to 300 K**, and `build_loop_pk`'s
IC (`cac.T[i] => T_inlet`) does **not** override that default for the boundary cells under
`NoInit`. When `ref_temp` is set to `T_inlet = 293.15` (≠ 300), the feedback term sees
`T − Tref = 300 − 293.15 = 6.85 K` on the boundary cells at t=0 and injects a large spurious
reactivity that swamps everything the test claims to study.

When the IC is made consistent (inlet = ref_temp = port default), the artifact vanishes
(`reactivity[0] = 0`) and the model behaves correctly: pure PK gives a textbook supercritical
rise; coupled strong-feedback gives a physical shutdown to low power.

---

## Evidence chain (all on Julia 1.12.6)

### 1. The reported TF-07 behavior reproduces
Exact TF-07 replica: `reactivity[t=0] = −0.137` (should be 0), `P` falls to 0.04 by t≈1 ms,
"settles" near 0.682 at t=2 s. `P_max == P0` exactly (no prompt jump).

### 2. The feedback wiring and `ref_temp` are CORRECT
Dumped the compiled `reactivity` observed equation:
```
pk7.reactivity ~ rho_val + rho_c_fn(t)
                 − 0.01·(−293.15 + T_source_cac7[1])
                 − 0.01·(−293.15 + T_source_cac7[2])
                 − 0.01·(−293.15 + T_source_cac7[3])
```
- `ref_temp = 293.15` **is** baked in correctly (the `rods7_cac7` caching fix works).
- `connect_temperature_feedback` emits `T_source_cac7[j] ~ cac7.T[j]` correctly.
- `−0.01·Σ(cac.T − 293.15)` evaluated by hand == `−0.137` == the observed reactivity. The
  feedback term is doing exactly what it should; the **inputs** are wrong.

### 3. The IC does not stick on the boundary cells
At t=0 (the built `u0`):
```
cac7.T[1] = 300.0    ← boundary (= port_in.T) — IC of 293.15 IGNORED
cac7.T[2] = 293.15   ← interior — IC applied correctly
cac7.T[3] = 300.0    ← boundary (= port_out.T) — IC of 293.15 IGNORED
```
`−0.01·[(300−293.15) + 0 + (300−293.15)] = −0.137`. Confirmed: the artifact is exactly the
two boundary cells sitting at the 300 K `FlowPort`/`ThermalPort` default
(`src/connectors.jl:7,17`). `HeatExchanger` pins `port_in.T ~ port_out.T ~ T_bc` only
*algebraically*; `solve_transient`'s default `initializealg = NoInit()` never solves that
algebraic relation at t=0, so the stale 300 K default survives into the first reactivity
evaluation. `CheckInit` confirms the IC is inconsistent (`normresid = 112 ≫ tol`);
`BrownFullBasicInit` does **not** repair the boundary cells (still −0.137).

### 4. The dynamics are pure IC relaxation
Once the integrator runs, inflow (mdot=0.2, inlet 293.15) flushes the 300 K boundary out;
`cac.T[1]: 300 → 293.16` by t=2 s. As the coolant returns to `Tref`, feedback decays to ~0
and power partially recovers. The "0.682" is **not an equilibrium** — it is a snapshot of
the slow recovery toward the +5e-4-driven supercritical rise. The +5e-4 step at t=0.1 is
irrelevant: power has already crashed to ~0.05 by then.

### 5. Align the IC → the artifact disappears and physics is correct
Setting `T_inlet = ref_temp = IC = 300 K` (so boundary cells match the port default):
| Case | scenario | `rho[0]` | result |
|---|---|---|---|
| 1 | pure PK, +5e-4 step, **no** feedback | **0.0** | clean monotonic rise → P=1.65 at 2 s (correct supercritical) |
| 2 | strong α=−0.01 but `fuel.power=0` (TF-07 topology) | **0.0** | identical to case 1 — coolant can't heat, feedback stays 0 |
| 3 | `build_loop_pk` real coupling, α=−0.01 | **0.0** | prompt response then **physical** feedback shutdown to P≈0.1 as coolant heats |

Compare case 3 (`rho[0]=0`, physical shutdown) to the artifact version (`T_inlet=293.15`):
`rho[0]=−0.0685`, power crashed by the 300-vs-293 mismatch. Both land near P≈0.1 but for
**completely different reasons** — one is the Python-intended feedback shutdown, the other an
IC bug.

### 6. The prompt jump is real and already tested (standalone)
Standalone PK, +5e-4 step: asymptotic prompt-jump factor measured `1.074` at +20 ms → `1.083`
(matches `β/(β−ρ) = 0.006502/0.006002 = 1.0833`). **`PK-03c` already asserts this correctly**
(δρ=0.002, sampled at t_step+28 ms). Note a ~1 % first-sample *dip* immediately after the
step (P=0.986 at +10 µs, recovering within ~5 ms) — a stiff-solver-at-discontinuity artifact.
This dip is why "sample-immediately `P_max > P0`" assertions are fragile and float-noise
dependent (the 1.12.5 "dust" that vanished on 1.12.6).

---

## The model is sound; three things are not

1. **IC consistency (the bug).** `build_loop_pk` returns an IC whose boundary coolant cells
   carry the 300 K port default. Any feedback/transient that depends on *absolute* temperature
   is corrupted at t=0. This is a real usability bug, not just a test issue: a user who sets
   `cac.T[i] => 293.15` reasonably expects all cells to start at 293.15.

2. **Test design.** Several coupled tests assert on the contaminated early transient, or on
   sample-immediately prompt-jump that is float-noise fragile, or only on `isfinite`.

3. **Sign-convention divergence from Python (parity trap, not a bug).**
   - Python (`point_kinetics.py:temperature_reactivity`): `ρ_fb = −Σ w·(T−T0)` with a built-in
     minus and **positive** weights `w` (Python tests use `+0.1`, `+1e-1`).
   - Julia (`point_kinetics.jl:274`): `feedback = +Σ α·(T−Tref)` with **no** minus, so Julia
     requires **negative** α (`−0.01`) for stabilizing feedback. Effect is equivalent; the
     conventions are opposite. Worth a docstring note and a parity-aware test.

---

## Per-test audit (meaningful / contaminated / hollow)

### Standalone PK — `test/test_point_kinetics.jl` — SOUND
`PK-01a/b/c/d`, `PK-02`, `PK-03a/b/c/d`, `RC-01`, `SCRAM-01/02`, `TF-01..05`: kinetics math,
IC formula, **prompt jump (PK-03c, well-designed)**, ramp monotonicity, controller/state
machine. No thermal coupling → no artifact. Keep as-is. (`PointKinetics` 1381/1381 green.)

### Coupled loop — `test/test_integration.jl` §5
| Test | What it claims | Reality |
|---|---|---|
| **LOOP-01** | compiles, returns (ssys, ic) | smoke; trivial but fine |
| **LOOP-02** | quiescent stability, no feedback | **meaningful** — PK steady-IC holds in a loop; no artifact (no `temp_worth`) |
| **LOOP-03** | step + weak α=−1e-4 → prompt jump `P_max>P0`, damped | **contaminated** — boundary artifact ≈ −0.00137 vs δρ=0.003; weak α keeps it passing, but the "prompt jump" is muddied + sample-immediately fragile |
| **LOOP-04** | large step → SCRAM fires, terminates | **semi-meaningful** — tests the SCRAM callback plumbing (good); early transient is artifact-contaminated but power eventually crosses plimit |
| **TF-06** | reactivity observable is finite | **hollow** — only `isfinite`; passes for almost any wiring |
| **TF-07** | "strong negative feedback bounds power (analytical)" | **artifact-only + mis-mirrors Python** (see below). 2-lite assertions document the IC bug, not physics |

### Coupled validation — `test/test_validation.jl`
| Test | What it claims | Reality |
|---|---|---|
| **VAL-PK-01** | constant-power loop, coolant rises linearly | **meaningful** (Python `test_channel_point_kinetics` parity). No feedback → no artifact. Steady-degeneracy workaround (`>0.5*P0` guard + transient fallback) is fragile but correct |
| **VAL-PK-02a** | strong α=−0.1 on **fuel** → P→0 | **contaminated/weak** — with α=−0.1 the boundary artifact alone is ≈ −1.4, which crashes P regardless of real feedback; `abs(P)<0.1` can't distinguish physics from artifact |
| **VAL-PK-02b** | strong α=−0.1 on **coolant** → P→0 | same as 02a |
| **VAL-PK-03** | reactivity finite + →0 at late time | early transient artifact-driven; late-time assertion OK |

---

## TF-07 mis-mirrors the Python test

TF-07's comment says it mirrors `test_integrations.py:352-428`. Those two Python tests
(`test_power_is_negligible_for_negative_Tfuel/Tcool_feedback`) are **steady-state solves**
that start from a hot/over-powered guess (`power=1e5`, `T=2·T0`) and assert that the unique
self-consistent critical steady state is `power < 1e-3` at `T = T0`. They contain **no step
insertion and no transient**. TF-07 invented a transient `+5e-4` step scenario and attached
the Python test's name to it. The **correct** Julia mirror of those Python tests is already
`VAL-PK-02a/02b` (steady-state, power→0). TF-07 is therefore **redundant and mislabeled** on
top of being artifact-driven.

---

## The PK steady-state degeneracy (charter dimension 4)

At criticality (`ρ_total = 0`), `dP/dt = 0` for **any** P → P is undetermined by the steady
equations. `solve_steady` (KINSOL) can therefore land on the trivial `P→0` root (documented
in `project_channels_redesign_branch`). This is why VAL-PK-01 needs the `>0.5*P0` guard.

**Principled consistent-IC procedure for PK loops (recommended design):**
1. Choose the operating power `P0` (this *breaks* the degeneracy — P is an input, not solved).
2. Solve the **thermal** steady state with the power source held fixed at `P0·power_scale`
   (PK decoupled during init — exactly the existing `symmetric_plate` / channel steady solve).
   This yields consistent temperatures `T_ss` **including the boundary cells**.
3. Precursors `C_k = β_k/(λ_k·Λ)·P0` (already in `point_kinetics_steady_state`).
4. Start the coupled transient from `(P0, C_k, T_ss, hydraulics_ss)` — the **full** consistent
   state vector (same pattern as the LOF `steady-then-trip` fix).
5. Set `ref_temp` deliberately:
   - **critical-operating-point tests**: `ref_temp = T_ss` → feedback = 0 at t=0 → genuinely
     critical IC → clean perturbation studies (prompt jump, excursion, SCRAM).
   - **feedback-shutdown tests** (Python style): `ref_temp = T_inlet` → reactor is supercritical
     at cold start and feedback drives it down — but the IC is still *thermally consistent*, so
     the only reactivity is the real feedback, not a 300 K boundary glitch.

This also fixes the build-time artifact: step 2 produces correct boundary-cell temperatures, so
no 300 K leak.

---

## Coverage gaps — physics we should test but don't

1. **Genuine prompt jump → feedback turnover in a coupled loop** (consistent IC, `ref_temp=T_ss`,
   real `fuel.power=P·scale`): assert (a) prompt jump `≈ β/(β−ρ)` sampled past the discontinuity,
   (b) power peaks, (c) feedback turns it over, (d) settles to a *new critical* equilibrium
   `0 < P_new`. None of the current tests do this with a clean IC.
2. **Feedback magnitude / sign correctness**, not just "P→0": assert the late-time temperature
   rise satisfies `Σα·(T−Tref) ≈ −ρ_inserted` (reactivity balance), proving feedback strength is
   physically calibrated — distinguishes real feedback from the artifact.
3. **Reactivity-at-t=0 sanity**: assert `reactivity[0] ≈ 0` for a critical IC. This single
   assertion would have caught the entire boundary-cell bug.
4. **Delayed-neutron timescale**: assert the post-prompt-jump rise follows the stable reactor
   period (delayed dynamics), not just "P increases."
5. **SCRAM shutdown transient** with `terminate=false`: verify power actually decays after the
   negative reactivity insertion (currently LOOP-04 terminates immediately, never exercising the
   shutdown curve).
6. **Decay heat** (`PointKineticsWInput` / `physical_models/decay_heat/` in Python) — entirely
   absent in Julia. Out of scope for v1.x but note the gap.

---

## Prioritized recommendations

**P0 — fix the IC bug (model).**
Make `build_loop_pk` return a consistent IC (boundary cells at their physical temperature, not
300 K). Cleanest: the steady-then-perturb procedure above. Minimal stopgap: seed the port/
boundary temperatures in the returned IC and/or solve the algebraic constraints at construction.
Add the `reactivity[0] ≈ 0` regression assertion so this can never silently regress.

**P0 — neutralize the FlowPort/ThermalPort 300 K default trap.**
Decide a policy: either (a) initialize connector temperatures from the loop's inlet BC during
IC construction, or (b) make the default obviously-invalid (e.g. `NaN`) so an unseeded boundary
cell fails loudly instead of silently injecting 6.85 K of feedback. (a) is safer for users.

**P1 — rewrite TF-07 or delete it.**
It is redundant with `VAL-PK-02a/02b` (the real Python mirror) and currently tests an artifact.
Options: (i) delete TF-07 and keep VAL-PK-02; (ii) repurpose it as the **new** coupled
prompt-jump → turnover test (gap #1) on a *consistent* IC. Recommend (ii) — it's the missing
high-value test. Remove the misleading "mirror Python 352-428" comment either way.

**P1 — strengthen VAL-PK-02a/02b** so they distinguish physics from artifact (gap #2:
reactivity-balance assertion), once the IC is consistent.

**P2 — TF-06 and LOOP-03 assertions.**
TF-06: replace bare `isfinite` with a real reactivity-value check on a consistent IC. LOOP-03:
sample the prompt jump past the discontinuity (à la PK-03c), not the fragile immediate `P_max`.

**P2 — document the sign convention** (`α` negative in Julia vs positive `w` in Python) in the
`PointKinetics` docstring, and add one parity-aware test pinning the Julia↔Python sign relation.

**Do NOT** treat the TF-07 "2-lite" assertions as ground truth — they were written to make the
*artifact* green and honest, with an in-code pointer here. They describe a bug's symptoms.

---

## Reproduction scripts
`/tmp/pk_diag.jl` (TF-07 replica + real-coupling), `pk_diag2.jl` (IC/u0 dump),
`pk_diag3.jl` (reactivity equation dump), `pk_diag4.jl` (init-alg comparison),
`pk_diag5.jl` (boundary-cell probe), `pk_diag6.jl` (aligned-IC physics confirmation),
`pk_diag7.jl` (standalone prompt-jump trace). All run with `julia +1.12.6 --project=.`.
