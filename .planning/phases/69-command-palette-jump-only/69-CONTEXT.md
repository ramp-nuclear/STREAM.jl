# Phase 69: Command palette (jump-only) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship a `Ctrl+P` fuzzy-search palette restricted to navigation — jump-to-component-by-name and jump-to-resource. The trigger, search pool, result-row shape, and per-kind on-select actions are locked by Section 3.7 of `.planning/notes/gui-redesign-design-decisions.md`; this phase decides HOW to implement them.

**In scope:**
- New `Ctrl+P` global shortcut registered alongside the existing `App.tsx` shortcut block (~lines 207–250).
- Top-anchored overlay palette UI (see D-02) using the `cmdk` library, dropped in as a new `gui/src/components/ui/command.tsx` shadcn-style primitive.
- Search pool unioned from: (a) all component instance names from `useStore.nodes[]`; (b) all Resource names across the four categories owned by the Resources tree — Geometries, Power Shapes, Fluids, Model Options children.
- Result rows: kind icon + name + (components only) component type label, with cmdk's built-in matched-character highlighting.
- On-select actions per Section 3.7:
  - **Component** → auto-enable any off layer it belongs to (D-03), `setCenter`+zoom-floor pan (D-04), select the node (sets `selectedNodeId`, opens property panel).
  - **Resource** → expand its category in the Resources tree, set `selectedResourceId`, open property panel.
  - **Model Options child** → open the Model Options editor focused on that child.
- Off-layer match handling: items remain visible in results with an inline "Hydraulic off → will enable" hint; layer is auto-enabled silently on select (D-03).
- ESC dismisses the palette (Section 3.8 universal rule).

**Out of scope (per Section 3.7 + scope discipline):**
- Action invocation ("Add Pump", "Save", "Toggle theme") — explicit deferral in Section 3.7.
- File search, recent-projects search, fuzzy search across help docs.
- Global validation panel integration / showing validation results inline in palette.
- Visual polish beyond what `cmdk` + existing radix/shadcn primitives already give.
- Any new `Ctrl+Shift+P`/`Ctrl+K` shortcuts — single `Ctrl+P` only.

</domain>

<decisions>
## Implementation Decisions

### Library and matching

- **D-01:** **`cmdk` is the chosen palette library**, subject to a dependency audit. Audit task is the **first task of the phase** before any wiring code lands. Audit checks: published source matches GitHub source, maintainer activity (paco/Vercel-backed), recent commit history for anything anomalous, transitive deps, install size. If audit produces a confirmed security concern, fall back to Fuse.js + custom UI on radix Dialog (do NOT silently swap to hand-rolled). Rationale: `feedback_dep_security_audit` memory.

### Visual surface

