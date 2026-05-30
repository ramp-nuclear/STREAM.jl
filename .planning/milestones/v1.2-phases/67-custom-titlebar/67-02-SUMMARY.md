---
phase: 67-custom-titlebar
plan: 02
subsystem: gui/react
tags:
  - tauri
  - window-controls
  - platform-detection
  - shadcn-dialog
  - theme
  - leaf-components
requirements:
  - D-14
  - D-15
  - D-20
  - D-21
  - D-24
dependency_graph:
  requires:
    - "67-01 (Tauri 4-layer foundation: @tauri-apps/plugin-os installed, capabilities granted, decorations: false)"
  provides:
    - "THEMES = ['light','dark','system'] as const exported from useTheme.ts; Theme derives from THEMES[number]"
    - "useWindowMaximized() reactive boolean hook subscribing to onResized with App.tsx-style listener cleanup (S5)"
    - "<WindowControls /> default-exported with platform branch (macOS traffic-lights vs Windows/Linux Lucide icons)"
    - "shadcn Dialog primitive at gui/src/components/ui/dialog.tsx (auto-generated)"
    - "<AboutDialog /> default-exported controlled dialog with Promise-aware getVersion()"
  affects:
    - "Plan 03 (CustomTitlebar.tsx + menus) — all four leaf primitives can now be imported directly"
    - "Phase 72 (handle/port rework) — THEMES is array-driven, appending a new entry widens the Theme union automatically"
tech_stack:
  added:
    - "shadcn 'dialog' primitive (radix-ui Dialog wrapper) — generated via `npx shadcn add dialog`"
  patterns:
    - "Pattern S5 (Tauri listener with cleanup-safe unlisten) applied to useWindowMaximized"
    - "Pattern S4 (fire-and-forget IPC `void w.method()`) applied to WindowControls"
    - "Array-driven literal-union type (THEMES[number]) for extensibility (D-21)"
key_files:
  created:
    - gui/src/hooks/useWindowMaximized.ts
    - gui/src/components/WindowControls.tsx
    - gui/src/components/__tests__/WindowControls.test.tsx
    - gui/src/components/ui/dialog.tsx
    - gui/src/components/AboutDialog.tsx
  modified:
    - gui/src/hooks/useTheme.ts
decisions:
  - "useWindowMaximized mirrors App.tsx onCloseRequested pattern verbatim (unlistenRef + active flag), not the simpler RESEARCH.md variant — PATTERNS.md Pattern S5 is authoritative for project-style adaptation"
  - "WindowControls render-fallback when plat === null is the Windows/Linux branch (same fallback used when platform() throws in vitest). Means macOS test must flush effects before asserting; documented in the test"
  - "shadcn dialog install pulled zero new npm peer deps — radix-ui meta package was already in node_modules from prior shadcn primitives"
metrics:
  duration_sec: 330
  duration_human: "5m 30s"
  completed_date: "2026-05-16"
  tasks_total: 3
  tasks_done: 3
  files_created: 5
  files_modified: 1
---

# Phase 67 Plan 02: Leaf UI primitives (WindowControls + AboutDialog) Summary

Built the four leaf primitives the custom titlebar (Plan 03) will consume: the `THEMES` array centralized in `useTheme.ts`, the `useWindowMaximized` reactive hook with App.tsx-style listener cleanup, the `<WindowControls />` component branching on `@tauri-apps/plugin-os` `platform()`, and the controlled `<AboutDialog />` after installing the shadcn `Dialog` primitive. 5/5 vitest assertions pass and no new tsc errors over the worktree baseline.

## Tasks Completed

| # | Task | Commits | Files |
|---|------|---------|-------|
| 1 | THEMES constant + useWindowMaximized hook | `ef69cdc` | `gui/src/hooks/useTheme.ts` (modified), `gui/src/hooks/useWindowMaximized.ts` (new) |
| 2 | WindowControls.tsx with platform branch (TDD) | RED `172ad04`, GREEN `229ba8c` | `gui/src/components/__tests__/WindowControls.test.tsx` (new), `gui/src/components/WindowControls.tsx` (new) |
| 3 | shadcn dialog install + AboutDialog.tsx | `4cc0496` | `gui/src/components/ui/dialog.tsx` (auto-generated), `gui/src/components/AboutDialog.tsx` (new) |

## Precise Locations

### `gui/src/hooks/useTheme.ts` (D-21)

Added directly after the file header (lines 3-7):

```ts
// Phase 67 D-21: array-driven theme list so ViewMenu can map over it
// (and Phase 72 can append without architectural change). `Theme` derives
// from this array — adding a new entry widens the union automatically.
export const THEMES = ["light", "dark", "system"] as const;
export type Theme = (typeof THEMES)[number];
```

