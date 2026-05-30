---
phase: 65-interaction-model-overhaul
plan: 14
type: execute
wave: 2
depends_on: [65-13]
files_modified:
  - gui/src/store/useStore.ts
  - gui/src/App.tsx
  - gui/src/store/__tests__/subscribeWithSelector.test.ts
autonomous: true
requirements: []
gap_closure: true
tags: [perf, zustand, subscribe-with-selector, autorecover, title-sync, gap-closure, phase-65]

must_haves:
  truths:
    - "During node drag (per-pixel mousemove ticks), the App.tsx title-sync subscribe does NOT call `getCurrentWindow().setTitle()` unless `currentFilePath` OR `isDirty` changed between ticks."
    - "During node drag, the autoRecover subscribe in useStore.ts:2691 schedules the debounced writer only on the rising edge of `isDirty` (false → true), NOT on every dirty=true mousemove tick."
    - "useStore is created with the `subscribeWithSelector` middleware so future `useStore.subscribe(selector, listener)` overloads work; existing `useStore.subscribe(listener)` callers continue to fire on every set (backward compatible)."
    - "Node drag, right-click pan, and selection behavior are unchanged functionally — this plan is purely a per-pixel overhead reduction. Test 4 perf complaint may persist due to the environmental WebKitGTK/WSLg floor (`.planning/debug/gui-drag-perf.md`) — that retest is deferred to the user, NOT part of acceptance criteria for this plan."
  artifacts:
    - path: "gui/src/store/useStore.ts"
      provides: "`create&lt;AppState&gt;()(subscribeWithSelector((set, get) =&gt; ({ ... })))` middleware composition at line 781. autoRecover subscribe (line ~2691) uses selector + listener overload to fire only on `isDirty` transitions."
      contains: "subscribeWithSelector"
    - path: "gui/src/App.tsx"
      provides: "Title-sync subscribe (line ~288) uses the `subscribeWithSelector` overload: `useStore.subscribe(s =&gt; ({ filePath: s.currentFilePath, dirty: s.isDirty }), ({filePath, dirty}) =&gt; syncTitle(filePath, dirty), { equalityFn: shallow })`. The listener fires only when those two fields change."
      contains: "subscribeWithSelector"
  key_links:
    - from: "App.tsx title-sync subscribe"
      to: "Tauri setTitle IPC"
      via: "selector-gated subscription (fires only on currentFilePath / isDirty change)"
      pattern: "subscribeWithSelector"
    - from: "useStore.ts autoRecover subscribe (line ~2691)"
      to: "writer.schedule / writer.cancel"
      via: "selector on isDirty firing only on transition (not on every dirty=true tick)"
      pattern: "writer.schedule"
---

<objective>
Close UAT Test 4 minor perf gap (#7) on its TRIVIAL dimension only. Per the planning brief
constraint: "plan the TRIVIAL fixes only; DEFER the medium-difficulty fixes (autoflip
memoization, isDirty-at-drag-stop) to a future perf phase; DEFER the environmental retest
to user."

Root cause split (`.planning/debug/gui-drag-perf.md`):
  (1) PRIMARY env floor: WSL2 + WebKitGTK compositing path. Not actionable in-app.
  (2) Application amplifiers: every store `set()` wakes every subscribe callback because
      zustand is created without `subscribeWithSelector` middleware. App.tsx:288 unconditionally
      calls Tauri's `setTitle()` IPC on every tick; autoRecover subscribe runs
      `clearTimeout`+`setTimeout` per tick.

Trivial fixes (this plan):
  T1. Add `subscribeWithSelector` middleware to `useStore` at line 781.
  T2. Gate App.tsx:288 title-sync subscribe so `setTitle()` IPC fires only when
      `{currentFilePath, isDirty}` change.
  T3. Gate useStore.ts:2691 autoRecover subscribe so it fires only on `isDirty` transitions
      (false→true schedules, true→false cancels), not on every `set()` where isDirty is true.

