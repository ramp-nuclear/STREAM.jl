---
phase: 66-code-preview-rework
plan: 4
type: execute
wave: 3
depends_on: [66-03]
files_modified:
  - gui/src/components/CodePreview.tsx
  - gui/src/components/BottomPanel.tsx
autonomous: true
requirements: []

must_haves:
  truths:
    - "`CodePreview.tsx` renders sections section-by-section: each populated `CodeSection` shows a styled header (`<h4>` or equivalent) followed by its `subBlocks`."
    - "Each `CodeSubBlock` renders inside a wrapper with `data-sub-block` attribute and a stable `id` (e.g., `code-sb-{section}-{index}`) so refs can be looked up for scroll/flash."
    - "Hovering a sub-block writes its `sourceIds` into `useStore.hoveredSourceIds`; leaving clears."
    - "Clicking a sub-block calls `togglePinnedForSubBlock(sourceIds)`."
    - "Clicking empty space INSIDE the code panel (the ScrollArea viewport, not on a sub-block) calls `clearPinnedSourceIds()`."
    - "On every render, if `useStore.pendingShowCodeFor` is non-null, the panel finds matching sub-blocks (by `sourceIds` intersection), scrolls the first match into view via `el.scrollIntoView({behavior:'smooth', block:'center'})`, applies a 1.5-second flash class/`data-flash` to that sub-block, then calls `consumePendingShowCodeFor()` to clear the pending state."
    - "`BottomPanel.tsx`'s `<TabsList>` strip has a right-side button group containing Copy + Export buttons; both `disabled={nodes.length === 0}`."
    - "Copy button: copies `serializeSections(sections)` to clipboard; flips to `Check`+'Copied' label for 1.5s after success."
    - "Export button: calls `exportCode({ sections, nodes, ... })` (the same util Toolbar.tsx uses)."
    - "Native browser text-selection works across sub-block boundaries — no `select-none`, no `preventDefault` on mousedown."
    - "Rendering is plain `<pre><code>`-style text; no Monaco, no Prism, no highlight.js installed."
  artifacts:
    - path: "gui/src/components/CodePreview.tsx"
      provides: "section-by-section renderer with hover/click handlers and stream:show-code-for consumer"
    - path: "gui/src/components/BottomPanel.tsx"
      provides: "right-side Copy + Export buttons in TabsList; nodes-length-disabled gate"
  key_links:
    - from: "CodePreview.tsx"
      to: "useStore.setHoveredSourceIds, togglePinnedForSubBlock, clearPinnedSourceIds, consumePendingShowCodeFor"
      via: "store action calls in event handlers + useEffect"
      pattern: "setHoveredSourceIds|togglePinnedForSubBlock|consumePendingShowCodeFor"
    - from: "BottomPanel.tsx Export"
      to: "exportCode"
      via: "named import from gui/src/lib/exportCode"
      pattern: "import.*exportCode.*from"
    - from: "BottomPanel.tsx Copy"
      to: "navigator.clipboard.writeText"
      via: "async handler"
      pattern: "navigator\\.clipboard\\.writeText"
---

<objective>
Rewrite `gui/src/components/CodePreview.tsx` as a section-by-section renderer over `CodeSection[]` with sub-block-level hover / click / pin / scroll / flash. Add Copy + Export buttons to `BottomPanel.tsx`'s `<TabsList>` strip (right side), calling the existing `exportCode.ts` util from Plan 03 and `navigator.clipboard.writeText` with `serializeSections(...)`.

Purpose: deliver the user-visible Phase 66 surface. After this plan, the canvas-to-code and code-to-canvas traceability is functional end-to-end (modulo the canvas-side hover-ring CSS, which Plan 05 wires).
Output: Plan 01's three CodePreview RED tests (component, showCodeFor, textSelection) flip GREEN; manual smoke (right-click → "Show generated Julia code") works end-to-end to the point of "panel opens, scrolls, flashes" — the canvas hover-ring lands in Plan 05.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.planning/phases/66-code-preview-rework/66-CONTEXT.md
@.planning/phases/66-code-preview-rework/66-RESEARCH.md
@.planning/phases/66-code-preview-rework/66-03-SUMMARY.md
@gui/src/components/CodePreview.tsx
@gui/src/components/BottomPanel.tsx
@gui/src/components/Toolbar.tsx
@gui/src/components/ui/scroll-area.tsx
@gui/src/components/ui/button.tsx
@gui/src/components/ui/tabs.tsx
@gui/src/components/resources/ResourceRow.tsx
</context>

