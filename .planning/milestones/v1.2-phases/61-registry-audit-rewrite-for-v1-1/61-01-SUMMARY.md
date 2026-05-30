---
phase: 61-registry-audit-rewrite-for-v1-1
plan: 01
subsystem: gui/registry
tags: [gui, registry, schema, typescript]
dependency-graph:
  requires:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-CONTEXT.md (D-01..D-21)
    - .planning/notes/correlation-geom-first-api.md (Phase 59 factory shapes)
    - .planning/notes/gui-redesign-design-decisions.md (§3.1, §3.4, §3.10, §3.11)
  provides:
    - "Extended ComponentRegistry TypeScript schema (gui/src/registry/types.ts) admitting all v1.1 fields"
    - "Version-bumped envelope (gui/src/registry/components.json: stream_version 1.1.0, schema_version 2.0)"
  affects:
    - gui/src/lib/codeGenerator.ts (return-type widened for BCPort)
    - gui/src/components/StreamNode.tsx (non-null assertions on optional Port.side)
tech-stack:
  added: []
  patterns:
    - "Additive TypeScript extension — new fields optional so unrewritten entries still parse"
    - "Separate top-level external_inputs[] array (Properties tab vs BCs tab split via structural separation, not a scope field — D-04)"
    - "Polymorphic type_union + input_modes pair for kwargs (Real|Vector|Function); bc_modes for external-input fields"
    - "BCPort GUI-only port-type tag (no src/ counterpart) for dashed-edge value-source outputs"
key-files:
  created:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-01-SUMMARY.md
  modified:
    - gui/src/registry/types.ts
    - gui/src/registry/components.json
    - gui/src/registry/__tests__/registry.test.ts
    - gui/src/lib/codeGenerator.ts
    - gui/src/components/StreamNode.tsx
decisions:
  - "Kept ports + constructorModes REQUIRED on ComponentDefinition; Plan 04 widens them when ReactivityController (the first Resource) lands. Loosening here would have forced a cascade of non-null assertions across 7 files that legitimately assume canvas components have ports/modes."
  - "Made Port.side optional (per D-16 — autoflip array ports leave it undefined). Two existing StreamNode call sites already index sideToPosition[port.side]; added `!` non-null assertions since the 12 current entries still set side. Plans 02/03/04 will swap these for proper default_axis-aware handle placement."
  - "Widened getPortTypeFromDef return type in codeGenerator.ts from `FlowPort | ThermalPort | undefined` to also include `BCPort` — direct consequence of Port.type union growing per D-14. One-line edit, minimal blast radius."
  - "Made FunctionOption.label optional (D-06 — some Phase 61 factory entries omit it). Kept `kind` retaining the legacy `simple` value alongside the new `stateless` and existing `factory` so the 12 unrewritten entries still parse."
  - "Made Parameter.type optional, Parameter.description optional. JSON audit confirmed every existing entry sets both — relaxing them only widens the schema for v1.1 Mark-typed entries (PointKinetics temp_worth/ref_temp, ReactivityController input_reactivity/state_machine/abort_states) per D-12, D-13."
metrics:
  duration: "4m 15s"
  completed: 2026-05-12
  tasks_completed: 2
  files_changed: 5
  files_created: 2
---

# Phase 61 Plan 01: Registry schema vocabulary extension + envelope bump — Summary

**One-liner:** Extended `gui/src/registry/types.ts` to admit the full v1.1 schema vocabulary (external_inputs, type_union, input_modes, bc_modes, geom_source, array_size, default_axis, pair_with, produces, BCPort, ExternalInput, resource_kind, Sources/Resources/Reactor Physics categories, no_default/required_if/visible_when) and bumped `components.json` to `stream_version 1.1.0` / `schema_version 2.0`; component bodies untouched, ready for Plans 02/03/04 to populate.

## What shipped

### Task 1 — extend `types.ts` (commit `d8111a9`)

Additions to the TypeScript schema (each backed by a CONTEXT decision):