Deferred (out-of-scope; flag for a future perf phase):
  - StreamNode autoflip per-port selector memoization (medium difficulty, requires
    restructuring of resolveFlowPortAssignment/resolveThermalPairSides).
  - Flip `isDirty` at `onNodeDragStop` instead of per-pixel (alters semantics of
    onNodesChange and risks the AutoRecover lock — needs design work).
  - Retest on native Linux or WebView2 (Windows) — user action, environmental.

Purpose: cheap wins now while preserving correctness. No measurable promise — these are
amplifier reductions that compound on top of the env floor, not a fix for the env floor itself.
Acceptance is correctness-preservation (vitest + the title still updates correctly on file
operations), NOT a perf delta.

Output: useStore middleware + 2 subscribe-gate refactors + 1 vitest covering the
subscribeWithSelector overload.

Source: `.planning/debug/gui-drag-perf.md` (root cause has app-layer + env layer; this plan
targets app-layer trivial only).
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/gui-drag-perf.md
@gui/src/store/useStore.ts
@gui/src/App.tsx

<interfaces>
<!-- Current useStore creation (line 781) -->
const useStore = create&lt;AppState&gt;()((set, get) =&gt; ({ ...slice... }));

After this plan:
const useStore = create&lt;AppState&gt;()(
  subscribeWithSelector((set, get) =&gt; ({ ...slice... }))
);

import to add at top of useStore.ts (near the existing `import { create } from "zustand";`):
  import { subscribeWithSelector } from "zustand/middleware";

`subscribeWithSelector` is bundled with zustand 5.0.12 (already in package.json) — no new
dependency. Type signature:

  // Backward-compatible: useStore.subscribe(listener) still fires on every set.
  // New overload added: useStore.subscribe(selector, listener, options?)
  //   options: { equalityFn?: (a, b) =&gt; boolean; fireImmediately?: boolean }

<!-- App.tsx:288 current shape (lines 282-292) -->
useEffect(() =&gt; {
  function syncTitle(filePath: string | null, dirty: boolean) {
    const filename = filePath ? filePath.split(/[/\\]/).pop() : null;
    const marker = dirty ? "*" : "";
    const title = filename
      ? `${filename}${marker} - STREAM Composer`
      : "STREAM Composer";
    document.title = title;
    getCurrentWindow().setTitle(title).catch(console.error);
  }
  const s = useStore.getState();
  syncTitle(s.currentFilePath, s.isDirty);
  const unsub = useStore.subscribe((state) =&gt; {
    syncTitle(state.currentFilePath, state.isDirty);
  });
  return unsub;
}, []);

After this plan:
useEffect(() =&gt; {
  function syncTitle(filePath: string | null, dirty: boolean) {
    // unchanged
  }
  const s = useStore.getState();
  syncTitle(s.currentFilePath, s.isDirty);
  const unsub = useStore.subscribe(
    (state) =&gt; ({ filePath: state.currentFilePath, dirty: state.isDirty }),
    ({ filePath, dirty }) =&gt; syncTitle(filePath, dirty),
    { equalityFn: (a, b) =&gt; a.filePath === b.filePath &amp;&amp; a.dirty === b.dirty },
  );
  return unsub;
}, []);

Inline shallow equality (3-line comparator) is enough; do NOT import zustand/shallow
unless useful elsewhere — keeps the diff minimal.

<!-- useStore.ts:2691 autoRecover subscribe current shape -->
const unsubscribe = useStore.subscribe((state) =&gt; {
  if (state.isDirty) {
    writer.schedule();
  } else {
    writer.cancel();
  }
});

After this plan:
const unsubscribe = useStore.subscribe(
  (state) =&gt; state.isDirty,
  (isDirty) =&gt; {
    if (isDirty) writer.schedule();
    else writer.cancel();
  },
);

Selector returns a primitive boolean; default equality (===) catches the transition.
The listener fires only on true→false and false→true edges.

Note: this changes a known semantic from Plan 07's design — "Each schedule() call resets the
2s timer". Under the new selector-gated version, `schedule()` is called ONLY on the
false→true transition. Subsequent edits within the same dirty session do NOT re-call
schedule() — but the writer's internal timer logic ALREADY handles "schedule called once, timer
fires after 2s". The behavior change is: rapid edits no longer continually reset the 2s
debounce window. The 2s window is now anchored at the first dirty transition; subsequent
edits accumulate into the eventual single sidecar write. This is ACCEPTABLE for AutoRecover —
the goal is "save within ~2s of last edit", and "save within ~2s of first edit" is a stricter
guarantee, not a regression. Document this in the inline comment.

