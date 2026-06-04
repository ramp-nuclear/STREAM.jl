# Phase 71: Validation framework - Context

**Gathered:** 2026-05-21
**Status:** Ready for planning

<domain>
## Phase Boundary

One unified, rule-pluggable validation framework that runs continuously on the
GUI model and surfaces every introspectable, physically- or structurally-wrong
condition through a uniform UX. Phase 71 ships:

- A **validator registry** with a single pure-function interface; one file per
  rule under `gui/src/lib/validation/rules/`, registered explicitly in
  `gui/src/lib/validation/index.ts`.
- **`ValidationResult` schema** with a tagged-targets array
  (`node` / `field` / `edge` / `port`) so a single result can light up the
  canvas red-ring, the property-panel red-highlight, an edge tint, and the
  panel-entry click-to-focus atomically.
- A **Validation tab in BottomPanel.tsx** alongside `Code` — the canonical
  surface for every result.
- A **new VS-Code-style statusbar strip** (~22-24px) under BottomPanel showing
  `⓭ N ⚠ N ⓘ N` chips. The strip is the always-visible discoverability surface.
- **Fix actions** on panel entries (lossless-sync / value-transfer-picker /
  navigation-only) per §3.9.
- **Export gating:** the pre-export hook runs the registry; if any
  `severity = error` is present, a short toast fires, the Validation tab
  auto-opens, the statusbar pulses, and emit is blocked. The Phase-39
  `ValidationDialog.tsx` modal is **retired**.
- **All 8 rules** from §3.9 in this phase: z_N match, length match, n-match
  (sources), required-connections, port-type match, dangling FlowPort, loop
  closure, gravity-sum-per-loop, geometry-consistency-across-shared-coupling.
- **Migration of pre-existing validation state:** `validateTopology()` +
  `errorNodeIds: Set<string>` + `validationResult: TopologyResult | null` +
  `ValidationDialog.tsx` are all replaced. VALD-01..03 become three registry
  validators. `errorNodeIds` becomes a memoized selector derived from the new
  `validationResults` slice. Phase 63's connection-time hard-blocks reroute
  through the registry as transient/synchronous rule emissions.

**Out of scope:**
- New rules beyond the §3.9 list (e.g., resource-name uniqueness, BC profile
  shape sanity) — captured as Deferred.
- Visual polish of the panel, the severity icon set, the statusbar typography,
  field-red-highlight token — Phase 72 design-system pass owns the colors,
  fonts, density.
- Per-rule disable/enable settings UI — Deferred.
- Caching / incremental re-run optimization — explicit deferral; \"run-all
  debounced ~150ms\" is the v1 contract.
- Reverse-direction lint (parsing hand-written `.jl` back into the model) —
  out of scope per §3.9.
- Bidirectional "fix from canvas right-click" remediation — context-menu
  "Show errors for this component" navigates to the panel, doesn't itself fix.

</domain>

<decisions>
## Implementation Decisions

### Panel + indicator surface

- **D-01:** **Validation panel** lives as a **new tab inside `BottomPanel.tsx`**
  alongside the existing `Code` tab. Reuses the `bottomPanelOpen` /
  `bottomPanelHeight` store slice and the tabs shell already there
  (`BottomPanel.tsx:108-168`). §3.9's "fixed location at the bottom of the GUI"
  is satisfied by the BottomPanel tab.
- **D-02:** **Status indicator** lives in a **new dedicated statusbar strip**
  (~22-24px high) anchored at the very bottom of the window, **under**
  `BottomPanel`. Chips: `⓭ N` (errors), `⚠ N` (warnings), `ⓘ N` (info). The
  strip is always visible (not collapsible) and is the always-on
  discoverability surface even when the BottomPanel is closed. The statusbar
  strip is **new chrome**; it does NOT live in the Phase-67 `CustomTitleBar`.
- **D-03:** **Auto-focus behavior:** the statusbar chip pulses when the error
  count rises from `0 → N` (a brief CSS animation; one pulse, not a continuous
  spinner). The `BottomPanel` does **NOT** auto-open. The pre-export gate
  (D-15) is the only path that auto-opens the panel.
