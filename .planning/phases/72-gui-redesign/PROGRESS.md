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

### Queued (next session — Session 3)

| Surface | Status | Audit / critique reference |
|---|---|---|
| First-run empty state (replaces WelcomeOverlay; engineering-voice) | ⬜ | Audit P0-1 · Critique P1-1 |
| Help system (Radix Tooltip primitive layer + `?` shortcut overview card) | ⬜ | Critique P0-2 |

### Queued (Session 4+)

| Surface | Status | Notes |
|---|---|---|
| BCEdge tokenization + CodePreview (tokenize remaining inline hex; finalize BC dashed-edge visual language) | ⬜ | HydraulicEdge already done (Phase B router); BCEdge sky-300/400 placeholders still pending. CodePreview `#0d1117` GitHub-dark hardcode also pending. |
| `/impeccable harden gui/src/` (cross-cutting: `prefers-reduced-motion`, div-as-button conversions, WCAG AA contrast pass) | ⬜ | Audit P0-3 · Critique Sam persona. Note: loop-highlight motion already has `prefers-reduced-motion` fallback. |
| `/impeccable clarify gui/src/` (copy pass: em dashes, consumer-SaaS framing in PresetsPanel, empty-state copy unification) | ⬜ | Audit P2-3 · Critique minor observations |

### Queued (Session 4 — phase close)

| Surface | Status | Notes |
|---|---|---|
| `/impeccable polish gui/src/` (final migration sweep — tokenize any remaining ad-hoc values) | ⬜ | |
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

## Re-entry instructions for the next session

Open a new Claude Code session, then say something like:

> Continue Phase 72. Read `PRODUCT.md`, `DESIGN.md`,
> `.planning/phases/72-gui-redesign/AUDIT.md`,
> `.planning/phases/72-gui-redesign/PROGRESS.md`, and the latest critique
> snapshot in `.impeccable/critique/`. Then start `/impeccable shape
> first-run` (or whatever surface is next per PROGRESS.md).

The new session will load doctrine + queue + locked values + recent
lessons in 1–2 minutes and resume cleanly.

**Next surface per queue:** `/impeccable shape first-run` — the empty-state
that replaces `WelcomeOverlay`. Audit P0-1 (textbook consumer-SaaS empty
state), Critique P1-1 (working-memory overload on first render). The
"to get started" copy is verbatim a PRODUCT.md anti-reference and the
recent-file rows are div-onClick a11y violations. Engineering-voice
empty canvas, no shadow-lg rounded card.

**Related memories** (loaded automatically — don't need to re-read):

- `project_impeccable_design_workflow` — workflow + how to integrate with GSD
- `feedback_gui_no_design_inertia` — nothing visible is sacred
- `feedback_opinionated_design_no_inertia_no_churn` — be opinionated; defend
  on merit, change on real gripe, never change for change's sake
