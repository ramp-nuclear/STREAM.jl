# Phase 66: Code preview rework - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 66-code-preview-rework
**Areas discussed:** Traceability granularity, Hover & jump UX, Click-to-pin semantics, Formatting rules scope, Buttons placement

---

## Meta — Option-scoring rule introduced mid-session

Mid-discussion the user proposed that every `AskUserQuestion` option carry an honest **`Score: X.Y/10 — <why>`** clause appended to its description, to surface Claude's project-fit judgment transparently. Adopted, committed to user memory (`feedback_option_scoring.md`), and applied to all remaining questions in this session and to every future GSD interactive flow. From this point on, every option below shows its score.

---

## Traceability granularity

### Q1 — Smallest UI-addressable unit

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Per sub-block | Section = ordered list of sub-blocks. One sub-block per component instance (Components), per connect-call (Composition), per resource (Resources). Sub-block carries sourceIds[]. | (not scored — first question of session, pre-rule) | ✓ |
| Per emitted line | Every line optionally carries sourceIds[]. Most precise; renderer must wrap every line. | | |
| Per top-level section only | Only the five named sections carry sourceIds[]. Coarsest; hover on Components is essentially no-op. | | |

**User's choice:** Per sub-block.

### Q2 — Composition sub-block boundaries (re-asked after the option-scoring rule was introduced)

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| One sub-block per emission unit | Each `connect(a.port, b.port)` line is its own sub-block; `fuel_assembly(...)`, `symmetric_plate(...)`, etc. each one sub-block. | 8.5/10 — minimal renderer logic, exactly mirrors codegen's existing walk, two-endpoint highlight is precise. | ✓ |
| Group connects by component | All `connect(...)` lines touching the same component merged into one sub-block. | 5.0/10 — extra grouping pass with no real UX win; hides which two ports a single connect joins. | |
| One sub-block per topology cluster | Detect graph-connected clusters (loops, fuel assemblies) and emit one sub-block per cluster. | 3.5/10 — non-trivial detection cost, premature, scope-overlaps Phase 71. | |

**User's choice:** One sub-block per emission unit.

### Q3 — Resources sub-block keying

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Per emitted line | Each HD-keyed Power Shape assignment is its own sub-block (sourceIds = [resource_uuid, hd_uuid]). | 8.8/10 — matches consumer-keyed emission shape, precise two-target hover, no extra cost. | ✓ |
| Group by resource | Merge all consumer-keyed lines that share the same Power Shape into one sub-block. | 5.5/10 — loses per-HD precision; same info better surfaced by Navigator selection. | |
| Per resource declaration only | Each resource is one sub-block; per-consumer assignment lines merged into the same sub-block. | 6.0/10 — simpler model, but conflates two emission units. | |

**User's choice:** Per emitted line.

---

## Hover & jump UX

### Q4 — Canvas-side hover-ring style

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Dedicated hover ring (new style) | New ring style distinct from selection ring and validation red ring; layer-aware. | 8.5/10 — keeps existing rings unambiguous, matches §3.8 professional feel, no semantic collision. | ✓ |
| Reuse the existing selection ring | Apply selection-ring style without mutating selection state. | 4.5/10 — collides with selection semantics codified in Phase 65 §3.5. | |
| Colored fill overlay | Semi-transparent color wash over the node body. | 7.5/10 — visible at zoom-out but competes with BC badges and validation markers. | |
| Pulse-on-hover animation | Brief glow / pulse, fades after ~600ms. | 3.0/10 — motion-heavy, conflicts with "visual restraint" §3.8, can't survive long hovers. | |

**User's choice:** Dedicated hover ring (new style).

### Q5 — When does canvas selection trigger code-panel jump?

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Explicit only (Phase 65 event) | Listen only for `stream:show-code-for` CustomEvent from the right-click menu. Plain selection does NOT scroll. | 8.8/10 — respects Phase 65's explicit contract, no surprise scrolls, matches §3.8 "no silent state changes." | ✓ |
| Auto-jump on any selection | Any selection change auto-scrolls and highlights. | 4.0/10 — jumpy during marquee/multi-select, fights user's reading position. | |
| Passive highlight (no scroll) | Apply hover-ring style to sub-blocks but never auto-scroll. | 7.0/10 — nice ambient feedback when panel already at right section, invisible otherwise. | |

**User's choice:** Explicit only.

### Q6 — Panel-closed behavior on `stream:show-code-for`

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Open panel, scroll to sub-block, flash highlight | Set `bottomPanelOpen = true`; smooth-scroll; 1.5s flash on the sub-block. | 9.0/10 — fulfills the menu's stated promise, deterministic, single visible state change. | ✓ |
| Open panel, scroll, no flash | Same but no flash. | 7.0/10 — quieter, easy to miss on a long script. | |
| Toast / hint instead of opening | Show a toast 'Open code panel to see this section'. | 2.5/10 — extra step for no reason; user already asked to see it. | |

**User's choice:** Open panel, scroll, flash highlight.

---

## Click-to-pin semantics

### Q7 — What does pin actually do?

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Sticky canvas highlight | Pin = hover-ring persists after cursor leaves the sub-block until toggle, empty-click, or Esc. | 9.0/10 — simplest mental model, directly matches roadmap text, composes with multi-pin. | ✓ |
| Sticky section header | Pinned sub-block's header sticks to top of scroll area like a TOC. | 5.5/10 — useful for long sections but loses bidirectional-traceability framing. | |
| Pinned table-of-contents | Each pin adds an entry to a TOC widget at the top. | 4.5/10 — new UI surface, not in roadmap, premature. | |
| Sticky-highlight + persistent canvas selection | Pin highlights AND selects nodes in store (Properties tab opens). | 3.5/10 — entangles pin with selection; violates §3.8 "no silent state changes." | |