- **D-04:** **Empty state:** the `Validation` tab is **always visible** in
  BottomPanel. When count = 0, the tab body shows a terse "No issues" empty
  state (engineering voice per memory `feedback_engineering_voice_copy.md`);
  the tab label has no badge.
- **D-05:** **Click handlers:**
  - Click a statusbar chip → open `BottomPanel`, switch to `Validation` tab,
    pre-filter by that severity.
  - Click a result entry → canvas pans to the affected nodes (ReactFlow
    `setCenter` on bbox of `kind === 'node' | 'port'` targets), a brief flash
    ring on the node, property panel opens to the offending field if there's
    exactly one `kind === 'field'` target.
  - Right-click on a node → context menu "Show errors for this component" →
    opens the panel, scrolls to entries whose targets reference this nodeId
    (power-user shortcut; not the primary path).

### Validator registry API & file layout

- **D-06:** **Validator interface shape** (pure-function-with-metadata):
  ```ts
  interface Validator {
    id: string;                      // stable identifier, e.g. 'z_n_match'
    severity: 'error' | 'warning' | 'info';
    description: string;             // human-readable rule name for the panel
    scope: ('nodes'|'edges'|'anchors'|'bcMode'|'resources')[];  // doc only in v1
    run(snapshot: ValidationSnapshot): ValidationResult[];
  }
  ```
  `ValidationSnapshot` carries everything any rule could read:
  `{ nodes, edges, anchors, bcMode, resources, getComponentDef }`. **Rule files
  MUST NOT import the store directly.** Pure-function contract preserves
  testability and mirrors the existing `validateTopology()` shape.
- **D-07:** **Registration:** explicit array in `gui/src/lib/validation/index.ts`:
  ```ts
  import { zNMatch } from './rules/zNMatch';
  import { lengthMatch } from './rules/lengthMatch';
  // ...
  export const validators: Validator[] = [
    zNMatch, lengthMatch, nMatch, portType,
    requiredConnections, danglingFlowPort,
    loopClosure, gravitySumPerLoop, geometryConsistency,
    pressureBoundaryRequired, drivingElementRequired,  // VALD-02, VALD-03
  ];
  ```
  Adding a rule = one import + one array push. No `import.meta.glob` magic.
- **D-08:** **File layout:** **one file per rule** under
  `gui/src/lib/validation/rules/<name>.ts`, with a co-located test file
  `gui/src/lib/validation/rules/__tests__/<name>.test.ts`. Adopt the existing
  vitest pattern used elsewhere in `gui/src/`.
- **D-09:** **Re-run policy:** **run-all, debounced ~150ms** on any store
  mutation affecting `nodes`, `edges`, `anchors`, `bcMode`, or `resources`.
  Implemented as a single zustand `subscribe` listener that calls
  `runValidators(snapshot)` and writes `validationResults` back to the store.
  Per-rule cache invalidation is **deferred** — §3.9's "Cached; re-run only
  what's affected" is acknowledged as future work; current model size makes
  full re-run sub-millisecond. The `scope` metadata in `Validator` is
  documentation-only for v1 and reserved for future targeted invalidation.
- **D-10:** **Runner location:** the runner lives in
  `gui/src/lib/validation/runner.ts`, decoupled from the store; the store
  imports it and wires the subscription. Mirrors `gui/src/lib/exportCode.ts`'s
  separation pattern.

### `ValidationResult` target schema

- **D-11:** **`ValidationResult` shape:**
  ```ts
  interface ValidationResult {
    id: string;                                    // stable per (validatorId, target hash) for dedup
    validatorId: string;
    severity: 'error' | 'warning' | 'info';
    description: string;                           // human-readable, names components + offending values
    targets: Target[];                             // see D-12
    fixAction?: FixAction;                         // see D-14
  }

  type Target =
    | { kind: 'node';  nodeId: string }
    | { kind: 'field'; nodeId: string; fieldPath: string }
    | { kind: 'edge';  edgeId: string }
    | { kind: 'port';  nodeId: string; portName: string };
  ```
  Each consumer (canvas red-ring, property-field highlight, panel entry,
  click-to-focus) filters for the `kind`s it handles. A single result can
  carry multiple targets, so e.g. a z_N mismatch lights up **both** node
  rings AND **both** `n` field highlights from one result.
