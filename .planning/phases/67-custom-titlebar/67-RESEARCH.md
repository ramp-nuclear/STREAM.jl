# Phase 67: Custom titlebar — Research

**Researched:** 2026-05-16
**Domain:** Tauri v2 frameless windows + React/shadcn menubar refactor
**Confidence:** HIGH on Tauri API surface and integration sites; MEDIUM on macOS visual conventions; LOW on WSLg-specific drag/resize edge behavior.

## Summary

Phase 67 replaces OS window chrome with an in-app titlebar. The work is small in code volume (~3 new components, 1 plugin install, 1 config flag, ~10 lines of capability JSON, App.tsx restructure) but threaded across four layers — Vite/React, `tauri.conf.json`, Rust `lib.rs` (`tauri_plugin_os::init`), and `capabilities/default.json` — each of which silently no-ops if forgotten. The current `Toolbar.tsx` splits cleanly into the new `CustomTitlebar` + `SecondaryToolbar` because every action it dispatches already lives in `useStore` (no wiring rewrites needed beyond render-location).

Three risks dominate. (1) **`decorations: false` + edge-resize on Linux/WSLg is buggy**: Tauri issues #8519, #6609, #9053 all describe broken or jittery resize when the OS chrome is gone. The user runs WSLg, so the Phase 67 UAT must explicitly probe edge-resize on the actual target platform. (2) **`data-tauri-drag-region` and child events**: the attribute applies only to the exact DOM node carrying it (issues #9901, #9725); menu triggers and window-control buttons must be **siblings** of the drag region, not descendants, or clicks bubble into "drag the window." (3) **Capability registration is silent**: missing `core:window:allow-minimize` etc. fails as a no-op IPC rejection, not a build error. Plan must enumerate every permission added.

**Primary recommendation:** Land the four-layer change in a single plan (one task per layer: Cargo + lib.rs plugin register, capabilities permissions, `tauri.conf.json` decorations flag, frontend components). Then a second plan for menu wiring + About dialog. Gate the whole phase behind a manual WSLg UAT — automated tests cannot verify drag/resize/minimize.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OS window chrome removal | Tauri config (`tauri.conf.json`) | — | Declarative; no code path |
| Window control IPC (min/max/close) | Tauri core plugin + capabilities | Frontend (React click handlers) | IPC is gated by capability permissions; React only calls `getCurrentWindow().X()` |
| Platform detection (macOS vs Windows/Linux) | `tauri_plugin_os` (Rust) + `@tauri-apps/plugin-os` (JS) | Frontend (one-time mount call) | Plugin must be registered in Rust AND capabilities AND added to package.json — three-tier install |
| Drag region | Frontend (HTML attribute `data-tauri-drag-region`) | Tauri WebView (native handler) | Tauri intercepts mousedown on the attribute; React just renders the empty div with `flex-1` |
| Project name + dirty dot | Frontend (Zustand selector) | — | Already in `useStore`; no IPC |
| Menu items (File/Edit/View/Help) | Frontend (shadcn DropdownMenu + Zustand actions) | — | Wires to existing store actions — no IPC, no Rust |
| About dialog version | `@tauri-apps/api/app::getVersion()` | Frontend | IPC call (async); reads from compiled binary |
| Theme submenu | Frontend (`useTheme` hook + localStorage) | — | Existing `useTheme` already owns persistence |
| Maximize-icon-state sync | Frontend (`onResized` listener) | Tauri core plugin (event source) | Listener fires on every resize; needs cleanup on unmount |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@tauri-apps/api` | `^2` (already in package.json) | `getCurrentWindow()`, window IPC | The Tauri v2 official JS binding; nothing else can talk to the Tauri core |
| `@tauri-apps/plugin-os` | `2.x` (needs install) | `platform()` for macOS vs Windows/Linux branching | Tauri v2 official OS-info plugin; replaces Tauri v1's `os` namespace |
| `tauri-plugin-os` | `"2"` (Cargo, needs install) | Rust counterpart of the JS plugin | Required — JS binding is a no-op without Rust registration |
| `@tauri-apps/api/app::getVersion` | (part of `@tauri-apps/api`) | About dialog version string | Reads the version from the compiled `Cargo.toml`/`tauri.conf.json` |
| `lucide-react` | `^1.7.0` (already in package.json) | `Minus`, `Maximize2`, `Minimize2`, `X` icons | Already the project icon library |
| shadcn `dropdown-menu` | already installed (`gui/src/components/ui/dropdown-menu.tsx`) | Menus + submenus + radio groups | Already the project DropdownMenu pattern |
| shadcn `dialog` | NOT installed — must run `npx shadcn add dialog` in `gui/` | About modal | Standard shadcn modal; UI-SPEC §"Registry Safety" already calls this out |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Zustand store (`useStore`) | (project-internal) | All Edit/View/Help menu item actions wire to existing store slices | Every menu item dispatches `useStore.getState().X()` — no new state slices needed |
| `useTheme` (project hook) | (project-internal) | Theme submenu value/setter | Already wired through `App.tsx`; just relocate the consumer to View menu |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `data-tauri-drag-region` attribute | `getCurrentWindow().startDragging()` on `mousedown` | Manual path is needed only if attribute is buggy on WSLg. Tauri's own window-customization docs and Ellie.wtf's "Fixing drag events with Tauri" article both recommend the manual fallback for Linux quirks. Plan should pick attribute-first and keep the manual path documented for the UAT fallback. [CITED: v2.tauri.app/learn/window-customization] |
| `tauri-plugin-decorum` / `tauri-plugin-mac-rounded-corners` for native macOS traffic lights | Pure-CSS replica circles | Plugin path adds Rust dependency + maintenance burden; CSS replica matches D-14 (user wants explicit "macOS vs Windows/Linux" branching at the React level, not OS-native chrome). Stick with CSS replica. |
| `useInterval`-poll for `isMaximized()` (per blog.elijahlopez.ca) | `onResized()` listener + `isMaximized()` query on each event | Polling burns CPU; `onResized` is the official pattern (Tauri discussion #5881). Use the listener. |

**Installation (new dependencies only):**

```bash
# In gui/
npm install @tauri-apps/plugin-os
npx shadcn add dialog
```

```toml
# In gui/src-tauri/Cargo.toml [dependencies]
tauri-plugin-os = "2"
```

**Version verification:**
- `@tauri-apps/api@2` already locked; nothing to bump. [VERIFIED: gui/package.json line 14]
- `@tauri-apps/plugin-os` published at `2.x` line; matches the `tauri = { version = "2" }` already pinned in `Cargo.toml`. [CITED: v2.tauri.app/plugin/os-info]
- `lucide-react@^1.7.0` already present — `Minus`, `Maximize2`, `Minimize2`, `X` all exist in this version line. [VERIFIED: gui/package.json line 21]

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `@tauri-apps/plugin-os` | npm | 2+ yrs (Tauri v2 line) | high | github.com/tauri-apps/plugins-workspace | [ASSUMED] (slopcheck not run in this session — but official Tauri org package, documented at v2.tauri.app/plugin/os-info) | Approved |
| `tauri-plugin-os` | crates.io | 2+ yrs | high | github.com/tauri-apps/plugins-workspace | [ASSUMED] (official Tauri org) | Approved |
| shadcn `dialog` | shadcn registry (not npm — copied source) | stable | N/A (source-copy) | github.com/shadcn-ui/ui | [ASSUMED] (official shadcn registry; project already uses 15 other shadcn components from same source) | Approved |

slopcheck was not executed in this research session. All three packages are from canonical sources used by the existing codebase (Tauri official + shadcn official). Risk is low but not zero — planner may optionally add a `checkpoint:human-verify` task before the `npm install` and `cargo` edit if desired.

## Architecture Patterns

### System Architecture Diagram

```
                User clicks Min/Max/Close
                          │
                          ▼
   ┌──────────────────────────────────────┐
   │ <WindowControls/> (React)            │
   │ (CSS branch: macOS circles vs        │
   │  Windows/Linux Lucide icons)         │
   └─────────────┬────────────────────────┘
                 │ getCurrentWindow().minimize() etc.
                 ▼
   ┌──────────────────────────────────────┐
   │ @tauri-apps/api/window (JS binding)  │
   └─────────────┬────────────────────────┘
                 │ IPC (gated by capabilities)
                 ▼
   ┌──────────────────────────────────────┐
   │ Tauri core window plugin (Rust)      │
   │ Permissions required:                │
   │   core:window:allow-minimize         │
   │   core:window:allow-toggle-maximize  │
   │   core:window:allow-start-dragging   │
   │   core:window:allow-is-maximized     │
   │   (close + set-title + destroy       │
   │    already granted in default.json)  │
   └─────────────┬────────────────────────┘
                 │
                 ▼
              OS window manager

  Parallel path — platform detection:
   <WindowControls/> mount
       │
       ▼ platform()    // synchronous in JS
   @tauri-apps/plugin-os (JS)
       │
       ▼ IPC
   tauri-plugin-os (Rust) — must be in lib.rs .plugin(tauri_plugin_os::init())
       │
       ▼
   os:default permission (required in capabilities)

  Parallel path — drag region:
   <div data-tauri-drag-region flex-1 h-full onDoubleClick=…/>
       │
       ▼ Tauri WebView intercepts mousedown on the EXACT node carrying the attribute
   Native window-drag
       │ (double-click → React onDoubleClick → getCurrentWindow().toggleMaximize())
       ▼
   OS window manager
