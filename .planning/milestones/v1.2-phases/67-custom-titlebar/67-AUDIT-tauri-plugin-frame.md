# Security & Correctness Audit — `tauri-plugin-frame` v1.1.7

**Auditor:** Claude (Opus 4.7), invoked by user from Phase 67 chrome gap-closure
**Date:** 2026-05-16
**Audited commit:** `3cac206caa1505781ba8ead75593bd45f9dd23a2` (`main` HEAD as of 2026-05-15 09:51 UTC)
**Audited crate version:** `tauri-plugin-frame = "1.1.7"` on crates.io (published 2026-05-15)
**Source URL:** https://github.com/clarifei/tauri-plugin-frame
**Audit scope:** Full source read + git history + dependency chain + distribution + behavior verification against claimed mechanism.

---

## 1. TL;DR Verdict

**ADOPT-WITH-CAVEATS.** The plugin is a clean, narrowly-scoped fork of the established `clearlysid/tauri-plugin-decorum` plugin. It implements exactly the mechanism we want (a child overlay HWND that returns `HTMAXBUTTON` from `WM_NCHITTEST`, triggering the Win11 shell's Snap Layout flyout). No network code, no filesystem code, no process spawning, no dynamic loading, no `postinstall` scripts, and zero added Tauri capabilities. The only Win32 surface is `windows-sys` (Microsoft-authored). All `unsafe` is the unavoidable Win32 FFI surface and is locally sound. The caveats are about **freshness and ecosystem proof**, not about confirmed flaws.

If you do **not** want to depend on a 1-day-old release from a 1-developer fork, the "Write our own" sketch in §10 is ~120 LOC of Rust — small enough to vendor without ongoing burden.

---

## 2. Repo Inventory

| File | LOC | Purpose |
|---|---|---|
| `Cargo.toml` | 25 | Crate manifest (5 direct deps total) |
| `build.rs` | 5 | Stock `tauri_plugin::Builder::new(&[]).build()` — no commands registered |
| `src/lib.rs` | 248 | `FramePluginBuilder`, plugin registration, JS-script templating |
| `src/snap.rs` | 380 | The native overlay HWND + WM_NCHITTEST handler (the load-bearing file) |
| `src/desktop.rs` | 91 | `WebviewWindowExt::create_overlay_titlebar` (opt-in helper) |
| `src/error.rs` | 35 | `eyre::Report`-wrapping error type |
| `src/js/titlebar.js` | 27 | Injected JS — creates a 32px `<div data-tauri-drag-region>` strip |
| `src/js/controls.js` | 151 | Injected JS — creates min/max/close `<button>` elements |
| `guest-js/index.ts` | 2 | Empty (just a comment — no JS API surface) |
| `permissions/default.toml` | 5 | **`permissions = []`** — no Tauri capabilities required |
| `rollup.config.js` | 31 | TS→ESM/CJS bundle config |
| `package.json` | 33 | NPM manifest — no `postinstall`/`preinstall`/`install` hooks |
| `.github/workflows/audit.yml` | 33 | Daily `rustsec/audit-check` on Cargo.lock |
| `.github/workflows/clippy.yml` | 34 | rustfmt + `clippy -D warnings` on `windows-latest` |

**Total source LOC (Rust + JS + TS):** **939** (`src/` + `guest-js/` + `build.rs`).
**Cargo.lock entries:** 395 distinct crates (typical Tauri v2 footprint — nothing unusual added).

---

## 3. Source Audit

### 3.1 `Cargo.toml`

Direct dependencies, all mainstream:

- `tauri = "2"` — the framework itself.
- `serde = "1"` + `serde_json = "1"` — serialization, dropped into Tauri's IPC layer (no IPC commands registered, see `build.rs`).
- `eyre = "0.6"` — error reporting (no `color-eyre`, no panic handler installation).
- `raw-window-handle = "0.6"` — extracts the HWND from Tauri's window.
- `[target.'cfg(windows)']` only: `windows-sys = "0.61"` with `Win32_Foundation`, `Win32_Graphics_Gdi`, `Win32_System_LibraryLoader`, `Win32_UI_Controls`, `Win32_UI_HiDpi`, `Win32_UI_Input_KeyboardAndMouse`, `Win32_UI_WindowsAndMessaging`. All Microsoft-authored bindings.
- `[build-dependencies]`: `tauri-plugin = "2"` — Tauri's own plugin-build helper.

**No `reqwest`, `hyper`, `tonic`, `tokio::process`, `libloading`, `tempfile`, `dirs`, `winreg`, or any other crate that would imply network/FS/exec/registry/privileged access.**

### 3.2 `build.rs`

```rust
const COMMANDS: &[&str] = &[];
fn main() { tauri_plugin::Builder::new(COMMANDS).build(); }
```

Five lines. Calls Tauri's standard plugin builder with **zero registered commands**. This is significant: it means the plugin defines **no `invoke`able IPC surface**. The webview cannot call into Rust through this plugin at all — everything flows the other direction (Rust → webview via `emit`).

### 3.3 `src/error.rs`

A thin `eyre::Report` wrapper with `Serialize`. Nothing unusual.

### 3.4 `src/lib.rs`

`FramePluginBuilder` exposes six tunables (titlebar height, button width, auto-titlebar, snap-overlay enable, two hover-bg colors). All stored in module-level atomics / `OnceLock` — single-init pattern. The two hover-bg colors are user-controlled strings interpolated into the injected JS via `String::replace` on placeholder substrings (`"rgba(196,43,28,1)"` and `"rgba(0,0,0,0.2)"`).

**Possible XSS-shaped concern (NOT exploitable as configured):** The hover-bg strings are passed through `String::replace` into a JS string that becomes the body of a `webview.eval(...)` call. If a caller of `FramePluginBuilder::close_hover_bg("...")` passed attacker-controlled input here, they could inject JS into their own webview. But:

1. The hover-bg values come from the **host app developer** (i.e., us), at compile-call time, not from network input.
2. Tauri's `webview.eval` runs in the same origin as our own frontend code — there's no privilege boundary being crossed.
3. The plugin doesn't expose any IPC command to change these at runtime.

**Verdict:** Not a security issue. It's a developer-ergonomics quirk — pass literal CSS strings, don't pipe user input through.

`on_page_load` callback (line 156-171): emits `frame-page-load`, optionally injects the titlebar/controls JS, optionally installs the snap overlay via `crate::snap::install_window`. This is the integration seam we'd hook into.

### 3.5 `src/snap.rs` — load-bearing file

**Mechanism (confirmed by line-by-line read):**

1. `register_class()` (line 197): Registers a Win32 window class `"TauriFrameSnapOverlay"` with `WNDPROC = overlay_proc`, `NULL_BRUSH` background (transparent). Single global registration; subsequent calls return `0` (class-already-exists) and the return is ignored — benign, since you can't have two registrations.
2. `install_hwnd()` (line 122): Calls `CreateWindowExW` with `WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_OVERLAPPED`, parent = the Tauri webview's HWND, size = (0,0,0,0) — to be positioned by `update_overlay_position`. Inserts a `SnapState` into the global `Mutex<HashMap<isize, SnapState>>`. Subclasses the parent window with `parent_subclass_proc` (so the overlay can be repositioned on `WM_SIZE`/`WM_DPICHANGED` and torn down on `WM_CLOSE`).
3. `overlay_proc` (line 281): the heart of the mechanism. On `WM_NCHITTEST`, **returns `HTMAXBUTTON as LRESULT`**. This is what the Win11 shell looks for to trigger Snap Layout. **No `Win+Z` key simulation, no `SendInput`, no `keybd_event` anywhere in the file.** (Grepped: 0 hits.) This is exactly the "right" approach — the one the broken `decorum` predecessor failed at.
4. On `WM_NCMOUSEMOVE`/`WM_NCMOUSELEAVE`/`WM_NCLBUTTONDOWN`/`WM_NCLBUTTONUP`, the overlay emits one of five Tauri events (`tauri-frame://snap/mouseenter` etc.) so the JS-side maximize button can mirror hover/press state.
5. `remove()` (line 251): removes the subclass and destroys the overlay HWND. Called on `WM_CLOSE` and via `uninstall()`.

**`unsafe` audit:** 13 `unsafe` sites, all of the form "Win32 FFI" or "wndproc callback signature":

| Line | Site | Soundness reasoning |
|---|---|---|
| 73 | `unsafe impl Send for SnapState` | Required because `HWND` is `*mut c_void`. The HWND is logically owned by Windows; the struct itself is only accessed under `Mutex<HashMap<...>>`. Sound. |
| 79, 102, 179 | `window.run_on_main_thread(\|\| unsafe { ... })` | Required because the bodies call `unsafe` functions; Tauri's `run_on_main_thread` already serializes access. Sound. |
| 122 | `unsafe fn install_hwnd` | All Win32 calls are FFI-safe. The `Box<dyn Fn>` closures are moved into `SnapState` without dangling refs. Sound. |
| 197 | `unsafe fn register_class` | Single `RegisterClassExW` call with a stack-allocated `WNDCLASSEXW`. Sound. |
| 215 | `unsafe fn module_instance` | `GetModuleHandleW(null)` — returns the EXE's HINSTANCE. Standard idiom. Sound. |
| 219 | `unsafe fn update_overlay_position` | Reads `SnapState` under the mutex, computes scaled coords, calls `SetWindowPos`. Sound. |
| 251 | `unsafe fn remove` | Idempotent — `RemoveWindowSubclass` and `DestroyWindow` are both safe to call on stale handles (return error, no crash). Sound. |
| 258 | `unsafe fn emit` | Just looks up state under the mutex and calls the closure. Sound. |
| 264, 281 | `unsafe extern "system" fn parent_subclass_proc / overlay_proc` | The `unsafe` is required by the `extern "system"` ABI for Win32 callbacks. Both callbacks acquire `SNAP_WINDOWS.lock()` and **`drop(states)` before calling `emit()`** (which re-acquires the lock) — this is the correct pattern to avoid re-entrant deadlock on the subclass chain. Sound. |
| 375 | `unsafe fn parent_for_overlay` | Locks the mutex and finds the parent HWND for a given overlay HWND by linear scan. Sound. |

**One minor correctness nit (NOT a security finding):** `register_class()` is called on every `install_hwnd()`. The class name is a fixed `&'static [u16]` so the second call is a no-op returning the already-registered atom — but the function ignores the return value. Benign. Could collide if another Tauri plugin in the same process picks the same class name `"TauriFrameSnapOverlay"`, but that's not realistic.

**Behavior on non-Windows:** `src/snap.rs` is gated behind `#[cfg(windows)] mod snap;` at the top of `lib.rs`. All Win32-specific builder methods have `#[cfg(not(windows))]` no-op stubs. **The plugin compiles and links cleanly on macOS/Linux as a pure no-op** — verified by reading the cfg gates in `lib.rs:75-184` and `desktop.rs:82-91`. Good hygiene.

### 3.6 `src/desktop.rs`

Defines `Frame<R>` (just an `AppHandle` wrapper) and `WebviewWindowExt::create_overlay_titlebar()` — the opt-in entry point that calls `set_decorations(false)` and wires up the page-load listener. For our adoption pattern (we already set `decorations: false` in `tauri.conf.json`), we'd skip this helper and call the plugin via `app.plugin(tauri_plugin_frame::FramePluginBuilder::new().auto_titlebar(false).snap_overlay(true).build())` directly. But it's fine code.

### 3.7 `src/js/titlebar.js` (27 LOC) and `src/js/controls.js` (151 LOC)

The injected frontend code. Creates a `<div data-tauri-frame-tb>` at `top:0, left:0, width:100%, height:32px, position:fixed`, with three `<button id="frame-tb-{minimize,maximize,close}">` children. Buttons call `win.minimize()` / `win.toggleMaximize()` / `win.close()` via `@tauri-apps/api`.

The maximize button additionally listens for the five `tauri-frame://snap/*` events from the Rust side to mirror hover/click state from the native overlay HWND.

**For our integration we don't need this JS** — we already have our own React titlebar (`gui/src/components/layout/Titlebar.tsx`). We'd configure `auto_titlebar(false)` so the JS injection is skipped, and only the native overlay HWND from `snap.rs` runs.

### 3.8 `guest-js/index.ts`

```ts
// Native Windows 11 Snap Layout support is installed by the Rust plugin.
// No frontend command is required.
```

Two lines. **No `invoke` calls, no IPC surface from the JS side.** This is the cleanest possible JS API: there isn't one.

### 3.9 `permissions/default.toml`

```toml
[default]
description = "Default permissions for the frame plugin"
permissions = []
```

**Zero Tauri capabilities required.** The plugin doesn't add any `core:window:*` grants to the host app; it doesn't expose any commands; it doesn't widen the host's permission surface in any way. This is the most reassuring single fact in the audit.

### 3.10 `.github/workflows/`

- `audit.yml`: Daily `rustsec/audit-check@v1` on `Cargo.lock`. Catches any newly-disclosed CVEs in transitive deps within 24h.
- `clippy.yml`: `cargo fmt --check` (Ubuntu) + `cargo clippy --all-targets --all-features -- -D warnings` (Windows). Run on every push/PR.

No release-signing workflow, no `npm --provenance`, no SLSA build attestation. Standard hobby-OSS posture.

---

## 4. Git History Audit

- **Total commits across all branches:** 179.
- **First commit on this branch:** `0530be7 feat: first commit` (much older — this is the `clearlysid/tauri-plugin-decorum` lineage).
- **GitHub API confirms `fork: true`, parent = `clearlysid/tauri-plugin-decorum`, source = same.** The lineage is **clean, public, and attributed**. This is exactly the opposite of a clean-room-rewrite-laundering scenario.
- **Tags:** none. (No tags = no signed tags to verify, but also no `v1.1.7` tag in the repo.) The crates.io release is the single source of truth for "what is v1.1.7" — we audit by commit hash `3cac206`.
- **Contributors (distinct identities):** 18, dominated by the original `clearlysid` (Siddharth, the `tauri-plugin-decorum` author) and `clarifei` (Rendy Sebpian). Other contributors are early decorum contributors. No suspicious typo-squat-name contributors.
- **Force pushes / suspicious history rewrites:** None visible — git log walk shows a linear-ish history with merge commits from labeled PRs (`Merge pull request #47 from clearlysid/copilot/fix-46`). The "feat: add native snap layout support" commit (`3cac206`) lands cleanly on top.
- **No commits with messages like "fix security issue", "remove backdoor", or "revert leak".**

`clarifei`'s author identity (GitHub ID 87487884, `admin@afterinput.com` / `nightcoremosta@gmail.com`) matches across all his commits. Real human, real account.

---

## 5. Dependency Chain Audit

### Rust

The plugin adds **no transitive Rust dependencies beyond what a stock Tauri v2 app already pulls in.** `windows-sys` is a Microsoft crate (`microsoft/windows-rs`). `eyre` is Yaah/Jane Lusby. `raw-window-handle` is the rust-windowing org (used by every windowing crate in the Rust ecosystem). `serde` is dtolnay.

Cargo.lock has 395 entries — same order of magnitude as our existing Tauri app's lockfile would have. Spot-check of frequently-flagged crates (`chrono 0.4.44`, `time 0.3.47`, `generic-array 0.14.7`) shows current/non-vulnerable versions.

CI runs `rustsec/audit-check` daily; new CVEs surface within 24h.

### NPM

`package.json` runtime deps: only `@tauri-apps/api`. Build-time only: `rollup`, `@rollup/plugin-typescript`, `typescript`, `tslib` — all mainstream.

**Important caveat:** The npm package `tauri-plugin-frame-api` does **not appear to be published to npm** — both `https://registry.npmjs.org/@clarifei/tauri-plugin-frame` and `https://registry.npmjs.org/tauri-plugin-frame-api` return `{"error":"Not found"}`. This is fine for our use because the plugin's JS API surface is empty (`guest-js/index.ts` is a 2-line comment) — we'd consume only the Rust crate via Cargo. **We must not blindly `npm install`** any package claiming to be the JS counterpart; if the user later adopts a published JS counterpart, re-audit at that point.

---

## 6. Behavior Audit — Mechanism Verification

The plugin claims: *"create a child overlay HWND that returns `HTMAXBUTTON` from `WM_NCHITTEST`, which the Windows 11 shell looks for to trigger Snap Layout."*

Direct verification from source:

- ✅ **Child HWND created** with `CreateWindowExW(WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_OVERLAPPED, ...)` and the parent set to Tauri's webview HWND (`snap.rs:131-144`).
- ✅ **Overlay positioned over the maximize button slot** by `update_overlay_position` (`snap.rs:219-245`), DPI-scaled, anchored to the right edge with `right_index = 1` (= second-from-rightmost slot = where the maximize button sits when the close button is the rightmost).
- ✅ **`WM_NCHITTEST` returns `HTMAXBUTTON as LRESULT`** (`snap.rs:294`). Single, unambiguous return.
- ✅ **NO Win+Z simulation.** Grepped for `VK_LWIN`, `keybd_event`, `SendInput`, `simulate` — all 0 hits.
- ✅ **Overlay teardown** via `RemoveWindowSubclass` + `DestroyWindow` on `WM_CLOSE` and explicit `uninstall()` (`snap.rs:251-256`). Multiple installs on the same HWND remove the prior overlay first (`snap.rs:151-154`). No HWND leak path.
- ✅ **No extra IPC channels** beyond five `webview.emit` events (mouse enter/leave/down/up/click + mousemove with coords) used for JS-side hover mirroring.
- ✅ **No network calls, no `std::fs::*`, no `std::process::Command`, no `libloading`, no shell execution, no registry access, no UAC elevation, no driver loading.** Confirmed by grep.

**Verdict: behavior matches claimed mechanism exactly.**

### Non-Windows behavior

- `mod snap;` is gated `#[cfg(windows)]` (`lib.rs:8-9`).
- `FramePluginBuilder::build()` has a `#[cfg(not(windows))]` variant that produces a do-nothing plugin (`lib.rs:175-183`).
- `WebviewWindowExt::create_overlay_titlebar` returns `Ok(self)` unchanged on non-Windows (`desktop.rs:82-91`).

Compiles to a pure no-op on macOS/Linux. No panics, no `unimplemented!()`, no `println!` spam.

---

## 7. Known Issues Audit

- **`clarifei/tauri-plugin-frame` open issues:** 0 (entire history — zero issues, zero PRs ever filed).
- **GitHub search across repo for `security`/`vulnerability`/`CVE`/`panic`/`memory`/`UB`:** 0 hits.
- **GitHub search across predecessor `clearlysid/tauri-plugin-decorum` for the same terms:** 0 security-labeled issues; 3 incidental hits all unrelated to security (blank-decoration race, CSS tightening, getting-started question).

The predecessor's well-known limitation (broken Win11 Snap Layout via Win+Z key simulation) is **exactly what this fork was created to fix** — and it does fix it, via the HTMAXBUTTON approach. That's the entire raison d'être of the fork.

---

## 8. Distribution Audit

- **Cargo crate** `tauri-plugin-frame`:
  - First published 2025-12-09 by `clarifei`.
  - Total downloads: 1,416 (modest, expected for a 5-month-old plugin).
  - Versions: 1.1.1, 1.1.2, **1.1.3 [yanked]**, **1.1.4 [yanked]**, **1.1.5 [yanked]**, 1.1.6, **1.1.7 (target)**.
  - All three yanks happened on 2025-12-12 (same day as the parent 1.1.2). Pattern is consistent with **rapid publish-fix-publish-fix** during initial setup, not with a security yank (which would typically be a single retroactive yank of a current version with a public RustSec advisory). No corresponding RustSec advisory exists for `tauri-plugin-frame`.
  - Publisher identity: `clarifei` on every version. No multi-publisher confusion.
  - **No `cargo install` provenance signing** — but Cargo doesn't have a standard provenance flow yet, so this is universal.

- **NPM:** Neither `@clarifei/tauri-plugin-frame` nor `tauri-plugin-frame-api` is currently published. We won't be pulling anything from npm — our integration is Rust-crate-only.

---

## 9. Final Verdict + Caveats

**Verdict: ADOPT-WITH-CAVEATS.**

The audit found **no security defects, no correctness defects, and no suspicious behavior**. The mechanism matches the claim. The unsafe surface is the irreducible minimum for Win32 FFI and is locally sound. The plugin adds **zero Tauri capabilities** to our host app. There is **no IPC command surface, no postinstall script, no network code, no FS code, no exec code, no dynamic loading**. The fork lineage from `clearlysid/tauri-plugin-decorum` is public, attributed, and clean.

The caveats are about **ecosystem proof**, not about any flaw:

1. **Pin the version exactly.** Use `tauri-plugin-frame = "=1.1.7"` (not `"^1.1.7"`) in our Cargo.toml. The Snap Layout code was added in `3cac206` (1.1.7) — older crates.io versions are pre-Snap-Layout and yank-churn-prone. New versions from the same author should be re-audited before bumping.
2. **Pin by git commit if you want extra safety.** `tauri-plugin-frame = { git = "https://github.com/clarifei/tauri-plugin-frame", rev = "3cac206caa1505781ba8ead75593bd45f9dd23a2" }` removes the crates.io supply-chain link entirely.
3. **Configure with `auto_titlebar(false)`.** We already have our own React titlebar; we only want the native Snap Layout overlay. This skips the JS injection entirely, halving the integration surface.
4. **Watch the upstream.** The plugin is 1 day old at v1.1.7 and has 0 open issues — meaning no one else has stress-tested it in production yet. If a real bug surfaces, we may be the ones to find it. Subscribe to repo notifications.
5. **Be aware of the no-IPC-surface invariant.** This audit's strongest reassurance is that `build.rs` declares `&[]` commands. If a future version of the plugin adds Tauri commands, **re-audit before bumping** — that would change the threat model materially.

If any of these caveats feels burdensome — particularly (1) and (4), since they imply long-term maintenance vigilance on a 1-day-old single-maintainer crate — the §10 "write our own" sketch is small enough to vendor.

---

## 10. "Write Our Own" Sketch

If we choose to vendor this ourselves instead of depending on the plugin, the entire load-bearing code is **~120 LOC of Rust**, plus ~15 LOC of integration. This is the smallest production-quality version:

### File: `gui/src-tauri/src/snap_layout.rs` (new, ~120 LOC)

```rust
//! Windows 11 Snap Layout overlay HWND.
//!
//! Creates a transparent child window over the maximize-button region of a
//! borderless Tauri webview. The child's WM_NCHITTEST handler returns
//! HTMAXBUTTON, which the Win11 shell uses as the trigger to display the
//! Snap Layout flyout on hover.

#![cfg(target_os = "windows")]

use std::sync::{Mutex, OnceLock};
use std::collections::HashMap;

use tauri::{Runtime, WebviewWindow};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{GetStockObject, HBRUSH, NULL_BRUSH};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, GetClientRect, RegisterClassExW,
    SetWindowPos, CS_HREDRAW, CS_VREDRAW, HTMAXBUTTON, HWND_TOP, SWP_ASYNCWINDOWPOS,
    SWP_SHOWWINDOW, WM_CLOSE, WM_DPICHANGED, WM_NCHITTEST, WM_SIZE,
    WNDCLASSEXW, WS_CHILD, WS_CLIPSIBLINGS, WS_VISIBLE,
};

const CLASS_NAME: &[u16] = &[
    b'S' as u16, b'T' as u16, b'R' as u16, b'E' as u16, b'A' as u16, b'M' as u16,
    b'S' as u16, b'n' as u16, b'a' as u16, b'p' as u16, 0,
];
const SUBCLASS_ID: usize = 0x53_54_52_4d; // 'STRM'
const TITLEBAR_PX: u32 = 32;
const BUTTON_PX: u32 = 46;
const RIGHT_INDEX: i32 = 1; // maximize button is 2nd from the right

static OVERLAYS: OnceLock<Mutex<HashMap<isize, HWND>>> = OnceLock::new();

pub fn install<R: Runtime>(window: &WebviewWindow<R>) -> Result<(), String> {
    let handle = window.window_handle().map_err(|e| e.to_string())?;
    let RawWindowHandle::Win32(h) = handle.as_raw() else {
        return Ok(()); // non-Win32 — no-op
    };
    let hwnd_isize = h.hwnd.get();
    window.run_on_main_thread(move || unsafe {
        install_native(hwnd_isize as HWND);
    }).map_err(|e| e.to_string())?;
    Ok(())
}

unsafe fn install_native(hwnd: HWND) {
    register_class_once();
    let overlay = CreateWindowExW(
        0, CLASS_NAME.as_ptr(), CLASS_NAME.as_ptr(),
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        0, 0, 0, 0, hwnd, std::ptr::null_mut(),
        GetModuleHandleW(std::ptr::null()), std::ptr::null_mut(),
    );
    if overlay.is_null() { return; }
    let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut g = map.lock().unwrap();
    if let Some(old) = g.insert(hwnd as isize, overlay) {
        DestroyWindow(old);
    }
    drop(g);
    SetWindowSubclass(hwnd, Some(parent_proc), SUBCLASS_ID, 0);
    reposition(hwnd);
}

unsafe fn register_class_once() {
    static REGISTERED: OnceLock<()> = OnceLock::new();
    REGISTERED.get_or_init(|| {
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: CS_HREDRAW | CS_VREDRAW,
            lpfnWndProc: Some(overlay_proc),
            cbClsExtra: 0, cbWndExtra: 0,
            hInstance: GetModuleHandleW(std::ptr::null()),
            hIcon: std::ptr::null_mut(), hCursor: std::ptr::null_mut(),
            hbrBackground: GetStockObject(NULL_BRUSH) as HBRUSH,
            lpszMenuName: std::ptr::null(),
            lpszClassName: CLASS_NAME.as_ptr(),
            hIconSm: std::ptr::null_mut(),
        };
        RegisterClassExW(&class);
    });
}

unsafe fn reposition(hwnd: HWND) {
    let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
    let g = map.lock().unwrap();
    let Some(&overlay) = g.get(&(hwnd as isize)) else { return; };
    drop(g);
    let mut rect = std::mem::zeroed();
    if GetClientRect(hwnd, &mut rect) == 0 { return; }
    let dpi = GetDpiForWindow(hwnd) as i32;
    let bw = (BUTTON_PX as i32 * dpi + 48) / 96;
    let th = (TITLEBAR_PX as i32 * dpi + 48) / 96;
    let x = rect.right - bw * (RIGHT_INDEX + 1);
    SetWindowPos(overlay, HWND_TOP, x, 0, bw, th,
        SWP_ASYNCWINDOWPOS | SWP_SHOWWINDOW);
}

unsafe extern "system" fn parent_proc(
    hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM, _id: usize, _data: usize,
) -> LRESULT {
    match msg {
        WM_SIZE | WM_DPICHANGED => reposition(hwnd),
        WM_CLOSE => {
            RemoveWindowSubclass(hwnd, Some(parent_proc), SUBCLASS_ID);
            let map = OVERLAYS.get_or_init(|| Mutex::new(HashMap::new()));
            if let Some(overlay) = map.lock().unwrap().remove(&(hwnd as isize)) {
                DestroyWindow(overlay);
            }
        }
        _ => {}
    }
    DefSubclassProc(hwnd, msg, wp, lp)
}

unsafe extern "system" fn overlay_proc(
    hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM,
) -> LRESULT {
    if msg == WM_NCHITTEST { return HTMAXBUTTON as LRESULT; }
    DefWindowProcW(hwnd, msg, wp, lp)
}
```

### Integration in `gui/src-tauri/src/lib.rs`

```rust
mod snap_layout;

// inside .setup(|app| { ... }):
#[cfg(target_os = "windows")]
{
    let main = app.get_webview_window("main").unwrap();
    let _ = snap_layout::install(&main);
}
```

### Cargo.toml addition

```toml
[target.'cfg(windows)'.dependencies]
windows-sys = { version = "0.61", features = [
    "Win32_Foundation",
    "Win32_Graphics_Gdi",
    "Win32_System_LibraryLoader",
    "Win32_UI_HiDpi",
    "Win32_UI_Shell",
    "Win32_UI_WindowsAndMessaging",
] }
raw-window-handle = "0.6"
```

### LOC estimate

- Rust: ~120 LOC in `snap_layout.rs` + 5 LOC integration in `lib.rs`.
- Cargo.toml: 8 lines added.
- **Total diff: ~135 LOC.**

### What's testable

- **Compile-test (cross-platform):** `cargo check --target x86_64-pc-windows-msvc` from CI.
- **Unit-testable:** `reposition` math (DPI scaling, right-anchor offset) — extract `compute_overlay_rect(client_rect, dpi, button_px, titlebar_px, right_index) -> (x, y, w, h)` as a pure function and unit-test it on Linux/macOS without any Win32.
- **Manual UAT only:** the actual Snap Layout flyout appearance — requires a real Win11 desktop. (Same as for the third-party plugin.)

### Tradeoff summary

| | Adopt plugin | Write our own |
|---|---|---|
| LOC added to our repo | ~5 (just config) | ~135 |
| Supply-chain surface | +1 crate (~939 LOC + transitive) | +0 crates (we already pull `windows-sys`) |
| Maintenance burden | Watch upstream + re-audit on bumps | Own it forever (but it'll never change) |
| Win11 evolution risk | Author tracks Win11 changes | We track them |
| Bug discovery latency | Community finds bugs | We find our own bugs |

For a feature this narrow (one HWND, one WM_NCHITTEST return value), **writing our own is genuinely competitive** — the maintenance burden of a 120-LOC file that never needs to change is lower than the burden of watching an upstream we don't control.

---

## AUDIT VERDICT: ADOPT-WITH-CAVEATS

Plugin is clean — correct mechanism (HTMAXBUTTON, not Win+Z simulation), zero Tauri capabilities, zero IPC commands, zero postinstall scripts, sound `unsafe` usage, clean public fork lineage. The caveats are about freshness (1-day-old v1.1.7, single maintainer, no production track record yet): pin to `=1.1.7` (or pin by commit `3cac206`), configure with `auto_titlebar(false)`, and re-audit on any version bump that touches `build.rs` or `Cargo.toml`. If those caveats feel like ongoing burden, the §10 "write our own" sketch (~135 LOC) is a defensible alternative — the feature is small enough to vendor.
