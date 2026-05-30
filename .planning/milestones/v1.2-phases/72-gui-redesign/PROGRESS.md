# Phase 72 — Progress Tracker

Mid-phase tracker for Phase 72 (GUI redesign via Impeccable). Updated after
each `/impeccable shape` session lands. The final `SUMMARY.md` (written at
phase end per the ROADMAP row) supersedes this file.

## Method (recap)

Phase 72 runs **entirely through the Impeccable Claude Code skill** —
bypassing `/gsd:discuss-phase`, `/gsd:plan-phase`, `/gsd:execute-phase`,
`/gsd:ui-phase`, `/gsd:ui-review`, `/gsd:verify-work`. Each per-surface
decision goes through `/impeccable shape <surface>` (discovery → brief →
confirm → implement), with cross-cutting passes via `/impeccable harden`
/ `clarify` / `polish` and a final `/impeccable extract` to promote
reusable tokens.

**Two-pass DESIGN.md protocol:** the seed `DESIGN.md` (written by
`/impeccable document --seed`-equivalent at the start) carries doctrine
+ `[TBD]` slots. As shape decisions land, this PROGRESS.md updates AND
the corresponding `[TBD]` slots in `DESIGN.md` get promoted to locked
values. At Phase 72 end, `/impeccable document` runs in scan mode to
capture the final tokens into a proper frontmatter + sidecar.

## Status legend

| | |
|---|---|
| ✅ | Locked — shape + implementation committed; DESIGN.md updated |
| 🟡 | In progress — shape session active |
| ⬜ | Queued — awaiting its shape session |
| ⏸ | Deferred — waiting on an upstream decision |
| ❌ | Cancelled — dropped from scope |

## Surface progress

### Locked

| Surface | Status | Commits | DESIGN.md |
|---|---|---|---|
| Canvas + StreamNode + Layer accents + 3-tier depth + grid background | ✅ | 5 initial + 3 visual-bug fixes + cleanup (see Decision log below) | §2 fully locked; §3 type scale locked, font/direction TBD; §4 depth approach locked, shadow vocab TBD; §5 StreamNode locked |
| shadcn primitive layer (Button / Input / Dialog / Tabs / etc.) | ✅ | 6 cluster commits (tokens, Button, Input, Surface, Menu, Navigation) — see Decision log | §2 --ring/--border/--popover/--shadow-dialog/--border-hover locked; §3 type-scale tokens exposed; §4 shadow vocab locked (single tier); §5 primitive layer fully locked |
| ValidationPanel + ValidationStatusBar + unified bottom-chrome footer | ✅ | 1 cluster commit (validator UX redesign) — see Decision log | §5 validator vocabulary, filter pills, group-by, resizable columns, selected-row indicator, status-bar tabs locked |
| Loop-highlight system + validator targeting rewrite (gravity_sum_per_loop) | ✅ | 1 cluster commit — see Decision log | §4 marching-ants flow trace motion; §5 .validation-flow-trace + .validation-flash-persistent + loop targeting contract locked |
| HydraulicEdge — obstacle-avoiding orthogonal router (Phase B) + smart port-side convention (Phase A v2) | ✅ | 1 cluster commit — see Decision log | §5 router contract + Phase 72 port-side convention (axis-snap, vertical bias, no-share-side invariant) locked |
| First-run empty-canvas hint (replaces WelcomeOverlay; chromeless typographic anchor) | ✅ | 1 commit — see Decision log | §5 first-run vocabulary locked (no card / no shadow / no wordmark, mono recents + Ctrl+ keymap, static-shortcut rule) |
| Help system (Tooltip discipline + cmdk shortcut mode + AnatomyDialog visual legend) | ✅ | 1 cluster commit — see Decision log | §5 tooltip consumption discipline + shortcut catalog SSOT + AnatomyDialog (real-component mirror) + HelpMenu rebuilt |
| BCEdge + HydraulicEdge + CodePreview tokenization (canvas↔code link state retoken to --foreground; 5 --syntax-* tokens; remove GitHub-dark borrow + border-l-2 + section-header slab) | ✅ | 1 cluster commit — see Decision log | §2 --syntax-* tokens + Code editor lane carve-out + Code-link active state (uses --foreground, no new hue); §5 CodePreview subsection locked |
| `/impeccable harden gui/src/` (prefers-reduced-motion safety net + scrollIntoViewSafe + ValidationPanel Row div→button + 3 token contrast fixes) | ✅ | 1 commit — see Decision log | (no DESIGN.md doctrine change — closes Audit P0-3 / Critique Sam persona findings) |
| `/impeccable clarify gui/src/` (em-dash purge + engineering-voice empty states across PresetsPanel / SidebarPanel / CodePreview / ResourcesTreePanel / AboutDialog / BottomPanel / CommandPalette) | ✅ | 1 commit — see Decision log | (no DESIGN.md doctrine change — closes Audit P2-3 + feedback_engineering_voice_copy) |
| `/impeccable polish gui/src/` (type-scale + section-header + border-l-2 sweep + AutoRecover dialog migration to locked surfaces + canvas-menu shadow removal) | ✅ | 1 commit — see Decision log | (no DESIGN.md doctrine change — closes Audit P2-4 + P2-6 + P1-1, and brings five consumer surfaces onto the locked primitive layer) |
| Preferences (Edit > Preferences… + Ctrl+,; two-pane Dialog; 6 categories; user-global persistence; Switch primitive added) | ✅ | 1 commit — see Decision log | §5 Preferences subsection locked |

### Queued (Session 4 — phase close)

| Surface | Status | Notes |
|---|---|---|
| `/impeccable extract` (promote new reusable tokens + components into design system; write `.impeccable/design.json` sidecar) | ⬜ | |
| Re-run `/impeccable audit gui/src/` | ⬜ | Target ≥17/20 |
| Re-run `/impeccable critique gui/src/` | ⬜ | Target ≥32/40 |
| Re-run `/impeccable document` in scan mode (transition DESIGN.md from seed to real spec) | ⬜ | |
| Write Phase 72 `SUMMARY.md` (supersedes this file) | ⬜ | Per the ROADMAP row contract |

## Decision log

### Canvas + StreamNode (locked 2026-05-21)

**Commits on `gui-redesign` branch (oldest → newest):**

```
4707b5c  feat(72-canvas): tokens + depth recommit + field highlight bug fix
df97873  feat(72-canvas): tokenize LayersPanel via shared layerColors lib
79674be  feat(72-canvas): StreamNode leading-band identity
82edeef  feat(72-canvas): grid lines replace ReactFlow default dots
42d64f9  feat(72-canvas): tokenize ValidationPanel warning + info colors
12a6415  fix(72-canvas): node bodies visible, ports unclipped, grid quieter
5094f57  fix(72-canvas): validation-flash hugs node edge (offset 4 → 0)
e79b242  fix(72-canvas): validation-flash border-radius matches node body
7f6fef5  fix(72-canvas): retarget validation-flash to StreamNode outer div
[cleanup commit]  (DESIGN.md lock + validation-flash CSS cleanup + this file)
```

**Key locked values** (full detail in `DESIGN.md` §2–§5):

- Depth tokens: `--chrome` 0.16/0.95 · `--panel` 0.21/0.98 · `--canvas` 0.27/0.99
  · `--card` 0.23/0.97 (all hue 254)
- Layer accents (OKLCH, dark/light): Hydraulic 0.62/0.50 @ hue 240 · Thermal
  0.74/0.60 @ hue 75 · Sources 0.74/0.60 @ hue 130 · ReactorPhysics
  0.62/0.48 @ hue 15
- Grid: minor 12 px @ Δ 0.02, major 24 px @ Δ 0.05 from canvas
- Type scale: 1.25 Major Third — 10 / 11 / 13 / 16 / 20 px
- Node visual: leading band (4 px → 8 px on select), `bg-card` body, no
  perimeter border, `rounded-md` (8 px), multi-layer split via
  `getDisplayLayers()`

**New shared modules introduced:**

- `gui/src/lib/layerColors.ts` — `LAYER_COLOR_VAR` map (single source of
  truth for layer accent CSS-var references)
- `getDisplayLayers()` in `gui/src/lib/layers.ts` — visual-only layer
  detection (dual-layer for components with both FlowPort + ThermalPort);
  behavioral `getComponentLayers()` unchanged

**Tests:** 1028 / 1028 pass. Pre-existing 11 tsc errors unchanged (per
CLAUDE.md baseline).

### shadcn primitive layer (locked 2026-05-22)

**Commits on `gui-redesign` branch (oldest → newest):**

```
965d781  feat(72-primitives): tokens + Button family
a2d17ca  feat(72-primitives): Input family
a456111  feat(72-primitives): Surface family
98e84aa  feat(72-primitives): Menu family
63fbe9e  feat(72-primitives): Navigation + misc
[this commit]  docs(72-primitives): lock DESIGN.md + PROGRESS.md
```

**Three confirmed locks** (via AskUserQuestion during shape):
1. Shadow vocabulary = single tier (`--shadow-dialog` on Dialog/AlertDialog/Sheet only)
2. Primary-action posture = context-aware (neutral high-contrast slab everywhere; modal scrim does the work of permitting it to read confidently)
3. Density = balanced 32 px (`h-8`) globally; `h-7` sm for property forms; `h-6` xs for chips

**Cross-cutting commitments** (full detail in `DESIGN.md` §2–§5):