- **D-02:** **Top-anchored overlay**, VS Code / Linear / Notion / Discord style. Anchored ~80px from the top of the viewport, width ~640px, internal scroll at ~480px max-height. Subtle dimmed backdrop with focus-trap on. ESC dismisses, click-outside dismisses. The cmdk parts (`Command.Root`, `Command.Input`, `Command.List`, `Command.Group`, `Command.Item`) mount inside a radix `Dialog.Portal` configured for top-anchor positioning (not `Dialog`'s default centered layout). Section 3.7 explicitly cites these four apps as the reference style; the choice is to match them.

### Off-layer (Phase 68 interaction) match handling

- **D-03:** **Forgiving / auto-enable** — items on currently-off layers appear in results normally. Each such row carries a small inline hint chip (e.g. `Hydraulic off — will enable`) so the side-effect isn't invisible. On select, the relevant layer(s) are toggled on before the pan/select runs. Mirrors Phase 68's "layer-aware connect auto-enables rather than blocks" philosophy and keeps the tool coherent. This is especially important in Hide mode where the user can't visually locate the component and is relying on the palette as a recovery mechanism.

### Pan / zoom focus behavior (component jumps)

- **D-04:** **`setCenter` + zoom floor.** On component select: `setCenter(node.x, node.y, { zoom: max(currentZoom, ZOOM_MIN_LEGIBLE), duration: 250 })`. Preserves the user's chosen zoom unless they're zoomed so far out that the node label wouldn't be legible — then zooms in to the legibility threshold. Selection ring confirms target. The exact `ZOOM_MIN_LEGIBLE` value is a tuning parameter for the executor to pick (likely 0.6–0.8 based on existing node label sizing).

### Claude's Discretion

The following weren't worth a question; flagging them so the planner knows they're not under-specified:

- **Empty-query state:** when the user opens the palette with no input, show all items grouped by kind (Components / Geometries / Power Shapes / Fluids / Model Options) so the palette also serves as a browse surface. As soon as the user types, collapse to a flat fuzzy-ranked list. Both modes are native cmdk capabilities.
- **Result grouping with typed input:** flat fuzzy-ranked list (no group headers), kind icon inline per row, matched-char highlighting on.
- **Max results shown with typed input:** ~50 (internal scroll handles the rest); avoids palette becoming a giant scrollable wall when the user types a single character.
- **Resource navigator focus** — likely needs a small store action like `expandResourceCategoryAndSelect(uuid)` that ensures the right `ResourceGroupHeader` is expanded before setting `selectedResourceId`. Planner to decide whether this goes in the store or is composed at the call site.
- **Bottom-panel status bar palette trigger button:** none. Section 3.7 says "the palette is Ctrl+P-only" (see also `.planning/notes/gui-redesign-design-decisions.md:567`). Do not add a button.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract (load-bearing)

- `.planning/notes/gui-redesign-design-decisions.md` §3.7 — Command Palette — Jump-Only. The full UX lock: trigger, search pool, result rendering, per-kind actions, out-of-scope items. Read this before doing anything else.
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — Design System / Interaction Contract. ESC-cancels-everything rule, predictable-defaults rule, no-silent-state-changes rule (relevant to D-03's inline hint chip).

### Roadmap entry

- `.planning/ROADMAP.md` §Phase 69 (lines 262–266) — goal statement + canonical-decisions pointer to §3.7.

### Phase 68 — layer system (D-03 depends on this)

- `.planning/phases/68-layers-system-overhaul/68-CONTEXT.md` — four-layer taxonomy, dual-layer visibility rule, off-layer locking semantics. D-03 mirrors the layer-aware-connect philosophy from this phase.

### Phase 62 — Resources panel (search pool source)

- `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` — Resources tree architecture, category structure (Geometries / Power Shapes / Fluids / Model Options), `selectedResourceId` selection model.

### Source files the planner will touch

- `gui/src/App.tsx` ~lines 207–250 — global shortcut block; `Ctrl+P` lands here.
- `gui/src/store/useStore.ts` — `nodes`, `selectedNodeId`, `selectedResourceId`, layer state slice; will need a `jumpToComponent(id)` / `jumpToResource(uuid)` pair (or similar) plus possibly a `setLayerEnabled` mutation if not already exported.
- `gui/src/components/resources/ResourcesTreePanel.tsx` — needs expand-and-select capability for jump-to-resource.
- `gui/src/components/ui/dialog.tsx` — radix Dialog primitive to portal cmdk into.
- `gui/package.json` — new dep: `cmdk` (subject to D-01 audit).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **radix Dialog primitive** (`gui/src/components/ui/dialog.tsx`) — focus-trap, ESC, portal, backdrop already wired. Re-used as the container; only the positioning class needs override for top-anchor.
- **Global shortcut wiring pattern** (`gui/src/App.tsx` ~207–250) — established `ctrlKey || metaKey` + `key === "x"` pattern with `e.preventDefault()`. `Ctrl+P` slot is unused.
- **`useReactFlow().setCenter` / `fitView`** (used in `gui/src/components/canvasMenus/FitViewButton.tsx`) — the pan/zoom primitive D-04 will call.
- **Store selection mutations** — `selectedNodeId` and `selectedResourceId` already drive the property panel; setting them is sufficient to "open property panel" per Section 3.7.
- **Resources tree categories** (`gui/src/components/resources/ResourcesTreePanel.tsx`) — Geometries / Power Shapes / Fluids each have a `ResourceGroupHeader` with `onAdd` + entries; Model Options is a singleton branch.

### Established Patterns

- **shadcn primitives live in `gui/src/components/ui/`** — `cmdk` integration follows the official shadcn `command.tsx` shape (wraps cmdk primitives with Tailwind classes). Drop the file there.
- **Global shortcuts open Dialogs**, not floating elements (see existing Settings / About / UnsavedChanges dialogs). Palette inherits the pattern.
- **`Esc` cancels in every panel** (Section 3.8). cmdk + radix Dialog deliver this for free; do not override.
- **No new top-level state slices for transient UI** — palette open/closed is local component state, not zustand. Matches how dialogs are managed today.

### Integration Points

- Shortcut handler in `App.tsx` toggles a local `paletteOpen` state on the rendered `<CommandPalette />`.
- `CommandPalette` reads `nodes` and the four resource slices from `useStore` directly (selectors); no new store wiring required for the *search pool*.
- For jump actions, the palette dispatches store mutations: `setSelectedNodeId(id)` or `setSelectedResourceId(uuid)`, plus layer toggles (D-03) and `setCenter` (D-04).
- The "expand-category-and-select-resource" jump may need a tiny new store action or a ref-based call into `ResourcesTreePanel` — planner to decide.

</code_context>

<specifics>
## Specific Ideas

- Section 3.7 explicitly names **Linear, VS Code, Notion, Discord** as the reference style — D-02 (top-anchored overlay) is the direct codification of that pointer.
- The "killer use case" framing from Section 3.7 is: a reactor model with 10+ named components like `top_pump`, `decay_loop_inlet`, `heated_channel` becomes hard to navigate visually. The palette must feel **fast** — sub-100ms open, no perceptible search lag for any plausible model size (< 500 items total).
- `feedback_dep_security_audit` makes D-01's audit step non-optional. The audit produces an artifact (e.g. one-page `69-CMDK-AUDIT.md` or section in the first plan's SUMMARY) recording what was checked and the verdict.

</specifics>

<deferred>
## Deferred Ideas

- **Full action-invocation palette** (VS Code-style "Save", "Toggle theme", "Add Pump", etc.) — Section 3.7 explicitly defers. Reconsider as later polish; not a v1.x milestone item right now.
- **File search / recent projects** — out of scope per Section 3.7.
- **Fuzzy search across help docs** — out of scope per Section 3.7.
- **Validation-aware results** (e.g. highlight components with validation errors in palette results) — belongs with Phase 71 Validation framework once that ships.
- **Status-bar trigger button for palette** — explicitly rejected by §3.7 ("palette is Ctrl+P-only"). Mentioned here so it doesn't get re-proposed.

### Reviewed Todos (not folded)

- `gui-visual-design-pass.md` — general visual polish; belongs to Phase 72 (design system).
- `2026-05-16-phase72-handle-port-visual-rework.md` — port handle restyle; belongs to Phase 72.
- `codegen-resource-naming-dedup.md` — codegen power-shape naming; independent codegen fix, unrelated to navigation.
- `panel-resize-overflow-bounds.md` — panel resize bounds bug; independent layout fix, unrelated to navigation.

</deferred>

---

*Phase: 69-command-palette-jump-only*
*Context gathered: 2026-05-18*
