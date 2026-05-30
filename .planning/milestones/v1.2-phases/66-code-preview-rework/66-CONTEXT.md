# Phase 66: Code preview rework - Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor the GUI's Julia code generator and code-preview UI so the preview becomes a **bidirectional, navigable surface** instead of a flat read-only string blob.

**In scope:**

- Refactor `gui/src/lib/codeGenerator.ts` from `string` return type to **`CodeSection[]`** structured output. Each `CodeSection` has a fixed top-level name (`Imports` / `Resources` / `Components` / `Composition` / `Main`) and contains an ordered list of `CodeSubBlock[]`. Each `CodeSubBlock` carries `lines: string[]` plus `sourceIds: string[]` (zero, one, or many UUIDs of canvas nodes and/or resource UUIDs that produced those lines).
- Rebuild `gui/src/components/CodePreview.tsx` to render sections as visually grouped blocks with hover targets at the **sub-block** granularity (see D-01..D-04 for what defines a sub-block in each section).
- Bidirectional traceability:
  - **Code → canvas (hover):** hovering a sub-block applies a dedicated hover-ring style to its `sourceIds` nodes on canvas (distinct from the selection ring and the validation red ring).
  - **Canvas → code (explicit jump):** consume the `stream:show-code-for` `CustomEvent` already dispatched by Phase 65's `NodeContextMenu.tsx:40` "Show generated Julia code" right-click action.
- Click-to-pin: clicking a sub-block toggles a **sticky** hover-ring on its source nodes that survives cursor-out. Multi-pin (additive) with `Esc` to clear all pins.
- Inline **Copy** and **Export** buttons in the bottom-panel Tabs header (right side, next to the `Code` tab).
- Hand-rolled formatting **floor only**: section header comments, blank-line discipline, no trailing whitespace, consistent indentation. Anything richer is Phase 72.

**Out of scope:**

- Monaco editor, Prism.js, highlight.js, any syntax highlighting library. Plain `<pre><code>` text styling continues (see `STACK.md` decision, restated under D-13).
- Sorted/grouped imports, aligned `@named` columns, normalized number literals — explicitly deferred to **Phase 72** (Design system / interaction contract) per user direction.
- Per-sub-block Copy buttons — rejected (visual restraint, §3.8; native browser text-selection already covers partial-copy).
- Editing the generated code in-panel. The preview stays read-only.
- Phase 71 validation surfacing (red-ring markers, status-bar counts). Phase 66 only adds a hover-ring style; validation rings are a separate concern owned by Phase 71.
- Layer system overhaul (Phase 68). Phase 66 hover-ring is layer-aware in the sense that highlighting an off-layer node briefly un-dims it, but Phase 66 does NOT change the four-layer taxonomy or its toggles.
- Changes to **what** codegen emits — Phase 66 changes the **return shape** and adds source-tracking, never the emitted Julia text (modulo the formatting floor in D-12). Existing string-equality codegen tests must continue to pass after passing through a `serializeSections(CodeSection[]) -> string` adapter.

</domain>

<decisions>
## Implementation Decisions

### Traceability granularity (sub-block model)

- **D-01:** The `CodeSection` shape is `{ name: 'Imports' | 'Resources' | 'Components' | 'Composition' | 'Main'; subBlocks: CodeSubBlock[] }`. The `CodeSubBlock` shape is `{ lines: string[]; sourceIds: string[]; kind?: string }` where `sourceIds` may be empty (e.g., for the Imports block) and `kind` is an optional discriminator the renderer can read for finer styling (`'component' | 'connect' | 'helper' | 'resource' | 'consumer-ps' | 'import' | 'system'`). The **smallest UI-addressable unit is the sub-block** — not the line, not the section.
- **D-02:** **Composition** sub-blocks emit one-per-emission-unit. Each individual `connect(a.port, b.port)` line is its own sub-block (`sourceIds = [a_uuid, b_uuid]`). A topology-detected `fuel_assembly([ch1, ...], [pl1, ...])` helper call is one sub-block (`sourceIds` = all CACs and HDs it consumes). `symmetric_plate(cac, hd)`, `plate(cac1, hd, cac2)`, `one_sided_connection(cac, hd)` are likewise each one sub-block. Whatever the codegen actually emits as one statement is one sub-block; no grouping pass.
- **D-03:** **Resources** sub-blocks are emitted per-line. Each `Geometry` declaration is one sub-block (`sourceIds = [geometry_uuid]`). Each per-HD consumer-keyed Power-Shape assignment (e.g., `hd1_power_shape = ones(nz, nx)`) is its own sub-block (`sourceIds = [power_shape_uuid, hd_uuid]`) — so hovering it highlights the resource row in the Navigator AND the `hd1` node on canvas. Each Fluid declaration (when added) is one sub-block.
- **D-04:** **Components** sub-blocks are one-per-`@named`-declaration with `sourceIds = [node_uuid]`. **Imports** is a single sub-block with `sourceIds = []`. **Main** (the final `@named sys = ODESystem(...)` plus any `structural_simplify` / problem-construction lines, if present) is a single sub-block with `sourceIds = []` — the system-construction line is conceptually about everything, so hover-highlighting nothing is correct.

