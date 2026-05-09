# Phase 55: Composition Helpers, Examples & Test Suite - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 55-Composition Helpers, Examples & Test Suite
**Areas discussed:** Args.funcs idiom (Channel/CHF heating API), test architecture (centerpiece + file layout), `build_loop_lof_bypass` heated-leg redesign, simple-loop builder consolidation, Channel/CHF architectural redesign (port retirement), test-file consolidation, PK component-vs-integration split

---

## Round 1 — Initial framing (rejected mid-flight)

The first round of questions was framed around minimal-disruption / port-the-old-tests semantics. The user rejected this framing with: "This is a rewrite. This is the time to break what was written before if it's for our benefit. We don't need to make minimal edits. What was before was wrong. The channels were written incorrectly." The questions were withdrawn before locking and re-formulated around clean-slate redesign.

**Original questions that were withdrawn:**
- Heated-loop builder API (Keep T_wall+h_wall / Drop T_wall expose h_left/h_right / Switch builders to CAC)
- LOF heated-leg redesign (Channel + h_callable + driver / CHF + precomputed q / Migrate to CAC)
- test_channel.jl rewrite strategy (Triage+merge / 1:1 port / Two-file split)
- Driver helpers placement (Public / Private / File-local)

**Reason for withdrawal:** all four anchored on "what was there before" rather than "what's the cleanest design for the new variants." The user explicitly chose to re-think test architecture, builder shape, and driver mechanism without porting-bias.

---

## Round 2 — User's framing-correction message

User identified the centerpiece thesis: **CAC + HeatDiffusion is the main use case.** Channel and CHF are simplified-model fixtures used for testing concepts; CAC + HD is what people will use STREAM for. Physics validation should always go through CAC + HD compositions, not Channel / CHF. The user also raised the args.funcs idea — Python STREAM's mechanism for providing scalars/functions/vectors to unequated values — and asked whether it could be made to work natively in Julia MTK rather than requiring driver components.

This reframe drove the rest of the discussion:
- Test architecture must reflect the centerpiece (heavy CAC↔HD coverage).
- Channel / CHF are "fixtures and concept demos" — their tests are about API shape, not physics depth.
- Args.funcs idiom should work via direct binding eqns OR via value-source components — both styles, not one or the other.

---

## Args.funcs idiom (Channel/CHF heating API)

| Option | Description | Selected |
|--------|-------------|----------|
| Kwargs only (drive-mode branch) | `Channel(; T_wall_left, T_wall_right, h_left, h_right)` Real/Vec/Callable; constructor branches based on which kwargs given. Closest to Python args.funcs. No new components. | |
| Driver components only | `WallTemperature(; n, T_wall)` and `HeatFluxSource(; n, q)` as public STREAM components, connect via `connect()`. Idiomatic MTK; GUI-friendly. | ✓ (with caveat) |
| Both (kwargs + components) | Ship both surfaces; constructor kwargs delegate to a hidden internal driver. Single mechanism, two ergonomic surfaces. | |

**User's choice:** Driver components — but with the explicit requirement that direct binding equations also work natively: "I want to make sure that if the users still just want to add their own equation where it just says channel.T_wall_left ~ my_T_wall_left it works no problem. Of course for each cell in a loop and handle that interface properly. But if they just want to add an equation that sets a variable to a scalar/vector/function it should be fine."

**Implication that surfaced after the answer:** the Phase 54 architecture (per-cell `ThermalPort` / `HeatFluxPort` arrays on Channel and CHF, with channel-side `port.Q_flow ~ q_expr` closure) does NOT support direct binding eqns natively — Phase 54's deviation 1 already documented that binding `port.T ~ value` over-determines because the dangling Flow rule auto-zeros Q_flow while the channel emits its own Q_flow definition. To make both styles work, the per-cell ports must be dropped from Channel and CHF entirely. CAC keeps its ports (it must wire to HD via Flow-based ports). This was the central architectural insight of Phase 55 — see "Channel/CHF architectural redesign" round below.

---

## Test architecture (centerpiece + initial file layout)

| Option | Description | Selected |
|--------|-------------|----------|
| New test_cac_hd.jl + slim test_channels.jl | New test_cac_hd.jl as explicit centerpiece signal; test_channels.jl scoped to variant unit tests. | |
| Heavy CAC+HD inside test_composition.jl | Keep three files: test_channels.jl (variants), test_composition.jl (helpers + heavy CAC↔HD), test_validation.jl. No new file. | ✓ (as starting point) |
| All channel-side tests in test_channels.jl | Single test_channels.jl holds variants + CAC↔HD compositions in sections. | |

**User's choice:** Don't introduce `test_cac_hd.jl`. Use `test_composition` for everything that doesn't involve actually solving a real system (with emphasis on CAC↔HD); `test_integration` validates that real systems solve and produce correct output. Plus the explicit ask: research Python STREAM's test layout, derive the rules, apply to Julia STREAM. "You can decide on reworking the current test files and what files exist and what not, but make it make sense and no random files or random tests."

