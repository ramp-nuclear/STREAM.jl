# Phase 71: Validation framework - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-21
**Phase:** 71-validation-framework
**Areas discussed:** Panel + indicator surface; Validator registry API & file layout; ValidationResult target schema; Initial rule-set scope + existing-mechanism migration

---

## Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Panel + indicator surface | Where the panel lives + where the status indicator lives | ✓ |
| Validator registry API & file layout | Interface shape, registration, file layout, re-run triggers | ✓ |
| ValidationResult target schema | Tagged-targets array, fieldPath shape, array-field handling, edge targets | ✓ |
| Initial rule-set scope + existing-mechanism migration | All 8 rules vs subset; fate of validateTopology/errorNodeIds/ValidationDialog | ✓ |

**User's choice:** All four areas. The gray-area selection step ran second after a 6-option list initially failed (4-option limit on AskUserQuestion), so the picker-button-fix-UX area was folded out into Claude's discretion and "More questions" tails for each area covered any residual sub-questions.

---

## Area 1 — Panel + indicator surface

### Q1: Where does the validation panel live?

| Option | Description | Selected |
|--------|-------------|----------|
| New tab in BottomPanel | Add a Validation tab next to the existing Code tab. Reuses bottomPanelOpen / bottomPanelHeight + tabs shell. §3.9 says fixed location at the bottom — satisfied. | ✓ |
| Dedicated bottom strip | Separate always-visible strip below the canvas, parallel to BottomPanel. Lets the user view code AND validations simultaneously. Costs new layout chrome. | |
| Slide-in side panel | Right/left-side panel that slides in/out, like CodePreview. Breaks §3.9's bottom-of-GUI commitment. | |

**Notes:** Max code reuse + clean tab semantics for two coexisting bottom surfaces.

### Q2: VS-Code-style count indicator host

| Option | Description | Selected |
|--------|-------------|----------|
| Titlebar (Phase 67) | Embed chips into the existing CustomTitleBar.tsx. No new chrome but breaks user expectation of bottom-left placement. | |
| New statusbar strip | Add a thin ~22-24px statusbar strip under BottomPanel. Canonical VS-Code location; reusable surface for later phases. | ✓ |
| Both: titlebar + statusbar | Redundant. | |
| Tab badge only | Counts on the new tab label only. Contradicts §3.9's "VS-Code-style compact status-bar indicator." | |

**Notes:** Matches VS Code mental model that the §3.9 goal explicitly cites.

### Q3: Auto-focus behavior when errors first appear

| Option | Description | Selected |
|--------|-------------|----------|
| Pulse statusbar only | Chip pulses on count rising from 0→N; BottomPanel does NOT auto-open. User decides when to look. | ✓ |
| Auto-open panel on first error per session | Panel auto-opens on first 0→N rise. Better discoverability for new users; intrusive mid-edit. | |
| Auto-open on every export attempt with errors | Panel auto-opens at export gate only. | |

**Notes:** Least-invasive; trusts the user; matches IDE convention. The export gate (D-15/D-17) still auto-opens the panel.

### Q4: Validation tab empty state

| Option | Description | Selected |
|--------|-------------|----------|
| Always-visible "All clear" | Tab always present; body shows "No issues" empty state when count=0. Tab label has no badge when 0. | ✓ |
| Hide tab until first result | Tab only appears once first ValidationResult exists. | |
| Tab always visible, body auto-collapses when empty | Clicking the tab collapses BottomPanel automatically if count=0. | |

**Notes:** Stable chrome; engineering-tool seriousness; aligns with engineering-voice copy memory.

---

## Area 2 — Validator registry API & file layout

### Q1: Validator interface shape

| Option | Description | Selected |
|--------|-------------|----------|
| Object with metadata + pure run() | `{ id, severity, scope, description, run(snapshot) => ValidationResult[] }`; snapshot carries everything; no store import in rule files. Mirrors validateTopology. | ✓ |
| Bare function + sidecar metadata | Pure function exported separately from metadata. Splits the rule across two locations. | |
| Class-based | OOP overhead with no benefit; rules don't need lifecycle. | |

