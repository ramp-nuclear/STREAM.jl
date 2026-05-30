---
phase: 66-code-preview-rework
plan: 3
type: execute
wave: 2
depends_on: [66-02]
files_modified:
  - gui/src/store/useStore.ts
  - gui/src/hooks/useShowCodeFor.ts
  - gui/src/App.tsx
  - gui/src/lib/exportCode.ts
  - gui/src/components/Toolbar.tsx
  - gui/src/store/__tests__/useStore.codePanel.test.ts
  - gui/src/lib/__tests__/exportCode.test.ts
autonomous: true
requirements: []

must_haves:
  truths:
    - "`useStore` has three new ephemeral slices: `hoveredSourceIds: Set<string>`, `pinnedSourceIds: Set<string>`, `pendingShowCodeFor: string[] | null` — none are serialized to `.scp` (verified by inspecting `projectIO.ts:serializeProject` argument list)."
    - "Store actions exist and behave correctly: `setHoveredSourceIds(ids)`, `clearHoveredSourceIds()`, `togglePinnedForSubBlock(ids)` (additive with D-10 overlap-toggle semantics), `clearPinnedSourceIds()`, `setPendingShowCodeFor(ids)`, `consumePendingShowCodeFor()`."
    - "Every mutation produces a NEW `Set` reference (no in-place mutation — Pitfall 1)."
    - "`useShowCodeFor()` hook listens on `window` for `stream:show-code-for` (accepts `nodeId` xor `nodeIds`); on event, opens bottom panel if closed and writes `pendingShowCodeFor`."
    - "App.tsx mounts `useShowCodeFor()` once at root AND registers a window-level Esc handler with input-focus guard that calls `clearPinnedSourceIds()`."
    - "`gui/src/lib/exportCode.ts` exists; encapsulates validation gate + Tauri `save` dialog + `writeTextFile`; returns `Promise<boolean>` (true = wrote file, false = cancelled or validation-blocked)."
    - "`Toolbar.tsx` calls `exportCode(...)` instead of inline `handleExport`; behavior is unchanged from user's perspective."
  artifacts:
    - path: "gui/src/store/useStore.ts"
      provides: "hoveredSourceIds, pinnedSourceIds, pendingShowCodeFor slices + setters"
    - path: "gui/src/hooks/useShowCodeFor.ts"
      provides: "CustomEvent listener that bridges canvas → code panel"
    - path: "gui/src/lib/exportCode.ts"
      provides: "shared Tauri save dialog flow + validation gate; called by Toolbar.tsx (this plan) and BottomPanel.tsx (Plan 04)"
  key_links:
    - from: "useShowCodeFor.ts"
      to: "useStore.pendingShowCodeFor"
      via: "useStore.getState().setPendingShowCodeFor"
      pattern: "setPendingShowCodeFor"
    - from: "Toolbar.tsx"
      to: "exportCode.ts"
      via: "named import"
      pattern: "import.*exportCode.*from"
    - from: "App.tsx"
      to: "useShowCodeFor"
      via: "hook call at app root"
      pattern: "useShowCodeFor\\("
---

<objective>
Land the ephemeral Zustand state, the `stream:show-code-for` listener hook, the global Esc-clears-pins handler, and the extracted `exportCode.ts` shared util. Pure data + util work — no new UI rendering. Plan 04 wires these into `CodePreview.tsx` and `BottomPanel.tsx`.

Purpose: separate the data layer from the UI so the Plan 04 executor can focus on render/click code without simultaneously learning a new store API and a new Tauri util.
Output: new store slices + setters, new hook, new shared util; `Toolbar.tsx` migrated to call `exportCode(...)`; tests for the store mutation discipline and the export util.
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
@.planning/phases/66-code-preview-rework/66-02-SUMMARY.md
@gui/src/store/useStore.ts
@gui/src/components/Toolbar.tsx
@gui/src/components/App.tsx
@gui/src/lib/projectIO.ts
@gui/src/components/CanvasPanel.tsx
</context>

