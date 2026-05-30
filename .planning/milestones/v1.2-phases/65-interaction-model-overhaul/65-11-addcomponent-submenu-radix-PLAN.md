---
phase: 65-interaction-model-overhaul
plan: 11
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/components/ui/dropdown-menu.tsx
  - gui/src/components/ui/context-menu.tsx
  - gui/src/components/canvasMenus/CanvasContextMenu.tsx
  - gui/src/components/canvasMenus/AddComponentSubmenu.tsx
  - gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx
autonomous: true
requirements: []
gap_closure: true
tags: [context-menu, submenu, radix, dropdown-menu, floating-ui, gap-closure, phase-65]

must_haves:
  truths:
    - "Right-clicking near the right edge of the canvas → hover 'Add Component' → hover a category — the per-component submenu is rendered FULLY visible (no offscreen clipping)."
    - "When the right edge is too close, the submenu flips to the LEFT of the trigger (Floating UI `flip()` behavior) and remains fully visible."
    - "The hand-rolled `PopoverMenuSub*` primitives in context-menu.tsx are no longer the rendering primitives for the Add Component submenus."
    - "Keyboard navigation (Enter / ArrowRight opens the submenu, ArrowLeft / Esc closes it) is preserved or improved by the Radix replacement."
    - "Top-level canvas context menu items (Paste, Auto-Layout, Add Component) still render correctly under the existing Popover host."
  artifacts:
    - path: "gui/src/components/ui/dropdown-menu.tsx"
      provides: "Thin shadcn-style shim around @radix-ui/react-dropdown-menu exporting DropdownMenu, DropdownMenuTrigger, DropdownMenuPortal, DropdownMenuContent, DropdownMenuItem, DropdownMenuSub, DropdownMenuSubTrigger, DropdownMenuSubContent, DropdownMenuSeparator. Same styling tokens as PopoverMenu* primitives."
      contains: "DropdownMenuSubContent"
    - path: "gui/src/components/canvasMenus/CanvasContextMenu.tsx"
      provides: "Renders Add Component as a DropdownMenu.Sub (level-1) so its SubContent has Floating-UI viewport flipping. Level-1 sub trigger lives inside the existing PopoverContent; uses a controlled DropdownMenu with `open` defaulting to true on render."
    - path: "gui/src/components/canvasMenus/AddComponentSubmenu.tsx"
      provides: "Uses DropdownMenuSub / DropdownMenuSubTrigger / DropdownMenuSubContent for the per-category level-2 submenus."
  key_links:
    - from: "AddComponentSubmenu per-category submenu"
      to: "viewport-collision-aware placement"
      via: "DropdownMenuSubContent (Radix Floating UI flip + shift middleware)"
      pattern: "DropdownMenuSubContent"
    - from: "CanvasContextMenu Add Component entry"
      to: "level-2 category submenus"
      via: "DropdownMenuSub wrapper inside PopoverContent"
      pattern: "DropdownMenuSub"
---

<objective>
Close UAT Test 13 (major): the per-category submenus inside the canvas Add Component menu
render offscreen / clipped — only a tiny edge is visible.

Root cause (`.planning/debug/addcomponent-submenu-placement.md`): the W10 workaround
introduced in Plan 65-05 replaced Radix's nested-menu primitives with hand-rolled
`PopoverMenuSub* ` `&lt;div className="absolute left-full top-0 z-50 ..."&gt;` — no Floating UI,
no flip middleware, no side fallback. When the parent menu sits in the right portion of
the viewport, `left-full` projects the level-2 panel past the right edge.

Fix (preferred path from debug session): swap the hand-rolled `PopoverMenuSub*` for Radix
`DropdownMenuSub` / `DropdownMenuSubTrigger` / `DropdownMenuSubContent`. The Radix nested-menu
primitives ship with Floating UI's `flip()` + `shift()` middleware out of the box, plus
keyboard navigation and focus management. `@radix-ui/react-dropdown-menu` is already in
`gui/node_modules/@radix-ui/` — no new dependency.

Approach:
1. Create a new shadcn-style shim `gui/src/components/ui/dropdown-menu.tsx` exporting the Radix
   primitives with project styling tokens.
