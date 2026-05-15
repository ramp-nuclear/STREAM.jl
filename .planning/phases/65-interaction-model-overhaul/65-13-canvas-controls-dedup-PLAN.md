---
phase: 65-interaction-model-overhaul
plan: 13
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/store/useStore.ts
  - gui/src/components/CanvasPanel.tsx
  - gui/src/components/canvasMenus/ZoomInButton.tsx
  - gui/src/components/canvasMenus/ZoomOutButton.tsx
  - gui/src/components/canvasMenus/FitViewButton.tsx
  - gui/src/components/canvasMenus/InteractiveLockButton.tsx
  - gui/src/store/__tests__/interactiveLocked.test.ts
autonomous: false
requirements: []
gap_closure: true
tags: [canvas-overlay, reactflow-controls, ui-polish, gap-closure, phase-65]

must_haves:
  truths:
    - "The canvas no longer renders ReactFlow's built-in bottom-left `&lt;Controls /&gt;` element."
    - "The top-right canvas overlay now contains five buttons: Zoom In, Zoom Out, Fit View, Interactive Lock, Snap-to-Grid (Snap-to-Grid stays at the rightmost / wherever the visual order looks clean)."
    - "Zoom In / Zoom Out / Fit View call `useReactFlow().zoomIn() / zoomOut() / fitView()` respectively."
    - "Interactive Lock toggles a new zustand boolean `interactiveLocked`; when true, ReactFlow's `nodesDraggable`, `nodesConnectable`, `elementsSelectable`, and `panOnDrag` are all disabled (nodes are frozen, no new connections, no selection — viewport pan only happens via panOnScroll/wheel)."
    - "`interactiveLocked` is session-only (NOT persisted to `.scp`) — it's a viewport-state preference, not a project property."
    - "The four new icon buttons follow the same styling as SnapToGridButton.tsx (8×8 rounded border, bg-primary when active)."
  artifacts:
    - path: "gui/src/store/useStore.ts"
      provides: "New `interactiveLocked: boolean` field (default false), `setInteractiveLocked: (v: boolean) =&gt; void` action; both declared in AppState interface."
      contains: "interactiveLocked"
    - path: "gui/src/components/canvasMenus/ZoomInButton.tsx"
      provides: "Icon button calling useReactFlow().zoomIn()."
    - path: "gui/src/components/canvasMenus/ZoomOutButton.tsx"
      provides: "Icon button calling useReactFlow().zoomOut()."
    - path: "gui/src/components/canvasMenus/FitViewButton.tsx"
      provides: "Icon button calling useReactFlow().fitView()."
    - path: "gui/src/components/canvasMenus/InteractiveLockButton.tsx"
      provides: "Icon button toggling interactiveLocked store field; visual state mirrors SnapToGridButton (bg-primary when locked)."
    - path: "gui/src/components/CanvasPanel.tsx"
      provides: "Remove `Controls` import (line 4) and `&lt;Controls /&gt;` render (line 328). Add four new button siblings to SnapToGridButton in the top-right overlay div. Wire `nodesDraggable`, `nodesConnectable`, `elementsSelectable`, and `panOnDrag` to respond to interactiveLocked."
  key_links:
    - from: "InteractiveLockButton onClick"
      to: "useStore.setInteractiveLocked"
      via: "store action"
      pattern: "setInteractiveLocked"
    - from: "CanvasPanel ReactFlow nodesDraggable/nodesConnectable/elementsSelectable/panOnDrag"
      to: "useStore.interactiveLocked"
      via: "props derived from useStore selector"
      pattern: "interactiveLocked"
---

