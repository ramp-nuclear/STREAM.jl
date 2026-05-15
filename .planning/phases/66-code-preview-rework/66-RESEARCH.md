# Phase 66: Code preview rework — Research

**Researched:** 2026-05-15
**Domain:** Frontend GUI refactor (codegen return-shape change + React preview UI + Zustand ephemeral slices + CustomEvent listener wiring)
**Confidence:** HIGH (all touchpoints physically verified in the working tree; no external library research required — locked decisions in CONTEXT.md forbid Monaco/Prism/highlight.js)

## Summary

Phase 66 is a UI-only refactor on the `gui-redesign` branch. There is **zero Julia / MTK / src-side work** — codegen is already a pure data module (`zero React, zero zustand`) and stays that way. The phase changes the codegen return type from `string` to a structured `CodeSection[]` so the preview can attach hover/click handlers at sub-block granularity and trace source UUIDs back to canvas nodes.

The mechanically dominant work is **mechanical-but-mediated**: every existing `lines.push(...)` site in `gui/src/lib/codeGenerator.ts` (≈ 80 sites across 1451 lines) must become a sub-block append. A `serializeSections(CodeSection[]) -> string` adapter preserves the existing test-suite byte equality (with a one-time fixture update absorbing the D-12 formatting floor: `# === <Section> ===` headers replace the current `# ---------` dashed blocks). All five test files (`codeGenerator.test.ts` 822 lines + 4 in `__tests__/`, 1215 lines total) keep their string-equality assertions intact by piping through the adapter — no fixture mass-rewrite needed.

The UI side rewrites `CodePreview.tsx` (34 lines) into a section-by-section renderer, adds Copy/Export buttons to `BottomPanel.tsx`'s `<TabsList>` strip, extracts `Toolbar.handleExport` into a shared `gui/src/lib/exportCode.ts` util, and adds two ephemeral Zustand slices (`hoveredSourceIds`, `pinnedSourceIds`) wired into `StreamNode.tsx` via primitive-boolean selectors (matching the existing Pitfall 1 / Pitfall 3 patterns documented in StreamNode.tsx:124-130, 184-195, 259-275). `NodeContextMenu.tsx:40` already dispatches `stream:show-code-for` — Phase 66 is the consumer, not the dispatcher.

**Primary recommendation:** Decompose into **5 sequential-ish plans** (Wave 0 RED tests → Wave 1 codegen refactor + adapter → Wave 2 store slices + exportCode util → Wave 3 CodePreview UI rewrite + BottomPanel buttons → Wave 4 StreamNode hover-ring + jump-to-code listener + Esc integration). The codegen refactor (Plan 02) is the load-bearing piece; everything else builds on the `CodeSection[]` output.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Codegen structured-output transform | Pure data lib (`gui/src/lib/`) | — | `codeGenerator.ts` header rule: zero React, zero zustand. New `serializeSections` adapter stays pure too. |
| `CodeSection[]` rendering | Frontend client (React component) | — | `CodePreview.tsx` consumes structured output and attaches DOM event handlers. |
| Hover / pin ephemeral state | Frontend client (Zustand slice) | — | Session-only, not persisted to `.scp` (explicit D-11 — matches existing `interactiveLocked`, `bottomPanelOpen` pattern). |
| Canvas hover-ring CSS class | Frontend client (`StreamNode.tsx` subscriber) | — | Primitive-boolean selector per node, identical pattern to `hasAnchor` (line 174) and `hasBCError` (line 317). |
| `stream:show-code-for` listener | Frontend client (`CodePreview.tsx` or `useShowCodeFor` hook) | — | Consumer side of Phase 65 D-14 dispatcher. The dispatcher (`NodeContextMenu.tsx:40`) already opens the bottom panel synchronously before firing the event. |
| Export file-write | Tauri shell IPC | Frontend client | `@tauri-apps/plugin-dialog` `save` + `@tauri-apps/plugin-fs` `writeTextFile`. Already imported and working in `Toolbar.tsx:53-58`. |
| Copy-to-clipboard | Frontend (`navigator.clipboard`) | — | Works natively in Tauri webview; same pattern as Phase 65 clipboard. No Tauri plugin needed. |
| `serializeSections` adapter | Pure data lib (named export in `codeGenerator.ts`) | — | Test suite needs SOME exported function with this signature; co-locating it minimizes import churn. |
| `exportCode.ts` shared util | Pure-ish lib (Tauri IPC + validation gate) | — | Both call sites (`Toolbar.tsx`, `BottomPanel.tsx`) drive the same flow per D-18. |

## Standard Stack

### Core (already in tree — no installs needed)

| Library | Version (verified) | Purpose | Why Standard |
|---------|-------------------|---------|--------------|
| React | 18.x | UI | Already in tree. [VERIFIED: package.json check pending — only matters if the planner adds dependencies, which it should not] |
| TypeScript | 5.x | Type safety | Already in tree. |
| Vite | 5.x | Bundler / HMR | Already in tree. |
| Zustand | 4.x (+ `subscribeWithSelector` middleware — Phase 65-14 installed) | Ephemeral UI state | Already in tree — `useStore.ts:2` imports `subscribeWithSelector`. |
| Tailwind | 3.x | Styling | Already in tree. |
| shadcn/ui (Radix primitives) | n/a (vendored shims under `gui/src/components/ui/`) | Tabs, Button, ScrollArea | Already in tree. `TabsList` is the insertion point per D-16. |
| `lucide-react` | already used | Copy / Download / Check icons | `Download` already used at `Toolbar.tsx:128`. |
| `@tauri-apps/plugin-dialog` `save` | Tauri 2 | Export save dialog | Already used at `Toolbar.tsx:3,53`. |
| `@tauri-apps/plugin-fs` `writeTextFile` | Tauri 2 | Export write | Already used at `Toolbar.tsx:4,58`. |
| `navigator.clipboard.writeText` | Browser-native | Copy-to-clipboard | Already used in Phase 65 clipboard work. No polyfill. |
| vitest + @testing-library/react | already used | Tests | Already used in `gui/src/lib/__tests__/` and component tests. |

### Forbidden / Out of scope (re-stated)

| Library | Why NOT used |
|---------|--------------|
| Monaco editor / CodeMirror | Locked out per `STACK.md:117` and D-13. Read-only `<pre><code>` only. |
| Prism.js / highlight.js / shiki | Locked out per D-13. No syntax highlighting. |
| react-syntax-highlighter | Same as above. |
| immer | Not used elsewhere in `useStore`. Phase 66 stays consistent with existing immutable-spread patterns (see `setBCMode` style at line 1134). |

**Installation:** **No new packages required.** Every dependency the phase needs is already in `gui/package.json`. The planner should NOT add to the dep tree.

## Package Legitimacy Audit

**Skipped:** Phase 66 does not install any external packages. Every library the phase uses (`@tauri-apps/plugin-dialog`, `@tauri-apps/plugin-fs`, `lucide-react`, Radix UI primitives via shadcn shims, Zustand, vitest) is already in the dependency tree from prior phases. No `npm install` step is required.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01..D-04** Sub-block model: `CodeSection = { name: 'Imports'|'Resources'|'Components'|'Composition'|'Main'; subBlocks: CodeSubBlock[] }`; `CodeSubBlock = { lines: string[]; sourceIds: string[]; kind?: string }`. Smallest UI-addressable unit is the sub-block. Composition sub-blocks one-per-emission-unit. Resources sub-blocks per-line. Components sub-blocks one-per-`@named`-declaration. Imports / Main are each one sub-block with `sourceIds = []`.
- **D-05..D-08** Hover style is a NEW dedicated hover-ring (distinct from selection, validation, BC-dashed). Layer-aware (un-dims off-layer node during hover/pin). Canvas→code is explicit-only via `stream:show-code-for`. Plain selection does NOT auto-scroll the panel. When event fires + panel closed, set `bottomPanelOpen = true` then on next render smooth-scroll + 1.5s flash. Listener accepts `nodeId` xor `nodeIds`.
- **D-09..D-11** Click-to-pin = sticky highlight. Multi-pin additive. Toggle semantics treat sub-block as unit. Esc clears all pins. Pin state does NOT touch canvas selection / Properties panel / undo. Pin state is ephemeral session state, NOT persisted to `.scp`.
- **D-12** Hand-rolled formatting **floor only**: `# === <Section Name> ===` headers, one blank line between sub-blocks, one blank line between sections, no trailing whitespace, consistent indentation. Nothing else (sorted imports / aligned `@named` columns / number-literal normalization are Phase 72).
- **D-13** Plain `<pre><code>` rendering. No Monaco / Prism / highlight.js. Each sub-block becomes its own `<div>` (or `<pre>`) inside the section.
- **D-14** Native browser text-selection MUST be preserved. No `user-select: none`. No `preventDefault()` on `mousedown`. Drag-to-select inside/across sub-blocks/sections must work and produce clean copyable text.
- **D-15** NO per-sub-block Copy button (rejected — visual clutter, §3.8 violation).
- **D-16..D-19** Copy + Export buttons on right side of `<TabsList>` strip in `BottomPanel.tsx`. Buttons are `Button size="sm"` (ghost or outline — variant=outline matches existing visual weight). Copy → `navigator.clipboard.writeText(serializeSections(sections))` + 1.5s "Copied" confirmation. Export reuses extracted `gui/src/lib/exportCode.ts` util (validation gate + Tauri save dialog). Top-Toolbar Export button STAYS (reachable when panel closed). Buttons disabled when `nodes.length === 0`.

### Claude's Discretion

