# Phase 67 — Decorations Redo Research

**Researched:** 2026-05-16
**Domain:** Tauri v2 frameless windows + native Windows chrome preservation (Aero Snap, edge resize, shadow, taskbar icon)
**Confidence:** HIGH on Tauri/Tao behavior and the plugin landscape; MEDIUM on WSLg specifics (only resolvable by UAT on a real Windows build).

---

## 1. TL;DR Recommendation

**Keep `decorations: false`. Stop hand-rolling window controls. Adopt `tauri-plugin-frame` (a maintained 2026-05 fork of `tauri-plugin-decorum`).** It is the only path that preserves Windows 11 Snap Layout (the hover-maximize feature) on a frameless Tauri v2 window, and it does so via the supported `WM_NCHITTEST` / `HTMAXBUTTON` mechanism — no key-simulation, no `WS_THICKFRAME` games. Aero Snap (drag-to-edge) and edge resize are **already preserved by Tao upstream** (PR #110, merged 2021) for any `decorations: false` window; that mechanism keeps working on Tauri v2 unchanged.

The WSLg taskbar penguin and missing window border are **not a Tauri problem and not solvable in this phase** — they are WSLg-side limitations (microsoft/wslg#614, #944, #1382). Treat WSLg as "best-effort dev surface, ship target is Windows native" and validate the real fix on a Windows-native `tauri build` artifact.

**Action shape:** add `tauri-plugin-frame = "1.1.7"` to `Cargo.toml`, register it in `lib.rs`, remove the hand-rolled `WindowControls.tsx` (or downgrade it to a no-op on Windows), keep `data-tauri-drag-region` as today. Estimated effort: **2–3 hours.**

---

## 2. VSCode's Mechanism (Context)

VSCode achieves the look the user wants via Electron's `BrowserWindow` options:

- `titleBarStyle: 'hidden'` + `titleBarOverlay: { color, symbolColor, height }` on Windows/Linux. This is **not** `frame: false`. The native frame stays — only the title text bar is hidden, and Chromium re-renders **OS-native min/max/close** in an overlay rectangle that the page must avoid via the `env(titlebar-area-*)` CSS variables. ([Electron docs](https://www.electronjs.org/docs/latest/tutorial/custom-title-bar))
- On macOS, `titleBarStyle: 'hidden'` alone is enough because NSWindow already supports a hidden title with visible traffic lights.

Why this gives them everything: the native window class is still `WS_CAPTION | WS_THICKFRAME`, so DWM keeps drawing shadow, the WM keeps doing edge-resize and Snap, the taskbar keeps the correct icon — **only the title strip is gone and is drawn by the renderer instead.** Crucially, the min/max/close buttons themselves are still **OS-painted**, so Snap Layout hover (Win+Z picker) works for free.

Tauri v2 has no equivalent of `titleBarOverlay`. The closest equivalents are: (a) the OS-native edge-resize + Aero Snap that Tao already preserves on `decorations: false`, and (b) the `WM_NCHITTEST`/`HTMAXBUTTON` overlay trick used by `tauri-plugin-frame` to bring back Snap Layout. There is no path in Tauri v2 to keep the native min/max/close buttons while removing the title text — you either get the whole native frame, or you draw them yourself. [VERIFIED via tauri-apps/tauri#9458 — request is open, status: upstream, no maintainer-proposed alternative.]

---

## 3. Tauri v2 Native Support — What Exists, What Doesn't

### What exists

| Capability | How |
|---|---|
| Remove window chrome | `decorations: false` in `tauri.conf.json` (current state of this project) |
| Drag region | `data-tauri-drag-region` HTML attribute |
| Aero Snap (drag-to-edge) with `decorations: false` | **Already works.** Tao PR #110 (merged 2021) added a `WM_NCHITTEST` handler that returns the correct edge constants from a borderless window, and a `WM_NCCALCSIZE` handler that keeps maximized borderless windows out of the taskbar. This carries into Tauri v2. [CITED: tauri-apps/tao commit f35dd03] |
| Edge resize with `decorations: false` | Same PR #110. The cursor changes and the system handles the drag. [CITED: tauri-apps/tao#103 / PR #110] |
| macOS hidden title bar with traffic lights | `app.windows[*].titleBarStyle: "Overlay"` or `"Transparent"` + `hiddenTitle: true` |
| Programmatic resize/drag | `window.startResizeDragging()`, `window.startDragging()` |
| Set window title (taskbar text) | `window.setTitle()` — already used at `App.tsx:313` |

### What doesn't exist in Tauri v2 schema

| Looked for | Result |
|---|---|
| `titleBarStyle` on Windows | **macOS-only** per docs and schema. No Windows variant. [CITED: v2.tauri.app/learn/window-customization] |
| `titleBarOverlay` equivalent (Electron-style) | **Does not exist.** Open feature request: tauri-apps/tauri#9458, status `upstream`. No native min/max/close overlay path. |
| `extendsContentIntoTitleBar` | **Does not exist** in Tauri v2. v1 had a similar idea on macOS only; v2 replaced it with `titleBarStyle`. |
| `WS_THICKFRAME` / `WS_CAPTION` toggle | **Not exposed.** Tao chose the `WM_NCHITTEST`-only route in PR #110, so the class style isn't user-tunable. |
| Native Windows 11 Snap Layout (hover-to-snap-picker) with `decorations: false` | **Not built-in.** Open feature request: tauri-apps/tauri#4531, status `upstream`. **Only third-party plugins (`tauri-plugin-frame`) provide this.** |
| Native window border drawn by DWM with `decorations: false` | **Lost.** With Tao's hit-test-only fix, the OS does not draw a 1px frame and DWM doesn't extend the client. You either accept the borderless look or restore it in CSS (1px outline) — there is no equivalent of `DwmExtendFrameIntoClientArea` exposed by Tauri/Tao. |

### Net consequence for Phase 67's current state

The Tauri config already has `decorations: false`. **Aero Snap (drag-to-edge) and edge resize should already work on a Windows-native build** — this contradicts the assumption written into 67-CONTEXT.md D-18. The likely reason the user thinks they're broken is that **the user is testing on WSLg, where window manager behavior is determined by Weston, not by anything Tao does.** The fix is to validate on a Windows-native build, not to change config.

What is *genuinely* missing on Windows-native with the current setup:

- **Windows 11 Snap Layout** (the hover-maximize picker) — `tauri-plugin-frame` is required.
- **Native shadow / 1px border** — not provided. Either accept it or add a CSS outline.
- **Native taskbar icon binding for `tauri dev`** — see §7.

---

## 4. `tauri-plugin-decorum` Deep Dive

### What it does

The Rust crate is small — `src/lib.rs` is ~150 LOC. The Windows path does exactly two things:

1. `self.set_decorations(false)?` — same as setting it in the config.
2. On `on_page_load`, `eval()`s an injected `controls.js` that does `document.createElement` to draw three Segoe-Fluent-Icons buttons inside whatever element the page marks with `data-tauri-decorum-tb`. The buttons call `getCurrentWindow().minimize()` / `toggleMaximize()` / `close()` and `invoke('plugin:decorum|show_snap_overlay')` for a "Win+Z" simulation.

**That's it.** There is no `WM_NCHITTEST` handler. There is no `WS_THICKFRAME` manipulation. There is no native overlay HWND. **The "preserves Windows Snap Layout" claim in the README is overstated:** Snap Layout (the *hover-maximize picker*) is NOT preserved by Decorum on Windows — only the **Win+Z keyboard overlay** is invokable via the plugin's `show_snap_overlay` command, and that's done by simulating the keystroke, not via the HTMAXBUTTON path that Windows expects. [VERIFIED: read of `src/lib.rs` and `src/js/controls.js` via GitHub API.]

The good news: Aero Snap drag-to-edge **does work** under Decorum, because Tao's PR #110 fix handles it independently of the plugin.

### Project health

| Signal | Value | Source |
|---|---|---|
| Stars | 311 | GitHub API |
| Open issues | 11 (incl. one labeled "decorations is blank when initializing the application, and it returns to normal after using any function" — #50, Aug 2025, open) | GitHub API |
| Last commit | **2025-08-08** (~9 months stale) | GitHub API |
| Maintenance status | "mostly in maintenance mode" per maintainer interview | dev.to interview |
| Stable Snap Layout? | **No** — only Win+Z simulation, not HTMAXBUTTON | source read |
| Frontend API | Injected JS only (no `@tauri-apps/plugin-decorum` npm). CSS hooks: `#decorum-tb-minimize`, `#decorum-tb-maximize`, `#decorum-tb-close`, `div[data-tauri-decorum-tb]` |
| `data-tauri-drag-region` interaction | None — Decorum draws buttons inside `data-tauri-decorum-tb`; you still need your own drag region |
| Tauri v2 support | Yes |
| `withGlobalTauri: true` required | **Yes** — uses `window.__TAURI__`. Not currently set in this project's `tauri.conf.json`. |

### Disposition

**Do not adopt Decorum.** Reasons:
1. Issue #50 (blank window on startup until first interaction) is open and would hit this project hard — the app shell renders immediately on launch.
2. Snap Layout is *not* truly preserved; the README oversells it.
3. Maintenance has slowed.
4. The fork — `tauri-plugin-frame` — fixes both of these and is actively developed.

---

## 4b. `tauri-plugin-frame` Deep Dive (the real recommendation)

**Repo:** github.com/clarifei/tauri-plugin-frame
**Crate:** `tauri-plugin-frame = "1.1.7"` (published 2026-05-15, one day before this research)
**Last commit:** 2026-05-15
**Authors:** Siddharth (original Decorum author) + clarifei
**License:** MIT
**Lineage:** Forked from `tauri-plugin-decorum`, then rewritten with real Win32 work.

### What it actually does on Windows (verified by source read)

`src/snap.rs` uses `windows-sys` and does the following:

1. **Creates a child overlay HWND** (`WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_OVERLAPPED`) positioned exactly over the custom Maximize button (using `SetWindowPos` with current titlebar height + button width + DPI awareness via `GetDpiForWindow`).
2. **Subclasses the parent window** via `SetWindowSubclass` with a custom `parent_subclass_proc`. The overlay HWND's own WndProc returns `HTMAXBUTTON` from `WM_NCHITTEST` — **the exact return value Windows 11's shell looks for to trigger the Snap Layout flyout on hover**. No keypress simulation. No Win+Z.
3. **Forwards `WM_NCLBUTTONDOWN`/`WM_NCLBUTTONUP` / `WM_NCMOUSEMOVE` / `WM_NCMOUSELEAVE`** through `TrackMouseEvent` with `TME_NONCLIENT | TME_LEAVE` and re-emits them as Tauri events (`tauri-frame://snap/mouseenter`, `mouseleave`, `mousedown`, `mouseup`, `click`, `mousemove`) so the frontend can mirror hover/press styles.
4. **Auto-injects** `js/titlebar.js` and `js/controls.js` on `on_page_load` that mounts buttons + sets `--tauri-frame-controls-width` CSS variable.
5. **DPI re-position** on `WM_DPICHANGED` and `WM_SIZE`.

[VERIFIED by reading `src/snap.rs` and `src/lib.rs` via GitHub API.]

### What it DOES preserve

| Behavior | Preserved? | Mechanism |
|---|---|---|
| Aero Snap (drag-to-edge) | Yes | Tao PR #110 (independent of this plugin) |
| Edge resize | Yes | Tao PR #110 |
| Windows 11 Snap Layout (hover maximize → picker) | **Yes — natively, via HTMAXBUTTON** | This plugin |
| Native min/max/close button visual chrome | No — replaced with HTML buttons styled by Segoe Fluent Icons font |
| Native shadow | No (lost with `decorations: false`) |
| 1px border | No (lost with `decorations: false`) |
| Taskbar icon | Unaffected — plugin doesn't touch icon plumbing |

### Project health

| Signal | Value |
|---|---|
| Stars | 40 (new — forked recently) |
| Open issues | 0 |
| Last push | 2026-05-15 (yesterday) |
| Snap Layout via HTMAXBUTTON | **Yes — source-verified** |
| Tauri v2 | Yes |
| Required permissions | `core:window:allow-close/center/minimize/maximize/set-size/set-focus/is-maximized/start-dragging/toggle-maximize` — most already in this project's `capabilities/default.json` |
| Requires `withGlobalTauri: true`? | **No** (improvement over Decorum). |
| Frontend API | Auto-injected — but pure CSS hooks: `[data-tauri-frame-tb]`, `#frame-tb-minimize`, `#frame-tb-maximize`, `#frame-tb-close`, and `--tauri-frame-controls-width` CSS var |

### Tradeoffs to flag

1. **Loss of the project's CustomTitlebar.tsx visual control.** The plugin auto-injects its own buttons. The project's existing `WindowControls.tsx` becomes redundant on Windows. Two options: (a) delete `WindowControls.tsx` and accept the plugin's button look (Segoe Fluent Icons — looks right on Windows), styled via CSS overrides; or (b) configure `snap_overlay(false)` and `auto_titlebar(false)`, then use only the overlay HWND piece — but the plugin doesn't expose that decomposition cleanly. Path (a) is the supported one.
2. **Windows-only.** On WSLg/Linux the plugin is a no-op — you fall back to the current `WindowControls.tsx`. The platform branch already exists in this project's component (D-14), so this is fine; just gate by `platform()`.
3. **Author overlap.** Both Decorum and Frame are authored by the same person (Siddharth, plus a co-maintainer clarifei). Frame is essentially "what Decorum should have been on Windows."
4. **Newness.** 40 stars, 1 day since last release. Low community validation. **slopcheck would flag this as [SUS]** — register a `checkpoint:human-verify` task before install.

### Verdict

**Recommended.** It is the only production-ish path to real Windows 11 Snap Layout on a Tauri v2 frameless window. Pin to `=1.1.7` (exact version), audit the lock file, and gate the install behind a human-verify checkpoint.

---

## 5. Manual Win32 Path (only if plugins are rejected)

If the user rejects third-party plugins, the manual path is **substantial** but well-trodden.

### What it requires

1. `windows-sys = { version = "0.61", features = ["Win32_Foundation", "Win32_UI_WindowsAndMessaging", "Win32_UI_Input_KeyboardAndMouse", "Win32_UI_HiDpi", "Win32_Graphics_Dwm", "Win32_Graphics_Gdi", "Win32_System_LibraryLoader", "Win32_UI_Shell"] }` in `Cargo.toml`.
2. In `lib.rs` `setup`, get the HWND from `window.window_handle()` (Tauri v2 returns a `raw_window_handle::RawWindowHandle::Win32`).
3. **Subclass the WndProc** via `SetWindowSubclass`. Handle:
   - `WM_NCCALCSIZE` (wparam = TRUE): set the rgrc[0] to extend client area to the full window — needed if you want the native 1px border back via DWM. Skip this if you don't want a border.
   - `WM_NCHITTEST`: only needed if you want a custom Snap Layout HTMAXBUTTON hover. **Tao already returns the correct edge constants for resize** — you do NOT need to re-implement edge hit testing.
   - `DwmExtendFrameIntoClientArea(hwnd, &MARGINS{1,1,1,1})`: restore the native shadow + 1px aero frame. Call once in `WM_CREATE` or right after window creation.
4. Optional: child overlay HWND over the Maximize button returning HTMAXBUTTON (the Snap Layout flyout trigger). This is what `tauri-plugin-frame` does — ~250 LOC of Rust.

### LOC and complexity

- Just restoring shadow + native border: **~50 LOC Rust** (a single `DwmExtendFrameIntoClientArea` call + a small `WM_NCCALCSIZE` handler).
- Add Snap Layout HTMAXBUTTON child overlay: **+200 LOC** (this is what Frame contains).
- Add WSLg/Linux conditional compilation: trivial (`#[cfg(target_os = "windows")]`).

### Canonical examples

- **Catch22 "Custom Titlebar"** (Win32 article, not Tauri-specific) — the canonical reference for `WM_NCCALCSIZE` + `WM_NCHITTEST` + DWM frame extension. [CITED: catch22.net/tuts/win32/custom-titlebar]
- **tauri-plugin-frame `src/snap.rs`** — read it as a Tauri-flavored example of the HTMAXBUTTON overlay pattern. ~250 LOC, all current best practices (windows-sys 0.61, raw-window-handle 0.6, DPI-aware, subclass cleanup).
- **window-shadows crate** — a 3-line Rust addition (`window_shadows::set_shadow(&window, true)`) that does just the DwmExtendFrameIntoClientArea piece. Used by [blog.elijahlopez.ca/posts/tauri-custom-titlebar/]. Note: maintained but Tauri-v1-era; works with v2 if the API is plumbed manually.

### Verdict

**Not recommended unless the plugin is explicitly rejected.** Maintaining ~250 LOC of unsafe Rust + windows-sys for a feature `tauri-plugin-frame` already provides is a poor trade. If the user wants only the shadow/border (no Snap Layout picker), 50 LOC + `window-shadows` is reasonable.

---

## 6. WSLg Reality Check

### The hard truth

**WSLg is not Windows.** It is Wayland/Weston tunneled to the Windows compositor. The following Windows behaviors **do not exist on WSLg regardless of what Tauri or any plugin does**, because the window manager is different:

| Windows-native feature | WSLg behavior |
|---|---|
| Aero Snap (drag-to-edge) | Not Weston-implemented; the WSLg-side compositor doesn't honor `WM_NCHITTEST` returns the way Windows does. Drag-to-edge may move the window into a corner but won't snap. |
| Windows 11 Snap Layout | Definitively absent — this is a Windows 11 shell feature with no Linux equivalent. |
| Native DWM shadow / 1px border | Absent — there is no DWM behind WSLg windows; the per-window border is whatever the Linux WM provides (none for `decorations: false`). |
| Native edge resize cursor | Tao's hit-test path runs in the Tauri/Tao process, so the cursor *does* change — but actual resize behavior under WSLg has been flaky (Tauri issues #8519, #6609, #9053). |
| Native minimize-to-taskbar animation | Replaced with WSLg's generic minimize animation. |
| App-specific taskbar icon | **Generic penguin** in many WSLg configurations — see §7. |

### Best-case behavior with `decorations: false` on WSLg

Today (current Tauri 2 + WebKitGTK on WSLg):
- Window opens with no chrome at all.
- Drag region works.
- Edge resize *may* work depending on WSLg version (current users report ~75% reliability — issues #8519/#6609 sometimes return).
- No snap, no shadow, no border.
- Taskbar shows the penguin.

### Can `decorations: true` help on WSLg?

It would restore the GTK title bar — that's the **WebKitGTK-provided** titlebar, which on WSLg looks like a thin grey bar with no buttons (because WSLg/Weston doesn't render GTK CSD properly). It's worse than `decorations: false`, not better. **Do not flip this back.**

### Practical recommendation

- **Treat WSLg as a development convenience, not a target platform.** The user runs WSLg because their dev machine is WSL2, but the *ship* surface is `tauri build` artifacts running on Windows 11 native, where everything in §4b works correctly.
- **Validate Phase 67 changes on a Windows-native `tauri build` smoke test** — either via a `npm run tauri build` then run the binary on the Windows side, or by occasional cross-validation runs. WSLg UAT can verify "does the React layout render correctly" but cannot validate "does Aero Snap work."
- **Don't add Linux-specific contingency code** for Aero Snap or borders. The plugin is `#[cfg(target_os = "windows")]`-gated; on WSLg it's a no-op, which is correct.

---

## 7. Taskbar Icon Root Cause + Fix

### Current state of icons in this project

`gui/src-tauri/icons/`:
- `icon.png` 512×512, RGBA. md5: `3fa44209…` — **this is the default Tauri sample icon** (a stylized Tauri logo, *not* a user asset). Same for `32x32.png` (md5 `1344a8f2…`).
- `icon.ico` is a real multi-resolution ICO (16+32 px layers), 86 KB — also the Tauri default sample.

The fact that they're the default doesn't break bundling — `tauri build` will still pack them. It just means the WSLg taskbar shows "Tauri logo" by default, not "penguin," unless icon resolution fails (which it does on WSLg, see below).

### Why the WSLg taskbar shows a penguin

Three root causes documented in microsoft/wslg:

1. **microsoft/wslg#944** — WSLg looks up icons via `set_app_id` matching against the `.desktop` file at install time. `tauri dev` does not install a `.desktop` file (it just spawns the WebKitGTK window), so WSLg falls back to the "unknown" icon, which is the penguin.
2. **microsoft/wslg#614** — WSLg doesn't pick up `_NET_WM_ICON` for runtime icons reliably.
3. **microsoft/wslg#1382** — confirmed regression in WSLg 1.0.71 where task manager icons were displayed as penguin even for installed apps.

The penguin is **not** a sign that `icons/icon.png` is wrong — the dev-mode taskbar can't reach it regardless.

### What controls the taskbar icon on each surface

| Surface | Source of taskbar icon | Status in this project |
|---|---|---|
| `tauri dev` on WSLg | `_NET_WM_ICON` (set by GTK via the configured app icon) → fallback penguin | Broken at the WSLg layer, not the Tauri layer. **Cannot be fixed in Phase 67.** |
| `tauri dev` on Windows native | `icons/icon.ico` if loaded at runtime; otherwise the executable's embedded resource | Default Tauri icon — works, just not the user's brand. |
| `tauri build` on Windows native (installed) | `icons/icon.ico` embedded in the .exe resource at compile time (Tauri does this automatically from `bundle.icon`) | Will work correctly once the user supplies real icons. |
| `tauri build` on Linux native (deb/AppImage) | `icons/128x128.png` + StartupWMClass matching | Will work once user supplies icons. |

### Is there a `windowIcon` config?

No top-level `windowIcon` in Tauri v2's schema. The `bundle.icon` array is the only thing — and it's used **at build time** to write the platform-specific resources (`.ico` → exe resource on Windows, `.png` → .desktop on Linux, `.icns` → .app on macOS). There is no separate "dev-mode icon" override.

### Fix per surface

| Surface | Fix |
|---|---|
| WSLg dev penguin | **Not fixable in Phase 67.** Document as known WSLg limitation. The user's "this looks wrong" complaint about the penguin should be resolved by switching the validation surface to Windows-native, not by code changes. |
| Windows-native dev | When user supplies real icon: replace `icons/icon.ico` (multi-resolution: 16, 24, 32, 48, 64, 256 with 32 first per Tauri docs). `tauri dev` picks it up at start (some restart may be needed since icons are cached aggressively — clear `gui/src-tauri/target/debug` if stale). |
| Windows installed | Same `icon.ico` swap. `tauri build` regenerates the exe resource. |
| WSLg installed (if ever) | Replace `icons/128x128.png` and `icons/icon.png`; ensure `tauri.conf.json` `identifier` (`com.stream.composer`) matches the `.desktop` `StartupWMClass`. |

### Workaround note for `gdk-pixbuf` crashes (separate issue)

If the user hits a `gdk-pixbuf` crash on `tauri dev` (a known Linux/WSLg issue when an icon file is malformed), set `"icon": []` temporarily in `bundle`. Not applicable here yet — current icons load fine.

---

## 8. Recommendation with Concrete File Change List

### Ranked options

| Rank | Option | Effort | Snap Layout? | Aero Snap? | Edge Resize? | Shadow? | Recommendation |
|---|---|---|---|---|---|---|---|
| **1** | **`tauri-plugin-frame` v1.1.7** | 2–3 h | **Yes (HTMAXBUTTON)** | Yes (Tao default) | Yes (Tao default) | Optional CSS outline | **ADOPT** |
| 2 | Manual Win32 (subclass + DWM) | 6–10 h | Yes (~200 LOC) | Yes | Yes | Yes (`DwmExtendFrameIntoClientArea`) | Only if plugin is rejected |
| 3 | Revert to `decorations: true` | 30 min | Yes (native) | Yes | Yes | Yes | **Loses the entire Phase 67 visual goal** — kills custom titlebar. Reject. |
| 4 | `tauri-plugin-decorum` | 2 h | **No** (Win+Z fake only) | Yes (Tao default) | Yes (Tao default) | No | Reject — Frame is the maintained successor |
| 5 | Status quo (current Phase 67) | 0 | No | Yes (Tao default) | Yes (Tao default) | No | Tolerable on Windows; WSLg gaps are WSLg-side |

### Recommended path: Option 1 — adopt `tauri-plugin-frame`

#### Concrete file change list

**Modify:**

- `gui/src-tauri/Cargo.toml`
  - Under `[dependencies]`, add: `tauri-plugin-frame = "=1.1.7"` (exact pin until project trusts the version)
- `gui/src-tauri/src/lib.rs`
  - Add `use tauri_plugin_frame::FramePluginBuilder;` (or `tauri_plugin_frame::init()` for the simple form)
  - In `tauri::Builder::default()` chain, after `tauri_plugin_os::init()`, add:
    ```rust
    #[cfg(target_os = "windows")]
    let builder = builder.plugin(
        FramePluginBuilder::new()
            .auto_titlebar(true)
            .titlebar_height(36)   // matches D-01 h-9
            .button_width(46)
            .snap_overlay(true)
            .build()
    );
    ```
    (Restructure the builder chain to use `let mut builder = …;` form to allow conditional plugin registration.)
- `gui/src-tauri/capabilities/default.json`
  - Add the two missing permissions: `core:window:allow-maximize`, `core:window:allow-set-size`, `core:window:allow-set-focus`, `core:window:allow-center`. The other six (close, minimize, toggle-maximize, start-dragging, is-maximized, destroy, set-title) are already present.
- `gui/src-tauri/tauri.conf.json`
  - **Do not change** `decorations: false` — keep as today. Plugin does not require `withGlobalTauri: true` (improvement vs Decorum).
- `gui/src/components/CustomTitlebar.tsx`
  - **On Windows**: do NOT render `<WindowControls />` (the plugin auto-injects controls into a `[data-tauri-frame-tb]` element). Instead, render a container `<div data-tauri-frame-tb className="..." />` at the right-end of the titlebar where Frame's auto-injected buttons should appear.
  - Use the `--tauri-frame-controls-width` CSS variable to add `padding-right` on the drag region so it never extends under the buttons:
    ```tsx
    <div data-tauri-drag-region className="flex-1 h-full" style={{ paddingRight: 'var(--tauri-frame-controls-width, 138px)' }} ... />
    ```
  - **On macOS/Linux**: still render the existing `<WindowControls />` (since Frame is no-op on these platforms — the platform-branch from D-14 already handles this).
- `gui/src/components/WindowControls.tsx`
  - Replace the `platform === "windows"` branch with `return null;` (Frame draws the buttons). Keep the macOS traffic-light branch and the Linux Lucide-icon branch unchanged. Add a comment explaining the Windows branch is owned by `tauri-plugin-frame`.

**Add (CSS, in `gui/src/index.css` or equivalent global stylesheet):**

```css
/* Match the Phase 67 visual contract for the Frame-injected buttons */
[data-tauri-frame-tb] {
  display: flex;
  align-items: center;
  height: 100%;
}
#frame-tb-minimize, #frame-tb-maximize, #frame-tb-close {
  background-color: transparent !important;
  color: inherit;
  font-family: 'Segoe Fluent Icons', 'Segoe MDL2 Assets', system-ui;
}
```

**No changes needed:**

- `gui/src-tauri/icons/*` — taskbar icon work is deferred to when the user supplies real icons; the icon files exist and bundle correctly.
- `gui/public/32x32.png` — keep as it is (used by titlebar app-icon `<img>`, separate concern).
- `data-tauri-drag-region` pattern (D-26) — still works; Frame's overlay HWND is non-client and doesn't interfere with the drag region's mousedown handling.

**Delete: nothing.** `WindowControls.tsx` stays but its Windows branch becomes `return null`.

#### Compatibility caveats

1. **Plugin is brand new (released 2026-05-15).** Treat as `[SUS]` for slopcheck purposes — gate the install behind a `checkpoint:human-verify` task in the plan that asks the user to confirm before `cargo add`.
2. **Visual styling of the Frame-injected buttons.** They use Segoe Fluent Icons (correct on Windows 11) but the project's existing macOS traffic-light replica won't apply (and shouldn't — Frame is Windows-only). Verify the button colors via `close_hover_bg` / `button_hover_bg` builder options match the D-14 spec.
3. **Aero Snap was likely never broken on Windows in the first place.** The user's claim that "decorations: false killed Aero Snap" is rooted in WSLg testing. Re-validate on a Windows-native build before assuming a plugin is needed for Snap drag-to-edge — *only Snap Layout (the hover picker) genuinely requires Frame*.
4. **The 36px titlebar height (D-01) is unchanged.** Frame's `titlebar_height(36)` config aligns the overlay HWND with the React-side h-9 strip.
5. **D-26 (drag region as sibling, not wrapper) stays valid.** Frame doesn't change the drag region contract.

#### Estimated effort breakdown

| Task | Hours |
|---|---|
| Read Frame docs end-to-end; choose API form (builder vs init+per-window) | 0.5 |
| `Cargo.toml` + `lib.rs` plugin register + `cfg(windows)` guard | 0.5 |
| Capability JSON updates | 0.1 |
| `WindowControls.tsx` Windows branch → `return null` | 0.2 |
| `CustomTitlebar.tsx` add `[data-tauri-frame-tb]` slot + drag-region padding | 0.5 |
| Global CSS for Frame buttons + theme match | 0.5 |
| Manual UAT on Windows-native build (Aero Snap drag-to-edge, Snap Layout hover, double-click maximize, minimize, close) | 1.0 |
| **Total** | **~3 hours** |

---

## 9. VSCode-Equivalent Tauri Apps in the Wild

I searched for production Tauri v2 apps achieving custom titlebar + Windows-native chrome. The honest answer: **the ecosystem is thin.** Most Tauri apps either accept the standard window or accept the loss of Snap Layout.

### Found

1. **Micro** (siddharth99c, Decorum's author) — github.com/clearlysid/micro. Tauri v2 desktop app, Decorum-based titlebar. *Approach: tauri-plugin-decorum* (no real Snap Layout; just custom drawn buttons). Author has now moved to Frame for greenfield work.
2. **dannysmith/tauri-template** — a "production-ready Tauri v2 template" featured in the search results. *Approach: ships `tauri-controls` (agmmnn) — CSS-only, no Snap Layout, no Win32.* Pragmatic compromise.
3. **agmmnn/tauri-controls** — 949 stars, the most popular community option. *Approach: pure frontend (React/Solid/Vue/Svelte components) that mimic native control look. Explicitly **does not** preserve Snap Layout — open issue #26 acknowledges it.* This is what most apps land on when they don't need the hover picker.

### Not found

I could not surface a single high-profile Tauri v2 app on GitHub that achieves **both** custom titlebar **and** Windows 11 Snap Layout via HTMAXBUTTON. `tauri-plugin-frame` exists precisely because nobody had bridged that gap before — which is why the recommendation is to use Frame despite its newness.

### What this means

Tauri's frameless story is roughly **3 years behind Electron's `titleBarOverlay` maturity.** The official Tauri team's open issues (#9458, #4531) and the lack of a `windowControlsOverlay` schema field both indicate this is acknowledged but not roadmapped. The honest answer to "how do I get VSCode's window in Tauri" is: **you don't quite — you get 90% of it via Frame, and the missing 10% (native min/max/close button visuals + free Snap Layout button) requires either Frame's HTMAXBUTTON overlay trick or accepting that the controls are HTML-rendered.**

---

## Source Hierarchy

### Primary (HIGH confidence)
- [Tauri v2 Window Customization docs](https://v2.tauri.app/learn/window-customization/) — official, current.
- [Tauri-apps/tao commit f35dd03 — Aero Snap fix for borderless windows](https://github.com/tauri-apps/tao/commit/f35dd03dc6f15d51fb348c6b404c195ba2401339)
- [tauri-plugin-frame source code](https://github.com/clarifei/tauri-plugin-frame/blob/main/src/snap.rs) — read in full via GitHub API
- [tauri-plugin-frame README](https://github.com/clarifei/tauri-plugin-frame/blob/main/README.md) — read in full via GitHub API
- [tauri-plugin-decorum source code](https://github.com/clearlysid/tauri-plugin-decorum/blob/main/src/lib.rs) — read in full via GitHub API
- [Electron BrowserWindow titleBarOverlay docs](https://www.electronjs.org/docs/latest/tutorial/custom-title-bar)

### Secondary (MEDIUM)
- [Tauri-apps/tauri#9458 — Custom Titlebar with native Window-Controls feat request](https://github.com/tauri-apps/tauri/issues/9458) (status: upstream, open)
- [Tauri-apps/tauri#4531 — Snap layouts support feat request](https://github.com/tauri-apps/tauri/issues/4531) (status: upstream, open)
- [Tauri-apps/tauri#12042 — decorations:false inconsistent on macOS/Windows](https://github.com/tauri-apps/tauri/issues/12042) (open, needs triage)
- [clearlysid/tauri-plugin-decorum#50 — blank window on Windows initialization](https://github.com/clearlysid/tauri-plugin-decorum/issues/50) (open)
- [Tauri Custom Titlebar (React) — Elijah Lopez](https://blog.elijahlopez.ca/posts/tauri-custom-titlebar/) — window-shadows crate reference
- [Catch22 — Custom Titlebar (Win32 canonical)](https://www.catch22.net/tuts/win32/custom-titlebar/)

### Tertiary (LOW — WSLg-side, contextual)
- [microsoft/wslg#614 — WSLg doesn't pick up actual icons](https://github.com/microsoft/wslg/issues/614)
- [microsoft/wslg#944 — generic Linux icons in WSL taskbar](https://github.com/microsoft/wslg/issues/944)
- [microsoft/wslg#1382 — task manager penguin regression](https://github.com/microsoft/wslg/issues/1382)
- [agmmnn/tauri-controls](https://github.com/agmmnn/tauri-controls) — 949★, frontend-only approach
- [agmmnn/tauri-controls#26 — Snap Layout limitation](https://github.com/agmmnn/tauri-controls/issues/26)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| B1 | Tao PR #110's Aero Snap fix carries cleanly into Tauri v2 with `decorations: false` (no regression in 2024–2026) | §3, §6 | MEDIUM — if Aero Snap is actually broken on current Tauri v2, the plan must add a Tao-version pin or Win32 reimplementation. Validate on Windows-native build. |
| B2 | `tauri-plugin-frame` v1.1.7 works on a fresh `cargo add` against the current `tauri = "2"` and `tauri-plugin-os = "2"` already in this project | §4b, §8 | LOW–MEDIUM — plugin uses `windows-sys 0.61` which is current; `raw-window-handle 0.6` which is what Tauri v2 uses. Slopcheck-flag-but-build-clean is the likely outcome. |
| B3 | The user's WSLg penguin is the microsoft/wslg#944 fallback, not a Tauri icon-bundle bug | §7 | LOW — confirmed by the wslg issue tracker and by the fact that this project's icons load fine on Windows-native bundling. |
| B4 | `data-tauri-drag-region` does not conflict with Frame's overlay HWND (overlay is non-client, drag region is client-area) | §8 | LOW — verified by reading Frame's snap.rs (overlay is WS_CHILD with non-client message routing). |
| B5 | The user is OK swapping the hand-rolled `WindowControls.tsx` Windows branch for Frame's auto-injected buttons (Segoe Fluent Icons styled by CSS overrides) | §8 | MEDIUM — if the user wants pixel-perfect control of the Windows button visuals, they may prefer Option 2 (manual Win32) instead. Surface this in discuss-phase. |

---

## RESEARCH COMPLETE
