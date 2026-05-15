---
phase: 66-code-preview-rework
plan: 1
type: execute
wave: 0
depends_on: []
files_modified:
  - gui/src/lib/__tests__/codeGenerator.sections.test.ts
  - gui/src/lib/__tests__/codeGenerator.serialize.test.ts
  - gui/src/components/__tests__/CodePreview.test.tsx
  - gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx
  - gui/src/components/__tests__/CodePreview.textSelection.test.tsx
autonomous: true
requirements: []

must_haves:
  truths:
    - "Five new vitest files exist and run (RED). Each asserts behavior that Plans 02/04 will deliver."
    - "Tests describe the CodeSection / CodeSubBlock contract by referencing exported symbols (`generateCode`, `serializeSections`, `CodeSection`, `CodeSubBlock`) from `gui/src/lib/codeGenerator`."
    - "RED state is type-clean: tests COMPILE (no `any` placeholders for the new types); failures are runtime expectation failures, not tsc errors."
  artifacts:
    - path: "gui/src/lib/__tests__/codeGenerator.sections.test.ts"
      provides: "sub-block emission contract (one per @named, one per connect(), one per helper call, one per Geometry, Imports / Main = sourceIds=[])"
    - path: "gui/src/lib/__tests__/codeGenerator.serialize.test.ts"
      provides: "serializeSections round-trip: parsing the assembled string back through the existing fixture comparison"
    - path: "gui/src/components/__tests__/CodePreview.test.tsx"
      provides: "section rendering + sub-block click writes pinnedSourceIds + hover writes hoveredSourceIds"
    - path: "gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx"
      provides: "stream:show-code-for opens panel, calls scrollIntoView({behavior:'smooth',block:'center'}), applies 1.5s flash"
    - path: "gui/src/components/__tests__/CodePreview.textSelection.test.tsx"
      provides: "no sub-block wrapper has `select-none` class (D-14 regression)"
  key_links:
    - from: "tests"
      to: "gui/src/lib/codeGenerator"
      via: "named imports of CodeSection, CodeSubBlock, generateCode, serializeSections"
      pattern: "import.*CodeSection|serializeSections.*from.*codeGenerator"
---

<objective>
Land the RED test surface for Phase 66 before any production code changes. Five new vitest files specify the structured `CodeSection[]` codegen contract, the `serializeSections` adapter, and the new `CodePreview.tsx` behavior (sub-block hover/click, `stream:show-code-for` listener, text-selection preservation). Tests must compile (type-clean) but fail at runtime — Plan 02 turns the codegen tests green, Plan 04 turns the CodePreview tests green.

Purpose: lock the contract in test code before refactoring 1451 lines of `codeGenerator.ts`. Prevents the Plan 02 executor from "tests describe whatever I implemented" drift.
Output: 5 new test files; all RED; CI/vitest run shows 5 new failures with clear "expected X, received Y" diffs.
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
@gui/src/lib/codeGenerator.ts
@gui/src/lib/__tests__/codeGenerator.smoke.test.ts
@gui/src/lib/__tests__/codeGenerator.resources.test.ts
@gui/src/components/CodePreview.tsx
</context>

<interfaces>
<!-- Types and exports that Plan 02 will introduce. Tests reference these by name. -->

To be exported from `gui/src/lib/codeGenerator.ts` (Plan 02 creates; tests in this plan import as the contract):

```typescript
export type CodeSectionName = 'Imports' | 'Resources' | 'Components' | 'Composition' | 'Main';

export type CodeSubBlockKind =
  | 'import' | 'resource' | 'consumer-ps' | 'bc-preeq'
  | 'component' | 'connect' | 'helper' | 'anchor'
  | 'bc-binding' | 'system' | 'comment';

export interface CodeSubBlock {
  lines: string[];
  sourceIds: string[];
  kind?: CodeSubBlockKind;
}

export interface CodeSection {
  name: CodeSectionName;
  subBlocks: CodeSubBlock[];
}

export function generateCode(/* same args as today */): CodeSection[];
export function serializeSections(sections: CodeSection[]): string;
```

