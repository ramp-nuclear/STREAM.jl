# WF — Flapper rework (charter for a dedicated session)

Goal: make STREAM.jl's `Flapper` faithful to Python STREAM in **what it does**, robust in
**how it solves**, and ergonomic in **how it's used**. The flapper is the weakest of the 21
integration ports (it scored ~80/100 in the WV UAT) because the *opening mechanism* was
worked around, not implemented. This workstream replaces the workaround with a real,
researched implementation.

**Hard rule for the session: research first, decide from evidence.** Itay's calls on the
open design questions were "try everything and find the most stable solution" — so the
session is spike-heavy. Do NOT commit to an API until the mechanism spikes pass. Lean on the
`modelingtoolkit-jl` skill throughout.

---

## Why now / what depends on it

- Integration ports **#14 (`flapper opens with ref_mdot`)**, **#15 (`flapper and pump`)**,
  **#18 (`inertia with flapper in PCS coastdown`)** all depend on the flapper. The other 18
  ports are done and reviewed.
- The Loss-of-flow transient in `test_examples.jl` also uses the flapper (`build_loop_lof_bypass`
  + `flapper_callback`) — must keep converging after the rework.
- WV (the 1:1 validation review) is **paused at #12 of 21**. After WF, resume the UAT at #13
  and finish through sign-off; by then #14/#15/#18 will be the clean versions.

## The root problem (diagnosed from the code)

**Python's flapper does not root-find. It does a per-accepted-step state check.**
`stream/calculations/flapper.py` → `change_state`:

```python
def change_state(self, ..., ref_mdot, t):
    if ref_mdot <= self.mdot0 and np.isposinf(self.t_open):
        self.t_open = float(t)          # latch on first step ref_mdot crosses the threshold
```

The Aggregator calls this every accepted step, hands it the externally-wired `ref_mdot`, and
the flapper latches `t_open`. It's approximate to the step size — hence Python uses
`max_step_size=1e-3` and asserts `rtol=1e-3`.

The Julia port expressed this as a **`ContinuousCallback` (root-find)**, which must evaluate
`ref_mdot` at the solver's *trial* states. When `ref_mdot` is algebraic (no inertia, as in
#14) there is no clean way to do that, so #14 hardcoded the analytic crossing
`p·exp(-t) − 0.1` into the callback. The mechanisms never matched, and the `t_open` assertion
became circular (the callback sets `T_open` to the root it was handed).

**Leading hypothesis for the fix: a `DiscreteCallback` (per-accepted-step check) mirrors
Python exactly** — at accepted steps `integ[ssys.flapper.ref_mdot]` is well-defined for
algebraic *or* state `ref_mdot`, so the condition is literally Python's `change_state`. But
**Itay notes a prior attempt with "continuous or discrete didn't work"** — so step 0 of the
session is to reproduce and *diagnose those prior failures* before re-trying, not assume the
DiscreteCallback just works.

## Known failure modes to diagnose first (from code + comments + git)

Before spiking solutions, reproduce and explain each of these so the spikes don't repeat them:

1. `flapper_callback` docstring (current): `integrator[observed_sym]` in a `ContinuousCallback`
   condition "reads `integrator.u` (last accepted step), causing both the step-start and
   step-end sign evaluations to return the same value and preventing zero-crossing detection."
   → why this kills the continuous-on-algebraic path.
2. `Inf` in the state vector destabilizes `Rodas5P` → the current `T_open = 1e30` sentinel hack.
3. `variable_index(ssys, monitored_sym)` returns `nothing` for an algebraic `ref_mdot` → the
   current callback's state-index path doesn't apply, and the `integrator[sym]` fallback is
   the broken path from (1).
4. Check `git log` on `src/components/flapper.jl` + `test_flapper.jl` for the earlier
   discrete/continuous attempts Itay referred to; capture what specifically broke.

## Design questions — research matrix (Itay: "try everything, find the most stable")

### Q1. Detection mechanism — **spike all, choose by stability**
Candidates, each tested on THREE regimes: (a) algebraic `ref_mdot` (no inertia, #14),
(b) state `ref_mdot` (with inertia, #18), (c) across flow reversal.
- **A. `DiscreteCallback`** (per-accepted-step check of `integ[ssys.flapper.ref_mdot]`, latch
  `T_open`). Closest to Python's `change_state`. Step-resolution `t_open` (add `max_step_size`
  or `tstops` for precision, like Python).
- **B. `ContinuousCallback`** root-finding the real `ref_mdot` crossing, evaluating the observed
  function at trial state via `ModelingToolkit.build_explicit_observed_function(ssys, ref_mdot)`
  called as `obsf(u, p, t)` in the condition (NOT `integrator[sym]`). This is the untested
  path that might fix the (1) failure mode — verify whether the observed function can be
  evaluated at trial `(u,t)`.
- **C. Hybrid** — continuous when `ref_mdot` is a state (exact timing), discrete otherwise.
- Decision criteria: faithfulness to Python's mechanism, numerical stability (no
  `InitialFailure`/`Unstable` across the 3 regimes), `t_open` accuracy, simplicity.
