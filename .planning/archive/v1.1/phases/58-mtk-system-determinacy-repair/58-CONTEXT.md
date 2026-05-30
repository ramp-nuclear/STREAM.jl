# Phase 58: MTK System Determinacy Repair - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Repair Julia STREAM's MTK system construction so that scenarios currently failing at the `mtkcompile` / `solve_steady` boundary with

> `ArgumentError: Equations (N), unknowns (N+1), and initial conditions (N+1) are of different lengths`

reach a working solver call and produce per-tier results. The root cause hypothesis (Phase 56 deferred-items D-1) is that ModelingToolkitBase upgraded between v1.1's baseline and the present `Manifest.toml`, and `mtkcompile(...; fully_determined=false)` no longer auto-balances the eq/unknown count. The fix lives at source — find what each broken builder is missing (an equation, a port-anchor, a topology binding) and add it. No `check_length=false` workarounds, no MTK package pinning backwards.

**In scope (scenarios that MUST reach a working solver call):**
- `Python parity: MTR symmetric` (`test/test_validation.jl` ≈ lines 390-410)
- `Python parity: MTR asymmetric` (`test/test_validation.jl` ≈ lines 560-580)
- `Python parity: MTR one-sided` (`test/test_validation.jl` ≈ lines 715-735)
- `VAL-01: HeatDiffusion transient — Fourier series validation` (`test/test_validation.jl:842`)
- `VAL-02: Two-plate one-channel topology — both faces active` (steady, `test/test_validation.jl:935`)
- `PointKinetics validation` testset (`test/test_validation.jl:1042`)
- `VAL-02 transient T_outlet rises after T_wall step` — distinct symptom (`ArgumentError: System sys: variable sys does not exist` on `ssys.sys.T_wall_callable`) but same MTK API drift family per D-1; in scope for diagnosis, fix may share or diverge from the structural-balance fix.

**In scope (sweep/audit):**
- `fully_determined=false` and `check_length=false` call sites across `src/` and `test/` — audit, classify, convert where possible to `fully_determined=true`; for sites that must keep `false` (e.g. `test/test_misc.jl:37` RL circuit with no T equations by design), add an inline comment naming the structural reason.

**In scope (regression test):**
- New determinacy assertion test ensuring `length(equations(ssys)) == length(unknowns(ssys))` AND `mtkcompile(sys; fully_determined=true)` succeeds for every canonical builder in `src/examples.jl` AND for each fixed scenario topology from this phase.

**Out of scope:**
- `check_length=false` workarounds anywhere in `src/solvers.jl::solve_steady` or anywhere else (locked: user directive, Plan 56-06 Task 2 verdict 2026-05-08).
- Pinning ModelingToolkit / ModelingToolkitBase / SciMLBase backwards in `Manifest.toml` to dodge the API drift.
- Phase 57's HTC film-T story — already shipped (`bf8b37e..2cf8a02`); MTR rows still emit `solver_error` sentinels until Phase 58 closes the gap.
- Phase 56 deferred-items D-2 (geometry precision %.10e → %.17g, three `rtol=1e-9` → `1e-12` re-tighten). Owned by Plan 56-06 resume; folding into Phase 58 mixes the phase boundary. The 1e-9 mitigation already in tree continues to pass.
- `NET-03 Cube flow` flakiness (Phase 55 D-22 documented flaky) — independent of MTK API drift.

**Out of scope as new capabilities:**
- Replacing `ThermalPort` / `FlowPort` connector design.
- Refactoring the `_channel_core` enthalpy-form energy balance.
- Adding a new builder API for "structurally validated systems"; the determinacy assertion test is the validation surface.
- Any new component or new physics — this is a structural-correctness phase.

</domain>

<decisions>
## Implementation Decisions

### Scenario scope (what must reach a working solver call)

- **D-01: Full set in scope.** All seven scenarios listed above MUST reach a working `solve_steady` (or `solve_transient` for VAL-01 / VAL-02 transient) and produce per-tier values. The user explicitly chose the broadest scope: MTR (3) + KEPT (HD Fourier VAL-01, two-plate VAL-02 steady, PK validation) + VAL-02 transient `T_wall` step. The transient case carries a distinct symptom (`variable sys does not exist`) but is acknowledged in `56-PAUSE-CONTEXT.md` line 53 as same family of API drift; if Plan 58-01's diagnostic shows the fix diverges, the planner is free to give it its own fix plan.

  *Rejected: MTR-only.* Leaves four KEPT testsets in known-broken state at v1.1 close — incompatible with the user's verdict against shipping with documented gaps (Plan 56-06 Task 2 directive).

  *Rejected: MTR + KEPT steady but exclude VAL-02 transient.* Leaves the transient T_wall step path failing; if the structural fix turns out to share a root cause with the steady scenarios (likely per D-1), excluding it just defers work that's about to be free.