The existing `generateCode` signature (inputs) is locked by Phase 63.1 D-04 and does not change. Only the return type changes from `string` to `CodeSection[]`.
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Write codeGenerator.sections.test.ts (sub-block emission contract)</name>
  <files>gui/src/lib/__tests__/codeGenerator.sections.test.ts</files>
  <read_first>
    - gui/src/lib/codeGenerator.ts (current emit sites — survey for connect() lines, @named lines, helper-call emission paths, Geometry/PowerShape emission, Imports/Main blocks)
    - gui/src/lib/__tests__/codeGenerator.resources.test.ts (fixture / mock-node conventions used by the codegen test family — reuse the same fixture-building style)
    - gui/src/lib/__tests__/codeGenerator.smoke.test.ts (mockGetComponent shape; how a minimal pump + channel + connect graph is built)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-01, D-02, D-03, D-04
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 10: vitest test surface" (the recommended assertion shapes in this section are the contract)
  </read_first>
  <behavior>
    - Imports section: exactly one sub-block; `sourceIds === []`; `lines[0]` matches `^using ModelingToolkit`.
    - Components section: one sub-block per `@named` declaration; each sub-block's `sourceIds` is `[node_uuid]`; sub-block's `lines` contain the `@named <name> = <Constructor>(...)` text.
    - Composition section: each `connect(a.port, b.port)` is its own sub-block (`kind: 'connect'`), with `sourceIds` = sorted UUIDs of the two endpoint nodes.
    - Composition section helper calls: `symmetric_plate(...)`, `plate(...)`, `one_sided_connection(...)`, `fuel_assembly(...)` are each ONE sub-block (`kind: 'helper'`), with `sourceIds` listing every CAC/HD UUID consumed (use a fixture that triggers `symmetric_plate` via topology detection).
    - Resources section: each `Geometry` declaration is its own sub-block (`kind: 'resource'`, `sourceIds: [geometry_uuid]`); each per-HD consumer-keyed Power Shape line (e.g., `hd1_power_shape = ones(nz, nx)`) is its own sub-block (`kind: 'consumer-ps'`, `sourceIds: [power_shape_uuid, hd_uuid]`).
    - Main section: exactly one sub-block; `sourceIds === []`; `lines` contain `@named sys = ` AND `mtkcompile` (or the existing finalization lines).
    - All five section `name` values appear in order: `['Imports', 'Resources', 'Components', 'Composition', 'Main']`. (Resources is included even if empty — Plan 02 must decide; assert PRESENCE in the test for the case where resources are non-empty, and assert ORDER for those that exist.)
  </behavior>
  <action>
    Create `gui/src/lib/__tests__/codeGenerator.sections.test.ts`. Import `generateCode`, `CodeSection`, `CodeSubBlock`, `CodeSectionName`, `CodeSubBlockKind` from `../codeGenerator`. Reuse the `mockGetComponent`/node-fixture helpers already in use in `codeGenerator.smoke.test.ts` and `codeGenerator.resources.test.ts` (copy the fixture shape rather than importing private helpers from sibling test files).

    Structure: one top-level `describe("generateCode returns CodeSection[] with source tracking")` block with the behaviors above as separate `it(...)` cases. Use a minimal-graph fixture (one Pump + one Channel + one connect edge) for the component/connect cases; a fixture with one Geometry + one PowerShape + one HD-with-consumer-keyed-ps for the resources case; a fixture that triggers `symmetric_plate` topology (one CAC + one HD wired symmetrically) for the helper case.

    DO NOT use `any` for the section/sub-block types in the test code. The contract under test is the typed shape.

    DO NOT modify `codeGenerator.ts` in this task. The test FILE MUST compile against the in-tree codegen — which means `codeGenerator.ts` does not yet export the new types. **Resolution: this task writes the test assuming the new exports exist; the test file will fail tsc compilation until Plan 02 lands.** That is the intended RED state. Run `cd gui && npx vitest --run gui/src/lib/__tests__/codeGenerator.sections.test.ts` once to capture the tsc errors and confirm they are about missing exports (`Module '"../codeGenerator"' has no exported member 'CodeSection'`), NOT about test-code typos. If the failures are anything other than missing-export from `codeGenerator`, fix the test code.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/lib/__tests__/codeGenerator.sections.test.ts 2>&1 | grep -E "(FAIL|TS2305|TS2724|no exported member)" | head -20</automated>
  </verify>
  <acceptance_criteria>
    - File `gui/src/lib/__tests__/codeGenerator.sections.test.ts` exists.
    - Running vitest on the file produces failures that mention missing exports (`CodeSection`, `CodeSubBlock`, `serializeSections` if used) from `../codeGenerator`. Failures are NOT about test-code typos or unresolved imports outside `codeGenerator.ts`.
    - The test file contains at minimum 6 `it(...)` blocks covering: Imports single block / Components one-per-@named / Composition one-per-connect / Composition one-per-helper-call (fuel_assembly OR symmetric_plate, planner picks one) / Resources Geometry sub-block / Resources consumer-keyed power_shape sub-block / Main single block. (≥6 it blocks.)
    - Test file does NOT contain `any` for `CodeSection` / `CodeSubBlock` / `CodeSectionName` / `CodeSubBlockKind`.
  </acceptance_criteria>
  <done>RED test file lands; vitest fails on missing-from-codegen exports; no test-code typos.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Write codeGenerator.serialize.test.ts (round-trip + D-12 header shape)</name>
  <files>gui/src/lib/__tests__/codeGenerator.serialize.test.ts</files>
  <read_first>
    - gui/src/lib/__tests__/codeGenerator.smoke.test.ts (the smoke fixture is the canonical "this output is Julia-runnable" reference)
    - gui/src/lib/__tests__/codeGenerator.resources.test.ts (Resources block round-trip cases)
    - gui/src/lib/__tests__/codeGenerator.bc.test.ts (BC emission shapes; the serializer must preserve BC pre-eqs and bindings without injecting extra blank lines)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-12 (formatting floor)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 2: serializeSections" and §"Pitfall 3: Blank-line double-emit"
  </read_first>
  <behavior>
    - `serializeSections(generateCode(...))` returns a `string`.
    - The string contains `# === Imports ===`, `# === Resources ===`, `# === Components ===`, `# === Composition ===`, `# === Main ===` as top-level section headers (D-12). (Empty sections MAY be omitted — Plan 02 decides; test only asserts presence when section is non-empty.)
    - Between two adjacent sub-blocks within a section: exactly one blank line (i.e., `lines.join('\n')` between them yields exactly one `\n\n`, not `\n\n\n`).
    - Between two adjacent top-level sections: exactly one blank line.
    - No line in the serialized output has trailing whitespace (`/[ \t]+$/m` does not match).
    - Round-trip property: take a non-trivial fixture (Pump + Channel + connect + one Geometry + one PowerShape + one HD with consumer-keyed ps), call `generateCode` → `serializeSections`, then assert: every `@named` line appears once, every `connect(` line appears once, the order Imports → Resources → Components → Composition → Main is preserved, and no sub-block content is duplicated.
  </behavior>
  <action>
    Create `gui/src/lib/__tests__/codeGenerator.serialize.test.ts`. Import `generateCode`, `serializeSections` from `../codeGenerator`. Build fixtures inline using the same conventions as `codeGenerator.smoke.test.ts`.

    Assertions: use `toContain` for section headers; use a regex `/^\S.*\n\n\S/m` (or equivalent) to detect double-blank-line gaps between sub-blocks; iterate over `serialized.split('\n')` and assert `! /[ \t]+$/.test(line)` for every line; use `serialized.match(/@named /g)` length to assert component count; assert order via `serialized.indexOf('# === Imports ===') < serialized.indexOf('# === Components ===')`.

    Include one explicit anti-regression test for Pitfall 3 (no triple newline between sub-blocks or between sections).

    Do NOT modify `codeGenerator.ts`. Test will fail to compile (missing `serializeSections` export) until Plan 02 lands — that is the RED state.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/lib/__tests__/codeGenerator.serialize.test.ts 2>&1 | grep -E "(FAIL|TS2305|TS2724|no exported member)" | head -20</automated>
  </verify>
  <acceptance_criteria>
    - File exists; vitest run fails on missing `serializeSections` export from `../codeGenerator`.
    - File contains assertions for: D-12 section-header presence, single blank line between sub-blocks (no double blanks), single blank line between sections, no trailing whitespace, section order, and round-trip uniqueness of `@named` / `connect(` lines.
    - At least one assertion explicitly matches `# === Imports ===` (exact header text per D-12).
  </acceptance_criteria>
  <done>RED test file lands; vitest fails on missing `serializeSections`; D-12 contract is encoded in tests.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Write CodePreview.test.tsx, CodePreview.showCodeFor.test.tsx, CodePreview.textSelection.test.tsx</name>
  <files>gui/src/components/__tests__/CodePreview.test.tsx, gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx, gui/src/components/__tests__/CodePreview.textSelection.test.tsx</files>
  <read_first>
    - gui/src/components/CodePreview.tsx (current 34-line implementation — what it renders, what store slices it reads)
    - gui/src/components/__tests__/StreamNode.test.tsx (the established react-testing-library + useStore mocking patterns for component tests in this repo)
    - gui/src/components/__tests__/AppShell.test.tsx (App-level integration test conventions — useStore.setState seeding, lib mocking)
    - gui/src/store/useStore.ts (find existing ephemeral slices like `bottomPanelOpen`, `errorNodeIds` for mocking patterns)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-05, D-06, D-07, D-09, D-10, D-13, D-14
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 3: scroll + flash", §"Pattern 5: CustomEvent listener", §"Pattern 7: native text-selection", §"Pattern 10: vitest test surface"
  </read_first>
  <behavior>
    File 1 — `CodePreview.test.tsx` (rendering + hover/click):
      - Renders one DOM element per section with a recognizable header for each populated section.
      - Renders multiple elements with `[data-sub-block]` attribute (one per emitted sub-block).
      - Hovering a sub-block (`fireEvent.mouseEnter`) writes its `sourceIds` into `useStore.getState().hoveredSourceIds`; `mouseLeave` clears them.
      - Clicking a sub-block writes its `sourceIds` into `useStore.getState().pinnedSourceIds` (additive across two clicks on different sub-blocks per D-10); clicking the same sub-block again removes those IDs.
      - Pressing `Esc` (window keydown) with focus outside any input clears `pinnedSourceIds`. (If this is wired in `App.tsx` rather than `CodePreview.tsx`, this assertion belongs in an AppShell-level test; planner picks where — but the test MUST exist somewhere in the Phase 66 test set.)
    File 2 — `CodePreview.showCodeFor.test.tsx`:
      - Mock `Element.prototype.scrollIntoView` with `vi.spyOn`.
      - Seed store with a node whose UUID will appear in a Components sub-block.
      - With `bottomPanelOpen: false`, dispatch `new CustomEvent('stream:show-code-for', { detail: { nodeId } })` on window.
      - Assert: `bottomPanelOpen` becomes `true`, `scrollIntoView` called with `{ behavior: 'smooth', block: 'center' }` (or `'nearest'` — match what Plan 04 commits to in CONTEXT D-07's "center-ish"), and the targeted sub-block has a flash class/data-attribute applied for ~1.5s.
      - Also test the `nodeIds: string[]` payload shape (D-08) accepts arrays.
    File 3 — `CodePreview.textSelection.test.tsx`:
      - Render `<CodePreview />` with a non-empty seeded store; query all `[data-sub-block]` wrappers.
      - For every wrapper, assert `expect(el.className).not.toContain('select-none')` (class-level lint per Pattern 7's recommendation — jsdom can't resolve Tailwind computed styles).
      - Also assert `expect(el.getAttribute('onMouseDown')).toBeNull()` is NOT a meaningful check (React props don't surface as DOM attributes); instead grep the source via a separate node-side test if needed — but for THIS test, the class-level assertion is sufficient.
  </behavior>
  <action>
    Create all three test files. Use `@testing-library/react` `render`, `fireEvent`, `act`, `waitFor`. Mock the store via `useStore.setState({ ... })` inside `beforeEach` to seed deterministic node fixtures (the pattern AppShell.test.tsx uses).

    For File 1, write a minimal `mockSections` array — but call the real `generateCode` from a real seeded store rather than hard-coding sections, so the test exercises the real CodePreview render path. Tests stay RED because `CodePreview.tsx` still renders the old `<pre><code>{string}</code></pre>` shape (no `[data-sub-block]` elements). Failures are runtime "no elements found" — that is the intended RED state.

    For File 2, spy `Element.prototype.scrollIntoView` and use `waitFor`. Wrap mock-store seeding in `act(() => useStore.setState(...))` to keep React's reconciler happy.

    For File 3, render and class-check; this is the cheapest test.

    Do NOT modify `CodePreview.tsx` or `useStore.ts`. RED is correct.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/components/__tests__/CodePreview.test.tsx src/components/__tests__/CodePreview.showCodeFor.test.tsx src/components/__tests__/CodePreview.textSelection.test.tsx 2>&1 | tail -40</automated>
  </verify>
  <acceptance_criteria>
    - All three files exist under `gui/src/components/__tests__/`.
    - Running vitest on the three files produces failures (RED). Failures are runtime expectation failures (`expect(...).toBeInTheDocument() failed`, `Cannot find element [data-sub-block]`, etc.) — NOT test-code syntax errors.
    - `CodePreview.test.tsx` contains at least 4 `it(...)` blocks: sub-block render, hover writes store, click pins store, Esc clears pins (the Esc test may live in an AppShell test instead; if so, leave a `it.todo('Esc clears pins — covered in AppShell test set'); ` placeholder here referencing the file path).
    - `CodePreview.showCodeFor.test.tsx` contains at least 2 `it(...)` blocks: panel opens + scroll, multi-node payload (`nodeIds: string[]`).
    - `CodePreview.textSelection.test.tsx` contains at least 1 `it(...)` block asserting no sub-block wrapper has `select-none` in its className.
  </acceptance_criteria>
  <done>Three RED test files land; vitest run shows 7+ new runtime failures; no test-code typos.</done>
</task>

</tasks>

<verification>
After all three tasks complete:

```bash
cd /home/itay/projects/Julia-STREAM/gui
npx vitest --run \
  src/lib/__tests__/codeGenerator.sections.test.ts \
  src/lib/__tests__/codeGenerator.serialize.test.ts \
  src/components/__tests__/CodePreview.test.tsx \
  src/components/__tests__/CodePreview.showCodeFor.test.tsx \
  src/components/__tests__/CodePreview.textSelection.test.tsx 2>&1 | tail -60
```

Expected: ALL five files RED. Sample of failure messages MUST include either:
- TS errors about missing `CodeSection` / `CodeSubBlock` / `serializeSections` exports from `../codeGenerator`, OR
- Runtime "expected X received Y" for the CodePreview render tests.

Pre-existing tests (the 5 existing codegen test files + the StreamNode/AppShell/etc.) MUST still pass:

```bash
cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run 2>&1 | tail -20
```

The 5 new failures are the ONLY new failures.
</verification>

<success_criteria>
- 5 new test files exist at the specified paths.
- All 5 RED (vitest fails with relevant assertions).
- No pre-existing test newly breaks (the 11 pre-existing tsc errors + 1 pre-existing failing test from Phase 61/65 deferred items are unchanged).
- Test files compile cleanly EXCEPT for the deliberate missing-import RED state of the codegen tests (which Plan 02 fixes).
- No production code modified in this plan.
</success_criteria>

<output>
Create `.planning/phases/66-code-preview-rework/66-01-SUMMARY.md` when done. Summary must list: each test file, the contract it locks (which D-IDs from CONTEXT.md), the assertion count, and the RED failure category for each.
</output>