- Two-tier radius: `--radius-sm` 4 px (compact controls) / `--radius-md` 8 px (surfaces); no `rounded-lg`
- Five-tier type scale tokens: `--text-{micro,label,body,title,display}` (10/11/13/16/20 px)
- 100 ms fade-in / 80 ms fade-out, `motion-reduce:!duration-0`. Zoom + slide entrance removed.
- Focus ring 2 px `--ring` at offset 0; inset on Input/Textarea
- Hover surface = `bg-card` (tonal step; chrome doesn't carry accent fill)
- Icons: Lucide stays; size-3.5 stroke-1.5 in h-8 controls (was size-4 stroke-2)
- `--ring` relocked to Hydraulic-hue tint (low chroma); `--border` relocked to solid OKLCH (no alpha-on-white)
- New token `--popover` exposed in light mode; `--border-hover` and `--shadow-dialog` introduced
- `Sheet` primitive added (built on Radix Dialog; no consumers yet)

**Audit deltas this session resolves:**
- Systemic-1 ("default shadcn everywhere") — primitive layer no longer reads as the unmodified new-york template
- P0-4 (theming layer broken) — every primitive now consumes tokens; no inline hex inside `gui/src/components/ui/`
- P1-1 (backdrop-blur on AutoRecoverRestoreModal) — Dialog scrim is now `bg-foreground/40` with no blur; consumer-side fix is mechanical
- P2-6 (arbitrary `text-[Npx]`) — primitive layer migrated to type-scale tokens; consumer migration deferred to `/impeccable polish`
- Doctrine §4 violations on `shadow-xs` on Input/Toggle/Select — all removed

**Tests:** 1028 / 1028 pass (same as canvas-locked baseline). tsc baseline:
10 errors (was 11 before this session — incidental drop, no new errors
introduced).

### Post-primitive walkthrough fixes (2026-05-22)

After first dev-server walkthrough of the primitive-layer pass, six
ordered corrections shipped on top:

| Commit | Fix |
|---|---|
| `25c98cf` | Borders dropped from chroma 0.012 → 0.005 (dark); popover lifted above canvas (0.265 → 0.33 dark, 1.0 → 0.96 light); menubar handoff fixed via instant close; control text 13 → 12 px on Button / Toggle / Menus / Tabs / Select / Command |
| `9f2f803` | Node ring color committed fully opaque (alpha compositing was bleeding canvas hue 254 into the "neutral" grey ring) |
| `e31e746` | `.stream-node--code-hover` / `.stream-node--code-pinned` CSS rules emptied to no-ops — the persistent "blue ring on non-Sources nodes" was that class painting sky-300 outline on top of the base ring |
| `c5d0c01` | Node ring (box-shadow only) moved from CSS class to inline `style={}` after diagnosis that Vite + Tailwind v4 + `.vite/deps` cache was serving stale compiled output for `.stream-node-*` class rules while body-level CSS HMR updated normally |
| `3c2961b` | Outline + outline-offset ALSO moved to inline style — the prior commit had left outline on the class, and the stale `.stream-node--code-pinned` `outline: 3px solid sky-300` rule was still painting through |
| `[cleanup]` | Long P-series comment blocks tightened; dead `.stream-node-ring-rest` / `.stream-node-ring-selected` CSS classes removed; `--node-ring-rest` consumed via inline `var()` for theme-awareness |

### ValidationPanel + ValidationStatusBar + unified bottom-chrome footer (locked 2026-05-22)

Full visual rebuild of the validator UX plus a chrome-topology refactor. The
data layer (validator results, severity sort, click-to-focus dispatch) was
already correct; this pass replaces the rendering + spatial layer wholesale
and merges the bottom-strip / panel-toggle chrome into a single 22 px
footer.

**Cluster commit (1):** `feat(72-validation): redesign ValidationPanel + unified bottom-chrome footer`

**Key commitments** (full detail in `DESIGN.md` §5):

- Row vocabulary: `ERR` / `WRN` / `INF` mono prefix, color-tokenized via
  `--destructive` / `--color-warning` / `--color-info`. No Lucide
  AlertCircle/Triangle/Info icons anywhere.
- Three-column row grid (absolute pixel widths, not `ch`): 32 px severity,
  200 px validator-id, fluid message. Pinned in px so the column-label row
  (10 px mono) and data rows (mixed 11/13 px) resolve identical columns.
- Validator ID leads the row (Linear-style rule-id pattern). The trailing
  10 px muted chip is gone.
- Resizable columns via drag handles between SEV/RULE and RULE/MESSAGE.
- Selected-row indicator: 2 px `--ring` left edge + `bg-popover` tint;
  clears on filter change or canvas click.
- Filter pills (ERR/WRN/INF) + group-by popover (None/Rule/Component) at the
  right of the panel header. Replace the prior banner-style `clear` flow.
- FixAction discriminated union deleted from `ValidationResult`. Rule
  emissions stopped emitting `fixAction:` in Phase 71 UAT; this session
  removed the type and the render branch.

**Unified bottom-chrome footer:**

- One 22 px always-present strip replaces the prior 14 px stub strip +
  22 px status bar pair (was 36 px of stacked chrome with no content when
  the panel was closed).
- Left cluster: severity segments `ERR 12 WRN 4 INF 2`. Click filters.
- Right cluster: `Code | Validation` tab buttons + explicit close chevron
  (visible only when panel open). Click an inactive tab → opens panel on
  that tab. Click active tab → closes. Active-tab indicator: 1 px `--ring`
  hairline at the tab's top edge.
- Source of truth for `activeBottomTab` moves from BottomPanel's header
  Tabs to the status-bar tabs. BottomPanel header keeps Copy / Export only.

**Right-click "Show generated Julia code" routing fix:**

- `useShowCodeFor.ts` now sets `activeBottomTab: "code"` in addition to
  opening the panel — the prior code only opened the panel without
  switching tabs, so right-clicking while on the Validation tab silently
  left the user on Validation.

**Tests:** 1038 / 1038 pass. tsc baseline 10 (unchanged).

### Loop-highlight system + validator targeting rewrite (locked 2026-05-22)

Reworked `gravity_sum_per_loop` to detect simple cycles correctly (not
SCCs), reclassified severities, and added a canvas-side loop-trace
visualization that the user can read at a glance.

**Cluster commit (1):** `feat(72-validation): loop-highlight system + gravity rule rewrite`

**Severity reclassification** (matches Phase 72 severity audit):

| Rule | Before | After | Why |
|---|---|---|---|
| `length_match` | error | warning | Code compiles, solver runs; physically inconsistent but not a compile-fail. |
| `gravity_sum_per_loop` | error | warning | Same — solver runs, the steady state is non-physical. |

**gravity_sum_per_loop algorithmic rewrite:**

- New `findAllSimpleCycles` in `lib/validation/loopTraversal.ts` —
  enumerates every simple directed cycle, rooted at the lowest node id to
  avoid duplicates. Replaces `findHydraulicLoops` (SCC-based) for this
  rule's needs. `loopClosure.ts` still uses the SCC traversal for its
  "any cycle?" check.
- Per-node ΣH walk uses BOTH entry-port and exit-port (not just exit) to
  handle "bounce" cases where the cycle visits a node via the same port
  it leaves on.
- Targets emitted per result are SCOPED to a single broken cycle: nodes
  and edges from THAT cycle only. Other cycles in the same SCC are
  unimplicated.
- Height-bearing components extended: Gravity (`H`) + Channel-family
  (`g × geometry.L` when `g != 0`). Matches Python STREAM
  `check_gravity_mismatch` convention (sum pressure drops per
  hydrostatic-bearing component around each loop).
- Project gravity cascade: `addNode` in `useStore.ts` initializes any new
  component's top-level `g` parameter from `modelOptions.g_default`
  (default Earth's 9.80665 m/s²) instead of the registry literal.
- Σ(g·h) check (not Σh): solver-relevant invariant is
  `ρ × g × h` integrated around a loop. We sum `g × h` per component
  using each component's own `g` (Channel uses its parameter; Gravity
  uses hardcoded 9.80665 matching the Julia STREAM `Gravity()` equation).
- Tight tolerance kept: `|Σ(g·h)| < 1e-5 m²/s²` ≈ 1 µm of effective
  height. A residual 1 mm would be a constant pressure source for the
  solver — physically wrong.
- Description format adaptive: `Loop ΣH = +3.40 mm (tol 1.02 µm)`.
  Units adapt by magnitude (m / mm / µm). Tolerance is disclosed inline.

**Canvas-side loop visualization:**

- New `.validation-flow-trace` CSS class with marching-ants animation
  (1.5 s linear infinite stroke-dashoffset). Severity-tinted via
  `--validation-trace-color` custom property. Reduced-motion fallback
  preserves the dashed pattern but stops the marching.
- New `.validation-flash-persistent` for steady-pulse node highlight
  (1.5 s infinite, color-mix at 40% transparency). Also reduced-motion
  aware.
- CanvasPanel handler detects multi-node-target results (≥2 nodes) and
  treats them as a TRACE: fitBounds to enclose all, apply persistent
  flash to nodes + flow-trace to edges. Single-node results keep the
  existing 600 ms one-shot navigation flash.
- Persistence: trace stays visible until any `mousedown` inside the
  ReactFlow viewport (matches the user's "stay until I look at something
  else" mental model).

**Tests:** 1047 / 1047 pass. tsc baseline 10.

### HydraulicEdge router + smart port-side convention (locked 2026-05-22)

Phase A (smart port-side assignment) and Phase B (obstacle-avoiding edge
router) shipped together. Built convention-driven port placement on top
of the existing Phase 64 local-geometry algorithm, then added an
orthogonal router that avoids node bodies.

**Cluster commit (1):** `feat(72-canvas): smart port placement + obstacle-avoiding edge router`

**Phase A — port-side convention** (`lib/autoflip.ts`):

- Aggregate-across-edges: a port with multiple connections now sums all
  neighbor vectors instead of using the first edge only.
- Dominant flow axis derived from cluster spread of NODE CENTERS
  (not full bboxes). Hydraulic components are wide and short; including
  widths would misclassify a clearly vertical layout as horizontal.
- 1.5× vertical bias: `flowAxis = (spreadY × 1.5 ≥ spreadX) ? vertical : horizontal`.
  Hydraulic loops are gravity-driven; the default leans vertical.
- Axis snap: a port's perpendicular-to-axis preference snaps to its
  "natural" side (port_in TOP/LEFT, port_out BOTTOM/RIGHT for vertical/
  horizontal). On-axis preferences are kept. Disconnected ports are
  EXEMPT from snap so D-11 (registry-default for isolated ports) stays
  intact.
- Collision resolution: ports never share a side. When both ports'
  preferences collide, both ports go to their natural sides (convention
  wins on both-connected). When only one port is connected, the
  connected port keeps its preference; the disconnected one moves to
  the opposite side.

**Phase B — obstacle-avoiding edge router** (`lib/edgeRouting.ts` + `HydraulicEdge.tsx`):

- 5 candidate paths per edge: naive Z-path, plus wraps via right / left /
  top / bottom lanes. Each lane sits at `outermost-bbox-edge ± laneMargin`.
- Source and target nodes are included as obstacles. The path is forced
  outside both bodies, not just other nodes'.
- Wrap pivots use CLUSTER-EDGE lanes (not port's own Y/X). For a T-shape
  topology where source/target sit inside the cluster, the wrap path
  extends from the source in its outward direction past the cluster
  bbox, travels along a side lane, and approaches target from outside.
  Guarantees zero crossings.
- Ranking: `(crossings, turns, length)` priority. Always picks the path
  with zero crossings if any candidate is clean.
- Rounded corners (~6 px) via quadratic Bezier joints — matches the
  prior smoothstep visual.

**Tests:** 1049 / 1049 pass. New tests:
- `edgeRouting.test.ts` — 9 tests, including a T-shape regression test
  matching `imp_bad_edges.png` topology (verifies zero crossings).
- `autoflip.test.ts` — 23 tests, including convention-driven layouts
  for vertical 2-node loops and the off-axis-neighbor case from
  `imp_edge_bug2.png`.

### First-run empty-canvas hint (locked 2026-05-22)

Replaces the prior `WelcomeOverlay` (centered rounded card with shadow-lg +
"to get started" copy + div-onClick recent rows) — the canonical PRODUCT.md
anti-reference and the single highest-priority audit finding (P0-1). Built
through `/impeccable shape first-run`; brief was compact because doctrine
pinned the vast majority of the design (engineering voice, no card/shadow/
rounded panel, canvas-as-lightest, Restrained).

**Single commit:** `feat(72-first-run): chromeless typographic anchor replaces WelcomeOverlay card`

**Three confirmed locks** (via AskUserQuestion during shape):
1. Topology = centered chromeless block (over bottom-center status line / completely empty canvas)
2. Wordmark = none (titlebar already carries app identity)
3. Recents surfacing = tight mono list inline (over File-menu-only / two-column with dates)

**Key commitments** (full detail in `DESIGN.md` §5):

- `w-[280px]` block, absolute-centered in canvas, pointer-events split:
  outer wrapper passes through (canvas pan/zoom/drag-drop unaffected on
  the empty area surrounding the hint); inner block accepts clicks.
- Two-column shortcut keymap: mono chip (`w-16` fixed) + sans label.
  Static text — the keybind IS the affordance. Three rows:
  `Ctrl+O open project` / `Ctrl+N new` / `Ctrl+P command palette`.
- Recents (when present): mono `text-label` `<button>` rows, basename
  stem (extension stripped), native `title=` for full path, max 5,
  rounded-sm + `hover:bg-card` + 80 ms transition-colors + focus-visible
  ring-2, `motion-reduce:!duration-0`. Hairline `--border` separator
  between recents and keymap. Lowercase section label `recent`
  (`text-micro mono foreground/45`).
- Shortcut glyph idiom: plain `Ctrl+...` matching the menubar
  (FileMenu/EditMenu literal `Ctrl+O` style). No `⌘`/Ctrl branching.

**Audit deltas this session resolves:**
- P0-1 (textbook consumer-SaaS empty state — verbatim PRODUCT.md
  anti-reference) — entire surface rebuilt
- P2-1 (`<div onClick>` recent rows lacked keyboard nav) — recents are
  now real `<button>` elements with proper keyboard nav + focus-visible
  ring
- Critique P1-1 (working-memory overload on first render) — block went
  from card+heading+helper-paragraph+button (4 distinct attention units)
  to recents + 3-row keymap; the keymap reads as a single typographic
  unit
- "to get started" verbatim anti-reference copy — deleted

**Tests:** 1049 / 1049 pass. tsc baseline 10 (unchanged). No tests
existed for `WelcomeOverlay` (still none — surface is doctrine-locked
visual + a `<button>` click path already covered by store-action tests).

### Help system (locked 2026-05-22)

Three coordinated artifacts that close the Critique P0-2 "no in-app help"
gap. Shipped through `/impeccable shape help-system`; brief was compact for
artifacts 1 and 2 (doctrine pinned almost everything) and discovery-led for
the Anatomy dialog (user explicitly added it to scope mid-discovery, asking
for an "appliance-guide-style visual cheatsheet").

**Cluster commit (1):** `feat(72-help): tooltip discipline + cmdk shortcut mode + anatomy dialog`

**Three confirmed locks** (via AskUserQuestion during shape):
1. Shortcut overview surface = cmdk in shortcut mode (over Sheet, over centered card)
2. Anatomy scope = Node + Edges (over node-only, over node + edges + layers)
3. Tooltip discipline = icon-only + shortcut-bearing-without-visible-binding (over icon-only-only, over "every actionable element")

**User-driven scope expansion (mid-discovery):** the Anatomy dialog wasn't in
the original brief; the user surfaced an "appliance-guide visual cheatsheet"
idea that fit the doctrine perfectly (schematic-legend tradition; Houdini
node-anatomy reference). Brief expanded; rendering strategy locked as
"real-component mirror" (visual fidelity to StreamNode without consuming the
zustand selectors that would force every store path to be stubbed in a
non-canvas context).

**Key commitments** (full detail in `DESIGN.md` §5):

- **Tooltip consumption discipline.** Two cases earn a Tooltip: (a) icon-only
  chrome controls where label is implicit, (b) clickable surface with a
  keyboard shortcut whose binding isn't already visibly displayed. Concrete
  inventory: WindowControls Min/Max/Close (Windows/Linux variant),
  ValidationPanel Group-by sliders icon, ValidationStatusBar close chevron
  (Ctrl+`). Explicitly excluded: menubar items, LayersPanel rows,
  status-bar Code/Validation tab buttons, App.tsx collapsed-edge re-expand
  strips. The Tooltip-Earns-Its-Pixels Rule.
- **cmdk shortcut mode.** `?` keybind opens existing palette in
  `mode: "shortcuts"`. Mode chip in the palette header swaps modes
  in-place; swapping clears search. Rows are read-only — closing the
  palette on select but NOT invoking the underlying action (mirrors the
  first-run Shortcut-Is-Static-Text Rule). `gui/src/lib/shortcuts.ts` is
  the SSOT for the catalog; new keybinds must be added there.
- **Anatomy dialog.** Modal Dialog (`!max-w-[920px]`), two tiles side by
  side (Node | Edges) on the canvas grid texture. Numbered callout chips
  (18×18 px rounded-sm mono micro) overlaid via absolute positioning;
  legend lists below each tile; `not all states co-occur on a real node`
  footnote at the bottom. Marching-ants edge animation scoped locally as
  `anatomy-flow-march` (so it doesn't depend on xyflow's
  `.validation-flow-trace .react-flow__edge-path` global selector).
- **HelpMenu rebuilt.** Shortcuts (with `?` shortcut chip) / Anatomy /
  About. The prior disabled `Keyboard Shortcuts` stub is removed. Both
  new entries dispatch custom events (`stream:open-shortcuts`,
  `stream:open-anatomy`) listened to in App.tsx — same pattern as
  `stream:open-save-preset`, no prop drilling.

**Files touched (production):**

- New: `gui/src/lib/shortcuts.ts` (SHORTCUTS_CATALOG SSOT)
- New: `gui/src/components/AnatomyDialog.tsx`
- Updated: `gui/src/components/CommandPalette.tsx` (mode prop + ShortcutGroups + ModeChip)
- Updated: `gui/src/App.tsx` (`?` keybind + custom-event wiring + AnatomyDialog mount + paletteMode state)
- Updated: `gui/src/components/HelpMenu.tsx` (two new entries, stub removed)
- Updated: `gui/src/components/WindowControls.tsx` (Tooltip on Windows/Linux buttons)
- Updated: `gui/src/components/ValidationStatusBar.tsx` (Tooltip on close chevron)
- Updated: `gui/src/components/ValidationPanel.tsx` (Tooltip on Group-by sliders icon, nested asChild with PopoverTrigger)

**Files touched (tests):** ValidationPanel / ValidationStatusBar /
WindowControls test files wrap their renders in `<TooltipProvider
delayDuration={0}>` because tooltips that mount in isolation need a provider
in scope. Production-side, the one provider lives at the app root in
`App.tsx` (existing).

**Tests:** 1046 / 1050 pass (the 4 failing are the pre-existing
`codeGenerator.smoke.test.ts` fixture-missing baseline, unchanged). tsc
baseline 10 errors (unchanged — none of the 10 are in surfaces this session
touched).

### BCEdge + HydraulicEdge + CodePreview tokenization (locked 2026-05-23)

Closes the last hardcoded-hex signature surfaces flagged by Audit P0-4
(`BCEdge.tsx:114–117`, `HydraulicEdge.tsx:70–75`, `CodePreview.tsx:460`).
Three coupled surfaces in one session because they share the Phase 66
bidirectional canvas↔code link signal.

**Cluster commit (1):** `feat(72-tokens): BCEdge + HydraulicEdge + CodePreview retoken`

**Three confirmed locks** (via AskUserQuestion during shape):
1. Code-link active state = **`--foreground` neutral** (over magenta hue 340,
   over `--ring` reuse, over `--chart-5` reuse). Initial proposal was a new
   `--color-code-link` magenta token; user pushed back ("is that color
   fitting the software? wouldn't it be too strong?"). Honest reconsideration
   landed on neutral high-contrast as the most tool-grade move: the link
   state is FOCUS, and `--foreground` is literally that semantic. No new
   hue earned.
2. CodePreview body = **inherit `--panel`** (no `--code-surface` token, no
   GitHub-dark borrow). Depth hierarchy already carries the tonal step.
3. Syntax palette = **One Dark Pro anchored** + documented "Code editor
   lane" carve-out (parallel to WindowControls' platform-mimicry
   exemption). User explicitly delegated theme choice: "look online on
   user trusted and accepted and liked Julia themes". One Dark Pro chosen
   for install count + Julia heritage via Juno/Atom.

**Tokens introduced** (5 new — fewer than the original brief because the
code-link hue was dropped in favor of `--foreground`):

| Token | Dark | Light | Surface |
|---|---|---|---|
| `--syntax-keyword` | `oklch(0.74 0.16 295)` | `oklch(0.55 0.18 295)` | CodePreview only |
| `--syntax-string`  | `oklch(0.78 0.14 145)` | `oklch(0.55 0.16 145)` | CodePreview only |
| `--syntax-type`    | `oklch(0.78 0.11 230)` | `oklch(0.55 0.14 230)` | CodePreview only |
| `--syntax-macro`   | `oklch(0.83 0.13 80)`  | `oklch(0.60 0.17 80)`  | CodePreview only |
| `--syntax-number`  | `oklch(0.78 0.13 50)`  | `oklch(0.58 0.17 50)`  | CodePreview only |

Syntax comments reuse `--muted-foreground` (italic) — the muted family is
already correct for "deprioritized prose inside code".

**Concrete surface changes:**

- **BCEdge + HydraulicEdge — final form** (after two iterations of live
  verification): `.code-link-active` CSS class applied to the `<path>`
  via `BaseEdge`'s className prop. Class rule sets stroke = `--foreground`,
  `stroke-dasharray: 6 4`, animation = `flow-trace-march 1.2s linear
  infinite` (reuses the validation-flow-trace keyframe). `.code-link-pinned`
  modifier bumps stroke-width 1.5 → 1.75 (barely heavier than hover).
  Marching motion is the primary signal — strokeWidth changes are minimal.
  `prefers-reduced-motion: reduce` stops the marching but keeps the dashed
  pattern. The old softened-color + width-ladder approach (`color-mix`
  hover, full `--foreground` pin at 1.5 / 2.0) was abandoned because
  multiple highlighted edges still made the canvas pulse — static
  contrast can't escape that. Motion-as-state is the durable answer.
- **Custom arrowhead marker**: `<marker id="stream-hydraulic-arrow"
  markerUnits="userSpaceOnUse" markerWidth="12" markerHeight="12">` defined
  once in CanvasPanel inside a hidden `<svg>`. Replaces xyflow's
  `MarkerType.ArrowClosed` (which uses `markerUnits="strokeWidth"` and
  scales 1:1 with stroke). `useStore.createEdges` switches to
  `markerEnd: "url(#stream-hydraulic-arrow)"`. `MarkerType` import removed
  from useStore. Fill is `var(--muted-foreground)` always; arrow is
  structural, not a state signal.
- **Active-edge zIndex bump**: `enrichedEdges` in CanvasPanel subscribes
  to `hoveredSourceIds` + `pinnedSourceIds` (selective subscriptions; the
  PERF comment's warning was about whole-store destructuring) and bumps
  `zIndex: 1500` on any edge whose both endpoints are in either set.
  Above xyflow's default selected-zIndex of 1000 so active edges always
  paint on top. Fixes the "marching dashes appear behind overlapping
  static line" bug — SVG paint order is DOM order, `z-index` doesn't
  apply to SVG siblings.
- **ValidationStatusBar — severity icons replace text labels.** The left
  cluster `ERR 12 WRN 4 INF 2` mono text → Lucide `CircleX` /
  `TriangleAlert` / `Info`, color-tokenized via `--destructive` /
  `--color-warning` / `--color-info`. Reads as the IDE status-bar lineage
  (VSCode/IntelliJ/Sublime/Eclipse). Doctrine carve-out documented in
  DESIGN.md §5 unified bottom-chrome footer ("The Status-Bar-Icons-Are-
  The-IDE-Convention exception"). Tests pass unchanged (they assert via
  aria-label, not literal text).
- **ValidationStatusBar — size + alignment iteration.** After live
  verification: bar 28 → 32 px, icons 14 → 18 px (stroke 1.5 → 1.75),
  count text 13 → 15 px. The count span is now `inline-flex items-center
  h-[18px]` so the digit visually centers within the same 18 px box as
  the icon — `leading-[18px]` alone wasn't enough because mono digit
  baselines anchor to the box bottom (no descenders), putting the
  visible digit visibly below the icon's centered glyph. Right cluster
  text + chevron icon harmonized to match.
- **ValidationPanel — severity relabel to full words + bigger filter
  controls.** `SEVERITY_LABEL` 3-letter `ERR/WRN/INF` → lowercase full
  words `error / warning / info`. Applied in both the row severity cell
  AND the filter pills (single source of truth). SEV column width
  default 32 → 80 px (min 28 → 60, max 64 → 120) to fit the longest
  label. FilterPill bumped text 11 → 13 px, padding px-1.5 py-1 →
  px-2.5 py-1.5 (~50% larger hit area + better visual weight against
  the bottom panel's empty space). GroupBy slider icon 3.5 → 4 (16 px),
  padding harmonized to match. Row SEV cell text 11 → 13 px (matches
  RULE / MESSAGE for cross-row uniformity); dropped `tracking-tight`
  since the full word doesn't need abbreviation-style condensation.
  Tests updated: `getAllByText("ERR")` → `getAllByText("error")`. All
  pass. Carve-out doctrine in DESIGN.md §5 explicitly notes the status-
  bar still uses icons (no room for full words there) while the panel
  uses words (no room shortage; words read better at a glance).
- **StreamNode — final form**: code-link box-shadow ring via inline
  style + `data-code-link` attribute on root. Hover ring = 2 px solid
  `--foreground`; pinned ring = 3 px solid `--foreground`; selected
  (3 px `--ring`) wins. Integer spreads (no more 2.5 px — sub-pixel
  rounding made the bottom render fatter than the top). The
  `transition-[box-shadow] duration-200` was removed for non-selected
  states — code-link snaps because the edge marching is the
  ongoing signal and the ring just needs to mark "which nodes" without
  a 200 ms ease that read as laggy on every click. Selected keeps its
  transition (band thickens 4 → 8 px in sync; gentle is right). The
  `.stream-node--code-hover` / `.stream-node--code-pinned` className
  additions are gone (they were dead-state markers — the CSS rules
  were no-ops); state marker moved to `data-code-link="hover|pinned"`.
  Tests rewritten to assert on `data-code-link`.
- **CodePreview**:
  - Body `bg-[#0d1117]` removed → inherits `--panel`.
  - Body text `text-zinc-200` → `text-foreground`.
  - Section-header dot slab (`bg-sky-400/80`) + heading color (`text-sky-300/90`)
    → muted-foreground uppercase tracking, no marker.
  - Sub-block `border-l-2 cursor-pointer` → `rounded-sm cursor-pointer`
    (absolute-ban side-stripe removed).
  - Sub-block hover: `hover:bg-sky-500/[0.09] hover:border-sky-400/60` →
    `hover:bg-[color-mix(in_oklch,var(--foreground)_5%,transparent)]`.
  - Sub-block pinned: `bg-sky-500/[0.14] border-sky-400 ring-1 ring-sky-400/40` →
    `bg-[color-mix(in_oklch,var(--foreground)_8%,transparent)] ring-2 ring-[var(--foreground)]`.
  - Sub-block flash: `bg-amber-500/30 border-amber-400 ring-1 ring-amber-400/70` →
    `bg-[color-mix(in_oklch,var(--color-warning)_22%,transparent)] ring-2 ring-[var(--color-warning)]`.
  - `TOKEN_CLASS` map: 6 raw Tailwind classes → 5 `--syntax-*` arbitrary-
    value classes + `text-muted-foreground italic` for comments.
  - Empty-state copy `text-zinc-500` → `text-muted-foreground`.
  - Transition duration tightened 150 ms → 80 ms (matches primitive-layer
    motion vocabulary locked in the shadcn-primitive-layer pass).

**Audit deltas this session resolves:**
- **P0-4** (theming layer broken) — closes the last three file-list entries
  (BCEdge, HydraulicEdge, CodePreview). All signature surfaces now consume
  tokens; the only remaining hardcoded hex in `gui/src/` is documented
  exception territory (WindowControls' macOS traffic-light values).
- **P1-3..P1-8** (hardcoded colors across signature surfaces) — completed.
- **P2-4** (colored `border-l-2` accent stripes) — `CodePreview.tsx:224`
  removed. `FunctionSelect.tsx:125` is the remaining site (deferred to
  polish pass).
- Critique P1-2 (visual consistency drift) — last raw-Tailwind color
  references in signature surfaces resolved.

### Harden pass — prefers-reduced-motion + div→button + WCAG AA contrast (locked 2026-05-23)

Cross-cutting hardening pass that closes Audit P0-3 + the Critique "Sam"
(accessibility-dependent) persona gripes without re-litigating any locked
design choice. Three coupled fixes shipped in one commit:

**Single commit:** `harden(72): prefers-reduced-motion + div→button + WCAG AA contrast`

**prefers-reduced-motion sweep:**

- `index.css` — added a belt-and-suspenders global `@media (prefers-
  reduced-motion: reduce)` block using the WebKit-recommended universal
  selector idiom (`*, *::before, *::after` → `animation-duration: 0.01ms
  !important`, `animation-iteration-count: 1 !important`,
  `transition-duration: 0.01ms !important`, `scroll-behavior: auto
  !important`). The shadcn primitive layer already carries per-class
  `motion-reduce:!duration-0` / `motion-reduce:transition-none`; this
  global rule catches anything that slips the net — Tailwind's
  `animate-pulse` on `PresetsPanel` skeletons, third-party transitions in
  `@xyflow/react`, any future surface. Per-surface `@media` blocks for
  the canvas marching-ants idioms (`.validation-flow-trace`,
  `.code-link-active`, `.validation-flash-persistent`) stay — defense in
  depth.
- `lib/scrollIntoViewSafe.ts` — motion-aware wrapper around
  `Element.scrollIntoView`. The JS `behavior: "smooth"` option is NOT
  affected by CSS `scroll-behavior: auto` under reduced motion; every
  call site that opts into smooth scrolling must consult `matchMedia` at
  call time. Single chokepoint replaces four scattered sites:
  - `ValidationPanel.tsx` (node-filter scroll, line 204)
  - `CodePreview.tsx` (show-code-for scroll, line 408)
  - `SidebarPanel.tsx` (open-property-field scroll, line 118)
  - `ResourcesTreePanel.tsx` (selected-resource scroll, line 61)
- `PresetsPanel` skeleton `animate-pulse` — covered by the global rule;
  no per-site `motion-reduce:animate-none` needed.

**div-as-button conversion:**

- `ValidationPanel` `Row` — was `<div role="button" tabIndex={0}
  onKeyDown>` (correct for axe-core but a semantic shim). Converted to
  native `<button type="button">`: drops the role / tabIndex / onKeyDown
  shim (button has native Enter/Space activation + tab-order
  participation), resets default button font/align with `text-left
  font-normal w-full`, updates `firstRowRef` typing
  `HTMLDivElement` → `HTMLButtonElement`, updates `RowProps.ref` type.
  Tests assert via `getAllByRole("button")` and remain green —
  `<button>` carries the role natively. `type="button"` guards against
  any future placement inside a `<form>` (no accidental submit).
- Other surveyed sites are correct as-is:
  - `PresetRow.tsx:172` — `<li tabIndex={0} draggable>` is a drag-
    source row, not a button. Buttons inside `<li>` lose Chromium's
    draggable scope.
  - `ResourceRow.tsx:268` — `<li role="treeitem" tabIndex={0}>` is the
    correct tree pattern.
  - `BottomPanel.tsx:133` — `<span tabIndex={...}>` wraps a disabled
    Button for the Radix tooltip-on-disabled-button idiom.
  - `ResourceReferencePicker.tsx:193`, `ResourceGroupHeader.tsx:101` —
    same disabled-tooltip wrapper.
  - `CanvasPanel.tsx:605,741`, `ResponsiveTabsList.tsx:185` —
    `tabIndex={-1}` programmatic focus targets, not tabbable.

**WCAG AA contrast:**

Computed OKLCH→sRGB→relative-luminance for every most-used token pair
against canvas / panel / chrome / popover / card (`/tmp/contrast.mjs`).
Three real violations of the locked 4.5:1 body-text floor:

| Token | Mode | Old | New | Why |
|---|---|---|---|---|
| `--muted-foreground` | dark | `oklch(0.50 0.01 250)` (2.51:1 on canvas) | `oklch(0.65 0.01 250)` | 4.48 canvas (within rounding of 4.5), 5.27 panel, 5.78 chrome, 5.02 card. On `--popover` (lifted in dark) it reads 3.63:1 — passes 3:1 large/icon floor but not body. Code discipline: use `--foreground/85` for body inside popover/dialog content. |
| `--muted-foreground` | light | `oklch(0.556 0 0)` (4.47:1 on panel) | `oklch(0.50 0.005 254)` | 5.83 canvas, 5.67 panel, 5.34 popover, 5.50 card. Also aligns chroma 0 → 0.005 hue 254 (was a chroma-0-on-pure-neutral degenerate case the dev pipeline warns about). |
| `--color-warning` | light | `oklch(0.74 0.16 75)` (2.23:1 on panel) | `oklch(0.55 0.16 75)` | 4.62 canvas, 4.48 panel. Hue + chroma unchanged so the perceptual identity stays. |
| `--color-info` | light | `oklch(0.62 0.18 240)` (3.26:1 on panel) | `oklch(0.535 0.18 240)` | 4.59 canvas, 4.46 panel. |

Dark `--color-warning` (0.78) and `--color-info` (0.72) already clear
8.66 and 7.27 on panel — unchanged. Dark `--destructive` already clears
6.12 on panel — unchanged. Light `--destructive` sits at 4.50:1 (right
at the line) — left alone (within float-rounding of the floor; pushing
it darker would alter brand identity).

`foreground/65` on dark canvas computes 4.45:1 — within float-precision
tolerance of 4.5; leave the alpha gradation as-is. The locked
foreground value (`oklch(0.73 0.012 250)`) is intentional and changing
it would cascade across every surface.

**Audit deltas this session resolves:**
- **Audit P0-3** (no `prefers-reduced-motion` respect anywhere) —
  fully closed. Global rule + JS chokepoint cover every animation,
  transition, and JS scrollIntoView site.
- **Critique Sam (accessibility-dependent) persona** — div-as-button
  shim removed from ValidationPanel rows; native semantics throughout.
- **Critique unaudited WCAG AA contrast** — spot-checked + tightened.
  The 3 token fixes cover the three real body-text violations across
  both modes.

**Tests:** 1046/1050 (4 failures are pre-existing
`codeGenerator.smoke.test.ts` fixture-missing baseline, unchanged).
tsc baseline: 10 errors, unchanged.

### Clarify pass — em-dash purge + engineering-voice empty states (locked 2026-05-23)

Cross-cutting copy pass that closes Audit P2-3 + the locked
engineering-voice doctrine (`feedback_engineering_voice_copy`). Single
commit, mechanical mostly, with a few opinion calls on what "engineering
voice" actually means at the empty-state level.

**Single commit:** `clarify(72): em-dash purge + engineering-voice empty states`

**Em-dash purge** across every user-visible string (locked DESIGN.md +
PRODUCT.md "no em-dashes" rule):

| Site | Before | After |
|---|---|---|
| `useStore.ts` SENTINEL_POWER_SHAPE_NAME | `"(leave unset — set in code)"` | `"(leave unset; set in code)"` |
| `AboutDialog.tsx` version placeholder + catch | `"—"` (×2) | `"unknown"` (×2) |
| `BottomPanel.tsx` Export-button tooltip | `"...errors — code won't compile"` | `"...errors (code won't compile)"` |
| `lib/exportCode.ts` toast | (same as above) | parens |
| `CommandPalette.tsx` off-layer chip title + aria-label | `"X layer off — will enable on select"` | `"X layer off; will enable on select"` |
| `PresetsPanel.tsx` console.error | `"...(path may be outside FS scope — see CR-01)"` | comma |
| `CodePreview.tsx` empty body | `"(empty — add components on the canvas to see generated Julia code)"` | `"No code yet."` (also drops hand-holding) |
| `ResourcesTreePanel.tsx` group placeholder (×3 groups) | `"(none yet — click +)"` | `"(none)"` |

The sentinel-name change cascaded through 28 test files (mechanical
sed). Sentinel string also lives hardcoded at
`ResourceReferencePicker.tsx:165` (duplicated rather than imported from
the SENTINEL_POWER_SHAPE_NAME constant); the sed swept it consistently —
that duplication is a separate code-smell, out of scope for clarify.

**Engineering-voice empty-state rewrites:**

- **PresetsPanel** — three rewrites:
  - "No project open" body: `"Open a project to use the Project store."`
    → `"No project open."` (single declarative, drops the "store" jargon
    and the imperative "open a project").
  - "No project presets" body: dropped the instruction line
    `"Multi-select components and right-click to save."` Kept
    `"No project presets."` (dropped "yet" — emotive suffix).
  - "No library presets" body: dropped the canonical hand-holding line
    `"Save a selection to add your first template."` Kept
    `"No library presets."`
- **SidebarPanel** — dropped the per-tab variantCopy second sentence
  (`"Select a resource to edit it."` /
  `"Select a component to view its properties."`). The right panel IS
  the property panel by definition — restating that in the empty state
  is consumer-SaaS hand-holding. `"No selection"` heading alone reads as
  status, not as instructions. Removed the now-unused
  `activeLeftTab` selector. `SidebarRouter.test.tsx` updated: two
  variantCopy assertions rewritten to assert on `"No selection"`.
- **CodePreview** — `"No code yet."` matches the ValidationPanel
  `"No issues."` idiom: declarative, no italic, no parenthesis. The
  prior italic-parenthetical-with-instruction was both italic
  (decoration) AND restating-the-obvious (the canvas is the only place
  to add components).
- **ResourcesTreePanel** — `"(none)"` matches the established
  "parenthetical-status" pattern from other compact lists. The prior
  `"(none yet — click +)"` did three things at once: status + emotive
  suffix + restated-visible-affordance.

**Surfaces NOT changed** (deliberate):

- **ValidationPanel** `"No issues."` — already canonical.
- **CommandPalette** `"No bindings."` / `"No matches."` — already
  canonical.
- **ResourceReferencePicker** `"No geometries. Use + New or the
  Resources tab."` — wayfinding pointer (the picker IS the discovery
  surface for + New + a separate tab); not hand-holding.
- **BottomPanel** `"No components"` tooltip — single declarative.

**The Empty-State-Reads-As-Status Rule.** Engineering-voice empty
states answer "what's the state?" with a noun phrase or single
sentence. They do NOT answer "what should I do?" — that's hand-holding
in surfaces where the affordance is visible (canvas, "+ New" buttons,
context menus). The doctrine carve-out for ResourceReferencePicker is
that pickers ARE discovery surfaces, so wayfinding to adjacent
affordances (the Resources tab) is in-bounds.

**Audit deltas this session resolves:**
- **Audit P2-3** (em dashes in user-visible strings) — every flagged
  site rewritten, plus three additional sites found during the sweep
  (BottomPanel/exportCode tooltip, CommandPalette off-layer chip,
  CodePreview empty state, ResourcesTreePanel group placeholders).
- **`feedback_engineering_voice_copy`** (specifically the
  `"Save a selection to add your first template."` line called out as
  the canonical hand-holding pattern to remove) — closed.
- **Critique minor observations** on PresetsPanel + SidebarPanel
  consumer-SaaS framing — closed.

**Tests:** 1046/1050 (4 pre-existing fixture failures, unchanged).
tsc baseline: 10 errors, unchanged.

### Polish pass — type-scale + section-header + border-l-2 sweep (locked 2026-05-23)

Cross-cutting polish pass that promotes the locked primitive-layer choices
(type-scale tokens, ValidationPanel column-label idiom, locked Dialog vocab)
across the remaining consumer surfaces. Mechanical mostly. Closes the last
three Audit findings that were deferred from prior sessions and brings the
ad-hoc-survivor dialogs onto the locked primitive layer.

**Single commit:** `polish(72): type-scale tokens + section-header retoken + ad-hoc-value sweep`

**1. Type-scale token migration (Audit P2-6).**

Replaced every `text-[10|11|13|16|20px]` arbitrary value in consumer surfaces
with the locked `--text-{micro,label,body,title,display}` token utilities.
Same scale (10/11/13/16/20 px); the rewrite enforces SSOT — restyling those
sizes now happens in `index.css` `@theme inline`, not across 30 files.

The primitive layer was migrated in the shadcn-primitive-layer shape pass;
this closes the consumer-side migration that was explicitly deferred.

Carve-outs kept verbatim:

- `text-[12px]` — control-text density (Button / Input / Toggle / Tabs /
  Select / Menu items / property-form Labels). Locked primitive-layer
  convention; intentionally off-the-five-tier-scale.
- `text-[15px]` — ValidationStatusBar count text. Locked status-bar
  carve-out (DESIGN.md §5).
- `text-base` on the body-level Anatomy node mirror — already routed via
  Anatomy's "visual mirror" strategy; one site, switched to `text-title`
  inline to consume the token rather than the Tailwind default.

Off-scale `text-[14px]` instances (SidebarPanel empty-state body,
ResourceReferencePicker placeholders) migrated to `text-body` (13 px).
13 px reads closer to the body-text density of the rest of the chrome;
14 px was a Tailwind-default leak.

**2. `text-xs` / `text-sm` Tailwind defaults swept.**

- `text-xs` (12 px) — drift target. Three flavors:
  1. Redundant on menubar triggers (primitive already sets `text-[12px]`):
     dropped. `text-xs font-normal` → `font-normal` on FileMenu / EditMenu /
     ViewMenu / HelpMenu triggers.
  2. Inline shortcut spans inside menubar items (`<span className="text-muted-foreground text-xs">Ctrl+Z</span>`):
     refactored to `<MenubarShortcut>Ctrl+Z</MenubarShortcut>` so the locked
     shortcut-chip idiom (`text-micro font-mono text-foreground/55`) flows
     from the primitive. The `<span className="flex justify-between w-full
     items-center gap-4">` wrapping (manual right-alignment) is gone —
     MenubarShortcut does `ml-auto` itself. Net DOM is simpler AND
     on-brand.
  3. Status/body text outside menubars (CodePreview empty state,
     CustomTitlebar filename, BCEdge mid-tag, error hints below inputs):
     mapped to `text-label` (11 px from the token scale).
- `text-sm` (14 px) — Tailwind default, off-scale. Migrated to `text-body`
  (UnsavedChangesDialog description, AboutDialog body, AutoRecover body).
  `text-sm font-medium` Recover/Discard buttons in AutoRecoverRestoreModal
  switched to the `<Button>` primitive (locked default size + variant).
- `text-base` — 16 px = `text-title`. Migrated InstanceNameField input
  emphasis and Anatomy mirror instance label.

**3. `border-l-2` colored side-stripe — last absolute-ban survivor (Audit P2-4).**

`FunctionSelect.tsx:125` sub-fields container — replaced `border-l-2
border-muted pl-3` with `border-l border-border pl-3`. The absolute ban
targets stripes >1 px used as colored accents; a 1 px neutral hairline is
within the ban's exemption and carries the "nested under selection"
structural cue without violating doctrine.

Test selector moved from `.border-l-2` querySelector to
`data-testid="function-subparams"` so future styling iterations don't
break test assertions on incidental classes.

**4. Section-header pattern retokened to the ValidationPanel column-label idiom.**

Six surfaces aligned to the locked compact-uppercase-header idiom
(`text-micro font-mono uppercase tracking-wide text-foreground/45`):

- LayersPanel "Layers" group label (was `text-[10px] font-semibold sans
  text-muted-foreground tracking-[0.08em]`)
- ResourceGroupHeader "Geometries / Power Shapes / Fluids" labels (was
  `text-xs font-semibold sans uppercase tracking-wide text-muted-foreground`)
- PresetsPanel "Project / Library" headers
- ToolboxPanel "Hydraulic / Thermal / Sources" categories
- SidebarPanel `<h2>` + `<h3>` ("Components / Resources / Project / Anchors
  / External Inputs")
- ParameterForm section group headers
- BCsTabForm group-base-field header
- ModelOptionsPanel "Solver Defaults"
- CodePreview section headers (was `text-[11px] font-semibold sans
  tracking-[0.12em] text-muted-foreground`)

Single section-header vocabulary across the chrome. Prior treatments lived
across at least three idioms (sans/mono, semibold/regular, 10/11/12 px,
muted-foreground/foreground-45); they now read as one.

**5. Locked-Dialog vocab applied to the two hand-rolled dialogs.**

- `AutoRecoverRestoreModal` (Radix Dialog directly, not the shadcn Dialog
  primitive — it pre-dates the primitive layer):
  - Scrim `bg-black/60 backdrop-blur-sm` → `bg-foreground/40` (locked
    Dialog scrim; closes Audit P1-1 glassmorphism finding).
  - Surface `rounded-lg bg-background shadow-xl` → `rounded-md bg-popover
    shadow-[var(--shadow-dialog)]` (locked surface vocab).
  - Custom-styled `<button className="px-4 py-2 text-sm font-medium
    rounded-md ...">` actions → `<Button>` primitive (one with className
    override for destructive intent on outline variant).
  - `AlertTriangle text-yellow-500` → `text-[color:var(--color-warning)]`
    (the last raw Tailwind color in `gui/src/` outside documented
    carve-outs).
- `UnsavedChangesDialog` (hand-rolled overlay, similarly pre-primitive-
  layer):
  - Scrim `bg-black/50` → `bg-foreground/40`.
  - Surface `rounded-lg bg-background shadow-lg` → `rounded-md bg-popover
    shadow-[var(--shadow-dialog)]`.
  - `<h2 className="text-base font-semibold">` title → `text-title
    font-semibold`.
  - Description `text-sm text-muted-foreground` → `text-body
    text-foreground/65`.

These were the two remaining hand-rolled dialogs in `gui/src/` that bypassed
the shadcn Dialog primitive. The locked vocab now reads through to both,
closing the gap left by the primitive-layer recommit.

**6. ModelOptionsPanel textarea → Textarea primitive.**

The Description field was a hand-styled `<textarea>` carrying every
pre-primitive-layer shadcn default the brief banned (`shadow-xs`, doubled
3 px focus ring, `md:text-sm`, `dark:bg-input/30`). Switched to the locked
`<Textarea>` primitive (`rounded-sm`, `text-body`, `border-hover` lift,
2 px inset focus ring). Net: one fewer surface bypasses the primitive
layer; one component file's `cn` import removed as a side-effect.

**7. Canvas-menu floating buttons — ambient shadow removed.**

ZoomIn / ZoomOut / FitView / SnapToGrid / InteractiveLockButton had
`shadow-sm` on their button shells. Doctrine §4 reserves shadows for modal
lift only; ambient atmospheric shadows on chrome controls are prohibited.
The buttons sit on the canvas as floating overlays — the `bg-background
border-border` already provides the tonal step + edge against the canvas
surface; the shadow was atmospheric. Removed across all five files.

**Audit deltas this session resolves:**

- **Audit P2-4** (colored `border-l-2` accent stripes) — FULLY closed.
  FunctionSelect was the last known site; CodePreview was removed during
  the BCEdge/CodePreview tokenization session.
- **Audit P2-6** (arbitrary `text-[Npx]` sizes) — FULLY closed for consumer
  surfaces. The primitive layer was already migrated; this pass cleared
  the consumer side. Locked carve-outs (12 px control text, 15 px status
  bar) intentionally retained.
- **Audit P1-1** (backdrop-blur glassmorphism on AutoRecoverRestoreModal) —
  FULLY closed. Scrim retokened; blur removed.
- **Audit P1-3..P1-8 systemic remainders** — every signature surface that
  still carried raw Tailwind colors closed. The only remaining hardcoded
  values in `gui/src/` are documented exception territory (WindowControls
  macOS traffic-light hex + the close-button red-600 platform mimicry).

**Files touched (production, 36):** consumer surfaces only; no primitive-
layer changes (those were locked previously). Imports added: `MenubarShortcut`
to FileMenu / EditMenu (existing in ViewMenu); `Button` to
AutoRecoverRestoreModal; `Textarea` to ModelOptionsPanel.

**Tests:** 1046/1050 (4 pre-existing fixture failures, unchanged). One test
assertion updated (`BCsTabForm.test.tsx` "BC required — select a mode" →
"BC required; select a mode") to track the inline em-dash purge in the
copy. tsc baseline: 10 errors, unchanged.

### Preferences — Edit > Preferences (locked 2026-05-23)

Net-new surface. User-global Preferences dialog reached from
`Edit > Preferences…` and `Ctrl+,`. Replaces the temporary LayersPanel
off-layer toggle (which was always meant as a temporary placeholder),
rehomes Theme as the canonical home (View > Theme stays as a quick-access
duplicate), surfaces 25+ knobs across 6 categories. Shape ran first
(documented brief in this session's earlier turns); discovery answers
locked Dialog two-pane topology + full catalog scope + strict user-global
persistence.

**Single commit:** `feat(72-prefs): Edit > Preferences (Ctrl+,) — two-pane Dialog + user-global prefs lib`

**Three confirmed locks** (via AskUserQuestion during shape):
1. Topology = Dialog with two-pane (categories left, content right) — over Dialog top-tabs / Sheet / Routed page
2. Scope = Full catalog (6 categories, ~25 settings) — over MVP / Mid cut
3. Persistence = Strict split (Preferences = user-global only; Project Options keeps `modelOptions`) — over merged / partial migration

**Architecture commitments** (full detail in `DESIGN.md` §5 Preferences):

- **`lib/preferences.ts` — single source of truth.** Type-safe `Preferences` interface, `DEFAULT_PREFERENCES` constant, `getPreference` / `setPreference` / `resetAllPreferences` functions, `usePreference` React hook backed by a `stream:prefs-changed` CustomEvent broadcast for cross-component sync. localStorage with namespaced one-key-per-setting keys (`stream-composer-pref.<category>.<setting>`).
- **Why per-key over one-blob:** future Tauri config write-side maps cleanly to TOML; corrupt single value doesn't poison the whole prefs; reads short-circuit defaults without parsing JSON.
- **Why not zustand for prefs:** prefs are user-global, not project-scoped. Living in `useStore` would pollute the undo stack (one Ctrl+Z would revert prefs) AND the `.scp` serialization would have to filter them out. Separate hook with localStorage backing is the cleaner boundary.
- **`initPreferencesBridge()`** — App.tsx-mounted listener that propagates pref changes for the three runtime-mirrored values (`hideOffLayer`, `snapToGrid`, `interactiveLocked`) into useStore. Other prefs are read by their consumers at call-time (`getPreference` from runner, autorecover gate, undo trim, addToRecent cap) — no bridging needed.
- **Canvas overlay buttons write through prefs.** SnapToGridButton + InteractiveLockButton now call `setPreference("editor", …)`; the bridge updates the runtime mirror. Reads still come from useStore. Click → pref → bridge → store → re-render.
- **Theme is canonical in useTheme.** Preferences > Appearance > Theme uses `useTheme()` directly, not an `appearance.theme` pref entry — two entry points (Preferences and View menu) share one localStorage key.

**Surface commitments:**

- Fixed `720 × 560` px Dialog. Desktop-only Tauri scope.
- 6 categories pinned in order: Editor / Appearance / Files / Validation / Code Export / Advanced.
- Left rail `w-[180px]` darker tonal step (`bg-panel`) so it recedes; selected row carries the 2 px `--ring` left-edge stripe (mirrors ValidationPanel selected-row idiom).
- Setting rows `grid grid-cols-[1fr_auto] gap-6 items-center py-3 border-b border-border/40`. Label-stack: `text-body font-medium` + `text-label text-foreground/65` description (one-line, engineering voice).
- Footer: ghost-button `Reset all preferences` (left, destructive on hover) + default `Done` (right). Reset replaces the footer inline with a confirm row — one less modal layer than an AlertDialog.

**The Pref-Persists-Even-When-Unwired Rule.** Settings whose downstream consumer doesn't read from the pref yet render with a **disabled** control + `Not yet wired.` mono micro line. The pref still persists in localStorage on change — future phases wire the consumer without touching the dialog. Currently disabled: Auto-flip ports, Show port type on hover, Default zoom, Density, Reduce-motion override, Default open / export paths, Indent width, Include source comments, Open exported file, Daemon status, Performance overlay (11 rows of 25).

**Wired settings (14 rows):** Off-layer behavior, Snap to grid, Interactive lock, Theme, Autorecover on/off, Autorecover interval (read once at init; change requires app restart), Recent files max, Undo history depth, all 10 Validation rule switches, Default group-by + Default severity filter (lazy initializer on ValidationPanel mount), Loop-trace persistence (the control is enabled but the canvas-side consumer for the timeout is not wired yet — categorically the control IS a valid pref to set even if a future phase wires the timeout).

**New Switch primitive.** `gui/src/components/ui/switch.tsx` added when Preferences became its first consumer. Sliding pill (Radix Switch). Documented radius exception: `rounded-full` vs the locked sm/md scale — the pill shape IS the affordance. `h-5 w-9` matches Badge density. Off `bg-border`, on `bg-primary`. Thumb `bg-background` reads against the track in both themes.

**Off-layer / snap-to-grid moved from per-project to user-global.** The `.scp` `layout.hide_off_layer` and `layout.snap_to_grid` fields are still serialized (back-compat for files written by older app versions) but **ignored on load** — the runtime mirror is seeded from prefs at store creation, and load paths drop the fields. Per `feedback_no_back_compat_during_heavy_dev`, no migration code.

**Files touched (production):**

- New: `gui/src/lib/preferences.ts` (types + storage + hook + bridge)
- New: `gui/src/components/PreferencesDialog.tsx` (Dialog + 6 category panes)
- New: `gui/src/components/ui/switch.tsx` (Radix Switch wrapper)
- Updated: `gui/src/App.tsx` (`Ctrl+,` keybind + bridge init + Dialog mount + custom-event wiring)
- Updated: `gui/src/components/EditMenu.tsx` (enables Preferences entry + MenubarShortcut + custom-event dispatch)
- Updated: `gui/src/lib/shortcuts.ts` (catalog entry for `Ctrl+,`)
- Updated: `gui/src/components/LayersPanel.tsx` (off-layer footer button removed)
- Updated: `gui/src/components/ValidationPanel.tsx` (group-by + severity filter lazy initializers from prefs)
- Updated: `gui/src/lib/validation/runner.ts` (filter validators by `rulesEnabled` pref at run-time)
- Updated: `gui/src/lib/projectIO.ts` (`addToRecent` cap reads from prefs)
- Updated: `gui/src/components/canvasMenus/SnapToGridButton.tsx`, `InteractiveLockButton.tsx` (write through `setPreference`)
- Updated: `gui/src/store/useStore.ts` (initial values from prefs; undo trim from prefs; autorecover gate + interval from prefs; ignore hideOffLayer/snapToGrid on load)

**Files touched (tests):**

- Removed: `LayersPanel.test.tsx` Dim/Hide footer toggle block (3 assertions across 2 tests) — surface no longer exists.
- Updated: `SnapToGridButton.test.tsx` — mounts the preferences bridge in `beforeEach` so the click → pref → bridge → store propagation completes in isolation.
- Updated: BC required hint copy (em-dash carry-over from the polish pass; this commit only re-runs the suite).

**Tests:** 1044/1058 (4 pre-existing fixture failures in `codeGenerator.smoke.test.ts`, unchanged baseline; 2 deleted tests for the removed footer surface — 1046 − 2 = 1044 net pre-baseline). tsc baseline: 10 errors, unchanged.

**Lessons captured below as #27 onward.**

### Preferences — wire-up sweep (locked 2026-05-23)

User feedback after the initial Preferences ship was "what is with
everything not being wired yet? can you not do it now or what?" — the
11 `Not yet wired.` placeholders read as deliberate gaps, not deferred
work. Wire-up pass closes 8 of the 11.

**Single commit:** `feat(72-prefs-wire): wire 8 deferred prefs (reduce-motion, autoflip, port-hover, default-zoom, default-open/export paths, indent width, open-after-export, loop-trace timeout)`

**Side-effects wired (8 controls):**

| Pref | Where it's read | Mechanism |
|---|---|---|
| `appearance.reduceMotion` | App.tsx + index.css + scrollIntoViewSafe | Writes `data-motion="full"\|"reduced"` on `<html>`. CSS targets the attribute; `html:not([data-motion="full"])` carves out the OS-pref reduce so "always on" overrides it. `scrollIntoViewSafe` inline-reads the attribute for JS-side smooth scroll. |
| `editor.autoFlipPortsOnConnect` | StreamNode FlowPortHandle + ThermalPortHandle | `usePreference` per handle; when OFF, the resolver is short-circuited and the port stays on its registry-declared side. Wasted resolver work is per-handle and bounded. |
| `editor.showPortTypeOnHover` | StreamNode FlowPortHandle + ThermalPortHandle | Native `title="FlowPort"\|"ThermalPort"` (not Radix Tooltip — 12-14 px hit targets, 400 ms Tooltip positioning math doesn't fit; native title preserves OS floating behavior + screen-reader announce). |
| `editor.defaultZoomOnOpen` | CanvasPanel | Memo at mount; "fit" → `fitView` prop, "100" → `defaultViewport={x:0,y:0,zoom:1}`, "last" → restored from `stream-composer-viewport` localStorage key (persisted on `onMoveEnd`). Falls back to fit if the key is missing/corrupt. |
| `files.defaultOpenLocation` | useStore.loadProject | Passed as `defaultPath` to Tauri `open()` when non-empty. |
| `codeExport.defaultPath` | exportCode | Seeds the save dialog's `defaultPath` (was hardcoded `"system.jl"`). |
| `codeExport.indentWidth` | exportCode | Post-processes the serialized output: each `"  "` (2-space) at line start → N×target unit. "tab" → `"\t"`. "4-spaces" → `"    "`. Avoids the full codeGenerator refactor (every `"  "` literal inside generation paths would need to thread). |
| `codeExport.openExportedFile` | exportCode | After `writeTextFile` succeeds, calls `@tauri-apps/plugin-opener.openPath()`. Non-fatal on failure. |
| `validation.loopTracePersistence` | CanvasPanel onFocusResult | When pref is "5s" or "10s", schedules a setTimeout after applying the trace. Closure-captures the current `activeTrace` reference so a replacement trace doesn't get cleared by the old timeout. |

**Still placeholder-disabled (3 controls, plus 1 explicit cosmetic):**

- `appearance.density` — needs an actual density-token system across the chrome (Compact vs Comfortable padding scales). Real feature, not just wiring.
- `advanced.showDaemonStatus` — needs a `bin/jl` liveness API in the status bar; daemon integration is a future phase.
- `advanced.performanceOverlay` — needs an FPS / paint-budget overlay component that doesn't exist.
- `codeExport.includeSourceComments` — the source-line comment emitter (`# from canvas: <node>`) doesn't exist in codeGenerator; the pref has nothing to gate.

These four stay disabled with the `Not yet wired.` mono micro line because there's no downstream feature to consume them yet. The pref persists either way, so adding the feature in a future phase doesn't touch PreferencesDialog.

**Files touched (production, 7):**

- `gui/src/index.css` — `data-motion` attribute selectors carving the OS-pref reduce-motion rule.
- `gui/src/lib/scrollIntoViewSafe.ts` — inline `data-motion` read for JS-side smooth scroll.
- `gui/src/App.tsx` — `data-motion` attribute writer + subscriber.
- `gui/src/store/useStore.ts` — `loadProject` consumes `files.defaultOpenLocation`.
- `gui/src/lib/exportCode.ts` — consumes `codeExport.defaultPath`/`indentWidth`/`openExportedFile`.
- `gui/src/components/CanvasPanel.tsx` — `editor.defaultZoomOnOpen` mount memo + viewport persistence + loop-trace timeout.
- `gui/src/components/StreamNode.tsx` — auto-flip gate + port-type-on-hover for both FlowPortHandle and ThermalPortHandle.
- `gui/src/components/PreferencesDialog.tsx` — dropped `notYetWired` + `disabled` on the 8 newly-wired controls.

**Tests:** 1044/1058 (4 pre-existing fixture failures, unchanged baseline). tsc: 10 errors (unchanged baseline).

### Lessons (worth re-reading at the start of the next session)

1. **The validation-flash bug took 3 sub-fixes** (offset → border-radius →
   retarget). Root cause: assuming the imperatively-added `.validation-flash`
   class lived on the rounded React-rendered element when it actually
   landed on xyflow's un-rounded wrapper. Lesson: when a class is added
   via `classList.add` from outside React, verify the DOM target element
   has the expected geometry/styling before tuning the CSS.
2. **`--card` initially tracked `--canvas`** which made node bodies invisible
   against the canvas. Lesson: when consolidating tokens, verify each one
   still has a *distinct* role; tracking values is fine for semantic
   alignment but only when the consumers need the same value.
3. **First-pass grid tones were too prominent** (Δ 0.08/0.04). User wanted
   "subtle structural texture, not decorative". Recommitted at Δ 0.05/0.02.
   Lesson: grids should be slightly less visible than feels right when
   coding (the contrast looks higher in real use because eye anchors on it).
4. **`--shadow-dialog` was self-referential in the first `@theme inline`
   pass.** Wrote `--shadow-dialog: var(--shadow-dialog)` — recursive
   reference. Tailwind v4 generates utilities from `@theme inline` shadow
   tokens with static values; for dark-mode-switching shadows the right
   pattern is to declare the token in `:root` and `.dark` and consume it
   via `shadow-[var(--shadow-dialog)]` arbitrary-value form at the
   primitive site. Lesson: when a token needs theme-switched values, don't
   try to expose it as a Tailwind utility — use arbitrary-value form.
5. **Removed `lg` button + `lg` icon-button sizes confidently** because
   grep showed zero consumers. The brief banned `h-9` / `h-10` from the
   primitive layer; the conservative move would have been to set `lg` to
   `h-9` as a compromise, but the brief was explicit. Lesson: greppable
   "no consumers" + explicit brief language is enough to drop API surface
   without a deprecation period (heavy-dev policy per `feedback_no_back_compat_during_heavy_dev`).
6. **The "blue ring on non-Sources nodes" bug took eight commits** because
   three independent contributors were stacked:
   (a) the `.stream-node--code-pinned` CSS rule (sky-300 placeholder) was
       being added only to Hydraulic / Thermal / ReactorPhysics nodes
       (Sources don't index to code-preview source lines), creating the
       Sources-vs-others visual asymmetry;
   (b) every "chroma 0 grey" attempted source value was either (i) a
       Tailwind arbitrary value like `ring-[oklch(0.65_0_0_/_0.3)]`
       whose `/` inside `oklch()` failed to parse in this Tailwind v4 +
       Vite configuration, silently falling back to `currentColor` =
       `--foreground` (hue 250 cool grey-blue), OR (ii) low-alpha grey
       that composited with the canvas background (`oklch(0.27 0.012 254)`)
       and inherited the canvas hue through the alpha;
   (c) the Vite + Tailwind v4 + `.vite/deps` dev pipeline was serving
       stale compiled CSS for `.stream-node--*` class rules even after a
       full cache nuke — verified via the magenta-probe diagnostic
       (body-level CSS edits did refresh; node class rules didn't).
   Lesson: when a "purely cosmetic" fix takes more than 2 passes,
   **inspect the compiled CSS in the running webview, not just the
   source file**. Cache + parse failures are invisible from the source
   side. Inline style on the React component is the unconditional
   workaround when class-side CSS won't refresh.
7. **OKLCH chroma-0 inputs are degenerate** — `oklch(L 0 0)` is "no hue
   at any chroma" which some browser parsers handle inconsistently. For
   intentionally pure-neutral colors in narrow geometry (rings, hairlines)
   where the doctrine "tint every neutral toward hue 254" produces an
   eye-amplified blue cast, prefer plain hex (`#6e6e6e`) over chroma-0
   OKLCH. The doctrine carve-out is documented in DESIGN.md §5.
8. **Auto-fix buttons in inspection panels violate the engineer's
   "tell-me-what-broke" expectation.** The original Phase 71 FixAction
   union (lossless-sync / value-transfer-picker / navigation-only) was
   removed wholesale in this session: type, render branch, emission. The
   panel is a recognize-and-locate surface, not a remediation surface.
9. **SCC-based cycle detection is the wrong tool for per-loop physics.**
   A graph with two cycles sharing one return edge has ONE SCC but TWO
   independent cycles. Use `findAllSimpleCycles` (Johnson-style DFS,
   rooted at lowest node id) when the rule needs to reason about each
   cycle independently — gravity sum is the canonical example.
10. **For per-cycle traversal physics, check entry-port AND exit-port at
    each node visit.** A cycle can enter and exit a node via the same
    port (parallel-paths topology); that's a "bounce" with zero
    contribution to ΣH, not a traversal contributing ±H. Symmetric
    in vs out is required for correctness.
11. **Hydraulic components are wide and short** (~280 × 80 px). Using the
    full bbox (including widths) for cluster-spread → axis-decision
    classifies clearly vertical layouts as horizontal because each row
    contributes node-width to X spread but only node-height to Y spread.
    Use NODE CENTERS, and apply a 1.5× vertical bias on top.
12. **xyflow's smoothstep / step / bezier edge routers have zero
    awareness of other nodes' bboxes.** A long edge happily cuts through
    every node body in its way. Custom edge components with explicit
    obstacle-avoidance routing are mandatory once the network has more
    than a handful of nodes.
13. **For obstacle-avoiding wrap paths, pivot points must be at
    cluster-edge lanes, not the source port's own Y/X.** If the source
    port sits inside the cluster (T-shape topology), using `sourceY` as
    the horizontal-pivot Y produces a segment that crosses other nodes.
    The pivot must extend along the source's outward direction past the
    cluster bbox first.
14. **Disconnected ports should be exempt from axis-snap.** When an
    isolated node has no edges, the D-11 contract says "use the
    registry-declared side." Auto-snapping disconnected ports to the
    flow-axis natural side broke that contract for any isolated node in
    a vertically-laid-out canvas.
15. **Tooltip discipline isn't "add Tooltip everywhere title= lives."** A
    400 ms tooltip showing information already visible at rest is friction
    (and PRODUCT.md flags it as the consumer-SaaS anti-pattern by name).
    The rule lands at: icon-only chrome OR shortcut-bearing-without-visible-
    binding. Everything else stays bare. Mechanical replacement of all 5
    existing `title=` attrs would have failed the audit; targeted
    application passes it.
16. **Real-component-in-the-Anatomy hits a hard wall on store coupling.**
    StreamNode reads from 5+ zustand selectors (errorNodeIds, anchors,
    hoveredSourceIds, pinnedSourceIds, activeLayers, hideOffLayer). Mounting
    a real StreamNode inside an Anatomy dialog would require either (a)
    seeding fake IDs into the production store (polluting state for an
    inert reference dialog) or (b) wrapping it in a mock-zustand Provider
    (zustand 4 doesn't support per-tree store overrides natively).
    The "visual mirror" middle ground — recreate the visual shell exactly
    using the same tokens / dimensions / DOM structure, but without the
    xyflow Handle plumbing — is the correct trade. Drift surface is the
    visual shell only; a marker comment on AnatomyDialog flags the dual-
    maintenance requirement.
17. **Adding `<Tooltip>` inside a component breaks isolated tests.** Radix
    Tooltip requires a `<TooltipProvider>` context, which production mounts
    once at the app root. Tests that render the leaf component in isolation
    have no provider and Radix throws a hard error
    (`Tooltip must be used within TooltipProvider`). Fix is to wrap the
    test render in `<TooltipProvider delayDuration={0}>`, not to pile
    multiple providers into production. Three test files touched in this
    session.
18. **A new "signal" doesn't automatically earn a new hue.** Initial shape
    proposal for the canvas↔code link state was a new `--color-code-link`
    magenta token (hue 340, chroma 0.20) — geometry-distinct from every
    existing hue. User pushed back: "is that color fitting the software?
    wouldn't it be too strong?" Reconsidering from first principles: the
    link state is FOCUS, the canvas already has 4 domain hues + 4 state
    hues, adding a 9th hue for "this is what you're looking at" would
    push the palette into the AI-workflow-tool territory PRODUCT.md
    anti-references. Neutral high-contrast (`--foreground`) is the
    semantic match AND the tool-grade move. Lesson: when a "third
    category" appears (focus, here), check if weight/contrast can carry
    the signal before reaching for a new hue slot — restraint compounds.
19. **Hover and pin earn different visual budgets.** First pass at the
    code-link active state gave hover and pin the same `--foreground`
    stroke at proportionally fatter widths (1.5 → 2 → 2.5). Live
    verification: hover was "way too loud" — moving the cursor across a
    code panel walks the hover signal across many edges + nodes in
    sequence, and a stream of full-contrast highlights makes the canvas
    pulse. Pin is fine being loud because the user committed to it.
    Final discipline: hover = color shift only (softened-foreground mix,
    no width change), pin = full foreground + modest +0.5 width fatten.
    Plus a second gotcha: xyflow's default arrowhead uses
    `markerUnits="strokeWidth"`, so arrows scale 1:1 with stroke. The
    "huge arrow on pin" complaint was the marker doing what it's
    supposed to do — fixed by tightening the stroke delta.
20. **"Don't paint node-side visual" doctrine was color-bound, not
    structural.** PROGRESS.md previously locked "any future code-link
    visual treatment belongs on edges, not nodes." Reasoning was: edges
    already convey the link, doubling on the node would be noise. That
    held under the sky-300 proposal (loud color, doubling = overpowering)
    but inverts under softened foreground (quiet color, doubling reads
    as harmonized). The doctrine call was implicitly a function of the
    proposed color value, not a structural principle. More importantly,
    component-definition lines (`@named pump = Pump(...)`) carry one
    node sourceId and zero edges — the edge-only doctrine left those
    lines producing no canvas feedback at all. Lesson: when re-reading
    a locked doctrine note in a new context, check whether the
    reasoning still holds with the current proposed values; "we
    previously decided X" is not load-bearing if the inputs changed.
21. **Motion-as-state beats contrast-as-state for high-fan-out
    highlights.** First-pass code-link active state was static
    `--foreground` stroke + width fatten. Second pass softened the
    color (color-mix toward canvas) + dropped the width fatten on
    hover. Both still made the canvas pulse when the cursor walked
    across many code lines — the eye anchors on the lit edges, no
    matter how clever the static color choice. Marching-ants on a
    near-rest stroke width fixes this categorically: motion conveys
    "linked" while the static visual weight stays near rest, so the
    eye registers the signal without being pulled to it. We already
    had this idiom in `.validation-flow-trace` for loop highlights;
    reusing the keyframe was the right call (consistency of motion
    grammar). Lesson: when a static-state design produces "too loud"
    feedback at scale, check whether motion can carry the signal at
    a lower static-weight floor. PRODUCT.md's "no decorative motion"
    bans choreography, NOT functional motion that conveys state.
22. **xyflow's default arrowhead scales with stroke
    (`markerUnits="strokeWidth"`).** No CSS or JS workaround can override
    that on a `MarkerType.ArrowClosed` — the markerUnits attribute is
    baked into xyflow's marker-generation code. The fix is to define a
    custom `<marker>` in a hidden SVG (inside the React tree so it lives
    in document scope) with `markerUnits="userSpaceOnUse"`, reference it
    via `markerEnd: "url(#id)"` from edge specs, and drop the
    MarkerType-based marker entirely. Took one tiny SVG component +
    a one-line useStore change. Lesson: when xyflow defaults don't fit,
    custom SVG defs are cleaner than fighting the framework — and the
    marker primitive is well-established SVG, no xyflow-specific API
    knowledge required.
23. **Sub-pixel box-shadow spreads render asymmetrically at some
    zooms.** First-pass code-pin ring used 2.5 px spread; user reported
    "bottom thicker than top." Sub-pixel rounding makes 2.5 → 2 on one
    side and 2.5 → 3 on the other depending on the box's subpixel offset
    (which varies with zoom level and DPI). Integer spreads (2, 3, 4)
    render symmetrically at every zoom. Lesson: in box-shadow / outline
    / border thicknesses, prefer integer pixel values unless there's a
    specific design reason for the half-pixel.
24. **CSS transitions on box-shadow read as click latency.** A 200 ms
    ease on a state change feels gentle when YOU initiate the state
    locally (selecting a node by clicking it), but feels laggy when the
    state is reactive to a remote input (clicking a code-panel sub-block
    → ring appears on the canvas node). The 200 ms ease was lifted from
    Linear/Cursor's selection-feel and was right for canvas-side
    selection; for cross-panel reactive state it needed to snap. Lesson:
    transition timing is a function of WHERE the state change is
    initiated, not just what changes. Snap for reactive, ease for
    self-initiated.
25. **SVG paint order is DOM order; `z-index` doesn't apply to SVG
    siblings.** Overlapping edges (e.g. parallel connections from a
    bottom port to two side-by-side targets) revealed that the marching-
    ants animation on an active edge could appear *behind* a static
    overlapping sibling — the dashes flickered as the sibling's solid
    stroke painted on top. CSS `z-index` and stacking contexts do not
    affect SVG sibling paint order; only DOM order does. xyflow's
    `Edge.zIndex` IS the supported mechanism — xyflow re-sorts edges
    by zIndex in the rendered DOM. Set 1500 for active edges (above
    xyflow's default selected zIndex of 1000). This required a
    selective subscription to `hoveredSourceIds` / `pinnedSourceIds` in
    CanvasPanel — the existing PERF comment warns against whole-store
    subscriptions, but scoped selectors are fine; hover/pin toggle
    frequency (mouseenter/leave on code lines, ~clicks/sec at most) is
    well below the node-drag tick rate (~60 Hz) the PERF doctrine was
    written to protect against. Lesson: when SVG layering matters, the
    fix lives in the framework's z-property (xyflow.Edge.zIndex) or in
    DOM reordering, NOT in CSS.
26. **An anti-pattern in one surface can be the convention in another.**
    Lucide `AlertCircle` / `AlertTriangle` / `Info` icons were banned
    earlier in Phase 72 from the ValidationPanel rows — they were a
    canonical shadcn-admin tell ("AlertCircle + chip + hover row"). The
    bottom-chrome status bar now uses the same icon family (`CircleX` /
    `TriangleAlert` / `Info`) for severity counts, and that's the right
    call: compact severity glyphs in a status-bar context are the
    IDE convention (VSCode / IntelliJ / Sublime / Eclipse). The icons
    don't carry the shadcn-admin meaning intrinsically — they carry it
    contextually, in combination with adjacent shadcn-admin patterns
    (chips, muted-foreground rows, hover-tinted list cells). Stripped
    of that surrounding context and used as a single-glyph + tabular-
    number cluster in a chrome bar, they read as the IDE family they
    actually come from. Lesson: anti-pattern rulings should be scoped
    to the surface where the pattern accumulates, not promoted to
    project-wide blanket bans. Document the carve-out where you take it
    so future sessions don't re-litigate the conflict.

## Re-entry instructions for the next session

Open a new Claude Code session, then say something like:

> Continue Phase 72. Read `PRODUCT.md`, `DESIGN.md`,
> `.planning/phases/72-gui-redesign/AUDIT.md`,
> `.planning/phases/72-gui-redesign/PROGRESS.md`, and the latest critique
> snapshot in `.impeccable/critique/`. Then start `/impeccable shape
> first-run` (or whatever surface is next per PROGRESS.md).

The new session will load doctrine + queue + locked values + recent
lessons in 1–2 minutes and resume cleanly.

**Next surface per queue:** phase-close — `/impeccable polish gui/src/`
landed. Run `/impeccable audit gui/src/` (target ≥17/20), then
`/impeccable critique gui/src/` (target ≥32/40), then
`/impeccable document` in scan mode (DESIGN.md seed → real spec), then
write Phase 72 SUMMARY.md per the ROADMAP row contract (supersedes this
file).

**Related memories** (loaded automatically — don't need to re-read):

- `project_impeccable_design_workflow` — workflow + how to integrate with GSD
- `feedback_gui_no_design_inertia` — nothing visible is sacred
- `feedback_opinionated_design_no_inertia_no_churn` — be opinionated; defend
  on merit, change on real gripe, never change for change's sake
