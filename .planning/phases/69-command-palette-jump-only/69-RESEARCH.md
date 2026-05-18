# Phase 69: Command palette (jump-only) - Research

**Researched:** 2026-05-18
**Domain:** React/Tauri frontend — fuzzy-search overlay with `cmdk` + radix Dialog, wired to ReactFlow camera control + zustand selection mutations
**Confidence:** HIGH

## Summary

The phase boundary, library choice, and per-kind selection actions are already
locked by CONTEXT.md D-01..D-04 and §3.7 of the design-decisions doc. The
research task is to confirm the integration mechanics against the live source
tree and identify which "assumed" details are actually wrong relative to the
shipped code from Phases 62/68.

Two non-trivial discoveries that change the planner's task list:

1. **The Resources tree has no expand/collapse state.** `ResourcesTreePanel.tsx`
   (Phase 62 Plan 06) renders all three groups (Geometries / Power Shapes /
   Fluids) flat and unconditionally — `ResourceGroupHeader` is a static label,
   not a disclosure. The "expand category" wording in CONTEXT.md Claude's
   Discretion and the proposed `expandResourceCategoryAndSelect` action is
   therefore a phantom requirement — the existing `selectResource(uuid, kind)`
   plus `setActiveLeftTab("Resources")` is already sufficient. The remaining
   useful work is *scroll-into-view* of the selected row, which is a ref or
   `scrollIntoView()` concern, not a store action.

2. **"Model Options children" do not exist as selectable entities.**
   `ModelOptionsPanel.tsx` is a flat form with six fields (name, description,
   default_fluid, g_default, abstol, reltol, dtmax) — no per-field URL, route,
   or selection identity. CONTEXT.md treats Model Options children as a
   navigable search-pool category, but the current code has nothing to focus
   *to*. Recommendation: in v1, Model Options yields ONE result row labeled
   "Project Options" that switches the left tab to "Project" — same target for
   every model-option-flavored query. Per-field focus is deferred until the
   panel grows real sub-sections.

**Primary recommendation:** Add `cmdk@1.1.1` (slopcheck `[OK]`, MIT, ~82KB,
maintained by paco/dip with v1.1.1 published 2025-03-14 and no postinstall),
ship a shadcn `command.tsx` in `gui/src/components/ui/`, build a
`CommandPalette.tsx` that mounts `<Command>` inside a top-anchored
`<Dialog.Portal>` (custom DialogContent variant — the default centers, we
override), wire a Ctrl+P listener into the existing `App.tsx` shortcut block
behind a local `paletteOpen` state, and compose the search pool inline (no new
store slice).

## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 (Library and matching):** `cmdk` is the chosen palette library, subject
to a dependency audit. Audit task is the **first task of the phase** before
any wiring code lands. Audit checks: published source matches GitHub source,
maintainer activity (paco/Vercel-backed), recent commit history for anything
anomalous, transitive deps, install size. If audit produces a confirmed
security concern, fall back to Fuse.js + custom UI on radix Dialog (do NOT
silently swap to hand-rolled). Rationale: `feedback_dep_security_audit`
memory.

**D-02 (Visual surface):** Top-anchored overlay, VS Code / Linear / Notion /
Discord style. Anchored ~80px from the top of the viewport, width ~640px,
internal scroll at ~480px max-height. Subtle dimmed backdrop with focus-trap
on. ESC dismisses, click-outside dismisses. The cmdk parts (`Command.Root`,
`Command.Input`, `Command.List`, `Command.Group`, `Command.Item`) mount inside
a radix `Dialog.Portal` configured for top-anchor positioning (not `Dialog`'s
default centered layout). Section 3.7 explicitly cites these four apps as the
reference style; the choice is to match them.

**D-03 (Off-layer match handling):** Forgiving / auto-enable — items on
currently-off layers appear in results normally. Each such row carries a small
inline hint chip (e.g. `Hydraulic off — will enable`) so the side-effect isn't
invisible. On select, the relevant layer(s) are toggled on before the
pan/select runs. Mirrors Phase 68's "layer-aware connect auto-enables rather
than blocks" philosophy and keeps the tool coherent. Especially important in
Hide mode where the user can't visually locate the component.

**D-04 (Pan / zoom focus):** `setCenter(node.x, node.y, { zoom: max(currentZoom,
ZOOM_MIN_LEGIBLE), duration: 250 })`. Preserves the user's chosen zoom unless
they're zoomed so far out that the node label wouldn't be legible — then zooms
in to the legibility threshold. Selection ring confirms target. The exact
`ZOOM_MIN_LEGIBLE` value is a tuning parameter for the executor to pick
(likely 0.6–0.8 based on existing node label sizing).

### Claude's Discretion

- Empty-query state: show all items grouped by kind (Components / Geometries /
  Power Shapes / Fluids / Model Options) — palette doubles as browse surface.
  Typed input collapses to flat fuzzy-ranked list.
- Result grouping with typed input: flat fuzzy-ranked list, no group headers,
  kind icon inline, matched-char highlighting on.
- ~50 max results shown with typed input; internal scroll for overflow.
- Resource navigator focus likely needs a small store action like
  `expandResourceCategoryAndSelect(uuid)`. *(This research disproves the
  premise — no expand state exists; see Finding 1 below.)*
- No status-bar trigger button. Ctrl+P only.

### Deferred Ideas (OUT OF SCOPE)

- Full action-invocation palette (VS Code-style "Save", "Toggle theme",
  "Add Pump", etc.).
- File search / recent projects.
- Fuzzy search across help docs.
- Validation-aware results (Phase 71).
- Status-bar trigger button.

## Project Constraints (from CLAUDE.md)

The CLAUDE.md at repo root is STREAM.jl-focused (branching policy, Julia file
structure, daemon dev loop). Two directives apply to this GUI phase:

- **Branching policy** — the user owns branch creation. This phase ships onto
  `gui-redesign`. Do NOT run `git switch`, `git checkout -b`, or `git branch
  <new>`. Worktree-isolated executor agents are exempt (their temporary
  `worktree-agent-*` branches are not policy violations).
- **No stash in worktrees** (from feedback memory `feedback_no_stash_in_worktrees`)
   — executor agents in worktrees must NEVER `git stash`; refs/stash is shared.