<objective>
Close UAT Test 14 cosmetic gap (#4): hide ReactFlow's built-in bottom-left `&lt;Controls /&gt;` panel
because the new top-right overlay (Plan 06 SnapToGridButton) makes it feel redundant.

Root cause (`.planning/debug/reactflow-controls-dedup.md`): `&lt;Controls /&gt;` rendered
unconditionally at `gui/src/components/CanvasPanel.tsx:328`; the top-right overlay at
lines 333-335 contains ONLY `&lt;SnapToGridButton /&gt;`. The four ReactFlow Controls functions
(zoom in, zoom out, fit view, interactive lock) have no top-right counterpart yet. Removing
`&lt;Controls /&gt;` without replacing those four functions strips them from the UI entirely.

Fix: add four new top-right icon buttons (Lucide `ZoomIn`, `ZoomOut`, `Maximize`, `Lock`)
mirroring `SnapToGridButton.tsx` structure. Wire the first three to
`useReactFlow().zoomIn/zoomOut/fitView`. Wire the fourth to a new `interactiveLocked` zustand
boolean. Then delete `&lt;Controls /&gt;` and the import.

Approach pinned by the debug session: "add top-right counterparts first using @xyflow/react
v12's useReactFlow() helpers (zoomIn, zoomOut, fitView) plus a lock toggle backed by a new
useStore boolean."

Decision: `interactiveLocked` is session-only. Not persisted to `.scp`. Not part of newProject.
It's a viewport-state preference like the ReactFlow Controls lock — survives only for the
current session.

Purpose: canvas chrome polish requested by UAT.

Output: 7 files (5 new, 2 modified), 1 vitest covering the new store action.

Source: `.planning/debug/reactflow-controls-dedup.md` (root cause confirmed, fix path
chosen explicitly = path (b) "add top-right counterparts first, then remove Controls").
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/65-interaction-model-overhaul/65-06-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/reactflow-controls-dedup.md
@gui/src/components/CanvasPanel.tsx
@gui/src/components/canvasMenus/SnapToGridButton.tsx
@gui/src/store/useStore.ts

<interfaces>
<!-- SnapToGridButton.tsx — pattern to mirror for the four new buttons -->
The 8×8 icon-button shape, aria-pressed state, on/off Tailwind class swap, and Lucide icon
sizing (h-4 w-4) are the canonical style. Reuse verbatim. The toggle-style buttons
(InteractiveLockButton) get the same `bg-primary text-primary-foreground` active style;
the action buttons (Zoom In / Out / Fit) stay in the inactive style permanently.

<!-- @xyflow/react v12 useReactFlow API -->
import { useReactFlow } from "@xyflow/react";
const { zoomIn, zoomOut, fitView } = useReactFlow();
- zoomIn()           — increments zoom by default step
- zoomOut()          — decrements zoom by default step
- fitView()          — fits all nodes in viewport (uses default padding)
None take required args; all are stable identities suitable for direct onClick handlers.

<!-- useStore.ts: snapToGrid action pattern (lines 1007-1008) -->
The pattern to mirror for interactiveLocked:

  // interface (around line 195):
  interactiveLocked: boolean;
  setInteractiveLocked: (v: boolean) =&gt; void;

  // initial state (around line 798):
  interactiveLocked: false,

  // action (around line 1008):
  setInteractiveLocked: (v) =&gt; set({ interactiveLocked: v }),
  // NOTE: do NOT set isDirty: true — this is a session preference, not a project change.

DO NOT touch the .scp serialize/deserialize code paths (around lines 2080-2300). interactiveLocked
must NOT appear in the .scp layout block. The newProject and loadProjectFromPath actions
should NOT reset it (or, if they do reset, reset to `false` explicitly — but the canonical
behavior is "session-only, untouched by project lifecycle"). Pick "untouched by project
lifecycle" for simplicity: do not add interactiveLocked to any project payload.

<!-- CanvasPanel.tsx — props to plumb -->
ReactFlow accepts these props (all booleans, default true):
  nodesDraggable={!interactiveLocked}
  nodesConnectable={!interactiveLocked}
  elementsSelectable={!interactiveLocked}
  panOnDrag={interactiveLocked ? false : [2]}    // when locked, no pan-on-drag at all;
                                                  // when unlocked, right-mouse pan (existing Plan 03 behavior)

Note: selectionOnDrag is left ON regardless — selection box still works while unlocked.
When locked, elementsSelectable: false makes selection impossible anyway.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add interactiveLocked store field + setter, with vitest</name>
  <files>
    gui/src/store/useStore.ts
    gui/src/store/__tests__/interactiveLocked.test.ts
  </files>
  <behavior>
    - Test: initial `useStore.getState().interactiveLocked === false`.
    - Test: `useStore.getState().setInteractiveLocked(true)` updates `interactiveLocked` to true
      AND does NOT set `isDirty: true` (session preference, not a project change).
    - Test: `interactiveLocked` is NOT present in the serialized `.scp` payload from
      `useStore.getState().serializeProject?.()` or whatever the serializer is named.
      (If the serializer is internal, instead grep the useStore module for `interactiveLocked` —
      it should appear ONLY in interface/state/action, not inside the serialize logic.)
  </behavior>
  <action>
    **TDD RED → GREEN.**

    Step 1 (RED). Create `gui/src/store/__tests__/interactiveLocked.test.ts`. Pattern on
    existing store tests (e.g. `gui/src/store/__tests__/autoRecover.actions.test.ts` if it
    exists, or any `useStore.*.test.ts` sibling). Reset store between tests using
    `useStore.setState({ ... })` with the initial state shape, or call `useStore.persist?.clear?.()`
    if a persistence middleware is involved (project uses plain `create` per
    `.planning/debug/gui-drag-perf.md`, so no persist middleware — `setState` is enough).

    Test cases:
      1. `expect(useStore.getState().interactiveLocked).toBe(false);`
      2. Call `useStore.getState().setInteractiveLocked(true)`. Assert
         `useStore.getState().interactiveLocked === true` AND
         `useStore.getState().isDirty === false` (assuming isDirty started false).
         Then call setInteractiveLocked(false) and assert it flips back.
      3. Inspect the module: import `useStore` and the serialize helper if exported (e.g.
         `serializeProject` or `saveProject`); if not exported, this is a static grep test:
         use `fs.readFileSync` (Node API available in vitest) and assert that
         "interactiveLocked" appears ONLY in the interface section (around line 195) and the
         initial-state object (around line 798) and the action implementation (around line
         1008) — and NOT inside any serialize/deserialize function body or `.scp` schema
         literal. A simple `grep -c interactiveLocked` is 3 (exactly 3). Or in vitest:
         `expect(contents.match(/interactiveLocked/g)?.length).toBe(3)` (interface, init,
         action) — adjust to 4 if you find a justifiable extra occurrence (e.g. a comment),
         but document why.

    All tests must FAIL initially because the field doesn't exist yet. Commit:
    ```
    git add gui/src/store/__tests__/interactiveLocked.test.ts
    git commit -m "test(65-13): RED — interactiveLocked store field

    Failing vitest cases for the new session-only interactiveLocked field
    that Plan 13 will use to replace ReactFlow built-in Controls lock.

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```

    Step 2 (GREEN). Edit `gui/src/store/useStore.ts`:
      - Around line 195 in the AppState interface (just after `setSnapToGrid` declaration):
        ```
        // Phase 65 Plan 13: viewport interaction lock (session-only, NOT persisted in .scp).
        interactiveLocked: boolean;
        setInteractiveLocked: (v: boolean) =&gt; void;
        ```
      - Around line 798 in the initial state object (next to `snapToGrid: false,`):
        ```
        interactiveLocked: false,
        ```
      - Around line 1008 next to `setSnapToGrid`:
        ```
        // Phase 65 Plan 13: do NOT set isDirty — session preference, not project state.
        setInteractiveLocked: (v) =&gt; set({ interactiveLocked: v }),
        ```
      - **Do NOT** touch serialize/deserialize/newProject/loadProjectFromPath/saveProject
        paths. The field intentionally does not survive project lifecycle.

    Re-run vitest — all 3 cases pass:
      cd gui &amp;&amp; npx vitest run src/store/__tests__/interactiveLocked.test.ts

    Commit:
    ```
    git add gui/src/store/useStore.ts
    git commit -m "feat(65-13): interactiveLocked session field + setter

    Session-only zustand boolean controlling ReactFlow nodesDraggable /
    nodesConnectable / elementsSelectable / panOnDrag (next task).
    Deliberately NOT persisted to .scp — viewport preference, not project
    state.

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      grep -q "interactiveLocked: boolean" gui/src/store/useStore.ts
      grep -q "setInteractiveLocked:" gui/src/store/useStore.ts
      test "$(grep -c "interactiveLocked" gui/src/store/useStore.ts)" -ge 3
      test "$(grep -c "interactiveLocked" gui/src/store/useStore.ts)" -le 4
      cd gui &amp;&amp; npx vitest run src/store/__tests__/interactiveLocked.test.ts
    </automated>
  </verify>
  <done>
    Three vitest cases pass; useStore exposes interactiveLocked + setInteractiveLocked; field
    does not appear in .scp serialize paths; two atomic commits (RED, GREEN) recorded.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add 4 top-right overlay buttons + wire CanvasPanel; delete &lt;Controls /&gt;</name>
  <files>
    gui/src/components/canvasMenus/ZoomInButton.tsx
    gui/src/components/canvasMenus/ZoomOutButton.tsx
    gui/src/components/canvasMenus/FitViewButton.tsx
    gui/src/components/canvasMenus/InteractiveLockButton.tsx
    gui/src/components/CanvasPanel.tsx
  </files>
  <action>
    **Step 1.** Create four button components mirroring `SnapToGridButton.tsx`. Same file
    header pattern, same 8×8 rounded-border icon-button JSX, same Tailwind class structure.

    Path / icon / behavior for each:

      gui/src/components/canvasMenus/ZoomInButton.tsx
        - Icon: `ZoomIn` from `lucide-react`
        - aria-label: "Zoom in"
        - title: "Zoom in"
        - onClick: `() =&gt; zoomIn()` — read `zoomIn` from `useReactFlow()`
        - Always in "inactive" style (it's an action, not a toggle)

      gui/src/components/canvasMenus/ZoomOutButton.tsx
        - Icon: `ZoomOut` from `lucide-react`
        - aria-label: "Zoom out"
        - title: "Zoom out"
        - onClick: `() =&gt; zoomOut()` from `useReactFlow()`
        - Always inactive style

      gui/src/components/canvasMenus/FitViewButton.tsx
        - Icon: `Maximize` from `lucide-react` (closest equivalent to RF's `fit-view`)
        - aria-label: "Fit view"
        - title: "Fit canvas to view"
        - onClick: `() =&gt; fitView()` from `useReactFlow()`
        - Always inactive style

      gui/src/components/canvasMenus/InteractiveLockButton.tsx
        - Icon: `Lock` from `lucide-react` when locked, `Unlock` when unlocked
          (or stay with `Lock` always and use the bg-primary active styling to convey state —
          choose whichever matches SnapToGridButton's pattern; SnapToGridButton uses a single
          icon and toggles the bg, so mirror that for consistency — use `Lock` always,
          aria-pressed reflects state).
        - aria-label: "Lock canvas interactions"
        - aria-pressed: `interactiveLocked` from `useStore`
        - data-state: `interactiveLocked ? "on" : "off"`
        - title: `interactiveLocked ? "Unlock canvas interactions" : "Lock canvas interactions"`
        - onClick: `() =&gt; setInteractiveLocked(!interactiveLocked)`
        - Active style when `interactiveLocked === true`
        - Read both `interactiveLocked` and `setInteractiveLocked` from `useStore` with
          separate primitive selectors:
            const interactiveLocked = useStore((s) =&gt; s.interactiveLocked);
            const setInteractiveLocked = useStore((s) =&gt; s.setInteractiveLocked);

    Copy the JSX skeleton from `SnapToGridButton.tsx` verbatim and swap icon + handler +
    aria attributes. Keep the file ≤ 35 lines like the existing SnapToGridButton.

    **Step 2.** Edit `gui/src/components/CanvasPanel.tsx`:

      - Line 4 imports: remove `Controls` from the `@xyflow/react` named imports. Keep
        `ReactFlow`, `MiniMap`, `Background`, `BackgroundVariant`, `ConnectionLineType`,
        `SelectionMode`, `useReactFlow`, etc.

      - After the existing `import SnapToGridButton from "./canvasMenus/SnapToGridButton";`
        line, add imports for the four new buttons:
        ```
        import ZoomInButton from "./canvasMenus/ZoomInButton";
        import ZoomOutButton from "./canvasMenus/ZoomOutButton";
        import FitViewButton from "./canvasMenus/FitViewButton";
        import InteractiveLockButton from "./canvasMenus/InteractiveLockButton";
        ```

      - Read `interactiveLocked` from the store. Add a primitive selector near the existing
        `snapEnabled` selector (the file already has `useStore` destructured at line 59-60;
        prefer a separate primitive selector to avoid widening the destructure object):
        ```
        const interactiveLocked = useStore((s) =&gt; s.interactiveLocked);
        ```
        (Place near the snap/active-layer selectors, before the JSX return.)

      - Update ReactFlow JSX props (around line 298-326) to make these reactive:
        ```
        nodesDraggable={!interactiveLocked}
        nodesConnectable={!interactiveLocked}
        elementsSelectable={!interactiveLocked}
        panOnDrag={interactiveLocked ? false : [2]}
        ```
        Replace ONLY the `panOnDrag={[2]}` line and add the three new props near it.
        Keep `selectionOnDrag` and `selectionMode` unchanged.

      - Delete the `&lt;Controls /&gt;` line (currently line 328).

      - Update the top-right overlay div to include the four new buttons. Convert the div
        from a single-child container to a 5-child flex column:
        ```
        &lt;div className="absolute top-2 right-2 z-10 flex flex-col gap-1"&gt;
          &lt;ZoomInButton /&gt;
          &lt;ZoomOutButton /&gt;
          &lt;FitViewButton /&gt;
          &lt;InteractiveLockButton /&gt;
          &lt;SnapToGridButton /&gt;
        &lt;/div&gt;
        ```
        Order rationale: zoom controls grouped at top, then fit-view, then the two toggles
        (lock + snap) at the bottom. Update the existing inline comment to:
        `{/* Phase 65 Plan 13: top-right overlay — Zoom/Fit/Lock replace ReactFlow built-in &lt;Controls /&gt;; SnapToGridButton from Plan 06. */}`

      - Optional but recommended: search-replace any remaining stale references to
        `Controls` in the file (should be only the import + the JSX usage you removed).
        Verify with `grep -n "Controls" gui/src/components/CanvasPanel.tsx` — expect 0 hits
        (the variant `BackgroundVariant.Dots`, `ConnectionLineType.SmoothStep`, and
        `ControlButton`-like identifiers if any, do NOT match plain "Controls").

    **Step 3.** Sanity-check tsc:
      cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c "error TS"
    Baseline pre-edit was 11 (Phase 71 owns); post-edit must be ≤ baseline.

    Run all existing canvas tests to catch regressions:
      cd gui &amp;&amp; npx vitest run src/components

    Commit (single atomic commit — primitives + wiring are a cohesive change):
    ```
    git add gui/src/components/canvasMenus/ZoomInButton.tsx \
            gui/src/components/canvasMenus/ZoomOutButton.tsx \
            gui/src/components/canvasMenus/FitViewButton.tsx \
            gui/src/components/canvasMenus/InteractiveLockButton.tsx \
            gui/src/components/CanvasPanel.tsx
    git commit -m "feat(65-13): replace &lt;Controls /&gt; with top-right Zoom/Fit/Lock buttons

    Four new icon buttons (ZoomIn, ZoomOut, FitView, InteractiveLock)
    mirror SnapToGridButton.tsx and call useReactFlow().zoomIn / zoomOut /
    fitView and the new useStore.setInteractiveLocked respectively.
    interactiveLocked drives nodesDraggable / nodesConnectable /
    elementsSelectable / panOnDrag so the canvas truly freezes when
    locked.

    Closes UAT Test 14 (.planning/debug/reactflow-controls-dedup.md).

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # 4 new button files exist
      test -f gui/src/components/canvasMenus/ZoomInButton.tsx
      test -f gui/src/components/canvasMenus/ZoomOutButton.tsx
      test -f gui/src/components/canvasMenus/FitViewButton.tsx
      test -f gui/src/components/canvasMenus/InteractiveLockButton.tsx
      # &lt;Controls /&gt; removed from CanvasPanel
      test "$(grep -c "&lt;Controls /&gt;\\|&lt;Controls/&gt;" gui/src/components/CanvasPanel.tsx)" = 0
      # Controls no longer imported
      test "$(grep -cE "^import.*Controls.*from .@xyflow" gui/src/components/CanvasPanel.tsx)" = 0
      # New buttons imported
      grep -q "import ZoomInButton" gui/src/components/CanvasPanel.tsx
      grep -q "import ZoomOutButton" gui/src/components/CanvasPanel.tsx
      grep -q "import FitViewButton" gui/src/components/CanvasPanel.tsx
      grep -q "import InteractiveLockButton" gui/src/components/CanvasPanel.tsx
      # interactiveLocked wired
      grep -q "interactiveLocked" gui/src/components/CanvasPanel.tsx
      grep -q "nodesDraggable={!interactiveLocked}" gui/src/components/CanvasPanel.tsx
      # Vitest no regression
      cd gui &amp;&amp; npx vitest run src/components 2>&amp;1 | tail -5
    </automated>
  </verify>
  <done>
    Four new files committed; CanvasPanel no longer imports or renders `Controls`; top-right
    overlay has 5 buttons in a flex column; ReactFlow interaction props wired to
    interactiveLocked; vitest passes.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Visual + functional checkpoint</name>
  <files>(no code change — visual + functional verification only)</files>
  <action>
    Removed ReactFlow's built-in bottom-left Controls; added 4 top-right buttons. Need a
    quick visual + functional pass: that the bottom-left is empty and that zoom/fit/lock
    behaviors work via the new buttons.

    **How to verify:**

    1. `cd gui &amp;&amp; npm run tauri dev` (or HMR-reload).
    2. Confirm: no bottom-left Controls panel. Top-right shows 5 icon buttons in a column
       (ZoomIn / ZoomOut / FitView / Lock / Grid).
    3. Click ZoomIn ≥ 3 times — canvas zooms in. Click ZoomOut ≥ 3 times — canvas zooms out.
       Click FitView — canvas fits to all nodes.
    4. Click InteractiveLock. It turns active (bg-primary). Try to drag a node — node does
       NOT move. Try to right-drag-pan — pan does NOT happen. Try to click a node — selection
       does NOT change. Click InteractiveLock again — unlock — drag/pan/select all work again.
    5. Confirm Snap-to-Grid button still works (Plan 06 regression check).
  </action>
  <verify>
    <human-check>Human runs the 5-step visual + functional check on the live Tauri dev shell.</human-check>
  </verify>
  <done>User types "approved" indicating all 5 checks passed.</done>
  <resume-signal>
    Type "approved" if all 5 checks pass; else describe which step fails.
  </resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

(none — UI only; no IPC, no fs)

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-13a | Denial of Service | InteractiveLockButton | accept | A stuck-locked state freezes the canvas. Unlock is one click. Documented via aria-pressed + title; no persistence means a reload restores unlocked. |
| T-65-13b | Tampering | useStore.interactiveLocked field placement | mitigate | Vitest case 3 asserts the field appears ≤ 4 times in useStore.ts to catch accidental insertion into serialize paths. |
</threat_model>

<verification>
- `test -f` for all 4 new button files.
- `&lt;Controls /&gt;` gone from CanvasPanel; import line not present.
- `interactiveLocked` wired to 4 ReactFlow props.
- 3 new vitest cases pass; no existing test regresses.
- Task 3 checkpoint approved.
</verification>

<success_criteria>
- ReactFlow built-in `&lt;Controls /&gt;` no longer renders.
- Top-right overlay contains: ZoomIn, ZoomOut, FitView, InteractiveLock, SnapToGrid (5 buttons in a flex column).
- useStore exposes `interactiveLocked: boolean` (default false) and `setInteractiveLocked: (v) =&gt; void`. Not persisted in `.scp`.
- Locking the canvas freezes node drag, connect, selection, and pan.
- Three new vitest cases pass; no `src/components` test regresses.
- Three atomic commits: RED test + GREEN store + button suite + CanvasPanel wiring (2 commits in Task 1 + 1 in Task 2 = 3 total).
- Task 3 checkpoint approved.
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-13-SUMMARY.md` when done.
</output>