**User's choice:** Sticky canvas highlight.

### Q8 — Pin cardinality and clear mechanism (with mid-question concern about partial-copy)

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Multi-pin, additive; Esc clears all | Many sub-blocks pinnable; clicking a pinned sub-block toggles off; Esc clears all. | 8.8/10 — matches multi-component diagnosis use case, Esc reuses universal cancel. | ✓ |
| Single-pin (replace on new click) | Only one sub-block pinned at a time. | 5.5/10 — simpler but loses main multi-component diagnostic value. | |
| Multi-pin with a 'Clear pins' button | Same as multi-pin but explicit button instead of Esc. | 6.0/10 — visible affordance but adds UI clutter; Esc covers it. | |

**User's choice:** Multi-pin, additive; Esc clears all.

**User's mid-question concern:** "What if the user just wants to copy a part of the generated code straight from the preview instead of exporting? How would that look, and is that even a good idea to care about? Be critical."

**Claude's critical answer:**
- Yes, partial-copy matters (researchers want to grab imports or one component for sister scripts).
- Native browser drag-to-select + Ctrl+C handles it for free; the existing `<pre>` already has `select-text`.
- Click-to-pin does NOT conflict: browser distinguishes click vs drag automatically, so drag-to-select fires no click and toggles no pins.
- Triple-click line-select fires three rapid clicks → pin state net-unchanged (toggle 3x = toggle 1x odd, but the user's intent IS the line, accepted minor edge case).
- Implementation constraint, not a feature: don't `user-select: none`, don't `preventDefault` on mousedown.
- No per-sub-block Copy button (visual restraint, §3.8).

Folded into CONTEXT D-14 (native text selection preserved) and D-15 (no per-sub-block Copy button).

---

## Formatting rules scope

### Q9 — How much hand-rolled formatting in scope?

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Floor only — section comments + blank-line discipline | Section headers `# === <Name> ===`, one blank line between sub-blocks and between sections, consistent indent, no trailing whitespace. | 8.5/10 — cleanest scope, leaves existing emit shapes intact, defers polish to Phase 72 where it belongs. | ✓ (with explicit Phase 72 hand-off) |
| Floor + sorted/grouped imports | Floor + `using` statements grouped alphabetically. | 6.5/10 — small win; current import list is 2–3 lines, mostly cosmetic. | |
| Floor + aligned `@named` columns | Floor + column-aligned `@named` declarations. | 5.0/10 — fragile under sub-block reordering, breaks with long kwarg lists. | |
| Maximal polish | Floor + sorted + alignment + normalized numerals. | 3.5/10 — scope-creep into Phase 72; high cost; risks breaking codegen test string-equality. | |

**User's choice:** Floor only, "only if we actually take care of this in phase 72." Phase 72 hand-off captured in CONTEXT Deferred Ideas.

---

## Toolbar buttons (Copy + Export)

### Q10 — Where do Copy + Export buttons live?

| Option | Description | Score | Selected |
|--------|-------------|-------|----------|
| Right side of Tabs header, Copy + Export, whole-script only | Two `Button size="sm"` icon+label buttons in `BottomPanel.tsx`'s `<TabsList>` right side. Copy = clipboard.writeText(fullCode) with 1.5s "Copied" state; Export = existing handler extracted to shared util. | 9.0/10 — puts buttons where roadmap says, reuses validation-gated export path, native selection covers partial copy. | ✓ |
| Floating top-right inside scroll area | Buttons float over the code text, top-right of scroll area. | 5.0/10 — overlaps long lines and section headers on real content; conflicts with §3.8 density. | |
| Both panel buttons AND keep top-Toolbar Export | Add panel buttons but also keep existing Toolbar.tsx Export. | 8.0/10 — redundant but defensible; top-Toolbar Export reachable with panel closed. | (implicit by D-18 in CONTEXT — top-Toolbar Export STAYS) |
| Replace top-Toolbar Export with panel-only buttons | Remove Toolbar.tsx's Export, only panel toolbar. | 4.5/10 — forces opening panel before exporting; loses always-reachable affordance. | |

**User's choice:** Right side of Tabs header (option 1). Top-Toolbar Export retention not explicitly answered but pre-stated in the session preamble as a carry-forward and not overridden; recorded as D-18 (top-Toolbar Export stays).

---

## Claude's Discretion

Items where the user did not constrain Claude and downstream agents have flexibility:

- Exact CSS for the hover-ring (color, stroke width, dash pattern, 1.5s flash animation timing).
- Whether `pinnedSourceIds` lives in `useStore` or a separate `useCodePanelStore`.
- Whether `serializeSections(...)` is exported from `codeGenerator.ts` or lives in a sibling util.
- File location for the shared `exportCode.ts` util (could equally live in `projectIO.ts`).
- Click-handler shape: single `onClick` vs custom `onMouseDown` + drag detection (default `onClick`).
- Test surface scope and split.

---

## Deferred Ideas

- **Phase 72:** Sorted/grouped imports, aligned `@named` columns, normalized number literal formatting, final hover-ring visual tuning.
- **Future (no current owner):** Multi-node `stream:show-code-for` payload; per-sub-block Copy button (rejected; revisit only if partial-copy friction becomes severe); syntax highlighting (Prism/highlight.js/shiki); in-panel code editing; section folding/collapse.