- Exact CSS for the hover-ring (color, stroke width, dash pattern, 1.5s flash animation timing) — final tuning is Phase 72; pick a sensible placeholder.
- Whether `pinnedSourceIds` lives on `useStore` or in a separate `useCodePanelStore` — both acceptable. (Recommendation below: single `useStore`.)
- Whether `serializeSections` is exported from `codeGenerator.ts` or a sibling file — both acceptable. (Recommendation below: co-locate in `codeGenerator.ts`.)
- File location for `exportCode.ts` (could go in `gui/src/lib/projectIO.ts` since both involve Tauri save). (Recommendation below: separate file `exportCode.ts`.)
- Click-handler shape: single `onClick` on sub-block wrapper (recommended) vs `onMouseDown` + custom drag detection.
- Test surface: vitest unit tests for `serializeSections` round-trip; component tests for `CodePreview` rendering; integration test for `stream:show-code-for`; regression test confirming `user-select: none` absent on sub-block wrappers.

### Deferred Ideas (OUT OF SCOPE)

**Phase 72:** Sorted/grouped `using` imports. Aligned `@named` columns. Normalized number-literal formatting. Final hover-ring visual tuning (color/animation).

**Future, no owner:** Multi-node `stream:show-code-for` payload (`nodeIds: string[]`). Per-sub-block Copy button. Syntax highlighting (Prism/highlight.js/shiki). In-panel code editing. Section folding / collapse.

## Phase Requirements

Phase 66 has no global REQ-IDs in `REQUIREMENTS.md` — v1.2 phases (including this one) track coverage via the locked CONTEXT.md decisions list, mirroring Phase 63.1's approach. The 19 D-IDs above ARE the requirements. The planner should map each plan's success criteria to the D-IDs it closes.

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01..D-04 | Sub-block model + per-section granularity | §Architecture: CodeSection / CodeSubBlock shape — verified mechanically against `codeGenerator.ts` walker emission sites |
| D-05..D-08 | Hover style + jump-to-code semantics | §Pattern 3: scroll-into-view + flash; §Pattern 5: CustomEvent listener lifecycle |
| D-09..D-11 | Click-to-pin store slices | §Pattern 4: Zustand ephemeral slice shape |
| D-12 | Formatting floor | §Pattern 1: serializeSections adapter |
| D-13 | Plain `<pre><code>` rendering | Locked by STACK.md:117; CONTEXT.md re-states |
| D-14 | Native text-selection preserved | §Pattern 7: text-selection regression test |
| D-15 | No per-sub-block Copy | Locked; no implementation work |
| D-16..D-19 | Copy/Export buttons + extracted exportCode util | §Pattern 8: 1.5s toggle confirmation; §Standard Stack: `Toolbar.tsx` already drives the save dialog |

## Architecture Patterns

### System Architecture Diagram

```
                  ┌─────────────────────────────────────────┐
                  │      pure data layer (no React)        │
                  │                                         │
                  │   generateCode(nodes, edges, anchors,   │
                  │                getComp, resources, bcs) │
                  │            │                            │
                  │            ▼                            │
                  │     CodeSection[]                       │
                  │   (Imports / Resources / Components /   │
                  │    Composition / Main; each carries     │
                  │    CodeSubBlock[] with sourceIds[])     │
                  │            │                            │
                  │            ▼                            │
                  │   serializeSections() → string          │
                  │   (back-compat adapter for tests +      │
                  │    Copy/Export buttons)                 │
                  └────────────┬────────────────────────────┘
                               │
            ┌──────────────────┴──────────────────┐
            │                                     │
   ┌────────▼─────────┐                  ┌────────▼─────────┐
   │ CodePreview.tsx  │                  │ exportCode.ts    │
   │ section-by-      │                  │ validateAndGate  │
   │ section renderer │                  │ + Tauri save     │
   │                  │                  │ + writeTextFile  │
   │  hover/click     │                  └──────────────────┘
   │  handlers per    │                          ▲
   │  sub-block       │                          │
   │       │          │                  ┌───────┴──────────┐
   │       │          │                  │ BottomPanel.tsx  │
   │       ▼          │                  │ Copy + Export    │
   │ useStore         │                  │ buttons (right   │
   │ .setHovered      │                  │  side of         │
   │ .togglePinned    │                  │  TabsList)       │
   └────────┬─────────┘                  └──────────────────┘
            │
            ▼
   ┌──────────────────┐
   │ Zustand slices   │       ◄──── window.addEventListener(
   │ hoveredSourceIds │             'stream:show-code-for',
   │ pinnedSourceIds  │             handler)
   │ (Set<string>)    │
   └────────┬─────────┘             dispatched by
            │                       NodeContextMenu.tsx:40
            ▼                       (already shipped)
   ┌──────────────────┐
   │ StreamNode.tsx   │
   │ subscribes via   │
   │ primitive-bool   │
   │ selector,        │
   │ applies hover-   │
   │ ring CSS class   │
   └──────────────────┘
```

### Pattern 1: `CodeSection[]` shape + per-emission-site refactor

**Recommended type shape (place in `gui/src/lib/codeGenerator.ts` near top, after the existing `CodegenBCsState` interface):**

```ts
export type CodeSectionName = 'Imports' | 'Resources' | 'Components' | 'Composition' | 'Main';

export type CodeSubBlockKind =
  | 'import'
  | 'resource'        // Geometry, PowerShape, Fluid
  | 'consumer-ps'     // per-HD power_shape variable line
  | 'bc-preeq'        // BC profile-var / function stub (pre-eqs)
  | 'component'       // @named declaration
  | 'connect'         // single connect() inside eqs[]
  | 'helper'          // symmetric_plate / plate / one_sided_connection / fuel_assembly @named line
  | 'anchor'          // pressure anchor binding (~)
  | 'bc-binding'      // BC binding (for-comprehension)
  | 'system'          // @named sys = ... + mtkcompile
  | 'comment';        // pure header/warning lines with no source

export interface CodeSubBlock {
  /** Lines as they appear in the generated script (no trailing newline). */
  lines: string[];
  /** Source-node and/or resource UUIDs that produced these lines. May be empty. */
  sourceIds: string[];
  /** Optional discriminator for renderer styling. */
  kind?: CodeSubBlockKind;
}

export interface CodeSection {
  name: CodeSectionName;
  subBlocks: CodeSubBlock[];
}
```

**Refactor strategy for `generateCode`:** Wrap the existing logic so each emit site appends to a section-local accumulator instead of the flat `lines: string[]` array. Smallest-change pattern:

```ts
// Replace flat `lines: string[]` with section accumulators
const imports: CodeSubBlock[] = [];
const resources: CodeSubBlock[] = [];
const components: CodeSubBlock[] = [];
const composition: CodeSubBlock[] = [];
const main: CodeSubBlock[] = [];

// Local helper builders so most emit sites stay almost-unchanged
function emitImport(line: string) { imports.push({ lines: [line], sourceIds: [], kind: 'import' }); }
function emitComponent(line: string, sourceIds: string[]) {
  components.push({ lines: [line], sourceIds, kind: 'component' });
}
function emitConnect(line: string, sourceIds: string[]) {
  composition.push({ lines: [line], sourceIds, kind: 'connect' });
}
// ... etc per kind

return [
  { name: 'Imports', subBlocks: imports },
  { name: 'Resources', subBlocks: resources },
  { name: 'Components', subBlocks: components },
  { name: 'Composition', subBlocks: composition },
  { name: 'Main', subBlocks: main },
];
```

**Worked example for D-02 (Composition):**

```ts
// Single connect() — sourceIds = [source-node, target-node]
emitConnect(
  `    connect(${sourcePath}, ${targetPath}),`,
  [edge.source, edge.target],
);

// fuel_assembly helper — sourceIds = ALL CACs + HD it consumes
emitHelper({
  lines: [
    `# Thermal assembly (auto-detected: fuel_assembly)`,
    `@named ${asm.assemblyName} = fuel_assembly([${chs}], [${pls}]; ...)`,
  ],
  sourceIds: [asm.hdNodeId, ...asm.cacEntries.map(c => c.nodeId)],
  kind: 'helper',
});

// Single anchor inside eqs[] — sourceIds = [consumer-node]
composition.push({
  lines: [`    ${prefix}${data.instanceName}.${entry.portField} ~ ${formatReal(entry.value)},`],
  sourceIds: [nodeId],
  kind: 'anchor',
});
```

**Where Composition section starts/ends:** The current `eqs = [` / `]` block straddles connect lines + BC bindings + anchors. Phase 66 keeps these inside the `Composition` section (each one its own sub-block); the literal `eqs = [` and `]` lines are emitted as small zero-`sourceIds` framing sub-blocks of `kind: 'comment'`.

**Where Main section starts:** Begins at the `@named sys = ...` / `@named sys = compose_systems(...)` line (`codeGenerator.ts:1433` or `:1438`), runs through `ssys = mtkcompile(sys)` and the solve-stub comments. One sub-block, `sourceIds = []`, per D-04.

**Pitfalls:**
- Today's `lines.push("")` blank-line emits within each section must be DROPPED from the new emit sites and re-injected by `serializeSections` at the section/sub-block boundary level (D-12 owns "exactly one blank line between sub-blocks within a section"). Mixing blank-line emit inside sub-blocks and blank-line emit between sub-blocks produces double blanks.
- The `# WARNING: ...` lines today are interleaved with the resource line they warn about (e.g., `codeGenerator.ts:816`). The cleanest pattern: emit the warning as its own preceding line WITHIN the same sub-block (`lines: ['# WARNING: ...', '${g.name} = PipeGeometry_rectangular(...)']`, `sourceIds: [g.uuid]`). Hovering the warning highlights the same resource as the body — correct behavior.
- The BC pre-eqs section currently lives between Components and Composition (`codeGenerator.ts:1163`). Decide explicitly: does it become a sub-block under **Resources** (BC profile-vars conceptually ARE resources for downstream eqs) or under **Composition** (it's an eqs prelude)? Recommendation: **Resources** (D-03 already lists "Each Fluid declaration (when added) is one sub-block" — BC profile-vars fit the same shape: pre-eqs declarations consumed downstream). Each item's `sourceIds = [consumerNode.id]`. The planner can flip this if Composition feels more natural; the user-visible output is unchanged either way.

### Pattern 2: `serializeSections(CodeSection[]) -> string` adapter

**Recommended location:** Named export in `gui/src/lib/codeGenerator.ts` (NOT a sibling file). Rationale: every test file already imports `generateCode` from `./codeGenerator`; adding `serializeSections` as a second named export means a one-line change per test (`import { generateCode, serializeSections } from "../codeGenerator"`), no new import path discovery. Keeps the public API surface co-located.

**Recommended shape:**

```ts
export function serializeSections(sections: CodeSection[]): string {
  const parts: string[] = [];
  for (let s = 0; s < sections.length; s++) {
    const section = sections[s];
    if (section.subBlocks.length === 0) continue;  // Skip empty Resources when no resources

    // Section header (D-12): `# === <Section Name> ===` replaces dashed blocks
    parts.push(`# === ${section.name} ===`);

    for (let b = 0; b < section.subBlocks.length; b++) {
      const sub = section.subBlocks[b];
      for (const line of sub.lines) {
        // D-12: no trailing whitespace
        parts.push(line.replace(/[ \t]+$/, ''));
      }
      // D-12: exactly one blank line between sub-blocks within a section
      if (b < section.subBlocks.length - 1) parts.push('');
    }
    // D-12: exactly one blank line between top-level sections
    if (s < sections.length - 1) parts.push('');
  }
  return parts.join('\n');
}
```

**Test-suite migration without bulk fixture rewrites:** Each of the 5 test files keeps its `generateCode(...)` call but wraps it in `serializeSections`:

```ts
// Before
const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
expect(code).toContain('@named pump1 = Pump(1.0)');

