# Windows-native dev setup for STREAM Composer

This guide installs Node + Rust + the Tauri prerequisites on the **Windows side** (NOT inside WSL) so you can run `npm run tauri dev` and `npm run tauri build` against a real Win32 window — required to validate the custom titlebar's native chrome (border, Aero Snap, Snap Layout flyout, taskbar icon) before shipping.

WSLg gives you a degraded preview only. All chrome-behavior UAT must happen on a Windows-native build.

## Prerequisites

You'll install everything from a regular **Windows PowerShell** (or Windows Terminal — PowerShell tab). Don't use the WSL terminal for these steps; the binaries must live on the Windows side.

### 1. Microsoft C++ Build Tools

Required by Rust on Windows.

1. Download the installer: <https://visualstudio.microsoft.com/visual-cpp-build-tools/>
2. Run it. In the workload picker, check **"Desktop development with C++"**.
3. Default options under that workload are fine. Install (~3-5 GB).

(If you already have Visual Studio 2022 Community installed with the C++ workload, you're done with this step.)

### 2. WebView2 Runtime

Tauri uses Microsoft's Edge WebView2 to render the frontend. Windows 11 ships this by default; check just in case:

- Settings → Apps → Installed apps → search "WebView2". If "Microsoft Edge WebView2 Runtime" is listed, skip.
- Otherwise: <https://developer.microsoft.com/microsoft-edge/webview2/> → "Evergreen Standalone Installer" → install.

### 3. Rust toolchain

Open PowerShell and run:

```powershell
winget install Rustlang.Rustup
```

After install, restart PowerShell, then verify:

```powershell
rustup default stable
rustc --version
cargo --version
```

You should see Rust 1.80+ and cargo. Tauri v2 needs Rust 1.77+ for `Cargo.toml`'s edition 2021 idioms — stable is fine.

### 4. Node.js (LTS)

```powershell
winget install OpenJS.NodeJS.LTS
```

Restart PowerShell. Verify:

```powershell
node --version   # should be 20.x or 22.x LTS
npm --version
```

### 5. Git (if not already on Windows)

```powershell
winget install Git.Git
```

This also gives you Git Bash if you want a Unix-style shell on the Windows side.

## Cloning the repo on the Windows side

The repo currently lives at `\\wsl$\Ubuntu\home\itay\projects\Julia-STREAM` (visible from Windows). You **don't want to build through that UNC path** — file I/O across the WSL boundary is slow and the Rust + node_modules build will be miserable. Clone a fresh checkout to a native Windows path:

```powershell
mkdir C:\src
cd C:\src
git clone <your repo URL> Julia-STREAM
cd Julia-STREAM
git switch gui-redesign     # the active milestone branch
```

If you don't have a remote yet, you can pull from the WSL checkout:

```powershell
cd C:\src
git clone \\wsl$\Ubuntu\home\itay\projects\Julia-STREAM Julia-STREAM
```

Both work — the goal is just to have the repo on a Windows-native filesystem (NTFS, not WSL).

## Install + run

```powershell
cd C:\src\Julia-STREAM\gui
npm install
npm run tauri dev
```

First run will compile the Rust side (~3-5 min cold). Subsequent runs are sub-30s.

For a release `.exe`:

```powershell
npm run tauri build
```

Output lands in `gui/src-tauri/target/release/bundle/` — `.exe` standalone, `.msi` and `.nsis` installers.

## Notes

- **Don't run `npm install` on both sides** (WSL + Windows) in the same checkout — they share `node_modules` and the native binaries get clobbered. Use **two separate clones**: one for WSL-side iteration, one for Windows-native validation.
- **Daemon dev loop (`bin/jl` / `bin/jl-up`) is WSL-side only.** It controls a Julia daemon for the STREAM.jl backend; the Composer GUI doesn't use it.
- **Rebuild after every Rust change.** Hot reload covers React/TS only — Rust edits in `src-tauri/` require killing `tauri dev` and re-launching.
- **First-time Windows Defender prompt:** when `tauri dev` launches the webview, Windows may pop a SmartScreen / Defender alert because the binary is unsigned. Click "More info" → "Run anyway" during dev. For release builds, code-signing is a Phase 72 deliverable.

## What to validate on Windows-native (NOT WSLg)

Once `npm run tauri dev` shows the Composer window:

1. **Window border + shadow** — does the window have a thin native border + drop shadow, like every other Windows app?
2. **Aero Snap** — drag the window's titlebar to the left/right/top edge of the screen. Does the snap preview rectangle appear? Does the window resize to half-screen on release?
3. **Snap Layout flyout (Win11 only)** — hover the cursor over the Maximize button in the titlebar. Does the Snap Layout grid appear? (This is the feature that requires the vendored `snap_layout.rs` — won't work yet at the time of this doc; expected to land in the next Phase 67 gap-closure commit.)
4. **Taskbar icon** — pin the running app to the taskbar (right-click on the icon → Pin). Does it use the bundled `icon.ico` (or the Tauri default rocket if you haven't swapped in your own asset yet)? On a release `tauri build`, the icon is embedded in the `.exe` resource — `tauri dev` may show a generic Electron-like icon, that's expected.
5. **Minimize-to-taskbar animation** — does the window's minimize animation match standard Windows apps?
6. **Right-click on titlebar** — does the system menu (Restore / Move / Size / Minimize / Maximize / Close) appear? (Custom titlebar in Tauri usually breaks this; we accept the loss unless you flag it.)

Surfaces 1-5 are the make-or-break list. 6 is a known gap that's hard to restore without significantly more Win32 work — flag if it matters to you.
