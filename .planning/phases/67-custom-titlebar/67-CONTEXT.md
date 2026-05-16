# Phase 67: Custom titlebar - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the OS window chrome with a custom HTML titlebar: `decorations: false` in `tauri.conf.json`, a full-width 36px titlebar strip with integrated File/Edit/View/Help menubar, app icon, project name, dirty dot, and custom Min/Max/Close controls. A second 32px secondary strip below holds canvas-specific controls (Layer toggle, Code preview toggle, Export button). Together these two strips replace the single-column `Toolbar.tsx` row that exists today.

**In scope:**
- Add `decorations: false` to `tauri.conf.json`
- New `<CustomTitlebar>` component (full-width, 36px): icon + project name + dirty dot + menus + window controls
- New/refactored `<SecondaryToolbar>` component (full-width, 32px): Layer toggle + Code toggle + Export
- File menu: move existing `FileMenu.tsx` into the titlebar (unchanged items)
- Edit menu: new — Undo/Redo, Cut/Copy/Paste/Duplicate, Preferences (disabled stub)
- View menu: new — Toggle Code Preview, Layer submenu, Theme submenu (absorbs ThemeMenu)
- Help menu: new — About STREAM Composer dialog, Keyboard Shortcuts (disabled stub)
- Window controls: `@tauri-apps/api/window` min/toggleMaximize/close; platform detection for visual style
- Both strips full-width (spanning left panel + canvas + right panel)
- Subtle `border-b` separating titlebar from secondary strip

**Out of scope:**
- Keyboard Shortcuts / Cheatsheet content (Phase 72)
- Settings / Preferences dialog content (Phase 72)
- Layer system overhaul (Phase 68 — the Layer toggle in the secondary strip stays as-is)
- Custom app icon asset (user will provide; Phase 67 uses `icons/32x32.png` placeholder)
- More than three themes (Light/Dark/System) — infrastructure for extended themes deferred to Phase 72
- Taskbar/window icon asset (user will provide separately; existing bundle icons stay for now)

</domain>

<decisions>
## Implementation Decisions

### Layout structure

- **D-01:** Two-strip layout:
  - **Titlebar strip** (36px / `h-9`, full-width): replaces OS chrome and the project-identity portion of `Toolbar.tsx`. Contains (left to right): app icon at ~20px → project name text → dirty dot (●) → File/Edit/View/Help dropdown menus → `data-tauri-drag-region` empty center → window controls (right).
  - **Secondary strip** (32px / `h-8`, full-width): replaces the canvas-control portion of `Toolbar.tsx`. Contains: Layer toggle (left-center) + Code preview toggle + Export button (right).
  - A subtle `border-b` (1px) separates the titlebar from the secondary strip. Both strips use `bg-muted` (same as current Toolbar). The secondary strip also has `border-b` separating it from the canvas/panel area.
- **D-02:** `Toolbar.tsx` is the **primary target for refactoring** — its current content splits between the two new strips. The file can be deleted or repurposed as the new secondary strip. `App.tsx` currently renders `<Toolbar>` inside the center column; the new layout wraps the entire `<div className="flex flex-col h-screen ...">` with a full-width titlebar at the very top (outside the `flex flex-1 min-h-0` row).
- **D-03:** `ThemeMenu.tsx` is **eliminated as a standalone component** — its three radio items (Light/Dark/System) move into the View → Theme submenu.

### Tauri config

- **D-04:** Add `"decorations": false` to `app.windows[0]` in `gui/src-tauri/tauri.conf.json`. No other `tauri.conf.json` changes needed for Phase 67.

### Titlebar content

- **D-05:** **App icon**: `icons/32x32.png` displayed at ~20px via `<img>` (or Tauri `convertFileSrc` if needed). User will provide a custom icon in a future session to replace the placeholder.
- **D-06:** **Project name**: reads `currentFilePath` from `useStore`. Display logic: if `currentFilePath` is set, show `basename(currentFilePath)` without extension; if not set and `isDirty`, show `"Untitled"`; if not set and clean, show nothing (or "STREAM Composer"). The dirty dot `●` appears immediately after the project name when `isDirty === true`.
- **D-07:** **Drag region**: the empty center area between the menus and window controls carries `data-tauri-drag-region`. Double-click on the drag region calls `getCurrentWindow().toggleMaximize()`. The drag region must be wide enough to be easily grabbable — planner should ensure it takes all available center space via `flex-1`.
- **D-08:** **Edit/View/Help keyboard shortcuts shown in menu items** (matching the existing File menu pattern in `FileMenu.tsx`): `Ctrl+Z` on Undo, `Ctrl+Y` on Redo, `Ctrl+X/C/V` on Cut/Copy/Paste, `Ctrl+D` on Duplicate. Preferences and Keyboard Shortcuts have no accelerator shown.

