---
phase: 61-registry-audit-rewrite-for-v1-1
plan: 02
subsystem: gui/registry
tags: [gui, registry, channels, heat-diffusion]
dependency-graph:
  requires:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-CONTEXT.md (D-03..D-21)
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-01-SUMMARY.md (Plan 01: extended TypeScript schema)
    - .planning/notes/correlation-geom-first-api.md (Phase 59 geom-first factory shapes)
    - src/components/channels.jl (lines 199-207, 357-363, 467-475 — authoritative signatures)
    - src/components/heat_diffusion.jl (HD port names + parameters)
  provides:
    - "v1.1 Channel entry: no thermal port; polymorphic h_left/h_right; external_inputs[T_wall_left,T_wall_right] -> WallTemperature; reshaped friction options"
    - "v1.1 ChannelHeatFlux entry: no thermal port; no T_wall scalar; external_inputs[q_left,q_right] -> HeatFluxSource"
    - "v1.1 ChannelAndContacts entry: collapsed factory sub-trees (Phase 59 geom-first); thermal port pair with array_size/default_axis=vertical/pair_with"
    - "v1.1 HeatDiffusion thermal port pair: array_size=nz, default_axis=horizontal, pair_with"
  affects:
    - gui/src/registry/__tests__/registry.test.ts (3 test cases relaxed/rewritten for v1.1)
    - gui/src/store/__tests__/useStore.test.ts (Channel default-population test updated)
    - gui/src/lib/codeGenerator.ts (array-port predicate extended to recognise array_size)
tech-stack:
  added: []
  patterns:
    - "Polymorphic kwargs via type_union + input_modes (Channel.h_left, Channel.h_right)"
    - "external_inputs[] top-level array (separate from parameters[] — Properties vs BCs tab split)"
    - "Factory geom_source='parent' tag on every geometry-bearing correlation factory"
    - "regime_dependent.produces: ['htc','friction'] (NamedTuple return) — registry stays simple; codegen owns dedupe"
    - "Thermal port pair via array_size + default_axis + pair_with triple (replaces legacy array/arrayParam/side)"
key-files:
  created:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-02-SUMMARY.md
  modified:
    - gui/src/registry/components.json
    - gui/src/registry/__tests__/registry.test.ts
    - gui/src/store/__tests__/useStore.test.ts
    - gui/src/lib/codeGenerator.ts
decisions:
  - "Bounded regime_dependent.htc_laminar.options (and htc_turbulent / htc_natural) to the HTC stateless and factory leaves — no nested regime_dependent — to avoid infinite recursion in the JSON tree. D-08 and the CONTEXT <specifics> sketch are silent on the question but the plan body explicitly forbids self-recursion."
  - "Dropped maximal_htc from CAC htc_correlation.options. The Phase 59 / D-08 allowlist does not list it, and the executor verified that src/physical_models/htc/correlations.jl still defines maximal_htc as an HTC combinator — but exposing it to v1.1 registry forms requires a sub_parameter tree (htc1/htc2 sub-pickers) and a `geom_source` rule that Phase 59 did not specify. Plan 04's unchanged-component re-audit can revive it if needed; Phase 61's explicit D-08 list is the binding contract here."
  - "Dropped scb_correction from CAC parameters and constructorModes. The Julia constructor still carries it as an optional kwarg, but v1.1 D-08 allowlist for CAC.parameters omits it, and the plan body's exact parameters order ('n, geometry, g, htc_correlation, friction_correlation') matches that omission. Advanced users can still set scb_correction by direct .jl edit; exposing it requires a function-typed registry slot that is out of v1.1 scope."
  - "Left CAC's friction_correlation including regime_dependent as a sibling option. D-09 explicitly mandates this — regime_dependent is independently selectable on both htc and friction fields; the registry tree carries the same recursive sub_parameter shape twice. The Phase 66 codegen-side dedupe is what collapses semantically-identical regime_dependent calls into a single `rd = regime_dependent(...)` call at code-emit time."
  - "Extended codeGenerator.ts's ConstantTemperature → array-ThermalPort branch to recognise v1.1 `array_size` ALONGSIDE the legacy `array: true` + `arrayParam` pair. Tasks 3/4 dropped the legacy keys from CAC/HD; the codegen would silently no-op the per-cell connect emission otherwise. The fix is a 3-line predicate widening; backwards compatible with any unrewritten entries that still carry the legacy keys."