// After (one-line change at the call site)
const code = serializeSections(generateCode(nodes, edges, NO_ANCHORS, mockGetComponent));
expect(code).toContain('@named pump1 = Pump(1.0)');
```

A **codemod-grep alternative** is acceptable: keep `generateCode` returning string by default and add a sibling `generateCodeSections` returning the structured form. But that means two parallel codegen entry points to maintain; CONTEXT.md D-13 commits to the structured output being THE codegen output and the string a derived view. Stick with the rename.

**Fixture drift from D-12:** The five test files currently assert against text that contains `# ----------` dashed-block headers (`codeGenerator.ts:802`, etc.) AND a top-level `# ===...` smoke banner. The D-12 change replaces both with `# === <Section> ===`. Three options for the test files:

1. **Update all string-equality assertions to match the new headers** (recommended; the D-12 floor IS a deliberate output change). The fixture diff is small — maybe ~15 lines across 5 files — and audit-able.
2. **Keep the legacy dashed-block headers as a serialize-mode flag**: `serializeSections(sections, { legacyHeaders: true })`. Tests pass the flag; preview omits it. Rejected — embeds a deprecated path into the new API.
3. **Snapshot tests**: convert string-equality to `toMatchInlineSnapshot`. Vitest can auto-update on first run. Rejected — masks regressions in the comparison.

Pick option 1. The five test files become Plan 02's edit set alongside the codegen refactor.

**Pitfalls:**
- The current `generateCode` includes a top-level `# === Generated by STREAM Composer ===` smoke header (lines 725-731). Decision: emit this as Imports section's FIRST sub-block (or as a separate top-of-file sub-block in a sixth "Header" section). Recommendation: prepend it to Imports as a zero-`sourceIds` comment sub-block; one less section to track.
- Trailing-whitespace strip is cheap (regex per line) but DO NOT strip leading whitespace — indentation inside `eqs[ ... ]` blocks is load-bearing.
- The `if (geometries.length > 0 || hdNodes.length > 0)` guard at `codeGenerator.ts:800` produces NO Resources block at all when both are empty. `serializeSections` must replicate this: if a section's `subBlocks` array is empty, emit NEITHER its header nor its blank line.

### Pattern 3: Smooth scroll-into-view + 1.5s flash for `stream:show-code-for`

**Recommended idiom:**

```tsx
// Inside CodePreview.tsx
const subBlockRefs = useRef<Map<string, HTMLDivElement>>(new Map());  // key: sub-block dom-id
const [flashIds, setFlashIds] = useState<Set<string>>(new Set());

useEffect(() => {
  const handler = (e: Event) => {
    const ce = e as CustomEvent<{ nodeId?: string; nodeIds?: string[] }>;
    const ids = ce.detail.nodeIds ?? (ce.detail.nodeId ? [ce.detail.nodeId] : []);
    if (ids.length === 0) return;

    // Find all sub-blocks whose sourceIds include any target id
    const matches = sections.flatMap((sec, si) =>
      sec.subBlocks
        .map((sb, bi) => ({ sb, domId: `sub-${si}-${bi}` }))
        .filter(({ sb }) => sb.sourceIds.some(id => ids.includes(id))),
    );
    if (matches.length === 0) return;

    // Smooth-scroll the first match; flash all matches
    requestAnimationFrame(() => {
      const firstEl = subBlockRefs.current.get(matches[0].domId);
      if (firstEl) {
        // shadcn ScrollArea uses Radix ScrollAreaPrimitive.Viewport — scrollIntoView
        // walks up to the nearest scrollable ancestor, which IS the viewport.
        firstEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
      setFlashIds(new Set(matches.map(m => m.domId)));
    });
  };
  window.addEventListener('stream:show-code-for', handler);
  return () => window.removeEventListener('stream:show-code-for', handler);
}, [sections]);

// Clear flash after 1.5s
useEffect(() => {
  if (flashIds.size === 0) return;
  const t = setTimeout(() => setFlashIds(new Set()), 1500);
  return () => clearTimeout(t);
}, [flashIds]);
```

**Why `requestAnimationFrame` (not `useLayoutEffect`):** The dispatcher (`NodeContextMenu.tsx:36`) already toggles `bottomPanelOpen = true` BEFORE dispatching the event. But `BottomPanel.tsx:11` short-circuits on closed-panel → `CodePreview.tsx` only mounts after the state flips. So the event-fire sequence is: (1) state set, (2) event dispatched, (3) render commits, (4) `CodePreview` mounts and registers its listener. The listener registration happens AFTER the event fires — the event is lost.

**Two fixes; pick one cleanly:**

a) **Move the listener up the tree** to a component that's mounted regardless of bottom-panel state — `App.tsx` is the natural host. The listener buffers the latest event into a `pendingShowCodeFor: string | null` Zustand field; `CodePreview` consumes-and-clears on mount. Pro: zero race conditions. Con: adds a one-shot store field.

