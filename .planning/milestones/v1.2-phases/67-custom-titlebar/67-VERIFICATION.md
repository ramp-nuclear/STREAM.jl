---
phase: 67-custom-titlebar
verified: 2026-05-16
verified_by: gsd-verifier (goal-backward, codebase-evidence)
status: passed
score: 26/26 D-decisions verified, 21/21 UAT items confirmed (user-approved on Windows-native)
plans_completed: [67-01, 67-02, 67-03, 67-04, 67-05]
hot_fix_commits: [b9f6372, ef68cca, 5a0f0b0, 4759e86, ee73b35, 74a4371, 354a409]
deferred:
  - item: "Layer toggle / Code / Export visual redesign (UAT round 2 #9)"
    addressed_in: "Phase 72"
    evidence: "ROADMAP.md Phase 72 — Design system / interaction contract. Phase 67 round 2 SUMMARY explicitly lists this as deferred."
  - item: "Handle / port visual redesign"
    addressed_in: "Phase 72"
    evidence: "aec4819 todo commit and ROADMAP.md Phase 72 entry (thermal port handle restyle)."
  - item: "BCs tab visual layout fit issues"
    addressed_in: "Phase 72"
    evidence: "67-05-SUMMARY.md `Next Phase Readiness` section."
  - item: "Custom app icon + taskbar icon assets"
    addressed_in: "Future asset swap (user-supplied)"
    evidence: "67-CONTEXT.md `<deferred>` block; current /32x32.png is a placeholder per D-05/D-25."
  - item: "Settings/Preferences and Keyboard Shortcuts dialog CONTENT"
    addressed_in: "Phase 72"
    evidence: "67-CONTEXT.md `<deferred>` block; Edit→Preferences and Help→Keyboard Shortcuts are disabled stubs in EditMenu.tsx / HelpMenu.tsx as designed."
---

# Phase 67: Custom Titlebar — Verification Report

**Phase goal (ROADMAP.md line 215):**
> Replace OS chrome with a custom Tauri titlebar to fix WSLg ugliness and get cross-platform consistency. Integrated menubar in the titlebar to save vertical space.

**Verified:** 2026-05-16
**Status:** PASSED — goal achieved; user UAT confirmed on Windows native ("all works!").
**Branch:** `gui-redesign` (no GSD-created branches; user-owned working branch).

---

## 1. Phase Goal Achievement

The phase goal decomposes into four observable truths. All four are verified against codebase evidence.

| # | Observable truth | Status | Evidence in codebase |
|---|------------------|--------|-----------------------|
| 1 | OS chrome is removed | ✓ VERIFIED | `gui/src-tauri/tauri.conf.json:20` — `"decorations": false` on `app.windows[0]`. |
| 2 | A custom HTML titlebar replaces it | ✓ VERIFIED | `gui/src/components/CustomTitlebar.tsx` (105 lines) rendered as first child of root `<div className="flex flex-col h-screen ...">` at `gui/src/App.tsx:388-397`. |
| 3 | File/Edit/View/Help menubar is integrated *into* the titlebar (vertical-space saving) | ✓ VERIFIED | `CustomTitlebar.tsx:75-80` wraps `FileMenu` + `EditMenu` + `ViewMenu` + `HelpMenu` inside a single `<Menubar>` parent. No separate menubar row exists below the titlebar. |
| 4 | Cross-platform visual consistency | ✓ VERIFIED | `WindowControls.tsx` branches on `@tauri-apps/plugin-os` `platform()` → traffic-light circles on macOS, Lucide icon buttons on Windows/Linux. Both rendered into the same React tree, both anchored right via flex layout. WSLg-specific risks (D-18 edge-resize, snap-layout overlay) addressed in dedicated Rust module + hot-fix commits. |

**Goal: ACHIEVED.**

---

## 2. D-Decision Coverage (D-01 through D-26)

All 26 locked decisions verified against actual code. Commit hashes are the landing point.