metrics:
  duration: "~6m"
  completed: 2026-05-12
  tasks_completed: 4
  files_changed: 4
  files_created: 1
---

# Phase 61 Plan 02: Channel-family v1.1 registry rewrite — Summary

**One-liner:** Rewrote the four channel-family entries (Channel, ChannelHeatFlux, ChannelAndContacts, HeatDiffusion) in `gui/src/registry/components.json` to v1.1: Channel and CHF lose their thermal port (T_wall and q are external-input @variables now), Channel gains polymorphic per-cell `h_left`/`h_right`, CAC's correlation factory tree collapses per Phase 59 geom-first with `geom_source: "parent"` tags, and the thermal port pairs on CAC and HD pick up the v1.1 `array_size` / `default_axis` / `pair_with` shape (CAC vertical, HD horizontal).

## What shipped

### Task 1 — Channel entry (commit `edd8930`)

- **Ports:** dropped legacy `thermal: ThermalPort` entry. Channel now lists only `port_in` and `port_out` (FlowPort, left/right). Source: `channels.jl:199-207` plus per-D-18.
- **Parameters:** dropped `htc_correlation` (D-18: only CAC carries HTC under v1.1). Added polymorphic `h_left` / `h_right` per D-10 with `type_union: ["Real","Vector","Function"]` and `input_modes: ["scalar","vector","callable"]`. Source: `channels.jl:204-205`.
- **friction_correlation options:** reshaped per Phase 59 / D-08 / CD-03. Three options: `blasius_friction` (stateless), `turbulent_friction` (stateless, sub_parameter `epsilon`), `laminar_friction` (factory, `geom_source: "parent"`). `regime_dependent` intentionally not listed — Channel has no HTC consumer per CD-03.
- **external_inputs (NEW):** two entries `T_wall_left` and `T_wall_right`, both with `shape: "[1:n]"`, `unit: "K"`, `bc_modes: ["Value","Profile","Function","Mark","Source"]`, `source_component: "WallTemperature"`, `source_port: "T_wall_out"`. The `WallTemperature` FK resolves at Plan 03 (Plan 05 owns the build-time cross-validation test).
- **constructorMode:** `Channel(; n, geometry, g=0.0, h_left=0.0, h_right=0.0, friction_correlation=blasius_friction)`.

### Task 2 — ChannelHeatFlux entry (commit `e2dd146`)

- **Label / description:** updated to "Channel (Heat Flux BC)" for v1.1 clarity (CHF imposes flux directly, no `h` Properties-tab kwarg).
- **Ports:** identical to Channel — `port_in` / `port_out` (FlowPort). No thermal port (D-19).
- **Parameters:** dropped `T_wall` scalar (D-03/D-05 replace it with per-cell q external_inputs in W/m²). Dropped `htc_correlation` (CHF imposes flux directly, no HTC consumer). Kept `n`, `geometry`, `g`, `friction_correlation`. `friction_correlation` sub-tree mirrors Channel's exactly (same three stateless/factory options).
- **external_inputs (NEW):** `q_left` and `q_right`, both `[1:n]` shape, unit `W/m^2`, source `HeatFluxSource.q_out`.
- **constructorMode:** `ChannelHeatFlux(; n, geometry, g=0.0, friction_correlation=blasius_friction)`. Source: `channels.jl:357-363`.

### Task 3 — ChannelAndContacts entry (commit `51ea240`)

This is the heaviest single rewrite — CAC carries the deepest correlation factory tree.