**`Port` interface (D-14, D-16, D-17, D-20, D-21):**
- New `PortType` union type: `"FlowPort" | "ThermalPort" | "BCPort"`. `BCPort` is GUI-only — no src/ counterpart, no MTK connector type. Used for value-source outputs (`WallTemperature.T_wall_out`, `HeatFluxSource.q_out`).
- `side` made optional. Array-shaped logical ports that autoflip via `default_axis` can leave `side` undefined; the 12 current entries still set it.
- `array_size?: string` — string-valued reference to a sibling `parameters[]` entry (e.g., `"n"`, `"nz"`). Replaces the legacy `array` + `arrayParam` pair (Plan 05 sunsets them).
- `default_axis?: "horizontal" | "vertical"` — drives §3.4 autoflip default.
- `pair_with?: string` — opposing port name for thermal pairs (locks autoflip).
- Legacy `array?: boolean` and `arrayParam?: string` retained for backwards compatibility with the 12 unrewritten entries; consumed by `codeGenerator.ts:730+` (ConstantTemperature array-port handler) and the existing `registry.test.ts:84+` assertions.

**`FunctionOption` interface (D-06, D-07, D-09):**
- `label` made optional (some Phase 61 factory entries omit it).
- `kind` union extended from `"simple" | "factory"` to `"simple" | "stateless" | "factory"`. `simple` retained for backwards compatibility with unrewritten entries; `stateless` is the v1.1 replacement for stateless options like `dittus_boelter`.
- `geom_source?: "parent"` — factory derives geometry from parent channel's `geometry` Resource. Applies to `laminar_friction`, `elenbaas_htc`, `developing_laminar_h_spl`, `fully_developed_laminar_h_spl`, `regime_dependent`.
- `produces?: ReadonlyArray<"htc" | "friction">` — only `regime_dependent` carries `["htc", "friction"]` (NamedTuple return). Registry stays simple; Phase 66 owns the dedupe codegen rule.

**`Parameter` interface (D-04, D-08, D-10, D-12, D-13):**
- `type` made optional, `description` made optional (relaxed for v1.1 Mark-typed entries; all 12 current entries still set both — audited via `node -e`).
- `type` union extended to admit `"Vector" | "Symbol"`.
- `type_union?: ReadonlyArray<"Real"|"Vector"|"Function"|"ReactivityController"|"Mark"|"Symbol">` — polymorphic kwarg type list. Used with `input_modes` (1:1).
- `input_modes?: ReadonlyArray<"scalar"|"vector"|"callable"|"controller">` — GUI mode-picker labels.
- `no_default?: boolean` — required-without-default for `developing_laminar_h_spl.develop_length` (Phase 59 D-04 forbids silent substitution with `geom.L`).
- `required_if?: string` — conditional required-when-sibling-set (e.g., `regime_dependent.g` is required only when `htc_natural` is set).
- `visible_when?: string` — GUI visibility predicate against sibling parameter modes (e.g., PointKinetics `temp_worth` visible only when `rho.input_mode in ['callable','controller']`).

**`ExternalInput` interface (NEW, D-03, D-05, D-11):**
```ts
export interface ExternalInput {
  name: string;
  shape: string;               // e.g. "[1:n]"
  unit?: string;
  description: string;
  bc_modes: ReadonlyArray<"Value" | "Profile" | "Function" | "Mark" | "Source">;
  source_component: string;    // allowed value-source id, e.g. "WallTemperature"
  source_port: string;         // allowed source-port name, e.g. "T_wall_out"
}
```
Distinct from `parameters[]` — `parameters[]` stays a pure constructor-kwarg list; `external_inputs[]` declares MTK `@variable` BCs that the BCs tab renders. `bc_modes` is deliberately distinct from `input_modes` because BCs include modes (`"Mark"` = emit `# TODO:` comment, `"Source"` = dashed BC edge to a value-source block) that don't apply to constructor kwargs.

**`ComponentDefinition` interface (D-03, D-12, D-13):**
- `category` union extended to admit `"Sources" | "Resources" | "Reactor Physics"`. Existing `"Hydraulic"` and `"Thermal"` retained.
- `external_inputs?: ReadonlyArray<ExternalInput>` — top-level array per entry (absent when no external inputs).
- `resource_kind?: string` — for Resource entries (`ReactivityController` carries `"reactivity_controller"`).
- `ports` and `constructorModes` left REQUIRED for now — see Decisions below.

### Task 2 — version envelope bump (commit `398e156`)

- `gui/src/registry/components.json`: `stream_version 0.7.0 → 1.1.0`, `schema_version 1.0 → 2.0`. Component bodies untouched (.components array length still 12).
- `gui/src/registry/__tests__/registry.test.ts`: assertions on lines 12 and 17 updated to match.