```

### Recommended Project Structure

```
gui/src/
├── components/
│   ├── CustomTitlebar.tsx           # NEW — 36px strip, integrates File/Edit/View/Help + WindowControls
│   ├── SecondaryToolbar.tsx         # NEW (replaces current Toolbar.tsx; rename or new file — see D-02)
│   ├── WindowControls.tsx           # NEW — platform branch (macOS circles vs Win/Linux icons)
│   ├── AboutDialog.tsx              # NEW — shadcn Dialog showing app name/version/GitHub link
│   ├── FileMenu.tsx                 # UNCHANGED — moved render site only
│   ├── EditMenu.tsx                 # NEW — Undo/Redo/Cut/Copy/Paste/Duplicate/Preferences
│   ├── ViewMenu.tsx                 # NEW — ToggleCode + Layer submenu + Theme submenu
│   ├── HelpMenu.tsx                 # NEW — About + Keyboard Shortcuts (stub)
│   ├── ThemeMenu.tsx                # DELETE (D-03) — radio items move into ViewMenu
│   └── Toolbar.tsx                  # DELETE or RENAME to SecondaryToolbar.tsx (D-02 — Claude's discretion)
├── hooks/
│   ├── useWindowMaximized.ts        # NEW — wraps isMaximized() + onResized listener for the Max/Restore icon swap
│   └── usePlatform.ts               # NEW (optional) — wraps platform() one-time fetch into a hook with state
├── App.tsx                          # MODIFIED — restructure root to put <CustomTitlebar> and <SecondaryToolbar> above the flex-1 row (see Layout below)
└── ...
gui/src-tauri/
├── tauri.conf.json                  # MODIFIED — add "decorations": false
├── Cargo.toml                       # MODIFIED — add tauri-plugin-os = "2"
├── src/lib.rs                       # MODIFIED — .plugin(tauri_plugin_os::init())
└── capabilities/default.json        # MODIFIED — add 5 permissions
gui/public/                          # COPY icons/32x32.png here so <img src="/32x32.png"> works
```

### Pattern 1: Frameless window setup (4-layer registration)

**What:** A custom titlebar requires changes in `tauri.conf.json`, `Cargo.toml`, Rust `lib.rs`, and `capabilities/default.json`. Missing any one of them produces silent runtime failures (no compile error).

**When to use:** Once per app; this is the Phase 67 setup.

**Example:**

```json
// gui/src-tauri/tauri.conf.json — app.windows[0]
{
  "title": "STREAM Composer",
  "width": 1280,
  "height": 800,
  "minWidth": 800,
  "minHeight": 600,
  "decorations": false
}
```

```json
// gui/src-tauri/capabilities/default.json — add to permissions
"core:window:allow-minimize",
"core:window:allow-toggle-maximize",
"core:window:allow-start-dragging",
"core:window:allow-is-maximized",
"os:default"
```
Source: [CITED: v2.tauri.app/learn/window-customization, v2.tauri.app/plugin/os-info]. The capabilities file currently only grants `set-title`, `close`, `destroy` — confirmed at `gui/src-tauri/capabilities/default.json` lines 26-28.

```toml
# gui/src-tauri/Cargo.toml — append under [dependencies]
tauri-plugin-os = "2"
```

```rust
// gui/src-tauri/src/lib.rs — inside pub fn run() builder chain
tauri::Builder::default()
    .plugin(tauri_plugin_opener::init())
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_os::init())   // NEW — must be registered or platform() returns nothing
    .invoke_handler(tauri::generate_handler![greet, is_pid_alive, get_pid])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
```

### Pattern 2: Window-controls component with platform branch

**What:** A single React component that calls `platform()` once on mount and renders either macOS traffic-light circles or Windows/Linux icon buttons.

**Example:**

```tsx
// gui/src/components/WindowControls.tsx
import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { platform } from "@tauri-apps/plugin-os";
import { Minus, Maximize2, Minimize2, X } from "lucide-react";
import { Button } from "./ui/button";
import { useWindowMaximized } from "../hooks/useWindowMaximized";

type Platform = "macos" | "windows" | "linux" | null;