If the change in semantics IS problematic, alternative: keep the rapid-reset behavior by
re-invoking schedule on every dirty=true set. To do that without firing on every set, store
the previous isDirty in a closure variable and re-schedule on dirty=true AS LONG AS it was
already dirty:

  let wasDirty = useStore.getState().isDirty;
  const unsubscribe = useStore.subscribe((state) =&gt; {
    if (state.isDirty) {
      // Always schedule on every set while dirty (matches Plan 07 semantics).
      writer.schedule();
    } else if (wasDirty) {
      writer.cancel();
    }
    wasDirty = state.isDirty;
  });

This still fires on every set, BUT skips the cancel() call when already not-dirty. Modest
saving (cancel is itself cheap), but it preserves Plan 07's "rapid edits reset the timer"
guarantee.

**Decision for this plan**: prefer the selector-gated version (the simpler one) because:
  - The brief explicitly calls out this subscribe as a trivial fix.
  - "2s after first edit" is a stricter, simpler guarantee than "2s after last edit".
  - The change is annotated; future maintainers see why.

If the executor encounters runtime behavior that contradicts this (the Task 3 checkpoint of
Plan 09's UAT 16/17 confirms sidecar still writes on edit), pivot to the closure-tracked
version. The plan does NOT depend on which variant ships — both close the gap.

<!-- shallow equality helper -->
zustand exports `import { shallow } from "zustand/shallow"` for object selectors. Optional.
For the inline 2-field object in App.tsx, the inline `(a, b) =&gt; a.filePath === b.filePath
&amp;&amp; a.dirty === b.dirty` is clearer than importing shallow. Use the inline version.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Install subscribeWithSelector middleware; add overload regression test</name>
  <files>
    gui/src/store/useStore.ts
    gui/src/store/__tests__/subscribeWithSelector.test.ts
  </files>
  <behavior>
    - Test: `useStore.subscribe(s =&gt; s.snapToGrid, listener)` invokes `listener` only when
      `snapToGrid` changes — NOT on unrelated setters (e.g., setting `bottomPanelOpen`).
    - Test: backward-compat — `useStore.subscribe(listener)` (single-arg) still fires on every
      `set()`.
    - Test: middleware composition does not alter `useStore.getState()` shape or any existing
      action's behavior; smoke-check 2-3 existing actions still work (e.g., setSnapToGrid).
  </behavior>
  <action>
    **TDD RED → GREEN.**

    Step 1 (RED). Create `gui/src/store/__tests__/subscribeWithSelector.test.ts`. Three
    test cases as in `<behavior>`. Use vitest's `vi.fn()` to count listener invocations.
    Between tests, reset relevant store fields via `useStore.setState(...)`.

    For case 1 (selector-gated):
      ```ts
      const listener = vi.fn();
      const unsub = useStore.subscribe(s =&gt; s.snapToGrid, listener);
      useStore.getState().setBottomPanelHeight(300);  // unrelated change
      expect(listener).toHaveBeenCalledTimes(0);
      useStore.getState().setSnapToGrid(true);
      expect(listener).toHaveBeenCalledTimes(1);
      useStore.getState().setSnapToGrid(true);        // no change
      expect(listener).toHaveBeenCalledTimes(1);
      unsub();
      ```

    For case 2 (backward-compat):
      ```ts
      const listener = vi.fn();
      const unsub = useStore.subscribe(listener);     // single-arg overload
      useStore.getState().setBottomPanelHeight(310);
      expect(listener).toHaveBeenCalled();            // fires on any set
      unsub();
      ```

    All cases must FAIL initially because zustand without subscribeWithSelector throws on
    the 2-arg overload (or treats the selector as the listener and "calls" it on every set —
    but case 1's `setSnapToGrid` invocation count would not be 1 strictly). Commit:
    ```
    git add gui/src/store/__tests__/subscribeWithSelector.test.ts
    git commit -m "test(65-14): RED — subscribeWithSelector overload

    Failing vitest cases for the selector-gated subscribe overload that
    requires the subscribeWithSelector middleware.

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```

    Step 2 (GREEN). Edit `gui/src/store/useStore.ts`:
      - Add `import { subscribeWithSelector } from "zustand/middleware";` near line 1
        (just below the existing `import { create } from "zustand";`).
      - Replace the line 781 store creation:
          `const useStore = create&lt;AppState&gt;()((set, get) =&gt; ({`
        with:
          `const useStore = create&lt;AppState&gt;()(subscribeWithSelector((set, get) =&gt; ({`
        And the closing of the slice (currently `}));` somewhere near line ~2640 or so;
        grep for the close-brace pattern that matches the line-781 open):
          `})));` (one extra `)` to close the middleware call).
        Verify by counting parens: the new shape is `create&lt;T&gt;()(subscribeWithSelector(fn))`
        — the closing must be `)))` (close fn, close subscribeWithSelector, close create-call).

    Run vitest and confirm all 3 new cases pass; no existing useStore test regresses:
      cd gui &amp;&amp; npx vitest run src/store

    Commit:
    ```
    git add gui/src/store/useStore.ts
    git commit -m "feat(65-14): subscribeWithSelector middleware on useStore

    Enables selector-gated useStore.subscribe(selector, listener) so
    consumers can opt into edge-only notifications. Backward-compat:
    useStore.subscribe(listener) (single-arg) continues to fire on every
    set().

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      grep -q "import { subscribeWithSelector } from \"zustand/middleware\"" gui/src/store/useStore.ts
      grep -q "subscribeWithSelector((set, get)" gui/src/store/useStore.ts
      cd gui &amp;&amp; npx vitest run src/store/__tests__/subscribeWithSelector.test.ts
      # Existing store tests don't regress
      cd gui &amp;&amp; npx vitest run src/store
    </automated>
  </verify>
  <done>
    Middleware installed; 3 new vitest cases pass; existing store tests pass; two atomic
    commits recorded.
  </done>
</task>

<task type="auto">
  <name>Task 2: Gate App.tsx title-sync + useStore autoRecover subscribe</name>
  <files>
    gui/src/App.tsx
    gui/src/store/useStore.ts
  </files>
  <action>
    **Step 1 — App.tsx title-sync gate.** Edit `gui/src/App.tsx` lines 287-290 (the
    `useStore.subscribe((state) =&gt; { syncTitle(...) })`). Replace with the selector-gated
    overload:

      const unsub = useStore.subscribe(
        (state) =&gt; ({ filePath: state.currentFilePath, dirty: state.isDirty }),
        ({ filePath, dirty }) =&gt; syncTitle(filePath, dirty),
        {
          equalityFn: (a, b) =&gt;
            a.filePath === b.filePath &amp;&amp; a.dirty === b.dirty,
        },
      );

    Add a one-line comment above the subscribe call:
      `// Phase 65 Plan 14: selector-gated — setTitle IPC fires only on filePath/dirty change.`

    Do NOT touch the `syncTitle` function itself, the initial-call line, or the unsubscribe
    return. Functional contract preserved: title still updates on every save/load/new/dirty
    transition.

    **Step 2 — useStore.ts autoRecover subscribe gate.** Edit the subscribe block around
    line 2691 (inside `initAutoRecover`). Replace:

      const unsubscribe = useStore.subscribe((state) =&gt; {
        if (state.isDirty) {
          writer.schedule();
        } else {
          writer.cancel();
        }
      });

    With:

      // Phase 65 Plan 14: selector-gated — schedule/cancel fire only on isDirty transitions.
      // Semantic shift from Plan 07 ("rapid edits reset the timer") to "2s after first edit
      // in the dirty session". Both satisfy the AutoRecover goal of "save within ~2s of
      // user activity" — the new semantics is a stricter, simpler guarantee.
      const unsubscribe = useStore.subscribe(
        (state) =&gt; state.isDirty,
        (isDirty) =&gt; {
          if (isDirty) writer.schedule();
          else writer.cancel();
        },
      );

    No `equalityFn` needed — primitive boolean uses default `===`.

    **Step 3 — tsc + vitest sanity.**
      cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c "error TS"
    Must be ≤ the pre-edit baseline (Phase 71 owns the 11 pre-existing errors).

      cd gui &amp;&amp; npx vitest run
    Must not introduce new failures. The AppShell tests (regressed in Plan 65-08 then
    fixed) should still pass.

    **Commit (single atomic — the two gates are a cohesive perf change):**
    ```
    git add gui/src/App.tsx gui/src/store/useStore.ts
    git commit -m "perf(65-14): gate title-sync + autoRecover subscribes

    App.tsx title-sync subscribe now uses the selector-gated overload so
    Tauri's setTitle IPC fires only when currentFilePath or isDirty
    actually change (was: every store set, including per-pixel drag
    ticks). useStore.ts autoRecover subscribe likewise fires only on
    isDirty transitions — semantic shift documented inline (Plan 07's
    'rapid edits reset 2s timer' becomes '2s after first edit'; both
    satisfy the safety net).

    Trivial fixes only — autoflip memoization and onNodeDragStop dirty
    flipping deferred to a future perf phase per Plan 14 brief.

    Source: .planning/debug/gui-drag-perf.md

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # App.tsx uses the 3-arg subscribe overload
      grep -q "equalityFn" gui/src/App.tsx
      grep -q "a.filePath === b.filePath" gui/src/App.tsx
      # useStore autoRecover subscribe uses the 2-arg overload with primitive selector
      grep -q "(state) =&gt; state.isDirty" gui/src/store/useStore.ts
      grep -q "(isDirty) =&gt; {" gui/src/store/useStore.ts
      # tsc not worse
      test "$(cd gui &amp;&amp; npx tsc --noEmit 2>&amp;1 | grep -c 'error TS')" -le 11
      # Full vitest suite still passes (apart from the pre-existing SidebarPanel.anchors flake
      # documented in STATE.md — that one test is owned by Phase 71)
      cd gui &amp;&amp; npx vitest run 2>&amp;1 | tail -10
    </automated>
  </verify>
  <done>
    Both subscribes converted to selector-gated overloads; tsc error count unchanged;
    vitest suite passes (Phase 71 pre-existing flake excepted); commit recorded.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

(none — internal subscribe wiring; no IPC surface change beyond the gate)

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-14a | Tampering | useStore autoRecover subscribe semantics | mitigate | Inline comment documents the Plan 07 → Plan 14 semantic shift ("2s after last edit" → "2s after first edit"). UAT Tests 16/17 still pass once Plan 09 ships because the writer still writes — same content, slightly different cadence. |
| T-65-14b | Denial of Service | subscribeWithSelector typo / paren mismatch | mitigate | tsc + vitest catch any composition error at commit time. Three new vitest cases assert both overloads work and don't regress backward compatibility. |
| T-65-14c | Information Disclosure | App.tsx title-sync gate omits a state | accept | Title now reflects ONLY {filePath, isDirty} — same fields the syncTitle function actually consumes. No state previously displayed in the title is dropped. |
</threat_model>

<verification>
- `grep -q "subscribeWithSelector" gui/src/store/useStore.ts`
- `grep -q "equalityFn" gui/src/App.tsx`
- 3 new vitest cases pass: `cd gui &amp;&amp; npx vitest run src/store/__tests__/subscribeWithSelector.test.ts`.
- Full vitest run does not introduce new failures.
- tsc error count unchanged from baseline (Phase 71 owns 11 pre-existing).
- Plan 09's manual UAT (Tests 16/17) STILL passes after this plan ships — the gate change
  preserves AutoRecover writes.
</verification>

<success_criteria>
- useStore is created with subscribeWithSelector middleware composition.
- App.tsx title-sync uses the 3-arg subscribe overload with inline equality on {filePath, dirty}.
- useStore autoRecover subscribe uses the 2-arg overload selecting `state.isDirty`.
- Three new vitest cases pass; backward-compat (single-arg subscribe) preserved.
- No new tsc errors; vitest suite has no NEW failures beyond Phase 71's owned flake.
- Three atomic commits recorded (RED + GREEN middleware + perf gates).
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-14-SUMMARY.md` when done.
</output>
