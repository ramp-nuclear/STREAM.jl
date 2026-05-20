# Phase 70: Presets and templates - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Reusable component-bundle templates for STREAM Composer. New `.scpr` file format (slimmed-down `.scp` sub-graph containing components + connections + parameter values + embedded resources + relative layout). UI surfaces: "Save selection as preset…" (right-click on multi-select + `File → Save selection as preset…`) and "Load preset…" (`File → Load preset…` + a dedicated Presets tab in the left panel with drag-from-toolbox entries). No identity (Option 1 per issue #14 / §3.14): copy-paste templates; link to source file severed after load; updates do not propagate to existing instantiations.

Out of scope: passive identity (UUID + version) on presets — forward-compatible but not built; reverse import (parsing hand-written `.jl` back into the GUI model); validation framework integration (Phase 71 owns that); visual polish of new chrome (Phase 72 owns the cross-app design audit).

</domain>

<decisions>
## Implementation Decisions

### Surface — left panel

- **D-01:** Add a **4th tab "Presets"** to the left panel, alongside Project / Resources / Components (the three tabs introduced in Phase 62). Keyboard binding **Ctrl+4**, aligned with Phase 62's Ctrl+1/2/3 scheme.
- **D-02:** This decision **supersedes the literal wording** in §3.14 ("Presets category in the toolbox"). Semantically identical (Presets still live in the left panel, drag-from-toolbox), but on their own tab rather than as a sibling category to Hydraulic / Thermal / Sources / Reactor Physics / Resources inside the Components tab. The driver is clutter avoidance once both stores (D-03) are populated.
- **D-03:** Presets tab body has **two sections**: "Project" (entries from `<project>/presets/`) and "Library" (entries from the user-global store). Each section is collapsible. Each entry shows name + description tooltip on hover.

### Storage — two stores, file-system-watched

- **D-04:** **Two stores**:
  - **Project store:** `<project-dir>/presets/*.scpr` — sits next to the `.scp` file; git-shareable; travels with the project. Resolved relative to the currently-open project's path.
  - **Library store:** Tauri `appConfigDir/stream-composer/presets/*.scpr` — cross-platform user-global library (`~/.config/stream-composer/presets/` on Linux, `~/Library/Application Support/stream-composer/presets/` on macOS, `%APPDATA%/stream-composer/presets/` on Windows). Use Tauri's `appConfigDir` API — do NOT hardcode `~/.config`.
- **D-05:** Both directories are **file-system-watched** (Tauri `watch` plugin or equivalent). New / renamed / deleted `.scpr` files appear in the Presets tab without app restart. Watcher is debounced (~200ms) to coalesce editor save-bursts.
- **D-06:** On project switch (open a different `.scp`), the Project store rebinds to the new project's directory and the Project section refreshes; the Library section is unaffected.

### `.scpr` file format

- **D-07:** Schema per §3.14, locked:
  ```json
  {
    "format_version": "1.0",
    "kind": "preset",
    "name": "mtr-fuel-assembly",
    "description": "Single MTR fuel plate flanked by two CAC channels",
    "resources": { /* embedded copies of referenced resources */ },
    "components": [ /* the components in the preset */ ],
    "connections": [ /* the internal connections, including BC edges */ ],
    "layout": { /* relative canvas positions, normalized to bbox-top-left at (0,0) */ }
  }
  ```