- Recommendation going in: **A (DiscreteCallback) as the faithful default**; keep B only if a
  use-case needs sub-step precision and the spike proves it stable.

### Q2. `T_open` representation — **spike both**
- **State** (current): `D(T_open) ~ 0`, mutated via `integrator.u[idx]`, needs the `1e30`
  sentinel. **Parameter (discrete/tunable)**: mutated via `integrator.ps[...]` in the callback,
  allows real `Inf`, removes the fake ODE. Verify the parameter form composes with
  `ifelse(t <= T_open, ...)` in the equations and survives `mtkcompile`.
- Recommendation going in: **discrete parameter** if the spike confirms it; else fall back to
  the state form.

### Q3. Relaxation — **DECIDED: cdr everywhere** (Itay's call)
Use `continuously_differentiable_relaxation` (`−2x³ + 3x²`, clamped [0,1]) for all flappers.
NOTE the deliberate divergence from Python: Python *defaults* to `legacy_relaxation`
(`x/√(4^(10(1−x)))`) and only #18 passes `cdr`. Document that Julia standardizes on `cdr`; the
ramp *shape* differs from Python for #14/#15 but the open/closed binary (what the assertions
test) does not. (If a future need for exact ramp parity arises, make it a configurable arg.)

### Q4. `ref_mdot` wiring ergonomics — **spike the connector, keep the equation as fallback**
- **Equation (current):** `flapper.ref_mdot ~ source.port_in.mdot` — transparent, no magic.
- **Dedicated reference connector:** so it reads `connect(flapper.reference, source.<outlet>)`.
  Itay: "looks good but I have no idea if it works." Spike whether a one-variable reference
  connector (a `@connector` exposing the monitored flow) composes cleanly and is read correctly
  by the detection callback. If it works and reads well, prefer it; else keep the equation plus
  a thin `watch(flapper, sym)` helper.

## Other faithfulness fixes the rework must include (not just the callback)

- **Open-state sign convention.** Python: `mdot_calc = −sign(dp)·√(2ρA²|dp|/f)`;
  Julia: `mdot_open = +sign(dp)·√(…)`. Opposite sign — the same "positive-downward vs
  drop-along-flow" trap as #16's gravity. Pin it NUMERICALLY against Python's
  `mdot_by_local_pressure(dp, ρ, f, A) = sign(dp)·√(2ρA²|dp|/f)`, don't eyeball.
- **Reverse-flow inlet temperature.** Python uses `directed_Tin(Tin, Tin_minus, mdot)`;
  Julia uses `instream(port_in.T)`. Verify equivalence under reversal.
- **Ergonomics:** `flapper_callback(ssys, flapper)` should read `open_at_current` and the wired
  `ref_mdot` OFF THE COMPONENT (today the threshold + monitored symbol are passed by hand).
  Add multi-flapper composition (`CallbackSet`), `open(t)`/`close()` parity (Python has both),
  and optional `stop_on_open` (terminate-on-open; Python's `stop_on_open`/`should_continue`).

## Plan of work

- **WF.0 Diagnose** the prior discrete/continuous failures (the "Known failure modes" list).
- **WF.1 Spikes** (throwaway, /tmp): Q1 (A/B/C × 3 regimes), Q2 (param vs state), Q4 (connector),
  and a numeric open-state sign/quadratic check vs Python. Use `modelingtoolkit-jl` skill.
- **WF.2 Design** the API from spike evidence; write it down; Itay reviews before implementation.
- **WF.3 Implement** reworked `Flapper` + detection callback + cdr relaxation; humanized
  docstrings; unit tests in `test_flapper.jl`.
- **WF.4 Re-port #14/#15/#18** onto the clean API (delete #14's hardcoded-analytic callback;
  the `t_open` assertion becomes a real test of detection). Re-verify the LOF transient in
  `test_examples.jl`. Full suite green, MTR parity held at 526 CLEAN / 0 / 0.

## Acceptance criteria

- Flapper opens by watching a real wired reference flow that reaches the threshold — same idea
  as Python — with no hardcoded analytic anywhere.
- #14 `t_open ≈ log(10)` is a genuine consequence of detecting the simulated `ref_mdot`
  crossing, not a self-fulfilling callback.
- #14/#15/#18 pass; full suite green; parity unchanged.
- API reads cleanly for a user (constructor + wiring + one callback call), documented.

## References

- Python: `~/projects/STREAM/stream/calculations/flapper.py` (`Flapper`, `change_state`,
  `continuously_differentiable_relaxation`, `legacy_relaxation`, `open`/`close`,
  `stop_on_open`); `mdot_by_local_pressure` in `physical_models/pressure_drop`.
- Julia: `src/components/flapper.jl` (`Flapper`, `flapper_callback`); ports in
  `test/test_integration.jl` (#14, #15, #18); LOF in `test/test_examples.jl`.
- Validation tracker: `VALIDATION.md`. Program tracker: GitHub issue #19, `WORKPLAN.md`.
