# W-FIXES — finish the `major-overhaul` branch (PR #21)

Charter for the fix work that clears PR #21 to merge. Lives on the branch; delete on completion
(delete-don't-archive). Status line mirrors into tracker #19.

## Goal

Make PR #21 mergeable: green for Aviv/Eshed/CI/users (not just the pinned Manifest), every
reviewer concern resolved, generic fluids folded in, then 3-way sign-off. UQ stays parked on tag
`uq-wip` until after merge.

## Confirmed facts (the diagnosis)

- Suite is green on the committed Manifest (our machine + GitHub CI) but Aviv got ~26 fail / 5
  error on his resolved package versions. All failures are transient/coastdown tests; `mdot`
  reads 0 at every step, or the solve returns `Unstable`/`MaxIters`.
- Root cause: the coastdown tests hand-feed a *partial* IC (`L_el.port_in.mdot => 1.0` + a couple
  branch flows) and rely on `NoInit`. MTK's choice of which variables to keep as **states**
  (`unknowns`) is not stable across versions; when the partial `op` doesn't land on the real
  states, flow defaults to 0 and the coastdown sits frozen at the `mdot=0` fixed point.
- Fix (spike-confirmed): build the loop **with the driving pump**, `solve_steady`, then start the
  transient from a snapshot of **all** `unknowns` with the perturbation as an override and
  `BrownFullBasicInit`. Reproduces the analytic curve exactly and is version-robust (every state
  gets a consistent value regardless of MTK's pick). This also mirrors Python 1:1.
- MTK v11 **requires a symbolic map** for the IC: passing the raw state vector or the solution
  object both error with "The operating_point passed to the problem constructor must be a
  symbolic map." So the snapshot map is the only valid form — and `unknowns` is the complete,
  non-redundant state (observed vars are functions of it).
- Minimal IC (only differential states + `BrownFullBasicInit` rebuilds the algebraic) also works,
  but seeding **all** unknowns is the safer default (gives the algebraic re-solve a converged
  starting guess instead of defaults).

## Core deliverable: helpers in `src/solvers.jl` (Julia overloads)

```julia
state_snapshot(ssys, sol) = [u => sol[u] for u in unknowns(ssys)]

function solve_transient(ssys, sol_ss::SciMLBase.AbstractSolution, t;
                         overrides = Pair[],
                         initializealg = BrownFullBasicInit(), kwargs...)
    op = state_snapshot(ssys, sol_ss)
    append!(op, overrides)
    return solve_transient(ssys, op, t; initializealg, kwargs...)
end
```

Low-level `solve_transient(ssys, op, t; …)` stays. Coastdown becomes
`solve_transient(ssys, sol_ss, t; overrides=[ssys.pump.dP_pump => 0.0])`. General to any
settle→perturb→transient scenario (pump trip, SCRAM, valve/flapper actuation, inlet/heat-flux
step). Caveat: snapshot keys by symbol, so it maps only onto the same compiled `ssys` (override
parameters/forcing, not structure).

## Phases

### Phase 0 — Reproduce the skew, lock the root cause
Copy repo to a throwaway dir, drop `Manifest.toml`, resolve to latest MTK/SciML, run
`test_integration.jl`. Exit: reproduce Aviv's fail/error signature. If it does NOT reproduce,
stop and re-diagnose (likely "didn't instantiate") before code changes.

### Phase 1 — Robust transient initialization (the blocker)
1. Add `state_snapshot` + `solve_transient` solution-overload to `src/solvers.jl`; export.
2. Rewrite affected tests to pump→steady→coast via the overload (Python 1:1):
   #10 RL, #17 friction, #20 two-parallel, #18 flapper, #19 transistor, #5 channel-PK transient.
3. Keep `BrownFullBasicInit` default; rampdown-forcing fallback only if a test won't converge.
4. Delete the misleading "overdetermined / NoInit" comments.
Verify: full suite green on BOTH the pinned Manifest AND the Phase-0 resolve.

### Phase 2 — Reproducibility guard
Add a second CI job that drops `Manifest.toml` and resolves fresh on latest stable Julia,
alongside the pinned-Manifest job. Keep the committed Manifest; keep only `julia = "1.12"`
minimum in `[compat]` (no exact MTK pin). Verify: both CI jobs green.

### Phase 3 — Completeness audit of `test_integration.jl`
Per-test diff vs Python `test_integrations.py` (870 vs 973 lines). Confirm every Python
assertion has a Julia counterpart; add the missing; record in `VALIDATION.md`.

### Phase 4 — Generic fluids #13
Evaluate Aviv's `H2O`/`D2O` `AbstractLiquid` against the agreed `AbstractFluid` + per-fluid
dispatch design; adopt it, replacing the version in `fluids.jl`. Reconcile with #20 snake_case
renames. Verify: fluid tests pass; #13 examples work; parity 526/0/0 holds.

### Phase 5 — Review-comment cleanup
Code changes:
- `@inferred` in `test_fluids`: keep only if it guards a real type-stability contract (+1-line
  comment), else drop.
- Drop `flapper` `stop_on_open` as user-facing; keep internal wiring only if a test needs it.

GitHub replies — **DO NOT auto-post.** Draft all replies, run `/humanizer`, keep them direct and
short, and show Itay for confirmation before anything is posted. Drafts to prepare:
- `resistors.jl` `D_h` removal was W7 geometry-inlining (`3f3ac81`), not UQ.
- PK N-precursor vectorization deferred (note in #19), not this PR.
- (any others surfaced during the work)

### Phase 6 — Re-verify & sign-off
Full suite + both CI jobs green; parity 526/0/0 re-confirmed after 1/4. Coordinate #20
sign-off with Eshed/Aviv. Update `VALIDATION.md` + #19; obtain 3-way sign-off. After merge: UQ
returns from `uq-wip` as its own PR.

## Sequencing
0 → 1 ordered. 2, 3 parallel with 1. 4 is the big independent chunk (parallel). 5 quick, anytime.
6 is the gate, last.

## Working rules (this branch)
- Never create git branches (Itay owns them); never push (Itay owns the PR). Phase-0 throwaway is
  a `/tmp` copy, not a branch.
- Never auto-post to GitHub. Draft → `/humanizer` → show Itay → he confirms → he/we post.
- If anything deviates from this plan, flag it to Itay immediately.
- If a test won't work with the intended change, do NOT give up — exhaust the options and only
  flag once sure it's not possible, with the evidence.

## Deferred (not this PR)
UQ (`uq-wip`) → follow-up PR after merge. PK vectorization → #19. Formatter CI (#10) → stays
deferred.

## Status
- [x] Sync: local == origin/major-overhaul == PR head `e32705a`; UQ tagged `uq-wip`.
- [x] Phase 0 — reproduce skew. Fresh resolve = MTK 11.26.7 / Symbolics 7.26.0 (pinned: 11.26.1 /
  7.23.0); reproduced Aviv's signature exactly (RL `isapprox(0.0,1.0)` at line 191).
- [x] Phase 1 — **DONE. Full integration suite GREEN on BOTH pinned and skew (MTK 11.26.7): all
  306 tests, 0 fail** (was 26 fail + 5 error on skew). Added `state_snapshot` +
  `solve_transient(::AbstractSciMLSolution; overrides, initializealg=BrownFullBasicInit())` overload
  to solvers.jl (+export). Rewrote 5 coastdowns to pump→steady→coast (RL, friction, two-parallel,
  flapper-coastdown, transistor); friction also needed a branch-flow guess so solve_steady doesn't
  `Stalled` at large magnitude on newer NonlinearSolve. #5 channel-PK rewritten to the continuation
  approach (see resolved note below); passes 33/33 on both envs.
- [ ] Phase 2 — repro-guard CI
- [ ] Phase 3 — completeness audit
- [ ] Phase 4 — generic fluids #13
- [ ] Phase 5 — review cleanup (+ GitHub reply drafts)
- [ ] Phase 6 — verify + sign-off

### #5 channel-PK — RESOLVED via continuation (both envs green)
A live coupled feedback-PK `solve_steady` is unreachable in Julia on every MTK version (collapses
to trivial P=0; Python's bespoke algebraic-Jacobian Newton sits on the unstable nonzero root, Julia
solvers won't — verified default/NewtonRaphson/SimpleNewtonRaphson/DynamicSS, both worth signs,
Λ=1, homotopy-seeded at the root). Python ground truth (ran in conda `stream-env`): P=17.25, coolant
linear 31→38.6, fuel above ref. **Final #5:** build the same shared-power channel+fuel loops, find
the self-consistent critical power by continuation (bisect the shared power until the uniform-worth
feedback reactivity vanishes ⇔ total temp-excess over T0 = 0; each constant-power steady solves
robustly), then assert Python's exact check — each channel's coolant strictly increasing + linear,
plus nonzero critical power and distinct per-mdot slopes. Live feedback-PK→channel coupling stays
covered by #8/#9. Documented in the test comment.

### (historical) #5 investigation notes
The hand-built IC covered only 74/112 unknowns (missed 43 `cac.thermal_left/right[j].T` contact
nodes + `fuel.power`). Completing the IC fixes the PK blow-up (P→1.0) and #5 passes on pinned under
every solver/tolerance. **On skew the stiff PK+thermal transient is `Unstable` within the first
step** — immune to: complete IC, 6 stiff solvers (Rodas5P/FBDF/QNDF/Rodas4/TRBDF2/Rosenbrock23),
analytic vs numerical vs no Jacobian, reltol/abstol 1e-8..1e-10, dtmax caps. u0 and f(u0) are
finite and *identical* on both envs → genuine MTK 11.26.7 structural/integration regression.
**KEY: Python's test_channel_point_kinetics uses a FEEDBACK PK + `solve_steady` + asserts only
coolant linearity** (random temp_worth on every channel+fuel, ref_temp=T0, Tin=T0-10, Λ=1). The
Julia port had DIVERGED — bare critical PK (no feedback) + fragile transient + extra P=1/slope
asserts. The 1:1 fix is to mirror Python (feedback PK + solve_steady + linearity).

**Blocker (exhaustively spiked):** Julia's `solve_steady` always collapses to the trivial **P=0**
root. Reason: for this feedback PK, **P=0 is the dynamically STABLE root, the nonzero root is
UNSTABLE** (cold coolant→subcritical→power decays). Python's solve_steady is a *local Newton from
a close guess* so it sits on the unstable root; Julia's globalized polyalgorithm AND `DynamicSS`
both correctly fall to P=0. Tried: Λ=1 (Python value), both worth signs, |α|∈{0.05..1.0},
near-root linear guesses, DynamicSS — all → P=0. The thermal *steady* itself is fine on skew
(constant-power gives exact slopes 0.142857/0.204082/0.357143); the thermal *transient* is the
MTK-11.26.7 regression. **GROUND TRUTH** (ran Python in conda `stream-env`): Python's steady is nonzero **P=17.25**,
coolant rises linearly 31.2→38.6 (below ref 40), **fuel 42→49.4 (above ref)** — positive worth
~0.4-0.96; it asserts ONLY coolant linearity (diff>0, diff(diff)≈0), not the power or slope.

**EXHAUSTIVE RESULT — a byte-for-byte 1:1 (coupled feedback PK + solve_steady) is NOT achievable
in Julia, on ANY MTK version.** Confirmed `solve_steady` on the coupled feedback PK collapses to
the trivial **P=0** on BOTH pinned and skew (Julia's MTK steady zeros dP/dt via P→0, not via
ρ→0; Python's bespoke ALG_jacobian Newton finds the nonzero root, Julia's stack will not). Tried:
default / NonlinearSolve.NewtonRaphson / SimpleNonlinearSolve.SimpleNewtonRaphson / DynamicSS;
positive AND negative worth; Λ=1 (Python value); and a homotopy that bisects the constant-power
power to where ρ=0 (P*≈11.68) and seeds the solve essentially AT the root — still P=0. The
critical-PK transient (the original author's workaround for this exact non-portability) works on
pinned but is the MTK-11.26.7 regression on skew. The constant-power steady is robust on skew.

**Robust options (none runs a live coupled PK solve_steady — that's impossible in Julia):**
(A) Homotopy: compute the self-consistent critical power P* (feedback reactivity ρ=0) via robust
constant-power steadies, assert linear coolant at that state — reproduces Python's exact physical
steady (feedback-balanced power + linear coolant) on all MTK versions. (B) Keep the critical-PK
transient, pin to Manifest, document + file an MTK issue (red on latest). (C) Constant-power
steady at P=1 (linear coolant only, no feedback balance). (D, untried) feedback PK + integrate
from the P* homotopy seed (live PK, but risks the skew transient instability). **DECISION NEEDED.**