- **D-12:** **`fieldPath`** is a dot/bracket-notation string into a
  component's data: `'n'`, `'geom.L'`, `'h_left'`, `'T_wall_left'`. The
  property panel subscribes to `validationResults`, filters by `kind ===
  'field'` matching the currently-open node, and looks up the rendered
  input element via a `data-field-path` HTML attribute that the property
  panel **adds on every renderable field** (planner: add the attribute to
  the existing field-render helper, do NOT per-field). Resolution lives in
  one place; rules don't know about DOM.
- **D-13:** **Array-shaped fields** (`T_wall_left[1:n]`, `q_left[1:n]`):
  whole-array target — `fieldPath = 'T_wall_left'`. The description carries
  the offending indices verbatim ("indices 3, 7 invalid"). No per-cell DOM
  highlight in v1; the BCs-tab field row is the highlight unit and matches
  Phase 63's existing single-row rendering.
- **D-14:** **Edge-level rules** emit edge + both endpoint targets:
  - Port-type mismatch → `[{kind:'edge'}, {kind:'port', src}, {kind:'port', tgt}]`
  - n-mismatch on a BC binding → `[{kind:'edge'}, {kind:'field', src, 'n'}, {kind:'field', tgt, 'n'}]`
  - Dangling FlowPort → `[{kind:'port', nodeId, portName}]` (no edge)
  Both endpoints highlight symmetrically without per-rule special-casing in
  consumers.

### Rule scope + existing-mechanism migration

- **D-15:** **All 8 rules from §3.9 ship in Phase 71**: z_N match, length match,
  n-match (sources), required-connections, port-type match, dangling FlowPort,
  loop closure, gravity-sum-per-loop, geometry-consistency-across-shared-coupling.
  Plus VALD-02 / VALD-03 lift as `pressureBoundaryRequired` and
  `drivingElementRequired` system-level validators (severity = error). The
  loop-closure + gravity-sum rules need a closed-hydraulic-loop traversal
  helper — the planner adds `gui/src/lib/validation/loopTraversal.ts`
  (graph utility, pure function, tested standalone).
- **D-16:** **`validateTopology()` is folded into the registry:**
  - VALD-01 ("every FlowPort connected") collapses INTO the new
    `danglingFlowPort` rule (same check, severity = error).
  - VALD-02 ("pressure boundary exists") → new validator
    `pressureBoundaryRequired` (system-level, severity = error).
  - VALD-03 ("driving element exists") → new validator
    `drivingElementRequired` (system-level, severity = error).
  - `gui/src/lib/validation.ts` is **deleted**. The new
    `gui/src/lib/validation/` directory replaces it. Field-level validators
    (`validateInt`, `validateReal`, `validatePositiveReal`,
    `validateJuliaIdentifier`) **remain** as plain helpers — move them to
    `gui/src/lib/validation/fields.ts` so the top-level name stays inside
    the new directory.
- **D-17:** **`ValidationDialog.tsx` is deleted.** The pre-export gate calls
  `runValidators(snapshot)` synchronously; if any error severity is present:
  - Short toast (≤2s): `"Export blocked: N validation errors. See Validation panel."`
  - `bottomPanelOpen` set to `true`; active tab set to `validation`.
  - Statusbar chip pulses.
  - Export aborts. **No modal.** The Validation panel is THE place per §3.9.
  - Export button in the chrome is disabled (with tooltip) when error count > 0
    — disabled-button is the primary signal; the toast is for users who got
    around the disabled state via menu/shortcut.
- **D-18:** **`errorNodeIds: Set<string>` becomes a memoized selector**
  derived from the new `validationResults` slice:
  `errorNodeIds = useMemo(() => new Set(
    validationResults
      .filter(r => r.severity === 'error')
      .flatMap(r => r.targets)
      .filter(t => t.kind === 'node' || t.kind === 'port')
      .map(t => t.nodeId)
  ), [validationResults])`. `StreamNode.tsx`'s existing red-ring consumption
  is unchanged — it still subscribes to `errorNodeIds`. One source of truth,
  zero UX regression.