b) **Make the dispatcher async-aware**: have `NodeContextMenu.tsx` queue the event in a `pendingShowCodeFor` store field rather than dispatch a CustomEvent; `CodePreview` reads-and-clears via `useEffect`. Pro: pure store flow, no event-bus race. Con: changes Phase 65 code (D-14 says don't).

**Recommendation: (a).** Add a `useShowCodeFor` hook installed in `App.tsx` that writes to a `pendingShowCodeFor: string[] | null` ephemeral store field; `CodePreview` reads `useStore(s => s.pendingShowCodeFor)`, runs the scroll/flash effect when non-null, then clears. The hook listens globally; the consumer reads when ready.

**`scrollIntoView` inside shadcn ScrollArea:** The shadcn ScrollArea (vendored at `gui/src/components/ui/scroll-area.tsx`) wraps Radix's `ScrollAreaPrimitive.Root` → `Viewport` → children. The Viewport has `data-slot="scroll-area-viewport"`. `Element.scrollIntoView()` walks up to the nearest scrollable ancestor (the Viewport), so calling it on a sub-block `<div>` inside the existing `<ScrollArea>` works without needing to find the viewport manually. **No extra plumbing needed.**

**Pitfalls:**
- `scrollIntoView({ behavior: 'smooth' })` is NOT implemented by jsdom (vitest default). In component tests, spy/mock it: `vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(() => {});` and assert it was called with the expected args.
- React 18 StrictMode double-mounts effects in development. The event-listener cleanup MUST run cleanly — the recommended `addEventListener` + return `removeEventListener` pattern handles this. The double-fire is a non-issue because the handler reads from `pendingShowCodeFor` (idempotent under repeat).
- Triple-click line-select in the panel fires three rapid synthetic `click` events; CONTEXT.md D-14 says this nets to "pin state unchanged." Our click handler must use `e.detail` (the native click-count) and bail out if `e.detail > 1`. Otherwise three rapid clicks would pin → unpin → pin.

### Pattern 4: Zustand ephemeral slice shape

**Recommended shape — single `useStore` slice (NOT a separate `useCodePanelStore`):**

```ts
// In gui/src/store/useStore.ts, alongside `errorNodeIds: Set<string>`
hoveredSourceIds: Set<string>;
pinnedSourceIds: Set<string>;
pendingShowCodeFor: string[] | null;  // see Pattern 3

setHoveredSourceIds: (ids: string[]) => void;
clearHoveredSourceIds: () => void;
togglePinnedForSubBlock: (subBlockIds: string[]) => void;
clearPinnedSourceIds: () => void;
consumePendingShowCodeFor: () => string[] | null;
```

**Rationale — single store wins:**
- `StreamNode.tsx` already subscribes to `useStore` for `nodeData`, `errorNodeIds`, `bcMode`, `anchors`, `nodes`, `edges`. Splitting hover/pin into a second store means StreamNode subscribes to TWO stores and the React reconciler can't batch updates across them — flicker risk.
- The Set mutation gotcha (Zustand shallow equality misses in-place Set mutations) is the same in both stores; no benefit to splitting.
- The Phase 65-14 `subscribeWithSelector` middleware is already installed on the single `useStore`. Adding a second store would either need the same middleware (duplicate boilerplate) or skip it (inconsistent).

**Set mutation discipline (load-bearing — easy to get wrong):**

```ts
// CORRECT — fresh Set every mutation
setHoveredSourceIds: (ids) =>
  set({ hoveredSourceIds: new Set(ids) }),

togglePinnedForSubBlock: (subBlockIds) =>
  set((s) => {
    const next = new Set(s.pinnedSourceIds);
    // CONTEXT D-10: any overlap → remove all of this sub-block's ids
    const anyPinned = subBlockIds.some(id => next.has(id));
    if (anyPinned) {
      for (const id of subBlockIds) next.delete(id);
    } else {
      for (const id of subBlockIds) next.add(id);
    }
    return { pinnedSourceIds: next };
  }),

// WRONG — would silently miss re-renders
// set((s) => { s.pinnedSourceIds.add(id); return s; });  // NEVER DO THIS
```

**StreamNode subscription pattern (re-render scope):** The naive `useStore(s => s.hoveredSourceIds.has(myId))` returns a primitive boolean → safe re-render. Every node re-evaluates its selector on every Set mutation, but the React commit only re-renders nodes whose selector return value changed (Zustand auto-uses `Object.is` for primitive returns). So toggling one ID in a 200-node canvas re-renders **at most 2 nodes** (the one being added/removed), not 200. This is identical to the existing `hasAnchor` / `hasBCError` pattern (StreamNode.tsx:174, 317).

```tsx
// Inside StreamNode component
const isHovered = useStore(useCallback((s) => s.hoveredSourceIds.has(id), [id]));
const isPinned = useStore(useCallback((s) => s.pinnedSourceIds.has(id), [id]));
const hasHoverRing = isHovered || isPinned;
```

**`projectIO.ts` exclusion:** Phase 66 needs ZERO changes to `projectIO.ts`. The serialize signature (`gui/src/lib/projectIO.ts:123`) takes specific args (`modelOptions`, `resources`, `nodes`, `edges`, `anchors`, `activeLeftTab`, `activeLayer`, `snapToGrid`) — it does NOT spread the entire store. Adding new store fields automatically excludes them from `.scp`. Same pattern as existing ephemerals (`bottomPanelOpen`, `bottomPanelHeight`, `interactiveLocked`, `errorNodeIds`, `validationResult`) which are also unmentioned in `projectIO.ts`. **Verified by grep: only `snapToGrid`, `currentFilePath`-via-store-IO, `activeLayer`, and `activeLeftTab` appear in projectIO; nothing else from the store.**

### Pattern 5: CustomEvent listener lifecycle in React

**Recommended pattern (in the `useShowCodeFor` hook installed in `App.tsx`):**

```tsx
// gui/src/hooks/useShowCodeFor.ts (new file)
import { useEffect } from "react";
import useStore from "@/store/useStore";

interface ShowCodeForDetail {
  nodeId?: string;
  nodeIds?: string[];
}

export function useShowCodeFor() {
  useEffect(() => {
    const handler = (e: Event) => {
      const ce = e as CustomEvent<ShowCodeForDetail>;
      const ids = ce.detail.nodeIds ?? (ce.detail.nodeId ? [ce.detail.nodeId] : []);
      if (ids.length === 0) return;
      useStore.getState().setPendingShowCodeFor(ids);
    };
    window.addEventListener("stream:show-code-for", handler as EventListener);
    return () => window.removeEventListener("stream:show-code-for", handler as EventListener);
  }, []);
}
```

```tsx
// In App.tsx — install the listener once at app root
function AppShell({ ... }) {
  useShowCodeFor();
  // ... rest of App
}
```

**Why the handler MUST be cast to `EventListener` for removeEventListener:** TypeScript treats the typed-CustomEvent handler signature differently from the broad `EventListener` type. Without the cast, `removeEventListener` is called with a different reference than `addEventListener` got, and cleanup silently fails. This is the most common HMR-induced listener leak pattern.

**Handler reference stability:** The handler is defined inside `useEffect`'s body, so it's a fresh function each effect run. With an empty deps array, the effect runs once on mount and the same handler reference is captured and removed on unmount. Safe.

**HMR double-mounts (Vite dev-server):** When `App.tsx` is HMR-edited, React StrictMode + Vite remount triggers `useEffect` cleanup→re-run. The cleanup uses the same captured handler reference, so removal succeeds. Safe.

**TypeScript typing of CustomEvent payloads:** Browser DOM types declare `addEventListener` with `EventListener` (no generics). The cleanest way is the cast pattern above. An alternative is module augmentation:

```ts
declare global {
  interface WindowEventMap {
    'stream:show-code-for': CustomEvent<ShowCodeForDetail>;
  }
}
```

This makes `window.addEventListener('stream:show-code-for', handler)` infer `e: CustomEvent<ShowCodeForDetail>` without casts. **Recommended** if no other file already declares the event in `WindowEventMap`. Check `grep -rn "WindowEventMap" gui/src/` before adding — Phase 65 may have already done this for `stream:focus-instance-name`. (Grep shows Phase 65 did NOT add module augmentation, so Phase 66 can be the first.)

### Pattern 6: Esc key coordination with Phase 65

**Existing Esc handler (`CanvasPanel.tsx:275-289`):** Already global on `window` keydown. Checks for input focus before clearing selection. The handler is **scoped to canvas selection clear** — it does NOT touch any code-panel state.

**Recommended Phase 66 integration: add a SECOND keydown handler in `App.tsx`** (or in the `useShowCodeFor` hook above — same lifetime). The two handlers run in DOM-event-listener registration order; both can fire on the same Esc without one preempting the other (CanvasPanel's handler does NOT call `stopPropagation`). Both are idempotent (clearing already-empty state is a no-op set call).

```tsx
useEffect(() => {
  const handler = (e: KeyboardEvent) => {
    if (e.key !== 'Escape') return;
    // Input-focus guard — match the CanvasPanel pattern (canvas selection
    // clear and pin-clear should both bail when the user is editing text)
    const target = e.target as HTMLElement;
    if (
      target instanceof HTMLInputElement ||
      target instanceof HTMLTextAreaElement ||
      target instanceof HTMLSelectElement ||
      target.isContentEditable
    ) return;
    useStore.getState().clearPinnedSourceIds();
  };
  window.addEventListener('keydown', handler);
  return () => window.removeEventListener('keydown', handler);
}, []);
```

**Phase 65 Plan 10 (`gui-redesign/65-10-esc-input-focus-guard-PLAN.md`)** specifically added an input-focus guard to `SidebarPanel.tsx`'s Esc handler. Phase 66 reuses the same predicate verbatim. The two handlers don't conflict — they clear different state on the same key.

**Priority / order:** With three independent Esc-handlers on `window` (CanvasPanel, SidebarPanel, App-for-pin-clear), the order in which they fire depends on `addEventListener` registration order. None of them call `stopPropagation`, so all three run on every Esc. Each handler is internally idempotent. **Safe.**

**Pitfalls:**
- AutoRecover modal (`AutoRecoverRestoreModal.tsx:73`) calls `onEscapeKeyDown={(e) => e.preventDefault()}` to stop Esc from closing the modal. That call is on the Radix Dialog event, NOT on the native `window` `keydown`. The window-level pin-clear handler still fires when the modal is open. Acceptable — clearing pins behind a modal is harmless.
- Radix ContextMenu / DropdownMenu (used by Phase 65's right-click menus) traps Esc to close themselves. When a menu is open, the menu's internal handler runs first (Radix captures at the portal root), `stopPropagation`s, and our window handler doesn't fire. Also acceptable.

### Pattern 7: Native text-selection preservation

**Active risk surface:** The sub-block wrapper `<div>` mounts inside a `<pre><code>`. If the wrapper sets `select-none` (Tailwind class for `user-select: none`), or calls `e.preventDefault()` in `onMouseDown`, drag-to-select breaks across that sub-block.

**Pre-audited Tailwind `select-none` usages in the GUI tree:**
- `gui/src/components/ui/scroll-area.tsx:42` — `select-none` on the scrollbar thumb (NOT on viewport content). Safe.
- `gui/src/components/ui/context-menu.tsx:76, 159, 213, 231, 256` — `select-none` on menu items. Safe.
- `gui/src/components/Toolbar.tsx:67, 87` — `select-none` on small UI labels. Safe.
- **No `select-none` is applied inside `<pre><code>` content.**

**`preventDefault` in `onMouseDown` risk:** A naive sub-block click handler that calls `e.preventDefault()` on `mousedown` would suppress the browser's native click-vs-drag discrimination, breaking text selection. **Use `onClick` only** — the browser handles click-vs-drag natively. Verified by Phase 65 D-14 recommendation: "Default expectation is `onClick`." If a planner finds a drag-fires-click bug during implementation, the fix is to compare `e.detail` (click-count) or measure `e.clientX/Y` against the mousedown event — NOT to add `preventDefault`.

**Recommended regression test:**

```tsx
it('sub-block wrappers do not set user-select: none', () => {
  const { container } = render(<CodePreview />);  // mounted with mock store state
  const subBlocks = container.querySelectorAll('[data-sub-block]');
  expect(subBlocks.length).toBeGreaterThan(0);
  for (const el of subBlocks) {
    const cs = getComputedStyle(el);
    expect(cs.userSelect).not.toBe('none');
  }
});
```

**Caveat:** jsdom's `getComputedStyle` does not resolve Tailwind utility classes — it returns the computed value from inline styles and matched `<style>` blocks only. A `className="select-none"` won't show up in jsdom's computed result. Two fixes:

1. Assert at the class level: `expect(el.className).not.toContain('select-none')`.
2. Or render with the Vite-built CSS injected (slower, more reliable).

Pick (1) for the regression test. It's a "shape lint" not a "computed-style lint" but it catches the only realistic regression vector (a Tailwind class slipping in).

### Pattern 8: Toggle-with-confirmation 1.5s state on Copy button

**Existing pattern reference:** `gui/src/components/resources/ResourceRow.tsx:114-122` uses `useState` + `setTimeout` + cleanup-via-effect-return for the rename-mode focus pattern. Adapted shape for Copy:

```tsx
const [copied, setCopied] = useState(false);

useEffect(() => {
  if (!copied) return;
  const t = setTimeout(() => setCopied(false), 1500);
  return () => clearTimeout(t);
}, [copied]);

async function handleCopy() {
  await navigator.clipboard.writeText(serializeSections(sections));
  setCopied(true);
}

return (
  <Button size="sm" variant="outline" disabled={nodes.length === 0} onClick={handleCopy}>
    {copied
      ? <><Check className="h-4 w-4 mr-1" /> Copied</>
      : <><Copy className="h-4 w-4 mr-1" /> Copy</>
    }
  </Button>
);
```

**Why the useEffect-driven timer (not raw `setTimeout` inside `handleCopy`):** If the user navigates away (closes the bottom panel, which unmounts `BottomPanel.tsx`) within 1.5s of clicking Copy, the raw `setTimeout` would call `setCopied(false)` on an unmounted component → React 18 warning + memory leak. The effect's cleanup function clears the timer on unmount; safe.

**Rapid double-click handling:** A second `handleCopy` call before the first timer fires writes clipboard again (intended) and sets `copied: true` again (re-triggering the effect with a fresh timer). Same effect as a single click. Acceptable.

**Pitfalls:**
- `navigator.clipboard.writeText` returns a Promise — must be `await`ed or the button shows "Copied" before the actual clipboard write succeeds. In Tauri's webview, the call is synchronous-fast (no permission prompt — webview has implicit clipboard permission), so a failed `await` is rare. Still: `await` it, and catch errors to fall back to a "Copy failed" state if needed. Optional.

### Pattern 9: Hover-ring CSS class strategy in StreamNode

**Recommended subscription:** Per-node primitive-boolean selector, matching the existing `hasAnchor` / `hasBCError` pattern at `StreamNode.tsx:174, 317`. See Pattern 4 above for the exact shape.

**Re-render fanout analysis:** With 200 nodes on canvas, a single hover toggle (e.g., `setHoveredSourceIds(['n42'])`) replaces the Set reference. All 200 node selectors re-evaluate. The selectors that returned `false` on the prior tick AND return `false` now (198 nodes) get `Object.is(prev, next) === true` and skip re-render. The two nodes whose membership flipped (`n42_prev_state` and `n42` if the previous hover was different) re-render. **Net: 2 nodes touched per hover transition. Acceptable.**

**CSS class name + Phase 71/68 forward-compat:**

- Phase 71 owns `red ring` for validation. Currently the validation ring is realized via `errorNodeIds` + a Tailwind class chain inside `StreamNode.tsx` (grep `errorNodeIds.has(id)` at `StreamNode.tsx:309` to find it). Phase 71 will likely formalize this as a `stream-node--invalid` class or similar.
- Phase 68 owns the four-layer dim/hide system. Phase 66 needs the hover to "un-dim" a node on a hidden layer — but Phase 68 hasn't shipped, so the dim mechanism doesn't exist yet. Treat the layer-aware un-dim as a Phase 68-side concern: Phase 66 emits the hover-ring class regardless of layer state; if/when Phase 68 lands a dim mechanism, that phase explicitly checks `hoveredSourceIds`/`pinnedSourceIds` to suppress dimming. CONTEXT.md D-05 acknowledges this ("layer-aware in the sense that highlighting an off-layer node briefly un-dims it, but Phase 66 does NOT change the four-layer taxonomy").

**Recommended class name + CSS variable convention:**

- Class name: `stream-node--code-hover` (when sub-block is hovered) and `stream-node--code-pinned` (when pinned). Two classes so Phase 72's tuning can give them different visual styles if desired (e.g., pin is slightly heavier).
- CSS variable: `--stream-code-hover-ring-color: oklch(0.65 0.18 220)` (placeholder accent — Phase 72 tunes). Define in `gui/src/index.css`.
- **Does NOT collide** with Phase 71's likely `stream-node--invalid` or Phase 68's likely `stream-node--layer-dimmed` / `stream-node--layer-hidden`. The `--code-` infix scopes the namespace.

**StyleS placement:** Add the two class rules to `gui/src/index.css` (same file Phase 65-12 appended marquee CSS to). One small rule block, ~10 lines.

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

`outline` chosen over `border` so it does NOT contribute to the node's box dimensions (which Phase 64 autoflip uses to compute handle positions). `outline-offset: 2px` keeps the ring visually distinct from the existing 2px selection ring (which is the React Flow default `box-shadow` on `.react-flow__node-streamNode.selected`).

### Pattern 10: vitest test surface

**Structured-output unit tests:**

```ts
// New file: gui/src/lib/__tests__/codeGenerator.sections.test.ts
import { generateCode } from "../codeGenerator";

describe("generateCode returns CodeSection[] with source tracking", () => {
  it("emits one Composition sub-block per connect() with both endpoint UUIDs", () => {
    const sections = generateCode([pump, channel], [edge_p_to_c], NO_ANCHORS, mockGetComponent);
    const composition = sections.find(s => s.name === 'Composition')!;
    const connect = composition.subBlocks.find(sb => sb.kind === 'connect');
    expect(connect).toBeDefined();
    expect(connect!.lines).toEqual(['    connect(pump1.port_out, ch1.port_in),']);
    expect(connect!.sourceIds.sort()).toEqual(['ch1-uuid', 'pump1-uuid'].sort());
  });

  it("emits one Components sub-block per @named with the node's UUID", () => {
    const sections = generateCode([pump], [], NO_ANCHORS, mockGetComponent);
    const components = sections.find(s => s.name === 'Components')!;
    expect(components.subBlocks).toHaveLength(1);
    expect(components.subBlocks[0].sourceIds).toEqual(['pump1-uuid']);
  });

  it("emits Imports as a single sub-block with no sourceIds", () => {
    const sections = generateCode([pump], [], NO_ANCHORS, mockGetComponent);
    const imports = sections.find(s => s.name === 'Imports')!;
    expect(imports.subBlocks).toHaveLength(1);
    expect(imports.subBlocks[0].sourceIds).toEqual([]);
  });

  it("emits one Resources sub-block per Geometry with the geometry UUID", () => {
    const resources: CodegenResources = { geometries: { 'g1': { uuid: 'g1', name: 'g1', kind: 'rectangular', params: { L: 1, W: 0.1, H: 0.05 } } }, powerShapes: {}, fluids: {} };
    const sections = generateCode([], [], NO_ANCHORS, mockGetComponent, resources);
    const resSec = sections.find(s => s.name === 'Resources')!;
    const geomSub = resSec.subBlocks.find(sb => sb.kind === 'resource');
    expect(geomSub!.sourceIds).toEqual(['g1']);
  });
});
```

**Serialize round-trip test (Plan 02):**

```ts
it("serializeSections produces byte-equal output to the pre-D-12 generator for an existing fixture", () => {
  const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
  const serialized = serializeSections(sections);
  // After updating the fixture for D-12 headers, this matches:
  expect(serialized).toContain('# === Components ===');
  expect(serialized).toMatch(/@named pump1 = Pump\(1\.0\)\n\n@named ch1/);  // one blank line between sub-blocks
});
```

**Integration test for `stream:show-code-for`:**

```tsx
it("opens panel + scrolls + flashes when stream:show-code-for fires", async () => {
  vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(() => {});
  const { container } = render(<App />);
  // Seed store with a node
  act(() => useStore.getState().addNode('Pump', { x: 0, y: 0 }));
  const nodeId = useStore.getState().nodes[0].id;

  act(() => {
    window.dispatchEvent(new CustomEvent('stream:show-code-for', { detail: { nodeId } }));
  });

  // Panel opens via dispatcher (Phase 65 NodeContextMenu — already shipped)
  // Phase 66 listener fires; scrollIntoView called
  await waitFor(() => {
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith(
      expect.objectContaining({ behavior: 'smooth', block: 'center' })
    );
  });

  // Flash class present
  const flashed = container.querySelector('[data-flash="true"]');
  expect(flashed).toBeInTheDocument();
});
```

**Regression test (text-selection preserved):**

```ts
it("no sub-block wrapper has select-none class", () => {
  const { container } = render(<CodePreview />);
  const wrappers = container.querySelectorAll('[data-sub-block]');
  expect(wrappers.length).toBeGreaterThan(0);
  for (const el of wrappers) {
    expect(el.className).not.toContain('select-none');
  }
});
```

### Pattern 11: `exportCode.ts` shared util shape

```ts
// gui/src/lib/exportCode.ts (new file)
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import useStore from "@/store/useStore";

/**
 * Run the validation gate, prompt for save location via Tauri dialog, write
 * the file. Returns true on successful write, false on user-cancel or
 * validation failure. The validation failure surfaces via the existing
 * useStore.validationResult dialog (no new UX needed).
 */
export async function exportCodeToFile(code: string): Promise<boolean> {
  const result = useStore.getState().validateAndGate();
  if (!result.valid) return false;  // Existing dialog surfaces via validationResult state

  const filePath = await save({
    defaultPath: deriveDefaultFilename(),
    filters: [{ name: "Julia files", extensions: ["jl"] }],
  });
  if (!filePath) return false;  // user cancelled

  await writeTextFile(filePath, code);
  return true;
}

function deriveDefaultFilename(): string {
  // Match existing Toolbar.tsx behavior (defaultPath: "system.jl"). A future
  // enhancement could derive from modelOptions.name, but D-18 says preserve
  // existing behavior — don't expand scope here.
  return "system.jl";
}
```

**Migration:** `Toolbar.tsx:49-60`'s `handleExport` becomes `await exportCodeToFile(code)`. `BottomPanel.tsx` calls the same util. Both pass the same store-derived `code` (or in Phase 66's case, `serializeSections(sections)`).

**Pitfalls:**
- The Tauri `save` dialog returns `null` (not `undefined`) when the user cancels. The check is `if (!filePath)` which handles both. **Verified at `Toolbar.tsx:57`.**
- The validation gate (`validateAndGate`) WRITES to `useStore.validationResult` — that's how the existing validation dialog appears. The util MUST call it (not bypass it), even though the result is also returned. Side-effect is load-bearing.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Syntax highlighting | Custom tokenizer | Plain `<pre><code>` (locked by D-13) | Locked out; not even a "could revisit." |
| Markdown-style code blocks | Custom renderer | Plain `<div>` per sub-block | KISS; CONTEXT.md D-13 says each sub-block is its own `<div>` (or `<pre>`) inside the section. |
| Drag-vs-click discrimination | Custom mouse-tracking | Browser-native `onClick` + `e.detail` | Phase 65 confirmed this works; CONTEXT.md "click-handler shape" recommends default `onClick`. |
| Code formatting pipeline | Custom AST transform | Hand-rolled string emit at floor only (D-12) | Phase 72 owns richer formatting. Don't pre-empt. |
| Clipboard polyfill | `clipboard-polyfill` lib | `navigator.clipboard.writeText` | Tauri webview supports it natively. Used in Phase 65 clipboard work. |
| Event-bus abstraction | RxJS / custom emitter | `window.dispatchEvent` + `CustomEvent` + `addEventListener` | Phase 65 already uses this pattern (`stream:focus-instance-name`, `stream:show-code-for`); consistency wins. |
| Scrollable-ancestor finder | Custom walk | Element.scrollIntoView() walks for you | Native DOM behavior is correct. |
| Set-based selector memoization | Custom equality fn | Zustand primitive-boolean selectors | Existing pattern; bulletproof. |

**Key insight:** Phase 66 has nearly zero genuine engineering work — every problem it solves has an established codebase pattern (anchor indicator subscription = hover-ring subscription; ResourceRow setTimeout = Copy button confirmation; Phase 65 dispatch = Phase 66 consume). The phase's risk is mechanical (refactor errors in the 80+ emit sites), not architectural.

## Runtime State Inventory

Phase 66 is a forward-only feature add — no rename, no migration, no schema change to persisted state. **N/A — phase introduces only new ephemeral state, never touches stored data.**

Confirmation by category:
- **Stored data:** None. `.scp` v2.0 schema unchanged.
- **Live service config:** None. No external services.
- **OS-registered state:** None. No OS-level registrations.
- **Secrets/env vars:** None.
- **Build artifacts:** New imports of `serializeSections` / `exportCode` add to the existing Vite bundle naturally — no clean-rebuild needed (HMR handles it).

## Common Pitfalls

### Pitfall 1: Set-reference equality in Zustand selectors
**What goes wrong:** In-place Set mutation (`s.hoveredSourceIds.add(id)`) doesn't change the Set reference; Zustand's shallow equality returns `true`; no re-render fires; the canvas hover-ring never appears.
**Why:** Zustand uses `Object.is` for state-slice equality. Mutating a Set in place keeps the same reference.
**How to avoid:** Always emit `new Set(prevSet)` in setters, then mutate the new Set, then `set({ ... })` with it. See Pattern 4 code shape.
**Warning signs:** Hovering a sub-block does nothing visible on canvas, even though `useStore.getState().hoveredSourceIds.size > 0` in DevTools.

### Pitfall 2: Event listener registered before dispatcher fires
**What goes wrong:** `BottomPanel.tsx:11` short-circuits when `bottomPanelOpen === false`. So `CodePreview` is unmounted when the bottom panel is closed. `NodeContextMenu.tsx:36-40` opens the panel THEN dispatches the event in the SAME tick — but the listener inside the not-yet-mounted `CodePreview` doesn't exist yet.
**Why:** React renders are async; the `bottomPanelOpen = true` set call queues a re-render, doesn't synchronously mount `CodePreview`. The dispatch fires before the listener registers.
**How to avoid:** Install the listener at `App.tsx` level via a `useShowCodeFor` hook that ALWAYS runs, buffering the event into a `pendingShowCodeFor` store field. `CodePreview` consumes on mount. See Pattern 5.
**Warning signs:** First right-click "Show generated Julia code" after app start does nothing visible; second right-click works fine (because the panel is already open and `CodePreview` is mounted from the first attempt).

### Pitfall 3: Blank-line double-emit between sub-blocks and sections
**What goes wrong:** Current `lines.push("")` calls inside `generateCode` (`codeGenerator.ts:752, 920, 988, 1044, 1244, 1415, 1442`) become DUPLICATES if `serializeSections` ALSO emits a blank line between sub-blocks.
**Why:** Migration has to delete the old `lines.push("")` calls site-by-site AND defer blank-line emit to `serializeSections`. Easy to miss one.
**How to avoid:** Grep for `lines.push("")` in `codeGenerator.ts` AFTER the refactor — there should be **zero remaining** (`grep -n 'lines.push(""' codeGenerator.ts | wc -l` must return 0). All blank lines come from `serializeSections`.
**Warning signs:** Existing test fixtures with `\n\n\n` (triple newline) where they used to have `\n\n` (double newline). Trailing-whitespace strip won't catch this; the assertion will fail with a diff showing the extra blank.

### Pitfall 4: `scrollIntoView` smooth behavior absent in jsdom
**What goes wrong:** vitest's jsdom doesn't implement `scrollIntoView({ behavior: 'smooth' })`. Calling it doesn't error, but the test can't observe the scroll position. Component tests that assert "scroll happened" silently pass even when the production code path is broken.
**How to avoid:** Use `vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(() => {})` AND assert it was called with the expected args (see Pattern 10 integration test).
**Warning signs:** A test passes locally but the user can't see the panel scroll when right-clicking a node in the live app.

### Pitfall 5: Triple-click selecting a code line toggles pin state
**What goes wrong:** Native triple-click selects a paragraph (one line of code in `<pre>`). This fires THREE rapid `click` events on the sub-block wrapper. If our handler is a naive toggle, the pin state goes: unpinned → pinned → unpinned → pinned. Net: pinned (visible state changed despite user intending to text-select).
**Why:** CONTEXT.md D-14 calls this out: "Triple-click line-select fires three rapid `click` events which net out to 'pin state unchanged' — accepted minor edge case." But "net out to unchanged" only holds when click-count is checked.
**How to avoid:** Check `e.detail` (browser's click-count) and bail when `e.detail > 1`:
```tsx
function handleSubBlockClick(e: React.MouseEvent, sb: CodeSubBlock) {
  if (e.detail > 1) return;  // double / triple click — let native text-select run
  useStore.getState().togglePinnedForSubBlock(sb.sourceIds);
}
```
**Warning signs:** User double-clicks a `connect(...)` line to select it, sees the canvas hover-ring pop on and off, complains the panel "fights" them.

### Pitfall 6: `removeEventListener` reference mismatch (HMR leak)
**What goes wrong:** Defining the handler inline in `useEffect`'s deps array without storing it locally first → the cleanup function captures a different reference than `addEventListener` got → listener is never removed. After multiple HMR reloads, multiple stale listeners are bound.
**How to avoid:** Always capture the handler into a const inside the effect body (Pattern 5 code shape). Even better: cast to `EventListener` consistently so TypeScript doesn't synthesize wrapper functions silently.
**Warning signs:** After 10+ hot-reloads in dev, a single right-click "Show generated Julia code" triggers 10+ scrolls / flashes.

### Pitfall 7: `Object.fromEntries(sections)` losing order
**What goes wrong:** Someone "helpfully" converts `CodeSection[]` to a `Record<CodeSectionName, CodeSubBlock[]>` thinking it's tidier. Section order is now non-deterministic (well, deterministic per V8, but undocumented).
**How to avoid:** Keep the array shape. The Section order Imports → Resources → Components → Composition → Main is load-bearing and matches the existing string output.
**Warning signs:** Test fixtures occasionally fail on different Node versions or after a TypeScript major-version bump.

## Code Examples

### Sub-block dom-id stable convention

```ts
function subBlockDomId(sectionIdx: number, subBlockIdx: number): string {
  return `sub-${sectionIdx}-${subBlockIdx}`;
}
```

Stable across re-renders (sections array is recomputed but ordering is deterministic). The `useShowCodeFor` lookup uses this to find the scroll target.

### CodePreview.tsx rewrite skeleton

```tsx
export default function CodePreview() {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const anchors = useStore((s) => s.anchors);
  const resources = useStore((s) => s.resources);
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);
  const pendingShowCodeFor = useStore((s) => s.pendingShowCodeFor);
  const consumePending = useStore((s) => s.consumePendingShowCodeFor);

  const sections = useMemo(
    () => generateCode(nodes, edges, { anchors }, getComponent, resources, { bcMode, bcSymmetric }),
    [nodes, edges, anchors, resources, bcMode, bcSymmetric],
  );

  const subBlockRefs = useRef<Map<string, HTMLDivElement>>(new Map());
  const [flashIds, setFlashIds] = useState<Set<string>>(new Set());

  // Consume pendingShowCodeFor on mount / change — scroll + flash
  useEffect(() => {
    if (!pendingShowCodeFor || pendingShowCodeFor.length === 0) return;
    const matches: string[] = [];
    sections.forEach((sec, si) => sec.subBlocks.forEach((sb, bi) => {
      if (sb.sourceIds.some(id => pendingShowCodeFor.includes(id))) {
        matches.push(subBlockDomId(si, bi));
      }
    }));
    if (matches.length === 0) { consumePending(); return; }
    requestAnimationFrame(() => {
      const first = subBlockRefs.current.get(matches[0]);
      first?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      setFlashIds(new Set(matches));
      consumePending();
    });
  }, [pendingShowCodeFor, sections, consumePending]);

  useEffect(() => {
    if (flashIds.size === 0) return;
    const t = setTimeout(() => setFlashIds(new Set()), 1500);
    return () => clearTimeout(t);
  }, [flashIds]);

  return (
    <ScrollArea className="h-full">
      <pre className="font-mono text-[13px] leading-[1.6] whitespace-pre overflow-x-auto p-4 bg-muted text-foreground select-text">
        {sections.map((sec, si) => (
          <section key={sec.name}>
            {sec.subBlocks.length > 0 && (
              <h4 className="text-muted-foreground font-semibold mb-1">{`# === ${sec.name} ===`}</h4>
            )}
            {sec.subBlocks.map((sb, bi) => {
              const domId = subBlockDomId(si, bi);
              return (
                <div
                  key={domId}
                  data-sub-block
                  data-flash={flashIds.has(domId) ? 'true' : undefined}
                  ref={(el) => { if (el) subBlockRefs.current.set(domId, el); else subBlockRefs.current.delete(domId); }}
                  className={`block py-0.5 cursor-pointer ${flashIds.has(domId) ? 'bg-sky-500/15 transition-colors' : 'hover:bg-sky-500/5'}`}
                  onMouseEnter={() => useStore.getState().setHoveredSourceIds(sb.sourceIds)}
                  onMouseLeave={() => useStore.getState().clearHoveredSourceIds()}
                  onClick={(e) => {
                    if (e.detail > 1) return;  // Pitfall 5
                    useStore.getState().togglePinnedForSubBlock(sb.sourceIds);
                  }}
                >
                  {sb.lines.map((line, li) => <div key={li}><code>{line || ' '}</code></div>)}
                </div>
              );
            })}
            {si < sections.length - 1 && <div>&nbsp;</div>}  {/* blank line between sections */}
          </section>
        ))}
      </pre>
    </ScrollArea>
  );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat `string` codegen output | `CodeSection[]` with source-UUID tracking | Phase 66 | Enables traceability without breaking the read-only preview contract |
