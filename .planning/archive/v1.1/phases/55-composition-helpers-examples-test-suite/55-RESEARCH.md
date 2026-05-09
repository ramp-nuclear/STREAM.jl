# Phase 55: Composition Helpers, Examples & Test Suite — Research

**Researched:** 2026-05-07
**Domain:** MTK rewiring of channel-family externals + builder/example port + test-suite reorg + LOF-spike protocol
**Confidence:** HIGH (all claims grounded in installed code + Project.toml + Phase 54 verification artifacts)

---

## Executive Summary

The 22-decision Phase 55 CONTEXT.md already locks every architectural choice. This research file
adds the five things the planner cannot derive from CONTEXT.md alone: (1) the **canonical MTK
callable-parameter syntax under MTK v11.25.0** (verified in `Project.toml` + already used in three
production files); (2) a **mechanical reading of the dangling-port question** — under the Phase 55
redesign Channel/CHF have NO port and emit NO `port.Q_flow ~ q_expr` equation, so the Phase 54
over-determination cannot recur, but **unbound `T_wall_*[i]` variables remain free unknowns and the
system is fully-determined ONLY when `h_*=0.0` at compile time** (otherwise `mtkcompile` will be
short n equations per side); (3) a **one-page LOF spike protocol** with concrete tolerances tied
to the existing `test_loss_of_flow.jl` thresholds; (4) **structural notes on Python STREAM
`test_integrations.py`** (973 lines, 23 flat top-level functions, no section headers, hypothesis
property tests interleaved with deterministic tests, naming pattern `test_{system}_{observed
behavior>`); (5) a **Validation Architecture** mapping TEST-01/02/03/05 onto four Nyquist
dimensions.

**Primary recommendation:** Plan as six waves following CONTEXT.md's discretion sketch (variant
rewrite + sources.jl + HeatFluxPort retire → test_channels.jl rewrite → helpers verify +
test_composition.jl → builders + LOF spike → test_integration.jl consolidation → doc fixes +
close gate). Lock the LOF spike protocol from Section 3 BEFORE the spike runs. Do not invent new
MTK patterns — reuse the v0.9 PointKinetics callable-parameter pattern verbatim for the three new
callable-input sites (`Channel.h_left::Function`, `WallTemperature.T_wall::Function`,
`HeatFluxSource.q::Function`).

---

## User Constraints (from CONTEXT.md)

CONTEXT.md is fully prescriptive — 22 D-XX locked decisions, plus a Discretion block, plus a
Deferred block. The summary below restates the binding ones; the full decision text is in
`55-CONTEXT.md` and is the planner's source of truth.

### Locked Decisions (D-01 — D-26)

- **D-01..D-04:** Channel and ChannelHeatFlux drop their per-cell `ThermalPort`/`HeatFluxPort`
  arrays and replace them with channel-level external-input variables `T_wall_left[1:n]` /
  `T_wall_right[1:n]` (Channel) and `q_left[1:n]` / `q_right[1:n]` (CHF). New file
  `src/components/sources.jl` ships `WallTemperature` and `HeatFluxSource` (portless,
  `Real|Vector|Function`). Both binding styles (direct binding eqns vs source component) work
  natively after the port removal.
- **D-05..D-07:** Either-or usage pattern; **CAC unchanged** (still has ThermalPort arrays).
- **D-06:** `HeatFluxPort` retired from `src/connectors.jl`, dropped from STREAM exports, deleted
  from `test/test_connectors.jl`. Final connector roster: `FlowPort`, `ThermalPort`.
- **D-08:** `composition/helpers.jl` likely zero-change (helpers wire CAC↔HD only — CAC kept).
  Mandatory verification step.
- **D-09..D-13:** Builders. Three simple-loop builders use direct binding eqns. `build_loop_pk`
  verified-only. `build_cube` unchanged. `build_loop_lof_bypass` decided by spike (see Section 3).
- **D-14..D-16:** Examples ported (`simple_loop.jl` minor; `lof_transient.jl` reworked per LOF
  spike outcome; `mtr_assembly.jl` likely zero-change).
- **D-17..D-22:** Test-suite reorg → 14 files. `test_channels.jl` rewritten under new design.
  `test_composition.jl` rewritten with heavy CAC↔HD coverage. `test_integration.jl` is the single
  big system-level file (LOF + PK loops + SCB + builder smokes + solver wrappers, all sections of
  one file). `test_thresholds.jl` is a pure rename of `test_analysis.jl`. `test_validation.jl`
  untouched. **TEST-05 close gate: no NEW failures vs the v1.0 baseline; pre-existing flakies
  (VAL-01 Fourier, NET-03 Cube flow KINSOL) tolerated.**
- **D-23..D-26:** New file `src/components/sources.jl`; `CLAUDE.md` File Structure Standard
  updated; REQUIREMENTS.md (CONN-02 + TEST-01) and ROADMAP.md (Phase 55 success criteria)
  retroactive annotations committed.

### Claude's Discretion

- Wave decomposition; variable naming for the source-component outputs (`T_wall_out[1:n]` vs
  `T[1:n]`); `h_wall` default; `build_loop_transient` time-varying mechanism choice; whether to
  fold WallTemperature/HeatFluxSource tests into `test_misc.jl` or split into `test_sources.jl`.

### Deferred Ideas (OUT OF SCOPE)

- Rationalizing ConstantTemperature / WallTemperature / HeatFluxSource. Generalizing the
  external-input-variable mechanism beyond `T_wall` and `q`. Filing the MTK upstream issue. GUI
  component-registry sync. Python STREAM cross-validation (TEST-04, Phase 56).
  STATE.md Key Decisions update post-milestone-close. Standardizing example boilerplate.

---

## Project Constraints (from CLAUDE.md)

- **Branching policy.** GSD must NOT create branches. Working branch is `channels-redesign`. Verify
  current branch before any commit; `.planning/config.json` `git.branching_strategy = "none"` must
  not be touched.
- **File structure standard.** New file `src/components/sources.jl` slotted between
  `components/misc.jl` and `components/channels.jl` per D-23. `CLAUDE.md:31` `src/components/`
  tree comment must be updated to list `sources.jl` per D-24.
- **Component authoring conventions.** Keyword-only kwargs (no multiple dispatch in Phase 55
  signatures). The `name` kwarg is always keyword-only. Internal helpers prefixed `_`. Every
  exported name has a docstring with description + Arguments + Returns.