The hook body, `STORAGE_KEY`, and the `setTheme` return shape are unchanged. Every existing consumer of `Theme` continues to typecheck — the union is the same set of literals.

### `gui/src/hooks/useWindowMaximized.ts` (new, 62 lines)

Mirrors the App.tsx `onCloseRequested` listener-cleanup pattern verbatim (Pattern S5):

- `const unlistenRef = useRef<(() => void) | null>(null);`
- `let active = true;` inside `useEffect`
- `.then((fn) => { if (!active) fn(); else unlistenRef.current = fn; })` for the Strict Mode double-mount race
- Cleanup: `active = false; unlistenRef.current?.(); unlistenRef.current = null;`

Every Tauri call is wrapped in try/catch (or `.catch(() => {})` on the `.onResized()` Promise) so vitest's non-Tauri environment renders the hook as a stable `false`. Refresh is event-driven (`onResized` callback re-reads `isMaximized()`), not polled — Pitfall 3 in 67-RESEARCH.md (issue #13199) is structurally avoided.

### `gui/src/components/WindowControls.tsx` (new, 100 lines)

Platform detection runs once on mount in a useEffect:

```tsx
try {
  const p = platform();  // SYNC per @tauri-apps/plugin-os
  setPlat(p === "macos" ? "macos" : p === "windows" ? "windows" : "linux");
} catch {
  setPlat("linux");
}
```

The two render branches:

- **macOS branch** — wrapper `<div className="flex items-center gap-2 px-3 group">`, three raw `<button>` circles `w-3 h-3 rounded-full bg-[<hex>]/40 group-hover:bg-[<hex>] transition-colors`, **L→R order = Close (red `#ff5f57`), Minimize (yellow `#ffbd2e`), Maximize (green `#28c840`)** per Apple HIG + D-14. Aria-labels: `"Close window"`, `"Minimize window"`, `"Toggle maximize"`.
- **Windows/Linux branch** (also the pre-mount and vitest fallback) — wrapper `<div className="flex items-stretch h-full">`, three shadcn `<Button variant="ghost" size="icon">` with `rounded-none h-full w-10` and Lucide `<Minus />` / (`<Maximize2 />` ↔ `<Minimize2 />` toggled by `useWindowMaximized()`) / `<X />`. Close button overrides hover to `hover:bg-destructive hover:text-destructive-foreground`. **L→R order = Minimize, Maximize/Restore, Close**.

IPC pattern: `const w = getCurrentWindow(); const onMin = () => void w.minimize(); …` — fire-and-forget per Pattern S4. `void` prefix matches App.tsx style.

### `gui/src/components/__tests__/WindowControls.test.tsx` (new, 5 tests)

Mocks `@tauri-apps/plugin-os` and `@tauri-apps/api/window` at module scope, then renders the component three times per assertion group:

1. macOS branch — three `.rounded-full` buttons with the exact traffic-light hex in `className`; aria-labels in Close/Min/Max order.
2. macOS click handlers — Close → `close()`, Min → `minimize()`, Max → `toggleMaximize()` (one call each).
3. Windows branch — three buttons, no `.rounded-full`, Close rightmost.
4. `platform()` throwing — falls back to Windows/Linux variant.
5. Linux click handlers — three buttons in Min/Max/Close left-to-right.

All 5 pass.

### `gui/src/components/ui/dialog.tsx` (new, auto-generated)

Created by `npx shadcn add dialog` (no flags, accept defaults — uses the `new-york` style + `lucide` icons configured in `gui/components.json`). Exports the full primitive set: `Dialog`, `DialogClose`, `DialogContent`, `DialogDescription`, `DialogFooter`, `DialogHeader`, `DialogOverlay`, `DialogPortal`, `DialogTitle`, `DialogTrigger` — exactly matches the plan's minimum.

### `gui/src/components/AboutDialog.tsx` (new, 55 lines)

Controlled component `{ open, onOpenChange }` returning `<Dialog open={open} onOpenChange={onOpenChange}>` wrapping `<DialogContent>` with:

- `<DialogTitle>STREAM Composer</DialogTitle>`
- `<DialogDescription>Version {version}</DialogDescription>` — em-dash placeholder until `getVersion()` resolves (Pitfall 8 avoidance)
- inline `<a href="https://github.com/ramp-nuclear/STREAM.jl" target="_blank" rel="noreferrer">View on GitHub</a>` (D-20 URL hardcoded inline, not via constant)
- `<DialogFooter>` with a `<Button variant="outline" onClick={() => onOpenChange(false)}>Close</Button>`

`getVersion().then(setVersion).catch(() => setVersion("—"))` runs in a mount-only useEffect; no listener cleanup needed (Promise, not subscription).

## Verification