- **D-19:** **Phase 63 connection-time hard-blocks** (port-type mismatch and
  BC-binding type mismatch — currently refuse the connection synchronously
  with a red toast) reroute through the registry. The `portType` validator
  becomes the single source of truth for the rule. The connection handler
  consults the validator on `onConnect` (one-shot, not via debounced runner)
  for the would-be edge and refuses if `severity === 'error'`. Same hard-block
  behavior, single rule definition.
- **D-20:** **Phase 63's BCs-tab n-mismatch red-ring + red-text hint** is
  superseded by the new `nMatch` validator's emitted `ValidationResult`. The
  ad-hoc red-text hint in the BCs-tab field is replaced by the registry-driven
  red highlight (D-12). Phase 63's hand-written check is removed.

### Claude's Discretion

- **Severity icon set + chip glyphs:** planner picks v1 icons (lucide-react
  is already in the project). Phase 72 finalizes the visual treatment.
- **Sort order within the panel:** default by severity (error → warning →
  info) then by validatorId. Group-by-component is a future toggle.
- **Statusbar height (22-24px), font size, hover-state:** planner picks
  reasonable values; Phase 72 sweeps them.
- **Toast library / mount point:** planner picks (use whatever is already in
  the project for transient notifications; if nothing, add `sonner` per the
  existing shadcn ecosystem).
- **`data-field-path` attribute injection site:** planner finds the smallest
  common ancestor in the property-panel field-render helper(s) and adds the
  attribute once.
- **Empty-state copy ("No issues"):** planner picks the exact words within
  the engineering-voice constraint.
- **Pre-export disabled-button tooltip wording:** planner picks; "Resolve N
  validation errors first" is the baseline.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked design decisions
- `.planning/notes/gui-redesign-design-decisions.md` §3.9 (Validation Framework) — locks the architecture, severity taxonomy, panel UX, action-button taxonomy, initial rule set, soft-warn-at-connect contract, and gates-code-gen-export commitment. **THE upstream contract.**
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 (Design system framing) — Phase 72 will sweep Phase 71's visual surfaces; this phase delivers structure, NOT final visual polish.
- `.planning/notes/gui-redesign-design-decisions.md` §3.11 (BCs tab / connection-time UX) — locks the soft-warn-at-connect semantics; the `nMatch` validator must produce results that match what Phase 63 already paints (without Phase 63's ad-hoc red-text).
- `.planning/notes/gui-redesign-design-decisions.md` §4 (Cross-Cutting Invariants) — "No-back-compat during heavy dev" applies here: VALD-01..03 and ValidationDialog are deleted, not deprecated.

### Roadmap & milestone
- `.planning/ROADMAP.md` §Phase 71 — phase goal + the §3.9 pointer.
- `.planning/STATE.md` — v1.2 active milestone status.

### Codebase landmarks (must read before planning)
- `gui/src/lib/validation.ts` — Phase 39 `validateTopology(nodes, edges, anchors, getComponentDef)` + `TopologyResult { valid, nodeErrors, systemErrors }` + field-helpers (`validateInt`, `validateReal`, `validatePositiveReal`, `validateJuliaIdentifier`). Source of VALD-01..03 logic to fold into the registry; the field-helpers move to `gui/src/lib/validation/fields.ts`.
- `gui/src/store/useStore.ts:190-205` — `bottomPanelOpen`, `bottomPanelHeight`, `errorNodeIds: Set<string>`, `validationResult: TopologyResult | null`, `validateAndGate()`, `clearValidation()`. These are the slices to refactor: `errorNodeIds` becomes derived; `validationResult` is replaced by `validationResults: ValidationResult[]`.
- `gui/src/store/useStore.ts:1339-1361, 1876-onward` — mutation-time interaction with `errorNodeIds` (Phase 63 hard-block writes) and `validateAndGate` implementation; both refactored under D-18 and D-19.
- `gui/src/lib/exportCode.ts` — `validateAndGate()` consumer at export time. Refactored to call `runValidators()` and apply D-17's gate UX.
- `gui/src/components/ValidationDialog.tsx` — **deleted** in this phase (D-17).
- `gui/src/components/BottomPanel.tsx:108-168` — host of the new `Validation` tab; tabs shell already wired for tab-pair UX.
- `gui/src/components/CustomTitleBar.tsx` (Phase 67) — NOT the host of the statusbar indicator; documented to set boundary expectations.
- `gui/src/components/StreamNode.tsx:17, 33, 57` — red-ring consumer of `errorNodeIds`; remains unchanged at the contract level under D-18 (input still a `Set<string>` of nodeIds).
- `gui/src/lib/selectors/nodeErrors.ts` and `gui/src/lib/selectors/topologyHints.ts` — Phase 63 per-node selectors. Either re-expressed in terms of `validationResults` or retired if D-18's derived-selector subsumes them. Planner decides on a per-selector basis.
- `gui/src/lib/bcMode.ts` and `gui/src/lib/codeGenerator.ts` — BC mode state shape (consumed by the `nMatch` validator); pre-export gate hooked here.
- `gui/src/registry/components.json` — component-port definitions consumed by the `portType` and `requiredConnections` validators.

### Prior CONTEXTs (decision continuity)
- `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md` §"Out of scope" — Phase 63 explicitly defers the inline-fix-action and the formal registry to Phase 71; this phase is the receipt.
- `.planning/phases/68-layers-system-overhaul/68-CONTEXT.md` — `layer` field on components is preserved through Phase 71; no rule touches it in v1.
- `.planning/phases/65-interaction-model-overhaul/65-CONTEXT.md` — onConnect hard-block contract (D-19 reroutes it through the registry).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`BottomPanel.tsx` tabs shell** — already mounts a `Tabs` primitive with one
  `code` tab; the `Validation` tab plugs in as a sibling `TabsTrigger` +
  `TabsContent`. No new chrome primitive needed.
- **`bottomPanelOpen` / `bottomPanelHeight` store slice** — already drives
  collapse and resize; the new tab inherits this behavior.
- **`errorNodeIds: Set<string>` consumer in `StreamNode.tsx`** — keeps the same
  shape under D-18, so the red-ring UX is untouched at the rendering layer.
- **`validateTopology()` snapshot shape** — `(nodes, edges, anchors,
  getComponentDef)` already mirrors what `ValidationSnapshot` will carry;
  D-06 extends with `bcMode` and `resources`.
- **shadcn `Tooltip`, `ContextMenu`, `Toast` (or `sonner`)** — already used
  by Phase 65 / 67; reusable for the panel entries' hover affordances and
  the export-gate toast.
- **Phase 39's vitest topology tests** (`gui/src/lib/__tests__/validation.test.ts`
  if present) — pattern reused for per-rule tests under
  `gui/src/lib/validation/rules/__tests__/`.

