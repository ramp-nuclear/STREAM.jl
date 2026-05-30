---
phase: 66-code-preview-rework
plan: 5
type: execute
wave: 4
depends_on: [66-04]
files_modified:
  - gui/src/components/StreamNode.tsx
  - gui/src/index.css
  - gui/src/components/__tests__/StreamNode.codeHover.test.tsx
  - .planning/notes/phase-66-hover-ring-tuning.md
autonomous: false

requirements: []

must_haves:
  truths:
    - "Each `StreamNode` subscribes to `hoveredSourceIds` and `pinnedSourceIds` via per-node primitive-boolean selectors (`useStore(useCallback((s) => s.hoveredSourceIds.has(id), [id]))`) — same pattern as `hasAnchor` / `hasBCError`."
    - "When the node's UUID is in `hoveredSourceIds`, the node renders with class `stream-node--code-hover`."
    - "When the node's UUID is in `pinnedSourceIds`, the node renders with class `stream-node--code-pinned`."
    - "Both classes can coexist (the placeholder CSS gives `--code-pinned` slightly heavier styling so the user can tell them apart)."
    - "Re-render scope: toggling one ID re-renders at most 2 StreamNode instances (the one being added and the one being removed if applicable), not all N nodes."
    - "Classes do NOT collide with Phase 71's planned `stream-node--invalid` or Phase 68's `stream-node--layer-dimmed` / `stream-node--layer-hidden` (verified via grep)."
    - "Visual ring style is `outline` not `border` — Phase 64's autoflip box-dimension math remains unaffected."
    - "Handoff note for Phase 72 visual tuning lives at `.planning/notes/phase-66-hover-ring-tuning.md`."
    - "Phase 66 manual UAT checkpoint (post-implementation): right-click → 'Show generated Julia code' end-to-end works AND the corresponding canvas node visibly gets a hover ring."
  artifacts:
    - path: "gui/src/components/StreamNode.tsx"
      provides: "hover/pin class application per node"
    - path: "gui/src/index.css"
      provides: "Phase 66 hover-ring + pinned-ring CSS rules"
    - path: ".planning/notes/phase-66-hover-ring-tuning.md"
      provides: "Phase 72 handoff: what to re-tune (color, stroke width, animation timing), where to do it"
  key_links:
    - from: "StreamNode.tsx (per node)"
      to: "useStore.hoveredSourceIds, useStore.pinnedSourceIds"
      via: "useStore(useCallback selector) returning primitive boolean"
      pattern: "hoveredSourceIds\\.has|pinnedSourceIds\\.has"
    - from: "StreamNode.tsx className"
      to: "gui/src/index.css"
      via: "CSS class names stream-node--code-hover / stream-node--code-pinned"
      pattern: "stream-node--code-(hover|pinned)"
---

<objective>
Wire the canvas-side visual ring for Phase 66's code-panel hover and pin states. `StreamNode.tsx` subscribes to the two new store slices via per-node primitive-boolean selectors (matching the established `hasAnchor` / `hasBCError` pattern). Two new CSS rules in `gui/src/index.css` provide placeholder outline styling. Manual UAT confirms the end-to-end loop: right-click a canvas node → "Show generated Julia code" → panel opens, scrolls, flashes the sub-block, AND the canvas node visibly gets a ring.

Purpose: deliver the user-visible bidirectional traceability. After this plan, Phase 66 is functionally complete; Phase 72 owns final visual tuning (color, animation, stroke).
Output: StreamNode subscription wired; CSS placeholder lands; tiny new test confirming the class application; handoff doc for Phase 72.
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
@.planning/phases/66-code-preview-rework/66-04-SUMMARY.md
@gui/src/components/StreamNode.tsx
@gui/src/index.css
</context>

<interfaces>
<!-- Existing patterns this plan extends (verbatim, no new interfaces). -->

`StreamNode.tsx` already has primitive-boolean store subscriptions (Research Pattern 9 verified):
- Line 174 area: `const hasAnchor = useStore(useCallback((s) => s.anchors[id] != null, [id]));`
- Line 317 area: `const hasBCError = useStore(useCallback((s) => s.errorNodeIds.has(id), [id]));`