## Verification

| Check | Result |
|-------|--------|
| `node -e "require('./src/registry/components.json').stream_version"` | `1.1.0` |
| `node -e "require('./src/registry/components.json').schema_version"` | `2.0` |
| `node -e "require('./src/registry/components.json').components.length"` | `12` |
| `grep -c` for each of the 12 required new identifiers in types.ts | all ≥ 1 (see grep audit in commit message) |
| `npx vitest run src/registry/__tests__/registry.test.ts` | 14/14 pass |
| `npm test` (full vitest suite) | **232 pass, 17 todo, 1 skip — no regressions** |
| `npm run build` (tsc + vite) | **7 pre-existing errors (baseline), 0 new errors from Plan 01** |

## Deviations from Plan

### Rule 3 — Auto-fixed blocking issues

**1. [Rule 3 — Blocking] Widened `getPortTypeFromDef` return type for BCPort**
- **Found during:** Task 1 verification (`npm run build`).
- **Issue:** Extending `Port.type` to include `BCPort` (per D-14) broke `gui/src/lib/codeGenerator.ts:300` whose return type was the narrower `"FlowPort" | "ThermalPort" | undefined`.
- **Fix:** One-line widening to `"FlowPort" | "ThermalPort" | "BCPort" | undefined`. Justified directly by D-14.
- **Files modified:** `gui/src/lib/codeGenerator.ts`.
- **Commit:** `d8111a9`.

**2. [Rule 3 — Blocking] Non-null assertion on `port.side` in `StreamNode.tsx`**
- **Found during:** Task 1 verification.
- **Issue:** Making `Port.side` optional (per D-16 — autoflip ports leave it undefined) broke two existing `sideToPosition[port.side]` indexing sites in `StreamNode.tsx` (lines 72 and 87) with TS2538.
- **Fix:** Added `!` non-null assertions at both sites. Safe for the 12 current entries (all set `side` explicitly); Plans 02/03/04 will replace these with proper `default_axis`-aware Handle placement when v1.1 array ports land.
- **Files modified:** `gui/src/components/StreamNode.tsx`.
- **Commit:** `d8111a9`.

### Decisions

**Kept `ports` and `constructorModes` REQUIRED on `ComponentDefinition`** despite the plan saying "loosen to optional for Resource entries". Rationale:
- Plan 04 introduces the first Resource entry (`ReactivityController`). Until then, no JSON entry omits these fields, so the schema relaxation is premature.
- Making them optional now would force a cascade of non-null assertions across `StreamNode.tsx`, `CanvasPanel.tsx`, `useStore.ts`, `codeGenerator.ts`, `layers.ts`, `validation.ts`, `ParameterForm.tsx`, `SidebarPanel.tsx`, `registry.test.ts` — none of which are on Plan 01's touch surface. That cascade is Plan 04's natural scope.
- The schema is still expressive enough to land Plans 02/03 (which only modify existing canvas components — Channel, CHF, CAC, HD — all of which keep ports + constructorModes).

This is annotated in `types.ts` with `Plan 04 widens this when ReactivityController lands`.

## Deferred Issues

7 pre-existing TypeScript build errors (StreamNode `<Handle data=...>` typing post-`@xyflow/react` upgrade ×2; 5 unused-variable lints) — present on the `gui-redesign` working branch before Plan 61-01 started. Verified via `git stash && npm run build` from HEAD `67cafa7`. Logged to `.planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md` per the executor scope-boundary rule.

`npm test` (Vitest) is unaffected and passes 232/232 because it does not go through the `tsc` gate.

## Self-Check

```bash
[ -f gui/src/registry/types.ts ] && echo FOUND || echo MISSING        # FOUND
[ -f gui/src/registry/components.json ] && echo FOUND || echo MISSING # FOUND
[ -f .planning/phases/61-registry-audit-rewrite-for-v1-1/61-01-SUMMARY.md ] && echo FOUND || echo MISSING  # written by this commit
[ -f .planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md ] && echo FOUND || echo MISSING  # FOUND
git log --oneline | grep -q d8111a9 && echo FOUND || echo MISSING     # FOUND
git log --oneline | grep -q 398e156 && echo FOUND || echo MISSING     # FOUND
```

## Self-Check: PASSED

All claimed files exist on disk; both task commits (`d8111a9`, `398e156`) are present in the worktree branch history.
