# Phase 65: Interaction model overhaul - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewire the canvas interaction model from v0.8's ReactFlow defaults to the drawio convention codified in §3.5 of the GUI redesign decisions doc. Specifically:

- **Selection / pan / context menu:** left-click empty drag = marquee selection; left-click on a node/edge = select; left-drag selected = move; right-click drag = pan; right-click no-drag = context menu; Del/Backspace = delete selected nodes AND/OR edges; Esc = clear selection.
- **Context menus:** node menu (Delete, Duplicate, Rename, Show generated Julia code, Show errors); edge menu (Delete, Show errors); canvas menu (Paste, Auto-Layout (future, grayed-out), Add Component › submenu).
- **Edge deletion:** Del/Backspace key path AND right-click → Delete (closes v0.8 user-list item #2).
- **Copy / cut / paste / duplicate:** Ctrl+C/X/V/D with smart-parse-and-increment naming using **lowest-free** semantics, internal-edge-only inclusion, +20px paste offset, resource references preserved verbatim.
- **Reset-to-empty rule:** unified field reset behavior across Properties / BCs / Resources tabs (cleared field → registry default applied; "required" error only fires when there is no usable default).
- **Snap-to-grid toggle:** canvas-overlay button surface in v1.2 (no Settings dialog yet); 16px fixed grid; snap-on-drag-and-drop via ReactFlow's `snapToGrid` + `snapGrid` props; OFF by default; persisted per-project in `.scp` layout block.
- **AutoRecover sidecar snapshot:** debounced-on-dirty (~2s) write of full `.scp` content to `appDataDir/STREAM-Composer/autorecover/<basename>.scp.autosave` (or `untitled-<uuid>.scp.autosave` for never-saved projects); clean-shutdown lockfile detects crash on next launch; blocking modal restore prompt before workspace loads.
- **Naming retrofit:** unify the toolbox-drop naming algorithm (`getNextInstanceName`) onto the same lowest-free semantics that paste and Phase 62 resource creation use; drop the module-level `instanceCounters` variable to eliminate hidden state desync after undo/load.

**In scope (this phase only):** the eight bullets above plus the right-click pan-vs-menu disambiguation logic (5px movement threshold).

**Out of scope:**
- The Settings dialog itself (Phase 67/72) — Phase 65 only ships the canvas-overlay snap-to-grid button and persists the boolean.
- The View menu / menubar (Phase 67 custom titlebar).
- Visual-design polish of context menus / overlay button (Phase 71/72 design system).
- Right-click context menus on side-panel rows (BC rows, Resource rows) — flagged but deferred from Phase 63.1.
- Auto-Layout (full-graph reflow) — stubbed as grayed-out menu item only.
- Pluggable validation framework (Phase 71) — "Show errors" menu items hidden until a validator surface exists.
- Cross-app clipboard interop (drawio etc.) — JSON shape is internal; door is open but not in scope.

</domain>

<decisions>
## Implementation Decisions

### AutoRecover mechanics

- **D-01:** Snapshot cadence is **debounced on dirty change** (~2s after the last edit while `isDirty=true`). No fixed timer. Skipped if a real Save is in flight on the same tick.
- **D-02:** Crash detection is **clean-shutdown marker file**: at startup write `appDataDir/STREAM-Composer/autorecover/running.lock` containing the PID and `started_at`; on graceful close, delete it. On next launch, if the lockfile exists AND the recorded PID is dead (or absent), the previous run crashed → trigger restore prompt. PID-alive check rules out the rare two-instances-open false positive.
- **D-03:** Restore UX is a **blocking modal dialog** rendered before the workspace finishes loading. Body: "Recover unsaved work from `<timestamp>` in `<project name or 'Untitled'>`?" Buttons: `[Recover]` `[Discard]`. Decision happens before any other interaction so it cannot be accidentally dismissed.
- **D-04:** Untitled-project policy: **always snapshot** with a synthetic name `untitled-<uuid>.scp.autosave`. Restore prompt labels them "Unsaved project from `<time>`." After Recover, the project is in-memory unsaved — user must explicitly Save As to make it permanent.
- **D-05:** Sidecar storage location is **`appDataDir/STREAM-Composer/autorecover/`** (Tauri `appDataDir()` — per-OS-correct: `%APPDATA%` / `~/.local/share` / `~/Library/Application Support`). Survives reboots; scoped per app; easy to enumerate at launch sweep. Note: this overrides the roadmap text's "OS temp dir" wording — `tempDir()` is too transient for crash-across-reboot recovery.
- **D-06:** Sidecar payload is the **full `.scp` content** — bit-identical to what `Save` would write (layout block, activeLeftTab, layer view, all of it). Reuses `projectIO.serialize` / `deserialize` end-to-end. No custom code path → no schema-drift risk.

### Snap-to-grid surfacing

- **D-07:** Toggle UI surface in v1.2 is a **canvas-overlay button** added to the existing top-right Controls/MiniMap stack on the canvas. The Settings dialog wiring is deferred — Phase 67/72 will surface the same toggle in the Settings dialog when that dialog is built.
- **D-08:** Grid step size is **16px fixed**. Matches ReactFlow's existing Background `gap=16` so snapped layouts visibly align with the dotted background.
- **D-09:** Snapping uses **ReactFlow's built-in `snapToGrid` + `snapGrid={[16, 16]}` props** — snaps live during drag AND on drop. Identical surface for toolbox-drop placement (drop coordinates are also quantized).
- **D-10:** Default state is **OFF** for new projects. Persisted per-project in the `.scp` layout block (sets `isDirty: true` on toggle so the change is captured by save).

### Context menu component & disambiguation

- **D-11:** Context menus use the **shadcn/Radix `ContextMenu` component** already in the repo (`gui/src/components/ui/context-menu.tsx`, same one Phase 62 uses for resource trees). Wrap nodes/edges with `<ContextMenuTrigger>`. For the canvas (empty-pane) right-click, ReactFlow's `onPaneContextMenu` triggers a custom-positioned shadcn `Popover` rendering the same `ContextMenu` content. Keeps look-and-feel consistent with the rest of the app and gets focus trap, keyboard nav, edge-collision handling, and dark-mode styling for free.
- **D-12:** Right-drag-pan vs right-click-menu disambiguation uses a **5px Manhattan-distance + 250ms time threshold**: track `mousedown` coords on right-button; if `mouseup` lands within 5px AND under 250ms, fire the context menu. Otherwise it was a pan and the menu is suppressed. Tolerates micro-jitter without over-suppressing intentional short pans.
- **D-13:** Mac ctrl-click handling: **inherit OS native behavior — do not intercept**. The browser already converts ctrl-click to a right-click event; context menu fires normally. Trackpad pan gesture is two-finger, not ctrl-click — no conflict.
- **D-14:** Action scope matches **§3.5 spec verbatim** with stub-or-grayed for items whose backend is not yet built:
  - Node menu: Delete, Duplicate, Rename, Show generated Julia code, Show errors.
  - Edge menu: Delete, Show errors.
  - Canvas menu: Paste, Auto-Layout (grayed-out — explicit "(future)" suffix), Add Component › (submenu mirroring the toolbox).
  - "Show errors" items are **hidden** until Phase 71 validation has fired for that node/edge — they don't render as grayed-out, they simply don't appear.
  - "Show generated Julia code" jumps to the Code preview panel and scrolls to the section for that component (relies on Phase 66 structured `CodeSection[]` if available; falls back to "open code panel and select all" if Phase 66 not yet done).

### Clipboard scope & naming retrofit

- **D-15:** Clipboard payload writes to the **OS clipboard via `navigator.clipboard.writeText` with a JSON string**. Cross-window paste between two STREAM Composer windows works. Tauri's webview supports the Clipboard API natively — no extra plugin. Reads use `navigator.clipboard.readText` and JSON.parse with try/catch (silently no-op if the clipboard text isn't a valid Composer payload).
- **D-16:** Ctrl+D (Duplicate) uses a **separate code path that does not touch the OS clipboard** — serialize+deserialize the selection in-memory with new UUIDs and a +20px offset. Leaves whatever the user had on the clipboard via Ctrl+C intact. The §3.5 wording "copy + paste at offset, single shortcut" is functional, not literal.
- **D-17:** Toolbox-drop naming is **retrofitted to lowest-free semantics**, replacing `getNextInstanceName`'s "next-after-highest" module-level counter. The new function scans the current store state for existing instance names matching `<componentId>_<digits>` and returns the lowest free integer suffix — mirroring `nextResourceName` from Phase 62 (D-19 of `62-CONTEXT.md`).
- **D-18:** The module-level `instanceCounters` variable in `useStore.ts` is **deleted entirely**. Recompute from current store state on every name request. Eliminates hidden-state desync bugs after undo/redo (counter doesn't decrement on undo) and after `loadProject` (counter is per-session, doesn't reset to loaded values).
- **D-19:** Paste behavior matches §3.5 verbatim: component types preserved as-is; resource references kept verbatim; internal edges (both endpoints inside selection) included; external edges (one endpoint outside) **silently dropped, no warning toast**. Spec is the contract.