| Check | Status |
|-------|--------|
| `npm run test -- WindowControls` (5 tests) | PASS (5/5) |
| `npx tsc --noEmit -p .` — no NEW errors in Phase 67-02 files | PASS (worktree baseline = 12 errors; my files contribute 0) |
| `gui/src/components/ui/dialog.tsx` exists and exports Dialog* primitives | PASS |
| `gui/src/hooks/useTheme.ts` exports `THEMES` constant; `Theme` derives from it | PASS |
| `gui/src/hooks/useWindowMaximized.ts` uses `onResized` + `unlistenRef` cleanup | PASS |
| `gui/src/components/WindowControls.tsx` contains `getCurrentWindow` and `platform()` | PASS |
| `gui/src/components/AboutDialog.tsx` contains `getVersion` and `ramp-nuclear/STREAM.jl` | PASS |
| macOS branch traffic-light hex values (`#ff5f57 / #ffbd2e / #28c840`) | PASS — exactly per UI-SPEC §Color |

### tsc baseline note

The plan's success criterion is "no NEW errors beyond the pre-existing 11 (per STATE.md)". Running `npx tsc --noEmit -p .` against the worktree base (without my changes) reports **12** errors today, not 11. Likely a worktree-base drift (perhaps a shadcn primitive previously contributed; the dialog primitive does not — it compiles clean). All 12 errors are in unrelated files: `StreamNode.tsx` (4 react-flow Handle prop-type errors), `sidebar/__tests__/*` (5), `lib/validation.test.ts` (3). After my changes the count remains **12** — zero regression. Plan 71 still owns reconciliation per STATE.md.

## Deviations from Plan

None — plan executed exactly as written.

Two minor notes:

1. **Render-fallback when plat is null.** The plan doesn't explicitly say what to render between mount and the useEffect setting `plat`. I chose to render the Windows/Linux branch in the `if (plat === "macos")` fallthrough — same as the vitest `platform() throws` path. This means the macOS test must use `flushEffects()` to wait for the useEffect → state-update → re-render cycle before asserting on `.rounded-full` buttons. Documented inline in the test.
2. **shadcn install warnings.** `npm ci` reports 49 vulnerabilities (3 low, 11 moderate, 31 high, 4 critical) inherited from the existing lockfile. Not introduced by this plan; not actionable here. Phase 71 owns reconciliation.

## Authentication Gates

None.

## Known Stubs

None — all artifacts in this plan are fully wired:

- `useWindowMaximized` reads real `isMaximized()` state and updates on real `onResized` events
- `WindowControls` invokes real `minimize() / toggleMaximize() / close()` IPC
- `AboutDialog` resolves the real `getVersion()` from `@tauri-apps/api/app`

The `<AboutDialog />` component is not yet rendered anywhere — that wiring is Plan 03's responsibility (HelpMenu opens it via local `useState`). This is the intentional plan-boundary, not a stub.

## Plan 03 Awareness

For the executor of Plan 67-03:

- **All four leaf primitives are importable**: `import WindowControls from "./WindowControls"`, `import AboutDialog from "./AboutDialog"`, `import { useWindowMaximized } from "../hooks/useWindowMaximized"`, `import { THEMES, type Theme } from "../hooks/useTheme"`.
- **No new npm dependencies were added.** `npm ci` is sufficient — no `npm install` needed.
- **No extra Radix peer deps from `shadcn add dialog`.** The `radix-ui` meta package was already present in `node_modules` (prior shadcn primitives pulled it). Dialog is internally a re-export.
- **ViewMenu (Plan 03) maps over `THEMES`** per D-21 — example:
  ```tsx
  import { THEMES, type Theme } from "../../hooks/useTheme";
  // ...
  {THEMES.map((t) => (
    <DropdownMenuRadioItem key={t} value={t}>
      {/* icon + label */}
    </DropdownMenuRadioItem>
  ))}
  ```
- **WindowControls's pre-mount render is the Windows/Linux variant.** If Plan 03's UAT screenshots the titlebar at first frame on macOS, expect a brief flash of Lucide icons before traffic-lights settle (one render-cycle, < 16ms). Not a regression — same behavior as the vitest fallback path.

## Self-Check: PASSED

- gui/src/hooks/useTheme.ts: FOUND (modified — `THEMES` exported)
- gui/src/hooks/useWindowMaximized.ts: FOUND (new)
- gui/src/components/WindowControls.tsx: FOUND (new)
- gui/src/components/__tests__/WindowControls.test.tsx: FOUND (new)
- gui/src/components/ui/dialog.tsx: FOUND (new, auto-generated)
- gui/src/components/AboutDialog.tsx: FOUND (new)
- Commit ef69cdc: FOUND in git log (Task 1)
- Commit 172ad04: FOUND in git log (Task 2 RED)
- Commit 229ba8c: FOUND in git log (Task 2 GREEN)
- Commit 4cc0496: FOUND in git log (Task 3)