<interfaces>
<!-- New exports added by this plan. Plan 04 consumes these. -->

```typescript
// gui/src/store/useStore.ts (new slices + actions)
hoveredSourceIds: Set<string>;
pinnedSourceIds: Set<string>;
pendingShowCodeFor: string[] | null;

setHoveredSourceIds: (ids: string[]) => void;
clearHoveredSourceIds: () => void;
togglePinnedForSubBlock: (subBlockSourceIds: string[]) => void;
clearPinnedSourceIds: () => void;
setPendingShowCodeFor: (ids: string[]) => void;
consumePendingShowCodeFor: () => string[] | null;  // returns + clears
```

```typescript
// gui/src/hooks/useShowCodeFor.ts (new file)
export function useShowCodeFor(): void;
```

```typescript
// gui/src/lib/exportCode.ts (new file)
export async function exportCode(opts: {
  sections: CodeSection[];  // from codeGenerator
  nodes: Node[];            // for validation gate (nodes.length === 0 → false)
  // any other args Toolbar.tsx currently passes to its inline handleExport
}): Promise<boolean>;
```

D-08: `stream:show-code-for` payload shape accepted by `useShowCodeFor`:
```typescript
interface ShowCodeForDetail { nodeId?: string; nodeIds?: string[]; }
```
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add Zustand slices + actions to useStore.ts (with new dedicated test file)</name>
  <files>gui/src/store/useStore.ts, gui/src/store/__tests__/useStore.codePanel.test.ts</files>
  <read_first>
    - gui/src/store/useStore.ts lines 175-300 and 800-1020 (existing ephemeral slice precedents: `bottomPanelOpen`, `interactiveLocked`, `errorNodeIds: Set<string>`, `validationResult`). Note the action-naming conventions, the immutable-spread style (`set((s) => ({...}))`), and how `subscribeWithSelector` is wired at line 2.
    - gui/src/lib/projectIO.ts lines 123-148 (confirm `serializeProject` takes specific named args; new store fields auto-excluded from `.scp`).
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 4: Zustand ephemeral slice shape" (the exact recommended action shapes — especially the D-10 toggle semantics with overlap detection; copy verbatim).
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-09, D-10, D-11.
  </read_first>
  <behavior>
    Store mutation discipline (must-have):
    - `setHoveredSourceIds(ids)` → `set({ hoveredSourceIds: new Set(ids) })`. Always a fresh Set.
    - `clearHoveredSourceIds()` → `set({ hoveredSourceIds: new Set() })`.
    - `togglePinnedForSubBlock(subBlockIds)` per D-10: build `next = new Set(s.pinnedSourceIds)`; if ANY id in `subBlockIds` is already in `next`, remove ALL `subBlockIds` from `next`; else add ALL `subBlockIds`. `set({ pinnedSourceIds: next })`. Fresh Set reference every call.
    - `clearPinnedSourceIds()` → `set({ pinnedSourceIds: new Set() })`.
    - `setPendingShowCodeFor(ids)` → `set({ pendingShowCodeFor: [...ids] })`. Fresh array.
    - `consumePendingShowCodeFor()` → reads `s.pendingShowCodeFor`, returns it (or null), then `set({ pendingShowCodeFor: null })`. **Atomic** — implement via `set((s) => { ... })` reading inside the setter, or via `getState()` + `setState()` sequence. Both acceptable.

    Test file `useStore.codePanel.test.ts` asserts:
    - Initial state: all three slices have empty / null values.
    - Each setter produces a NEW Set reference (assert with `expect(after).not.toBe(before)`).
    - `togglePinnedForSubBlock(['a','b'])` then `togglePinnedForSubBlock(['a','b'])` → pin set is empty.
    - `togglePinnedForSubBlock(['a','b'])` then `togglePinnedForSubBlock(['c','d'])` → pin set has all four (additive D-10).
    - `togglePinnedForSubBlock(['a','b'])` then `togglePinnedForSubBlock(['b','c'])` → 'b' overlap removes ALL of `['b','c']`, leaving `{a}` (overlap-removes-all semantics per D-10).
    - `setPendingShowCodeFor([...])` then `consumePendingShowCodeFor()` returns the array and clears the slice to `null`. Second call returns `null`.
    - `.scp` exclusion: import `serializeProject` from `projectIO.ts`; call it with seeded store containing non-empty hover/pin/pending sets; assert the returned object has NO keys named `hoveredSourceIds`, `pinnedSourceIds`, or `pendingShowCodeFor`.
  </behavior>
  <action>
    Edit `useStore.ts`. Add the three slices alongside `errorNodeIds: Set<string>` (use grep to find the existing slice; place new slices nearby for code locality). Add the six actions alongside `setErrorNodeIds` / `clearErrorNodeIds` patterns already in the store. Use the exact action shapes from Research Pattern 4. Do NOT use immer; the existing store uses plain spread / fresh-Set patterns.

    Create `gui/src/store/__tests__/useStore.codePanel.test.ts`. Use the existing test patterns from `useStore.*.test.ts` if any exist (check `ls gui/src/store/__tests__/`); if none, follow the patterns in `gui/src/lib/__tests__/projectIO.scp.test.ts` which exercises the store. Reset store with `useStore.setState({...initialDefaults})` in `beforeEach`.

    For the `.scp` exclusion assertion: build a minimal serialize call mimicking what `projectIO.ts` does in production. Read `serializeProject`'s signature first; pass the new slices in only if they're in the signature (they should NOT be).
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/store/__tests__/useStore.codePanel.test.ts 2>&1 | tail -20</automated>
  </verify>
  <acceptance_criteria>
    - `useStore.ts` exports the three slices and six actions; all actions produce fresh Set / array references.
    - `useStore.codePanel.test.ts` exists and ALL `it(...)` blocks pass.
    - At least one test covers each: initial state, fresh-Set discipline, additive multi-pin, overlap-removes-all toggle (D-10), `consumePendingShowCodeFor` atomicity, `.scp` exclusion via `serializeProject`.
    - `grep -E "hoveredSourceIds|pinnedSourceIds|pendingShowCodeFor" gui/src/lib/projectIO.ts` returns 0 matches (the slices are NOT mentioned in projectIO).
  </acceptance_criteria>
  <done>Three slices + six actions land; mutation discipline test-locked; `.scp` exclusion verified.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Create useShowCodeFor hook + mount in App.tsx + global Esc-clears-pins handler</name>
  <files>gui/src/hooks/useShowCodeFor.ts, gui/src/App.tsx</files>
  <read_first>
    - gui/src/hooks/useBottomPanelResize.ts (existing hook in the same directory — follow its module shape: default export NOT used; named export; useEffect lifecycle)
    - gui/src/store/useStore.ts:178 (`bottomPanelOpen: boolean` slice declaration), :1779 (`toggleBottomPanel: () => set({ bottomPanelOpen: !get().bottomPanelOpen })` — the verified setter to call when opening from this hook; no `setBottomPanelOpen` setter exists, only the toggle)
    - gui/src/components/canvasMenus/NodeContextMenu.tsx:36-37 (existing open-if-closed call shape — copy verbatim: `if (useStore.getState().bottomPanelOpen === false) useStore.getState().toggleBottomPanel();`)
    - gui/src/App.tsx (find the existing root `AppShell` or equivalent — Phase 65 added various hooks here; identify the right mount point)
    - gui/src/components/CanvasPanel.tsx lines 260-294 (existing Esc handler with input-focus guard — copy the guard predicate verbatim; do NOT recreate the predicate from memory)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 5: CustomEvent listener lifecycle", §"Pattern 6: Esc key coordination with Phase 65"
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-06, D-07, D-08, D-09, D-10
  </read_first>
  <behavior>
    `useShowCodeFor()` behavior:
    - Mounts once at app root. Registers a window `addEventListener('stream:show-code-for', handler)`.
    - Handler: cast to `CustomEvent<ShowCodeForDetail>`; read `detail.nodeIds ?? (detail.nodeId ? [detail.nodeId] : [])`; if empty, return.
    - If `useStore.getState().bottomPanelOpen === false`, call `useStore.getState().toggleBottomPanel()` to open it. Verified setter: `toggleBottomPanel: () => set({ bottomPanelOpen: !get().bottomPanelOpen })` at `gui/src/store/useStore.ts:1779`. This mirrors the existing pattern in `gui/src/components/canvasMenus/NodeContextMenu.tsx:36-37` (`if (useStore.getState().bottomPanelOpen === false) useStore.getState().toggleBottomPanel();`). Do NOT introduce a `setBottomPanelOpen` setter — there isn't one and the toggle is the established convention.
    - Call `useStore.getState().setPendingShowCodeFor(ids)`. Plan 04 wires the consumer that scrolls + flashes.
    - Cleanup: `removeEventListener` with the SAME function reference. Cast to `EventListener` per Research Pattern 5 to avoid the TS type mismatch that breaks cleanup.
    - Optional: also add `declare global { interface WindowEventMap { 'stream:show-code-for': CustomEvent<ShowCodeForDetail>; } }` at the top of the file (Research Pattern 5 recommends; check `grep -rn "WindowEventMap" gui/src/` first — if Phase 65 already declared the event, do not duplicate).

    Esc handler (lives in App.tsx, registered via `useEffect`):
    - `window.addEventListener('keydown', handler)`.
    - Handler: if `e.key !== 'Escape'`, return. Apply the SAME input-focus guard predicate as `CanvasPanel.tsx:275-289` (HTMLInputElement / HTMLTextAreaElement / HTMLSelectElement / isContentEditable). If guard passes, call `useStore.getState().clearPinnedSourceIds()`.
    - Cleanup on unmount.
    - Coexists with the existing CanvasPanel Esc handler — neither calls `stopPropagation`; both fire on the same Esc; both are idempotent. Verified by Research Pattern 6.
  </behavior>
  <action>
    Create `gui/src/hooks/useShowCodeFor.ts`. Implement per Research Pattern 5. Export named `useShowCodeFor`.

    Edit `gui/src/App.tsx`. Identify the root component (likely `AppShell` or `App`). Add:
    ```tsx
    useShowCodeFor();
    ```
    near the top of the component body. Add the Esc `useEffect` block from Research Pattern 6 (verbatim — including the input-focus guard) immediately after.

    Use named imports: `import { useShowCodeFor } from "./hooks/useShowCodeFor";` (path may need adjustment based on App.tsx's location — `gui/src/App.tsx` → `./hooks/useShowCodeFor` works; verify).

    DO NOT modify `useStore.ts` in this task (Task 1 handled it). DO NOT modify `CodePreview.tsx` (Plan 04). DO NOT add a Phase 66 test for `useShowCodeFor` here — Plan 01's `CodePreview.showCodeFor.test.tsx` is the integration test for the full panel-open-scroll-flash flow, which depends on Plan 04's UI work.

    Sanity test: a tiny unit test for the hook in isolation is nice-to-have. Defer to Plan 04's integration coverage rather than adding here.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run 2>&1 | tail -15 && cd /home/itay/projects/Julia-STREAM/gui && npx tsc --noEmit 2>&1 | grep "error TS" | grep -v "pre-existing" | head -20</automated>
  </verify>
  <acceptance_criteria>
    - File `gui/src/hooks/useShowCodeFor.ts` exists; default exports nothing; named exports `useShowCodeFor`.
    - `gui/src/App.tsx` calls `useShowCodeFor()` exactly once.
    - `gui/src/App.tsx` registers a window `keydown` listener that calls `clearPinnedSourceIds()` on Esc with input-focus guard.
    - `grep "stopPropagation" gui/src/hooks/useShowCodeFor.ts gui/src/App.tsx` returns 0 (no event propagation interference).
    - `cd gui && npx tsc --noEmit` shows no new errors beyond pre-existing 11.
    - AppShell.test.tsx still passes (the Esc handler is global on window and shouldn't break existing component tests).
  </acceptance_criteria>
  <done>Hook + Esc handler mounted; CustomEvent bridge to store live; no new tsc / test breaks.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Extract exportCode.ts shared util + migrate Toolbar.tsx to call it</name>
  <files>gui/src/lib/exportCode.ts, gui/src/components/Toolbar.tsx, gui/src/lib/__tests__/exportCode.test.ts</files>
  <read_first>
    - gui/src/components/Toolbar.tsx lines 49-60 (current `handleExport` — full implementation: validation gate, `save` dialog call, `writeTextFile` call, error handling)
    - gui/src/lib/projectIO.ts (for the Tauri save dialog import patterns and the existing error-handling shape; the export util will mirror this style)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 11: exportCode.ts shared util shape"
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-17, D-18, D-19
  </read_first>
  <behavior>
    `exportCode(opts): Promise<boolean>` behavior:
    - Reads `opts.sections` and `opts.nodes` (and whatever else Toolbar's current `handleExport` consumes — read the actual function to enumerate).
    - Validation gate: if `opts.nodes.length === 0`, return `false` (do NOT call `save`). (The button-disabled-state will prevent this in normal use, but the gate stays as a safety per D-19.)
    - Any additional validation Toolbar currently runs (e.g., a `validateGraph(...)` call — check the current `handleExport` body): preserve verbatim. If validation fails, return `false`.
    - Call `save({ defaultPath: '...', filters: [...] })` with the same args Toolbar currently uses. If user cancels (`save` returns `null`), return `false`.
    - Call `serializeSections(opts.sections)` to assemble the string; call `writeTextFile(path, string)`. If write throws, propagate the error (do not swallow — the caller's `.catch` handles it, same as today).
    - Return `true` on successful write.

    `Toolbar.tsx` migration:
    - Replace inline `handleExport` body with a call to `exportCode({ sections, nodes, ... })`. The `sections` come from a freshly-computed `generateCode(...)` call inside `Toolbar.tsx` (matches the current pattern of computing the code inline at export-time).
    - Drop the in-Toolbar `serializeSections` wrap from Plan 02's Task 3 — `exportCode.ts` now owns serialization.
    - Top-Toolbar Export button stays per D-18; `disabled={nodes.length === 0}` predicate stays.

    Test file `exportCode.test.ts`:
    - Mock `@tauri-apps/plugin-dialog` `save` and `@tauri-apps/plugin-fs` `writeTextFile`.
    - Case 1 — validation gate: call with `nodes: []`, assert returns `false` and `save` NOT called.
    - Case 2 — user cancel: mock `save` to return `null`, assert returns `false`, `writeTextFile` NOT called.
    - Case 3 — happy path: mock `save` to return `'/tmp/out.jl'`, `writeTextFile` to resolve, assert returns `true`, `writeTextFile` called with `(['/tmp/out.jl', expect.stringContaining('# === Imports ===')])`.
    - Case 4 — write throws: mock `writeTextFile` to reject; assert `exportCode` rejects (does not silently swallow).
  </behavior>
  <action>
    Create `gui/src/lib/exportCode.ts`. Import `save` from `@tauri-apps/plugin-dialog`, `writeTextFile` from `@tauri-apps/plugin-fs`, `serializeSections` and `CodeSection` from `./codeGenerator`. Implement per the behavior block.

    Read `gui/src/components/Toolbar.tsx:49-60` first to capture the EXACT current behavior of `handleExport` (filter list, default path computation, error toast / console.error pattern). The util MUST reproduce these — this is a refactor, not a behavior change.

    Edit `Toolbar.tsx`: replace `handleExport`'s body with the `exportCode(...)` call; keep the `disabled={nodes.length === 0}` predicate on the button (currently at line ~125). The button stays.

    Create `gui/src/lib/__tests__/exportCode.test.ts`. Use `vi.mock('@tauri-apps/plugin-dialog', ...)` and `vi.mock('@tauri-apps/plugin-fs', ...)` to mock the Tauri plugins. The 4 cases above.

    DO NOT introduce new behavior. If Toolbar currently does NOT have a validation gate (verify by reading), then `exportCode.ts` shouldn't add one — keep behavior equivalent. The `nodes.length === 0` early return IS already implicitly handled by the disabled button at the UI level (D-19), but the util should still bail safely if called with empty nodes (defensive programming, matches Research Pattern 11).
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/lib/__tests__/exportCode.test.ts 2>&1 | tail -20 && npx tsc --noEmit 2>&1 | grep "error TS" | grep -v "pre-existing" | head -10</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/lib/exportCode.ts` exists; exports `exportCode(opts): Promise<boolean>`.
    - `gui/src/components/Toolbar.tsx` imports `exportCode` and calls it from the (former-)`handleExport`.
    - `exportCode.test.ts` has 4 `it(...)` blocks (validation, cancel, happy, write-throws); all pass.
    - `grep "writeTextFile\|@tauri-apps/plugin-fs" gui/src/components/Toolbar.tsx` returns 0 matches AFTER this task — the Tauri-write logic moved out of Toolbar.tsx.
    - No new tsc errors.
    - Existing AppShell / Toolbar component tests still pass.
  </acceptance_criteria>
  <done>exportCode util lands; Toolbar migrated; util tested; Plan 04 can reuse the same util.</done>
</task>

</tasks>

<verification>
After all three tasks:

```bash
cd /home/itay/projects/Julia-STREAM/gui
# Store + export util tests GREEN
npx vitest --run src/store/__tests__/useStore.codePanel.test.ts src/lib/__tests__/exportCode.test.ts

# Full suite — Plan 01's CodePreview UI tests still RED (Plan 04 fixes); everything else GREEN
npx vitest --run 2>&1 | tail -30

# TSC clean (no new errors)
npx tsc --noEmit 2>&1 | grep "error TS" | wc -l
```

Manual sanity:
```bash
cd /home/itay/projects/Julia-STREAM/gui && npm run dev
# In running app: right-click a canvas node → "Show generated Julia code". Phase 66 listener should fire silently
# (it writes pendingShowCodeFor to the store; nothing visible until Plan 04 wires the consumer).
# Confirm the bottom panel OPENS if it was closed (this is Phase 65's existing behavior; Phase 66's listener only adds the pending-id write).
# Confirm top-toolbar Export still writes a .jl file with `# === ... ===` headers.
```
</verification>

<success_criteria>
- 3 new files: `useShowCodeFor.ts`, `exportCode.ts`, `useStore.codePanel.test.ts` (and `exportCode.test.ts`).
- 3 modified files: `useStore.ts` (new slices), `App.tsx` (hook + Esc), `Toolbar.tsx` (export util migration).
- All new tests GREEN.
- No new tsc errors beyond pre-existing 11.
- `.scp` exclusion verified (new slices NOT in `serializeProject` output).
- Plan 01's CodePreview UI tests are STILL RED (intentional — Plan 04 closes them).
</success_criteria>

<output>
Create `.planning/phases/66-code-preview-rework/66-03-SUMMARY.md` when done. Summary lists: each new slice + its initial state, the toggle-semantics test case count, confirmation of `.scp` exclusion, the 4 exportCode test cases, and confirmation that `Toolbar.tsx` no longer references `writeTextFile` directly.
</output>