### Plan structure

- **D-02: Diagnostic-first, then targeted fix plans.** Plan 58-01 builds a per-scenario diagnostic table without source edits — for each in-scope scenario, instantiate the topology, call `equations(ssys)`, `unknowns(ssys)`, `initialization_eqs(ssys)`, and produce a row: `(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)`. The table is committed as part of the plan SUMMARY and lives as documentation. Plan 58-02..N are one fix plan per scenario family (MTR pair handled together since same topology shape; VAL-01 HD-only Fourier; VAL-02 two-plate steady; PK validation; VAL-02 transient if diagnosis shows it diverges from steady). Each fix plan is small and verifiable in isolation.

  *Rejected: one plan per scenario family without a dedicated diagnostic plan.* Loses the consolidated picture of the determinacy gap pattern across scenarios — and that picture is exactly what informs the `fully_determined=false` audit.

  *Rejected: one combined fix plan.* Wide blast radius; if one fix regresses another scenario the bisect cost is high.

- **D-03: Diagnostic plan emits introspection on minimal repros, not full test files.** `/tmp/test_mtr.jl` is the canonical repro template (already exists, already triggers D-1). Build one minimal repro per scenario family in `tmp/` (or a one-off scratch dir under `.planning/phases/58.../scratch/`) — do not pollute `test/`. The introspection table becomes part of `58-01-SUMMARY.md`.

### `fully_determined=false` / `check_length=false` policy

- **D-04: Audit + convert + document survivors.** Plan 58-01's diagnostic step also greps `src/` and `test/` for every `fully_determined=false` and `check_length=false` site (today: `test/test_pump.jl:18,36,68,83,99,133`, `test/test_misc.jl:19,37,41,48,71,131,178`, `test/test_resistors.jl:18`, `test/test_validation.jl:204,379`, `src/components/flapper.jl:38` docstring, `src/components/channels.jl:207,409` comments). For each: classify as `legitimate-structural` (intentionally underdetermined, e.g. the RL circuit in `test_misc.jl:37` with no T equations) or `bug-hiding` (the gap is a real determinacy gap that should be fixed). Per-family fix plans (D-02) convert `bug-hiding` sites to `fully_determined=true` after their topology fix lands; `legitimate-structural` sites get an inline comment naming the structural reason ("no T equation exists in this topology by design — kept underdetermined for isolated-component test").

  *Rejected: leave existing `fully_determined=false` usages alone.* Preserves bug-hiding gaps in tests like `test_validation.jl:204,379` that may currently mask the same family of issue Phase 58 is trying to close.

  *Rejected: make `true` the default everywhere, no exceptions.* Forces rewriting the RL circuit test (`test_misc.jl:37`) and similar isolated-component tests to add anchors that don't reflect what those tests are validating. High blast radius for marginal benefit.

- **D-05: solve_steady stays as it is.** `src/solvers.jl::solve_steady` does NOT grow a `check_length` kwarg. The phase fixes determinacy at source so the kwarg is never needed. (Reaffirms the 2026-05-08 Plan 56-06 Task 2 directive.)

### Regression assertion