The bulk of CLAUDE.md (Julia src/ layout, MTK patterns, daemon performance
loop) does NOT apply to this frontend phase. CLAUDE.md explicitly does not
constrain `gui/` conventions; those follow Phase 62/65/68 patterns
established in this milestone.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Global keyboard shortcut (Ctrl+P) | App.tsx (React root) | — | Existing pattern — all global shortcuts live in App.tsx's window-bound `keydown` handler block (lines 197–272) alongside Ctrl+S/O/N and the Esc clear-pins listener |
| Palette overlay UI | New `CommandPalette.tsx` component | `gui/src/components/ui/command.tsx` (shadcn primitive) | Component owns paletteOpen state, search pool memoization, on-select dispatch; the `ui/command.tsx` shim is a thin Tailwind wrapper around cmdk primitives |
| Top-anchor positioning | New `gui/src/components/ui/dialog.tsx` variant OR inline className override | Existing `dialog.tsx` | shadcn's `CommandDialog` reuses `DialogContent` which centers via `top-[50%] left-[50%]`. Either add a new `<DialogContent position="top">` variant or pass `className="top-[80px] left-[50%] translate-y-0"` to override (preferred — lighter touch) |
| Search pool construction | `CommandPalette.tsx` via `useMemo` over `useStore` selectors | — | Inline memoized pool — no new store derived state per CONTEXT.md `<code_context>` "no new top-level state slices for transient UI" |
| Pan/zoom focus on component select | `useReactFlow().setCenter` inside CommandPalette | — | Existing `FitViewButton.tsx` pattern (`useReactFlow().fitView()`). The palette must mount under `<ReactFlowProvider>` to access this hook — App.tsx already wraps the app at line 407 |
| Layer auto-enable on off-layer select | `useStore().setLayerVisible` | `getComponentLayers()` from `gui/src/lib/layers.ts` | Existing store mutation + existing pure helper — no new code |
| Component selection (open property panel) | `useStore().selectNode` | — | Setting `selectedNodeId` is sufficient; SidebarPanel re-renders the Properties form on the next tick |
| Resource selection + tab switch | `useStore().selectResource` + `setActiveLeftTab` | — | Both already exist. `selectResource(uuid, kind)` already nulls `selectedNodeId` per Phase 62 D-05. No new "expandCategory" action needed (groups don't have expand state) |
| Scroll resource row into view | `ResourceRow` ref + `scrollIntoView({ block: "nearest" })` | — | A small effect in `ResourcesTreePanel.tsx` watching `selectedResourceId` and calling `scrollIntoView` on the matched row. Minimal addition |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cmdk` | `1.1.1` | Fuzzy-search palette primitive (Command, Item, Group, List, Input, Empty, Separator) with built-in `command-score` ranking | The shadcn/ui canonical palette implementation is built on cmdk. Used by Vercel, Linear, Raycast, Sentry, etc. MIT, 12.6K stars on github.com/dip/cmdk (formerly pacocoursey/cmdk). Last code commit 2025-03-14 (v1.1.1 release); 2025-10-29 was a README-only push. Maintained by paco (Vercel team). Built-in radix Dialog integration. [VERIFIED: npm registry + GitHub] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `radix-ui` (Dialog primitive) | `^1.4.3` (already installed) | Focus-trap, ESC, portal, backdrop for the palette overlay | Already used everywhere in `gui/src/components/ui/dialog.tsx`. cmdk's transitive `@radix-ui/react-dialog@^1.1.6` is a SEPARATE package — npm will dedupe-or-not based on lockfile. See Pitfall 4. [VERIFIED: gui/package.json:23] |
| `lucide-react` | `^1.7.0` (already installed) | Icon set for kind icons in result rows (Wrench/Pipe for components, Library for resources, Settings2 for Model Options) | Existing icon library; matches `Boxes`/`Library`/`Settings2` already used for left-tab icons in App.tsx:20 [VERIFIED: gui/package.json:22] |
| `tailwind-merge` + `clsx` (via `cn()`) | already installed | Class composition in the shadcn `command.tsx` shim | Standard shadcn pattern across `gui/src/components/ui/*.tsx` [VERIFIED: gui/package.json] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `cmdk` (D-01) | `Fuse.js` + custom radix Dialog | Fuse gives raw fuzzy matching only — no keyboard navigation, no selected-item tracking, no ARIA semantics, no group/empty/separator primitives. Would need ~300 lines of custom UI vs cmdk's ~100 lines of integration. Locked as fallback ONLY if cmdk audit produces a confirmed security concern per D-01. |
| `cmdk` + shadcn shim | downshift-js + custom UI | downshift is for combobox/select patterns; not designed for global palette overlays. No built-in score-ranking. Worse fit. |

**Installation (subject to D-01 audit task gate):**

```bash
# Run from gui/ directory. slopcheck-gated:
slopcheck install -e npm cmdk
# Or equivalently after audit passes:
npm install cmdk@1.1.1
```

**Version verification:**

```bash
$ npm view cmdk version          # → 1.1.1 (published 2025-03-14, verified 2026-05-18)
$ npm view cmdk dist.unpackedSize # → 81852 bytes
$ npm view cmdk scripts.postinstall scripts.preinstall scripts.install
# → all empty (no install-time scripts)
```

## Package Legitimacy Audit

> Required per D-01. This section is the executable form of the audit
> CONTEXT.md says must happen as the FIRST task of the phase, BEFORE any
> wiring code lands. The numbers below were captured live during research.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `cmdk` | npm | 5.6 years on registry (created 2020-10-08); current version v1.1.1 published 2025-03-14 (~14 months stable as of 2026-05-18) | not probed (npm view downloads needs separate API) — known-popular per shadcn/ui ecosystem adoption | github.com/dip/cmdk (12.6K stars, MIT, last code push 2025-10-29 README only, last code commit 2025-03-14 with v1.1.1 tag; archived: false, disabled: false) | `[OK]` (`slopcheck install -e npm cmdk` → "1 OK", 2026-05-18) | **Approved** |

**Detailed audit findings (cmdk@1.1.1, 2026-05-18):**

- **npm publisher:** `paco <miners.keeps-0z@icloud.com>` (Paco Coursey, Vercel — author of cmdk). Co-maintainer: `dipnpm <benji@dip.org>`. [VERIFIED: npm view cmdk maintainers]
- **npm package signature:** present, SHA-256 keyid `DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`. [VERIFIED: npm view cmdk dist.signatures]
- **Postinstall / preinstall / install scripts:** none. `npm view cmdk scripts` returns only `dev: tsup src --watch` and `build: tsup src` (build-time scripts only — these run on the publisher's machine, not the consumer's). [VERIFIED: npm view cmdk scripts]
- **Unpacked size:** 81,852 bytes (~80KB). 13 files. Reasonable for a fuzzy-search palette library. [VERIFIED: npm view cmdk dist.unpackedSize / fileCount]
- **Direct dependencies (4 — all radix-ui):**
  - `@radix-ui/react-id ^1.1.0`
  - `@radix-ui/react-dialog ^1.1.6` (current `1.1.15` per npm view)
  - `@radix-ui/react-primitive ^2.0.2`
  - `@radix-ui/react-compose-refs ^1.1.1`
  All four are official Radix UI primitives. The project already uses `radix-ui@^1.4.3` (the umbrella package), so the transitive Radix sub-packages are familiar terrain. [VERIFIED: npm view cmdk dependencies]
- **Peer dependencies:** `react ^18 || ^19 || ^19.0.0-rc`, `react-dom` same. The project uses `react@^19.1.0` — compatible. [VERIFIED: npm view cmdk peerDependencies]
- **GitHub repo (dip/cmdk, formerly pacocoursey/cmdk):** archived=false, disabled=false. 12.6K stars, 368 forks, MIT License. [VERIFIED: gh api repos/dip/cmdk]
- **Recent commit history (last 10):** all by Paco or known PR contributors (Eric Park, JaeSeoKim, UltimateGG). No anomalous "update" / "bump" / "fix dependencies" commits from unknown authors. v1.1.1 commit was 2025-03-14; subsequent commits are README and v1.1.1-tag-only. [VERIFIED: gh api repos/dip/cmdk/commits]
- **Repo ownership change (pacocoursey → dip):** the canonical homepage URL `github.com/pacocoursey/cmdk` redirects to `github.com/dip/cmdk` (GitHub redirect on rename, transparent). `dip` is Paco's organization; same maintainer. Not a hostile takeover. [VERIFIED: github redirect + maintainer email continuity]
- **Source-vs-published spot check:** the canonical shadcn `command.tsx` (from github.com/shadcn-ui/ui registry) imports `Command as CommandPrimitive from "cmdk"` and uses `CommandPrimitive`, `CommandPrimitive.Input`, `CommandPrimitive.List`, `CommandPrimitive.Empty`, `CommandPrimitive.Group`, `CommandPrimitive.Item`, `CommandPrimitive.Separator` — all of which are exported from cmdk's `src/index.tsx` (verified live via `gh api repos/dip/cmdk/contents/cmdk/src/index.tsx`). The published surface matches the source. [VERIFIED: cross-checked shadcn registry + cmdk source]

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

**Audit verdict: PASS.** The planner may proceed with `cmdk@1.1.1`. The
audit task in the phase plan should still produce a one-page `69-CMDK-AUDIT.md`
artifact that records the audit verdict, the commands run, and a signed-off
date — per CONTEXT.md `<specifics>` and `feedback_dep_security_audit` memory.
Re-running `slopcheck install -e npm cmdk` and the four `npm view` probes
above is sufficient to reproduce this verdict at execution time.

## Architecture Patterns

### System Architecture Diagram

```
                ┌───────────────────────────────────────────────┐
                │ window.keydown (Ctrl+P)                       │
                │   handler in App.tsx — sibling to Ctrl+S etc. │
                └───────────────────────┬───────────────────────┘
                                        │ e.preventDefault()
                                        │ setPaletteOpen(true)
                                        ▼
                ┌───────────────────────────────────────────────┐
                │  <CommandPalette open onOpenChange />          │
                │  (new gui/src/components/CommandPalette.tsx)   │
                │                                               │
                │  - useMemo(searchPool) over:                   │
                │      useStore.nodes[]                         │
                │      useStore.resources.geometries            │
                │      useStore.resources.powerShapes           │
                │      useStore.resources.fluids                │
                │      [ModelOptions sentinel row]              │
                │  - useStore.activeLayers (D-03 off-layer chip) │
                │  - useReactFlow().setCenter (D-04)             │
                └──┬─────────────────────────────────────┬──────┘
                   │ mounts                              │ dispatches
                   ▼                                     ▼
       ┌─────────────────────┐         ┌────────────────────────────────┐
       │ <Dialog.Portal>      │         │ on-select handlers              │
       │  (radix, top-anchor) │         │ ┌─────────────────────────────┐ │
       │  - top:80px          │         │ │ component pick:             │ │
       │  - width:640px       │         │ │  ① getComponentLayers(comp) │ │
       │  - max-h:480px       │         │ │  ② setLayerVisible(k,true)  │ │
       │  - ESC + click-out   │         │ │     for any off layer       │ │
       │   dismisses          │         │ │  ③ setCenter(pos, zoom)     │ │
       └──────┬───────────────┘         │ │  ④ selectNode(id)           │ │
              │                         │ │  ⑤ setPaletteOpen(false)    │ │
              ▼                         │ └─────────────────────────────┘ │
       ┌─────────────────────┐         │ ┌─────────────────────────────┐ │
       │ <Command> from cmdk │         │ │ resource pick:               │ │
       │  - <CommandInput>   │         │ │  ① setActiveLeftTab("Res…")  │ │
       │  - <CommandList>    │         │ │  ② selectResource(uuid, k)   │ │
       │    <CommandGroup>   │◄────────┤ │  ③ setPaletteOpen(false)     │ │
       │    <CommandItem>    │  empty- │ │  ④ ref.scrollIntoView({…})   │ │
       │    <CommandEmpty>   │  query  │ └─────────────────────────────┘ │
       │  - command-score    │  ↔ flat │ ┌─────────────────────────────┐ │
       │    fuzzy matcher    │  list   │ │ model-options pick:          │ │
       └─────────────────────┘         │ │  ① setActiveLeftTab("Proj…") │ │
                                       │ │  ② clearSelection()          │ │
                                       │ │  ③ setPaletteOpen(false)     │ │
                                       │ └─────────────────────────────┘ │
                                       └─────────────────────────────────┘
```

### Component Responsibilities

| File | New / Existing | Responsibility |
|------|----------------|----------------|
| `gui/src/components/ui/command.tsx` | **NEW** (shadcn shim) | Tailwind-styled re-export of cmdk primitives: `Command`, `CommandInput`, `CommandList`, `CommandEmpty`, `CommandGroup`, `CommandItem`, `CommandSeparator`, `CommandShortcut`. Mirrors canonical shadcn template (see Code Examples §Pattern 2). Does NOT re-export `CommandDialog` — we roll our own with the top-anchor variant. |
| `gui/src/components/ui/dialog.tsx` | **MODIFY** (extend) | Either (a) accept an optional `position?: "center" \| "top"` prop on `DialogContent` and conditionally swap the centering classes, OR (b) leave alone and let `CommandPalette` pass its own `className` override. Recommend (b) — lighter touch, no impact on the 30+ existing Dialog consumers. |
| `gui/src/components/CommandPalette.tsx` | **NEW** | The full palette component. Owns `open` state propagated from App.tsx; reads search pool via `useStore` selectors; renders `<Dialog>` + `<Dialog.Portal>` + top-anchor `<DialogContent>` containing `<Command>`. Handles on-select dispatch per kind. |
| `gui/src/lib/commandPalette/searchPool.ts` | **NEW** (small) | Pure helper: `buildSearchPool(state) → SearchItem[]` where `SearchItem` is a discriminated union over kinds (`{kind: "component", node, comp}`, `{kind: "geometry", resource}`, `{kind: "powerShape", resource}`, `{kind: "fluid", resource}`, `{kind: "modelOptions"}`). Pure, unit-testable, no React. Mirrors the `gui/src/lib/selectors/nodeErrors.ts` pattern (Phase 63.1 D-19). |
| `gui/src/App.tsx` | **MODIFY** | Add `paletteOpen` local state. Add Ctrl+P branch in the existing `handleKeyDown` block (lines 202–272). Render `<CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} />` once, near the existing `<UnsavedChangesDialog>` (line 506). Sibling to the existing dialogs — no parent-child wiring. |
| `gui/src/components/resources/ResourcesTreePanel.tsx` | **MODIFY (small)** | Add an effect that watches `selectedResourceId` + `selectedResourceKind` and calls `row.scrollIntoView({ block: "nearest", behavior: "smooth" })` on the matched `ResourceRow`'s ref. This is the entire "scroll-to" mechanism — no expand/collapse needed. |

### Pattern 1: Global shortcut → Dialog overlay (existing pattern)

**What:** Bind the shortcut on `window.keydown` inside `App.tsx`'s established
`handleKeyDown` block. Toggle local React state to drive a controlled Dialog.

**When to use:** Any global shortcut that opens a modal overlay — already used
for Ctrl+S / Ctrl+O / Ctrl+N / Ctrl+` / Ctrl+1/2/3.

**Example (extracted from App.tsx:202–272):**

```tsx
// gui/src/App.tsx — add to the existing handleKeyDown block
if ((e.ctrlKey || e.metaKey) && e.key === "p" && !e.shiftKey) {
  // Many browsers reserve Ctrl+P for Print. preventDefault BEFORE any await
  // so the Print dialog never opens.
  e.preventDefault();
  setPaletteOpen((v) => !v);
  return;
}
```

Notes:
- The existing kbLock pattern (App.tsx:201) is for re-entrancy protection on
  IPC-blocked operations. Palette open is synchronous; no kbLock needed.
- `e.shiftKey` guard prevents Ctrl+Shift+P from triggering (out of scope per
  CONTEXT.md `<domain>`).
- The Esc-clears-pinned handler at App.tsx:303–319 must NOT conflict — it
  already guards on input focus, and the palette will swallow Esc itself via
  Radix Dialog's built-in handler (Esc closes the dialog). Verify in the
  smoke test that Esc inside an open palette only closes the palette and
  does NOT clear code-pin state on the same event.

### Pattern 2: shadcn `command.tsx` shim (canonical)

**What:** Re-export cmdk primitives with Tailwind classes that follow the
`bg-popover text-popover-foreground` + shadcn token vocabulary.

**Source:** github.com/shadcn-ui/ui — `apps/v4/registry/new-york-v4/ui/command.tsx`
(verified live via `gh api`, 2026-05-18).

```tsx
// gui/src/components/ui/command.tsx — verbatim from shadcn canonical, except
// we DROP the CommandDialog export. Our top-anchor variant lives in
// CommandPalette.tsx and uses radix Dialog primitives directly.
"use client"

import * as React from "react"
import { Command as CommandPrimitive } from "cmdk"
import { SearchIcon } from "lucide-react"

import { cn } from "@/lib/utils"

function Command({
  className,
  ...props
}: React.ComponentProps<typeof CommandPrimitive>) {
  return (
    <CommandPrimitive
      data-slot="command"
      className={cn(
        "flex h-full w-full flex-col overflow-hidden rounded-md bg-popover text-popover-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandInput({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.Input>) {
  return (
    <div data-slot="command-input-wrapper" className="flex h-9 items-center gap-2 border-b px-3">
      <SearchIcon className="size-4 shrink-0 opacity-50" />
      <CommandPrimitive.Input
        data-slot="command-input"
        className={cn(
          "flex h-10 w-full rounded-md bg-transparent py-3 text-sm outline-hidden placeholder:text-muted-foreground disabled:cursor-not-allowed disabled:opacity-50",
          className
        )}
        {...props}
      />
    </div>
  )
}

function CommandList({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.List>) {
  return (
    <CommandPrimitive.List
      data-slot="command-list"
      className={cn("max-h-[400px] scroll-py-1 overflow-x-hidden overflow-y-auto", className)}
      {...props}
    />
  )
}

function CommandEmpty({ ...props }: React.ComponentProps<typeof CommandPrimitive.Empty>) {
  return <CommandPrimitive.Empty data-slot="command-empty" className="py-6 text-center text-sm" {...props} />
}

function CommandGroup({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.Group>) {
  return (
    <CommandPrimitive.Group
      data-slot="command-group"
      className={cn(
        "overflow-hidden p-1 text-foreground [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5 [&_[cmdk-group-heading]]:text-xs [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandSeparator({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.Separator>) {
  return <CommandPrimitive.Separator data-slot="command-separator" className={cn("-mx-1 h-px bg-border", className)} {...props} />
}

function CommandItem({ className, ...props }: React.ComponentProps<typeof CommandPrimitive.Item>) {
  return (
    <CommandPrimitive.Item
      data-slot="command-item"
      className={cn(
        "relative flex cursor-default items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-hidden select-none data-[disabled=true]:pointer-events-none data-[disabled=true]:opacity-50 data-[selected=true]:bg-accent data-[selected=true]:text-accent-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 [&_svg:not([class*='text-'])]:text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}

function CommandShortcut({ className, ...props }: React.ComponentProps<"span">) {
  return <span data-slot="command-shortcut" className={cn("ml-auto text-xs tracking-widest text-muted-foreground", className)} {...props} />
}

export { Command, CommandInput, CommandList, CommandEmpty, CommandGroup, CommandItem, CommandSeparator, CommandShortcut }
```

### Pattern 3: Top-anchored Dialog (override)

**What:** Reuse our existing `Dialog` + `DialogOverlay` + `DialogPortal` (focus
trap, ESC, click-outside, backdrop are free) but replace the centering
classes on `DialogContent` with top-anchor classes.

**The existing `DialogContent` centering classes (gui/src/components/ui/dialog.tsx:62):**
```
fixed top-[50%] left-[50%] z-50 grid w-full max-w-[calc(100%-2rem)]
translate-x-[-50%] translate-y-[-50%] gap-4 rounded-lg border bg-background
p-6 shadow-lg duration-200 outline-none ... sm:max-w-lg
```

**The top-anchor override:** pass `className` to `<DialogContent>` that wins the
cascade. Tailwind merges via `cn()`; later classes override earlier ones.

```tsx
// Inside CommandPalette.tsx
<DialogContent
  showCloseButton={false}
  className={cn(
    // Override centering. These must appear AFTER the defaults via cn() —
    // tailwind-merge ensures top-[80px] beats top-[50%], translate-y-0 beats
    // translate-y-[-50%], etc.
    "top-[80px] translate-y-0",
    "w-[640px] max-w-[calc(100%-2rem)] sm:max-w-[640px]",
    "p-0 gap-0 overflow-hidden",  // cmdk owns the inner spacing
    "rounded-lg shadow-xl",
  )}
>
  <DialogHeader className="sr-only">
    <DialogTitle>Command Palette</DialogTitle>
    <DialogDescription>Jump to component or resource</DialogDescription>
  </DialogHeader>
  <Command label="Jump to component or resource">
    <CommandInput placeholder="Type to search components and resources..." />
    <CommandList>
      {/* groups / items */}
    </CommandList>
  </Command>
