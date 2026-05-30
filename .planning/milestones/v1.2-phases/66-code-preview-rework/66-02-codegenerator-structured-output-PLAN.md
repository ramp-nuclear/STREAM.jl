---
phase: 66-code-preview-rework
plan: 2
type: execute
wave: 1
depends_on: [66-01]
files_modified:
  - gui/src/lib/codeGenerator.ts
  - gui/src/lib/codeGenerator.test.ts
  - gui/src/lib/__tests__/codeGenerator.anchors.test.ts
  - gui/src/lib/__tests__/codeGenerator.bc.test.ts
  - gui/src/lib/__tests__/codeGenerator.resources.test.ts
  - gui/src/lib/__tests__/codeGenerator.smoke.test.ts
  - gui/src/components/CodePreview.tsx
  - gui/src/components/Toolbar.tsx
autonomous: true
requirements: []

must_haves:
  truths:
    - "`generateCode(...)` returns `CodeSection[]` (not `string`)."
    - "Section names emitted in order: Imports, Resources (if non-empty), Components, Composition, Main."
    - "Composition sub-blocks: one per `connect(...)` line; one per topology-helper call (`fuel_assembly`, `symmetric_plate`, `plate`, `one_sided_connection`); each carries `sourceIds: string[]` with the consumed node UUIDs."
    - "Resources sub-blocks: one per Geometry; one per per-HD consumer-keyed power_shape assignment; one per Fluid (if any)."
    - "Components sub-blocks: one per `@named` declaration; `sourceIds = [node_uuid]`."
    - "Imports + Main sub-blocks: each a single sub-block with `sourceIds = []`."
    - "`serializeSections(CodeSection[]): string` exists; produces D-12 formatting: `# === <Section> ===` headers, one blank line between sub-blocks, one blank line between sections, no trailing whitespace."
    - "All five existing codegen test files pass after adapter wrap + D-12 header updates."
    - "Plan 01 RED tests (sections + serialize) flip GREEN."
    - "`CodePreview.tsx` and `Toolbar.tsx` continue rendering / exporting a `string` via the adapter — they are TEMP wrappers that Plans 03/04 take over."
  artifacts:
    - path: "gui/src/lib/codeGenerator.ts"
      provides: "CodeSection[] return type; serializeSections export; per-emission-site sourceIds tracking"
      contains: "export function generateCode"
      contains_also: "export function serializeSections"
      contains_also: "export interface CodeSubBlock"
      contains_also: "export interface CodeSection"
    - path: "gui/src/components/CodePreview.tsx"
      provides: "TEMP adapter — renders serializeSections(generateCode(...)) as a string; Plan 04 rewrites"
    - path: "gui/src/components/Toolbar.tsx"
      provides: "TEMP — calls serializeSections in handleExport; Plan 03 extracts to exportCode.ts"
  key_links:
    - from: "gui/src/lib/codeGenerator.ts (each emit site)"
      to: "CodeSubBlock.sourceIds"
      via: "node UUID resolution at emit time"
      pattern: "sourceIds:.*\\["
    - from: "5 existing codegen tests"
      to: "serializeSections"
      via: "one-line adapter wrap"
      pattern: "serializeSections\\(generateCode"
---

<objective>
Refactor `gui/src/lib/codeGenerator.ts` from `string` return to `CodeSection[]` return, with per-emission-site `sourceIds` tracking on each sub-block. Add a `serializeSections(CodeSection[]): string` adapter that reproduces the existing string output (modulo the D-12 formatting floor). Migrate the 5 existing codegen test files to wrap calls in `serializeSections(...)` and update fixture strings for the new `# === <Section> ===` headers.

Purpose: lock the new data shape inside the pure-data lib before any UI changes. Runtime behavior of the app is preserved — `CodePreview.tsx` and `Toolbar.tsx` are TEMP-wrapped through `serializeSections` so the app keeps rendering / exporting a string. Plans 03 and 04 take over those two consumers.
Output: Structured codegen output, all RED tests from Plan 01 (sections + serialize) flip GREEN, all 5 existing codegen test files pass with their D-12-updated fixtures.
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
@.planning/phases/66-01-SUMMARY.md
@gui/src/lib/codeGenerator.ts
@gui/src/components/CodePreview.tsx
@gui/src/components/Toolbar.tsx
</context>

<interfaces>
<!-- New exports this plan adds to codeGenerator.ts. Plans 03/04/05 consume these. -->