### Claude's Discretion

- File layout for new modules — e.g. `gui/src/lib/clipboard.ts`, `gui/src/lib/autoRecover.ts`, `gui/src/lib/contextMenu/{NodeMenu,EdgeMenu,CanvasMenu}.tsx` — planner picks.
- Exact wiring of the right-click 5px/250ms threshold — could live as a custom hook (`useRightClickContextMenu`) on `CanvasPanel`, or as a thin handler. Planner decides.
- Test surface: vitest unit tests for naming (lowest-free), serialize/deserialize round-trip for clipboard, smart-parse-and-increment edge cases (`pump_v2` → `pump_v3` is acceptable noise per §3.5); component tests with `@testing-library/react` for context menu rendering and the modal restore dialog; no e2e for the crash-detection lockfile (manual UAT instead).
- Whether the `running.lock` file is JSON or a single line of `<pid>\n<iso8601>` — implementation detail.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design decisions (LOCKED — re-debate not allowed)
- `.planning/notes/gui-redesign-design-decisions.md` §3.5 — Interaction Model: selection / pan / copy-paste / edge deletion. Definitive on the interaction matrix, context menu inventories, copy/cut/paste/duplicate semantics, smart-parse-and-increment naming with lowest-free semantics, reset-to-empty rule. Lines 463–544.
- `.planning/notes/gui-redesign-design-decisions.md` §7 (Section 7) — Carries the "Snap-to-grid toggle" and "AutoRecover" bullets that flag these as Phase-65 deliverables. Lines ~1380–1414.