- **Label:** "Channel And Contacts" → "Channel and Contacts" (lowercase article, cosmetic).
- **Ports (D-20):** four entries — `port_in` / `port_out` (FlowPort, left/right) + `thermal_left` / `thermal_right` (ThermalPort, `array_size: "n"`, `default_axis: "vertical"`, `pair_with` cross-references). Legacy `array: true`, `arrayParam: "n"`, `side: "top"/"bottom"` keys removed from the rewritten thermal ports per the plan body's explicit instruction.
- **Parameters:** five entries (`n`, `geometry`, `g`, `htc_correlation`, `friction_correlation`). Dropped `scb_correction` (see Decisions).
- **htc_correlation options (D-08 exact list):**
  - `dittus_boelter` — stateless, no sub_parameters.
  - `constant_Nusselt` — stateless, sub_parameter `Nu` (default 8.235).
  - `elenbaas_htc` — factory, `geom_source: "parent"`, sub_parameter `g` (default 9.81).
  - `developing_laminar_h_spl` — factory, `geom_source: "parent"`, sub_parameter `develop_length` (required, `no_default: true`).
  - `fully_developed_laminar_h_spl` — factory, `geom_source: "parent"`, no sub_parameters (CD-01: omitted entirely for JSON cleanliness).
  - `regime_dependent` — factory, `geom_source: "parent"`, `produces: ["htc","friction"]`, 7 sub_parameters per D-08 (`htc_laminar`/`htc_turbulent`/`friction_laminar`/`friction_turbulent` all required; `htc_natural` optional; `g` with `required_if: "htc_natural"`; `Re_transition` default 2300). The nested `htc_*` options exclude `regime_dependent` itself (no recursion); the nested friction options exclude it too. Same recursive tree appears under both `htc_correlation.regime_dependent` and `friction_correlation.regime_dependent` per D-09 (independently selectable).
- **friction_correlation options:** four entries — `blasius_friction` (stateless), `turbulent_friction` (stateless + `epsilon`), `laminar_friction` (factory + `geom_source`), `regime_dependent` (factory + `produces` + same 7-sub_parameter tree).
- **external_inputs:** omitted entirely (D-03: CAC has no external inputs — its thermal boundary is set via the `thermal_left`/`thermal_right` MTK ports).
- **constructorMode:** `ChannelAndContacts(; n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction)`.

**Verified by recursive walk over CAC's entire sub_parameter tree:** zero occurrences of `Dh`, `L`, `b`, or `aspect_ratio` anywhere — every factory's geometry kwargs are gone, as Phase 59 / D-07 requires.

### Task 4 — HeatDiffusion thermal port pair (commit `64317db`)