### Hover and jump UX

- **D-05:** Hover style on canvas is a **new dedicated hover-ring** — visually distinct from the existing selection ring (blue), validation red ring (Phase 71), and BC dashed-edge style (§3.11). Concrete style decided during the design-system pass (Phase 72); for v1 the planner picks a thin accent-color outline that is unambiguously not the selection ring. The hover-ring is **layer-aware**: if a highlighted node sits on a hidden/dimmed layer (per Phase 68 once it lands), the node un-dims for the duration of the hover/pin so the user can see what got highlighted.
- **D-06:** Reverse direction (canvas → code) is **explicit only**. The code panel listens for the `stream:show-code-for` `CustomEvent` already dispatched by `gui/src/components/canvasMenus/NodeContextMenu.tsx:40` (Phase 65 D-14). Plain canvas selection (click, marquee, ctrl-click) does **not** scroll the panel and does **not** apply any code-side highlight. This respects §3.8's "no silent state changes."
- **D-07:** When `stream:show-code-for` fires and `bottomPanelOpen === false`, the listener sets `bottomPanelOpen = true`, then on the next render: smooth-scrolls the target sub-block into view (center-ish), and applies a **1.5-second flash** to the sub-block (e.g., the hover-ring background fades from accent-200 to transparent) so the user notices the jump landed. If the panel is already open and the target is already in view, the flash still fires (it's the acknowledgment, not the scroll, that matters).
- **D-08:** Multi-node lookup: `stream:show-code-for` carries `{ nodeId: string }` today (single-node). The listener finds every sub-block whose `sourceIds` includes that `nodeId` and applies hover-ring style to all of them simultaneously; the scroll target is the first match (lowest in document order). Extending to multi-node payloads (`nodeIds: string[]`) is a non-breaking future change — the listener accepts `nodeId` xor `nodeIds`.

### Click-to-pin

- **D-09:** Click-to-pin means **sticky canvas highlight**. Clicking a sub-block adds its `sourceIds` to a `pinnedSourceIds: Set<string>` slice in the store; the hover-ring style persists on those canvas nodes until the user clicks the sub-block again (toggle off — removes those IDs from the set) or clicks empty space inside the code panel (clears the entire pin set), or presses `Esc` (clears the entire pin set; matches §3.8 universal cancel).
- **D-10:** **Multi-pin is additive.** Pinning a second sub-block adds its `sourceIds` to the set without disturbing the first; the canvas hover-ring renders on the union. Toggle semantics: clicking a sub-block that contributes ANY ID currently in the pin set removes ALL of its `sourceIds` from the set (treat the sub-block as the unit, even if some of its IDs are also pinned via another sub-block — minor double-pin overlap is acceptable; the diagnostic value of multi-pin outweighs the edge-case bookkeeping cost).
- **D-11:** Pinning does **NOT** mutate canvas selection state. The Properties tab is unaffected, the selection ring does not appear, undo/redo is untouched. Pin state lives only in the code-panel UI slice and the canvas hover-ring CSS class — it is ephemeral session state, NOT persisted to `.scp`.

### Formatting and rendering rules

- **D-12:** Hand-rolled formatting is **floor only** for Phase 66:
  - Section headers as `# === <Section Name> ===` comments (top-level section delimiter; replaces the current ad-hoc `# ---------------------...` lines).
  - Exactly one blank line between sub-blocks within a section.
  - Exactly one blank line between top-level sections.
  - No trailing whitespace on any line.
  - Consistent indentation matching the existing codegen.
  - Nothing else. Sorted imports, aligned `@named` columns, normalized number literals are explicitly deferred to **Phase 72** per user direction.
- **D-13:** Rendering technology stays **plain `<pre><code>`** — no Monaco, no Prism.js, no highlight.js (`STACK.md:117` decision restated). Each sub-block becomes its own `<div>` (or `<pre>` if necessary to preserve text-selection across newlines) inside the section. Section headers render as styled `<h4>` or similar above each block group.
- **D-14:** **Native browser text-selection is preserved.** Sub-block wrappers MUST NOT set `user-select: none`. Click handlers MUST NOT call `preventDefault()` on `mousedown`. Drag-to-select inside one sub-block, across multiple sub-blocks, or across an entire section MUST work and produce a clean copyable text run. Triple-click line-select fires three rapid `click` events which net out to "pin state unchanged" — accepted minor edge case.
- **D-15:** No per-sub-block Copy button (rejected as visual clutter and a §3.8 violation). Native `Ctrl+C` on a user-selected range covers partial copies; the panel-level Copy button covers whole-script copy.

### Toolbar buttons

- **D-16:** **Copy** and **Export** buttons live in the **right side of the existing `<TabsList>`** strip in `gui/src/components/BottomPanel.tsx` (next to the `Code` tab trigger). Both are `Button size="sm"` shadcn icon+label buttons (icons: `lucide` `Copy` and `Download` — `Download` matches the existing top-Toolbar Export at `Toolbar.tsx:128`).
- **D-17:** **Copy** runs `navigator.clipboard.writeText(serializeSections(sections))` on the full assembled script and shows a brief 1.5-second `Copied` confirmation state on the button (label swaps to "Copied" with a `Check` icon, reverts after 1500ms). No validation gate — copying invalid-but-incomplete code is a legitimate user workflow (paste into REPL to iterate).
- **D-18:** **Export** reuses the existing `handleExport` logic from `gui/src/components/Toolbar.tsx:49-60`. Extract the validation-gate + Tauri-save-dialog flow into a shared util `gui/src/lib/exportCode.ts` so both call sites (top-Toolbar and panel-Toolbar) drive the same path. The top-Toolbar Export button **stays** — it's the reachable affordance when the bottom panel is closed.
- **D-19:** Buttons are disabled when `nodes.length === 0` (matches the existing `Toolbar.tsx:125` `disabled={nodes.length === 0}` predicate). When the bottom panel is closed, the buttons are not rendered (they live inside `BottomPanel.tsx` which short-circuits at line 11).

### Claude's Discretion

- Exact CSS for the hover-ring (color, stroke width, dash pattern, animation timing on the 1.5s flash) — planner picks; final visual tuning happens in Phase 72.
- Whether `pinnedSourceIds` lives as its own `useStore` slice or as a separate small `useCodePanelStore` Zustand store — planner decides; both are acceptable.
- Whether `serializeSections(CodeSection[]) -> string` lives inside `codeGenerator.ts` (as a named export) or as a sibling util `gui/src/lib/serializeCodeSections.ts` — planner picks; the test suite needs SOME exported function with this signature so the existing string-equality tests can stay green.
- File location for the shared `exportCode.ts` util (could equally live in `gui/src/lib/projectIO.ts` since both involve Tauri save dialogs) — planner picks.
- Click-handler shape: a single `onClick` on the sub-block wrapper, vs `onMouseDown` + custom drag-detection — planner picks. Default expectation is `onClick` (browser's built-in click-vs-drag discrimination is sufficient). Custom logic only if the planner finds a concrete drag-selects-but-fires-click bug during execution.
- Test surface: vitest unit tests for `serializeSections` round-trip; component tests for `CodePreview` rendering one sub-block per emission unit; an integration test confirming `stream:show-code-for` opens the panel + scrolls + flashes; a regression test confirming `user-select: none` is absent from every sub-block wrapper class.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design decisions (LOCKED — re-debate not allowed)
- `.planning/notes/gui-redesign-design-decisions.md` §3.11 — Boundary Conditions: tab and value-source components. Phase 66 must understand the BC emission modes (Value / Profile / Function / Mark / Source) because each emits a different `Channel`/`CHF` sub-block shape that Phase 66 must address as one sub-block per emission. Lines 907–994.
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — Design system / interaction contract. Spatial consistency (bottom panel = "code preview / message log"); feedback consistency ("no silent state changes" — drives D-06); visual restraint discipline (drives D-12 floor-only, D-15 rejection of per-sub-block Copy). Lines ~620–710.
- `.planning/notes/gui-redesign-design-decisions.md` §7 — code-tab rework bullet (lines ~1395–1397): "Export button in code-tab window (and in File menu); copy-to-clipboard button; section blocks with hover/click → highlight source on canvas; possibly script formatting rules." This is the source bullet for Phase 66.
- `.planning/notes/gui-redesign-design-decisions.md` §3.10 — Channel Variants (Three Explicit Components). Affects how Components-section sub-blocks for Channel/CHF/CAC are emitted. Lines 841–905.

### Project / milestone state
- `.planning/ROADMAP.md` §"Phase 66: Code preview rework" — phase goal text (line ~200–206). Depends on Phase 62 (resources are part of generated sections).
- `.planning/STATE.md` — working branch is `gui-redesign`; v1.2 milestone active. Branching policy locked in `CLAUDE.md` (do NOT create new branches; stay on `gui-redesign`).
- `.planning/REQUIREMENTS.md` — full v1.2 milestone requirements; Phase 66 deliverables map to the "Live code preview / Export" features.

### Prior-phase artifacts that constrain Phase 66
- `.planning/phases/65-interaction-model-overhaul/65-CONTEXT.md` **D-14** — `stream:show-code-for` `CustomEvent` is dispatched by `NodeContextMenu.tsx:40` when the user picks the "Show generated Julia code" right-click action. Phase 66 is the **consumer** side. Quote: "...relies on Phase 66 structured `CodeSection[]` if available; falls back to 'open code panel and select all' if Phase 66 not yet done." Phase 66 replaces the fallback.
- `.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md` — codegen call signature `generateCode(nodes, edges, { anchors }, getComponent, resources, { bcMode, bcSymmetric })` is locked. Phase 66 changes the return TYPE (`string` → `CodeSection[]`), never the inputs. D-05 (single anchor emission loop) is consumed unchanged.
- `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` — Phase 62 invariants INV-CG-01..04 (Resources block emitted at top; component constructors reference resources by declared variable name via `_ref` UUID lookups; four Power Shape forms; per-HD consumer-keyed Power Shape variables). These all survive Phase 66 unchanged; the structured output simply wraps them as sub-blocks per D-03.
- `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` line 141–144 — explicitly states "Code preview rework with `CodeSection[]` and source-UUID tracking" is Phase 66 territory and that Phase 62 only changes WHAT codegen emits, not the section-block UI.

### Code touchpoints (read before planning)
- `gui/src/lib/codeGenerator.ts` (1451 lines) — the main refactor target. `generateCode(...)` at line 709 currently returns `string`; Phase 66 changes the return to `CodeSection[]` and adds a `serializeSections(...)` helper. The internal `lines: string[]` walker (lines 724, 752, 920, 1044, etc.) is restructured so each emit-block builds a `CodeSubBlock` with its `sourceIds`. Topology detection (lines 464–688: `detectThermalTopology`, `assemblies`) feeds sub-block boundaries in the Composition section per D-02.
- `gui/src/lib/codeGenerator.test.ts`, `gui/src/lib/__tests__/codeGenerator.anchors.test.ts`, `codeGenerator.smoke.test.ts`, `codeGenerator.bc.test.ts`, `codeGenerator.resources.test.ts` — all currently assert against the string output. Test surface migration: keep the string-equality tests green by piping the new `CodeSection[]` output through `serializeSections(...)` in each test (one-line adapter). Then add new sub-block-level tests for the structured output.
- `gui/src/components/CodePreview.tsx` (34 lines) — full rewrite. Current `<pre>` wrapping a single `code` string becomes a section-by-section renderer over `CodeSection[]` with hover/click handlers per sub-block. The existing `useStore` reads (`nodes`, `edges`, `anchors`, `resources`, `bcMode`, `bcSymmetric`) stay; the call site memoizes the new structured output.
- `gui/src/components/BottomPanel.tsx` (32 lines) — add Copy + Export buttons to the right side of the `<TabsList>` strip (line 21). Buttons are `flex-1`-aware (use `ml-auto` on the button group so they hug the right edge).
- `gui/src/components/Toolbar.tsx` lines 49–60 — current `handleExport` implementation. Phase 66 extracts this to `gui/src/lib/exportCode.ts` (or similar) so both Toolbar.tsx and BottomPanel.tsx call the same util. The top-Toolbar Export button (lines 122–129) is **kept** as-is (D-18).
- `gui/src/components/canvasMenus/NodeContextMenu.tsx:40` — already dispatches `stream:show-code-for` (Phase 65). Phase 66 does NOT modify this file. It adds a listener in `CodePreview.tsx` (or in a `useShowCodeFor()` custom hook).
- `gui/src/components/StreamNode.tsx` — receives the new hover-ring style. Phase 66 adds a CSS class triggered by a Zustand-store-fed `isHovered`/`isPinned` predicate (read from `hoveredSourceIds` / `pinnedSourceIds` slices). The class itself is final-tuned in Phase 72.
- `gui/src/store/useStore.ts` — add two ephemeral slices: `hoveredSourceIds: Set<string>` and `pinnedSourceIds: Set<string>` (or a single `codePanelHighlight: { hovered: Set<string>; pinned: Set<string> }` object — planner picks). These are **NOT** persisted to `.scp` (D-11); exclude them from `serialize` / `deserialize` in `projectIO.ts`.

### Reference for traceability fan-out
- `gui/src/lib/codeGenerator.ts` lines 464–688 — `detectThermalTopology` and `assemblies` builder. The `Assembly` record (lines ~580+) already aggregates per-helper-call the set of source nodes; Phase 66 attaches its UUIDs as the helper sub-block's `sourceIds`. No new graph traversal needed.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/ui/scroll-area.tsx` — used by current `CodePreview.tsx`; keep. The new section renderer scrolls inside the same `<ScrollArea>`.
- `gui/src/components/ui/tabs.tsx` + `<TabsList>` — already in `BottomPanel.tsx`. The Copy + Export buttons drop into the existing tabs strip as siblings of `<TabsTrigger>`.
- `gui/src/components/ui/button.tsx` — shadcn Button, used everywhere; use the `variant="ghost"` or `variant="outline"` `size="sm"` for the panel toolbar buttons (less visual weight than the top-Toolbar's `variant="default"` Export — the panel is secondary surface).
- `@tauri-apps/plugin-dialog` `save` + `@tauri-apps/plugin-fs` `writeTextFile` — already imported in `Toolbar.tsx` for the Export flow. Reuse via the extracted `exportCode.ts` util.
- `navigator.clipboard.writeText` — already available in the Tauri webview (no extra plugin). Used by Phase 65 D-15 for clipboard payloads; same pattern.
- `lucide-react` `Copy`, `Download`, `Check` icons — already in dependency tree (`Download` used by `Toolbar.tsx:128`).
- `gui/src/lib/codeGenerator.ts` `detectThermalTopology` + assembly builder (lines 464–688) — emits the helper-call substitutions (`fuel_assembly`, `symmetric_plate`, `plate`, `one_sided_connection`). Phase 66's Composition sub-blocks per D-02 already have all the source-node info they need attached to the `Assembly` records — no new detection logic required.
- Phase 65 D-14 dispatcher in `NodeContextMenu.tsx:40` — the canvas-side trigger is already shipped; Phase 66 only writes the consumer.

### Established Patterns
- **Pure-codegen module rule** (`codeGenerator.ts` header comment lines 1–16): zero React dependencies, zero zustand imports, codegen takes plain shapes. Phase 66 preserves this: `CodeSection[]` is a plain data type, no React. The `CodePreview.tsx` component handles all rendering.
- **Memoized derive-from-store pattern** (`CodePreview.tsx:18-25`): `useMemo` over the store-slice reads. Phase 66 keeps this pattern; the memo now returns `CodeSection[]` instead of `string`.
- **Tabs header right-side affordance pattern** — `Toolbar.tsx` already places action buttons in a flex row with `justify-between`. `BottomPanel.tsx`'s `<TabsList>` can mirror this with `ml-auto` on a button group.
- **Toggle-with-confirmation state pattern** — temporary visual state on a button after action (matches the "Copied" state we want for D-17). Phase 62's resource-row inline rename uses `useState` + `setTimeout` for similar 1.5s confirmation states; use the same shape.
- **Store-slice-for-ephemeral-UI-state pattern** — `bottomPanelOpen`, `bottomPanelHeight`, `theme` all live in `useStore` without being persisted. Phase 66's `hoveredSourceIds` / `pinnedSourceIds` follow this exact pattern. Exclude from `projectIO.ts` `serialize` (matches existing exclusion list).

### Integration Points
- **CodePreview** ← reads `useStore.nodes/edges/anchors/resources/bcMode/bcSymmetric`. Phase 66 adds reads of `hoveredSourceIds`/`pinnedSourceIds` (probably read by StreamNode, not CodePreview, since they drive canvas-side styling). CodePreview WRITES `hoveredSourceIds` (on mouse enter/leave) and `pinnedSourceIds` (on click).
- **StreamNode** ← reads `hoveredSourceIds`/`pinnedSourceIds`; applies the hover-ring CSS class when its `id` ∈ either set.
- **BottomPanel** ← hosts the new Copy/Export buttons; subscribes to `useStore.nodes.length` for the disabled state.
- **`stream:show-code-for` listener** ← installed by `CodePreview.tsx` (or a `useShowCodeFor` hook). On event: ensure `bottomPanelOpen`, scroll, flash. Cleans up on unmount.
- **`Esc` key listener** ← global or panel-scoped; clears `pinnedSourceIds`. Coordinate with Phase 65's universal Esc cancel — Phase 65 may already wire a global Esc handler; the planner checks `gui/src/hooks/` and the Phase 65 implementation for the integration shape.
- **`exportCode.ts` util** ← consumed by `Toolbar.tsx` (existing call site, replace inline `handleExport`) AND `BottomPanel.tsx` (new call site). Both pass the same store-derived `code` string. The util owns validation gate + Tauri save dialog + writeTextFile.

</code_context>

<specifics>
## Specific Ideas

- User explicitly asked for **honest fit-scoring (0.0–10.0)** on every option presented during discuss-phase from this session forward. Captured to user memory `feedback_option_scoring.md`; applies to all future GSD interactive flows, not just Phase 66. Surfaced here because every D-XX decision above was reached via a scored option.
- User explicitly raised partial-copy-from-preview as a concern; resolved via D-14 (native text selection preserved) and D-15 (no per-sub-block Copy button). The diagnostic worry was real — the resolution is "implementation constraint, not UI feature."
- "Visual restraint" framing from §3.8 was repeatedly load-bearing in the discussion. The user's higher-order goal is "professional engineering tool, not consumer SaaS playground" — every UI option that added visual clutter (TOC widgets, per-sub-block buttons, pulse animations) was scored down and rejected.
- The decision to keep the top-Toolbar Export button **alongside** the new panel Export is deliberate (D-18): Export must be reachable when the bottom panel is closed, since one of the core workflows is "build model, hit Export, ship .jl file" without ever opening the code preview.

</specifics>

<deferred>
## Deferred Ideas

### Phase 72 (Design system / interaction contract)
- **Sorted and grouped `using` imports.** ModelingToolkit first, then DelimitedFiles (when conditional), then STREAM-specific helpers, with deterministic alphabetic order within each group. (User confirmed this lives in Phase 72.)
- **Aligned `@named` declaration columns.** Variable-name column right-padded so the `=` lines up across all declarations in a section. (User confirmed Phase 72.)
- **Normalized number literal formatting.** Always `0.5` not `.5`, scientific-notation cutoffs, trailing-zero rules. (User confirmed Phase 72.)
- **Final hover-ring visual tuning.** Concrete CSS for color, stroke width, dash pattern, and the 1.5s flash animation timing — planner picks a sensible default in Phase 66; Phase 72's design-system audit re-tunes it alongside the broader accent-palette and visual-style commitments.

### Future (no current phase owner)
- **Multi-node `stream:show-code-for` payload** (`{ nodeIds: string[] }` instead of `{ nodeId: string }`). Non-breaking extension when Phase 65's right-click menu eventually supports multi-selection; Phase 66 listener already accepts both shapes per D-08, but the dispatcher side stays single-node for now.
- **Per-sub-block Copy button.** Rejected for Phase 66 (visual restraint). If a future workflow makes partial-copy from very long files painful, revisit — but the bar is high; native `Ctrl+C` is the answer for v1 and likely v2.
- **Syntax highlighting (Prism.js / highlight.js / shiki).** Explicitly out of scope per `STACK.md:117`. The plain `<pre>` rendering survives Phase 66 unchanged. A future v0.9+ phase can revisit if the read-only preview becomes a friction point.
- **In-panel code editing.** Far-future (would require Monaco or CodeMirror). Out of scope; the panel stays read-only.
- **Section folding / collapse.** Could be a nice density improvement (collapse Resources / Imports to free vertical space). Not in Phase 66 scope; revisit during Phase 72 if needed.

</deferred>

---

*Phase: 66-code-preview-rework*
*Context gathered: 2026-05-15*