### Project / milestone state
- `.planning/ROADMAP.md` §"Phase 65: Interaction model overhaul" — phase goal text. No depends-on (phase is independent).
- `.planning/STATE.md` — current working branch is `gui-redesign`; v1.2 milestone active. Branching policy hard-locked in CLAUDE.md (do NOT create new branches).

### Prior-phase artifacts that constrain Phase 65
- `.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md` — D-13 anchor glyph principle (right-click context menu surfacing must not collide with BC anchor affordances). Also explicitly defers "Right-click context menu on BC rows" to Phase 65 — this Phase 65 keeps it deferred (see Deferred Ideas).
- `.planning/phases/64-connection-routing/64-CONTEXT.md` — D-04 anchor follows handle. Pasted nodes will trigger autoflip recomputation on render (autoflip is pure derivation per Phase 64 D-02), so paste does not need to compute handle sides itself.
- `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` — D-19 lowest-free naming algorithm. The naming retrofit (D-17/D-18) explicitly mirrors this. Read this before implementing the new `getNextInstanceName`.

### Code touchpoints (read before planning)
- `gui/src/components/CanvasPanel.tsx` lines 200–233 — ReactFlow root render. Already has `deleteKeyCode={["Delete","Backspace"]}` (line 223). Phase 65 adds: `panOnDrag={[2]}` (or custom right-click handling), `selectionOnDrag={true}` (left-marquee), `snapToGrid` + `snapGrid` props (D-09), `onPaneContextMenu` / `onNodeContextMenu` / `onEdgeContextMenu` handlers, and the canvas-overlay snap-to-grid button.
- `gui/src/components/ui/context-menu.tsx` — shadcn/Radix ContextMenu component to reuse (D-11). Already used by `gui/src/components/resources/ResourcesTreePanel.tsx` (Phase 62) — read that file for an integration precedent.
- `gui/src/store/useStore.ts` lines 296–307 — current `getNextInstanceName` + `instanceCounters` module variable. To be replaced per D-17/D-18.
- `gui/src/store/useStore.ts` line 317 — `nextResourceName` (Phase 62) is the pattern to mirror for the new toolbox-drop naming.
- `gui/src/store/useStore.ts` lines 288–289 + 1763+ — existing `saveProject` / `saveProjectAs` paths. AutoRecover write hook attaches to the same dirty-tracking signal; reuses `projectIO.serialize`.
- `gui/src/lib/projectIO.ts` lines 1–40 + the serialize/deserialize functions — sidecar payload uses these unchanged (D-06).
- `gui/src-tauri/src/lib.rs` (currently 16 lines, only contains `greet`) — AutoRecover lockfile + sidecar I/O may live partly here as Tauri commands, OR fully in TypeScript via `@tauri-apps/plugin-fs`. Planner decides; no preference.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/ui/context-menu.tsx` — shadcn/Radix ContextMenu, dark-mode styled, already in repo. Integration precedent: `gui/src/components/resources/ResourcesTreePanel.tsx` (Phase 62).
- `gui/src/store/useStore.ts:317` — `nextResourceName(kind, existingNames)` lowest-free implementation. Copy its shape for the new instance-name function.
- `gui/src/lib/projectIO.ts` `serialize` / `deserialize` — directly reusable for AutoRecover sidecar payload (D-06).
- `@tauri-apps/api/path` `appDataDir`, `join` — already imported elsewhere in `useStore.ts` (line 445). Reuse for sidecar location resolution (D-05).
- `@tauri-apps/plugin-fs` `writeTextFile`, `readTextFile`, `mkdir` — already imported (lines 446, 460, 1776). Reuse for sidecar I/O.
- `gui/src/components/ThemeMenu.tsx` — uses the lucide `Settings` icon; the snap-to-grid canvas-overlay button can use a `Grid` lucide icon similarly. Visual convention precedent.
- ReactFlow's built-in `snapToGrid`, `snapGrid`, `selectionOnDrag`, `panOnDrag`, `deleteKeyCode` props — handle most of the interaction-matrix wiring. No custom code for these.

### Established Patterns
- **isDirty tracking** is already centralized in `useStore.ts` (saves set it false; mutations set it true). AutoRecover hooks into the same signal — no new dirty mechanism.
- **Per-project layout persistence** — the `.scp` `layout` block already carries `activeLeftTab`, layer view state, etc. Snap-to-grid boolean joins this block (D-10).
- **Module-level state in `useStore.ts`** — currently the only example is `instanceCounters` (the very thing being deleted). Phase 65 leaves no module-level mutable state in this file post-D-18.
- **Tauri command pattern** — minimal so far (`greet` only). If AutoRecover's lockfile reading needs to happen pre-React mount, a Tauri command may be cleaner than waiting for the JS runtime; otherwise pure TS via `@tauri-apps/plugin-fs` works.
- **Modal-on-startup pattern** — there is no precedent yet (no current modal blocks workspace load). Phase 65 establishes one with the AutoRecover restore prompt; future Settings dialog (Phase 67) will follow the same pattern.

### Integration Points
- `CanvasPanel.tsx` ReactFlow props block — primary surface for marquee/pan/snap/context-menu wiring.
- `useStore.ts` actions slice — new `clipboard` actions (`copySelection`, `cutSelection`, `pasteFromClipboard`, `duplicateSelection`), new `autoRecover` slice (`writeSidecar`, `readSidecarOnLaunch`, `clearSidecar`), and a renamed lowest-free `nextInstanceName` function.
- `App.tsx` (or wherever the workspace mounts) — AutoRecover launch sweep + restore modal renders here, before the canvas.
- `projectIO.ts` — unchanged (sidecar reuses serialize/deserialize as-is).
- Each component node type wrapper (in `gui/src/components/StreamNode.tsx` and friends) — wrap with `<ContextMenuTrigger>` to attach the node menu.
- `HydraulicEdge.tsx` / `BcEdge.tsx` / thermal edge — wrap with `<ContextMenuTrigger>` similarly.

</code_context>

<specifics>
## Specific Ideas

- The drawio convention is the visual reference for the interaction matrix. If a behavior question arises mid-implementation that §3.5 doesn't cover, drawio's behavior is the tiebreaker.
- `nextResourceName` (Phase 62) is the definitive shape for the lowest-free naming function — copy it, don't reinvent.
- Smart-parse-and-increment edge cases per §3.5: `pump_v2` → `pump_v3` is **acceptable noise** (the rule produces the wrong answer; user can rename inline). All other rules have worse failure modes; do NOT add special-case logic to detect "v2"-style versioning.
- All produced names must be valid Julia identifiers (ASCII, no spaces / parens / hyphens) — same constraint as Phase 62 resource names. The smart-parse function operates on names that are already Julia-valid by construction, so this falls out for free, but tests should cover it explicitly.
- The "Show errors for this component" menu item from §3.5 is **conditional on Phase 71 validation existing**. Until Phase 71 lands, the menu item is hidden (not grayed-out — simply not rendered). Once Phase 71 lands, it lights up automatically because validation state is already in the store.

</specifics>

<deferred>
## Deferred Ideas

- **Right-click context menu on BC rows / Resource rows** (side panels) — explicitly flagged as Phase 65 candidate by Phase 63.1's deferred list, but kept deferred here. §3.5 scopes context menus to canvas surfaces (node / edge / canvas). Side-panel rows already have hover-revealed action buttons (Phase 62/63.1) — adding right-click menus is a UX consistency play that belongs in Phase 72 design-system audit.
- **Cross-app clipboard interop** (paste from drawio, paste to other Composer-aware tools) — JSON shape is internal in v1.2. If a magic prefix scheme becomes useful, add it as a follow-up.
- **Settings dialog** — Phase 67 (custom titlebar with menubar) and Phase 72 (design system) build the actual Settings UI. Phase 65 ships a canvas-overlay snap-to-grid button as the only user-facing toggle.
- **Auto-Layout** (full-graph reflow) — context menu has a grayed-out "(future)" entry only. Algorithm choice (ELK / dagre / custom) is a future phase.
- **Per-component rotation override** (right-click → Rotate 90°) — already deferred by Phase 64. Stays deferred.
- **Manual handle override** (drag a port to a different side) — already deferred by Phase 64. Stays deferred.
- **AutoRecover for in-flight Julia simulation runs** — sidecar covers project-data only, not running solver state. Out of scope.
- **AutoRecover history / multiple sidecars per project** — Phase 65 keeps only the latest sidecar per project (overwrite-in-place on debounced write). Multi-version history is a future "fit and finish" idea.
- **User-tunable AutoRecover debounce / grid-step size** — both fixed in v1.2 (D-01: ~2s, D-08: 16px). No Settings entry. Future tuning if user feedback demands it.
- **Snap-to-grid per-canvas / per-selection toggle** — global per-project only in v1.2.
- **OS clipboard payload validation prefix** (`__STREAM_COMPOSER_CLIPBOARD__::`) — considered but rejected. JSON parse + shape-check is sufficient; the prefix scheme can be retrofitted later if cross-app paste introduces ambiguity.
- **"Show errors" toast on component when error first appears** — passive surfacing only via the context menu in Phase 65. Active error indicators are Phase 71's job.

### Reviewed Todos (not folded)
None — no pending todos matched Phase 65 scope.

</deferred>

---

*Phase: 65-Interaction-model-overhaul*
*Context gathered: 2026-05-14*
