---
phase: 65-interaction-model-overhaul
plan: 10
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/components/sidebar/SidebarPanel.tsx
  - gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx
autonomous: true
requirements: []
gap_closure: true
tags: [selection, esc-handler, sidebar, gap-closure, phase-65]

must_haves:
  truths:
    - "Pressing Esc while a sidebar text input is focused does NOT clear the zustand selection slice — the Properties panel keeps showing the current selection."
    - "The canvas ReactFlow `nodes[].selected` flag and the zustand `selectionKind`/`selectedNodeId` stay in lockstep when Esc fires inside an input."
    - "Pressing Esc with no input focused still clears selection (existing Plan 03 CanvasPanel handler is the only canonical handler for that path)."
  artifacts:
    - path: "gui/src/components/sidebar/SidebarPanel.tsx"
      provides: "Document-level Esc keydown handler with input-focus guard (matches CanvasPanel.tsx:266-275 reference implementation)."
      contains: "isContentEditable"
    - path: "gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx"
      provides: "Vitest cases proving Esc-with-input-focused does not call clearSelection; Esc-with-no-input-focused (or pane-focused) does not regress."
  key_links:
    - from: "SidebarPanel Esc keydown handler"
      to: "useStore.clearSelection()"
      via: "early-return guard on HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable"
      pattern: "isContentEditable"
---

<objective>
Close UAT Test 7 desync (major). Esc inside a focused sidebar text input currently clears the
zustand selection slice (Properties panel goes blank) but does NOT clear ReactFlow's per-node
`selected` flag — so the canvas keeps the selection outline while Properties claims no selection.
The two state sources drift.

Root cause (`.planning/debug/esc-selection-desync.md`): SidebarPanel.tsx:80-95 has a
document-level Esc keydown listener that unconditionally calls `clearSelection()` with NO
target/activeElement check. CanvasPanel.tsx:266-275 (Plan 03) is the correct reference
implementation — it checks `HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement |
isContentEditable` and returns early when an input is focused.

Fix: add the same input-focus guard to SidebarPanel.tsx:80-95. After the fix, when Esc fires
inside a sidebar input it is a no-op (text input default browser behavior); when Esc fires
with no input focused, the CanvasPanel handler clears both state sources together.

Purpose: restore the documented invariant from `.planning/notes/gui-redesign-design-decisions.md`
that Esc-in-text-input does not affect selection.

Output: SidebarPanel.tsx patched with input-focus guard; vitest proving the new behavior.

Source: `.planning/debug/esc-selection-desync.md` (root cause confirmed; preferred fix listed).
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/65-interaction-model-overhaul/65-03-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/esc-selection-desync.md
@gui/src/components/sidebar/SidebarPanel.tsx
@gui/src/components/CanvasPanel.tsx

<interfaces>
<!-- Existing reference implementation in CanvasPanel.tsx (lines 266-280, Plan 65-03) -->
The guard pattern to mirror:

    if (e.key === "Escape") {
      const target = e.target as HTMLElement;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        target.isContentEditable
      ) {
        return;
      }
      // ... clear selection ...
    }

<!-- Current SidebarPanel.tsx handler (lines 80-95) — must gain the same guard -->
Current shape (input-blind):

    const handler = (e: KeyboardEvent) => {
      if (e.defaultPrevented) return;
      if (e.key !== "Escape") return;
      if (useStore.getState().selectionKind !== "none") {
        useStore.getState().clearSelection();
      }
    };