export default function WindowControls() {
  const [plat, setPlat] = useState<Platform>(null);
  const isMax = useWindowMaximized();

  useEffect(() => {
    // platform() is SYNCHRONOUS in @tauri-apps/plugin-os (CITED: v2.tauri.app/plugin/os-info).
    // Returns one of: "linux", "macos", "ios", "freebsd", "dragonfly", "netbsd",
    // "openbsd", "solaris", "android", "windows".
    try {
      const p = platform();
      setPlat(p === "macos" ? "macos" : p === "windows" ? "windows" : "linux");
    } catch {
      // Non-Tauri env (vitest) — render Windows/Linux variant
      setPlat("linux");
    }
  }, []);

  const w = getCurrentWindow();
  const onMin = () => void w.minimize();
  const onMax = () => void w.toggleMaximize();
  const onClose = () => void w.close();

  if (plat === "macos") {
    return (
      <div className="flex items-center gap-2 px-3 group">
        <button aria-label="Close window" onClick={onClose}
          className="w-3 h-3 rounded-full bg-[#ff5f57]/40 group-hover:bg-[#ff5f57] transition-colors" />
        <button aria-label="Minimize window" onClick={onMin}
          className="w-3 h-3 rounded-full bg-[#ffbd2e]/40 group-hover:bg-[#ffbd2e] transition-colors" />
        <button aria-label="Toggle maximize" onClick={onMax}
          className="w-3 h-3 rounded-full bg-[#28c840]/40 group-hover:bg-[#28c840] transition-colors" />
      </div>
    );
  }

  // Windows / Linux
  return (
    <div className="flex items-stretch h-full">
      <Button variant="ghost" size="icon" aria-label="Minimize window" onClick={onMin}
        className="rounded-none h-full w-10 hover:bg-muted-foreground/20">
        <Minus className="h-4 w-4" />
      </Button>
      <Button variant="ghost" size="icon" aria-label="Toggle maximize" onClick={onMax}
        className="rounded-none h-full w-10 hover:bg-muted-foreground/20">
        {isMax ? <Minimize2 className="h-4 w-4" /> : <Maximize2 className="h-4 w-4" />}
      </Button>
      <Button variant="ghost" size="icon" aria-label="Close window" onClick={onClose}
        className="rounded-none h-full w-10 hover:bg-destructive hover:text-destructive-foreground">
        <X className="h-4 w-4" />
      </Button>
    </div>
  );
}
```

Source: traffic-light hex values from `aizcutei/tauri_mac_traffic_light_window_demo` (`#ff5f57`/`#ffbd2e`/`#28c840` — the canonical Apple HIG values; demo uses `#ff6159`/`#ffbd2e`/`#28c941` but the UI-SPEC color section already locks the exact hex). Lucide icon component names verified via [CITED: lucide.dev]. `platform()` is **synchronous** per [CITED: v2.tauri.app/plugin/os-info].

### Pattern 3: `useWindowMaximized` hook

**What:** Reactive boolean reflecting whether the window is currently maximized, used to swap `Maximize2` ↔ `Minimize2` icon.

**Example:**

```tsx
// gui/src/hooks/useWindowMaximized.ts
import { useCallback, useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";

export function useWindowMaximized(): boolean {
  const [isMax, setIsMax] = useState(false);

  const update = useCallback(async () => {
    try {
      setIsMax(await getCurrentWindow().isMaximized());
    } catch {
      // Non-Tauri env (tests) — leave default false
    }
  }, []);

  useEffect(() => {
    void update();
    let unlisten: undefined | (() => void);
    (async () => {
      try {
        unlisten = await getCurrentWindow().onResized(() => { void update(); });
      } catch {
        // Non-Tauri env
      }
    })();
    return () => { unlisten?.(); };
  }, [update]);

  return isMax;
}
```

Source: pattern from Tauri discussion #5881 [CITED: github.com/tauri-apps/tauri/discussions/5881]. **Caveat:** issue #13199 reports `isMaximized()` inside event listeners can cause an infinite memory leak on macOS when used carelessly; the hook above avoids this by debouncing through React state (idempotent setState).

### Pattern 4: Drag region with double-click toggle

**What:** The center of the titlebar carries `data-tauri-drag-region` and an `onDoubleClick` handler — but **menu triggers and window controls must NOT be descendants** of this node, only siblings.

**Example:**

```tsx
// gui/src/components/CustomTitlebar.tsx — JSX skeleton
<div className="flex items-center h-9 bg-muted border-b w-full">
  <img src="/32x32.png" alt="" className="w-5 h-5 ml-2 shrink-0" />
  <span className="text-xs text-muted-foreground ml-1 select-none truncate max-w-[120px]">{projectName}</span>
  {isDirty && <span className="text-xs text-muted-foreground ml-0.5 select-none">●</span>}
  <FileMenu onUnsavedCheck={onUnsavedCheck} />
  <EditMenu />
  <ViewMenu theme={theme} setTheme={setTheme} />
  <HelpMenu />
  {/* SIBLING — must NOT contain the menus or the controls */}
  <div
    data-tauri-drag-region
    className="flex-1 h-full"
    onDoubleClick={() => void getCurrentWindow().toggleMaximize()}
  />
  <WindowControls />
</div>
```

Why sibling-not-wrapper: per Tauri issue #9901 and #9725, "the child elements of `data-tauri-drag-region` cannot trigger events" in Tauri v2. Wrapping menu triggers inside the drag region breaks their clicks. Tauri docs state explicitly: *"data-tauri-drag-region will only work on the element to which it is directly applied."* [CITED: v2.tauri.app/learn/window-customization]

### Pattern 5: View menu — submenus + radio groups (shadcn)

```tsx
// gui/src/components/ViewMenu.tsx — sketch
<DropdownMenu>
  <DropdownMenuTrigger asChild>
    <Button variant="ghost" size="sm">View</Button>
  </DropdownMenuTrigger>
  <DropdownMenuContent align="start">
    <DropdownMenuItem onClick={toggleBottomPanel}>
      {bottomPanelOpen && <Check className="h-4 w-4 mr-2" />}
      Toggle Code Preview
    </DropdownMenuItem>
    <DropdownMenuSub>
      <DropdownMenuSubTrigger>Layer</DropdownMenuSubTrigger>
      <DropdownMenuSubContent>
        <DropdownMenuRadioGroup value={activeLayer} onValueChange={(v) => setActiveLayer(v as LayerView)}>
          <DropdownMenuRadioItem value="Hydraulic">Hydraulic</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="Both">Both</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="Thermal">Thermal</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuSubContent>
    </DropdownMenuSub>
    <DropdownMenuSub>
      <DropdownMenuSubTrigger>Theme</DropdownMenuSubTrigger>
      <DropdownMenuSubContent>
        <DropdownMenuRadioGroup value={theme} onValueChange={(v) => setTheme(v as Theme)}>
          {THEME_OPTIONS.map((opt) => (
            <DropdownMenuRadioItem key={opt.value} value={opt.value}>
              <opt.icon className="h-4 w-4 mr-2" />{opt.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuSubContent>
    </DropdownMenuSub>
  </DropdownMenuContent>
</DropdownMenu>
```

Per "Specific Ideas" line in CONTEXT.md, theme list must be array-driven (`THEME_OPTIONS`) so Phase 72 can extend it. [CITED: ui.shadcn.com/docs/components/radix/dropdown-menu]

### Anti-Patterns to Avoid