**Notes:** §3.9 names this shape almost verbatim ("name, severity, applicable scope, run function returning ValidationResults").

### Q2: Registration model

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit array in index.ts | Imports each rule + Validator[] array. Compile-time checked, greppable, no Vite magic. | ✓ |
| Vite import.meta.glob auto-discovery | Drop a file in rules/ folder; magic registration. Hidden coupling on file order/naming. | |
| Build-time codegen | Generator scans rules/ and emits manifest. Overkill at this scale. | |

**Notes:** Explicit > implicit; matches existing components.json convention.

### Q3: File layout

| Option | Description | Selected |
|--------|-------------|----------|
| One file per rule | `gui/src/lib/validation/rules/<name>.ts` for each rule; co-located test file. | ✓ |
| Grouped by domain | discretization.ts / topology.ts / hydraulics.ts (~3 files for 9 rules). | |
| Single validation.ts | Everything in one file; conflicts with pluggable framing. | |

**Notes:** Smallest blast radius per change; rules are independently pluggable.

### Q4: Re-run trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Run-all, debounced | On any mutation affecting nodes/edges/anchors/bcMode/resources, run ALL validators after ~150ms debounce. Simple, correct. | ✓ |
| Scope-tagged, run-affected | Validators declare scopes; only matching ones re-run. Matches §3.9's literal "Cached; re-run only what's affected." | |
| Subscribe-per-rule | Each validator subscribes to its inputs via zustand. Contradicts the pure-function shape. | |

**Notes:** Simplest thing that works at current scale; §3.9's caching is deferred as future work (scope metadata reserved for it).

---

## Area 3 — ValidationResult target schema

### Q1: Target shape

| Option | Description | Selected |
|--------|-------------|----------|
| Tagged targets array | Discriminated-union `{ kind: 'node' \| 'field' \| 'edge' \| 'port', ... }`; consumers filter for kinds they care about. | ✓ |
| Single primary target + secondary nodeIds | primary + relatedNodeIds + relatedEdgeIds. Awkward for symmetric mismatch rules. | |
| Free-form opaque payload | target: unknown + per-validator renderer. Abandons uniform-treatment. | |

**Notes:** Single result can light up multiple surfaces atomically; discriminated unions are well-supported by TS.

### Q2: fieldPath addressing

| Option | Description | Selected |
|--------|-------------|----------|
| Dot/bracket string, panel resolves | Strings like `'n'`, `'geom.L'`, `'T_wall_left[3]'`; panel filters by node + looks up via `data-field-path` attribute. | ✓ |
| Validator returns DOM ref/callback | Rejected — validator can't know about DOM. | |
| Registry of well-known field IDs | Pre-declared FieldId union. Too rigid for array fields. | |

**Notes:** Property panel doesn't need to know which validator emitted what; one shared resolver.

### Q3: Array-shaped fields (T_wall_left[1:n], q_left[1:n])

| Option | Description | Selected |
|--------|-------------|----------|
| Whole-array target | fieldPath = `'T_wall_left'`; row highlights regardless of which index. Description spells out offending indices. | ✓ |
| Per-index targeting | fieldPath = `'T_wall_left[3]'`; one result per offending index. | |
| Range target | Whole-array + extra `range: number[]` metadata. | |

**Notes:** Matches BCs-tab single-row rendering; precision carried in description.

### Q4: Edge-level rules' target set

| Option | Description | Selected |
|--------|-------------|----------|
| Edge + both endpoints | Port-type mismatch → edge + both ports. n-mismatch BC binding → edge + both n field targets. Dangling FlowPort → port target only. | ✓ |
| Edge-only target | Consumers chase down endpoints. Loses symmetric-highlight. | |
| Separate edgeResults[] | Two parallel arrays. Contradicts unified targets array. | |

**Notes:** Same targets array generalizes node-level and edge-level rules.

---

## Area 4 — Rule-set scope + existing-mechanism migration