### Established Patterns
- **Pure-function validators with snapshot input** — `validateTopology()`
  already does this. D-06 generalizes the same contract.
- **Single-source-of-truth zustand slice** — `errorNodeIds` is currently
  written ad-hoc from multiple call sites (e.g., Phase 63 connection-time
  hard-block at `useStore.ts:1339-1361`); D-18 collapses to one derived
  selector. Mirrors the "one slice, many subscribers" pattern already
  established by `bcMode`, `presets`, and `hoveredSourceIds`.
- **Debounced subscription to store mutations** — Phase 70's preset watcher
  uses ~200ms debounce; D-09's ~150ms validator debounce is the same pattern.
- **`data-*` HTML attribute as cross-cutting bridge** — D-12's
  `data-field-path` follows the same idiom as Phase 66's
  `data-source-id` linking sub-block to canvas node.
- **One file per registered thing** — registry/components.json (per-component
  metadata), `gui/src/registry/types.ts` (per-component-port type) — the
  one-file-per-rule layout (D-08) extends the same locality rule to
  validators.
- **No back-compat hacks during heavy dev** (memory
  `feedback_no_back_compat_during_heavy_dev.md`) — VALD-01..03 fold, not
  coexist; `ValidationDialog` deletes, not deprecates.

### Integration Points
- **`BottomPanel.tsx`** gains a second `TabsTrigger`/`TabsContent` pair.
- **`App.tsx`** mounts the new statusbar strip below `BottomPanel` and above
  any existing footer chrome (none currently).
- **`useStore.ts`** gains `validationResults: ValidationResult[]` slice +
  `runValidators()` action; `errorNodeIds` becomes a memoized derivation
  (selector hook); `validationResult` (singular) and `validateAndGate` are
  retired.