2. In `CanvasContextMenu.tsx`, wrap the "Add Component" entry with `DropdownMenu` (controlled,
   `open=true` via render-on-mount) + `DropdownMenuTrigger` (the row) + `DropdownMenuContent`
   that hosts the per-category subs. Note: keep Paste / Auto-Layout / Separator as plain
   PopoverMenuItem because they are leaves of the Popover host, not part of the dropdown.

   Actually, simpler approach: use Radix DropdownMenu purely for the LEVEL-1 "Add Component"
   entry — that is, the "Add Component" row remains a PopoverMenuItem-style trigger, and on
   hover/click it opens a `DropdownMenu` whose SubContent contains the category submenus
   (which themselves are DropdownMenu.Sub for level-2). This nests Radix DropdownMenu inside
   the existing Popover host (Popover host is OK with DropdownMenu children — DropdownMenu
   owns its own root context).
3. Rewrite `AddComponentSubmenu.tsx` to emit `DropdownMenuSub` / `DropdownMenuSubTrigger` /
   `DropdownMenuSubContent` per category.
4. Remove the now-unused `PopoverMenuSub`, `PopoverMenuSubTrigger`, `PopoverMenuSubContext`,
   and `PopoverMenuSubContent` exports from `context-menu.tsx`. Keep `PopoverMenuItem` and
   `PopoverMenuSeparator` — they're still used by NodeContextMenu, EdgeContextMenu, and the
   Paste / Auto-Layout rows of CanvasContextMenu.

Purpose: restore viewport-aware menu placement that Plan 03 lost when it ripped out
Radix ContextMenu for the W10 workaround.

Output: 4 files modified (or 5 with the new dropdown-menu.tsx shim), 1 vitest covering
the wiring, no offscreen clipping at the right edge of the viewport.

Source: `.planning/debug/addcomponent-submenu-placement.md` (root cause confirmed;
preferred path = Radix DropdownMenu.Sub, alternative = @floating-ui patch — preferred is
chosen because dependency is already installed).
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/65-interaction-model-overhaul/65-05-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/addcomponent-submenu-placement.md
@gui/src/components/ui/context-menu.tsx
@gui/src/components/canvasMenus/CanvasContextMenu.tsx
@gui/src/components/canvasMenus/AddComponentSubmenu.tsx
@gui/src/components/CanvasPanel.tsx

<interfaces>
<!-- @radix-ui/react-dropdown-menu IS installed (verified via
     `ls gui/node_modules/@radix-ui/react-dropdown-menu`).
     If at execution time it's NOT installed, do not run `npm install` — the package
     is a peer of the existing shadcn primitives already in package.json. If absent,
     halt and report — that would be an environmental anomaly worth investigating. -->

<!-- Radix DropdownMenu API contract (from @radix-ui/react-dropdown-menu) -->
The relevant primitives for nested menus:

  &lt;DropdownMenu open?={boolean} onOpenChange?={(v:boolean)=&gt;void} modal?={boolean}&gt;
    &lt;DropdownMenuTrigger asChild&gt;&lt;Row /&gt;&lt;/DropdownMenuTrigger&gt;
    &lt;DropdownMenuPortal&gt;
      &lt;DropdownMenuContent side="right" align="start" sideOffset={4}&gt;
        ...items...
        &lt;DropdownMenuSub&gt;
          &lt;DropdownMenuSubTrigger&gt;Category&lt;/DropdownMenuSubTrigger&gt;
          &lt;DropdownMenuPortal&gt;
            &lt;DropdownMenuSubContent&gt;
              &lt;DropdownMenuItem onSelect={(e)=&gt;{...}}&gt;Component&lt;/DropdownMenuItem&gt;
            &lt;/DropdownMenuSubContent&gt;
          &lt;/DropdownMenuPortal&gt;
        &lt;/DropdownMenuSub&gt;
      &lt;/DropdownMenuContent&gt;
    &lt;/DropdownMenuPortal&gt;
  &lt;/DropdownMenu&gt;

DropdownMenuSubContent has Floating-UI viewport-flip built in (collisionPadding default
8 — adequate for our case). No middleware config needed.

<!-- Existing context-menu.tsx symbols that REMAIN after this plan -->
Keep (still used by EdgeContextMenu, NodeContextMenu, and the non-submenu rows of
CanvasContextMenu):
- `PopoverMenuItem`       — leaf row
- `PopoverMenuSeparator`  — separator