**Notes:** The user gave Claude license to redesign the test layout based on Python STREAM rules. Claude conducted full research of `~/projects/STREAM/tests/**/*.py` (read every test file), extracted five organizational rules, and proposed the 14-file layout in Round 3 below.

---

## Channel/CHF architectural redesign (port retirement)

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — drop ports, retire HeatFluxPort | Channel/CHF lose per-cell ThermalPort/HeatFluxPort arrays; expose T_wall_left/T_wall_right (Channel) and q_left/q_right (CHF) as channel-level external-input variables. HeatFluxPort deleted. CAC unchanged. | ✓ |
| Yes for binding, but keep ports as opt-in | Add external-input variables AND keep per-cell ports; channel-side Q_flow eqn becomes conditional on which API the user uses. Drive-mode branch in constructor. HeatFluxPort survives. | |
| No, keep Phase 54 architecture | Keep per-cell ports as the only connection pattern; require driver components for binding; document that direct binding eqns over-determine. Conservative, but doesn't deliver the args.funcs binding. | |

**User's choice:** Drop the ports, retire HeatFluxPort. This is the clean rewrite: Channel/CHF never connect to HD per the architectural rule (`feedback_channel_hd_connection_rule.md`), so they never needed Flow-based ports. The Phase 54 per-cell port arrays were vestigial. Removing them eliminates the over-determination problem at its root, makes direct binding eqns work natively, and lets `WallTemperature` / `HeatFluxSource` exist as portless value-source components.

---

## `build_loop_lof_bypass` heated-leg redesign

| Option | Description | Selected |
|--------|-------------|----------|
| Migrate to CAC + tiny wall source | CAC + WallTemperature pinning T_wall per cell, no HD plate. Simpler; CAC's correlation-driven htc handles regime switching naturally. | |
| Migrate to CAC + HD plate | CAC + HeatDiffusion plate via one_sided_connection or symmetric_plate. Most physically faithful (real fuel-plate transient). Heaviest rework. | |
| Channel + h_left callable + wall source | Channel(h_left=regime_callable) + WallTemperature. Lightest migration but burdens "simplified" Channel with regime physics. | |

**User's choice:** "I think this is a complex decision. I would like to prove that lof fully works in this code, and for the 'fully' to exist we need a full physical system. That requires HD plate. But I don't want to overcomplicate and make stuff take hours to run and find the final solution that works for this. Here you can apply thinking, maybe spike both directions and see if they both work or not. Test around to see what makes the most sense to use ultimately."

**Notes:** Decision is spike-driven, not pre-locked. Phase 55 plan must include a short spike step that exercises both Spike A (CAC + WallTemperature, no HD plate) and Spike B (CAC + HD plate). Acceptance criteria for the chosen variant: (i) compiles + solves a brief transient, (ii) reproduces the v1.0 LOF NC-reversal qualitative behavior (mdot crosses zero, NC equilibrium reached), (iii) reasonable runtime (< 60s per scenario for the integration-test version). If both work, prefer Spike A (simpler). User wants Phase 55 to demonstrate that LOF fully works in Julia, including with a real fuel plate where appropriate, but is fine deferring the more complex topology if the simpler one is sufficient for the test.

---

## Simple-loop builders consolidation

| Option | Description | Selected |
|--------|-------------|----------|
| Keep three, demo-progression structure | build_loop = simplest, build_loop_vertical adds gravity, build_loop_transient adds time-varying input. Clear pedagogy, separate test fixtures. | |
| Collapse to one parameterized builder | Single `build_simple_loop(; vertical=false, transient_input=nothing, ...)`. Less duplication; one source of truth. | |
| Three builders, but rethink LOF/PK fit | Keep three simple-loop builders separate (concept demos with Channel/CHF); separately scrutinize whether build_loop_lof_bypass and build_loop_pk should both move to CAC+HD as "real physics" builders — explicit two-tier structure. | ✓ |

**User's choice:** Three builders kept; explicit two-tier framing — simple-loop builders are concept demos using Channel/CHF, LOF/PK are physics-grade builders using CAC + HD. This aligns with the centerpiece thesis from Round 2 (CAC + HD = physics, Channel/CHF = simplified concept demos).

---

## Test layout sign-off (Round 3, after Python STREAM research)

| Option | Description | Selected |
|--------|-------------|----------|
| Approve as proposed (14-file layout) | test_channels.jl absorbs test_channel_core.jl + test_sign_safety.jl + flow-reversal; test_integration.jl absorbs test_examples + test_solvers + test_loss_of_flow + test_subcooled_boiling + PK integration; test_thresholds.jl renames test_analysis.jl; test_point_kinetics.jl shrinks to component-unit tests; test_validation.jl untouched. | ✓ |
| Approve, but split test_integration.jl | Same plus split by physics regime (test_integration_loops.jl + test_integration_lof.jl + test_integration_pk.jl). Diverges from Python's single-file pattern. | |
| Approve, but keep test_loss_of_flow + test_subcooled_boiling separate | Major physics regimes worth own files; test_integration absorbs only smaller fixtures. | |