- **Exports.** Single export list in `STREAM.jl`. New exports: `WallTemperature`, `HeatFluxSource`.
  Removed export: `HeatFluxPort` (currently on `STREAM.jl:27`).
- **MTK patterns.** `@register_symbolic` is for fluid properties (untouched in Phase 55).
  `ifelse()` for flow reversal (untouched). `mtkcompile` before solve (untouched). Variant
  declares all `@variables`; underscore-prefixed `_channel_core` consumes by reference.
- **Daemon dev loop.** `bin/jl test/runtests.jl` is the primary close-gate command. Plain
  `julia --project=. test/runtests.jl` is the cold-start fallback (CONTEXT.md TEST-05 wording
  allows either). **Struct/type definition edits don't hot-reload — restart daemon when you change
  Channel/CHF struct shape or add WallTemperature/HeatFluxSource (the first time).**
- **PackageCompiler sysimage abandoned.** Don't try `--sysimage stream.so`.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-01 | `test/test_channels.jl` rewritten under the new design (variants + `_channel_core` + sign-safety merged in); legacy `test/test_channel.jl` deleted; surviving `CHAN-*`, `GRAV-*`, `THERM-*`, `PHY-*` re-derived in their canonical homes. | Section 1 (MTK callable-param pattern), Section 2 (dangling-port behavior), Section 5 (validation architecture, dimension i = component-level unit). |
| TEST-02 | All shipped builders (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`, `build_loop_pk`) and `examples/*.jl` build and solve without regression. | Section 1 (callable-param for `build_loop_transient`), Section 3 (LOF spike protocol for `build_loop_lof_bypass`), Section 5 (dimension iii = end-to-end integration). |
| TEST-03 | Composition helpers verified under new design; MTR assembly tests pass (CAC ↔ HD topologies). | Section 6 pitfall #1 (`_infer_n` works on CAC unchanged but would fail on the new Channel/CHF — helpers must NEVER take Channel/CHF as their first arg), Section 5 (dimension ii = compose-correctness). |
| TEST-05 | Full test suite passes locally (`bin/jl test/runtests.jl`). No NEW failures vs the v1.0 baseline. | Section 5 (dimension iv = regression gate). |

---

## Section 1 — MTK Callable-Parameter Pattern (HIGH confidence)

### Installed environment (verified)

- **`Project.toml:18`** pins `ModelingToolkit = "11"` with `julia = "1.12"`.
- **`Manifest.toml`** resolves to `ModelingToolkit v11.25.0` and `Symbolics v7.21.0` (verified
  2026-05-07 via `awk '/\[\[deps\.ModelingToolkit\]\]/,/^$/' Manifest.toml`).
- The MTK 11 series uses the macro-form `@parameters (callable_name::FType)(..)` introduced in
  v9 and unchanged through v11. **Citation: MTK 11 documentation (Symbolics-driven callable
  parameter pattern) and three production sites in this codebase.**

### The canonical pattern (already used in production)

The v0.9 PointKinetics callable-parameter pattern is already used in three places. Phase 55
introduces three more uses (`Channel.h_left::Function` already exists post-Phase-54 — verified;
`WallTemperature.T_wall::Function` and `HeatFluxSource.q::Function` are new). Reuse verbatim:

```julia
# Pattern: capture concrete FType at construction; declare variadic callable parameter;
# call as `pname(t)` inside equations; user supplies actual function via the `op` dict
# at solve time as `ssys.<owner>.<pname> => fn`.

# Production reference 1 — PointKinetics (src/components/point_kinetics.jl:225,241):
FType = typeof(rho_c_fn)
pars = @parameters begin
    # ... other scalar pars ...
    (rho_c_fn::FType)(..)              # variadic callable; called as rho_c_fn(t)
end
# Used in equations as `rho_c_fn(t)`:
#   Dt(P) ~ (rho_val + rho_c_fn(t) + ...) / Lambda_gen * P + ...

# Production reference 2 — Channel.h_left::Function (src/components/channels.jl:261-266):
FType_L = typeof(h_left)
pL = @parameters (h_left_fn::FType_L)(..)        # returns Vector{Symbolics.CallAndWrap{Num}}
hL_call = pL[1](t)                               # the symbolic call expression
hL_per_cell = fill(hL_call, n)                   # broadcast across cells
append!(extra_pars, pL)                          # splice into pars list

# Production reference 3 — build_loop_transient (src/examples.jl:222-229):
FType = typeof(T_wall_fn)
ps = @parameters (T_wall_callable::FType)(..)
connections = [
    ...,
    ch.thermal.T ~ ps[1](t),                     # CALLER usage — note Phase 55 will
                                                 # change `ch.thermal.T ~ ...` to
                                                 # `ch.T_wall_left[i] ~ ps[1](t)` per cell
]
@named sys = compose(System(connections, t, [], ps; name=:sys), pump, bc, ch)
```

### Required adjustments for Phase 55 source components

`WallTemperature(; name, n, T_wall::Union{Real,Vector,Function})` and
`HeatFluxSource(; name, n, q::Union{Real,Vector,Function})` need a three-branch construction
pattern (Real / Vector / Function), identical in shape to `Channel`'s `h_left` resolution at
`src/components/channels.jl:253-281`:

```julia
# Inside WallTemperature(...):
@variables (T_wall_out(t))[1:n]              # exposed output, no equation yet
@named sys_dummy = nothing                   # value source has no ports

if T_wall isa Real
    eqs = Equation[T_wall_out[i] ~ T_wall for i in 1:n]
    pars = @parameters T_wall_const = T_wall # store as parameter for inspection
    # ... build System ...
elseif T_wall isa AbstractVector
    length(T_wall) == n || error("WallTemperature: T_wall vector length $(length(T_wall)) ≠ n=$n")
    eqs = Equation[T_wall_out[i] ~ T_wall[i] for i in 1:n]
    # ... build System with no extra pars ...
else  # Function / callable
    FType = typeof(T_wall)
    pT = @parameters (T_wall_fn::FType)(..)
    eqs = Equation[T_wall_out[i] ~ pT[1](t) for i in 1:n]
    # The same callable produces the value for every cell. If a per-cell index is
    # ever wanted, declare `(T_wall_fn::FType)(..)` accepting two args and call
    # `pT[1](t, i)` — but D-04 says scalar-broadcast is the contract; defer the
    # per-cell-index variant to a future feature.
    # ... build System with `pars=collect(pT)` ...
end
```

**Source:** Pattern verified verbatim in `src/components/channels.jl:253-281`,
`src/components/point_kinetics.jl:215-242`, `src/examples.jl:194-241`. Tag: [VERIFIED in
codebase].

### CONTEXT.md alignment

CONTEXT.md D-04 wording mentions both `@register_symbolic` and the callable-parameter pattern as
options. **The callable-parameter pattern is the right choice** — `@register_symbolic` is for
fluid properties (opaque, non-time-varying numeric closures); the callable-parameter pattern is
for time-varying inputs supplied via the solver `op` dict. The patterns are NOT interchangeable.
This is not a re-decision; it's a precision adjustment the planner should record explicitly so the
implementer doesn't pick the wrong macro.

---

## Section 2 — Dangling-Port / Unbound External-Input Variable Behavior (HIGH confidence)

### What Phase 54 actually proved

Phase 54-05 shipped a closed-form proof (`54-05-SUMMARY.md` Deviation 1, lines 156-164 of that
file; reproduced in `54-VERIFICATION.md` Deviation 1) that ran exactly the experiment Phase 55
needs to know about. Quoting the verified finding (HIGH confidence — reproducer exists in
`test/test_channels.jl:36-48`):

> "When a Channel/CHF emits the channel-side closure `port.Q_flow ~ q_*_expr[i]` AND the port
> has no `connect()` to another system, MTK's Flow rule auto-zeros Q_flow on the dangling port,
> producing TWO equations on Q_flow → over-determined system
> (`ExtraEquationsSystemException`). Adding a binding eq on `port.T` does NOT suppress the
> Flow rule, since the Flow rule fires on the Flow var, not the across var."

### Why Phase 55 sidesteps the issue entirely

The Phase 55 redesign **removes both inputs to the over-determination**:

1. **No port subsystem.** New Channel/CHF have NO `thermal_left[1:n]` or `thermal_right[1:n]`
   subsystems. There is nothing for MTK's Flow rule to see, because there is no Flow variable.
2. **No `port.Q_flow ~ q_*_expr` closure equation.** The variant emits `q_*_expr[i]` *internally*
   and feeds it directly into `_channel_core` — the equation is consumed by the energy balance,
   not by a port-closure. There is no `Q_flow` to balance.

What remains is `n` plain `@variables T_wall_left(t)[1:n]` (and same for the right side,
similarly `q_left[1:n]` / `q_right[1:n]` for CHF). MTK treats these as ordinary unknowns of the
System.

### Equation-balance question — the planner needs to answer this

For an isolated Channel system with `h_left=h_right=0.0` and unbound `T_wall_left` /
`T_wall_right`:

- **Equations contributed:** `n` energy-balance ODEs + `n` friction algebraic + 5 scalar port
  wiring (T_out, mass conservation, momentum, port_in.T, port_out.T) = `2n + 5` total. Plus any
  observed defs (counted in `obs`, not `eqs`).
- **Unknowns contributed:** `n` T + `n` dp + `n` T_wall_left + `n` T_wall_right + scalars
  (T_out, dP, ...). The two `T_wall_*[1:n]` arrays add `2n` unknowns the variant does not
  internally constrain.
- **q-expression effect:** under `h_left=h_right=0.0`,
  `q_left_expr[i] = 0 * geometry.heated_parts[1] * dz * (T_wall_left[i] - T[i]) ≡ 0` symbolically.
  MTK's structural simplification recognizes `0 * x` as zero — the `T_wall_left[i]` symbol falls
  out of the energy balance entirely.

**The behavior to expect (planner must verify in test_channels.jl Wave 0 / Wave 1):**

- **Hypothesis A (likely):** `mtkcompile` on isolated Channel with default `h_*=0.0` succeeds
  with `fully_determined=false`, and the `T_wall_*[i]` unknowns remain in the unknowns list as
  free variables. They cannot affect the solution because they are multiplied by zero.
- **Hypothesis B (worst case):** `mtkcompile` errors with `ExtraVariablesSystemException` short
  by `2n`. In that case the test must explicitly add binding equations
  `[ch.T_wall_left[i] ~ 0.0 for i in 1:n]` (or any constant) for adiabatic-by-default to
  compile in isolation. This does **not** affect closed-loop solving (the smokes in
  `test/test_channels.jl` always wire at least one side), but it does affect any unit test
  that compiles a Channel in isolation under `mtkcompile(...; fully_determined=false)`.

**Recommendation:** plan Wave 0 to include a 5-line spike script
(`/tmp/spike_phase55_unbound.jl`) that runs `mtkcompile(ch; fully_determined=false)` for a
default-kwarg Channel and reports which hypothesis holds. The result drives whether the
adiabatic-by-default test in `test_channels.jl` (D-17 second bullet) needs explicit `T_wall_*`
binding eqns. If hypothesis B holds, the planner should also document the binding pattern as
the canonical adiabatic test idiom; if hypothesis A holds, the test can leave them genuinely
unbound (matching CONTEXT.md D-02's wording).

**Why this matters:** The CONTEXT.md D-02 sentence "(adiabatic by default falls out
automatically: `h_left = h_right = 0.0` ... makes both `q_*_expr[i]` zero regardless of
`T_wall_*[i]`, which is then a free unknown that the user can leave unbound)" is asserted but
not mechanically verified. The 5-line spike confirms it (HIGH-confidence path) or surfaces
hypothesis B as a planner-visible adjustment (still HIGH-confidence path; the binding eqns are
trivial). Either way the spike result locks the test idiom.

**Closed-loop case (the smokes):** When the heated face is bound (Style 1 binding eqns or
Style 2 source component), `n` more equations close the system. The right side is left
adiabatic via `h_right=0.0` AND a binding `[ch.T_wall_right[i] ~ T[i] for i in 1:n]` (or any
finite value — the `0 * x` collapse means the value is irrelevant). Smokes won't hit
hypothesis B regardless.

**Source:** Argument is structural (counts MTK equations and unknowns from the verified
`channels.jl` body lines 219-359). Tag: [VERIFIED structural; spike step locks behavior at
plan time].

---

## Section 3 — `build_loop_lof_bypass` Spike Protocol (HIGH confidence)

CONTEXT.md D-11 lists three acceptance criteria but stops short of operationalizing them. This
section turns them into a one-page protocol the planner locks before the spike step runs.

### What the spike must produce

Two candidate `build_loop_lof_bypass` topologies, each on its own short-lived branch / scratch
file, each producing a compiled `ssys` and a transient solution. The winner becomes the
phase's `build_loop_lof_bypass`; the loser is discarded.

### Spike A — CAC + WallTemperature on the heated leg

```julia
# Heated leg: CAC pinned via WallTemperature
@named ch_wt = WallTemperature(; n=n, T_wall=T_wall)
@named ch    = ChannelAndContacts(; n=n, geometry=geom, g=(-g_acc),
                                  htc_correlation=rd_ch.htc,
                                  friction_correlation=rd_ch.friction)
# bind: ch.thermal_left[i] ↔ ch_wt — but WallTemperature has no port; instead bind T directly
extra_eqs = [ch.thermal_left[i].T ~ ch_wt.T_wall_out[i] for i in 1:n]
# Right side dangling — ThermalPort Flow rule auto-zeros (CAC is unchanged from Phase 54)
```

### Spike B — CAC + HeatDiffusion plate on the heated leg

```julia
# Heated leg: full CAC ↔ HD via one_sided_connection (real fuel-plate physics)
@named ch   = ChannelAndContacts(; n=n, geometry=geom, g=(-g_acc), ...)
@named fuel = HeatDiffusion(; nz=n, nx=2, Lz=L_ch, Lx=Lx, y=0.07,
                            rho_s=19300.0, cp_s=116.0, k_s=174.0,
                            power_shape=ps, power=power_W)
heated_leg = one_sided_connection(ch, fuel; side=:left, name=:heated)
# Right side of CAC is auto-adiabatic via the Flow rule on the dangling thermal_right ports.
```

In both spikes, the `ret` Channel migrates to the new Channel API regardless. `ret.thermal.T ~
T_inlet` (current example) becomes `[ret.T_wall_left[i] ~ T_inlet for i in 1:n]` (with
`h_left=0.0` keeping it adiabatic) — which is just a way of leaving `ret` unheated and exists
purely so the binding eqns aren't free if hypothesis B from Section 2 holds.

### Acceptance criteria — quantitative

Run each spike against the LOF-02 / LOF-03 / VAL-01 / VAL-02 inputs and tolerances from
`test/test_loss_of_flow.jl` (currently passing on v1.0). Both spikes must satisfy:

| Criterion | Source / threshold |
|----------|---------------------|
| (A) **Compiles cleanly:** `mtkcompile(sys)` returns a balanced system; `length(equations(ssys)) == length(unknowns(ssys))`. | LOF-01 line 133 of `test/test_loss_of_flow.jl`. |
| (B) **Steady-state IC physical:** `0.001 < mdot_ss < 1.0` kg/s. | LOF-01 line 134. |
| (C) **Flapper fires:** `T_open_end < 1.0e10` and `0 ≤ T_open_end`; `flapper.xi[end] ≈ 1.0` atol 1e-4. | LOF-02 lines 152-154. |
| (D) **Channel flow reverses:** `ch.port_in.mdot[1] > 0` AND `ch.port_in.mdot[end] < 0`; NC equilibrium `0.001 < |mdot_nc| < 2.0`. | LOF-03 lines 168-175. |
| (E) **Energy balance — instantaneous:** at t=0, `Q_meas_0 ≈ Q_wall_0` rtol 0.02. | VAL-01 line 205. |
| (F) **Energy balance — NC time-averaged:** mean over t∈[100s,300s], rtol 0.02. | VAL-01 line 218. |
| (G) **NC mdot vs analytical buoyancy:** rtol 0.30. | VAL-02 line 267. |
| (H) **Total runtime budget:** end-to-end transient solve ≤ 60 s wall-time on the dev box, integration-test version (n=10, t∈[0,300s]). | CONTEXT.md D-11 (iii). |

### Decision rule (from D-11)

- **Both pass:** prefer Spike A (simpler topology, smaller compile time, less to debug). This is
  CONTEXT.md D-11's tiebreaker.
- **Only A passes:** ship A.
- **Only B passes:** ship B.
- **Neither passes:** STOP. Surface as a blocker — CONTEXT.md D-11 did not anticipate dual
  failure. Roll back to Phase 54's `_FluxDriver`-style external driver pattern within the
  builder, file an MTK issue, and document the deviation. Don't silently relax the criteria.

### Comparison source — what to compare against

`test/test_loss_of_flow.jl` is the v1.0 baseline. The Phase 55 spike must not introduce any
NEW failure in that file vs the current passing run. If LOF-01 was passing under the old
`build_loop_lof_bypass(ChannelHeatFlux + T_wall=...)` API, the new builder must keep LOF-01
green when run with the same constants (`BYPASS_N=10`, `BYPASS_T_WALL=373.15`,
`BYPASS_T_INLET=313.15`, `BYPASS_G_ACC=9.80665`, etc., as defined at lines 30-41). Note that
this file is being absorbed into `test_integration.jl` per D-19 — the absorption happens
**after** the spike, so during the spike step the file is still the canonical comparison source.

### What changes in `examples/lof_transient.jl`

Per D-15: lines 88-103 of the example construct an inline reference loop with
`ChannelHeatFlux(T_wall=...)` (old API). After spike resolution, both that inline reference
loop and the call to `build_loop_lof_bypass` migrate to the winning topology. The IC dict
keys at lines 105-119 also adjust:

- If Spike A wins: `ssys.ch.T[i]` keys remain; new keys `ssys.ch.thermal_left[i].T` may need
  initialization if hypothesis B from Section 2 holds.
- If Spike B wins: add `ssys.heated.fuel.T[i,j] => T_inlet` for `i in 1:nz, j in 1:nx`
  (mirroring `build_loop_pk` at `src/examples.jl:614`).

The transient + plotting code at lines 200+ is unchanged.

**Source:** Citations are file:line references in `test/test_loss_of_flow.jl` and CONTEXT.md
D-11. Tag: [VERIFIED — file:line].

---

## Section 4 — Python STREAM `test_integrations.py` Structural Notes (HIGH confidence)

### File metadata

- **Path:** `/home/itay/projects/STREAM/tests/test_general/test_integrations.py`
- **Lines:** 973 (verified via `wc -l`)
- **Test count:** 23 top-level `def test_*` functions (verified via grep)
- **Header:** Three-line module docstring `"""Testing global, or integrative, arrangements."""` —
  no further section markers. The file is **flat** (no `# === SECTION ===` headers, no nested
  classes).

### Naming convention

`test_{system_or_setup}_{observed_behavior}` — e.g.
`test_pump_resistor_in_series_follows_analytic_solution`,
`test_channel_stable_state_with_uniform_heating_increases_linearly`,
`test_kirchhoff_with_decaying_pump_eventually_flips_flow_direction_gravity`,
`test_inertia_with_friction_in_PCS_coastdown`. Names are long and assertion-style — they read
as the property the test is asserting, not as a feature inventory.

### Mix of test styles

The 23 tests interleave two styles freely:

- **Hypothesis property tests** (10 of 23): decorated with `@settings(deadline=None)` plus
  `@given(...)` from the `hypothesis` library. Examples: lines 57-83, 83-127, 127-148, 148-200.
  These exercise the same topology across many parameter samples.
- **Deterministic tests** (13 of 23): no decoration, fixed inputs, single solve. Examples: lines
  201-269 (`test_channel_point_kinetics`), 270-315 (Kirchhoff with decaying pump), 720-770
  (PCS coastdown — the LOF analogs), 833-898 (transistor coastdown).

Julia STREAM **does not currently use a hypothesis-equivalent** (`PropCheck.jl` exists but is
not in the project's deps). The Julia `test_integration.jl` should mirror the deterministic
half of the Python file — the property tests are out of scope for Phase 55. (PropCheck adoption
is a future improvement, not a Phase 55 deliverable.)

### Shared fixtures (conftest.py)

Two file-local helpers in `~/projects/STREAM/tests/test_general/conftest.py`:

- `are_close(a, b, rtol=1e-5, atol=1e-8)` — wraps `np.allclose` with a percentage report on
  failure.
- `pos_medium_floats` — hypothesis strategy `floats(allow_infinity=False, allow_nan=False,
  max_value=1e6, min_value=1e-6)`.

And `~/projects/STREAM/tests/test_composition/conftest.py` provides `MTR_fuel_and_channel(z_N,
fuel_N, clad_N) -> (Fuel, ChannelAndContacts)` — a **constructor**, not a pytest fixture. The
function is imported and called per-test, not auto-injected. Julia equivalent: a module-local
helper function defined at the top of `test_integration.jl` (or in a `test_helpers.jl`
`include`d once) — no Julia-side analog of pytest fixtures is needed.

### Concrete sectioning recommendation for Julia `test_integration.jl`

The Python file is flat — it does NOT use section comments. But for Julia this would lose the
TEST-02 / TEST-05 audit trail CONTEXT.md D-19 spelled out. Recommend Julia uses **`@testset`
groups** as soft sections (NOT `#=== ===` header banners — keep the file readable and grep-able):

```julia
@testset "Builders smokes" begin
    @testset "build_loop" begin ... end
    @testset "build_loop_vertical" begin ... end
    ...
end

@testset "Solver wrappers (SOLV-01, SOLV-02)" begin ... end

@testset "Loss-of-flow transient" begin
    @testset "LOF-01: bypass topology compiles" begin ... end
    ...
end

# etc.
```

This matches Python's flat structure (no section headers) while giving Julia's test runner
the grouping it expects, and gives D-19's D-section names a place to live as `@testset` titles
rather than comment banners. Estimated final length: 600-900 lines (the absorbed files
together: `test_examples.jl` 122 + `test_solvers.jl` 99 + `test_loss_of_flow.jl` 287 +
`test_subcooled_boiling.jl` 208 + relocated PK loop tests ~150 lines = ~870 lines uncondensed;
some consolidation expected, target ~700 lines).

**Source:** All counts verified via direct file reads in this session — `wc -l`, `grep -nE`,
and full reads of the head, middle, and tail sections of `test_integrations.py`. Tag:
[VERIFIED — file inspected].

---

## Section 5 — Validation Architecture (Nyquist)

`workflow.nyquist_validation: true` in `.planning/config.json:12`. This section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Base `Test` stdlib + `OrdinaryDiffEq.ReturnCode` for solver retcode assertions |
| Config file | None — Julia uses `Project.toml` `[targets] test = ["Test"]` (verified `Project.toml:30`) |
| Quick run command | `bin/jl test/test_{file}.jl` for a single file (~3-12s warm) |
| Full suite command | `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl` cold, per CONTEXT.md TEST-05) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | Channel/CHF/CAC + `_channel_core` + sign-safety variant unit tests | unit | `bin/jl test/test_channels.jl` | ❌ exists but rewritten in this phase (Wave 2) |
| TEST-01 | WallTemperature / HeatFluxSource component unit tests | unit | `bin/jl test/test_misc.jl` (or `test_sources.jl` per discretion) | ⚠ test_misc.jl exists (81 lines); needs new testsets |
| TEST-02 | Six builder smokes + `solve_steady`/`solve_transient` wrappers | integration | `bin/jl test/test_integration.jl` | ❌ NEW file (Wave 5) |
| TEST-02 | LOF transient (LOF-01..03) + VAL-01..02 + ISCB-01..02 + PK loops (LOOP-01..04, TF-06, TF-07) | integration | `bin/jl test/test_integration.jl` | ❌ Wave 5 absorbs 4 existing files |
| TEST-03 | `symmetric_plate` / `plate` / `one_sided_connection` / `compose_systems` / `port` / `check_gravity_mismatch` / `_infer_n` / `connect_temperature_feedback` | compose-correctness | `bin/jl test/test_composition.jl` | ⚠ exists (354 lines); rewritten in Wave 3 |
| TEST-05 | No NEW failures vs v1.0 baseline | regression | `bin/jl test/runtests.jl` | ✅ runtests.jl exists; updated `include` lines per Wave 6 |

### Sampling Rate

- **Per task commit:** `bin/jl test/test_{file_modified}.jl` (~3-12s warm, sub-second on the
  daemon for files smaller than `test_channels.jl`).
- **Per wave merge:** `bin/jl test/runtests.jl` — rejects regression in any of the 14 files.
- **Phase gate (TEST-05 close):** Full suite green per the CONTEXT.md D-22 framing — "no NEW
  failures vs v1.0 baseline." VAL-01 (Fourier numerical flake) and NET-03 (Cube flow KINSOL
  convergence) remain tolerated.

### Four validation dimensions (matches the additional_context request)

| Dim | Concern | Required tests | Files where they live |
|-----|---------|----------------|------------------------|
| **i. Component-level unit** | Each Channel/CHF/CAC variant instantiates and `mtkcompile`s cleanly under the new API; per-cell external-input variables exist; observable surface is correct; `_channel_core` enthalpy-form physics still holds (G1-G4 stage tests); flow-reversal sign safety. | All seven test sections of D-17 (construction & shape; adiabatic-by-default; heated Style 1; heated Style 2; h_left value-shape coverage; CAC correlation-driven htc; CAC SCB; flow reversal; `_channel_core` G1-G4; CAC↔CHF cross-equiv). Plus WallTemperature/HeatFluxSource unit tests. | `test_channels.jl` (rewritten); `test_misc.jl` (extended) |
| **ii. Compose-correctness** | CAC↔HD assemblies via the helpers compile cleanly across `(n, nz, nx)` shapes; equation/unknown count is balanced; lightweight solve-to-verify yields meaningful steady states (NOT physics validation). `connect_temperature_feedback` equation-counting tests. `_infer_n` correctness on CAC. | All eight test sections of D-18 (port helper; gravity mismatch; `_infer_n`; symmetric_plate; plate; one_sided_connection; compose_systems; multi-shape matrix; solve-to-verify; TF-04 equation-counting). | `test_composition.jl` (rewritten) |
| **iii. End-to-end integration** | Each builder + example builds, mtkcompiles, and runs `solve_steady`/`solve_transient` to physically meaningful endpoints. Validates against analytic / expected behavior — the Python-STREAM-style integration regime. LOF + PK loops + SCB + builder smokes + solver wrappers. | All six sections of D-19 (Builders smokes; Solver wrappers; LOF; SCB; PK + thermal feedback; COMPAT). | `test_integration.jl` (NEW) |
| **iv. Regression gate** | `bin/jl test/runtests.jl` (or cold-start fallback) green; no NEW failures vs v1.0 baseline; existing flakies (VAL-01 Fourier, NET-03 Cube flow KINSOL) tolerated per CONTEXT.md D-22. | Full-suite run is the gate. Use the v1.0 commit (whichever was tagged before `channels-redesign` opened — verify via `git log main`) as the baseline. | All 14 test files via `test/runtests.jl` |

### Wave 0 Gaps

- [ ] `test/test_channels.jl` — rewrite under new design (Wave 2). Test framework already in
  place (file exists, exits 0 today with 31 Phase-54 tests; rewrite replaces it).
- [ ] `test/test_composition.jl` — rewrite, expand CAC↔HD coverage (Wave 3).
- [ ] `test/test_integration.jl` — NEW file (Wave 5).
- [ ] `test/test_thresholds.jl` — pure rename of `test_analysis.jl` (Wave 6, trivial).
- [ ] `test/test_misc.jl` — add WallTemperature / HeatFluxSource unit tests (Wave 1 or Wave 2,
      planner picks).
- [ ] `test/test_connectors.jl` — remove HeatFluxPort tests + `_StubFluxDriver` stub (Wave 1).
- [ ] `test/test_point_kinetics.jl` — TRIM (move LOOP-* + TF-06/07 to test_integration.jl;
      Wave 5).
- [ ] `test/runtests.jl` — update `include` lines (Wave 6).
- [ ] **Spike script `/tmp/spike_phase55_unbound.jl`** (Wave 0) — 5-line script verifying the
      hypothesis A vs hypothesis B question from Section 2. Locks the test idiom for
      `test_channels.jl` adiabatic-by-default before Wave 2 begins.

Framework install: none — `Test` is a Julia stdlib, already wired via `Project.toml:30`.

---

## Section 6 — Pitfalls / Landmines

Items the planner needs to know that CONTEXT.md doesn't already cover. One bullet each.

- **`_infer_n` (`src/composition/helpers.jl:136-143`) counts subsystems named `thermal_left*` on
  its first arg.** Works on CAC (still has them post-Phase-55). Would silently fail with the
  helpful `error("_infer_n: could not detect thermal port count ... Pass an uncompiled
  ChannelAndContacts instance.")` if someone passes the new Channel/CHF (which have no such
  subsystems anymore — they have plain `T_wall_left[1:n]` variables instead). This is fine
  because CONTEXT.md D-08 says helpers only ever take CAC as the first arg, but a planner who
  doesn't know this might be tempted to "fix" `_infer_n` to handle Channel — they should not.
  The architectural rule (`feedback_channel_hd_connection_rule.md`) means Channel/CHF
  should NEVER touch the helpers.

- **`build_cube` is unrelated to CAC.** Phase 54-03's SUMMARY incorrectly claimed `build_cube`
  validated CAC↔HD compile (54-VERIFICATION.md Deviation 2; 54-05-SUMMARY.md fix paragraph).
  Phase 55 must not repeat the misattribution — `build_cube` is the resistor cube; CAC↔HD
  composition is exercised via `symmetric_plate(cac, fuel; name=:rods)` + `compose_systems`.

- **All three current simple-loop builders are ALREADY broken under Phase 54's new API.**
  `build_loop` (`src/examples.jl:67`), `build_loop_vertical` (`:157`), and `build_loop_transient`
  (`:216` and `:229`) all reference `ch.thermal.T ~ T_wall` — but the new Channel exposes
  `thermal_left[1:n]` arrays, NOT a singular `thermal` port. These builders fail at compose-time
  today (see `test_examples.jl` for what's currently being tested — likely a stale set). Phase
  55 must rewrite them per D-09 / D-10 to bind `[ch.T_wall_left[i] ~ T_wall for i in 1:n]`
  AFTER the variant rewrite (Wave 4 must follow Wave 1).

- **`build_loop_lof_bypass` (`src/examples.jl:405-412`) currently calls
  `ChannelHeatFlux(; n, geometry, g, T_wall=, htc_correlation=, friction_correlation=)` —
  but the post-Phase-54 CHF signature is the minimal 5-kwarg form (no `T_wall`, no
  `htc_correlation`).** This is broken today, surfaces only when someone runs the example.
  Phase 55 fix is the LOF spike + redesign per D-11. Don't get confused by the current code
  shape during pre-spike research — it's already wrong.

- **`build_loop_lof_bypass` also uses `ret.thermal.T ~ T_inlet` (line 433) — same
  singular-port issue as the simple loops.** Will become `[ret.T_wall_left[i] ~ T_inlet for
  i in 1:n]` (with `h_left=0.0`, so the binding is essentially decorative — see Section 2).

- **`build_loop_transient`'s `T_wall_callable` parameter** (`src/examples.jl:223-231`) currently
  uses the v0.9 callable-parameter pattern at the **builder** level (not inside Channel). After
  Phase 55, the cleanest port is to keep the pattern exactly as-is at the builder level and bind
  per-cell: `[ch.T_wall_left[i] ~ ps[1](t) for i in 1:n]` (replacing line 229's
  `ch.thermal.T ~ ps[1](t)`). Valid alternative is to push the callable into a `WallTemperature`
  source component instead. Both work; CONTEXT.md Discretion explicitly allows either.

- **CAC's `Q_wall_total` lives in `variant_obs`** (`src/components/channels.jl:697`), NOT
  `variant_eqs`, after Phase 54-05's fix. It's expressed as `sum(q_left_expr[i] +
  q_right_expr[i] for i in 1:n)`. Tests should read it as `sol[ssys.rods.cac.Q_wall_total,
  end]`, not as a regular unknown. Phase 55 should not regress this — any new variant code that
  sums `q_wall[i]` directly will trip the same observed-to-equation chain. (Already covered
  in 54-05-SUMMARY.md "Notes for Phase 55 TEST-01" item 5; restated here so the planner doesn't
  miss it.)

- **`extra_pars = Vector{Any}` in Channel** (`src/components/channels.jl:253`) — when the
  callable-parameter branch fires, `pL` returns
  `Vector{Symbolics.CallAndWrap{Num}}`, not `Vector{Num}`. Splice into `pars` via
  `Any[pars_base...; extra_pars...]`. The same shape applies to `WallTemperature` /
  `HeatFluxSource` when their `T_wall::Function` / `q::Function` branch fires. Don't try
  `Vector{Num}` for the merged pars list — it'll throw a method error on construction.

- **`HeatDiffusion` has FIVE mandatory kwargs** with no defaults: `y, rho_s, cp_s, k_s,
  power_shape` (verified from how `test_channels.jl` constructs it at lines 221-228, and
  `build_loop_pk` at `src/examples.jl:518-528`). Plus `power` — now an unknown that must be
  constrained at compose time (`rods.fuel.power ~ power_W` or via PK power binding). Phase 55
  doesn't change this, but any new test that constructs HD must supply all five (gold-uranium
  MTR-plate canonical values: `y=0.07, rho_s=19300, cp_s=116, k_s=174`). Already documented in
  `54-05-SUMMARY.md` item 4 of "Notes for Phase 55 TEST-01"; restated.

- **IC dicts are mandatory for `solve_transient` on Channel/CHF/CAC.** Default
  `T(t)[1:n]=600.0` is far above typical `T_inlet=313.15` — without explicit `[ssys.<comp>.T[i]
  => T_inlet for i in 1:n]` and `ssys.<comp>.port_in.mdot => mdot0`, the DAE init fails with
  `DtNaN` (CHF and CAC included; Channel has the same default IC). Mirror
  `build_loop_pk:612-614`. Already documented in `54-05-SUMMARY.md` item 3; restated.

- **`bin/jl` requires daemon; daemon does NOT hot-reload struct definitions.** When
  Wave 1 changes Channel/CHF struct shape (add `T_wall_*[1:n]`/`q_*[1:n]` variables) and Wave
  1 also adds new components (`WallTemperature`, `HeatFluxSource`), `tmux kill-session -t
  stream-jl` followed by `bin/jl-up` is mandatory. Don't trust Revise to pick up the
  redefinitions silently.

- **`STREAM.jl:27` exports `HeatFluxPort` today.** Removal under D-06 is a one-line edit, but
  also drops it from the export line at `STREAM.jl:27` (currently `export FlowPort, ThermalPort,
  HeatFluxPort`). Must update to `export FlowPort, ThermalPort` AND add `WallTemperature,
  HeatFluxSource` to the components export block at `STREAM.jl:28-42` (alphabetize with
  `Channel`, `Pump`, `Friction`, etc. or just append — file is already not strictly sorted).

- **`function Channel end` declaration at `src/components/channels.jl:20`** is required to
  disambiguate `STREAM.Channel` from Julia stdlib's `Base.Channel{T}`. Don't delete it during
  the variant rewrite. Phase 55 rewrites Channel's body but the `function Channel end`
  declaration itself stays. Same mechanism applies to any other component name colliding
  with `Base` — `WallTemperature` and `HeatFluxSource` have no `Base` collision so no such
  declaration is needed.

---

## Section 7 — References / Files Cited

### Primary (HIGH confidence)

- `Project.toml:18` — `ModelingToolkit = "11"`, `julia = "1.12"`.
- `Manifest.toml` — MTK v11.25.0, Symbolics v7.21.0 (verified 2026-05-07).
- `CLAUDE.md:1-174` — full project instructions (branching policy, file structure, MTK patterns,
  daemon dev loop).
- `.planning/config.json:7-23` — workflow flags, branching strategy.
- `.planning/REQUIREMENTS.md:18-50` — TEST-01 / TEST-02 / TEST-03 / TEST-05; CONN-02 supersession.
- `.planning/STATE.md` — current branch `channels-redesign`; v1.1 phasing.
- `.planning/ROADMAP.md:79-92` — Phase 55 success criteria 1-6.
- `.planning/phases/54-variant-rewrites-file-consolidation/54-VERIFICATION.md` — full Phase 54
  verification including the three Notable Deviations (lines 100-107) directly relevant to
  Phase 55.
- `.planning/phases/54-variant-rewrites-file-consolidation/54-05-SUMMARY.md:156-211` — Phase 54
  Deviation 1 root cause + Phase 55-relevant notes (especially items 1-5 of "Notes for Phase
  55 TEST-01").
- `.planning/phases/55-composition-helpers-examples-test-suite/55-CONTEXT.md` — 449-line phase
  context; 22 D-XX decisions.

### MTK callable-parameter pattern (HIGH confidence — verified in production)

- `src/components/point_kinetics.jl:225,241` — `FType = typeof(rho_c_fn)` + `@parameters
  (rho_c_fn::FType)(..)` reference implementation.
- `src/components/channels.jl:253-281` — Channel's `h_left::Function` branch using same pattern.
- `src/examples.jl:222-229` — `build_loop_transient`'s builder-level callable parameter.

### Phase 54 codebase state (HIGH confidence — verified by reading)

- `src/components/channels.jl:84-181` — `_channel_core` body (Phase 53 deliverable; UNCHANGED in
  Phase 55).
- `src/components/channels.jl:219-359` — current Channel body (REPLACED in Phase 55: drops
  `thermal_left[1:n]`/`thermal_right[1:n]` ThermalPort arrays, adds `T_wall_left[1:n]`/
  `T_wall_right[1:n]` plain variables, drops `port.Q_flow ~ q_*_expr` closure equations).
- `src/components/channels.jl:396-487` — current ChannelHeatFlux body (REPLACED in Phase 55:
  same shape change with `q_left[1:n]` / `q_right[1:n]` variables).
- `src/components/channels.jl:533-717` — ChannelAndContacts body (UNCHANGED in Phase 55).
- `src/components/misc.jl:80-99` — `ConstantTemperature` (closest analog for `WallTemperature` /
  `HeatFluxSource`).
- `src/connectors.jl:7-51` — `FlowPort` (kept), `ThermalPort` (kept), `HeatFluxPort`
  (DELETED in Phase 55).
- `src/STREAM.jl:6-95` — full module entrypoint; line 18 includes channels.jl; line 27 exports
  the connectors; lines 28-42 export the components.
- `src/composition/helpers.jl:28,59-118,136-143,174-185,217-230,261-277,304-306,347-367` —
  helpers and `_infer_n` (UNCHANGED in Phase 55, pending verification per D-08).
- `src/examples.jl:48-79` — `build_loop` (BROKEN today; rewritten in Phase 55).
- `src/examples.jl:124-169` — `build_loop_vertical` (BROKEN today; rewritten).
- `src/examples.jl:194-241` — `build_loop_transient` (BROKEN today; rewritten).
- `src/examples.jl:278-339` — `build_cube` (UNCHANGED).
- `src/examples.jl:378-448` — `build_loop_lof_bypass` (BROKEN today; redesigned via D-11 spike).
- `src/examples.jl:496-617` — `build_loop_pk` (verify-only per D-12).

### Phase 54 test state (HIGH confidence)

- `test/test_channels.jl:1-269` — Phase 54 close-gate file (REWRITTEN in Phase 55 per D-17).
  Lines 36-48 hold the `_WallTempDriver` / `_FluxDriver` stubs that become first-class
  `WallTemperature` / `HeatFluxSource` components in Phase 55.
- `test/test_loss_of_flow.jl:1-287` — v1.0 LOF baseline (lines 30-41 constants; lines 130-176
  LOF-01..03; lines 192-219 VAL-01; lines 235-287 VAL-02). ABSORBED into `test_integration.jl`
  per D-19.
- `test/test_channel.jl:1-958` — legacy file (DELETED per D-17).
- `test/test_channel_core.jl` (604 lines) — DELETED per D-17.
- `test/test_sign_safety.jl` (173 lines) — DELETED per D-17.
- `test/test_examples.jl`, `test/test_solvers.jl`, `test/test_loss_of_flow.jl`,
  `test/test_subcooled_boiling.jl` — DELETED, content into `test_integration.jl` per D-19.
- `test/test_analysis.jl` (340 lines) — RENAMED to `test_thresholds.jl` per D-20.
- `test/test_validation.jl` (759 lines) — UNTOUCHED (Phase 56's deliverable).

### Python STREAM reference (HIGH confidence — verified by reading)

- `~/projects/STREAM/tests/test_general/test_integrations.py` (973 lines, 23 top-level test
  functions, flat structure, no section headers).
- `~/projects/STREAM/tests/test_general/conftest.py` (54 lines, `are_close` + `pos_medium_floats`
  + `MTR_fuel_and_channel`).
- `~/projects/STREAM/tests/test_calculations/`, `~/projects/STREAM/tests/test_libraries/`,
  `~/projects/STREAM/tests/test_composition/` — directory listings confirming the
  one-file-per-component / library / composition organizational pattern.
- `~/projects/STREAM/stream/calculations/channel.py:224-238,384` — Python `Channel` and
  `ChannelHeatFlux` API source-of-truth (cited via CONTEXT.md canonical_refs).

### Memory references (Claude's project memory)

- `feedback_channel_hd_connection_rule.md` — HeatDiffusion ↔ CAC architectural rule.
- `feedback_keyword_only_rule.md` — kwarg conventions.
- `feedback_ascii_variable_names.md` — no Unicode in variable names.
- `feedback_power_shape_trust_caller.md` — don't validate caller-supplied data.

### Tertiary / context

- `bin/jl`, `bin/jl-up`, `bin/jl-client.jl` — daemon dev loop infrastructure (CLAUDE.md lines
  113-173).
- `.planning/PROJECT.md` (cited via CONTEXT.md canonical_refs but not required reading for
  Phase 55 plan).

---

## Metadata

**Confidence breakdown:**
- MTK callable-parameter pattern (Section 1): HIGH — verified against installed MTK v11.25.0 +
  three production sites + Project.toml.
- Dangling-port behavior (Section 2): HIGH structural; spike step locks the binary outcome.
- LOF spike protocol (Section 3): HIGH — tolerances cited from existing v1.0 baseline file:line.
- Python STREAM test structure (Section 4): HIGH — file inspected directly.
- Validation Architecture (Section 5): HIGH — derived from CONTEXT.md D-17..D-22 + project
  config.
- Pitfalls (Section 6): HIGH — every claim cites file:line in the current codebase.

**Research date:** 2026-05-07
**Valid until:** 2026-06-07 (30 days; Phase 55 should plan-lock and execute well within this
window). Re-verify if MTK is upgraded past v11.25.0 (the callable-parameter pattern has been
stable since v9 but minor wording in Section 1 may shift).

## RESEARCH COMPLETE