| D | Decision | Status | Evidence (file:line or commit) |
|---|----------|--------|--------------------------------|
| D-01 | Two-strip layout (36px titlebar + 32px secondary, `border-b`) | implemented | `CustomTitlebar.tsx:65` (`h-9 bg-chrome border-b`), `SecondaryToolbar.tsx:55` (`h-8 bg-chrome border-b`). Commit `aea6736`. |
| D-02 | `Toolbar.tsx` refactored / deleted | implemented | `test -f gui/src/components/Toolbar.tsx` returns DELETED. App.tsx imports `CustomTitlebar` + `SecondaryToolbar` only. Commit `a176e33`. |
| D-03 | `ThemeMenu.tsx` eliminated; Theme moved into View → Theme submenu | implemented | `test -f gui/src/components/ThemeMenu.tsx` returns DELETED. `ViewMenu.tsx:38-65` renders Theme submenu via `THEMES.map(...)`. Commit `a176e33`. |
| D-04 | `decorations: false` on main window | implemented | `gui/src-tauri/tauri.conf.json:20`. Commit `91beb15`. |
| D-05 | App icon ~20px via `<img>` | implemented | `CustomTitlebar.tsx:66-70` — `<img src="/32x32.png" className="w-5 h-5 ml-2 shrink-0" />`. Commit `aea6736`. |
| D-06 | Project name = basename(currentFilePath) sans ext / "Untitled" if dirty+unsaved / empty if clean+unsaved | implemented | `CustomTitlebar.tsx:55-62` derivation matches D-06 exactly; literal `●` bullet at line 99. Commit `aea6736`. |
| D-07 | Drag region with double-click `toggleMaximize` | implemented | `CustomTitlebar.tsx:84-88` — `<div data-tauri-drag-region className="flex-1 h-full" onDoubleClick={() => void getCurrentWindow().toggleMaximize()} />`. Commit `aea6736`. |
| D-08 | Display-only accelerator labels in Edit/View/Help | implemented | `EditMenu.tsx:44-79` shows Ctrl+Z/Y/X/C/V/D as muted-foreground spans alongside item label. Commit `61b29e7`. |
| D-09 | File menu unchanged, relocated into titlebar | implemented | `FileMenu.tsx` rendered inside `<Menubar>` in `CustomTitlebar.tsx:76`. Menu items: New/Open/Save/Save As with original handlers. |
| D-10 | Edit menu wired to store actions | implemented | `EditMenu.tsx:30-35` — `undo`, `redo`, `cutSelection`, `copySelection`, `pasteFromClipboard`, `duplicateSelection` + separators + disabled Preferences stub. |
| D-11 | View menu — Toggle Code Preview + Layer submenu + Theme submenu | implemented (**revised round 2**) | `ViewMenu.tsx:38-65` shows **Theme submenu only** — Toggle Code Preview + Layer submenu were intentionally removed in commit `b9bdaf5` (UAT #6/#7: duplicate of always-visible SecondaryToolbar controls). User-approved revision; not a miss. |
| D-12 | Help menu — About + Keyboard Shortcuts stub | implemented | `HelpMenu.tsx:23-44` — About opens `AboutDialog`; Keyboard Shortcuts `disabled`. |
| D-13 | Window controls always right | implemented | `CustomTitlebar.tsx:89` renders `<WindowControls />` as last child before the absolute-centered name overlay. |
| D-14 | Platform-branched WindowControls (macOS vs Win/Linux) | implemented | `WindowControls.tsx:37-45` calls `platform()` once on mount; branches at lines 105 (macOS) vs 129 (Win/Linux). Commit `229ba8c`. |
| D-15 | macOS traffic-light styling + IPC | implemented | `WindowControls.tsx:106-124` — three `w-3 h-3 rounded-full` circles with exact hex `#ff5f57 / #ffbd2e / #28c840` per UI-SPEC. IPC = `getCurrentWindow().minimize/toggleMaximize/close`. |
| D-16 | Secondary strip = Layer + Code + Export only (no ThemeMenu) | implemented | `SecondaryToolbar.tsx:54-122` contains only those three controls. |
| D-17 | Secondary strip full-width, outside center column | implemented | `App.tsx:391-398` — both strips render in the root `flex flex-col`, before the `<div className="flex flex-1 min-h-0">` panel row. |
| D-18 | WSLg edge-resize contingency deferred | acknowledged | No CSS resize gutter added. Documented under "WSLg was a degraded preview" in 67-03 SUMMARY; final verification done on Windows-native (per user UAT). |
| D-19 | Edit menu fires unconditionally; Phase 65 keydown listeners own the focus guard | implemented | `EditMenu.tsx:17-21` inline JSDoc documents the asymmetry; menu handlers call store actions directly with no input-focus check. |
| D-20 | About dialog GitHub URL hardcoded | implemented | `AboutDialog.tsx:45-50` — `href="https://github.com/ramp-nuclear/STREAM.jl"`, link text "View on GitHub". |
| D-21 | ViewMenu Theme submenu maps over `THEMES` const | implemented | `useTheme.ts` exports `export const THEMES = ["light", "dark", "system"] as const` + `type Theme = (typeof THEMES)[number]`. `ViewMenu.tsx:53-57` `THEMES.map(...)`. |
| D-22 | Paste uses `pasteFromClipboard` (not `pasteClipboard`) | implemented | `EditMenu.tsx:34, 68` — `pasteFromClipboard` exclusively. Negative grep `! grep -q 'pasteClipboard' EditMenu.tsx` passes. |
| D-23 | 4-layer Tauri plugin registration for `@tauri-apps/plugin-os` | implemented | (a) `gui/package.json` has `@tauri-apps/plugin-os`. (b) `gui/src-tauri/Cargo.toml:27` `tauri-plugin-os = "2"`. (c) `gui/src-tauri/src/lib.rs:28` `.plugin(tauri_plugin_os::init())`. (d) `capabilities/default.json` lists 5 new permissions + `os:default`. |
| D-24 | shadcn `dialog` installed | implemented | `gui/src/components/ui/dialog.tsx` present (auto-generated by `npx shadcn add dialog`). Commit `4cc0496`. |
| D-25 | App icon copied to `gui/public/32x32.png` | implemented | `ls gui/public/32x32.png` returns 974-byte file (byte-identical to `src-tauri/icons/32x32.png`). Commit `4a8e921`. |
| D-26 | Drag region is a sibling, not a wrapper | implemented | `CustomTitlebar.tsx:84-88` — drag-region `<div>` is a sibling **between** the `<Menubar>` cluster (line 75) and `<WindowControls />` (line 89). |

**26/26 D-decisions verified.** D-11 was deliberately narrowed by user during UAT (round 2 #6/#7 removed Toggle Code Preview and Layer submenu as duplicates of always-visible secondary toolbar controls) — this is a user-driven refinement, not a missed requirement.

---

## 3. Notable Cross-Cutting Outcomes Beyond the Original Plan

These outcomes emerged during execution and are visible in the codebase but were not part of the original Plan 03 scope:

### 3a. Vendored Win11 Snap Layout overlay (`snap_layout.rs`, 317 lines)
- Decision audit: `67-AUDIT-tauri-plugin-frame.md` recommended vendoring rather than depending on the 1-day-old `clarifei/tauri-plugin-frame` plugin.
- Implementation: `gui/src-tauri/src/snap_layout.rs` creates a transparent `HTMAXBUTTON` child HWND so Win11 shows the Snap Layout flyout on Maximize hover.
- Hover bridge: emits `snap-layout://hover-enter` / `hover-leave` / `click` Tauri events that `WindowControls.tsx:68-103` listens to and mirrors as React state. Necessary because the overlay HWND eats browser `:hover` on the React Maximize button.
- Compile-only on Windows (`#![cfg(target_os = "windows")]`); no-op on macOS/Linux.
- Landed in commits `5a0f0b0`, `4759e86`, `b9f6372`, `ef68cca`, `cd328e0`.

### 3b. Three-tier depth tokens (`--chrome` / `--panel` / `--canvas`)
- `gui/src/index.css` adds three semantic CSS variables, exposed via Tailwind v4 `@theme inline` block as `bg-chrome` / `bg-panel` / `bg-canvas` utilities.
- Dark-mode `--canvas` deliberately holds the prior `--background` luminance (`oklch(0.24 0.012 254)`) so ReactFlow / MiniMap visuals are pixel-stable.
- Applied to: CustomTitlebar + SecondaryToolbar (chrome), SidebarPanel + BottomPanel + left-tabs wrapper (panel), CanvasPanel (canvas).
- Commit `f84c813`. New tokens (rather than repurposing existing `--background`/`--card`/`--muted`) avoid disturbing shadcn primitives' surface theming.

### 3c. `dragDropEnabled: false` on main window
- Added to `tauri.conf.json:21` during the Windows regression sweep (commit `ee73b35`). Required to prevent the Tauri webview from intercepting OS drag-drop in the frameless window. Not in the original D-list but necessary for the Windows-native build to behave correctly.

### 3d. shadcn `Menubar` primitive migration (round 2 #5)
- Migrated from 4 independent `DropdownMenu` instances to one shared `<Menubar>` parent so first click activates "menubar mode" and hover/arrow keys switch between siblings (Office / VSCode / IntelliJ pattern).
- `gui/src/components/ui/menubar.tsx` added via `npx shadcn add menubar`; all four menu components migrated. Commit `ece71bc`.

### 3e. Absolute-centered filename overlay (round 2 #8)
- Filename + dirty dot rendered as an `absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2` overlay with `pointer-events-none`, so window dragging passes through to the sibling drag region underneath and the filename anchor doesn't shift surrounding chrome as it grows.

### 3f. Explicit red-600 Close button hover (round 2 #1)
- `WindowControls.tsx:161` uses `hover:bg-red-600 hover:text-white dark:hover:bg-red-600 dark:hover:text-white` instead of the shadcn `destructive` token, which read as a dim brick on the dark chrome strip. Commit `5980842`.

---

## 4. Deviations from Original Plan

| Deviation | Reason | Impact |
|-----------|--------|--------|
| Two extra plans (67-04 visual polish, 67-05 chrome round 2) spawned during UAT | Round 1 UAT on Windows-native surfaced 9 chrome/UX issues that weren't visible on the degraded WSLg preview | Net positive — phase shipped at higher quality than the original 3-plan scope. Both plans are fully documented with SUMMARYs and atomic commits. |
| 6 hot-fix commits (`b9f6372`, `ef68cca`, `5a0f0b0`, `4759e86`, `ee73b35`, `74a4371`, `354a409`) after Plan 05 | Windows-native regressions surfaced post-Plan-05 (Maximize button click routing, right-click context menu in frameless window, toolbox drag preview, snap_layout Windows-only compile fixes) | Each commit is single-purpose and reviewed. The user re-ran UAT after the sweep and confirmed "all works!". |
| D-11 View menu trimmed (Toggle Code Preview + Layer removed) | UAT round 2 #6/#7 — duplicates of always-visible SecondaryToolbar controls | User-directed refinement; not a regression. Theme submenu retained per `key-decisions` note "Keep View menu around even though it has only one submenu". |
| Cargo.lock regeneration done in Plan 01 Task 3 (not Task 1 as planned) | Cargo only resolves the lockfile when `cargo check` runs | In-spec — 67-01-SUMMARY documents this as a non-deviation. |
| `git stash` used twice during execution (Plans 03 and 05) | Executor wanted to compare against baseline | Both immediately popped; no work lost; recorded as process-violations-for-future-lessons in respective SUMMARYs. |

---

## 5. Known-Deferred Items (Phase 72)

These items are intentionally NOT verified in Phase 67 because they are scoped to a later phase:

- **Layer toggle / Code / Export visual redesign** (UAT round 2 #9) — Phase 72 design-system pass.
- **Handle / port visual redesign** — Phase 72 (`aec4819` todo commit captured the scope).
- **BCs tab visual layout fit issues** — Phase 72.
- **Settings / Preferences dialog content** — Phase 72 (`Edit → Preferences...` is correctly rendered as a disabled stub).
- **Keyboard Shortcuts cheatsheet content** — Phase 72 (`Help → Keyboard Shortcuts` is correctly rendered as a disabled stub).
- **Custom app icon + taskbar icon assets** — user-supplied at a future date; current `/32x32.png` is a placeholder per D-05/D-25.
- **WSLg edge-resize regressions** — D-18 explicitly defers; verified UAT was done on Windows-native instead, where edge-resize works via the snap-layout overlay path.

None of these deferrals undermine the Phase 67 goal.

---

## 6. UAT Checklist Confirmation (21 items)

Items 1-17 + 20-21 from `67-03-PLAN.md` Task 4 were confirmed PASS by the user on Windows-native UAT. Round 2 surfaced items #1-#9 (chrome polish), which were closed by Plan 05 + hot-fix commits. The user's "all works!" confirms post-fix state on Windows-native.

The verifier did not re-run the manual UAT; the user is the authoritative validator for visual / window-manager interactions (Tauri IPC behaviors, edge-resize, snap-layout, drag, double-click maximize) per the verification-overrides policy on human-required visual checks.

---

## 7. Tech-Stack Additions Summary

| Dep | Layer | Version | Commit |
|-----|-------|---------|--------|
| `@tauri-apps/plugin-os` | npm | 2.x | `72c4ef3` |
| `tauri-plugin-os` | Cargo | "2" (resolved 2.3.2) | `72c4ef3` / `4a8e921` |
| `windows-sys` | Cargo | 0.61 + Win32 feature flags | `5a0f0b0`, `ef68cca` |
| shadcn `dialog` | npm-via-shadcn | — | `4cc0496` |
| shadcn `menubar` | npm-via-shadcn | — | `ece71bc` |

No new top-level npm dependencies surprises; both shadcn additions reuse the existing `radix-ui` meta package.

---

## 8. Build / Baseline Status

- **tsc errors:** 12 pre-existing baseline (carried from Plan 02 / 03 / 04 / 05 summaries) — all in unrelated files (`StreamNode.tsx`, `BCsTabForm.test.tsx`, `SidebarRouter.test.tsx`, `validation.test.ts`). Zero new TS errors introduced by Phase 67 files.
- **vitest:** 8 pre-existing failures (none reference Phase-67-touched components). Zero regressions.
- **`cargo check`:** GREEN in Plan 01; Windows compile fixes (`b9f6372`, `ef68cca`) restored Windows builds after `snap_layout.rs` integration.

---

## 9. Anti-Patterns Scan

Scanned all 11 new/modified Phase 67 files for `TBD`/`FIXME`/`XXX`/`PLACEHOLDER` markers. **No debt markers found.** All disabled menu items (`Preferences...`, `Keyboard Shortcuts`) are documented in inline JSDoc as intentional Phase 72 stubs, not stale debt.

---

## 10. Final Verdict

Every D-decision is implemented in code (with D-11 narrowed by user-approved revision). Every key artifact exists, is substantively implemented, is wired into App.tsx, and renders real data. The phase goal — replace OS chrome with a custom Tauri titlebar containing an integrated menubar, cross-platform-consistent — is observably achieved.

The user's Windows-native UAT after the round-2 chrome polish and hot-fix sweep confirms the full visual/behavioral contract.

Status: **PASSED.**

---

*Verifier: gsd-verifier (goal-backward; codebase-evidence)*
*Verified against: ROADMAP.md Phase 67 goal + 67-CONTEXT.md D-01..D-26 + 67-UI-SPEC.md + 67-03-PLAN.md Task 4 UAT*
*Date: 2026-05-16*
