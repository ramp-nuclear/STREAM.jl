---
status: diagnosed
trigger: "Canvas → Add Component nested submenus render offscreen/clipped — only a tiny edge visible"
created: 2026-05-15T00:00:00Z
updated: 2026-05-15T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — `PopoverMenuSubContent` is a plain `<div className="absolute left-full top-0 z-50 ...">` (context-menu.tsx:251-264) with no collision detection. Anchoring is correct (relative to the parent `PopoverMenuSub` row at line 197 — `className="relative"` is the offset parent), but the static `left-full` ALWAYS places the level-2 submenu to the right of the level-1 menu. When the top-level Popover anchor is in the right portion of the viewport, the level-2 submenu's `left-full` projection lands offscreen and only a sliver is visible. No Floating UI / no `flip` middleware / no side="left" fallback.
test: Read of context-menu.tsx, AddComponentSubmenu.tsx, CanvasContextMenu.tsx, CanvasPanel.tsx, popover.tsx complete.
expecting: (confirmed) PopoverMenuSubContent is option (b) — absolute-positioned div with hardcoded `left-full top-0` that doesn't react to viewport collisions.
next_action: Return ROOT CAUSE FOUND to caller.

## Symptoms

expected: Per-category submenus inside Canvas → Add Component render fully on screen, anchored next to their parent menu item (typical "side=right align=start" nested-menu placement).
actual: Top-level menu (Paste / Auto-Layout / Add Component) opens correctly at right-click position. Hovering Add Component opens a per-category submenu, but the per-component submenu (level 2) is clipped — only a tiny edge visible.
errors: none
reproduction: Right-click empty Canvas → hover "Add Component" → hover any category → category submenu barely visible.
started: Plan 65-05 deviation W10 — `PopoverMenuItem`/`PopoverMenuSub*` introduced to work around Radix `ContextMenuItem` requiring a `MenuContentContext` not present inside Popover.

## Eliminated

- hypothesis: Nested Radix Popover wrapping inherits root anchor at right-click coords
  evidence: context-menu.tsx:243-265 — PopoverMenuSubContent is a plain `<div>`, NOT a nested Popover. No inheritance issue exists.
  timestamp: 2026-05-15
- hypothesis: Z-index stacking
  evidence: PopoverMenuSubContent uses `z-50` and renders inside PopoverContent (also `z-50`); user reports a "tiny edge visible," consistent with viewport clipping, not z-stack occlusion.
  timestamp: 2026-05-15
- hypothesis: Parent PopoverContent `overflow-hidden` clips children
  evidence: popover.tsx:48 — PopoverContent classNames contain no `overflow-hidden`; clipping is by the viewport, not by the parent popover box.
  timestamp: 2026-05-15

## Evidence

- timestamp: 2026-05-15
  checked: gui/src/components/ui/context-menu.tsx (PopoverMenuSub* primitives)
  found: PopoverMenuSub (line 188-202) wraps children in `<div className="relative">`. PopoverMenuSubTrigger (209-241) is a plain div with `onMouseEnter/onMouseLeave/onClick` that toggle local React state. PopoverMenuSubContent (243-265) is `<div className="absolute left-full top-0 z-50 min-w-[8rem] ... rounded-md border bg-popover ...">` rendered conditionally on `open`. NO Floating UI, NO collision detection, NO flip middleware, NO side/align logic.
  implication: Level-2 submenu position is statically "right of the trigger row" via `left-full` Tailwind class — when the parent Add Component menu is anywhere near the right edge of the viewport, the level-2 panel spills offscreen.
- timestamp: 2026-05-15
  checked: gui/src/components/canvasMenus/AddComponentSubmenu.tsx
  found: Each category renders `<PopoverMenuSub><PopoverMenuSubTrigger>{category}</PopoverMenuSubTrigger><PopoverMenuSubContent>...</PopoverMenuSubContent></PopoverMenuSub>` (lines 45-61). Composition is correct; the problem is in the primitive itself.
  implication: Fix must change the primitive, not the consumer.
- timestamp: 2026-05-15
  checked: gui/src/components/canvasMenus/CanvasContextMenu.tsx
  found: One additional `PopoverMenuSub` wraps the entire Add Component subtree (line 38-43). The nesting depth is therefore 2: level-1 = Add Component, level-2 = per-category. Both levels use `left-full`, but the symptom is reported only at level-2 (level-1 itself opens fine because the user opens the parent Popover near the right-click point and Add Component is in the top-level PopoverContent — that content uses Radix Popover's own collision-aware positioning via `<PopoverContent align="start" side="bottom">`).
  implication: Only PopoverMenuSubContent needs collision-aware positioning; the top-level PopoverContent already has it.
- timestamp: 2026-05-15
  checked: gui/src/components/CanvasPanel.tsx (lines 340-373) and gui/src/components/ui/popover.tsx
  found: PopoverContent renders inside `<PopoverPrimitive.Portal>` (i.e., portalled to `<body>`). PopoverAnchor is `position: fixed` at (rcMenu.screenX, rcMenu.screenY). PopoverContent has no `overflow-hidden`. Therefore the level-2 submenu's clipping is by the **viewport**, not by the parent popover box.
  implication: Fix is to make PopoverMenuSubContent viewport-collision-aware (flip to side="left" when there's not enough room on the right).
- timestamp: 2026-05-15
  checked: 65-UAT.md test 13 + Gap
  found: User report: "shows a tiny edge of it but it doesn't show everything." Severity: major. Truth #: "Per-category submenus render fully on screen (not clipped or positioned offscreen)" — failed.
  implication: Visual symptom exactly matches a `left-full` element being pushed past the right viewport edge.

## Resolution

root_cause: |
  `PopoverMenuSubContent` in `gui/src/components/ui/context-menu.tsx` (lines 243-265, introduced by Plan 65-05 deviation W10) is a plain absolutely-positioned `<div>` with hardcoded Tailwind classes `absolute left-full top-0 z-50`. It has no viewport-collision detection — no Floating UI, no Radix `SubContent` (which it deliberately doesn't use to avoid the `MenuContentContext` requirement that broke `ContextMenuItem` inside Popover). When the parent Add Component menu sits anywhere in the right portion of the viewport, `left-full` pushes the level-2 per-category submenu past the right edge of the screen, so only a "tiny edge" remains visible. The level-1 submenu opens correctly because the top-level Popover (in CanvasPanel.tsx) uses Radix `PopoverContent` with `align="start" side="bottom"` — which DOES have built-in collision-aware positioning. The W10 workaround replaced that capability with a static `left-full` and never restored it.
fix: |
  Recommend (preferred): replace the hand-rolled `PopoverMenuSub*` primitives with `DropdownMenuSub` / `DropdownMenuSubTrigger` / `DropdownMenuSubContent` from a `dropdown-menu.tsx` shim (Radix DropdownMenu has built-in `MenuContentContext` AND lives happily inside a Popover when used as the children of `PopoverContent` because DropdownMenu owns its own root context). DropdownMenu.SubContent has Floating-UI-based viewport flipping out of the box.
  Alternative (lighter): keep `PopoverMenuSub*` but wire it through Floating UI's `useFloating({ placement: 'right-start', middleware: [flip(), shift({padding: 8})] })` so the level-2 submenu flips to `left-start` when right-side space is insufficient. Anchor reference = PopoverMenuSubTrigger's DOM node (`useRef` on the trigger, pass to `refs.setReference`); floating = PopoverMenuSubContent.
  Either path also benefits from rendering `PopoverMenuSubContent` into a portal so its overflow is not clipped by any future `overflow-hidden` on parent menu boxes.
verification: ""
files_changed: []