Phase 66 adds two parallel subscriptions in the same shape:
```tsx
const isCodeHovered = useStore(useCallback((s) => s.hoveredSourceIds.has(id), [id]));
const isCodePinned = useStore(useCallback((s) => s.pinnedSourceIds.has(id), [id]));
```

And appends conditional class names to whatever className-construction the node already uses:
```tsx
className={cn(
  // ... existing classes ...
  isCodeHovered && "stream-node--code-hover",
  isCodePinned && "stream-node--code-pinned",
)}
```
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Subscribe StreamNode.tsx to hoveredSourceIds / pinnedSourceIds + add test</name>
  <files>gui/src/components/StreamNode.tsx, gui/src/components/__tests__/StreamNode.codeHover.test.tsx</files>
  <read_first>
    - gui/src/components/StreamNode.tsx lines 174, 184-195, 259-275, 309-321 (Research-identified primitive-boolean selector + className-application sites; this file is large — focus reading on these regions plus the surrounding context)
    - gui/src/components/__tests__/StreamNode.anchor.test.tsx (the established testing pattern for primitive-boolean StreamNode subscriptions — copy fixture shape)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 9: Hover-ring CSS class strategy in StreamNode" (the recommended subscription + re-render fanout analysis)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-05, D-09, D-11 (hover ring is a visually-distinct style; pin is sticky; ephemeral session state — these constrain class semantics)
  </read_first>
  <behavior>
    StreamNode subscription:
    - Add `const isCodeHovered = useStore(useCallback((s) => s.hoveredSourceIds.has(id), [id]));`
    - Add `const isCodePinned = useStore(useCallback((s) => s.pinnedSourceIds.has(id), [id]));`
    - Append both to the className composition (using whatever class-composition helper StreamNode already uses — likely `clsx` or `cn` from `lib/utils.ts`).

    Class names:
    - `stream-node--code-hover` when `isCodeHovered` is true.
    - `stream-node--code-pinned` when `isCodePinned` is true.
    - Both can be present simultaneously (a sub-block-hovered + previously-pinned node) — CSS in Task 2 handles the coexistence (last-written class wins by CSS specificity; or both apply because outline only renders once — single outline property; whichever wins per CSS cascade is fine for the placeholder).

    Test (`StreamNode.codeHover.test.tsx`):
    - Render `<StreamNode ... id="n1" />` (with the minimum required props — survey `StreamNode.anchor.test.tsx` for the fixture shape).
    - Initially: no `stream-node--code-hover` class on the rendered DOM. `useStore.setState({ hoveredSourceIds: new Set(['n1']) })` (wrap in `act`). Assert `stream-node--code-hover` class present on the node element.
    - Reset: `setState({ hoveredSourceIds: new Set() })`. Assert class removed.
    - Same pair of tests for pinned: `pinnedSourceIds.has('n1')` → `stream-node--code-pinned` class present / absent.
    - Final test: both sets contain `n1` → both classes present.

    Re-render fanout (NOT a unit test, but verify mentally per Research Pattern 9): per-node primitive-boolean selectors mean toggling one ID only re-renders the affected nodes. Document this in a code comment near the subscription.
  </behavior>
  <action>
    Edit `gui/src/components/StreamNode.tsx`. Locate the line where `hasAnchor` is defined (~line 174 per research). Add the two new subscriptions immediately after. Locate the className composition (the JSX render path). Add the two conditional classes alongside the existing `hasAnchor` / `hasBCError` class applications.

    Use the SAME `useCallback` + dependency `[id]` shape as the existing subscriptions. Do NOT use a different memoization pattern (consistency matters for the codebase audit in Phase 71).

    Create `gui/src/components/__tests__/StreamNode.codeHover.test.tsx`. Use the testing-library setup from `StreamNode.anchor.test.tsx` (import same helpers; reuse the mock-store-seeding pattern). The 5 assertions above as separate `it(...)` blocks (initial absent, hover-applied, hover-removed, pin-applied, both-applied).

    If StreamNode uses memoization at the component level (`React.memo` wrapper), confirm the new subscriptions are reflected on re-render: the Zustand primitive-return pattern triggers a re-render via the store subscription, which then re-evaluates `React.memo`'s shallow-equal — should work, but verify with the test.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/components/__tests__/StreamNode.codeHover.test.tsx 2>&1 | tail -20 && npx tsc --noEmit 2>&1 | grep "error TS" | grep -v "pre-existing" | head -10</automated>
  </verify>
  <acceptance_criteria>
    - `StreamNode.tsx` contains `hoveredSourceIds.has(id)` AND `pinnedSourceIds.has(id)` in primitive-boolean selectors.
    - className composition includes `stream-node--code-hover` and `stream-node--code-pinned` conditional applications.
    - `StreamNode.codeHover.test.tsx` exists with 5 `it(...)` blocks; all pass.
    - Existing StreamNode tests (anchor, autoflip, base) still pass.
    - No new tsc errors.
  </acceptance_criteria>
  <done>StreamNode wired to new slices; class application test-locked.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Append placeholder CSS rules + Phase 72 handoff note</name>
  <files>gui/src/index.css, .planning/notes/phase-66-hover-ring-tuning.md</files>
  <read_first>
    - gui/src/index.css (current file — identify Phase 65-12's marquee CSS block as the precedent for where Phase 66 rules go; append after that block)
    - .planning/notes/correlation-geom-first-api.md (Phase 59's handoff doc — the model for Phase 66's handoff doc style: scope, what was deferred, where to look, how to verify after re-tuning)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 9: Hover-ring CSS class strategy" (the recommended CSS placeholder rules — `outline: 2px solid var(--stream-code-hover-ring-color, #38bdf8)`; copy verbatim as the initial placeholder)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-05 (hover ring is visually distinct from selection ring; final tuning is Phase 72)
  </read_first>
  <behavior>
    CSS rules (append to `gui/src/index.css`):

    ```css
    /* Phase 66 — code-panel hover/pin ring on canvas nodes. Phase 72 re-tunes visuals. */
    .stream-node--code-hover {
      outline: 2px solid var(--stream-code-hover-ring-color, #38bdf8);  /* sky-400 placeholder */
      outline-offset: 2px;
    }
    .stream-node--code-pinned {
      outline: 2px solid var(--stream-code-pinned-ring-color, #0ea5e9);  /* sky-500 — slightly heavier */
      outline-offset: 2px;
    }
    ```

    `outline` not `border` (Pattern 9 rationale: outline does NOT contribute to box dimensions, so Phase 64's autoflip handle-position math stays correct).
    `outline-offset: 2px` keeps the new ring visually offset from the React Flow selection ring (which is `box-shadow`-based by default).

    Handoff note (`.planning/notes/phase-66-hover-ring-tuning.md`):
    - 1 paragraph: what Phase 66 shipped (placeholder outline, sky-400/500 colors, fixed 2px stroke).
    - Bulleted list: what Phase 72 should re-tune. Each bullet says WHERE (file:line or CSS variable name) and WHAT to consider.
        - Color: `--stream-code-hover-ring-color` and `--stream-code-pinned-ring-color` CSS variables in `gui/src/index.css`. Should align with the v1.2 accent palette decided in Phase 72.
        - Stroke width / style: currently solid 2px. Dashed variants worth considering for the pinned-vs-hovered distinction.
        - Flash animation: currently a simple `data-flash="true"` attribute toggled for 1.5s in `CodePreview.tsx`. Phase 72 may want a CSS `@keyframes` fade-out instead of an abrupt class toggle.
        - Layer-aware un-dim (Phase 68): when Phase 68 lands the four-layer dim mechanism, the dim logic in `StreamNode.tsx` MUST check `hoveredSourceIds` / `pinnedSourceIds` to suppress dimming on hover/pin. Phase 66 does NOT change layer behavior; the un-dim is a Phase 68 concern. CONTEXT.md D-05 acknowledges this.
    - 1 short paragraph noting the verification path: "After Phase 72 re-tunes, the Plan 01 `CodePreview.textSelection.test.tsx` and the `StreamNode.codeHover.test.tsx` should still pass — those tests assert class-level behavior, not specific visual properties."
  </behavior>
  <action>
    Append the CSS rules to `gui/src/index.css`. Place them near the Phase 65-12 marquee CSS block for code locality.

    Write `.planning/notes/phase-66-hover-ring-tuning.md`. ~30-50 lines total. Follow the Phase 59 handoff doc style (`.planning/notes/correlation-geom-first-api.md`).

    DO NOT edit any source file. The CSS rules and the handoff doc are the only artifacts.
  </action>
  <verify>
    <automated>grep -c "stream-node--code-hover\|stream-node--code-pinned" gui/src/index.css && test -f .planning/notes/phase-66-hover-ring-tuning.md && wc -l .planning/notes/phase-66-hover-ring-tuning.md</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/index.css` contains both CSS rules (`.stream-node--code-hover`, `.stream-node--code-pinned`) with `outline` (not `border`) and `outline-offset: 2px`.
    - The two CSS custom properties (`--stream-code-hover-ring-color`, `--stream-code-pinned-ring-color`) appear in the rules.
    - `.planning/notes/phase-66-hover-ring-tuning.md` exists, has ≥30 lines, references Phase 72 explicitly, references Phase 68 layer-aware un-dim explicitly, and lists at least 4 tuning targets.
    - `cd gui && npx vitest --run` shows all Phase 66 tests still GREEN.
  </acceptance_criteria>
  <done>CSS placeholder lands; handoff doc commits Phase 72's scope.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Manual UAT — end-to-end Phase 66 acceptance</name>
  <what-built>
    Phase 66 is functionally complete after this checkpoint. The user runs the dev server and walks the full bidirectional traceability flow. This is the gate: if any step fails, Plan 06 (or a gap-closure plan) is needed before Phase 66 ships.
  </what-built>
  <how-to-verify>
    1. Start the dev server:
       ```bash
       cd /home/itay/projects/Julia-STREAM/gui && npm run dev
       ```
    2. Build a non-trivial loop graph: drop a Pump, a Channel, a Friction, an HX. Connect them in a loop. Add at least one resource (a Geometry). Confirm the Code panel populates.

    **Code → Canvas (hover):**
    3. Open bottom panel (toggle from top toolbar if closed).
    4. Hover the `@named pump1 = Pump(...)` sub-block in Components. Expect: the `pump1` node on canvas gets a sky-400 outline ring (placeholder color — Phase 72 re-tunes). Move mouse off — ring disappears.
    5. Hover a `connect(pump1.port_out, ch1.port_in)` sub-block in Composition. Expect: BOTH `pump1` and `ch1` nodes get the hover ring simultaneously.
    6. Hover the Imports sub-block. Expect: NO node on canvas gets a ring (Imports has `sourceIds: []`).

    **Code → Canvas (pin):**
    7. Click the `pump1` sub-block. Expect: it gets the heavier sky-500 pinned-ring. Move mouse away — ring stays.
    8. Click the `ch1` sub-block (a different one). Expect: BOTH `pump1` AND `ch1` have the pinned ring (additive, D-10).
    9. Click `pump1` sub-block again. Expect: `pump1`'s pinned ring disappears (toggle); `ch1` still pinned.
    10. Click empty space in the code panel (gutter / between sub-blocks). Expect: ALL pinned rings cleared.
    11. Pin some sub-blocks. Click into the canvas (not into any node — just background). Then press Esc with focus on canvas. Expect: pinned rings cleared.

    **Canvas → Code (explicit jump):**
    12. With panel CLOSED: right-click any node on canvas → "Show generated Julia code". Expect: (a) panel opens, (b) the corresponding `@named` sub-block in Components scrolls into view (center-ish), (c) a brief visual flash on the sub-block, (d) the node on canvas gets the pinned ring (per Plan 04 Task 1 D-09 decision).
    13. With panel OPEN but scrolled to top: right-click a Channel node (Components are usually further down). Expect: smooth-scroll to the matching sub-block, flash, pin.

    **Copy / Export:**
    14. Click Copy in the panel. Expect: button shows "Copied" + Check icon for ~1.5s, then reverts. Paste in a text editor — confirm full assembled script with `# === Imports ===`, `# === Components ===`, `# === Composition ===` (and Resources / Main if applicable) headers.
    15. Click Export in the panel. Confirm Tauri save dialog. Pick a path. Confirm file written with the D-12 headers.
    16. Close the panel via the toggle. Click top-Toolbar Export. Confirm it still works (D-18 — Export reachable when panel closed).

    **Text-selection (D-14):**
    17. Click-and-drag across two sub-block boundaries in the code panel. Expect: browser's native text-selection works, no `user-select: none` interference. Ctrl+C; paste into a text editor; confirm the selected range copies cleanly.

    **Disabled state (D-19):**
    18. Select all nodes; delete. With an empty canvas, confirm Copy and Export buttons in the panel are visibly disabled.

    **Layer-aware un-dim (D-05, Phase 68 forward-compat):**
    19. **Skip** — Phase 68 hasn't shipped yet. Phase 66 emits the hover-ring class regardless of layer state; the un-dim is Phase 68's responsibility. Acknowledge and move on.

    **Regression sweep:**
    20. Run `cd gui && npx vitest --run` once more from this terminal session. Confirm all GREEN (modulo the 1 pre-existing SidebarPanel.anchors failure and the 11 pre-existing tsc errors).
  </how-to-verify>
  <resume-signal>Type "approved" to mark Phase 66 ready for `/gsd:verify-work 66`. Type "regression: <describe>" to flag a gap → spawn a Plan 06 gap-closure planning step.</resume-signal>
</task>

</tasks>

<verification>
After Tasks 1 and 2:

```bash
cd /home/itay/projects/Julia-STREAM/gui
# StreamNode test + full suite GREEN
npx vitest --run src/components/__tests__/StreamNode.codeHover.test.tsx
npx vitest --run 2>&1 | tail -30   # full suite

# CSS rules present
grep -c "stream-node--code-hover" gui/src/index.css   # ≥1
grep -c "stream-node--code-pinned" gui/src/index.css  # ≥1

# Handoff doc present
test -f .planning/notes/phase-66-hover-ring-tuning.md && wc -l .planning/notes/phase-66-hover-ring-tuning.md

# TSC clean
npx tsc --noEmit 2>&1 | grep "error TS" | wc -l   # 11 (pre-existing)
```

Task 3 (manual UAT) is the acceptance gate. Pass = Phase 66 ready for `/gsd:verify-work`.
</verification>

<success_criteria>
- `StreamNode.tsx` wired to both new slices via primitive-boolean selectors.
- `StreamNode.codeHover.test.tsx` GREEN with 5 it-blocks.
- `gui/src/index.css` has placeholder hover/pinned ring rules using `outline` (not `border`) and CSS variables for Phase 72 tuning.
- `.planning/notes/phase-66-hover-ring-tuning.md` exists and documents the Phase 72 handoff.
- Manual UAT (Task 3) approved by user: end-to-end bidirectional traceability works.
- No new tsc errors / no new package dependencies.
</success_criteria>

<output>
Create `.planning/phases/66-code-preview-rework/66-05-SUMMARY.md` when done. Summary lists: StreamNode subscription line numbers (the per-node primitive selectors), CSS rule placement, UAT items pass/fail, any issues surfaced during UAT.

### Phase-level must_haves rollup (consolidated from all 5 plans)

This is the goal-backward verification list for `/gsd:verify-work 66`:

**Truths (observable behaviors):**
- `generateCode(...)` returns `CodeSection[]` (not `string`). Section names exactly `Imports` / `Resources` / `Components` / `Composition` / `Main`.
- Composition emits one sub-block per `connect(...)` line; topology helpers (`fuel_assembly`, `symmetric_plate`, `plate`, `one_sided_connection`) each one sub-block with all consumed source UUIDs.
- Resources emits one sub-block per Geometry, one per per-HD consumer-keyed power_shape, one per Fluid.
- Components emits one sub-block per `@named` declaration with `sourceIds: [node_uuid]`.
- Imports + Main each have a single sub-block with `sourceIds: []`.
- `serializeSections(CodeSection[]): string` exists; emits D-12 formatting floor (`# === <Section> ===` headers, one blank line between sub-blocks, one blank line between sections, no trailing whitespace).
- The five existing string-equality codegen test files pass after the documented one-line `serializeSections(...)` adapter wrap + D-12 header fixture updates.
- `CodePreview.tsx` renders sub-blocks as hover-targetable elements; hovering writes `hoveredSourceIds`; the matching canvas node visibly gets the `stream-node--code-hover` ring.
- Clicking a sub-block toggles pinning (additive multi-pin); clicking empty space in the code panel clears all pins; pressing `Esc` (with input-focus guard) clears all pins.
- `stream:show-code-for` CustomEvent (dispatched by `NodeContextMenu.tsx:40`): opens panel if closed, smooth-scrolls target sub-block into view, applies 1.5s flash, pins the source IDs.
- Copy + Export buttons at the right side of `BottomPanel.tsx`'s `<TabsList>`; both `disabled={nodes.length === 0}`; Copy shows "Copied" + Check icon for 1.5s after success; Export reuses `gui/src/lib/exportCode.ts` (also called from `Toolbar.tsx`).
- Native browser text-selection works across sub-block boundaries (no `user-select: none`, no `preventDefault` on mousedown).
- Rendering is plain `<pre><code>`-style text — no Monaco / Prism / highlight.js / shiki in `gui/package.json`.
- Three Zustand slices (`hoveredSourceIds`, `pinnedSourceIds`, `pendingShowCodeFor`) are NOT serialized to `.scp` (verified by inspecting `serializeProject` arg list in `projectIO.ts`).

**Artifacts:**
- `gui/src/lib/codeGenerator.ts` (returns `CodeSection[]`; exports `serializeSections`, `CodeSection`, `CodeSubBlock` types).
- `gui/src/lib/exportCode.ts` (new).
- `gui/src/hooks/useShowCodeFor.ts` (new).
- `gui/src/components/CodePreview.tsx` (full rewrite, section-by-section renderer).
- `gui/src/components/BottomPanel.tsx` (with Copy + Export buttons).
- `gui/src/components/StreamNode.tsx` (with hover/pin subscriptions).
- `gui/src/store/useStore.ts` (with three new ephemeral slices + six actions).
- `gui/src/App.tsx` (mounts `useShowCodeFor()` + global Esc handler).
- `gui/src/index.css` (placeholder hover/pinned ring rules).
- `.planning/notes/phase-66-hover-ring-tuning.md` (Phase 72 handoff doc).
- New vitest files (7 total): `codeGenerator.sections.test.ts`, `codeGenerator.serialize.test.ts`, `useStore.codePanel.test.ts`, `exportCode.test.ts`, `CodePreview.test.tsx`, `CodePreview.showCodeFor.test.tsx`, `CodePreview.textSelection.test.tsx`, `StreamNode.codeHover.test.tsx`. (Counted: 8.)

**Key links:**
- `CodePreview.tsx` → `useStore.setHoveredSourceIds / togglePinnedForSubBlock / clearPinnedSourceIds / consumePendingShowCodeFor` (event handlers + scroll/flash useEffect).
- `useShowCodeFor.ts` → `useStore.setPendingShowCodeFor` (CustomEvent handler).
- `App.tsx` → `useShowCodeFor()` + window keydown Esc → `clearPinnedSourceIds`.
- `BottomPanel.tsx` Export → `exportCode(...)`.
- `BottomPanel.tsx` Copy → `navigator.clipboard.writeText(serializeSections(...))`.
- `StreamNode.tsx` → `useStore.hoveredSourceIds.has(id)` AND `useStore.pinnedSourceIds.has(id)` → conditional className.
- `NodeContextMenu.tsx:40` (unchanged from Phase 65) → `window.dispatchEvent(new CustomEvent('stream:show-code-for', { detail: { nodeId } }))` → consumed by `useShowCodeFor`.
</output>