<!-- useStore.clearSelection() — only mutates zustand selection slice -->
clearSelection: () =>
  set({
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
  });
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add input-focus guard to SidebarPanel Esc handler</name>
  <files>
    gui/src/components/sidebar/SidebarPanel.tsx
    gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx
  </files>
  <behavior>
    - Test: Render SidebarPanel inside a test harness with a node selected (selectionKind="node",
      selectedNodeId="x"). Render a sidebar `&lt;input&gt;` element (already exists in real component,
      e.g. InstanceNameField). Focus the input. Dispatch a `keydown` Escape on document.
      Assert: `useStore.getState().selectionKind` is still `"node"` and `selectedNodeId` is
      still `"x"` — selection NOT cleared.
    - Test: With NO input focused (focus on document.body or a non-input element). Dispatch
      a `keydown` Escape on document. Assert: `useStore.getState().selectionKind === "none"`.
    - Test (edge): a `&lt;textarea&gt;`-focused Escape is also a no-op. (One assertion suffices.)
    - Test (edge): a `contentEditable` div Escape is also a no-op.
  </behavior>
  <action>
    **TDD RED → GREEN.**

    Step 1 (RED). Create `gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx`.
    Use the same testing-library + vitest stack as existing sidebar tests
    (see `gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx` for the
    setup pattern, store seeding, and `@testing-library/react` imports). The test file
    should:

      - `beforeEach`: reset the zustand store with `useStore.setState({ ... })` to a
        known state where a node is selected (selectionKind="node", selectedNodeId="x").
        Make sure `nodes` contains the seed node so SidebarPanel doesn't crash on a
        nonexistent selection.
      - Render SidebarPanel inside a minimal harness (just `&lt;SidebarPanel /&gt;` —
        no ReactFlow needed for the Esc handler tests because the handler is document-level).
      - Helper `dispatchEsc(target: Element | null)`: dispatch a real `KeyboardEvent`
        on `document`, with `target` set via `Object.defineProperty(event, 'target', {value: target})`
        or by `target.focus()` first then `document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`.
        Prefer the focus-then-dispatch approach since `e.target` is the focused element.
      - Test case 1: focus an `&lt;input&gt;` (use `getByRole("textbox")` or `screen.getByLabelText`
        — pick whatever real input the sidebar renders for an instance name). Dispatch Esc.
        Assert `useStore.getState().selectionKind === "node"`.
      - Test case 2: blur all inputs (`(document.activeElement as HTMLElement)?.blur()`).
        Dispatch Esc on document. Assert `useStore.getState().selectionKind === "none"`.
      - Test case 3: render a `&lt;textarea&gt;` (you may need to render a sidebar context that
        exposes one, or render a dummy textarea inside the harness and pass it as the target).
        If sidebar doesn't render textareas natively, you can mount the harness with an
        extra `&lt;textarea data-testid="dummy-ta" /&gt;` inside it — the test is about the document
        handler, not about which input came from sidebar. Focus → dispatch Esc → assert
        selectionKind unchanged.
      - Test case 4: same as 3 but with a `&lt;div contentEditable&gt;` — render in the harness.

      All 4 tests must FAIL initially (current handler has no guard).

      Commit:
      ```
      git add gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx
      git commit -m "test(65-10): RED — Esc inside input must not clear selection

      Failing vitest cases proving SidebarPanel's document-level Esc handler
      currently clears selection regardless of focus target, desyncing the
      zustand selection slice from ReactFlow's per-node \`selected\` flag
      (UAT Test 7).

      Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
      ```

    Step 2 (GREEN). Edit `gui/src/components/sidebar/SidebarPanel.tsx` lines 80-95.
    Inside the `handler` function, BEFORE the `if (useStore.getState().selectionKind !== "none")`
    check, insert the input-focus guard mirroring CanvasPanel.tsx:266-275:

      const target = e.target as HTMLElement | null;
      if (
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target instanceof HTMLSelectElement ||
        (target !== null &amp;&amp; target.isContentEditable)
      ) {
        return;
      }

    Place this AFTER the `e.defaultPrevented` and `e.key !== "Escape"` early returns and
    BEFORE the `getState().selectionKind` check. Update the surrounding inline comment
    (currently around L75-79) to:

      // Esc cascade tail (UI-SPEC §"Esc precedence cascade" item 4 only).
      // Items 1-3 (popover-close, rename-cancel, context-menu-close) are owned
      // by their respective layers and stop propagation before reaching this
      // listener — see file header for details.
      // Phase 65 Plan 10: input-focus guard mirrors CanvasPanel.tsx:266-275 — Esc
      // inside a text input is a no-op so zustand selection and ReactFlow per-node
      // selected flag stay in lockstep (UAT Test 7 desync fix).

    Do NOT remove the `e.defaultPrevented` guard or any other existing logic.

    Run vitest and confirm all 4 new cases pass + no existing sidebar tests regress:
      cd gui &amp;&amp; npx vitest run src/components/sidebar

    Commit:
    ```
    git add gui/src/components/sidebar/SidebarPanel.tsx
    git commit -m "fix(65-10): input-focus guard on SidebarPanel Esc handler

    Mirror the CanvasPanel.tsx:266-275 guard so Esc inside a text input is
    a no-op. Closes the zustand-vs-ReactFlow selection desync (UAT Test 7).

    Source: .planning/debug/esc-selection-desync.md

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # New test file exists
      test -f gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx
      # SidebarPanel now contains the guard idioms
      grep -q "HTMLInputElement" gui/src/components/sidebar/SidebarPanel.tsx
      grep -q "HTMLTextAreaElement" gui/src/components/sidebar/SidebarPanel.tsx
      grep -q "isContentEditable" gui/src/components/sidebar/SidebarPanel.tsx
      # New tests + existing sidebar tests pass
      cd gui &amp;&amp; npx vitest run src/components/sidebar
    </automated>
  </verify>
  <done>
    Four new Esc-handler vitest cases pass; SidebarPanel Esc handler short-circuits on
    input/textarea/select/contentEditable targets; no existing sidebar test regresses;
    two commits recorded (RED then GREEN).
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

(none — pure UI state guard; no IPC, no fs, no untrusted input)

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-10a | Denial of Service | SidebarPanel Esc handler | accept | Worst case: a malformed `e.target` (not a real Element) causes a TypeError in the `instanceof` chain. `e.target` is browser-provided and guaranteed to be an EventTarget or null; falling back to `null` check on `isContentEditable` handles the null case. No DoS surface. |
</threat_model>

<verification>
- `grep -q "HTMLInputElement" gui/src/components/sidebar/SidebarPanel.tsx` — guard present.
- `cd gui &amp;&amp; npx vitest run src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx` — all 4 cases pass.
- `cd gui &amp;&amp; npx vitest run src/components/sidebar` — no regression in sibling sidebar tests.
- Optional manual: launch Tauri dev, select a node, click into the InstanceNameField, press Esc. Properties panel still shows the selection; canvas outline unchanged. (Not required for plan completion — vitest is dispositive.)
</verification>

<success_criteria>
- Esc inside a focused sidebar `&lt;input&gt;` is a no-op: zustand `selectionKind` and `selectedNodeId` unchanged.
- Esc on document with no input focused still calls `clearSelection()` (existing behavior preserved).
- 4 new vitest cases pass; no existing sidebar test regresses.
- Two atomic commits recorded (RED + GREEN), each with `(65-10):` prefix.
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-10-SUMMARY.md` when done.
</output>