| Inline `handleExport` in `Toolbar.tsx` | Shared `exportCode.ts` util consumed by Toolbar + BottomPanel | Phase 66 D-18 | Single source of truth for validation+save flow |
| `lines.push("")` blank-line emit per section in codegen | Blank lines synthesized by `serializeSections` adapter | Phase 66 D-12 | Centralizes formatting floor; easier Phase 72 expansion |

**Deprecated/outdated:**
- Nothing being deprecated. Phase 66 is purely additive on the data side (new types, new `serializeSections` export) and a UI rewrite that replaces a 34-line component with a richer one. The existing `string`-returning `generateCode` shape goes away — but every consumer migrates in the same plan (Toolbar.tsx, CodePreview.tsx, tests), so no transitional deprecation period is needed (matches the "no back-compat during heavy dev" memory).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Zustand selector with primitive-boolean return re-renders only nodes whose result changed | Pattern 9 | If Zustand actually re-renders all subscribers on Set replacement, hover would trigger 200-node re-render storm. **Mitigation:** Existing `hasAnchor` / `hasBCError` patterns work this way and Phase 64 didn't report perf issues — high confidence. |
| A2 | Phase 65 did not module-augment `WindowEventMap` for `stream:focus-instance-name` / `stream:show-code-for` | Pattern 5 | If it did, Phase 66 redeclaration would be a TS conflict. **Mitigation:** Grep confirmed no `WindowEventMap` in Phase 65 code. |
| A3 | `Element.scrollIntoView()` walks up to the shadcn ScrollArea viewport correctly (it's the nearest scrollable ancestor) | Pattern 3 | If a higher ancestor is scrollable, the wrong viewport scrolls. **Mitigation:** The flexbox layout has `overflow: hidden` on intermediate ancestors; the ScrollArea viewport is the next scrollable parent. Easily verified during execution. |
| A4 | Tauri webview's `navigator.clipboard.writeText` works without permission prompt | Pattern 8 | If Tauri 2 added a permission prompt for clipboard write, Copy could fail silently. **Mitigation:** Phase 65 clipboard work (Plan 04, `gui/src/lib/clipboard.ts`) already uses `navigator.clipboard.writeText` in production without issues. |
| A5 | The 5 existing codegen test files will accept a minimal fixture update for `# === <Section> ===` headers without significant rewrite | Pattern 2 | If many assertions match the old `# -----` headers, the migration is bigger than estimated. **Mitigation:** Grep for `# -----` in the test files; count likely-small (the headers appear ~3x per fixture file, ~15 occurrences total). |
| A6 | Phase 71's red validation ring class will use a different naming convention (`stream-node--invalid`) than the hover ring (`stream-node--code-hover`) | Pattern 9 | Class collision if Phase 71 picked the same name. **Mitigation:** Phase 71 is future work; Phase 66 emits the canonical name first, future phase adapts. |
| A7 | The `# WARNING:` comments emitted today inline with resource lines should be folded into the SAME sub-block as the resource (not a separate one) | Pattern 1 | If kept separate, hovering the warning doesn't highlight the resource. Recommendation is "fold" but planner can flip. |

## Open Questions (RESOLVED)

1. **Should BC pre-eqs sub-blocks live under `Resources` or `Composition`?**
   - What we know: BC profile-var assignments (`ch1_T_wall_left_profile = cosine_T_wall_profile(...)`) are declared BEFORE `eqs = [` and consumed inside the eqs block. They're prelude declarations, conceptually closer to resources than to connections.
   - What's unclear: Whether the user wants them visually grouped with Geometry/PowerShape resources or with the connect/anchor lines.
   - Recommendation: Plan-time decision. Default to **Resources** (matches D-03's "Each Fluid declaration (when added) is one sub-block" framing — pre-eqs declarations ARE resources-like). Flag in plan review.
   - **RESOLVED:** Components (not Resources) — co-locating BC pre-eqs with the `@named` declarations matches `codeGenerator.ts`'s existing emission order (pre-eqs are interleaved with `@named` lines before the `eqs = [` block), so the structural sub-block grouping mirrors the textual emission grouping; overriding the original Resources default avoids reshuffling existing emit-site code. (Locked in Plan 02 Task 1 behavior bullet for Components.)

2. **Where does the top-of-file `# === Generated by STREAM Composer ===` smoke header live?**
   - What we know: Today it's the very first emission (`codeGenerator.ts:725-731`). Pre-imports.
   - What's unclear: Treat as a sixth "Header" section, or as Imports' first sub-block, or drop it entirely (D-12 doesn't list it as required).
   - Recommendation: Fold into Imports as a zero-`sourceIds` `kind: 'comment'` sub-block. Header value preserved; no new section needed.
   - **RESOLVED:** Fold into Imports as a zero-`sourceIds` sub-block — matches Plan 02 Task 1 behavior and avoids inventing a new top-level section just for one header line. (Locked in Plan 02 Task 1 Imports sub-block contract.)

3. **CSS color for the hover/pin ring — does the planner pick a placeholder now, or defer to Phase 72?**
   - What we know: D-05 says "for v1 the planner picks a thin accent-color outline that is unambiguously not the selection ring."
   - What's unclear: Whether "thin accent" should match the existing Hydraulic-layer blue (`#3b82f6` per Toolbar.tsx) or Thermal amber (`#f59e0b`), or pick a totally new accent (sky `#38bdf8`).
   - Recommendation: **sky-400 (`#38bdf8`)** placeholder. Distinct from layer colors (blue/amber), distinct from validation red (Phase 71), distinct from BC dashed-edge orange. Phase 72 re-tunes.
   - **RESOLVED:** sky-400/500 (tailwind) — distinct from selection blue, Hydraulic layer blue, Thermal amber, and Phase 71's validation red; final aesthetic tuning deferred to Phase 72 per CONTEXT.md `## Deferred Ideas`. (Locked in Plan 05 Task 2 StreamNode hover/pin ring class.)

## Environment Availability

Skipped — Phase 66 has no external CLI / runtime / service dependencies beyond what's already running in the Vite/Tauri dev environment.

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a — single-user desktop app, no auth surface |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | partial | The Copy button serializes existing in-memory codegen output to the clipboard; the Export util reuses `validateAndGate` (already in place). No new user input parsing. |
| V6 Cryptography | no | n/a |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Clipboard content tampering | Information disclosure | `navigator.clipboard.writeText` only — never reads from clipboard in Phase 66 |
| Code-injection via generated Julia | Tampering | Codegen output is constructed from typed registry params + validated identifiers (`validateJuliaIdentifier` already in use, `codeGenerator.ts:24`). Phase 66 doesn't add new identifier paths. |
| XSS via sub-block rendering | Tampering | All sub-block content rendered as React text nodes (not `dangerouslySetInnerHTML`). Strings from `sb.lines` are escaped by React automatically. |

**No new security surface introduced by Phase 66.** The phase reads existing store state, transforms it, renders as text. No new file paths, no new IPC channels, no new user input parsing.

## Recommended Plan Decomposition

A 5-plan decomposition. Wave 0 is RED-test scaffolding; Waves 1-4 are sequential due to type-flow dependencies. The planner makes the final call — these are starting-point suggestions.

```yaml
# Plan 66-01 — RED tests for structured codegen output + sub-block traceability
title: "RED tests: codeGenerator returns CodeSection[] with source-UUID tracking"
wave: 0
depends_on: []
files_modified:
  - gui/src/lib/__tests__/codeGenerator.sections.test.ts  (NEW — sub-block-level assertions)
  - gui/src/lib/__tests__/codeGenerator.serialize.test.ts  (NEW — serializeSections byte-equal regression)
  - gui/src/components/__tests__/CodePreview.test.tsx  (NEW — render + sub-block click + hover writes store)
  - gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx  (NEW — CustomEvent integration with scrollIntoView mock)
  - gui/src/components/__tests__/CodePreview.textSelection.test.tsx  (NEW — regression for D-14)
# All 5 test files RED (assert against not-yet-built API). Confirms test surface contracts upfront per Wave-0 RED convention.
```

```yaml
# Plan 66-02 — codeGenerator structured-output refactor + serializeSections adapter
title: "codeGenerator returns CodeSection[]; serializeSections adapter; update 5 existing test files for D-12 headers"
wave: 1
depends_on: [66-01]
files_modified:
  - gui/src/lib/codeGenerator.ts  (return type change + emit-site refactor across ~80 push sites; new CodeSection/CodeSubBlock types; serializeSections export)
  - gui/src/lib/codeGenerator.test.ts  (wrap calls in serializeSections; update # === <Section> === header assertions)
  - gui/src/lib/__tests__/codeGenerator.anchors.test.ts  (wrap + header updates)
  - gui/src/lib/__tests__/codeGenerator.bc.test.ts  (wrap + header updates)
  - gui/src/lib/__tests__/codeGenerator.resources.test.ts  (wrap + header updates)
  - gui/src/lib/__tests__/codeGenerator.smoke.test.ts  (wrap; smoke fixture stays Julia-runnable)
  - gui/src/components/CodePreview.tsx  (TEMP — pipe through serializeSections so the app keeps rendering string in this plan; Plan 03 takes over)
  - gui/src/components/Toolbar.tsx  (TEMP — pipe through serializeSections; Plan 04 takes over)
# Largest plan in the phase. Keep the app's runtime behavior unchanged (string output preserved via adapter) while migrating the internal shape. RED tests from Plan 01 flip GREEN at the end. Existing 5 test files stay GREEN modulo the D-12 header updates.
```

```yaml
# Plan 66-03 — Zustand ephemeral slices + useShowCodeFor hook + exportCode util
title: "useStore hover/pin slices; pendingShowCodeFor; useShowCodeFor hook in App.tsx; exportCode.ts shared util"
wave: 2
depends_on: [66-02]
files_modified:
  - gui/src/store/useStore.ts  (hoveredSourceIds, pinnedSourceIds, pendingShowCodeFor + setters + clearers; clearPinned action)
  - gui/src/hooks/useShowCodeFor.ts  (NEW)
  - gui/src/App.tsx  (mount useShowCodeFor; add Esc keydown for pin-clear with input-focus guard)
  - gui/src/lib/exportCode.ts  (NEW)
  - gui/src/components/Toolbar.tsx  (call exportCode.ts instead of inline handleExport)
  - gui/src/store/__tests__/useStore.codePanel.test.ts  (NEW — Set replacement on every mutation; multi-pin additive; toggle-by-overlap semantics)
  - gui/src/lib/__tests__/exportCode.test.ts  (NEW — validation gate failure → false; user-cancel → false; happy path → true)
# Pure data + util work; no new UI yet. Plan 04 wires the UI in.
```

```yaml
# Plan 66-04 — CodePreview UI rewrite + BottomPanel Copy/Export buttons + section rendering
title: "CodePreview section-by-section renderer with hover/click/flash; BottomPanel Copy + Export buttons in TabsList strip"
wave: 3
depends_on: [66-03]
files_modified:
  - gui/src/components/CodePreview.tsx  (full rewrite — section renderer + sub-block dom-ids + refs + flash + click handlers)
  - gui/src/components/BottomPanel.tsx  (add right-side button group with Copy + Export; subscribe to nodes.length for disabled)
# RED tests from Plan 01 (CodePreview render + click + flash + showCodeFor + text-selection) flip GREEN.
```

```yaml
# Plan 66-05 — StreamNode hover-ring + CSS class wiring + index.css rules + Phase 72 handoff notes
title: "StreamNode subscribes to hoveredSourceIds / pinnedSourceIds; index.css hover-ring rules; handoff doc"
wave: 4
depends_on: [66-04]
files_modified:
  - gui/src/components/StreamNode.tsx  (per-node primitive-boolean selectors; conditional className for stream-node--code-hover / --code-pinned)
  - gui/src/index.css  (append .stream-node--code-hover and .stream-node--code-pinned rules with CSS-variable placeholders)
  - gui/src/components/__tests__/StreamNode.codeHover.test.tsx  (NEW — class applied when id in hoveredSourceIds; class removed when not)
  - .planning/notes/phase-66-hover-ring-tuning.md  (NEW — Phase 72 handoff: chosen placeholder colors, where to re-tune; mirrors the Phase 59 correlation-geom-first-api.md handoff style)
# Final visual surface. Manual UAT checkpoint: right-click a node → "Show generated Julia code" → panel opens, scrolls to component, flashes, hover ring on canvas. Pin survives cursor-out. Esc clears.
```

**Total: 5 plans, 1 RED-test wave, 4 implementation waves, 1 manual UAT checkpoint at end.** Roughly mirrors the Phase 63.1 14-plan decomposition but smaller scope; Phase 66 has fewer ID-domain boundaries to navigate.

---

## Sources

### Primary (HIGH confidence — physical file inspection in working tree)

- `/home/itay/projects/Julia-STREAM/.planning/phases/66-code-preview-rework/66-CONTEXT.md` — 187-line locked decisions; the authoritative scope source.
- `/home/itay/projects/Julia-STREAM/gui/src/lib/codeGenerator.ts:1-1451` — refactor target; emit-site survey, type-signature lock from Phase 63.1 D-04, header rule lines 1-16.
- `/home/itay/projects/Julia-STREAM/gui/src/components/CodePreview.tsx:1-34` — full rewrite target.
- `/home/itay/projects/Julia-STREAM/gui/src/components/BottomPanel.tsx:1-32` — TabsList insertion point.
- `/home/itay/projects/Julia-STREAM/gui/src/components/Toolbar.tsx:49-60, 122-129` — handleExport extraction source.
- `/home/itay/projects/Julia-STREAM/gui/src/components/canvasMenus/NodeContextMenu.tsx:35-43` — dispatcher contract (Phase 65 D-14).
- `/home/itay/projects/Julia-STREAM/gui/src/components/StreamNode.tsx:174, 184-195, 259-275, 309-321` — established primitive-boolean selector + per-port sub-component pattern.
- `/home/itay/projects/Julia-STREAM/gui/src/store/useStore.ts:175-300, 800-1020` — ephemeral slice precedents (`bottomPanelOpen`, `interactiveLocked`, `errorNodeIds`).
- `/home/itay/projects/Julia-STREAM/gui/src/lib/projectIO.ts:123-148` — verified that `serializeProject` takes specific args (does NOT spread store); new ephemeral slices auto-excluded.
- `/home/itay/projects/Julia-STREAM/gui/src/components/CanvasPanel.tsx:260-294` — existing Esc handler shape + input-focus guard.
- `/home/itay/projects/Julia-STREAM/gui/src/components/resources/ResourceRow.tsx:114-122` — setTimeout-with-cleanup pattern for the Copy button confirmation.
- `/home/itay/projects/Julia-STREAM/gui/src/components/ui/scroll-area.tsx:1-59` — shadcn ScrollArea = Radix Viewport (verified scrollIntoView walks up correctly).
- `/home/itay/projects/Julia-STREAM/gui/src/lib/__tests__/codeGenerator.smoke.test.ts:1-80` — test harness conventions for the codegen test family.

### Secondary (MEDIUM confidence — design decision references)

- `/home/itay/projects/Julia-STREAM/.planning/notes/gui-redesign-design-decisions.md` §3.8 (visual restraint), §3.11 (BC tab + value-source emission), §7 (code-tab rework bullet). Cited but not loaded line-by-line in this research — CONTEXT.md restates the load-bearing decisions.
- `/home/itay/projects/Julia-STREAM/.planning/phases/65-interaction-model-overhaul/65-CONTEXT.md` D-14 — dispatcher contract.
- `/home/itay/projects/Julia-STREAM/.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md` — generateCode signature lock + single anchor emission loop.
- `/home/itay/projects/Julia-STREAM/.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` INV-CG-01..04.

### Tertiary (LOW confidence — would need verification before relying on)

- Tauri 2 `@tauri-apps/plugin-dialog` save-returns-null-on-cancel — verified via existing `Toolbar.tsx:57` usage in production but not against current plugin docs.
- Zustand 4.x `subscribeWithSelector` middleware order — verified by Phase 65-14 install at `useStore.ts:2` but not cross-checked against current Zustand docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every dependency is already in tree and used elsewhere.
- Architecture: HIGH — CodeSection/CodeSubBlock type design is mechanically derived from existing emit sites; sub-block boundaries are documented per-section in CONTEXT.md D-01..D-04.
- Patterns (hover-ring, Zustand slice, listener lifecycle): HIGH — all map 1:1 to existing established patterns in the codebase (`hasAnchor`, `hasBCError`, `stream:focus-instance-name`).
- Pitfalls: HIGH — most pitfalls are codebase-specific (BlankLine double-emit, ListenerBeforeMount) and identified by reading the code; the generic ones (Set mutation, scrollIntoView in jsdom) are widely-documented React/Zustand pitfalls.
- Test surface: MEDIUM — recommendations are concrete but full assertion shapes will only be finalized during plan-time as the existing fixture files are surveyed for D-12 header collisions.

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (30 days; codebase is in heavy active development on `gui-redesign` but Phase 66 touchpoints are mature)

## RESEARCH COMPLETE