### Menu content (locked item lists)

- **D-09:** **File menu** (unchanged from `FileMenu.tsx`): New (Ctrl+N) / Open… (Ctrl+O) / Save (Ctrl+S) / Save As… (Ctrl+Shift+S).
- **D-10:** **Edit menu** (new):
  - Undo (Ctrl+Z) — calls `useStore.getState().undo()`
  - Redo (Ctrl+Y) — calls `useStore.getState().redo()`
  - Separator
  - Cut (Ctrl+X)
  - Copy (Ctrl+C)
  - Paste (Ctrl+V)
  - Duplicate (Ctrl+D)
  - Separator
  - Preferences… (disabled, stub for Phase 72)
  
  Cut/Copy/Paste/Duplicate wire to the same store actions that Phase 65 keyboard handlers call. Keyboard accelerators in the menu items are display-only (no separate registration — Phase 65 already registered them as window keydown listeners).

- **D-11:** **View menu** (new):
  - Toggle Code Preview — calls `useStore.getState().toggleBottomPanel()`; shows a check mark when `bottomPanelOpen === true`
  - Layer submenu → radio group: Hydraulic / Both / Thermal — mirrors the ToggleGroup in the secondary strip; both stay in sync via the same `activeLayer` / `setActiveLayer` store slice
  - Theme submenu → radio group: Light / Dark / System — wires to the same `setTheme()` function currently passed to `ThemeMenu`