- **`exportCode.ts`** swaps `validateAndGate()` for `runValidators(snapshot)`
  + D-17's gate UX.
- **`useStore.ts` onConnect handler** consults `portType` validator before
  creating an edge per D-19 — single-rule hard-block.
- **Property-panel field-render helper** gains a `data-field-path` attribute
  injection point per D-12 (planner: one shared site).
- **`StreamNode.tsx`** unchanged at the contract level; the source of
  `errorNodeIds` is the only thing that moves.
- **`tauri.conf.json`** — no new permissions; this phase is pure
  TypeScript/React.

</code_context>

<specifics>
## Specific Ideas

- **"VS-Code-style" is taken literally** — the statusbar strip is the
  canonical VS Code mental model (bottom-edge, always-visible, count chips
  with icons). Embedding the chips into the Phase 67 titlebar was considered
  and rejected because it breaks the convention every engineering-tool user
  brings to the app. Phase 72 will polish the strip's typography and
  density; the strip itself is a Phase 71 deliverable.
- **Panel-is-THE-place** is a constitutional decision for v1.2 — the
  ValidationDialog modal, the canvas right-click "fix" actions, and the
  inline property-panel fix buttons were ALL rejected in §3.9 in favor of
  the single Validation panel surface. Phase 71 implements this faithfully;
  navigation aids (statusbar chip, canvas red-rings, right-click "Show
  errors") all funnel TO the panel, not parallel UI.
- **Hard-block reserved for invariants that cannot produce a meaningful
  model** — §3.9 + §3.11 locked: port-type mismatch + BC-binding type
  mismatch are connection-time hard-blocks. Everything else is soft-warn
  (allowed connection, panel entry). D-19 reroutes the existing Phase 63
  hard-blocks through the registry without changing this behavior.
- **One-file-per-rule + explicit array** — both the file layout (D-08) and
  registration (D-07) optimize for the "delete a rule cleanly" property.
  Adding/removing/disabling a rule is a single PR touching at most three
  files: rule, test, registry array.
- **Pure-function rules, no store imports** — D-06 is non-negotiable; rule
  files import only types and the `ValidationSnapshot` shape. Snapshot is
  built once per debounced tick by the runner. Tests pass synthetic
  snapshots; no store mocking required.

</specifics>

<deferred>
## Deferred Ideas

- **Per-rule cache invalidation / incremental re-run** — D-09 explicitly
  defers §3.9's "Cached; re-run only what's affected" optimization.
  Re-evaluate if a model with hundreds of components shows perceptible
  validator-loop latency. Reserve the `scope: (...)[]` metadata on
  `Validator` for that future expansion.
- **Per-rule enable/disable settings UI** — power users may want to silence
  specific warnings. Out of scope for v1; the registry array is the only
  toggle point today (comment out a line).
- **Group-by-component in the panel** — default sort is severity-then-rule
  in v1. A "group by component" toggle is a small follow-up if users
  request it.
- **Per-cell BC-vector targeting** — D-13 chose whole-array targeting.
  Per-cell highlight (`T_wall_left[3]`) needs a BCs-tab vector preview UI
  that doesn't exist yet; add when/if the BCs-tab grows that surface.
- **"Fix all" batch remediation** — one-click "apply every lossless-sync
  fix" button. Considered; deferred until usage shows the friction.
- **Reverse-direction lint** — parsing hand-written `.jl` back to surface
  problems. Out of scope per §3.9.
- **Drag-from-panel "navigate to" affordance** — dragging a result entry
  onto the canvas could open a fix wizard. Deferred; click-to-focus is the
  v1 navigation contract.
- **Per-rule severity override** (user toggling `loopClosure` from error to
  warning). Deferred; the registry's `severity` field is the only setting.
- **Validation history / time-travel** — show resolved issues over the
  session. Deferred.
- **Cross-rule deduplication** — two rules flagging the same node with
  related descriptions; the `id` field (D-11) is stable enough for de-dupe
  but the panel renders one entry per result in v1.

</deferred>

---

*Phase: 71-validation-framework*
*Context gathered: 2026-05-21*