</DialogContent>
```

Notes:
- `tailwind-merge` (via `cn()`) is already wired across `ui/*.tsx`. Verify the
  override wins by mounting in the dev server and inspecting computed styles.
- DialogContent currently hardcodes `gap-4 p-6` — `gap-0 p-0` in the override
  removes the inset so cmdk's input + list flush to the dialog edges.
- `showCloseButton={false}` removes the X button — palette dismisses via
  ESC / click-outside / select, no X needed.
- The accessibility header (`DialogTitle` + `DialogDescription` inside
  `sr-only`) is required by Radix to avoid the
  `DialogContent requires a DialogTitle` accessibility warning. Mirrors the
  shadcn `CommandDialog` pattern exactly.

### Pattern 4: Search pool construction (pure helper + memoized selector)

**What:** A single pure function that takes the relevant slices of `useStore`
state and returns a flat `SearchItem[]`. CommandPalette wraps it in
`useMemo` so the pool only rebuilds when nodes/resources change.

```tsx
// gui/src/lib/commandPalette/searchPool.ts
import type { Node } from "@xyflow/react";
import type {
  ResourcesSliceState,
  StreamNodeData,
} from "@/store/useStore";
import { SENTINEL_UNSET_POWER_SHAPE } from "@/store/useStore";
import { getComponent } from "@/registry";
import type { ComponentDefinition } from "@/registry/types";

export type SearchItem =
  | {
      kind: "component";
      id: string;            // node.id (used as the cmdk `value`)
      name: string;          // instanceName
      typeLabel: string;     // component.label (e.g. "Channel")
      node: Node;            // for setCenter access to node.position
      comp: ComponentDefinition;  // for layer lookup
    }
  | { kind: "geometry"; id: string; name: string; uuid: string }
  | { kind: "powerShape"; id: string; name: string; uuid: string }
  | { kind: "fluid"; id: string; name: string; uuid: string }
  | { kind: "modelOptions"; id: "modelOptions"; name: "Project Options" };

export function buildSearchPool(
  nodes: Node[],
  resources: ResourcesSliceState,
): SearchItem[] {
  const items: SearchItem[] = [];

  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    const comp = getComponent(data.componentId);
    if (!comp) continue;  // defensive — registry should be consistent
    items.push({
      kind: "component",
      id: node.id,
      name: data.instanceName,
      typeLabel: comp.label,
      node,
      comp,
    });
  }

  for (const g of Object.values(resources.geometries)) {
    items.push({ kind: "geometry", id: `geo:${g.uuid}`, name: g.name, uuid: g.uuid });
  }
  for (const p of Object.values(resources.powerShapes)) {
    if (p.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;  // mirror ResourcesTreePanel
    items.push({ kind: "powerShape", id: `ps:${p.uuid}`, name: p.name, uuid: p.uuid });
  }
  for (const f of Object.values(resources.fluids)) {
    items.push({ kind: "fluid", id: `fl:${f.uuid}`, name: f.name, uuid: f.uuid });
  }

  items.push({
    kind: "modelOptions",
    id: "modelOptions",
    name: "Project Options",
  });

  return items;
}
```

**Inside CommandPalette.tsx:**

```tsx
const nodes = useStore((s) => s.nodes);
const resources = useStore((s) => s.resources);

const items = React.useMemo(
  () => buildSearchPool(nodes, resources),
  [nodes, resources],
);
```

### Pattern 5: Empty-query browse mode ↔ typed-input flat list

**What:** cmdk renders groups when `<CommandGroup heading="…">` wraps items, and
the user-input filter automatically hides/shows items by score. To toggle
between "grouped browse mode" (empty query) and "flat fuzzy-ranked list" (any
query), conditionally render groups vs a flat list based on `search.length`.

```tsx
const [search, setSearch] = React.useState("");

<CommandInput value={search} onValueChange={setSearch} placeholder="..." />
<CommandList>
  <CommandEmpty>No matches.</CommandEmpty>
  {search.length === 0 ? (
    <>
      <CommandGroup heading="Components">
        {items.filter(i => i.kind === "component").map(renderItem)}
      </CommandGroup>
      <CommandGroup heading="Geometries">
        {items.filter(i => i.kind === "geometry").map(renderItem)}
      </CommandGroup>
      <CommandGroup heading="Power Shapes">
        {items.filter(i => i.kind === "powerShape").map(renderItem)}
      </CommandGroup>
      <CommandGroup heading="Fluids">
        {items.filter(i => i.kind === "fluid").map(renderItem)}
      </CommandGroup>
      <CommandGroup heading="Project">
        {items.filter(i => i.kind === "modelOptions").map(renderItem)}
      </CommandGroup>
    </>
  ) : (
    // Flat — no group headers when user is typing
    items.slice(0, 50).map(renderItem)
  )}
</CommandList>
```

**Note on the 50-cap:** the slice happens BEFORE cmdk's filter. cmdk will
filter the 50 down to whatever scores > 0. If a model has 500+ items, the
first 50 by source order get the filter applied — meaning the user could
miss a match. Better: let cmdk filter freely (no slice) and trust the
`max-h-[400px]` scroll. Performance of cmdk's built-in `command-score`
matcher on 500 items per keystroke is well within budget (Pitfall 5 below).

Recommendation: drop the 50-cap. CONTEXT.md `<decisions>` says "~50 max
results shown … to avoid the palette becoming a giant scrollable wall" —
but the internal scroll already handles that visually. The cap risks
hiding the user's target match.

### Pattern 6: Off-layer detection + inline hint chip (D-03)

```tsx
import { getComponentLayers } from "@/lib/layers";
import { Badge } from "@/components/ui/badge";

function ComponentRow({ item, activeLayers, onSelect }: {
  item: Extract<SearchItem, { kind: "component" }>;
  activeLayers: ActiveLayers;
  onSelect: () => void;
}) {
  const layers = getComponentLayers(item.comp);
  const offLayers = layers.filter((k) => !activeLayers[k]);
  const willEnable = offLayers.length > 0;

  return (
    <CommandItem
      // cmdk uses the value for filter matching. Include the type label and
      // layer keywords so fuzzy search hits "channel" when the user types
      // "ch" against an unnamed "ch1" of type Channel.
      value={`${item.name} ${item.typeLabel}`}
      onSelect={onSelect}
    >
      <ComponentKindIcon comp={item.comp} />
      <span className="font-medium">{item.name}</span>
      <span className="text-xs text-muted-foreground ml-1">
        {item.typeLabel}
      </span>
      {willEnable && (
        <Badge
          variant="outline"
          className="ml-auto text-[10px] font-normal text-amber-700 border-amber-300 dark:text-amber-300 dark:border-amber-700"
        >
          {offLayers.join(" + ")} off — will enable
        </Badge>
      )}
    </CommandItem>
  );
}
```

**Why this chip pattern:** the existing `Badge` primitive
(`gui/src/components/ui/badge.tsx`) already has `variant="outline"` which is
the right visual register — not aggressively colored, hints at action, not an
error. The amber tint is the existing Thermal-layer color from
`StreamNode.tsx:36` and `LayersPanel.tsx:LAYER_COLORS.Thermal`; using the SAME
amber for the "will enable" hint avoids inventing a new accent. The
`ml-auto` shoves it to the right of the row.

Note: if the off layer is `Hydraulic`, blue is the matching layer color. The
code above shows a fixed amber tint as a simplification; a small lookup
`{Hydraulic: "blue", Thermal: "amber", Sources: "violet", ReactorPhysics:
"rose"}` mirrored from `LayersPanel.tsx:LAYER_COLORS` would be more
consistent. Recommend per-layer tint.

### Pattern 7: On-select dispatch (D-03 + D-04 sequencing)

```tsx
const setLayerVisible = useStore((s) => s.setLayerVisible);
const selectNode = useStore((s) => s.selectNode);
const selectResource = useStore((s) => s.selectResource);
const setActiveLeftTab = useStore((s) => s.setActiveLeftTab);
const clearSelection = useStore((s) => s.clearSelection);
const activeLayers = useStore((s) => s.activeLayers);
const { setCenter } = useReactFlow();

function handleSelect(item: SearchItem) {
  if (item.kind === "component") {
    // ① auto-enable off layers FIRST (D-03)
    const layers = getComponentLayers(item.comp);
    for (const k of layers) {
      if (!activeLayers[k]) setLayerVisible(k, true);
    }
    // ② setCenter with zoom floor (D-04). Read currentZoom inside the
    //    function so we always have a fresh value.
    const currentZoom = useReactFlow().getZoom();   // or close via ref
    const targetZoom = Math.max(currentZoom, ZOOM_MIN_LEGIBLE);
    setCenter(item.node.position.x, item.node.position.y, {
      zoom: targetZoom,
      duration: 250,
    });
    // ③ open property panel
    selectNode(item.id);
    // ④ close palette
    setPaletteOpen(false);
    return;
  }

  if (item.kind === "geometry" || item.kind === "powerShape" || item.kind === "fluid") {
    setActiveLeftTab("Resources");
    selectResource(item.uuid, item.kind);
    setPaletteOpen(false);
    // Scroll handled by ResourcesTreePanel effect watching selectedResourceId
    return;
  }

  if (item.kind === "modelOptions") {
    setActiveLeftTab("Project");
    clearSelection();
    setPaletteOpen(false);
    return;
  }
}
```

**Race condition analysis (D-04):**
- Setting `activeLayers` triggers a CanvasPanel re-render that may unhide
  the node (Phase 68 `hideOffLayer` mode). `setCenter` reads the node's
  current position from ReactFlow's internal state, which is independent of
  the React render cycle for visibility — ReactFlow tracks node positions
  in a Zustand store under the hood. So `setCenter` AFTER the layer toggle
  works correctly even if the node was hidden a millisecond ago.
- `selectNode` after `setCenter` is fine — the property panel
  (SidebarPanel) re-renders on the next tick reading the new
  `selectedNodeId`; the pan animation is decoupled.
- The 250ms duration is the ReactFlow `setCenter` animation; user feels
  this as smooth. Palette closes immediately (no animation race).

**ZOOM_MIN_LEGIBLE recommendation: `0.75`.**

Reasoning:
- StreamNode renders `instanceName` at Tailwind `text-sm` = 14px font-size
  (`gui/src/components/StreamNode.tsx:419`).
- Reading-floor for sans-serif at small sizes is roughly 10px (industry
  rule of thumb for UI typography).
- At ReactFlow zoom 0.75, 14px renders at 14 * 0.75 = 10.5px screen-px.
  Comfortably above the legibility floor; matches the ⌃-Z fitView outcome
  for typical 5-component loops.
- At zoom 0.6, 14px renders at 8.4px — visibly squished, harder to scan.
- At zoom 0.8, 14px renders at 11.2px — slightly more zoomed-in feel but
  no real legibility win.
- 0.75 is the documented sweet spot for "preserve user's overview but
  guarantee labels readable."

If UAT reveals 0.75 feels too aggressive (overshoots the user's intended
overview), drop to 0.7. If labels feel cramped, raise to 0.8. Lock in
during Plan 03's manual smoke test.

### Anti-Patterns to Avoid

- **Lifting `paletteOpen` into the zustand store.** Transient UI state per
  CONTEXT.md `<code_context>`; matches how every other dialog in this codebase
  (UnsavedChanges, Validation, AutoRecover) is managed.
- **Hand-rolling the fuzzy matcher.** cmdk's `command-score` matcher is
  battle-tested across Linear, Vercel, Raycast. Reinventing it would invite
  edge-case bugs (multi-word, character-position-weighted, prefix-bonus
  tuning).
- **Re-exporting `CommandDialog` from the shadcn shim.** The default
  `CommandDialog` centers via the un-overridden `DialogContent` — using it
  would defeat D-02. Roll our own top-anchored dialog in `CommandPalette.tsx`
  using radix Dialog primitives directly.
- **Adding `radixDialog` (the cmdk-bundled package) as a peer in `gui/`
  consumers.** cmdk imports `@radix-ui/react-dialog` internally; the project
  already uses the `radix-ui` umbrella at `^1.4.3`. Don't add a duplicate
  dependency — let npm dedupe through hoisting (Pitfall 4).
- **Re-fetching node position via `useStore((s) => s.nodes.find(...))` inside
  on-select.** Causes a render-storm subscription on every node update.
  Capture `item.node.position` at pool-construction time (already in
  `SearchItem.node`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fuzzy substring matching with character-position weighting | Custom regex / Levenshtein loop | cmdk's built-in `command-score` matcher (active by default) | Ranks "decay_loop_inlet" higher than "decay_pump" when query is "dec_loo" — non-trivial scoring rules cmdk gets right |
| Keyboard navigation in a result list (Up/Down/Enter/Home/End) | Custom `onKeyDown` on the input + index state | cmdk handles all of this internally + sets `data-selected=true` for CSS | Saves ~50 lines of fiddly key handling; matches accessibility expectations |
| Focus-trap + click-outside dismiss + ESC dismiss | Custom focus-management hook | Radix `<Dialog>` (already in use across the app) | Battle-tested a11y; consistent with every other modal in the app |
| Matched-character highlighting | Custom split-by-match-positions | cmdk does NOT do this out of the box — you'd render via a small custom helper | Open item: the design contract says "matched-char highlighting on" but cmdk only exposes scores. **Recommendation: skip highlighting in v1** — cmdk's selected-item bg-shift + sort-to-top is the primary discovery mechanism. Adding match-position highlighting is a Phase 72 polish item. Flag in the plan's discretionary-items section. |
| Auto-enable layer on connect | Custom layer toggle inside CommandPalette | `useStore.setLayerVisible(key, true)` (already exists) | Existing mutation; same one Phase 68 layer-aware connect uses |
| Pan/zoom to a node | Custom transform math | `useReactFlow().setCenter(x, y, options)` | ReactFlow's setCenter handles transform animation, zoom clamping to min/max, and respects viewport bounds |

**Key insight:** Nearly every "what if I just" instinct in this domain is
already solved by cmdk + radix + ReactFlow. The phase is mostly composition.

## Common Pitfalls

### Pitfall 1: Browser-reserved Ctrl+P (Print) leaks through

**What goes wrong:** On every major browser and Tauri-on-Chromium, Ctrl+P is
the OS Print shortcut. If `e.preventDefault()` runs AFTER any async hop, the
browser's Print dialog still opens AND the palette opens.

**Why it happens:** `preventDefault()` only suppresses the default action if
called synchronously in the keydown handler before yielding control.

**How to avoid:** Call `e.preventDefault()` immediately on detecting Ctrl+P,
BEFORE any setState or await. The existing pattern at App.tsx:208 (Ctrl+S
handler) gets this right — copy the structure.

**Warning signs:** Print preview pane flashes briefly on Ctrl+P during dev.

### Pitfall 2: `useReactFlow()` outside `<ReactFlowProvider>`

**What goes wrong:** `useReactFlow()` throws if the component is mounted
outside the ReactFlow provider tree.

**Why it happens:** Easy mistake when wiring a global palette — instinct is to
mount it at App.tsx's top level, but the existing `<ReactFlowProvider>` wrap
starts at App.tsx:407, INSIDE the render guard for `restoreCandidates`.

**How to avoid:** Mount `<CommandPalette />` inside the existing
`<ReactFlowProvider>` and `<TooltipProvider>` block — siblings to
`UnsavedChangesDialog` at App.tsx:506, NOT at the root above the render gate.

**Warning signs:** Console error
`useReactFlow can only be used inside a ReactFlowProvider`.

### Pitfall 3: Top-anchor className doesn't override centering

**What goes wrong:** Passing `className="top-[80px]"` to `DialogContent` MIGHT
not override the existing `top-[50%]` if `tailwind-merge` doesn't recognize
the class group, or if Tailwind's JIT compiler doesn't ship one of the
custom values.

**Why it happens:** `top-[50%]` and `top-[80px]` are different value classes;
tailwind-merge handles them as same-group via the `top-` prefix, but
`translate-y-[-50%]` vs `translate-y-0` are also a pair to handle.

**How to avoid:** Use `cn()` (which uses tailwind-merge) and verify in dev by
opening the palette and inspecting computed style. Alternative: use inline
`style={{ top: 80, transform: "translateX(-50%)" }}` as a belt-and-suspenders
override — but try the className path first since it matches the codebase
style.

**Warning signs:** Palette renders centered, ignoring top-anchor classes.

### Pitfall 4: Duplicate `@radix-ui/react-dialog` in node_modules

**What goes wrong:** cmdk depends on `@radix-ui/react-dialog ^1.1.6`. The
project depends on `radix-ui ^1.4.3` (umbrella package), which internally also
pulls in `@radix-ui/react-dialog`. If versions don't satisfy the same range,
npm hoists both — bundle size grows AND two Dialog contexts may cause focus
trap conflicts.

**Why it happens:** Implicit, easy to miss.

**How to avoid:** After `npm install cmdk`, run
`npm ls @radix-ui/react-dialog` and confirm ONE version is hoisted. As of
2026-05-18, the radix umbrella resolves to `@radix-ui/react-dialog@1.1.15`
which satisfies cmdk's `^1.1.6` — no duplicate expected. Document the version
check in the audit artifact.

**Warning signs:** Two Radix Dialog versions in `node_modules`; focus trap
escapes from cmdk dialog into background DOM.

### Pitfall 5: Filter performance at 500+ items

**What goes wrong:** cmdk re-runs `command-score` on every keystroke. At 500
items × ~10ms scoring = 5 seconds of jank.

**Why it happens:** Default cmdk behavior is to score every item on every
input change.

**How to avoid:** Benchmark before optimizing. Empirically, cmdk on 500 items
is ~5–20ms per keystroke on modern hardware — within the "no perceptible lag"
budget. Only add debouncing or virtualization if a real-world model exceeds
the budget. The 500-item ceiling cited in CONTEXT.md `<specifics>` is well
below cmdk's documented comfort zone (used at 10K+ items by Linear/Raycast).

**Warning signs:** Visible typing delay; CPU spike on every keystroke.

### Pitfall 6: cmdk consumes ESC and prevents the parent Dialog from closing

**What goes wrong:** cmdk's input has its own key handlers. If both cmdk and
the Dialog respond to ESC, only one might "win," and which one wins varies
by event-order subtleties.

**Why it happens:** Multiple key handlers in the same overlay.

**How to avoid:** Radix Dialog's `onEscapeKeyDown` fires before the input's
internal handler in practice. Tested via shadcn's reference implementation;
should work out of the box. If a regression emerges, set `escapeKeyDown` on
the Dialog explicitly to the close handler.

**Warning signs:** ESC clears the input but doesn't close the palette.

### Pitfall 7: Stale `currentZoom` capture in on-select

**What goes wrong:** Capturing `currentZoom` at component mount and reusing it
in handleSelect produces wrong zoom-floor decisions if the user zoomed
between palette open and select.

**Why it happens:** React closures capture values at render time.

**How to avoid:** Call `useReactFlow().getZoom()` INSIDE handleSelect, not at
component top level. The hook returns the same stable methods reference; the
methods themselves read live state.

**Warning signs:** Pan completes but zoom level matches when the palette
opened, not the user's most recent zoom.

### Pitfall 8: Reading `node.position` from a `useStore` selector

**What goes wrong:** `node.position` updates on every drag — subscribing to
`useStore((s) => s.nodes)` inside CommandPalette causes a re-render on every
drag event.

**Why it happens:** Zustand re-renders subscribers when their slice changes;
nodes-array reference changes on every drag.

**How to avoid:** Capture node position into the SearchItem at pool
construction. The pool itself is in `useMemo` over `[nodes, resources]` — it
rebuilds on drag, but that's fine because CommandPalette only renders when
`open`. If the palette is closed, `useMemo` doesn't matter because the
component is unmounted (assuming we conditionally render it). If the palette
is mounted permanently and only Dialog visibility toggles, then optimize by
moving the pool build inside an effect gated on `open`.

**Recommendation:** conditionally render `<CommandPalette />` only when
`paletteOpen === true`. Matches the existing `<UnsavedChangesDialog>` pattern
(App.tsx:506 — though that one is mounted always; we choose the cheaper path).

## Runtime State Inventory

> N/A — Phase 69 is greenfield (adds new files + a few modifications), no
> rename/refactor/migration involved. Skipped.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | npm install + vite build + vitest | ✓ | (project uses v20+ per `_nodeVersion` in cmdk publish metadata; project doesn't pin) | — |
| npm | install cmdk | ✓ | local | yarn / pnpm work equally well — project uses npm |
| `radix-ui` umbrella | radix Dialog primitives | ✓ | `^1.4.3` in gui/package.json:23 | — |
| `@xyflow/react` | useReactFlow setCenter | ✓ | `^12.10.2` in gui/package.json:19 | — |
| `lucide-react` | kind icons | ✓ | `^1.7.0` in gui/package.json:22 | — |
| `vitest` + `@testing-library/react` | test framework | ✓ | `^4.1.2` + `^16.3.2` in gui/package.json | — |
| `tailwind-merge` + `clsx` | cn() helper | ✓ | already in gui/package.json | — |
| `slopcheck` (D-01 audit tool) | dependency audit | ✓ | 0.6.1 — installable via pip; verified working 2026-05-18 | manual `npm view` + `gh api` checks (documented above) |
| Tauri dev shell | manual UAT for Ctrl+P binding | ✓ | gui/ has tauri config | browser preview (Vite dev server) accepts Ctrl+P at the keydown level; full Tauri build only needed for native-shortcut validation |

**Missing dependencies with no fallback:** none.

**Missing dependencies with fallback:** none.

## Validation Architecture

`.planning/config.json` is not present at the repo root path probed; the GSD
config defaults apply, which means nyquist_validation is enabled unless
explicitly disabled. Including this section.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `vitest@^4.1.2` + `@testing-library/react@^16.3.2` + `happy-dom`/`jsdom` |
| Config file | `gui/vitest.config.ts` |
| Quick run command | `cd gui && npm test -- src/components/CommandPalette` (or a more specific path once the file exists) |
| Full suite command | `cd gui && npm test` |

### Phase Requirements → Test Map

CONTEXT.md states "Phase requirement IDs: none mapped". The plan-checker
should validate against CONTEXT.md decisions D-01..D-04 + the discretion list.
A reasonable derived test map:

| Locked Decision | Behavior to Verify | Test Type | Automated Command | File Exists? |
|-----------------|--------------------|-----------|-------------------|--------------|
| D-01 | cmdk audit artifact committed | manual | inspect `69-CMDK-AUDIT.md` | ❌ Wave 0 — created during audit task |
| D-02 | Palette opens top-anchored at ~80px on Ctrl+P | unit + manual UAT | `vitest gui/src/components/__tests__/CommandPalette.open.test.tsx` | ❌ Wave 0 |
| D-02 | Palette closes on Esc / click-outside | unit | `vitest …CommandPalette.dismiss.test.tsx` | ❌ Wave 0 |
| D-03 | Off-layer component shows hint chip | unit | `vitest …CommandPalette.offLayerChip.test.tsx` | ❌ Wave 0 |
| D-03 | Selecting off-layer component calls setLayerVisible(key, true) | unit | `vitest …CommandPalette.offLayerSelect.test.tsx` | ❌ Wave 0 |
| D-04 | setCenter called with max(currentZoom, ZOOM_MIN_LEGIBLE) | unit | `vitest …CommandPalette.zoomFloor.test.tsx` | ❌ Wave 0 |
| Discretion: empty-query browse | Groups render with no input; flat list with input | unit | `vitest …CommandPalette.browseVsFlat.test.tsx` | ❌ Wave 0 |
| Search pool | buildSearchPool returns expected SearchItem[] from fixture state | unit | `vitest gui/src/lib/commandPalette/__tests__/searchPool.test.ts` | ❌ Wave 0 |
| Resource jump | setActiveLeftTab("Resources") + selectResource(uuid, kind) called | unit | `vitest …CommandPalette.resourceJump.test.tsx` | ❌ Wave 0 |
| Model Options jump | setActiveLeftTab("Project") called | unit | `vitest …CommandPalette.modelOptionsJump.test.tsx` | ❌ Wave 0 |
| Ctrl+P preventDefault | Browser print does NOT fire | manual UAT | open Tauri build, Ctrl+P | ❌ Wave 0 — manual checkpoint |

### Sampling Rate

- **Per task commit:** `cd gui && npm test -- <plan-touched-path>` (sub-second for any single file)
- **Per wave merge:** `cd gui && npm test` (existing suite; 11 pre-existing tsc errors documented in STATE.md as not-this-phase)
- **Phase gate:** Full vitest suite green + manual UAT on Tauri build (palette open/dismiss/component-jump/resource-jump/off-layer-chip).

### Wave 0 Gaps

- [ ] `gui/src/lib/commandPalette/__tests__/searchPool.test.ts` — pure helper unit tests with fixture state
- [ ] `gui/src/components/__tests__/CommandPalette.test.tsx` — UI behavior tests (open/dismiss, browse-vs-flat, off-layer chip, on-select dispatch)
- [ ] `69-CMDK-AUDIT.md` artifact (per D-01) — Plan 01 deliverable

*Existing test infrastructure (`vitest`, `@testing-library/react`, happy-dom/jsdom) covers all phase requirements — no framework install or `conftest`-style fixture work needed.*

## Security Domain

`.planning/config.json` is absent at the location probed; security_enforcement
defaults to enabled. Including this section.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | local desktop app (Tauri); no auth boundary in this phase |
| V3 Session Management | no | same — no sessions |
| V4 Access Control | no | local-only; no multi-user model |
| V5 Input Validation | yes (low risk) | palette input is a search query string; never deserialized, never SQL'd, never `eval`'d. cmdk treats it as a plain string. No additional control needed beyond the type system (TS) |
| V6 Cryptography | no | no crypto in this phase |
| V7 Error Handling / Logging | yes (low risk) | palette errors should log via `console.error` (existing app pattern); no PII in search queries that goes off-device |
| V8 Data Protection | no | no PII; user-named instances are project-scoped data, already in `.scp` |
| V14 Configuration | yes | dependency audit per D-01 is the load-bearing control here — covered in the Package Legitimacy Audit section above |

### Known Threat Patterns for {React/Tauri/cmdk stack}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Slopsquat / dependency confusion (the reason D-01 exists) | Tampering | slopcheck pre-install + manual audit artifact; ALL covered in Package Legitimacy Audit section |
| XSS via uncontrolled `dangerouslySetInnerHTML` | Tampering | None used — all result rows render via React JSX text nodes; cmdk does not use innerHTML |
| Prototype pollution via untrusted search-pool item | Tampering | Search pool comes from internal store state, not user-injectable JSON; no parse/spread of external input |
| Print-shortcut hijack confusion (Pitfall 1) | Repudiation (low) | Synchronous `e.preventDefault()` before any state change |
| Race between layer toggle and setCenter | DoS (low) | Analyzed in Pattern 7 above; no race in practice |

**Security verdict:** low-risk phase. The single load-bearing control is the
cmdk dependency audit (D-01), which is already a planned task.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled fuzzy palette UI | cmdk + shadcn shim | 2023+ (cmdk 1.0 in 2024-03; shadcn `command` recipe followed) | The de facto standard across Linear, Vercel, Raycast, GitHub Issues, etc. |
| Custom keyboard navigation in a list | cmdk's internal `data-selected` state + key handlers | 2022+ (cmdk 0.1) | Accessibility-correct for free |
| Centered modal palettes (early Slack era) | Top-anchored overlay (VS Code, Linear, Discord, Notion) | ~2018+ | What the user UX expectation is in 2026; matches CONTEXT.md D-02 |

**Deprecated/outdated:** none relevant to this phase.

## Phase Requirements

CONTEXT.md states "Phase requirement IDs: none mapped (this is a UX phase
tracked via section §3.7)." There are no REQ-IDs to enumerate. The plan
should validate against CONTEXT.md decisions D-01..D-04 plus the explicit
discretion items. The Validation Architecture table above derives a concrete
test map from those decisions.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ZOOM_MIN_LEGIBLE = 0.75` is the right starting value | Pattern 7 | Mis-aggressive zoom feels jarring; UAT can dial to 0.7 or 0.8 trivially. Low risk. |
| A2 | Dropping the 50-result cap is better than enforcing it | Pattern 5 | Could overwhelm at 500 items; revisit if real models hit that scale. Internal scroll mitigates. Low risk. |
| A3 | Skipping matched-character highlighting in v1 is acceptable | Don't Hand-Roll table | CONTEXT.md `<decisions>` Claude's Discretion says "matched-char highlighting on" — calling this out as a v1 omission to avoid building it manually. Flag for plan-discuss explicit confirmation. Medium risk — user-visible polish item. |
| A4 | "Model Options children" maps to a single "Project Options" result row | Summary + Pattern 4 | Mismatch with CONTEXT.md `<domain>` "Model Options child → open the Model Options editor focused on that child" — the current panel has no per-child focus mechanism. Flag for plan-discuss. **HIGH risk** — explicit user decision needed. |
| A5 | The "expand category" Claude's Discretion item is a phantom requirement (groups don't have expand state) | Summary + Architectural Responsibility Map | If the user expected the Resources tree to GAIN collapse capability as part of this phase, that's a separate phase. Flag for plan-discuss. Medium risk. |
| A6 | cmdk's filter performance at 500 items is fine without debouncing | Pitfall 5 | Benchmark in Plan 02 before declaring done. Low risk — debouncing is a one-line follow-up if needed. |
| A7 | `tailwind-merge` correctly overrides `top-[50%]` with `top-[80px]` via `cn()` | Pattern 3 / Pitfall 3 | Verified in pattern docs but not in this codebase yet. Plan 02 smoke test catches it. Low risk. |
| A8 | The amber chip color for off-layer hint is acceptable without per-layer tinting | Pattern 6 | Design contract (Section 3.8) reserves amber for Thermal; using amber for ALL off-layer hints conflates with Thermal-layer meaning. Recommendation in pattern is to use per-layer tint; assumption here is the planner picks one. Low risk. |

## Open Questions

1. **Matched-character highlighting in v1 — ship or skip?**
   - What we know: CONTEXT.md says "matched-char highlighting on" in the
     Claude's Discretion block. cmdk does NOT ship this out of the box.
   - What's unclear: whether the user expects this in v1 or is fine deferring
     to Phase 72 polish.
   - Recommendation: discuss-phase asks explicitly; default skip in v1 to
     keep this phase tight.

2. **Model Options handling — one row or per-field rows?**
   - What we know: CONTEXT.md `<domain>` says "Model Options child → opens the
     Model Options editor focused on that child." The panel has no per-field
     focus today.
   - What's unclear: do we ship "one Project Options row that just switches
     the tab" (research recommendation), or do we add field-anchor focus
     (each field gets an `id` + `scrollIntoView` on jump) as part of this
     phase?
   - Recommendation: discuss-phase asks. Default to the simpler "one row,
     switch tab" — per-field anchoring belongs with Phase 72 polish.

3. **50-result cap — drop or keep?**
   - What we know: CONTEXT.md `<decisions>` Claude's Discretion says ~50 to
     "avoid the palette becoming a giant scrollable wall."
   - What's unclear: whether internal scroll already solves the perceived
     problem.
   - Recommendation: drop the cap; rely on internal scroll. If UAT shows
     overwhelm, add back.

4. **Per-layer chip tint or single amber tint?**
   - What we know: the off-layer hint is amber in the Pattern 6 example.
     Per-layer tinting (Hydraulic-blue, Thermal-amber, Sources-violet,
     Reactor-rose, matching `LayersPanel.tsx:LAYER_COLORS`) is more
     consistent with Section 3.8's color-discipline rule.
   - What's unclear: whether the chip is supposed to read as "warning"
     (single amber) or as "this layer" (per-layer color).
   - Recommendation: per-layer tint. Section 3.8 says "restricted accent
     palette" — using each layer's accent color in its own chip is the more
     disciplined choice.

## Sources

### Primary (HIGH confidence)
- `gui/src/App.tsx:197–319` — global keydown handler block (existing pattern for Ctrl+P shortcut)
- `gui/src/store/useStore.ts:170–296` — AppState interface; confirms `nodes`, `selectedNodeId`, `selectedResourceId`, `selectedResourceKind`, `activeLayers`, `hideOffLayer`, `selectResource`, `clearSelection`, `setActiveLeftTab`, `setLayerVisible` exist
- `gui/src/store/useStore.ts:1040–1063` — Phase 68 layer mutations (toggleLayer, setLayerVisible, setAllLayersVisible, setHideOffLayer)
- `gui/src/store/useStore.ts:1815–1829` — selectResource + clearSelection mutations
- `gui/src/components/resources/ResourcesTreePanel.tsx` — confirms no expand/collapse state; ResourceGroupHeader is static label
- `gui/src/components/project/ModelOptionsPanel.tsx` — confirms flat-form panel with no per-field selection identity
- `gui/src/components/ui/dialog.tsx:62` — existing centering classes that the top-anchor variant overrides
- `gui/src/components/canvasMenus/FitViewButton.tsx` — existing useReactFlow hook usage pattern
- `gui/src/lib/layers.ts:67–119` — getComponentLayers + isNodeVisible (Phase 68); used for D-03 off-layer detection
- `gui/src/components/LayersPanel.tsx:39–44` — LAYER_COLORS constants for the per-layer chip tint recommendation
- `gui/src/components/StreamNode.tsx:419` — node label uses `text-sm` (14px) — foundation for ZOOM_MIN_LEGIBLE = 0.75 reasoning
- `gui/package.json` — confirms `radix-ui@^1.4.3`, `@xyflow/react@^12.10.2`, `lucide-react@^1.7.0`, `react@^19.1.0`, `vitest@^4.1.2` already present
- `.planning/notes/gui-redesign-design-decisions.md:581–613` — Section 3.7 canonical UX contract
- `.planning/notes/gui-redesign-design-decisions.md:615–700` — Section 3.8 interaction contract (Esc-cancels, visual restraint)
- `.planning/phases/69-command-palette-jump-only/69-CONTEXT.md` — locked decisions D-01..D-04
- `npm view cmdk` (live registry probe, 2026-05-18) — version 1.1.1, no postinstall, MIT, dist signed
- `gh api repos/dip/cmdk` (live, 2026-05-18) — 12.6K stars, MIT, archived=false
- `gh api repos/dip/cmdk/commits` (live, 2026-05-18) — clean commit history, paco is current maintainer
- `gh api repos/shadcn-ui/ui/contents/apps/v4/registry/new-york-v4/ui/command.tsx` (live, 2026-05-18) — canonical shadcn `command.tsx` template
- `slopcheck install -e npm cmdk` (run live, 2026-05-18) — verdict `[OK]`

### Secondary (MEDIUM confidence)
- cmdk source at `gh api repos/dip/cmdk/contents/cmdk/src/index.tsx` — confirms `RadixDialog`, `commandScore`, primitive exports

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack (cmdk + shadcn + radix Dialog): HIGH — cross-verified live npm/GitHub/shadcn
- Architecture (App.tsx shortcut integration, store mutations, ReactFlow setCenter): HIGH — all paths verified against current source
- Off-layer auto-enable (D-03): HIGH — Phase 68 mutations live in store; pattern is composition only
- Top-anchor Dialog override (D-02): MEDIUM — pattern documented but not yet exercised in this codebase; Pitfall 3 explicit
- ZOOM_MIN_LEGIBLE = 0.75: MEDIUM — first-principles reasoning from font-size; UAT-tunable
- ModelOptions children handling: LOW — open question A4 / Open Q 2; needs discuss-phase confirmation
- Match-character highlighting: LOW — open question A3 / Open Q 1; explicit defer recommendation

**Research date:** 2026-05-18
**Valid until:** 2026-06-18 (30 days — cmdk stable since 2025-03-14; no churn expected). Re-audit cmdk if v1.2+ ships within the window.

## RESEARCH COMPLETE