- **D-06: Per-builder + per-scenario determinacy test.** Add `test/test_determinacy.jl` (new file; mirrors the test-file-per-domain layout in CLAUDE.md "Test placement rule") with two testsets:
  1. **Canonical builders** — for every builder in `src/examples.jl` (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`), assert `mtkcompile(sys; fully_determined=true)` succeeds AND `length(equations(ssys)) == length(unknowns(ssys))`.
  2. **Phase-58 scenario topologies** — same assertions for each fixed scenario from D-01 (MTR sym/asym/one-sided, two-plate VAL-02 steady, HD Fourier transient setup, PK validation loop). Where a scenario topology lives only inside `test/test_validation.jl`, lift the topology into a small builder helper inside `test/test_determinacy.jl` so the assertion has a stable target.

  Add `include("test_determinacy.jl")` to `test/runtests.jl` (CLAUDE.md "Test placement rule": one `include()` per test file in the orchestrator).

  *Rejected: builders only.* Misses regressions in scenario topologies that today cost an entire `test_validation.jl` run to surface.

  *Rejected: no regression test.* Trust-and-pray; Phase 58's whole motivation is that this class of regression went undetected from a transitive dep upgrade.

### Branching

- **D-07: Stay on `channels-redesign`.** Per CLAUDE.md branching policy: GSD must never create its own branch; all Phase 58 commits land on the existing `channels-redesign` working branch off `main`. Verify `git rev-parse --abbrev-ref HEAD` matches before any commit. `.planning/config.json` `git.branching_strategy` must remain `"none"`.

### Claude's Discretion

- **MTK API drift root-cause depth.** Plan 58-01's diagnostic should read the recent ModelingToolkit / ModelingToolkitBase CHANGELOG entries near the version range in `Manifest.toml`, but does not need to bisect commit-by-commit. The user did not pick this as a separate gray area; use judgment in Plan 58-01.
- **Whether MTR sym + asym + one-sided collapse to one fix plan or three.** They share an identical topology shape (two `ChannelAndContacts` + `HeatDiffusion`-with-two-faces, varying only in `power_shape` and which face is heated). If diagnosis shows the missing equation is the same in all three, one fix plan covers them; if asymmetric/one-sided diverge, split.
- **Where the determinacy assertion's "scenario builder helpers" live.** Inside `test/test_determinacy.jl` is the default; if any helper is reusable beyond Phase 58's scope, the planner may lift it to `src/examples.jl`. Either is acceptable.
- **VAL-02 transient as its own plan vs folded into VAL-02 steady.** Decided by Plan 58-01's diagnostic. If the `variable sys does not exist` symptom shares root cause with the structural-balance gap (e.g. callable parameter wiring same as scalar parameter wiring), one plan; else two.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 58 motivation and root-cause hypothesis
- `.planning/phases/56-python-stream-cross-validation/deferred-items.md` §D-1 — original symptom statement, reproducer pointer (`/tmp/test_mtr.jl`), root-cause hypothesis (ModelingToolkitBase API drift), three resolution paths (only path 3 — "add the missing ICs/equations to each affected scenario at source" — is permitted; paths 1 and 2 are explicitly out of scope per Phase 58 lock).
- `.planning/phases/56-python-stream-cross-validation/56-PAUSE-CONTEXT.md` lines 22, 31, 47-55 — Phase 58 → Phase 56 resume gate; six failures Phase 58 must resolve; "fix at source so equations == unknowns. No `check_length=false` workarounds" directive.
- `.planning/phases/57-htc-film-temperature-evaluation/57-CONTEXT.md` line 22 — Phase 57's explicit hand-off note that MTR scenarios continue to emit `solver_error` sentinels until Phase 58 ships.
- `.planning/phases/57-htc-film-temperature-evaluation/57-01-SUMMARY.md` line 120 — confirms post-Phase-57 MTR rows are still `solver_error` sentinels.

### MTK structural patterns this phase relies on
- `.planning/STATE.md` lines 73-74 (entry tagged `[v1.1 CONN-impl, 2026-05-06]`) — `WallPort` drive-aware self-anchoring pattern: 2-across/1-flow connectors are structurally underdetermined when unconnected; "driven ports get the channel-side `Q_flow ~ h·A·(T_wall−T)` equation; unconnected ports self-anchor `T_wall ~ T_default; h ~ 0`. The two cases are mutually exclusive per port — mixing them over-determines the system." This pattern is the prior art for closing per-port determinacy gaps.
- `src/components/channels.jl:716-722` — `ChannelAndContacts` per-cell `ThermalPort` adiabatic-when-unconnected story; the "MTK's Flow rule auto-zeros Q_flow ⇒ q_*_expr[i] = 0 ⇒ T_wall[i] = T[i]" comment is the contract Phase 58 must verify still holds under the new MTK API.
- `src/connectors.jl:17-24` — `ThermalPort` definition (across=T, flow=Q_flow); the only port type used at CAC↔HD seams.

### Project + memory invariants
- `CLAUDE.md` "Branching Policy" — D-07 derives from this; Phase 58 must not create branches.
- `CLAUDE.md` "Test placement rule" — `test_determinacy.jl` placement (D-06) follows the per-domain rule; new file added to `test/runtests.jl` orchestrator.
- `~/.claude/projects/-home-itay-projects-Julia-STREAM/memory/feedback_channel_hd_connection_rule.md` — architectural invariant: only `ChannelAndContacts` connects to `HeatDiffusion`. MTR + VAL-02 + HD Fourier scenarios respect this; no Phase 58 fix may violate it.

### Test files in scope
- `test/test_validation.jl` lines ~390-410, ~560-580, ~715-735 (MTR sym/asym/one-sided), 842 (VAL-01 Fourier), 935 (VAL-02 two-plate steady), ≈1042-1213 (PK validation), ≈line 295 area (VAL-02 transient `T_outlet` rises after `T_wall` step — distinct symptom).
- `/tmp/test_mtr.jl` — pre-existing minimal repro template; Plan 58-01 builds analogous scratch repros for the other scenarios.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`src/solvers.jl::solve_steady`** (line 73) — currently passes `warn_initialize_determined=false` but NOT `check_length=false`. D-05 keeps it that way. Phase 58 must not edit this signature.
- **`src/components/channels.jl::ChannelAndContacts`** (line 584) — per-cell `ThermalPort` arrays + internal `h_tc[i] * heated_parts[1,2] * dz * (T_wall - T)` q-expression; comment block at lines 716-722 explicitly describes the adiabatic-when-unconnected contract that depends on MTK's Flow rule. Phase 58 verifies this contract still holds.
- **`src/components/heat_diffusion.jl`** lines 36-50 — HD's `thermal_left[i].Q_flow ~ k_s * (y * dz) * (thermal_left[i].T - T[i,1]) / (dx/2)` constitutive equation. CAC↔HD seam is the canonical structurally balanced shape — diagnostic plan checks every other in-scope scenario against it.
- **`/tmp/test_mtr.jl`** — already-built minimal repro for MTR symmetric (45 lines, no Phase-56 wiring); the canonical template for new minimal repros in Plan 58-01.

### Established Patterns
- **WallPort drive-aware self-anchoring** (Phase 52, see `STATE.md` ref above) — when a 2-across/1-flow port is unconnected, MTK's Flow rule zeros only the Flow variable, leaving Across variables free. The fix is per-port mutually-exclusive: drive it (closing equation from upstream) or self-anchor it (`T ~ default; h ~ 0`). This is the most likely shape of Phase 58's per-scenario fixes.
- **`fully_determined=false` legitimate uses** (`test/test_misc.jl:37`) — pure RL circuit has no T equations by design; the `false` is structural, not a bug. The audit (D-04) preserves these with inline comments.
- **CAC adiabatic-when-unconnected** (`channels.jl:716-722`) — uses MTK's auto-zero Flow rule to settle to `T_wall[i] = T[i]` on dangling ports. If MTK's auto-zero behavior changed across the version drift, this contract is the first thing the diagnostic must check.
- **Pressure anchor pump.port_in.P ~ 1.0e5** (`PROJECT.md:183`, present in every multi-branch builder) — required to pin absolute pressure in Kirchhoff networks. Phase 58 builders that fail may be missing an analogous "absolute" anchor on a non-pressure dimension.

### Integration Points
- **`test/runtests.jl`** — orchestrator; D-06's new `test_determinacy.jl` adds one `include()` line.
- **`test/test_validation.jl`** — six in-scope scenarios live here; Plan 58-01's diagnostic introspects them; per-family fix plans land their structural fix at the topology site (or in the underlying builder if the scenario uses `build_*` from `examples.jl`).
- **`Manifest.toml`** — read-only for Phase 58; do not bump or pin MTK package versions. The fix is at source.
- **`src/examples.jl`** — canonical builders (lines 56, 139, 218, 309, 429); D-06's per-builder determinacy assertion targets these.

</code_context>

<specifics>
## Specific Ideas

- The user's exact directive (Plan 56-06 Task 2, 2026-05-08): "**Phase 58 (MTK determinacy):** Find why current loop builders produce under-determined systems. Fix at source so equations == unknowns. No `check_length=false` workarounds."
- The diagnostic table's columns are concrete: `(scenario, n_eqs, n_unknowns, n_init_eqs, missing_kind, hypothesis, fix_sketch)`. Use these column names verbatim in `58-01-SUMMARY.md`.
- The determinacy assertion is `length(equations(ssys)) == length(unknowns(ssys))` AND `mtkcompile(sys; fully_determined=true)` succeeds. Both checks; the second is the stronger contract.
- Daemon dev loop (CLAUDE.md "Daemon dev loop") is the primary workflow. Plan 58-01's diagnostic introspection runs through `bin/jl scratch_repro.jl` per scenario. Cold-start `julia --project=.` is the documented fallback if the daemon's `Sockets`-vs-MTK `connect` ambiguity from Phase 57 D-04 deviation #1 resurfaces.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 56 deferred-items D-2 (geometry precision)** — bump `PARITY_MTR_GEOM_DH` emit precision from `%.10e` to `%.17g` in `test/generate_mtr_reference.py`, regenerate `test/data/python_parity_reference.jl`, tighten the three `rtol=1e-9` call sites back to `rtol=1e-12`. Owned by Plan 56-06 resume; not folded into Phase 58 to keep the phase boundary clean. The current `rtol=1e-9` mitigation continues to pass.
- **MTK API drift bisect** — the user did not pick "deep bisect of ModelingToolkitBase" as a gray area. If Plan 58-01's CHANGELOG read does not produce a clear hypothesis, escalation to a bisect can happen inside that plan; otherwise it is deferred indefinitely.
- **Replacing `solve_steady` with a "structurally validated" wrapper** that calls `mtkcompile(sys; fully_determined=true)` internally. Would obviate the per-builder determinacy assertion but requires API coordination across every existing caller. Not in scope for v1.1.
- **NET-03 Cube flow flakiness** (Phase 55 D-22) — independent of MTK API drift; flaky for unrelated reasons. Stays deferred.

</deferred>

---

*Phase: 58-mtk-system-determinacy-repair*
*Context gathered: 2026-05-08*