- **Ports (D-21):** thermal_left / thermal_right reshaped from legacy `{type, side, array: true, arrayParam: "nz"}` to v1.1 `{type, array_size: "nz", default_axis: "horizontal", pair_with}`. Note `default_axis` is horizontal (distinct from CAC's vertical) and `array_size` references `"nz"` not `"n"` (HD's array parameter is `nz` per `heat_diffusion.jl:130-136`).
- **Parameters / constructorModes:** unchanged (per plan body — Plan 04 owns the full unchanged-components re-audit).
- **external_inputs:** absent (HD's `T[1:nz,1:nx]` is internal state, not a BC).

## Verification

| Check | Result |
|-------|--------|
| `node` audit: `components.length` | `12` (unchanged) |
| Channel: no `ThermalPort` in `.ports`; `h_left`/`h_right` present; no `htc_correlation`; `external_inputs.length === 2` pointing to WallTemperature | PASS |
| CHF: no `ThermalPort`; no `T_wall`; no `htc_correlation`; `external_inputs.length === 2` pointing to HeatFluxSource; unit `W/m^2` | PASS |
| CAC: 4 ports; thermal pair has `array_size="n"` / `default_axis="vertical"` / `pair_with` cross-ref; recursive walk finds zero `Dh`/`L`/`b`/`aspect_ratio`; `elenbaas_htc.geom_source==="parent"`; `regime_dependent.produces===["htc","friction"]`; no `external_inputs` | PASS |
| HD: thermal pair has `array_size="nz"` / `default_axis="horizontal"` / `pair_with`; no legacy `array`/`arrayParam`/`side` keys on thermal ports; no `external_inputs` | PASS |
| `npm test` (vitest full suite) | **232 passed, 17 todo, 1 skipped — no regressions** |
| `npm run build` | **7 pre-existing tsc errors (deferred-items.md baseline), 0 new errors from Plan 02** |

## Deviations from Plan

### Rule 3 — Auto-fixed blocking issues

All four deviations below were forced by the v1.0-baked test fixtures in the GUI test suite. The plan body explicitly states the legacy tests will be updated in Plan 05, but that would leave the test suite red across the entire wave 2 → wave 3 gap. Per Rule 3, each test that hard-asserts the v1.0 schema was updated in lockstep with the JSON entry it covers.

**1. [Rule 3 — Blocking] Relaxed `every parameter has required fields` to accept `type_union` (Task 1)**
- **Found during:** Task 1 verification (`npx vitest run`).
- **Issue:** Test asserted `param.type` is truthy on every parameter. v1.1 D-10 polymorphic kwargs (Channel.h_left, Channel.h_right) carry `type_union` *instead of* `type`. Plan 01 made `Parameter.type` optional in `types.ts`, but the runtime assertion lagged behind.
- **Fix:** Asserted `param.type || param.type_union` instead. Same coverage, accepts both shapes.
- **Files modified:** `gui/src/registry/__tests__/registry.test.ts`.
- **Commit:** `edd8930`.

**2. [Rule 3 — Blocking] Updated `populates default parameter values from registry` for v1.1 Channel defaults (Task 1)**
- **Found during:** Task 1 verification.
- **Issue:** Test asserted `data.parameters.htc_correlation === "dittus_boelter"`. v1.1 Channel has no `htc_correlation` parameter (D-18).
- **Fix:** Replaced the htc_correlation assertion with `h_left === 0.0` and `h_right === 0.0` (Channel's v1.1 defaults from `channels.jl:204-205`).
- **Files modified:** `gui/src/store/__tests__/useStore.test.ts`.
- **Commit:** `edd8930`.

**3. [Rule 3 — Blocking] Updated `ChannelHeatFlux has no ThermalPort (T_wall is scalar BC)` for v1.1 CHF shape (Task 2)**
- **Found during:** Task 2 verification.
- **Issue:** Test asserted `chf.parameters.find(p => p.name === 'T_wall').type === 'Real'`. v1.1 CHF dropped the `T_wall` scalar parameter entirely (D-03/D-05 replace it with per-cell `q_left[1:n]` / `q_right[1:n]` external_inputs in W/m^2).
- **Fix:** Renamed the test and rewrote its body to assert the v1.1 shape — `T_wall` is undefined; `external_inputs` is `["q_left","q_right"]`; each entry's `source_component === "HeatFluxSource"` and `source_port === "q_out"` and `unit === "W/m^2"`.
- **Files modified:** `gui/src/registry/__tests__/registry.test.ts`.
- **Commit:** `e2dd146`.

**4. [Rule 3 — Blocking] Relaxed `every port has required fields` to allow optional `side` on array ports (Task 3)**
- **Found during:** Task 3 verification.
- **Issue:** Test asserted `port.side` matches `/^(left|right|top|bottom)$/` on every port. v1.1 D-16 made `side` optional on array-shaped logical ports that autoflip via `default_axis` (CAC/HD's thermal pairs).
- **Fix:** When `port.side` is set, assert the regex as before. When `port.side` is absent, require `port.default_axis` to match `/^(horizontal|vertical)$/`. Also widened the `port.type` regex to admit `BCPort` per D-14 (forward-compatible with Plan 03).
- **Files modified:** `gui/src/registry/__tests__/registry.test.ts`.
- **Commit:** `51ea240`.

**5. [Rule 3 — Blocking] Updated `ChannelAndContacts has ThermalPort array ports` for v1.1 array_size shape (Task 3)**
- **Found during:** Task 3 verification.
- **Issue:** Test asserted `thermalLeft.array === true` and `thermalLeft.arrayParam === 'n'`. Plan body explicitly drops those legacy keys from CAC's rewritten thermal ports.
- **Fix:** Asserted `array_size === "n"`, `default_axis === "vertical"`, `pair_with === "thermal_right"` (and symmetrically for thermal_right).
- **Files modified:** `gui/src/registry/__tests__/registry.test.ts`.
- **Commit:** `51ea240`.

**6. [Rule 3 — Blocking] Updated `HeatDiffusion has ThermalPort array ports` for v1.1 array_size shape (Task 4)**
- Same shape as deviation #5 but for HD. `array_size === "nz"`, `default_axis === "horizontal"`, `pair_with` cross-refs.
- **Files modified:** `gui/src/registry/__tests__/registry.test.ts`.
- **Commit:** `64317db`.

**7. [Rule 3 — Blocking] Extended `codeGenerator.ts` array-port predicate to recognise `array_size` (Task 4)**
- **Found during:** Task 4 — discovered while auditing codegen consumers of CAC/HD thermal ports.
- **Issue:** `gui/src/lib/codeGenerator.ts:733` (the ConstantTemperature → array ThermalPort branch that emits per-cell `connect(ct.thermal, port(cac, :thermal_left, i)) for i in 1:n` codegen) checked only the legacy `array: true` key. Tasks 3/4 dropped that key from CAC/HD, which would have silently no-op'd the per-cell emission and produced wrong Julia code.
- **Fix:** Widened the predicate: `sourcePort?.array === true || typeof sourcePort?.array_size === "string"` (and symmetrically for target). The `nParam` lookup now prefers `array_size` and falls back to `arrayParam` for any not-yet-migrated entries. Backwards compatible.
- **Files modified:** `gui/src/lib/codeGenerator.ts`.
- **Commit:** `64317db`.

### Decisions (Claude's discretion — see frontmatter)

Four decisions taken under D-06/D-08/D-09/CD-01 ambiguity — see `decisions:` in the frontmatter. Most consequential:

- **`regime_dependent` sub-pickers do NOT recurse into `regime_dependent`.** The CONTEXT `<specifics>` sketch is silent here, but Phase 61 plan body Task 3 explicitly states "no infinite recursion" for the `htc_laminar.options` list. Same applied to `htc_turbulent`, `htc_natural`, `friction_laminar`, `friction_turbulent`.
- **`maximal_htc` not exposed under CAC.** Phase 59 / D-08 allowlist for CAC omits it. Plan 04's re-audit can revive it.
- **`scb_correction` not exposed.** Plan body's exact parameters list for CAC has 5 entries; `scb_correction` is not one of them.

## Source-vs-registry discrepancies surfaced

None at the signature level — the four entries now mirror `src/components/channels.jl:199-207`, `:357-363`, `:467-475` and `src/components/heat_diffusion.jl:130-136` exactly for kwargs in scope. Out-of-scope advanced kwargs that exist in `src/` but aren't yet exposed in v1.1 registry:

- `ChannelAndContacts(scb_correction=nothing)` — registry omits this kwarg per Plan 02 Decisions (see frontmatter). Advanced users invoke it by direct .jl edit. A future plan (post-v1.2) can expose it once an SCB closure-picker UI exists.

No physics discrepancies, no broken assumptions, no Julia source changes required.

## Threat Flags

None. All four entries mirror Julia source signatures that already exist; no new attack surface introduced. The `external_inputs[].source_component` FK is a known trust-boundary point already enumerated in the Plan threat model (T-61-05 accepted, T-61-06 mitigated by Plan 05's cross-validation test).

## Deferred Issues

The 7 pre-existing TypeScript build errors documented in `.planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md` remain present. Line numbers shifted slightly (`codeGenerator.ts:736 → 740` for the `singlePort` unused-local lint) due to my 3-line edit at line 733; same error, same root cause (`singlePort` was added in the original feature commit but never used downstream — pre-existing dead code).

No new tsc errors introduced by Plan 02.

## Self-Check

```bash
[ -f gui/src/registry/components.json ] && echo FOUND || echo MISSING                               # FOUND
[ -f gui/src/registry/__tests__/registry.test.ts ] && echo FOUND || echo MISSING                    # FOUND
[ -f gui/src/store/__tests__/useStore.test.ts ] && echo FOUND || echo MISSING                       # FOUND
[ -f gui/src/lib/codeGenerator.ts ] && echo FOUND || echo MISSING                                   # FOUND
[ -f .planning/phases/61-registry-audit-rewrite-for-v1-1/61-02-SUMMARY.md ] && echo FOUND           # written by this commit
git log --oneline | grep -q edd8930 && echo FOUND                                                   # FOUND (Task 1)
git log --oneline | grep -q e2dd146 && echo FOUND                                                   # FOUND (Task 2)
git log --oneline | grep -q 51ea240 && echo FOUND                                                   # FOUND (Task 3)
git log --oneline | grep -q 64317db && echo FOUND                                                   # FOUND (Task 4)
```

## Self-Check: PASSED

All claimed files exist on disk; all four task commits (`edd8930`, `e2dd146`, `51ea240`, `64317db`) are present in the worktree branch history. The `npm test` suite passes 232/232 (no regressions, no tests skipped beyond the 1 pre-existing skip). `npm run build` produces exactly the 7 pre-existing baseline tsc errors and zero new errors.