- **D-08:** Serialization lives in `gui/src/lib/projectIO.ts` (or a sibling `presetIO.ts` — planner's call). The `.scp` writer in `projectIO.ts` is the established single-source-of-truth pattern; `.scpr` follows the same code-locality rule.
- **D-09:** `name` field MUST match the filename stem (without `.scpr`). Rename operations (D-19) update both.
- **D-10:** `name` MUST be ASCII-only and a valid filename — enforced at save time. The cross-cutting invariant "All Julia identifiers produced by the GUI are ASCII-only and valid" applies (no Unicode, no spaces, no parens, no hyphens). Lock to `[A-Za-z0-9_-]+` (hyphen allowed in filenames; only Julia identifiers ban hyphens, and `.scpr` files are never identifiers).
- **D-11:** `layout` is **normalized to bbox-top-left at (0,0)** at save time. This makes drop-placement math trivial (D-16, D-17) and decouples saved coordinates from wherever the user happened to have the components on the source canvas.

### Selection → preset contents

- **D-12:** **Auto-extend rule.** Starting from the user's explicit selection S:
  1. **Extend S by one hop along BC edges only:** any unselected component on the other end of a BC edge connected to a component in S is added to the preset (e.g., a WallTemperature feeding a selected Channel's `T_wall_out`).
  2. **Drop cross-boundary edges** that remain after the extension: FlowPort connections and thermal-pair connections (ChannelAndContacts ↔ HeatDiffusion) where one endpoint is still outside the extended set. Those are wiring, not part of a self-contained bundle.
  3. **Keep all edges fully inside** the extended set.
  4. **Embed resource copies** (§3.14): every resource referenced by a component in the extended set has its embedded copy added to the preset's `resources` block.
- **D-13:** Extension is **one hop only**, not recursive. A WT pulled in by Channel A does NOT pull in Channel B (even if the same WT also feeds Channel B). The WT's connection to Channel B is dropped as a cross-boundary edge per step 2.
- **D-14:** Components keep their **layer assignment** (hydraulic / thermal / sources / reactor physics, from Phase 68) through preset round-trip.

### Save UX

- **D-15:** **"Save selection as preset…"** opens a **modal dialog** (radix Dialog, same chrome as Settings/About from Phase 67) with three controls:
  - **Name** (text input; required; ASCII-only validation per D-10; live-validates against existing filenames in the chosen store).
  - **Description** (textarea; optional; multi-line; shown as tooltip on Presets tab hover).
  - **Store** (radio: Project / Library; **default Library**). If no project is open, Project radio is disabled.
  - **Save** commits the `.scpr` to `<store>/presets/<name>.scpr`. **Cancel** discards. ESC closes (per existing dialog convention).
- **D-15.1:** Save action surfaces:
  - Right-click on a multi-selection (≥2 components) → context menu entry "Save selection as preset…".
  - `File → Save selection as preset…` menu item; disabled when fewer than 2 components are selected.

### Load UX

- **D-16:** **Drag-from-toolbox** (Presets tab → drag → drop on canvas): **bbox-center at cursor on release.** Components offset from the cursor by their saved relative layout (normalized per D-11).
- **D-17:** **`File → Load preset…`** opens a file picker; on choose, the bundle lands at **bbox-center at the current viewport center** (compute via ReactFlow's viewport transform). Always immediately visible to the user.
- **D-18:** **Auto-select-after-load.** All loaded components are selected after placement (consistent with copy/paste behavior from Phase 65 / `gui/src/lib/clipboard.ts`). User can immediately move/edit/delete the freshly-loaded bundle.
- **D-18.1:** On load, components and connections are **mint-new-UUID'd** (§3.14). The `name` field on each component is run through smart-name-increment per the existing helpers (`useStore.ts:1748`, `clipboard.ts:60`). Embedded resources are added to the project's Resources, also with smart-name-increment if a same-name resource exists — **no auto-dedupe-by-content** (user can manually merge after).

### Manage UX (Presets tab)

- **D-19:** Right-click on a preset entry exposes three actions:
  - **Rename** — inline rename (like Resources rename in Phase 62); on commit, renames the `.scpr` file AND updates the `name` field inside the JSON (§D-09).
  - **Delete** — confirmation modal, then unlinks the `.scpr`; the file-system watcher removes the entry from the tab.
  - **Reveal in Finder/Explorer** — Tauri `shell.open` on the parent folder, with the file selected if the platform supports it.
- **D-19.1:** **No "Edit description" action.** Description is set on save (D-15). To edit a description after the fact, the user can either (a) right-click → Reveal in FS, edit the JSON directly (the watcher picks up the change), or (b) re-save (the save modal pre-fills existing values when saving with an identical name into the same store — confirms overwrite). Adding a dedicated "Edit description" action was considered and dropped as low-value clutter.

### Claude's Discretion

- Preset tab visual style: follows the existing left-panel patterns (Phase 62 ToolboxPanel + Resources tab). Density expectations and accent colors are inherited from those phases — the design audit in Phase 72 will sweep this surface along with everything else.
- Loading state / progress indicators while watcher initializes: planner's call; reasonable default is "tab body shows skeleton briefly, then populates."
- Tooltip rendering on Presets tab entries: name + description; planner decides whether to show component count, layer breakdown, or other metadata.
- Save modal field order, label wording, button labels: planner / UI-spec.
- Empty-state copy for each section ("No project presets yet. Save a selection to create one." / similar).
- Whether the toolbox-drag drag-image is a generic preset icon or a mini-render of the preset bbox: planner's call; generic icon is simpler and matches the existing component-drag UX.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked design decisions
- `.planning/notes/gui-redesign-design-decisions.md` §3.14 (Projects and Presets — File Format and Identity) — locks file format, no-identity model, smart-name on load, save/load surfaces, the door-open-to-passive-identity-later contract. The single most important upstream doc for this phase.
- `.planning/notes/gui-redesign-design-decisions.md` §4 (Cross-Cutting Invariants) — see the "Presets are copy-paste templates with no identity" bullet and the ASCII-identifier rule that constrains preset `name`.
- `.planning/notes/gui-redesign-design-decisions.md` §3.2 (Save Format / `.scp` schema) — `.scpr` is a slimmed-down version; the planner must understand the parent schema before slimming.
- `.planning/notes/gui-redesign-design-decisions.md` §3.5 (Naming / smart-name-increment rules) — applies to component renames AND embedded-resource renames on load.

### Roadmap & milestone
- `.planning/ROADMAP.md` §Phase 70 (lines 285–288) — phase goal and design-decisions reference pointer.
- `.planning/ROADMAP.md` lines 14–22 (Overview) — v1.1 channels-redesign architectural invariants that constrain BC-edge behavior in §D-12.

### Codebase landmarks
- `gui/src/lib/projectIO.ts` — `.scp` serialization; the established single-source-of-truth pattern for save-file IO; `.scpr` IO sits here or in a sibling file in the same `lib/` directory.
- `gui/src/lib/clipboard.ts` (line 60 onward) — existing smart-parse-and-increment naming logic for component clones; the same helper is reused for load-preset's collision handling.
- `gui/src/store/useStore.ts` (line 1748 onward) — smart-name-increment for resources; reused on embedded-resource auto-create during preset load.
- `gui/src/registry/components.json` — existing toolbox category mechanism (`"category": "Hydraulic" / "Thermal" / "Sources" / "Reactor Physics" / "Resources"`); informs how the Presets tab parallels this surface but lives on its own tab rather than as another category value.
- `gui/src/components/ToolboxPanel.tsx`, `gui/src/components/SidebarPanel.tsx`, `gui/src/App.tsx` — left-panel tab shell from Phase 62 (Tabs component + Ctrl+1/2/3 keybinds). The 4th Presets tab plugs in here.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`projectIO.ts`** — JSON serializer/parser with `format_version` versioning; `.scpr` reads/writes follow the same pattern (different `format_version` namespace, different `kind` field).
- **`clipboard.ts` (smart-parse-and-increment)** — already handles "Channel_1, Channel_2, Channel_3" style increment; reused for loaded-preset component name collisions.
- **`useStore.ts:1748` (resource smart-name-increment)** — already handles resource-name collisions; reused for embedded-resource auto-create on load.
- **Left-panel Tabs shell from Phase 62** — Tabs primitive + Ctrl+digit keybind mechanism; Presets tab slots in as the 4th tab.
- **Radix Dialog from Phase 67 (Settings, About, AutoRecoverRestore)** — established modal chrome; reused for the Save-as-Preset modal.
- **Drag-from-toolbox flow** (`ToolboxItem.tsx` + drop handlers on the canvas) — already exists for components; the Presets tab reuses the same drag start → canvas drop pipeline, just with a `.scpr`-payload-aware drop handler.
- **Layer assignment per component (Phase 68)** — preset round-trip preserves the `layer` field already present on every component.

### Established Patterns
- **One file = one IO surface.** `.scp` reads/writes are in `projectIO.ts`. `.scpr` reads/writes follow the same locality rule (planner decides: extend `projectIO.ts` or new `presetIO.ts` in the same folder).
- **No back-compat hacks during heavy dev** (per CLAUDE.md / user memory) — `.scpr v1.0` is the only format; no upgraders, no fallbacks for missing fields. Old/broken files surface a clear error.
- **Reset-to-empty rule for property fields** (§3.5) — applies to the Save modal's Name field as long as the user can blank-and-default; here there's no default name so empty is rejected.
- **Watched-folder pattern is new to this phase.** No existing Tauri-watch usage in the GUI; planner researches the Tauri watch API and selects the smallest surface (debounce + add/remove/rename event handling).
- **Drag-from-toolbox drop placement.** Components currently drop at the cursor position with the component icon centered on the cursor; presets follow the same convention with bbox-center at cursor (D-16).

### Integration Points
- **New tab** plugs into `App.tsx`'s left-panel Tabs and the Ctrl+digit keybind handler (currently 1/2/3 → add 4).
- **File menu** (`FileMenu.tsx` from Phase 67) gains two new items: "Save selection as preset…" and "Load preset…".
- **Canvas right-click context menu** gains one new item (visible when selection count ≥ 2): "Save selection as preset…".
- **Tauri config** — `tauri.conf.json` needs allowlist entries for the watch API and `appConfigDir` resolution. Planner researches exact entries.
- **Store** — new slice for `presets: { project: PresetIndexEntry[]; library: PresetIndexEntry[]; activePresetStore: 'project' | 'library' }` (planner finalizes shape); watcher events mutate this slice.

</code_context>

<specifics>
## Specific Ideas

- **Section 3.14 is the spec.** The phase goal in ROADMAP.md is a one-line pointer; §3.14 is the actual contract (file format, no-identity Option 1 resolution, save/load surfaces, embedded-resource semantics). Downstream agents start by reading §3.14 end-to-end.
- **Default save store: Library.** Users typically save personal templates that they want available across projects; Project-store saves are the deliberate "I'm bundling this for the team" choice. Default reflects the common case.
- **Tab keybind: Ctrl+4.** Parallel to Phase 62's Ctrl+1 (Project) / Ctrl+2 (Resources) / Ctrl+3 (Components). Phase 69's Ctrl+P (command palette) is independent; no conflict.
- **`appConfigDir` cross-platform.** Hardcoding `~/.config/...` is wrong on macOS/Windows. The user explicitly named "user-library" rather than "~/.config" — Tauri's `appConfigDir` API resolves to the right per-platform path.
- **Auto-extend one hop, not recursive.** Bounded behavior; predictable; the user sees exactly which components got pulled in (they're highlighted before save).

</specifics>

<deferred>
## Deferred Ideas

- **Passive identity for presets (Option 3 from §3.14)** — UUID + version field on `.scpr`, auto-link existing preset instances to the source file, prompt-to-update on file change. Forward-compatible (the v1 format leaves room) but explicitly out of scope per §3.14 ("wait for the pain" call). Re-evaluate when users complain about manual update churn.
- **Auto-dedupe embedded resources by content** — when an embedded resource is byte-identical to an existing project resource, link instead of duplicate. §3.14 explicitly defers this: "User can manually merge duplicate Resources after load if they want." A future phase if manual merging becomes a pain point.
- **Preset preview thumbnail** — mini-render of the preset bbox on hover or in the tab listing. Aesthetic; the design audit in Phase 72 may roll this in.
- **Edit description from right-click** — dropped from v1 per D-19.1; can be added later if "re-save with same name" friction shows up in usage.
- **Preset categories / tags** — group presets by type ("fuel assemblies," "test rigs," etc.) inside the tab. Not needed until users have many presets.
- **Bulk operations** (multi-select presets to delete or export) — not v1.
- **Import preset from URL / share** — not v1.
- **Reviewed Todos (not folded):** The four todos surfaced by `todo.match-phase 70` (gui-visual-design-pass, codegen-resource-naming-dedup, phase72-handle-port-visual-rework, panel-resize-overflow-bounds) matched on generic "phase"/"design" keywords but do not intersect Phase 70's scope. They stay in their respective lanes (general visual polish → Phase 72; codegen naming → backlog).

</deferred>

---

*Phase: 70-presets-and-templates*
*Context gathered: 2026-05-20*
</content>
</invoke>