Remove (replaced by Radix DropdownMenu primitives):
- `PopoverMenuSub`
- `PopoverMenuSubTrigger`
- `PopoverMenuSubContent`
- `PopoverMenuSubContext`

If something else outside the canvas menus imports `PopoverMenuSub*`, grep finds it:
  grep -rn "PopoverMenuSub" gui/src
Expected hits after this plan: ONLY in dropdown-menu.tsx file headers or
removed-symbols comments, and zero consumers.

<!-- Existing styling tokens to reuse (from context-menu.tsx PopoverMenuItem) -->
PopoverMenuItem className:
  "relative flex cursor-default select-none items-center gap-2
   rounded-sm px-2 py-1.5 text-sm outline-hidden
   focus:bg-accent focus:text-accent-foreground
   data-[disabled]:pointer-events-none data-[disabled]:opacity-50
   hover:bg-accent hover:text-accent-foreground"

Mirror the same Tailwind classes on DropdownMenuItem / DropdownMenuSubTrigger /
DropdownMenuSubContent / DropdownMenuContent in the new shim for visual parity.
The existing border / shadow / bg-popover styling on PopoverContent should also
match DropdownMenuContent + DropdownMenuSubContent classes for menu boxes.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create dropdown-menu.tsx shim + rewire AddComponent to Radix Sub primitives</name>
  <files>
    gui/src/components/ui/dropdown-menu.tsx
    gui/src/components/canvasMenus/CanvasContextMenu.tsx
    gui/src/components/canvasMenus/AddComponentSubmenu.tsx
    gui/src/components/ui/context-menu.tsx
  </files>
  <action>
    **Pre-flight check.** Verify `@radix-ui/react-dropdown-menu` is installed:
      ls gui/node_modules/@radix-ui/react-dropdown-menu/dist/index.d.ts
    If the file does NOT exist, halt the task and report — the diagnosis says it should be
    there; missing would be an environmental anomaly. Do NOT `npm install` to fix this.

    **Step 1.** Create `gui/src/components/ui/dropdown-menu.tsx` as a shadcn-style shim.
    Pattern this on the existing `gui/src/components/ui/popover.tsx` for structure +
    on context-menu.tsx for the menu-item / menu-content className tokens. Export:

      DropdownMenu                 (Radix Root)
      DropdownMenuTrigger          (Radix Trigger)
      DropdownMenuPortal           (Radix Portal)
      DropdownMenuContent          (Radix Content, styled like PopoverContent box)
      DropdownMenuItem             (Radix Item, styled like PopoverMenuItem)
      DropdownMenuSub              (Radix Sub)
      DropdownMenuSubTrigger       (Radix SubTrigger, styled like PopoverMenuSubTrigger but
                                    NO hand-rolled positioning — Radix handles it)
      DropdownMenuSubContent       (Radix SubContent, styled like PopoverContent box)
      DropdownMenuSeparator        (Radix Separator, styled like PopoverMenuSeparator)

    Use `React.forwardRef` for Content/Item/SubTrigger/SubContent to forward refs.
    Default `sideOffset` on DropdownMenuContent and DropdownMenuSubContent to a sensible
    value (4 px). On DropdownMenuSubContent, no explicit side/align needed — Floating UI
    defaults + collision detection handle placement.

    Styling reuse (className strings) — copy verbatim from context-menu.tsx:
      - DropdownMenuItem className mirrors PopoverMenuItem (existing string in context-menu.tsx
        around line 273-285). Add `&lt;ChevronRightIcon className="ml-auto size-4" /&gt;` ONLY in
        DropdownMenuSubTrigger (mirrors existing PopoverMenuSubTrigger).
      - DropdownMenuContent + DropdownMenuSubContent className matches PopoverContent
        (white/dark bg, rounded-md border, shadow-lg, p-1, min-w-[8rem], text-popover-foreground).
        Look at `gui/src/components/ui/popover.tsx` PopoverContent for the canonical class list.
      - DropdownMenuSeparator className: `"-mx-1 my-1 h-px bg-border"` (matches PopoverMenuSeparator).

    Add a one-line file header comment:
      `// dropdown-menu.tsx — shadcn-style shim around @radix-ui/react-dropdown-menu (Phase 65 Plan 11). Used for nested submenus with viewport-collision-aware placement (replaces hand-rolled PopoverMenuSub*).`

    **Step 2.** Rewrite `gui/src/components/canvasMenus/AddComponentSubmenu.tsx`. Replace
    `PopoverMenuSub / PopoverMenuSubTrigger / PopoverMenuSubContent / PopoverMenuItem` with
    `DropdownMenuSub / DropdownMenuSubTrigger / DropdownMenuSubContent / DropdownMenuItem`.
    Wrap each per-category `DropdownMenuSubContent` body in `DropdownMenuPortal` so it
    portals to body and is not subject to Popover host overflow.

    Update the file-level comment to:
      `// AddComponentSubmenu.tsx — Phase 65 Plan 11: uses Radix DropdownMenu.Sub for viewport-collision-aware placement (was PopoverMenuSub* with hardcoded left-full positioning).`

    Keep `getAllComponents` + `useMemo` grouping logic unchanged. Inside `DropdownMenuItem`,
    `onSelect={(e) =&gt; { e.preventDefault?.(); useStore.getState().addNode(comp.id, flowPosition); onClose(); }}`.
    (`e.preventDefault?.()` is harmless if Radix's onSelect event doesn't supply one; defensive.)

    **Step 3.** Update `gui/src/components/canvasMenus/CanvasContextMenu.tsx`. Replace the
    `&lt;PopoverMenuSub&gt;` wrapper around the Add Component entry with a Radix
    `&lt;DropdownMenu open={true}&gt;` whose root contains exactly:

      &lt;DropdownMenuTrigger asChild&gt;
        &lt;div role="menuitem"&gt;Add Component
          &lt;ChevronRightIcon className="ml-auto size-4" /&gt;
        &lt;/div&gt;
      &lt;/DropdownMenuTrigger&gt;
      &lt;DropdownMenuPortal&gt;
        &lt;DropdownMenuContent side="right" align="start" sideOffset={4}&gt;
          &lt;AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} /&gt;
        &lt;/DropdownMenuContent&gt;
      &lt;/DropdownMenuPortal&gt;

    Issue: a DropdownMenu with `open={true}` (uncontrolled-but-forced) opens on mount.
    But the canvas context-menu lifecycle (Popover) already toggles render of the whole
    CanvasContextMenu — when Popover closes, this whole tree unmounts. So `open={true}`
    on mount is correct. Alternative: omit `open` and use `defaultOpen={true}` + an
    `onOpenChange` that calls `onClose` when the dropdown is closed (so closing the
    inner dropdown propagates closure to the outer Popover host). PREFERRED: use
    `defaultOpen` + `onOpenChange={(open) =&gt; { if (!open) onClose(); }}`.

    Keep the Paste / Auto-Layout / Separator rows AS-IS (`PopoverMenuItem` /
    `PopoverMenuSeparator`). Only the "Add Component" row gets replaced.

    Update imports at top of CanvasContextMenu.tsx:
      - Remove `PopoverMenuSub`, `PopoverMenuSubContent`, `PopoverMenuSubTrigger`.
      - Add `DropdownMenu`, `DropdownMenuTrigger`, `DropdownMenuPortal`,
        `DropdownMenuContent` from `@/components/ui/dropdown-menu`.
      - Keep `PopoverMenuItem`, `PopoverMenuSeparator`.
      - Add `ChevronRightIcon` from `lucide-react` for the trigger row.

    **Step 4.** Remove dead code from `gui/src/components/ui/context-menu.tsx`. Delete:
      - `PopoverMenuSub` (export function around line 188-202)
      - `PopoverMenuSubContext` (line 204-207)
      - `PopoverMenuSubTrigger` (line 209-241)
      - `PopoverMenuSubContent` (line 243-265)

    Leave `PopoverMenuItem`, `PopoverMenuSeparator`, and any other ContextMenu*-prefixed
    exports untouched.

    Confirm no other consumer imports the removed symbols:
      grep -rn "PopoverMenuSub" gui/src --include="*.tsx" --include="*.ts"
    Expected after the deletions: zero hits, OR only hits inside file-header comments
    documenting "was PopoverMenuSub*, replaced by DropdownMenu.Sub". If any consumer still
    imports them, halt and report.

    Verify build:
      cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -E "(context-menu|dropdown-menu|CanvasContextMenu|AddComponentSubmenu)" || echo "clean"
    The pre-existing 11 tsc errors (Phase 71 owns them per STATE.md) MUST NOT GROW. To verify:
      cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c "error TS"
    Capture the count before editing (write to /tmp/tsc-before.txt) and re-check after.
    The post-edit count must be `&lt;=` the pre-edit count.

    Commit (single commit for the 4 files — they're a cohesive primitive swap):
    ```
    git add gui/src/components/ui/dropdown-menu.tsx \
            gui/src/components/canvasMenus/AddComponentSubmenu.tsx \
            gui/src/components/canvasMenus/CanvasContextMenu.tsx \
            gui/src/components/ui/context-menu.tsx
    git commit -m "fix(65-11): swap Add Component submenus to Radix DropdownMenu.Sub

    Replace hand-rolled PopoverMenuSub* (W10 workaround from Plan 65-05)
    with Radix DropdownMenu.Sub primitives. DropdownMenuSubContent ships
    with Floating UI's flip() + shift() so submenus near the right edge
    of the viewport flip left instead of clipping offscreen. New
    dropdown-menu.tsx shim mirrors existing shadcn primitive style.

    Closes UAT Test 13 (.planning/debug/addcomponent-submenu-placement.md).

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # New shim exists
      test -f gui/src/components/ui/dropdown-menu.tsx
      # Old PopoverMenuSub* primitives gone from context-menu.tsx
      test "$(grep -v '^//' gui/src/components/ui/context-menu.tsx | grep -c 'PopoverMenuSubContent\|PopoverMenuSubTrigger\|PopoverMenuSubContext\|export function PopoverMenuSub')" = 0
      # No consumer of removed symbols
      test "$(grep -rn 'PopoverMenuSub' gui/src --include='*.tsx' --include='*.ts' | grep -v '^[^:]*:[^:]*://' | wc -l)" = 0
      # AddComponentSubmenu uses Radix DropdownMenu.Sub
      grep -q "DropdownMenuSub" gui/src/components/canvasMenus/AddComponentSubmenu.tsx
      grep -q "DropdownMenuSubContent" gui/src/components/canvasMenus/AddComponentSubmenu.tsx
      # CanvasContextMenu uses Radix DropdownMenu
      grep -q "DropdownMenu" gui/src/components/canvasMenus/CanvasContextMenu.tsx
      # tsc error count not increased (capture, compare)
      cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c "error TS" &gt; /tmp/tsc-after-65-11.txt
      cat /tmp/tsc-after-65-11.txt
      # Vitest does not regress across the canvas menus
      cd gui &amp;&amp; npx vitest run src/components/canvasMenus 2>&amp;1 | tail -20
    </automated>
  </verify>
  <done>
    The four files committed. dropdown-menu.tsx shim exports the documented Radix primitives.
    PopoverMenuSub*/PopoverMenuSubContext are gone. AddComponentSubmenu emits DropdownMenu.Sub.
    No new tsc errors. Canvas menu vitest suite (if any) still passes.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Smoke test — AddComponentSubmenu renders Radix DropdownMenuSub for each category</name>
  <files>
    gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx
  </files>
  <behavior>
    - Test: render `AddComponentSubmenu flowPosition={{x:0,y:0}} onClose={vi.fn()}` inside a
      Radix DropdownMenu host (to satisfy SubTrigger's requirement to be inside a Menu).
      Assert: for each category returned by `getAllComponents()` grouped by category, a
      `&lt;DropdownMenuSubTrigger&gt;` is rendered with text content matching the category name.
      The test does NOT need to verify viewport-flip behavior (that is Radix's responsibility
      and is covered by the manual UAT in Task 3 — and by the diagnose session's mechanical
      analysis).
    - Test: clicking a category SubTrigger opens its SubContent (assert
      `screen.findByRole("menuitem", { name: /^Pump$/ })` or similar resolves) and that
      clicking the leaf item invokes `useStore.getState().addNode` once with the expected
      component id + flowPosition, and invokes onClose.
  </behavior>
  <action>
    **TDD RED → GREEN.** Because Task 1 already swapped the primitives, the RED here is
    only a few seconds — the test fails because the test file doesn't exist yet; once it
    exists and asserts on `DropdownMenuSubTrigger`, it passes against the new
    AddComponentSubmenu code. Still write RED first (TDD discipline), commit, then GREEN
    is a no-op verify.

    Pattern: see `gui/src/components/canvasMenus/__tests__/NodeContextMenu.test.tsx`
    (if it exists; if not, see any sibling test in `gui/src/components/__tests__/`) for the
    testing-library setup, store seeding, and Radix-component testing idioms. Radix
    portals to `document.body` by default — testing-library finds them as long as you
    use `screen.getBy*` (not `getByTestId` inside a specific container).

    Test setup:
      - Mock `useStore.getState().addNode` via `vi.spyOn(useStore.getState(), 'addNode')`
        or by replacing the action with `useStore.setState({ addNode: vi.fn() })` before render.
      - Wrap the component under test in a parent `&lt;DropdownMenu open={true}&gt;
        &lt;DropdownMenuContent&gt;...&lt;/DropdownMenuContent&gt;&lt;/DropdownMenu&gt;` so that the
        DropdownMenuSub primitives have the required Radix Root context. Without this wrapper,
        Radix throws "DropdownMenuSub must be used within a DropdownMenu".
      - Use `userEvent.hover` (or `fireEvent.pointerEnter`) on the SubTrigger to open the
        SubContent. Radix DropdownMenu uses hover/keyboard, not click, to open subs by default.

    Note: this test is mostly defensive — if Radix changes its API or if a future refactor
    accidentally drops the SubTrigger, it catches the regression. Functional placement
    (viewport flip) is verified by manual UAT in the implicit re-test of Test 13 after this
    plan + Plan 09 ship.

    Commit:
    ```
    git add gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx
    git commit -m "test(65-11): AddComponentSubmenu renders Radix DropdownMenuSub per category

    Regression guard for the Plan 11 primitive swap.

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      test -f gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx
      cd gui &amp;&amp; npx vitest run src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx
    </automated>
  </verify>
  <done>
    Test file exists; passes against Task 1's implementation; commit recorded.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

(none — pure UI primitive swap; no IPC, no fs)

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-11a | Tampering | dropdown-menu.tsx shim | accept | Radix DropdownMenu is already a transitive dep of multiple shadcn primitives in the project; the shim adds no new external code. |
| T-65-11b | Denial of Service | nested portal rendering | accept | Each DropdownMenuSub portals to body. Worst case: a malformed registry with hundreds of categories triggers many portals. getAllComponents currently returns 16 components (~3-4 categories) — bounded. |
</threat_model>

<verification>
- `test -f gui/src/components/ui/dropdown-menu.tsx`
- `grep -q DropdownMenuSubContent gui/src/components/ui/dropdown-menu.tsx`
- `grep -rn PopoverMenuSub gui/src --include='*.tsx' --include='*.ts'` returns no consumer hits.
- `cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c "error TS"` ≤ pre-edit baseline (Phase 71 owns 11 pre-existing).
- `cd gui &amp;&amp; npx vitest run src/components/canvasMenus` — all pass.
- Manual (recommended but not gating): right-click near the right edge of the canvas in
  Tauri dev → hover Add Component → hover a category → submenu visible (flipped left).
</verification>

<success_criteria>
- New shim `gui/src/components/ui/dropdown-menu.tsx` exports the 9 documented primitives.
- `gui/src/components/ui/context-menu.tsx` no longer exports `PopoverMenuSub`, `PopoverMenuSubTrigger`, `PopoverMenuSubContent`, or `PopoverMenuSubContext`.
- `gui/src/components/canvasMenus/AddComponentSubmenu.tsx` emits Radix `DropdownMenuSub` per category.
- `gui/src/components/canvasMenus/CanvasContextMenu.tsx` wraps Add Component in a `DropdownMenu` rooted with `defaultOpen={true}` and `onOpenChange={(open) =&gt; { if (!open) onClose(); }}`.
- New regression test passes; no sibling test regresses.
- No new tsc errors; build (`npm run build` if invoked locally) is no worse than baseline.
- Two commits recorded.
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-11-SUMMARY.md` when done.
</output>