<interfaces>
<!-- The contracts this plan consumes (already in tree from Plans 02 and 03). -->

From `gui/src/lib/codeGenerator.ts`:
```typescript
export interface CodeSection { name: CodeSectionName; subBlocks: CodeSubBlock[]; }
export interface CodeSubBlock { lines: string[]; sourceIds: string[]; kind?: CodeSubBlockKind; }
export function generateCode(...): CodeSection[];
export function serializeSections(sections: CodeSection[]): string;
```

From `gui/src/store/useStore.ts`:
```typescript
hoveredSourceIds: Set<string>;
pinnedSourceIds: Set<string>;
pendingShowCodeFor: string[] | null;
setHoveredSourceIds(ids: string[]): void;
clearHoveredSourceIds(): void;
togglePinnedForSubBlock(subBlockSourceIds: string[]): void;
clearPinnedSourceIds(): void;
consumePendingShowCodeFor(): string[] | null;
```

From `gui/src/lib/exportCode.ts`:
```typescript
export async function exportCode(opts: { sections: CodeSection[]; nodes: Node[]; /* ... */ }): Promise<boolean>;
```

Sub-block DOM-id convention (Research §Sub-block dom-id stable convention): `code-sb-{section_name_lowercase}-{index_within_section}`. Used for refs and the `data-sub-block` selector that Plan 01 tests query.
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Rewrite CodePreview.tsx as a section-by-section renderer</name>
  <files>gui/src/components/CodePreview.tsx</files>
  <read_first>
    - gui/src/components/CodePreview.tsx (current 34-line implementation — what it reads from store, how it mounts)
    - gui/src/components/ui/scroll-area.tsx (the ScrollArea component — its viewport DOM structure matters for scrollIntoView walking)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 3: Smooth scroll-into-view + 1.5s flash", §"Pattern 7: native text-selection preservation", §"Pattern 9: hover-ring CSS class strategy" (only the StreamNode part is for Plan 05; the dom-id convention here is shared), §"Code Examples: CodePreview.tsx rewrite skeleton", §"Pitfall 4: scrollIntoView smooth behavior absent in jsdom", §"Pitfall 5: triple-click selecting a code line toggles pin state"
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-01..D-04 (sub-block shape), D-05..D-11 (hover/pin UX), D-13 (plain pre/code), D-14 (text-selection)
    - gui/src/components/__tests__/CodePreview.test.tsx, CodePreview.showCodeFor.test.tsx, CodePreview.textSelection.test.tsx (Plan 01 RED tests — read these for the exact DOM contract: `[data-sub-block]`, scrollIntoView args, flash mechanism)
  </read_first>
  <behavior>
    Render structure:
    - `useMemo` recomputes `const sections: CodeSection[] = useMemo(() => generateCode(...), [deps])` (drop the Plan 02 TEMP `serializeSections` wrap — we render the structured shape now).
    - For each `section` where `subBlocks.length > 0`: render a section group with:
        - A header (`<h4>` or `<div role="heading">` — planner picks; must be visually distinct so the user knows it's a section header).
        - One child element per sub-block. Each child has: `id={`code-sb-${section.name.toLowerCase()}-${i}`}`, `data-sub-block` attribute, `ref` registered into a Map (for scroll-into-view lookup).
        - The sub-block content is `subBlock.lines.join('\n')` rendered inside a `<pre>` (or a `<div>` with `whitespace-pre` — planner picks; native text-selection must work across sub-blocks per D-14 so `<pre>`-wrapping-each-sub-block is safer).
    - Between sub-blocks within a section: a spacer (CSS margin) producing exactly one blank-line worth of visual space — matches D-12's "one blank line between sub-blocks" rule visually.

    Event handlers:
    - `onMouseEnter` on each sub-block: `setHoveredSourceIds(subBlock.sourceIds)`.
    - `onMouseLeave` on each sub-block: `clearHoveredSourceIds()`. (No need to track which sub-block left — last-write-wins is correct.)
    - `onClick` on each sub-block: `togglePinnedForSubBlock(subBlock.sourceIds)`. Use plain `onClick` (NOT `onMouseDown` — Research Pattern 7).
    - `onClick` on the ScrollArea viewport itself (NOT on sub-blocks — use `e.target === e.currentTarget` check, or attach to a wrapper that doesn't include sub-blocks): if click landed on empty space, `clearPinnedSourceIds()`.

    `stream:show-code-for` consumer (PIN behavior — LOCKED, no deliberation):
    - `useEffect` with `pendingShowCodeFor` in deps.
    - If `pendingShowCodeFor` is non-null and non-empty, on the next render the consumer effect performs the following ordered steps. The listener (Plan 03's `useShowCodeFor` hook) has already written `pendingShowCodeFor`; this effect is the consumer.
      1. **Find the target sub-block.** Iterate `sections` in order; within each section iterate `subBlocks` in order; return the FIRST sub-block whose `sourceIds` includes any id from `pendingShowCodeFor` (handles both the single-`nodeId` and multi-`nodeIds` payload shapes from D-08). If no match, skip to step 5.
      2. **Pin (additively) the matched sub-block's source IDs.** Call `useStore.getState().togglePinnedForSubBlock(subBlock.sourceIds)` to add the sub-block's source IDs to `pinnedSourceIds` (additive per D-09/D-10; if any id is already pinned, D-10's overlap-removes-all semantics fire — that is the documented store contract and is acceptable here). **Do NOT call `setHoveredSourceIds` on this path.** Hover state is mouse-driven and releases on cursor-out, defeating the purpose of "jump to code" (the user moves the cursor immediately after the jump and would lose the highlight). D-09 specifies the highlight is sticky; D-09 plus Plan 05 Task 3's UAT step 12 ("the node on canvas gets the pinned ring") together rule out hover-on-jump.
      3. **Scroll into view.** Call `targetEl.scrollIntoView({ behavior: 'smooth', block: 'center' })` on the matched sub-block's DOM ref.
      4. **Apply the 1.5s flash.** Set local component state `flashedId = matchId` (the `code-sb-{section}-{index}` id), which drives a `data-flash="true"` attribute or a CSS class on the sub-block wrapper. A separate `useEffect` watching `flashedId` clears it after 1500ms via `setTimeout` with cleanup-aware `clearTimeout`.
      5. **Consume the pending state.** Call `useStore.getState().consumePendingShowCodeFor()` to atomically read-and-clear `pendingShowCodeFor` so the effect does not re-fire on the next render. Run this last so that an early return at step 1 (no match) still clears the state.
    - Plan 03's `interfaces` block already exposes `togglePinnedForSubBlock(subBlockSourceIds: string[]): void` (see Plan 03 line ~85), so no additional helper is needed. The action name is verbatim `togglePinnedForSubBlock`.
    - Canvas hover ring on the matched node: comes from `pinnedSourceIds` (sticky), wired in Plan 05's StreamNode subscription. Plan 04 does NOT touch StreamNode.

    Triple-click handling (Pitfall 5):
    - Triple-click fires three `click` events in rapid succession on the same element. Each calls `togglePinnedForSubBlock`. Toggle-toggle-toggle on the same sub-block yields: ON → OFF → ON. Net: pin ends up ON. Acceptable (user wanted to text-select a line; pin state ends ON, which is a minor side effect they can clear with Esc or another click). Document this in a code comment per CONTEXT D-14 footnote.

    Re-render scoping:
    - Subscribe to `pendingShowCodeFor` with a primitive-stable selector (it's an array reference; use a length+first-id derived key, OR rely on Zustand's shallow equality at array-replacement boundaries — `setPendingShowCodeFor` creates a fresh array, so reference inequality is sufficient).
  </behavior>
  <action>
    Replace the entire contents of `gui/src/components/CodePreview.tsx`. Skeleton structure (Research's §"CodePreview.tsx rewrite skeleton" is the source; planner adapts):

    1. Imports: React (`useMemo`, `useEffect`, `useRef`, `useState`), `useStore`, `getComponent` from `../registry`, `generateCode` (and `CodeSection`, `CodeSubBlock` types) from `../lib/codeGenerator`, `ScrollArea` from `./ui/scroll-area`.
    2. Store reads: `nodes`, `edges`, `anchors`, `resources`, `bcMode`, `bcSymmetric`, `pendingShowCodeFor`, plus the action getters via `useStore.getState()` inside handlers (matches existing pattern; avoids unnecessary re-renders).
    3. `const sections = useMemo(() => generateCode(...), [deps])`.
    4. Refs map: `const subBlockRefs = useRef<Map<string, HTMLElement>>(new Map())`.
    5. Flash state: `const [flashedId, setFlashedId] = useState<string | null>(null)`.
    6. `useEffect` watching `pendingShowCodeFor`: implements the lookup, scroll, flash, pin, and consume.
    7. Render: ScrollArea > section divs > sub-block elements with handlers, refs, `data-sub-block`, `data-flash={flashedId === id}` attribute.
    8. Empty-space click handler on ScrollArea viewport (use `e.target === e.currentTarget` predicate, OR check that the click did not bubble through a sub-block; planner picks).

    DO NOT add `select-none` anywhere. DO NOT call `preventDefault()` on mousedown.
    DO NOT install Monaco / Prism / highlight.js / shiki.
    Use `<pre>` inside each sub-block wrapper to preserve whitespace AND enable text-selection across sub-blocks (per Research Pattern 7).

    Headers: render section headers as `<h4 className="...">{section.name}</h4>` (or similar). Visual styling can be minimal — Phase 72 tunes. The literal text shown is the section name (`Imports`, `Components`, etc.), NOT the `# === Imports ===` Julia-comment form (that form is only in the COPIED text via `serializeSections`).

    `flashedId` cleanup: `useEffect(() => { if (!flashedId) return; const t = setTimeout(() => setFlashedId(null), 1500); return () => clearTimeout(t); }, [flashedId])`.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/components/__tests__/CodePreview.test.tsx src/components/__tests__/CodePreview.showCodeFor.test.tsx src/components/__tests__/CodePreview.textSelection.test.tsx 2>&1 | tail -30</automated>
  </verify>
  <acceptance_criteria>
    - All three Plan 01 CodePreview tests pass.
    - `grep "select-none" gui/src/components/CodePreview.tsx` returns 0 matches.
    - `grep "preventDefault" gui/src/components/CodePreview.tsx` returns 0 matches in mousedown contexts (an unrelated `preventDefault` elsewhere is acceptable; the lint is that the sub-block click handlers don't preventDefault).
    - `grep "Monaco\|prism\|highlight.js\|shiki" gui/src/components/CodePreview.tsx gui/package.json` returns 0 matches.
    - `data-sub-block` attribute renders on every sub-block wrapper.
    - Sub-block stable IDs follow `code-sb-{section_lowercase}-{index}` convention.
    - No new tsc errors beyond pre-existing 11.
  </acceptance_criteria>
  <done>CodePreview UI delivers section-by-section render + hover/click/scroll/flash; three Plan 01 RED tests GREEN.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Add Copy + Export buttons to BottomPanel.tsx TabsList (right side)</name>
  <files>gui/src/components/BottomPanel.tsx</files>
  <read_first>
    - gui/src/components/BottomPanel.tsx (current 32-line implementation; the `<TabsList>` at line 21)
    - gui/src/components/ui/tabs.tsx (TabsList component — verify it accepts arbitrary children and supports flex layout for right-side alignment)
    - gui/src/components/Toolbar.tsx (existing top-Toolbar Export button at lines 122-129 — match its variant / size for the BottomPanel buttons OR pick a lighter variant per Research §"ui/button.tsx" recommendation; the panel is a secondary surface)
    - gui/src/components/resources/ResourceRow.tsx lines 114-122 (the setTimeout-with-cleanup pattern for 1.5s confirmation — the Copy button reuses this shape)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 8: Toggle-with-confirmation 1.5s state on Copy button", §"Pattern 11: exportCode.ts shared util shape"
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-16, D-17, D-18, D-19
  </read_first>
  <behavior>
    Layout:
    - `<TabsList>` (currently `mx-2 mt-1`) becomes a flex row: existing `<TabsTrigger value="code">Code</TabsTrigger>` on the left, a `<div className="ml-auto flex items-center gap-1">` on the right containing the two buttons.

    Buttons:
    - Copy: `<Button size="sm" variant="outline" disabled={nodes.length === 0} onClick={handleCopy}><Copy/>Copy</Button>` — swaps to `<Check/>Copied` for 1.5s after success.
    - Export: `<Button size="sm" variant="outline" disabled={nodes.length === 0} onClick={handleExport}><Download/>Export</Button>`.
    - Lucide icons: `Copy`, `Check`, `Download` (all already in tree per Toolbar.tsx usage).

    Handlers:
    - `handleCopy`: compute `sections = generateCode(nodes, edges, { anchors }, getComponent, resources, { bcMode, bcSymmetric })`; await `navigator.clipboard.writeText(serializeSections(sections))`; on success `setCopied(true)`. The 1.5s timer is in a `useEffect` watching `copied` per Research Pattern 8.
    - `handleExport`: compute `sections` (same as Copy); call `await exportCode({ sections, nodes, ...whatever-other-args-the-util-needs })`. Discard the boolean return (the util handles its own validation; no in-component status display needed — matches top-Toolbar Export behavior).

    Store reads needed: `nodes`, `edges`, `anchors`, `resources`, `bcMode`, `bcSymmetric` (for sections computation), plus `nodes.length` for the disabled predicate. To avoid double-computing `sections` (CodePreview also computes it), the planner has two options:
        a) Recompute in BottomPanel (simple, costs ~5-50ms per click — acceptable).
        b) Hoist `sections` computation to BottomPanel and pass to CodePreview via prop (clean but requires CodePreview signature change).
    Pick (a). It's the simplest and matches the existing pattern where `Toolbar.tsx` ALSO independently computes its own `generateCode` call.

    Imports: `Copy`, `Check`, `Download` from `lucide-react`. `Button` from `./ui/button`. `useStore`. `generateCode`, `serializeSections` from `../lib/codeGenerator`. `exportCode` from `../lib/exportCode`. `getComponent` from `../registry`.
  </behavior>
  <action>
    Edit `BottomPanel.tsx`. Restructure the `<TabsList>` per the layout block above. Add the two handlers and a `copied` state. Add the `useEffect`-driven 1500ms timer.

    Concrete `<TabsList>` shape:
    ```tsx
    <TabsList className="mx-2 mt-1 flex">
      <TabsTrigger value="code" className="text-[13px] font-medium">Code</TabsTrigger>
      <div className="ml-auto flex items-center gap-1">
        <Button size="sm" variant="outline" disabled={nodes.length === 0} onClick={handleCopy}>
          {copied ? <><Check className="h-4 w-4 mr-1" /> Copied</> : <><Copy className="h-4 w-4 mr-1" /> Copy</>}
        </Button>
        <Button size="sm" variant="outline" disabled={nodes.length === 0} onClick={handleExport}>
          <Download className="h-4 w-4 mr-1" /> Export
        </Button>
      </div>
    </TabsList>
    ```

    Verify `TabsList` accepts non-`TabsTrigger` children — read `gui/src/components/ui/tabs.tsx`. If shadcn's TabsList restricts children, wrap the right-side group in a sibling div OUTSIDE the TabsList but inside the same Tabs row. Read first; adapt.

    DO NOT add a new test file for BottomPanel — Plan 01 did not specify one for this surface, and the Copy/Export behavior is covered indirectly via `exportCode.test.ts` (Plan 03) and the manual UAT in `<verification>` below. If the planner-implementor wants confidence, a 2-3-`it` test file `BottomPanel.test.tsx` is fine to add (small scope, ~30 lines) — but not required.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run 2>&1 | tail -15 && npx tsc --noEmit 2>&1 | grep "error TS" | grep -v "pre-existing" | head -10</automated>
  </verify>
  <acceptance_criteria>
    - `BottomPanel.tsx` renders Copy + Export buttons inside (or alongside) `<TabsList>`, right-side-anchored via `ml-auto`.
    - Both buttons have `disabled={nodes.length === 0}`.
    - Copy button uses `Copy` icon initially, swaps to `Check`+'Copied' for 1.5s after a click, then reverts.
    - Export button calls `exportCode(...)` from `gui/src/lib/exportCode.ts`.
    - No new tsc errors.
    - Existing tests (BottomPanel-adjacent: AppShell.test.tsx, Toolbar tests) still pass.
  </acceptance_criteria>
  <done>Copy + Export buttons live in panel; behavior matches D-16..D-19.</done>
</task>

</tasks>

<verification>
After both tasks:

```bash
cd /home/itay/projects/Julia-STREAM/gui
# All Phase 66 tests now GREEN (Plan 01's 5 + Plan 03's 2 = 7 new test files)
npx vitest --run 2>&1 | tail -30

# TSC clean
npx tsc --noEmit 2>&1 | grep "error TS" | wc -l   # expect 11 (pre-existing)
```

Manual UAT (run the dev server, click through):
```bash
cd /home/itay/projects/Julia-STREAM/gui && npm run dev
```

UAT checklist (with a non-trivial loop graph: pump + channel + friction + connect edges):

1. **Section rendering:** Open bottom panel. Confirm 4-5 visually-grouped sections appear with headers (`Imports`, `Components`, `Composition`, optional `Resources`, `Main`).
2. **Hover-to-write-store:** Open React DevTools or `useStore.getState()` in the browser console. Hover a sub-block. Confirm `hoveredSourceIds` becomes a non-empty Set. Move mouse off; confirm it clears.
3. **Click-to-pin:** Click a sub-block. Confirm `pinnedSourceIds` has its IDs. Click another sub-block. Confirm additive (both sets of IDs present). Click the first again — confirm its IDs removed.
4. **Empty-space click clears pins:** Click a sub-block to pin. Click in the ScrollArea gutter (visible whitespace not over any sub-block). Confirm `pinnedSourceIds` empty.
5. **Esc clears pins:** Pin some. Press Esc with focus outside any input. Confirm `pinnedSourceIds` empty.
6. **stream:show-code-for:** Right-click a canvas node → "Show generated Julia code". Confirm: (a) bottom panel opens if closed, (b) the matching `@named <node>` sub-block in Components scrolls into view, (c) a brief visual flash (whatever data-flash styling is wired — even a temporary background tint) appears on the sub-block, (d) `pinnedSourceIds` contains the node UUID.
7. **Copy:** Click Copy. Confirm "Copied" + Check icon for ~1.5s, then revert. Paste into a text editor; confirm the full assembled script lands, with `# === Imports ===` and other D-12 headers.
8. **Export:** Click Export. Confirm Tauri save dialog appears. Cancel; confirm no file written. Click again, pick a path; confirm `.jl` file written with the D-12 headers.
9. **Top-Toolbar Export still works:** Close panel. Click top-Toolbar Export. Confirm file write — D-18 requires this path stays alive.
10. **Text-selection:** Click+drag across two sub-block boundaries in the code panel. Confirm browser-native selection works and selects clean text. Ctrl+C; paste; confirm the selected range is what was copied.
11. **Disabled state:** Empty canvas (delete all nodes). Confirm Copy + Export buttons are visibly disabled.
12. **Hover-ring on canvas:** **NOT this plan's job — Plan 05 wires StreamNode subscription. For now, expect no visible ring on canvas. Verify hover/pin still WRITE the store (step 2/3).**

Note: any flash visual that's "wrong color" or "feels too fast/slow" is Claude's Discretion per CONTEXT — Phase 72 tunes. The acceptance gate is functional ("a visual flash happens, persists ~1.5s, then disappears"), not aesthetic.
</verification>

<success_criteria>
- `CodePreview.tsx` and `BottomPanel.tsx` rewritten per spec.
- Plan 01's three CodePreview RED tests flip GREEN.
- All Phase 66 vitest tests GREEN (5 from Plan 01 + 2 from Plan 03 = 7 new files; plus all 5 existing codegen files still GREEN from Plan 02).
- Manual UAT items 1-11 pass on the dev server.
- No new tsc errors.
- No new packages added to `gui/package.json` (verify with `git diff gui/package.json` = empty).
</success_criteria>

<output>
Create `.planning/phases/66-code-preview-rework/66-04-SUMMARY.md` when done. Summary lists: CodePreview line-count delta, sub-block dom-id convention used, flash mechanism (CSS class vs data-attribute vs inline style), the explicit pin-on-show-code-for vs hover-on-show-code-for choice with rationale, and the UAT checklist pass/fail per item.
</output>