```typescript
// gui/src/lib/codeGenerator.ts (new exports)
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

// CHANGED return type:
export function generateCode(
  nodes: Node[],
  edges: Edge[],
  anchorsArg: { anchors: AnchorsRecord },
  getComp: GetComponent,
  resources?: CodegenResources,
  bcsState?: CodegenBCsState,
): CodeSection[];

export function serializeSections(sections: CodeSection[]): string;
```

Existing call sites and inputs to `generateCode` are unchanged (Phase 63.1 D-04 lock). Only the return type changes.

D-12 formatting floor (serializer obligations):
- Section header per section: `# === <Section Name> ===` (replaces ad-hoc `# ---------------------...` lines).
- Exactly one blank line between sub-blocks within a section.
- Exactly one blank line between top-level sections.
- No trailing whitespace.
- Consistent indentation (preserve what `codeGenerator.ts` already emits per-line).
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Refactor codeGenerator.ts — types, per-emission-site sub-blocks, serializeSections export</name>
  <files>gui/src/lib/codeGenerator.ts</files>
  <read_first>
    - gui/src/lib/codeGenerator.ts (the entire file — 1451 lines. Survey: lines 1-16 (header rule: no React, no Zustand); the existing `lines: string[]` walker pattern at lines 724, 752, 920, 1044, etc.; `detectThermalTopology` and `assemblies` builder at lines 464-688; the section delimiters currently emitted as `# ---------------------...` comments; the existing return statement `return lines.join('\n')`)
    - .planning/phases/66-code-preview-rework/66-RESEARCH.md §"Pattern 1: CodeSection[] shape + per-emission-site refactor" (full pattern with type shapes; the internal `pushSubBlock` helper recommendation), §"Pattern 2: serializeSections adapter", §"Pitfall 3: Blank-line double-emit between sub-blocks and sections", §"Pitfall 7: Object.fromEntries(sections) losing order"
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-01..D-04, D-12
  </read_first>
  <behavior>
    Sub-block emission contract (each maps to a Plan 01 sections.test.ts assertion):
    - Imports: ONE sub-block, `sourceIds: []`, `kind: 'import'`. All `using ...` lines + the leading "Generated by STREAM Composer" header comment (if any) go into this sub-block.
    - Resources: emitted ONLY when non-empty. One sub-block per Geometry (`kind: 'resource'`, `sourceIds: [geom.uuid]`). One sub-block per per-HD consumer-keyed power_shape assignment line (`kind: 'consumer-ps'`, `sourceIds: [ps.uuid, hd.uuid]`). One sub-block per Fluid declaration if/when fluids are emitted (`kind: 'resource'`, `sourceIds: [fluid.uuid]`).
    - Components: one sub-block per `@named <name> = <Constructor>(...)` declaration, `kind: 'component'`, `sourceIds: [node.uuid]`. BC pre-equation lines (BC profile-var stubs, function declarations) get `kind: 'bc-preeq'` sub-blocks with `sourceIds` resolved per Phase 63.1 D-04 (typically `[node.uuid]` for the consumer plus any source-id for the BC pattern; planner reads `codeGenerator.ts` lines around 900-1100 for the existing BC emission shape to attribute correctly). **Placement rationale (overrides RESEARCH.md Open Question #1 default of Resources):** BC pre-eqs sub-blocks (`kind: 'bc-preeq'`) land here under Components, not under Resources, because the existing codegen emits them between `@named` declarations and the `eqs = [` block — co-locating with `@named` declarations matches the existing emission order and avoids reshuffling the emit-site walker. See RESEARCH.md `## Open Questions (RESOLVED)` #1.
    - Composition: ONE sub-block per `connect(a.port, b.port)` line — `kind: 'connect'`, `sourceIds: [a_uuid, b_uuid]` (sorted). ONE sub-block per topology-helper call (`symmetric_plate`, `plate`, `one_sided_connection`, `fuel_assembly`) — `kind: 'helper'`, `sourceIds = ` union of all CAC/HD UUIDs the helper consumes (read from the existing `Assembly` record at lines ~580+). Pressure anchor lines get `kind: 'anchor'`, `sourceIds: [pump.uuid]` (or whatever component owns the anchor); BC bindings get `kind: 'bc-binding'`.
    - Main: ONE sub-block, `kind: 'system'`, `sourceIds: []`. Contains the final `@named sys = ODESystem(...)` + `mtkcompile(...)` lines.

    `serializeSections` behavior:
    - Iterate sections in order: `['Imports', 'Resources', 'Components', 'Composition', 'Main']`.
    - For each section with `subBlocks.length > 0`: emit `# === <Section Name> ===` on its own line, then exactly one blank line, then `subBlocks` joined with exactly one blank line between adjacent sub-blocks (each sub-block is `lines.join('\n')`).
    - Between top-level sections: exactly one blank line.
    - No trailing whitespace: after assembly, run `output.split('\n').map(l => l.replace(/[ \t]+$/, '')).join('\n')`.
    - Returns a single `string`. The string should end with a single trailing newline (current behavior; preserve).
  </behavior>
  <action>
    Add new type exports near the top of `codeGenerator.ts` (after the existing `CodegenBCsState` interface). Restructure the internal walker. The mechanical recipe:

    1. Replace the top-level `const lines: string[] = []` with section-scoped accumulators. The cleanest shape (per Research Pattern 1): a small internal `Emit` helper class or a closure-bound `pushSubBlock(section, kind, lines, sourceIds)` function. Pick one; the type signatures of all internal helpers (`emitImports`, `emitResources`, `emitComponents`, `emitComposition`, `emitMain` — or whatever the current helpers are named) change from `lines.push(...)` to `pushSubBlock(...)`.

    2. Walk every existing `lines.push(...)` call (use grep to enumerate them — survey shows ~80 sites at lines 724, 752, 920, 1044, etc.) and migrate each to `pushSubBlock(section, kind, [line1, line2, ...], sourceIds)`. **Adjacent `.push` calls that emit lines belonging to the same logical sub-block** (e.g., a multi-line `@named` declaration or a single `connect(` that spans a continuation comma — read the existing code to identify these) collapse into ONE `pushSubBlock` call with multi-element `lines`. **Different logical units** (next `@named`, next `connect`) become separate `pushSubBlock` calls.

    3. Update existing section-delimiter comment emissions: remove the current `# ---------------------...` style delimiter (which is currently a regular `lines.push(...)` line) and treat the section as a structural property. The section header is rendered by `serializeSections`, not stored in any sub-block.

    4. Add `serializeSections(sections)` exported function implementing the D-12 behavior above.

    5. Change `generateCode`'s return statement from `return lines.join('\n')` to `return sections` (a `CodeSection[]`).

    6. Preserve the pure-data discipline: NO React, NO Zustand, NO DOM. Header comment lines 1-16 stay verbatim.

    7. For Composition helper sub-blocks: read `Assembly.cacIds` and `Assembly.hdIds` (or equivalent — check the actual field names at lines 580+ in `codeGenerator.ts`). Concatenate into a single `sourceIds` array; sort for stable test assertions if helpful.

    Type safety: `CodeSubBlock.sourceIds: string[]` (NOT `string[] | undefined`). Empty array means "no sources" (intentional).

    DO NOT touch the actual emitted Julia text apart from removing the ad-hoc `# ---------------------...` delimiter lines (replaced by `serializeSections`'s `# === <Section> ===` headers). The five existing test files will be updated in Task 2 to absorb the header change.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/lib/__tests__/codeGenerator.sections.test.ts src/lib/__tests__/codeGenerator.serialize.test.ts 2>&1 | tail -30</automated>
  </verify>
  <acceptance_criteria>
    - `codeGenerator.ts` exports `CodeSection`, `CodeSubBlock`, `CodeSectionName`, `CodeSubBlockKind`, `serializeSections` (all named exports).
    - `generateCode(...)` return type is `CodeSection[]`.
    - Plan 01's `codeGenerator.sections.test.ts` ALL `it(...)` blocks pass.
    - Plan 01's `codeGenerator.serialize.test.ts` ALL `it(...)` blocks pass.
    - Pure-data discipline preserved: `grep -E "import .*react|from.*useStore|from.*zustand" gui/src/lib/codeGenerator.ts` returns 0 matches.
    - File header comment lines 1-16 unchanged (the "no React, no Zustand" header rule).
  </acceptance_criteria>
  <done>Structured output lands; Plan 01 sections + serialize tests GREEN.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Migrate 5 existing codegen test files (adapter wrap + D-12 header updates)</name>
  <files>gui/src/lib/codeGenerator.test.ts, gui/src/lib/__tests__/codeGenerator.anchors.test.ts, gui/src/lib/__tests__/codeGenerator.bc.test.ts, gui/src/lib/__tests__/codeGenerator.resources.test.ts, gui/src/lib/__tests__/codeGenerator.smoke.test.ts</files>
  <read_first>
    - gui/src/lib/codeGenerator.test.ts (all assertions — find every `expect(code).toContain(...)` or `expect(code).toBe(...)` / `toMatchSnapshot()` site)
    - gui/src/lib/__tests__/codeGenerator.anchors.test.ts (same survey)
    - gui/src/lib/__tests__/codeGenerator.bc.test.ts (same)
    - gui/src/lib/__tests__/codeGenerator.resources.test.ts (same)
    - gui/src/lib/__tests__/codeGenerator.smoke.test.ts (the "Julia-runnable smoke fixture" — its assertions tend to be the strictest)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md D-12 (header format `# === <Section> ===`)
  </read_first>
  <behavior>
    - Every existing `generateCode(...)` call site in these 5 files gets wrapped: `serializeSections(generateCode(...))` returning a `string`. This is the one-line documented adapter migration per CONTEXT canonical-refs §"Code touchpoints".
    - Any assertion that references the old section-delimiter comment shape (`# ---------------------` or similar) is updated to the new `# === <Section Name> ===` form.
    - String-equality / snapshot assertions update to reflect the new header text AND any blank-line normalization that the new serializer introduces (Pitfall 3: the new serializer guarantees exactly one blank line between sub-blocks; if the OLD codegen sometimes emitted zero or two blank lines, those fixtures must be updated to one).
    - No assertion logic is removed. Only fixture strings and the one-line wrap are touched.
  </behavior>
  <action>
    For each of the 5 files:

    1. Add `import { serializeSections } from "../codeGenerator";` (or `"../../lib/codeGenerator"` depending on the file's path).
    2. At every `generateCode(...)` call site that's stored to a `code` variable used in string assertions, wrap: `const code = serializeSections(generateCode(...));`.
    3. Update assertions that reference the old `# ---------------------` style section delimiters to use `# === <Section> ===`. Use grep on each file to find the old style: `grep -n '^\s*expect.*#.*---' gui/src/lib/__tests__/*.ts gui/src/lib/codeGenerator.test.ts`.
    4. Run the test file in isolation: `npx vitest --run <file>`. Read the failure output. If a fixture string has a different blank-line count than the new serializer emits, update the fixture (NOT the serializer — the serializer is the new spec per D-12).
    5. Snapshot files (`*.snap`) under `gui/src/lib/__tests__/__snapshots__/` for these tests: regenerate ONCE with `npx vitest --run -u <file>`, then HUMAN-READ the diff to confirm the changes are exclusively (a) the new `# === <Section> ===` headers, (b) blank-line normalization to single-blank between sub-blocks. Any other change is a regression — investigate before committing the snapshot.

    DO NOT update test logic. The test ASSERTIONS stay the same; only the FIXTURES (expected strings / snapshots) and the call-site wrap change.

    `codeGenerator.test.ts` is at `gui/src/lib/codeGenerator.test.ts` (NOT in `__tests__/` — research's path was slightly off). The other four are at `gui/src/lib/__tests__/codeGenerator.*.test.ts`.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run src/lib/codeGenerator.test.ts src/lib/__tests__/codeGenerator.anchors.test.ts src/lib/__tests__/codeGenerator.bc.test.ts src/lib/__tests__/codeGenerator.resources.test.ts src/lib/__tests__/codeGenerator.smoke.test.ts 2>&1 | tail -30</automated>
  </verify>
  <acceptance_criteria>
    - All 5 existing codegen test files pass.
    - Each file has at least one `serializeSections(generateCode(...))` call (the adapter wrap is present).
    - `grep -rn "# ---------------------" gui/src/lib/__tests__/ gui/src/lib/codeGenerator.test.ts` returns 0 hits (no stale section delimiters left in fixtures).
    - Any updated snapshot file's diff has been human-read and contains only the two expected change categories (header rename, blank-line normalization).
  </acceptance_criteria>
  <done>5 existing test files GREEN; fixture migrations clean; no test-logic edits.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: TEMP-wrap CodePreview.tsx and Toolbar.tsx through serializeSections (preserve runtime behavior)</name>
  <files>gui/src/components/CodePreview.tsx, gui/src/components/Toolbar.tsx</files>
  <read_first>
    - gui/src/components/CodePreview.tsx (current 34-line implementation — line 18-25 useMemo over generateCode)
    - gui/src/components/Toolbar.tsx (line 49-60 handleExport — current call into generateCode)
    - .planning/phases/66-code-preview-rework/66-CONTEXT.md (this is TEMP per the phase plan; Plans 03/04 replace it)
  </read_first>
  <behavior>
    - `CodePreview.tsx`: `useMemo` still returns a `string` (assembled via `serializeSections(generateCode(...))`); the `<pre><code>{code}</code></pre>` render path is UNCHANGED. Runtime UI looks identical to before this plan.
    - `Toolbar.tsx`: `handleExport` still calls `generateCode(...)` internally but wraps the result in `serializeSections(...)` before passing to `writeTextFile`. Exported `.jl` files are byte-equivalent to before this plan modulo the D-12 header changes (acceptable — exported files now have `# === <Section> ===` headers).
    - NO new behavior. NO new UI elements. This task exists solely to keep the app building and rendering between Plan 02 and Plan 04.
  </behavior>
  <action>
    `CodePreview.tsx`: change the `useMemo` body from
    ```
    () => generateCode(nodes, edges, { anchors }, getComponent, resources, { bcMode, bcSymmetric })
    ```
    to
    ```
    () => serializeSections(generateCode(nodes, edges, { anchors }, getComponent, resources, { bcMode, bcSymmetric }))
    ```
    Add the `serializeSections` import. Nothing else changes.

    `Toolbar.tsx`: locate `handleExport` (lines ~49-60). Whatever variable receives the `generateCode` result, wrap it in `serializeSections(...)`. Add the import. Nothing else changes — the validation gate, the `save` dialog, the `writeTextFile` call are untouched.

    Add a `// TEMP — Phase 66 Plan 03/04 takes over this consumer` comment above each call in both files so the next plan's executor sees them clearly.
  </action>
  <verify>
    <automated>cd /home/itay/projects/Julia-STREAM/gui && npx vitest --run 2>&1 | tail -10 && cd /home/itay/projects/Julia-STREAM/gui && npx tsc --noEmit 2>&1 | grep -E "error TS" | grep -v "pre-existing" | head -20</automated>
  </verify>
  <acceptance_criteria>
    - `cd gui && npx vitest --run` shows: Plan 01 sections + serialize tests GREEN; 5 existing codegen tests GREEN; pre-existing 1 SidebarPanel.anchors failure unchanged; Plan 01 CodePreview tests still RED (Plan 04 fixes those).
    - `cd gui && npx tsc --noEmit` shows the same 11 pre-existing tsc errors documented in `.planning/phases/61-.../deferred-items.md` — NO new tsc errors.
    - `CodePreview.tsx` and `Toolbar.tsx` each contain `serializeSections(generateCode(`.
    - App runtime (`cd gui && npm run dev` — sanity boot, no manual click-through required) starts without TypeError or "generateCode is not a function" errors.
  </acceptance_criteria>
  <done>App keeps rendering / exporting strings; all codegen tests GREEN; CodePreview UI tests stay RED for Plan 04.</done>
</task>

</tasks>

<verification>
After all three tasks:

```bash
cd /home/itay/projects/Julia-STREAM/gui
# All codegen tests GREEN (7 files: Plan 01's 2 + 5 existing)
npx vitest --run src/lib/ 2>&1 | tail -20

# Full vitest run — only newly-RED tests should be Plan 01's CodePreview tests (3 files; Plan 04 makes them GREEN)
npx vitest --run 2>&1 | tail -30

# TSC — no new errors beyond pre-existing 11
npx tsc --noEmit 2>&1 | grep "error TS" | wc -l
```

Manual sanity:
```bash
cd /home/itay/projects/Julia-STREAM/gui && npm run dev
# Then in browser: confirm code preview panel still renders Julia code with `# === Imports ===` etc. section headers.
# Click top-toolbar Export; confirm `.jl` file writes correctly.
# This is a 30-second sanity check, not a full UAT.
```
</verification>

<success_criteria>
- `codeGenerator.ts` returns `CodeSection[]`; `serializeSections` exported.
- Plan 01 sections + serialize RED tests flip GREEN.
- 5 existing codegen test files GREEN with D-12 header updates.
- `CodePreview.tsx` and `Toolbar.tsx` TEMP-wrapped through `serializeSections` — app behavior preserved.
- No new tsc errors beyond pre-existing 11.
- Pure-data discipline preserved in `codeGenerator.ts` (no React / Zustand imports).
</success_criteria>

<output>
Create `.planning/phases/66-code-preview-rework/66-02-SUMMARY.md` when done. Summary must list: line-count delta on `codeGenerator.ts`, count of `pushSubBlock` call sites added, list of fixture files updated and the change category for each (header / blank-line), confirmation that no test logic was removed.
</output>