### Q1: Rule scope in Phase 71

| Option | Description | Selected |
|--------|-------------|----------|
| All 8 in Phase 71 | z_N, length, n-match, required-conn, port-type, dangling, loop-closure, gravity-sum, geometry-consistency. Bigger phase but matches §3.9 verbatim. | ✓ |
| Per-node rules now, graph rules deferred | 7 of 8 simpler rules in 71; loop-closure + gravity-sum to 71.x. | |
| Framework + first 3 rules only | Registry + panel + statusbar + 3 most-different rules. Smallest landing, slowest value delivery. | |

**Notes:** Keeps §3.9's promise; planner adds `loopTraversal.ts` graph utility under `gui/src/lib/validation/`. Plus VALD-02/VALD-03 lift as `pressureBoundaryRequired` and `drivingElementRequired`.

### Q2: Fate of validateTopology / VALD-01..03

| Option | Description | Selected |
|--------|-------------|----------|
| Fold into registry as 3 validators | VALD-01 → danglingFlowPort; VALD-02 → pressureBoundaryRequired; VALD-03 → drivingElementRequired. validation.ts deleted. | ✓ |
| Keep validateTopology, layer registry on top | Two parallel mechanisms; violates no-back-compat memory. | |
| Drop VALD-01..03 entirely | Dangerous regression of system-level checks. | |

**Notes:** Field-helpers (validateInt, etc.) move to `gui/src/lib/validation/fields.ts`.

### Q3: ValidationDialog.tsx replacement

| Option | Description | Selected |
|--------|-------------|----------|
| Delete dialog — panel + toast | Pre-export runs validators; short toast on error, auto-open Validation tab, statusbar pulse. No modal. | ✓ |
| Keep dialog as export-gate | Modal + panel say the same thing; double-acknowledge. | |
| Silent disabled-button only | No modal, no toast; ambiguous for first-time users. | |

**Notes:** Consistent with panel-is-the-place UX; the export button is also disabled (with tooltip) when error count > 0.

### Q4: errorNodeIds: Set<string> fate

| Option | Description | Selected |
|--------|-------------|----------|
| Derive from validation results | Memoized selector over validationResults filtering severity=error + node/port-kind targets. StreamNode.tsx unchanged. | ✓ |
| Validators populate errorNodeIds imperatively | Dual-write; brittle. | |
| Keep errorNodeIds for ad-hoc errors | Two parallel mechanisms; violates no-back-compat memory. | |

**Notes:** Phase 63 connection-time hard-blocks reroute through the registry's portType rule (D-19); Phase 63's BCs-tab n-mismatch hint is superseded by the nMatch rule (D-20).

---

## Claude's Discretion

The following are left to the planner / UI-spec author within the constraints set by CONTEXT.md:

- Severity icon set and statusbar chip glyphs (Phase 72 sweeps visual treatment).
- Sort order within the panel (default: severity → validatorId; group-by-component is a future toggle).
- Statusbar height, font size, hover state (Phase 72 sweeps density).
- Toast library / mount point (sonner if not already present).
- Exact location to inject the `data-field-path` attribute (one shared field-render helper site).
- Empty-state copy ("No issues" or equivalent terse engineering voice).
- Pre-export disabled-button tooltip wording.
- Picker-button UX detail (lossless-sync = one-click; value-transfer-picker = radix Popover anchored to the panel entry vs full Dialog; planner picks Popover unless layout forces Dialog).

## Deferred Ideas

- Per-rule cache invalidation / incremental re-run — re-evaluate at hundreds of components.
- Per-rule enable/disable settings UI.
- Group-by-component toggle in the panel.
- Per-cell BC-vector targeting (needs new BCs-tab vector preview).
- "Fix all" batch remediation.
- Reverse-direction lint (parse hand-written .jl back to surface problems).
- Drag-from-panel "navigate to" affordance.
- Per-rule severity override (user-configurable).
- Validation history / time-travel.
- Cross-rule deduplication (panel renders one entry per result in v1).