- **Wrapping menus inside the drag region.** Breaks menu clicks (issue #9901). Make the drag region a sibling that takes `flex-1`.
- **Registering Edit-menu keyboard shortcuts in the menu items.** Phase 65 already registered Ctrl+Z/Y/X/C/V/D on `window.keydown` in `CanvasPanel.tsx` lines 209-272. Shadcn `DropdownMenu` does NOT auto-register accelerators from the displayed label text — putting `<DropdownMenuShortcut>Ctrl+Z</DropdownMenuShortcut>` is purely visual. No double-fire risk. The Edit menu MUST NOT add its own `window.addEventListener("keydown", …)`.
- **Calling `isMaximized()` in a `setInterval`.** Wastes CPU and triggers issue #13199 on macOS. Use `onResized` listener (Pattern 3).
- **Referring `<img src="/src-tauri/icons/32x32.png">`.** Vite cannot serve files outside the frontend root. Either (a) `cp gui/src-tauri/icons/32x32.png gui/public/32x32.png` so `<img src="/32x32.png">` works, or (b) import the image as an ES module from a frontend-reachable path. (a) is simpler.
- **Forgetting `core:window:allow-is-maximized`.** Without it, `useWindowMaximized` silently returns false forever — the Maximize/Restore icon never swaps. There is no console error; the IPC just rejects.
- **Leaving `decorations: false` and `resizable: true` without testing edge-resize on WSLg.** Issues #8519, #6609, #9053 describe broken/jittery resize on Linux frameless windows. Required UAT step.
- **Re-implementing Tab cycling inside ViewMenu.** Phase 65 already binds Tab to `cycleLayer()` in CanvasPanel.tsx line 274-285. Menu items must not register another Tab listener.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Window drag handling | Custom `mousedown` → IPC | `data-tauri-drag-region` (declarative) | Tauri intercepts at native layer; manual path only as Linux fallback |
| OS detection | `navigator.userAgent` parsing | `@tauri-apps/plugin-os::platform()` | Browser UA strings are unreliable; plugin returns canonical strings (`"macos"`, `"windows"`, `"linux"`, etc.) |
| App version | Hardcode in source | `@tauri-apps/api/app::getVersion()` | Single source of truth in `Cargo.toml`/`tauri.conf.json` |
| Maximize-state tracking | `setInterval` polling | `getCurrentWindow().onResized()` listener | Lower CPU, event-driven |
| Menu submenu UI | Hand-rolled flyout | shadcn `DropdownMenuSub` + `DropdownMenuSubTrigger` + `DropdownMenuSubContent` | Radix gives keyboard nav, focus trapping, ARIA, hover-delay; project already uses shadcn DropdownMenu elsewhere |
| About modal | Custom modal | shadcn `Dialog` | Same shadcn-Radix infrastructure the project's existing dialogs (`UnsavedChangesDialog`, `ValidationDialog`, `AutoRecoverRestoreModal`) use |
| macOS traffic light native | `tauri-plugin-decorum` / `tauri-plugin-mac-rounded-corners` | Pure CSS replica (Pattern 2) | D-14 explicitly asks for React-tier styling; plugins add Rust deps for ~30 lines of CSS savings |

**Key insight:** Every action wired by the new Edit/View menus already exists in `useStore` (verified — see "Existing Code Insights" below). This phase is plumbing + render-location, not logic.

## Runtime State Inventory

This phase is a UI restructure, **not a rename/refactor of a stored identifier**. The traditional Runtime State Inventory categories (databases, OS-registered names, secrets) do not apply — no stored string is changing.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — phase introduces no new persisted state; theme is already in localStorage via `useTheme` | none |
| Live service config | None — no external services involved | none |
| OS-registered state | The OS window title (set via `getCurrentWindow().setTitle()` in App.tsx line 313) still updates correctly with `decorations: false` (the title bar is invisible to the user but the OS taskbar still reads it). Verified safe. | none |
| Secrets/env vars | None | none |
| Build artifacts | `Cargo.lock` will gain `tauri-plugin-os` entry. `dist/` re-bake includes the new components. No stale artifacts to clean. | none |

## Common Pitfalls

### Pitfall 1: Tauri v2 silent IPC failures from missing capabilities

**What goes wrong:** `getCurrentWindow().minimize()` does nothing. No error in the DevTools console. No Rust panic.
**Why it happens:** Tauri v2's capabilities system silently rejects unauthorized IPC calls. The default `core:default` permission set does not include `allow-minimize`, `allow-toggle-maximize`, `allow-start-dragging`, or `allow-is-maximized` — they must be added explicitly.
**How to avoid:** Plan must include a single task that enumerates every permission added to `capabilities/default.json` and reviews the diff. Already-granted (lines 26-28): `set-title`, `close`, `destroy`. Need to add: `core:window:allow-minimize`, `core:window:allow-toggle-maximize`, `core:window:allow-start-dragging`, `core:window:allow-is-maximized`, `os:default`.
**Warning signs:** Buttons render but produce no visible effect; `onResized` never fires.

### Pitfall 2: `data-tauri-drag-region` swallows child clicks

**What goes wrong:** File menu opens but Edit menu doesn't, or buttons inside the titlebar are unclickable.
**Why it happens:** Tauri v2 attaches drag behavior only to the exact node carrying `data-tauri-drag-region`. Issue #9901: child elements cannot trigger events when nested under it. Issue #9725: drag-and-drop is mis-handled on Linux.
**How to avoid:** Drag region is a **sibling** of menus and window controls, never a wrapper. Use `flex-1 h-full` to make it grab the leftover horizontal space.
**Warning signs:** A menu trigger that looks correct but does not open; whole titlebar drags when clicking a button.

### Pitfall 3: WSLg edge-resize is buggy when `decorations: false`

**What goes wrong:** Window edges become unresponsive to resize cursor, or resize triggers wrong window dimensions.
**Why it happens:** Issues #8519, #6609, #9053 — frameless windows on Linux/GTK lose part or all of the resize hit area. The project runs on WSL2/WSLg, which inherits GTK's behavior.
**How to avoid:** Cannot be avoided in code — this is a Tauri/WebKitGTK limitation. UAT must verify edge-resize works on the actual WSLg target. If broken, fallback options are: (a) add a tiny invisible CSS resize gutter at each edge, (b) call `getCurrentWindow().startResizeDragging()` programmatically, (c) accept the limitation for now and revisit in Phase 72.
**Warning signs:** Cursor doesn't change to resize cursor at window edges; dragging an edge moves the whole window instead of resizing.

### Pitfall 4: `decorations: false` on macOS removes traffic lights AND the rounded-corner mask

**What goes wrong:** On real macOS, removing decorations also removes the system-provided rounded window corners. Window looks rectangular and harsh.
**Why it happens:** `decorations: false` removes the entire NSWindow chrome including the cornerMask.
**How to avoid:** Out of scope for Phase 67 (the user is on WSL2/WSLg, not macOS). If macOS support becomes a target, use `tauri-plugin-mac-rounded-corners` or set window background-color + `border-radius` on the root `<div>` with `transparent: true`.
**Warning signs:** Future macOS users report "the window has sharp corners."

### Pitfall 5: `icons/32x32.png` is unreachable from the frontend

**What goes wrong:** `<img src="/icons/32x32.png">` 404s in dev and renders a broken-image glyph.
**Why it happens:** `gui/src-tauri/icons/` is outside Vite's frontend root. Vite serves `/` from `gui/` (specifically `gui/public/` for non-imported assets and `gui/dist/` for built output).
**How to avoid:** Copy or symlink `gui/src-tauri/icons/32x32.png` into `gui/public/32x32.png` as a Phase 67 task. After the user provides the custom icon, update both locations.
**Warning signs:** Broken image in the titlebar; DevTools network tab shows 404 on `/icons/32x32.png`.

### Pitfall 6: Phase 65 keyboard listeners + menu shortcut labels are decoupled — but the input-focus guard matters

**What goes wrong:** User opens the Edit menu while a text input is focused, clicks "Copy," but nothing happens. Or user with focus in a text input presses Ctrl+C — and gets the canvas copy behavior, not the input's native copy.
**Why it happens:** Phase 65's `CanvasPanel.tsx` handler (lines 222-247) gates `copySelection`/`cutSelection`/`pasteFromClipboard`/`duplicateSelection` behind an input-focus check: when an input is focused, the Ctrl+C/X/V/D keys are passed through to the browser. **The menu items, by contrast, ALWAYS fire the store action** — they have no focus check. Net effect: clicking "Copy" in the Edit menu always copies the canvas selection regardless of focus context. This is desired behavior, but it diverges from the keyboard path.
**How to avoid:** Plan must document this asymmetry. The Edit menu items unconditionally call `useStore.getState().copySelection()` etc. There is no double-fire (the menu item is a click, not a keypress), so Phase 65's listener does not also fire. The accelerator label in the menu (`Ctrl+C`) is purely visual.
**Warning signs:** UAT shows menu Copy + keyboard Ctrl+C produce different behavior when an input is focused — that's correct, not a bug.

### Pitfall 7: `pasteFromClipboard`, not `pasteClipboard`

**What goes wrong:** Edit menu's "Paste" item compile-errors or runtime-errors as `useStore.getState().pasteClipboard is not a function`.
**Why it happens:** UI-SPEC §"Edit menu (D-10 — new)" line 207 names the action `pasteClipboard`, but the actual store action is `pasteFromClipboard` (verified in `gui/src/store/useStore.ts` line 341 and line 1964; called as `pasteFromClipboard()` in `CanvasContextMenu.tsx` line 33 and `CanvasPanel.tsx` line 258).
**How to avoid:** Plan must use `pasteFromClipboard` everywhere. Treat UI-SPEC's `pasteClipboard` as a typo and flag for the planner.
**Warning signs:** TypeScript compile error; `npm run build` fails.

### Pitfall 8: `getVersion()` is async

**What goes wrong:** `<AboutDialog>` renders `"Version [object Promise]"`.
**Why it happens:** `import { getVersion } from "@tauri-apps/api/app"` returns `Promise<string>` — not a sync string.
**How to avoid:** Resolve in a `useEffect` and store in `useState`. Show "—" or a spinner while pending.
**Warning signs:** Dialog shows `[object Promise]` or `undefined`.

### Pitfall 9: macOS traffic-light circles in the wrong order

**What goes wrong:** UAT on macOS shows the circles correct visually but the click handlers are scrambled.
**Why it happens:** Apple convention is **left-to-right: Close, Minimize, Maximize** (red, yellow, green). Window controls on Windows/Linux are right-aligned with order Min, Max, Close. Easy to get wrong when copy-pasting.
**How to avoid:** Pattern 2 above places them in the macOS order (red=Close, yellow=Minimize, green=Maximize) on the macOS branch. Sanity-check the test: the leftmost circle on macOS must close the window.
**Warning signs:** Hover colors look right but the wrong window action fires.

## Code Examples

All shown inline in Patterns 1-5 above. Key snippets summarized:

- Frameless config: `"decorations": false` in `tauri.conf.json`. [CITED: v2.tauri.app/learn/window-customization]
- Capability permissions: `core:window:allow-minimize`, `allow-toggle-maximize`, `allow-start-dragging`, `allow-is-maximized`, `os:default`. [CITED: v2.tauri.app/learn/window-customization, v2.tauri.app/plugin/os-info]
- Rust plugin register: `.plugin(tauri_plugin_os::init())`. [CITED: v2.tauri.app/plugin/os-info]
- JS API: `getCurrentWindow().minimize() / .toggleMaximize() / .close() / .isMaximized() / .onResized()`. [CITED: v2.tauri.app/reference/javascript/api/namespacewindow]
- Drag region: `<div data-tauri-drag-region className="flex-1 h-full" onDoubleClick={…} />` as a **sibling** of menus. [CITED: v2.tauri.app/learn/window-customization]
- Version: `await getVersion()` from `@tauri-apps/api/app`. [CITED: v2.tauri.app/reference/javascript/api/namespaceapp]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Tauri v1 `import { appWindow } from "@tauri-apps/api/window"` | Tauri v2 `import { getCurrentWindow } from "@tauri-apps/api/window"`; `appWindow = getCurrentWindow()` | Tauri 2.0 (Oct 2024) | App.tsx already uses the v2 pattern (line 4); consistent across phase |
| Tauri v1 `os` namespace under `@tauri-apps/api` | Tauri v2 `@tauri-apps/plugin-os` separate package + Rust plugin | Tauri 2.0 | New install required (not in current package.json) |
| Tauri v1 implicit allowlist | Tauri v2 capabilities/permissions JSON | Tauri 2.0 | Each window API needs explicit permission grant |

**Deprecated/outdated:**
- Polling `isMaximized()` via `setInterval` — superseded by `onResized()` listener (Pattern 3). Memory-leak hazard on macOS (issue #13199).
- `data-tauri-drag-region` recursive descendant inheritance (v1 behavior) — v2 applies only to the exact node carrying the attribute (issue #9901).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `@tauri-apps/plugin-os@2.x` is current and not deprecated | Standard Stack | LOW — official Tauri-org package, doc URL is canonical |
| A2 | slopcheck would not flag any of the three new packages | Package Legitimacy Audit | LOW — all three are well-known packages with extensive provenance |
| A3 | Copying `icons/32x32.png` into `gui/public/` is the simplest path; the user has no objection to a duplicated asset until they swap in the real icon | Recommended Project Structure / Pitfall 5 | LOW — duplicate is ~5 KB; one-line task to dedupe later |
| A4 | The Edit-menu items should NOT have their own input-focus guard (always-fire is correct) | Pitfall 6 | MEDIUM — if the user prefers the menu to also no-op when an input is focused, the implementation must add the same guard the CanvasPanel listener uses |
| A5 | Edge-resize on WSLg with `decorations: false` will work well enough to ship (or will degrade gracefully) | Pitfall 3 / Open Questions | MEDIUM — if it breaks badly, Phase 67 must add a CSS resize-gutter workaround or revert decorations |
| A6 | macOS traffic-light circle hex values `#ff5f57 / #ffbd2e / #28c840` (UI-SPEC) match user expectation, not the slightly different `#ff6159 / #ffbd2e / #28c941` from the aizcutei demo repo | Pattern 2 | LOW — UI-SPEC is the authoritative source; this just flags the discrepancy |
| A7 | shadcn `dialog` install (`npx shadcn add dialog`) will not conflict with existing shadcn components | Standard Stack | LOW — shadcn adds files into `gui/src/components/ui/`; no overwrites for components already installed |
| A8 | The user will not be running macOS during Phase 67 UAT, so macOS rounded-corners (Pitfall 4) can be deferred | Pitfall 4 | LOW — confirmed via STATE.md "Working branch: gui-redesign" + Phase 65 lessons referencing WSLg; macOS support is out of scope |

## Open Questions (RESOLVED)

> All five questions below were resolved in `67-CONTEXT.md` after research. Resolution markers added inline.

1. **WSLg edge-resize behavior with `decorations: false`.** — **RESOLVED: D-18 — defer.** Ship as-is; Plan 67-03 Task 4 UAT items 18-19 capture status without blocking. No CSS resize-gutter task added.
   - What we know: known buggy on Linux (Tauri issues #8519, #6609, #9053) but the severity ranges from "unusable" to "minor cosmetic."
   - What's unclear: whether the user's WSLg setup specifically lands in the "unusable" bucket or "tolerable" bucket.
   - Recommendation: Phase 67 UAT must include "drag each window edge — does the window resize correctly?" as a first-class check. If broken, the planner should pre-stage a contingency task to add a 4px transparent CSS resize-gutter or revert `decorations` for Linux only via runtime config.

2. **What does the title bar look like across virtual-desktop / window-snap workflows on WSLg?** — **RESOLVED: handled as UAT step in Plan 67-03 Task 4.**
   - What we know: WSLg windows are Wayland-presented; window snapping behavior differs from native Linux Wayland.
   - What's unclear: whether `toggleMaximize()` produces the expected "occupy the WSLg work area" behavior.
   - Recommendation: UAT step.

3. **Should the Edit menu items also honor the Phase 65 input-focus guard?** — **RESOLVED: D-19 — always-fire.** Menu items unconditionally call store actions; the Phase 65 keyboard guard remains for keypresses only.
   - What we know: Phase 65's keyboard handler in `CanvasPanel.tsx` lets Ctrl+C/X/V/D pass through to text inputs.
   - What's unclear: when a user is editing a text input and clicks the Edit menu → Copy, do they want the **canvas** copy or the **input** copy?
   - Recommendation: Match the keyboard behavior — if the active element is a text input, the menu items also pass through (default OS behavior). Or simpler: just always fire `copySelection()` and document the asymmetry. **Assumed default = always fire (A4).**

4. **About dialog GitHub URL — is the repo public yet?** — **RESOLVED: D-20 — `https://github.com/ramp-nuclear/STREAM.jl`** (user-supplied).
   - What we know: v1.0 was "Open-Source Release" per STATE.md.
   - What's unclear: actual canonical URL.
   - Recommendation: planner should pick a placeholder URL constant and flag for user confirmation before About dialog ships.

5. **Theme list extension hook.** Phase 72 will add more themes. Should Phase 67 declare `THEME_OPTIONS` array in `useTheme.ts` (centralized) or in `ViewMenu.tsx` (local)? — **RESOLVED: D-21 — centralize in `useTheme.ts` as `THEMES` const array.**
   - Recommendation: centralize in `useTheme.ts` next to `Theme` type — the type and the list are coupled.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js + npm | Build, plugin install | ✓ (Phases 59-65 all built) | (project standard) | — |
| Rust + cargo | Tauri backend rebuild after `tauri-plugin-os` add | ✓ (Phases 59-65 all built) | (project standard) | — |
| Tauri v2 CLI | `npm run tauri dev` UAT | ✓ (`@tauri-apps/cli ^2` in devDependencies, line 32 of package.json) | 2.x | — |
| WSLg | Final UAT target | ✓ (confirmed in CLAUDE.md and STATE.md) | (Linux 6.6.114.1-microsoft-standard-WSL2) | — |
| `npx shadcn` | One-time `add dialog` install | ✓ (used in prior phases per `gui/components.json` presence) | (latest) | — |

No missing or fallback dependencies. The phase is buildable on the current environment.

## Validation Architecture

> SKIPPED — `workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. Phase 67 uses manual UAT only (no automated test gates per phase requirement). Existing vitest suite stays green if components are added correctly.

That said, three lightweight automated checks the planner may add as a task (cheap, high value):

- A vitest unit test for `WindowControls.tsx` mocking `@tauri-apps/plugin-os` to return `"macos"` and `"windows"`, asserting the rendered structure differs (circles vs Lucide buttons). Mock pattern is the same one used by `AppShell` tests (mocking `lib/autoRecover` — see STATE.md note on Phase 65 Plan 08).
- A vitest unit test for `EditMenu.tsx` that clicks each menu item and asserts the corresponding store action fires.
- A vitest unit test for `ViewMenu.tsx`'s Layer + Theme radio groups round-trip — selecting `Thermal` calls `setActiveLayer("Thermal")` and the menu re-reads the new value.

Drag region, window controls, edge-resize, double-click maximize, platform detection on actual Tauri runtime, and macOS visual fidelity are all **manual UAT only** — cannot be vitested.

### Manual UAT Checklist (for the verifier)

Run `npm run tauri dev` on WSLg:
1. Window has no GTK title bar; the custom strip appears at the top.
2. Drag region (the empty center area) moves the window when dragged.
3. Double-click the drag region toggles maximize. (Tauri issue #11945 — may have minor restore artifacts; document if observed.)
4. Each window-control button performs its action: Minimize → window minimizes, Maximize/Restore → toggles, Close → fires the existing unsaved-changes guard.
5. Maximize icon swaps to Restore icon when window is maximized.
6. Edge-resize: cursor changes to resize cursor on all four edges and four corners; dragging resizes. **HIGH RISK on WSLg — Pitfall 3.**
7. File menu: New / Open / Save / Save As behave as before (regression check).
8. Edit menu: Undo (Ctrl+Z), Redo (Ctrl+Y), Cut, Copy, Paste, Duplicate each fire the corresponding store action.
9. View menu: Toggle Code Preview check mark reflects `bottomPanelOpen`. Layer submenu radio selection mirrors the secondary strip ToggleGroup. Theme submenu changes light/dark/system.
10. Help menu: About dialog opens, shows version (matches `tauri.conf.json` version `"0.1.0"`).
11. Project name shows current `.scp` basename without extension; dirty dot `●` appears after unsaved edits, disappears on Save.
12. App icon displays at 20px in the leftmost position (placeholder `32x32.png`).
13. Secondary strip (32px) has Layer toggle, Code button, Export button — no ThemeMenu visible.
14. Resizing the window to minimum (800×600 per `tauri.conf.json`) does not break the titlebar layout (menus + drag region + controls all visible).

## Project Constraints (from CLAUDE.md)

CLAUDE.md is STREAM.jl-centric (file structure rules, MTK patterns, Julia daemon). It does **not** constrain GUI/Tauri work directly. Two general directives apply:

- **Branching:** "GSD must never create its own branches." The working branch `gui-redesign` is already active. No `gsd/*` branch creation. `git.branching_strategy = "none"` in config.json — leave it.
- **No back-compat shims during heavy dev:** From MEMORY.md `feedback_no_back_compat_during_heavy_dev`. Phase 67 changes the GUI shell — no need to keep the old `Toolbar.tsx` exports working. Delete or rename freely (D-02 grants this discretion).

## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 through D-17, copied verbatim from 67-CONTEXT.md)

- **D-01:** Two-strip layout: 36px titlebar (`h-9`) + 32px secondary strip (`h-8`), both full-width, with `border-b` between them. Both `bg-muted`. Titlebar contents L→R: app icon (~20px) → project name → dirty dot → File/Edit/View/Help → `data-tauri-drag-region` (`flex-1`) → window controls (right).
- **D-02:** `Toolbar.tsx` is the primary refactor target — split into two new strips. Repurpose or replace. Outside the `flex flex-1 min-h-0` row.
- **D-03:** `ThemeMenu.tsx` is eliminated as a standalone component — items move into View → Theme submenu.
- **D-04:** `"decorations": false` in `app.windows[0]` of `tauri.conf.json`. No other config changes.
- **D-05:** App icon = `icons/32x32.png` at ~20px via `<img>`.
- **D-06:** Project name from `currentFilePath` — basename without extension; `"Untitled"` if dirty+unsaved; empty/blank if clean+unsaved. Dirty dot `●` immediately after.
- **D-07:** Drag region is `flex-1`, takes empty center, with `onDoubleClick → toggleMaximize`.
- **D-08:** Edit/View/Help keyboard shortcuts shown in menu items only — no separate registration (Phase 65 already registered them).
- **D-09:** File menu unchanged: New (Ctrl+N) / Open… (Ctrl+O) / Save (Ctrl+S) / Save As… (Ctrl+Shift+S).
- **D-10:** Edit menu items: Undo (Ctrl+Z) / Redo (Ctrl+Y) / sep / Cut / Copy / Paste / Duplicate / sep / Preferences… (disabled stub). Wires to existing Phase 65 store actions.
- **D-11:** View menu: Toggle Code Preview / Layer submenu (Hydraulic|Both|Thermal) / Theme submenu (Light|Dark|System). Layer radio binds to `activeLayer` (same slice as secondary strip).
- **D-12:** Help menu: About STREAM Composer (dialog) / Keyboard Shortcuts (disabled stub).
- **D-13:** Window controls always on right.
- **D-14:** Platform-specific visuals: macOS = three traffic-light circles, dim at rest, colored on hover. Windows/Linux = Lucide `Minus`/`Maximize2`/`X` buttons, Close hover red, Min/Max hover `bg-muted-foreground/20`.
- **D-15:** API calls: `getCurrentWindow().minimize() / toggleMaximize() / close()` from `@tauri-apps/api/window`.
- **D-16:** Secondary strip contents L→R: Layer toggle / Code preview toggle / Export. ThemeMenu removed from here.
- **D-17:** Secondary strip full-width, immediately below titlebar in the root `flex flex-col`. NOT scoped to center column.

### Claude's Discretion

- Exact component file names and locations (e.g., `CustomTitlebar.tsx`, `SecondaryToolbar.tsx`)
- Whether to keep `Toolbar.tsx` as the renamed secondary strip file or delete it and create a new file
- CSS for the macOS circle buttons at rest (dim factor, exact circle size, border)
- The "About" dialog implementation (shadcn `Dialog` is the obvious choice)
- Whether `platform()` is called once on mount (stored in component state) or at render time

### Deferred Ideas (OUT OF SCOPE)

- Extended theme palette beyond Light/Dark/System (Phase 72 — but build the theme list array-driven so Phase 72 doesn't have to refactor).
- Custom app icon + taskbar icon asset (user will provide).
- Keyboard Shortcuts content (Phase 72 — Phase 67 ships a disabled stub).
- Preferences dialog content (Phase 72 — Phase 67 ships a disabled stub).

## Existing Code Insights (verified)

### Reusable assets (already in `useStore`)

| Action | Store member | Verified location |
|--------|--------------|------------------|
| Undo | `undo()` | `gui/src/store/useStore.ts:945` |
| Redo | `redo()` | `gui/src/store/useStore.ts:986` |
| Cut | `cutSelection()` | `gui/src/store/useStore.ts:340` |
| Copy | `copySelection()` | `gui/src/store/useStore.ts:339` |
| **Paste** | **`pasteFromClipboard()`** (NOT `pasteClipboard` as in UI-SPEC) | `gui/src/store/useStore.ts:341, 1964` |
| Duplicate | `duplicateSelection()` | `gui/src/store/useStore.ts:342` |
| Toggle Code Preview | `toggleBottomPanel()` | `gui/src/store/useStore.ts` (referenced in Toolbar.tsx:33) |
| Bottom panel open state | `bottomPanelOpen` | `gui/src/store/useStore.ts:813` |
| Active layer | `activeLayer` | `gui/src/store/useStore.ts:213` |
| Set active layer | `setActiveLayer(layer)` | `gui/src/store/useStore.ts:214` |
| Dirty state | `isDirty` | `gui/src/store/useStore.ts:223` |
| Current file path | `currentFilePath` | `gui/src/store/useStore.ts:224` |
| Save | `saveProject()` | from `FileMenu.tsx:19` |
| Save As | `saveProjectAs()` | from `FileMenu.tsx:20` |
| Open | `loadProject()` | from `FileMenu.tsx:21` |
| New | `newProject()` | from `FileMenu.tsx:22` |

### Existing keyboard listeners (Phase 65 — confirmed no double-fire risk)

- `gui/src/App.tsx:251` — Ctrl+N/O/S/Shift+S (file ops) on window
- `gui/src/App.tsx:274` — Ctrl+1/2/3 (left tab switcher) on window
- `gui/src/App.tsx:298` — Esc clears pinned source ids on window
- `gui/src/components/CanvasPanel.tsx:210-307` — Ctrl+Z/Y/Shift+Z (undo/redo), Ctrl+C/X/V/D (clipboard), Tab (cycle layer), Esc (clear selection) on window — **with input-focus guards on C/X/V/D**

Phase 67 adds **zero new keyboard listeners**. Menu accelerator labels are visual only — Radix DropdownMenu does not auto-register them.

### Integration site in App.tsx

The current return block (App.tsx:387-477) renders:

```tsx
<div className="flex flex-col h-screen w-screen overflow-hidden">
  <div className="flex flex-1 min-h-0">       ← outer panel row
    {!toolboxCollapsed && <left panel>}
    <div className="flex flex-col flex-1 min-w-0">
      <Toolbar … />                            ← CURRENT location of Toolbar
      <CanvasPanel … />
    </div>
    {!sidebarCollapsed && <SidebarPanel … />}
  </div>
  <BottomPanel />
</div>
```

Phase 67 must restructure to (per UI-SPEC §"App.tsx layout integration"):

```tsx
<div className="flex flex-col h-screen w-screen overflow-hidden">
  <CustomTitlebar … />          ← NEW, full-width, above the panel row
  <SecondaryToolbar … />        ← NEW (replaces Toolbar), full-width
  <div className="flex flex-1 min-h-0">       ← outer panel row, unchanged
    {!toolboxCollapsed && <left panel>}
    <div className="flex flex-col flex-1 min-w-0">
      <CanvasPanel … />                       ← Toolbar removed from here
    </div>
    {!sidebarCollapsed && <SidebarPanel … />}
  </div>
  <BottomPanel />
</div>
```

The `showUnsavedDialog` prop currently flows `App → Toolbar → FileMenu`. Post-refactor it flows `App → CustomTitlebar → FileMenu`. `theme` / `setTheme` props flow `App → CustomTitlebar → ViewMenu` (replacing the `App → Toolbar → ThemeMenu` chain).

The AutoRecover render-gate (App.tsx:372-385) must remain — `CustomTitlebar` and `SecondaryToolbar` only render once the gate resolves to `restoreCandidates.length === 0`.

## Files to Create / Modify (for pattern mapper)

### Create

- `gui/src/components/CustomTitlebar.tsx`
- `gui/src/components/SecondaryToolbar.tsx` (or repurpose `Toolbar.tsx`)
- `gui/src/components/WindowControls.tsx`
- `gui/src/components/AboutDialog.tsx`
- `gui/src/components/EditMenu.tsx`
- `gui/src/components/ViewMenu.tsx`
- `gui/src/components/HelpMenu.tsx`
- `gui/src/hooks/useWindowMaximized.ts`
- `gui/src/components/ui/dialog.tsx` (auto-generated by `npx shadcn add dialog`)
- `gui/public/32x32.png` (copy of `gui/src-tauri/icons/32x32.png`)

### Modify

- `gui/src/App.tsx` — restructure root JSX (see above); drop `<Toolbar>` from center column; mount `<CustomTitlebar>` + `<SecondaryToolbar>` at root
- `gui/src-tauri/tauri.conf.json` — add `"decorations": false` to `app.windows[0]`
- `gui/src-tauri/Cargo.toml` — add `tauri-plugin-os = "2"` under `[dependencies]`
- `gui/src-tauri/src/lib.rs` — add `.plugin(tauri_plugin_os::init())` to builder chain
- `gui/src-tauri/capabilities/default.json` — add 5 permissions
- `gui/package.json` (via `npm install @tauri-apps/plugin-os`)
- `gui/package-lock.json` (auto)
- `gui/src-tauri/Cargo.lock` (auto)

### Delete

- `gui/src/components/ThemeMenu.tsx` (D-03)
- `gui/src/components/Toolbar.tsx` (D-02 — if not reused as `SecondaryToolbar.tsx`)

## Sources

### Primary (HIGH confidence)

- [Tauri v2 Window Customization](https://v2.tauri.app/learn/window-customization/) — `decorations: false`, drag region, capability permissions, start-dragging fallback
- [Tauri v2 OS Plugin](https://v2.tauri.app/plugin/os-info/) — `platform()` is synchronous, return values enumerated, install (`Cargo.toml: "2.0.0"`, JS bindings), `os:default` permission
- [Tauri v2 Window API reference](https://v2.tauri.app/reference/javascript/api/namespacewindow/) — `getCurrentWindow()`, `minimize()`, `toggleMaximize()`, `close()`, `isMaximized()`, `onResized()`
- [Tauri v2 App API reference](https://v2.tauri.app/reference/javascript/api/namespaceapp/) — `getVersion(): Promise<string>` async signature
- [shadcn dropdown-menu](https://ui.shadcn.com/docs/components/radix/dropdown-menu) — `DropdownMenuSub`, `DropdownMenuRadioGroup` patterns
- Project files (verified by direct read):
  - `gui/package.json` — dependency versions, missing `@tauri-apps/plugin-os`
  - `gui/src-tauri/Cargo.toml` — missing `tauri-plugin-os`
  - `gui/src-tauri/capabilities/default.json` — currently grants only `set-title`, `close`, `destroy`
  - `gui/src-tauri/src/lib.rs` — currently registers `opener`, `dialog`, `fs`; needs `os`
  - `gui/src/components/Toolbar.tsx`, `FileMenu.tsx`, `ThemeMenu.tsx`, `App.tsx`, `CanvasPanel.tsx` — all read and analyzed
  - `gui/src/store/useStore.ts` — action names verified (`pasteFromClipboard` NOT `pasteClipboard`)

### Secondary (MEDIUM confidence)

- [Tauri discussion #5881 — isMaximized + onResized React pattern](https://github.com/tauri-apps/tauri/discussions/5881)
- [Tauri issue #9901 — child clicks under data-tauri-drag-region](https://github.com/tauri-apps/tauri/issues/9901)
- [aizcutei/tauri_mac_traffic_light_window_demo — CSS hex values](https://github.com/aizcutei/tauri_mac_traffic_light_window_demo) — `#ff6159 / #ffbd2e / #28c941` (note: UI-SPEC uses slightly different canonical hex `#ff5f57 / #ffbd2e / #28c840`)
- [Tauri v2 Stable Release notes](https://v2.tauri.app/blog/tauri-20/)

### Tertiary (LOW confidence, flagged for UAT validation)

- [Tauri issue #8519 — decorations false breaks resize on Linux](https://github.com/tauri-apps/tauri/issues/8519) — issue closed but resolution comment not surfaced
- [Tauri issue #6609 — frameless resize buggy](https://github.com/tauri-apps/tauri/issues/6609)
- [Tauri issue #9053 — non-decorative resize](https://github.com/tauri-apps/tauri/issues/9053)
- [Tauri issue #11945 — double-click drag region restore size bug](https://github.com/tauri-apps/tauri/issues/11945)
- [Tauri issue #13199 — isMaximized inside event listener leaks memory on macOS](https://github.com/tauri-apps/tauri/issues/13199)
- [Tauri issue #9725 — drag-drop on Linux](https://github.com/tauri-apps/tauri/issues/9725)

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — every package documented at official Tauri/shadcn sources, all versions cross-checked against the repo's existing dependency tree
- Architecture: HIGH — integration site in App.tsx and all store action names verified by direct file read
- Pitfalls: MEDIUM — the 4-layer registration (Pitfall 1), drag-region sibling rule (Pitfall 2), and `pasteFromClipboard` naming (Pitfall 7) are HIGH-confidence. WSLg edge-resize (Pitfall 3) is LOW-confidence — only resolvable by actual UAT.
- macOS behavior: LOW — out of scope per A8, but the existing references in the research are sound if macOS becomes relevant.

**Research date:** 2026-05-16
**Valid until:** ~2026-06-15 (30 days — Tauri v2 API surface is stable; this estimate is fine unless Tauri ships a 2.x minor that adds new permissions)