- **D-12:** **Help menu** (new):
  - About STREAM Composer — opens a small modal dialog showing: app name, version (read from `tauri.conf.json` or `@tauri-apps/api/app`'s `getVersion()`), link to GitHub repo
  - Keyboard Shortcuts (disabled, stub for Phase 72)

### Window controls

- **D-13:** Controls are **always on the right side** of the titlebar — no platform-dependent positioning.
- **D-14:** **Platform detection** via `@tauri-apps/plugin-os` `platform()` to determine visual style:
  - **macOS**: three filled circles, horizontally arranged, dim at rest, red/yellow/green on hover (traffic-light convention) — Close=red, Minimize=yellow, Maximize=green. Icons omitted.
  - **Windows/Linux**: icon-based buttons using Lucide `Minus` / `Maximize2` / `X`. Hover on Close = red background. Hover on Minimize/Maximize = subtle `bg-muted-foreground/20`.
- **D-15:** API calls: `getCurrentWindow().minimize()`, `getCurrentWindow().toggleMaximize()`, `getCurrentWindow().close()` from `@tauri-apps/api/window`.

### Secondary strip

- **D-16:** **Secondary strip contents** (left to right): Layer toggle (existing ToggleGroup, same classes) | Code preview toggle button | Export button. ThemeMenu is removed from here.
- **D-17:** The secondary strip is **full-width** (`w-full`), positioned immediately below the titlebar in the main `flex flex-col` root. It is NOT scoped to the center column.

### Claude's Discretion

- Exact component file names and locations (e.g., `gui/src/components/CustomTitlebar.tsx`, `gui/src/components/SecondaryToolbar.tsx`)
- Whether to keep `Toolbar.tsx` as the renamed secondary strip file or delete it and create a new file
- CSS for the macOS circle buttons at rest (dim factor, exact circle size, border)
- The "About" dialog implementation (shadcn `Dialog` is the obvious choice)
- Whether `platform()` is called once on mount (stored in component state) or at render time

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design decisions (LOCKED — re-debate not allowed)
- `.planning/notes/gui-redesign-design-decisions.md` §3.6 — Custom Titlebar: the structural decision (decorations: false, drag region, layout table, File menu integrated). Lines ~546–580.
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — Design System / Interaction Contract: visual restraint ("no silent state changes", information density, muted palette, professional engineering tool). Lines ~620–710.

### Existing components being refactored
- `gui/src/components/Toolbar.tsx` — existing 36px toolbar strip being split/replaced; source of FileMenu, ThemeMenu, Layer toggle, Code toggle, Export button
- `gui/src/components/FileMenu.tsx` — existing File menu (shadcn DropdownMenu pattern); moves into titlebar
- `gui/src/components/ThemeMenu.tsx` — existing theme selector; folds into View → Theme submenu
- `gui/src/App.tsx` — main layout; titlebar inserts at the top of the outer `flex flex-col h-screen` wrapper

### Tauri config
- `gui/src-tauri/tauri.conf.json` — add `decorations: false`; reference for current window config

### Phase / milestone state
- `.planning/ROADMAP.md` §"Phase 67: Custom titlebar" — phase goal text
- `.planning/notes/gui-redesign-design-decisions.md` §7 — GUI redesign backlog bullets (custom titlebar is item 5)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FileMenu.tsx`: shadcn `DropdownMenu` with `onUnsavedCheck` prop — reuse as-is in the titlebar; only its render location changes
- `useStore` selectors `isDirty`, `currentFilePath`, `toggleBottomPanel`, `bottomPanelOpen`, `activeLayer`, `setActiveLayer` — all needed in the titlebar; already implemented
- `useStore` clipboard/undo actions already called by Phase 65 keyboard listeners — same calls go into Edit menu items
- `exportCode` util in `gui/src/lib/exportCode.ts` — reused by secondary strip Export button (same as current Toolbar)
- `@tauri-apps/api/window` `getCurrentWindow()` — already imported in `App.tsx` for the close-guard handler

### Established Patterns
- shadcn `DropdownMenu` + `DropdownMenuTrigger` + `DropdownMenuContent` + `DropdownMenuItem` — the existing pattern for FileMenu and ThemeMenu; new Edit/View/Help menus use the same pattern
- `bg-muted border-b` on the Toolbar — keep this as the background for both new strips
- `h-9` (36px) for the titlebar matches the current Toolbar height exactly
- `@tauri-apps/plugin-os` is the Tauri v2 way to call `platform()` — check if it's already in `package.json` or needs adding

### Integration Points
- `App.tsx` JSX: the new `<CustomTitlebar>` must be placed **above** the `<div className="flex flex-1 min-h-0">` that contains the left/canvas/right panel layout — it becomes the first child of the root `<div className="flex flex-col h-screen ...">`. The `<SecondaryToolbar>` goes between titlebar and the `flex flex-1` row (or as the top of the center column if full-width layout requires restructuring `App.tsx`).
- `showUnsavedDialog` callback in `App.tsx` must be passed to the File menu inside `CustomTitlebar` (same as it's currently passed to `Toolbar`)
- `theme`/`setTheme` props currently passed from `App.tsx` to `Toolbar` → `ThemeMenu` must now route to the View menu inside `CustomTitlebar`

</code_context>

<specifics>
## Specific Ideas

- User explicitly wants the titlebar to "feel slim and nice" with no dead space — padding and line-heights should be tight (e.g., `py-0.5` or `py-1` max on menu items inside the strip, text-xs for project name)
- The dirty dot indicator is a literal `●` character (per §3.6 spec), not an icon component
- The user will provide a custom app icon and taskbar icon in a future session — Phase 67 should make it easy to swap by keeping the icon source as a single referenced asset path
- User specifically noted that future theme infrastructure should be built to support more than Light/Dark/System — even if Phase 67 only ships those three, avoid hardcoding assumptions that would block Phase 72 from adding more

</specifics>

<deferred>
## Deferred Ideas

- **Extended theme palette** (more than Light/Dark/System): user wants infrastructure for richer themes in the future. Noted for Phase 72 (Design system / interaction contract). Don't hardcode the theme list to exactly 3 items in a way that would require architectural changes to add more.
- **Custom app icon + taskbar icon asset**: user will provide custom icon files to replace `icons/32x32.png` and the bundle icons. No phase assigned — will be a one-file-swap when the user delivers the assets.
- **Keyboard Shortcuts / Cheatsheet content**: Phase 72 deliverable; Phase 67 adds a disabled menu stub only.
- **Settings / Preferences dialog content**: Phase 72 deliverable; Phase 67 adds `Edit → Preferences` as a disabled menu stub only.

</deferred>

---

*Phase: 67-custom-titlebar*
*Context gathered: 2026-05-16*