**User's choice:** Approve as proposed — single big `test_integration.jl` that mirrors Python STREAM's `test_general/test_integrations.py`. LOF, PK loops, SCB integration, builders smokes, solver wrappers all live together as labeled sections in one file. Matches the rule extracted from Python: "ONE big integration file holds all multi-component system-level tests" (Python's test_integrations.py is 973 lines — the Julia equivalent will be similarly comprehensive).

**Python STREAM research findings (recorded for audit):**
- 5-bucket structure: test_calculations/ (per-component unit), test_libraries/ (pure-function correlations), test_composition/ (compose/wire), test_general/ (framework + ONE big integration file), test_analysis/ (UQ pipelines, out of scope).
- Rule 1: One file per component-class for unit tests. Subclasses live in same file as parent (ChannelAndContacts in test_channel.py). Shared core helpers tested in same file as variants that use them (coolant_first_order_upwind_dTdt in test_channel.py).
- Rule 2: Stand-alone correlation/threshold math goes in test_libraries/.
- Rule 3: test_composition/ is for HOW systems get built — graph construction, MTR helpers, state manipulation. May solve for compose-correctness but no long-running physics validation.
- Rule 4: ONE big test_integrations.py holds all multi-component system-level tests. **LOF and PK + thermal feedback are NOT separate files in Python — they're sections of this one big file.**
- Rule 5: External-reference validation gets its own file (Julia-specific, since Python STREAM IS the reference).

---

## PK component-vs-integration test split

| Option | Description | Selected |
|--------|-------------|----------|
| Component unit tests only stay | Keep PK-01..03, RC-01, TF-01..05, SCRAM-01 in test_point_kinetics.jl. Move LOOP-01..04, TF-06, TF-07 to test_integration.jl. Mirrors Python's split. | ✓ |
| All PK in test_point_kinetics.jl | Treat PK as a major regime worth keeping its tests together. | |

**User's choice:** Component unit tests only stay in `test_point_kinetics.jl`. Full-loop integration tests (LOOP-01..04 — build_loop_pk compiles + quiescent stability + step reactivity + SCRAM termination, plus TF-06 reactivity-observable-in-solved-system, TF-07 strong-feedback-bounds-power) move to `test_integration.jl`. Matches Python STREAM's split exactly: PK construction in test_point_kinetics.py, full PK + thermal coupling in test_integrations.py.

---

## Claude's Discretion

The user explicitly delegated several judgment calls to the planner:

- **Plan / wave decomposition** — wave structure for Phase 55 execution (e.g., variant rewrite + sources.jl + connectors.jl HeatFluxPort retirement; tests rewrite; helpers verify; builders rewrite + LOF spike; integration consolidation; doc fixes). Atomicity / commit boundaries / file-conflict resolution all planner's call.
- **Naming of value-source-component output variables** — `WallTemperature.T_wall_out[1:n]` vs `WallTemperature.T[1:n]` (matching ConstantTemperature.T) — pick once, document, stay consistent.
- **Default value of `h_wall` in builders** — Phase 54 smoke used 5000.0 W/m²K. Planner picks a sensible default that makes the existing `T_wall=373.15` / `T_inlet=313.15` defaults produce a meaningful T_out rise.
- **`build_loop_transient` time-varying T_wall mechanism** — direct callable in binding eqn vs MTK callable-parameter pattern; both are correct, planner picks based on what existing test_solvers SOLV-02 callers expect.
- **Whether to keep `ConstantTemperature` / `WallTemperature` / `HeatFluxSource` as three separate components vs unify** — keep separate for v1.1; document the distinction; defer rationalization to a future phase.
- **`WallTemperature` / `HeatFluxSource` test-file placement** — `test_misc.jl` (alongside ConstantTemperature) or new `test_sources.jl`. Planner picks based on file size after consolidation.

---

## Deferred Ideas

Captured in `55-CONTEXT.md` `<deferred>` section. Summary:
- ConstantTemperature / WallTemperature / HeatFluxSource rationalization — defer to future GUI phase.
- Channel / CHF "extra inputs" beyond T_wall and q (e.g., pressure forcing) — already work via existing binding-eqn idiom; no action needed.
- MTK-upstream issue for the [input=true] auto-anchor gap — Phase 55 sidesteps by removing the ports, but the gap exists for any future 2-across-1-flow connector. Out of v1.1 scope.
- GUI component-registry sync for the new value-source components — defer to GUI milestone.
- Cross-validation under the new architecture (TEST-04) — Phase 56's milestone gate.
- STATE.md Key Decisions update — happens at Phase 55 finalization or via `/gsd:extract-learnings`.
- CONN-02 + TEST-01 doc fixes — committed alongside CONTEXT.md / DISCUSSION-LOG.md per D-25 (mirrors Phase 54's pattern).
- Unification of example-script boilerplate across simple_loop / mtr_assembly / lof_transient — defer post-v1.1.
