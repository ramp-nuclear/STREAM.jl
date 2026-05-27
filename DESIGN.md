---
name: STREAM Composer
description: Desktop visual editor that produces STREAM.jl Julia scripts for MTR plate-fuel safety analysis
---

<!-- PARTIAL SEED — Phase 72 in progress.

LOCKED (from /impeccable shape canvas, 2026-05-21):
  - §2 Colors except --destructive (still provisional)
  - §3 Type scale (1.25 Major Third) + scale tokens; font choice + typography direction still TBD
  - §4 Depth approach (3-tier tonal layering with structural shadows) + shadow vocabulary (single tier, --shadow-dialog)
  - §5 StreamNode visual treatment + canvas background (grid lines)

LOCKED (from /impeccable shape shadcn-primitive-layer, 2026-05-22):
  - §2 --ring relocked (hue-240 tint, low chroma)
  - §2 --border relocked (solid OKLCH, no alpha-on-white)
  - §2 new tokens: --border-hover, --popover (light mode), --shadow-dialog
  - §3 Type scale tokens exposed (--text-{micro,label,body,title,display})
  - §4 Shadow vocabulary: SINGLE TIER (--shadow-dialog applied to
        Dialog/AlertDialog/Sheet only; all other primitives are tonal+border)
  - §5 Radius scale committed (--radius-sm 4 px, --radius-md 8 px; no
        rounded-lg/xl in the primitive layer)
  - §5 All shadcn primitives recommitted: Button family, Input family,
        Surface family (Dialog/AlertDialog/Popover/Tooltip/Sonner + new
        Sheet), Menu family (DropdownMenu/ContextMenu/Menubar/Select/Command),
        Navigation (Tabs/ScrollArea/Separator)

LOCKED (from /impeccable shape help-system, 2026-05-22):
  - §5 Tooltip consumption discipline (icon-only OR shortcut-bearing-without-
        visible-binding); inventory of consumers; explicit exclusions
  - §5 cmdk shortcut mode + ? keybind (Linear convention), ModeChip swap,
        SHORTCUTS_CATALOG SSOT in gui/src/lib/shortcuts.ts
  - §5 AnatomyDialog — visual legend, dialog modal, real-component mirror
        strategy, Node + Edges tiles, numbered callouts, footnote
  - §5 HelpMenu rebuilt (Shortcuts / Anatomy / About)

STILL HELD OPEN:
  - §2 --destructive still provisional (semantic gravity earns it as the
       one chrome-permitted accent, but the exact OKLCH value is inherited)
  - §3 Font choice and typography direction — pending /impeccable shape
       first-run + help-system

Two-pass protocol per Impeccable's `document.md`:
  1. This file documents locked doctrine + locked-so-far values + held-open slots.
  2. As subsequent `/impeccable shape <surface>` decisions land, promote each
     [TBD] to a locked value here.
  3. At Phase 72 end, re-run `/impeccable document` in scan mode to capture
     the now-decided tokens into a real frontmatter + sidecar. -->

# Design System: STREAM Composer

## 1. Overview

**Creative North Star: "The Schematic Editor" (posture) + "The Composer's Workbench" (voice)**

Two paired metaphors, deliberately chosen because each one corrects a failure
mode of the other.

STREAM Composer reads as a *schematic editor* in **posture**: dim chrome, dense
layout, work-surface-as-product, no decoration, every visual choice in service
of the canvas. Every interface element earns its pixels or disappears.

It reads as a *composer's workbench* in **voice**: terse, craft-confident,
tool-grade. The language and personality of a workshop, not of a control system.
Sharp tools laid out for someone who knows what to do with them.

The first metaphor enforces visual restraint. The second prevents that
restraint from becoming sterile.

### Architectural commitments (locked, not relitigated per surface)

These are project-shape decisions, not visual ones.

- **Color space:** OKLCH only. No HSL or sRGB in tokens. Hex is acceptable for
  legacy inline values that bypass Tailwind JIT (documented exceptions), but
  the underlying choice is OKLCH and any new value must be OKLCH.
- **Primitive layer:** shadcn (new-york style, zinc base) + Radix UI primitives.
  Don't introduce a competing component library.
- **Styling layer:** Tailwind v4 with `@theme inline` token block.
- **Canvas library:** `@xyflow/react`.
- **Desktop shell:** Tauri (custom titlebar via Phase 67).
- **Accessibility floor:** WCAG 2.1 AA contrast across every surface, full
  keyboard navigation for all chrome (sidebars, dialogs, command palette,
  validator), `prefers-reduced-motion` respect (animations collapse to instant).
- **Domain structure:** the 4-layer taxonomy
  (Hydraulic / Thermal / Sources / ReactorPhysics) exists because there are
  four physics layers in the domain. Their *visual signal* is color
  (locked — see §2); the *structural fact* of four layers is permanent.

### Key Characteristics

- Canvas-as-product hierarchy (chrome recedes; canvas reaches out)
- Restraint over decoration
- Engineering voice — terse, declarative, no consumer hand-holding
- Speed-of-thought ergonomics — keyboard parity, command palette, dense layout
- Every choice committed — no fence-sitting defaults, no starter-template inheritance

### What this system explicitly rejects

Full anti-references catalogued in §6 (Do's and Don'ts). One-line summary:
generic shadcn admin dashboards, consumer-SaaS friendliness, legacy
Java-Swing-era scientific UI, observability/SRE dashboard cliché, and anything
that reads as "obviously LLM-generated."

## 2. Colors

### Locked rules

- **OKLCH only.** Reduce chroma as lightness approaches 0 or 100; high chroma
  at extremes looks garish.
- **No `#000` or `#fff`.** Tint every neutral toward hue 254 (the warm
  blue-grey base) at chroma 0.003–0.005 — near-imperceptible but technically
  tinted, satisfying the no-pure-neutral rule.

### Color strategy

**Locked.**

The **canvas surface** uses **Full palette** — 4 deliberate layer accents
(below) + 3 functional roles (destructive, ring, border) + the chart-data
palette for value visualization. The canvas is the only surface that earns
this much color; the work IS the color story.

**Chrome surfaces** (chrome/panel) use **Restrained** — tinted neutrals only,
no accent except where layer accents are referenced (e.g. the LayersPanel
dot indicators). This keeps the canvas-as-product hierarchy intact: chrome
recedes, color happens on the work surface.

### Neutrals (3-tier depth hierarchy, locked)

| Token | Dark | Light | Use |
|---|---|---|---|
| `--chrome`  | `oklch(0.16 0.012 254)`  | `oklch(0.95 0.005 254)` | Titlebar, status bar, edges of chrome surfaces |
| `--panel`   | `oklch(0.21 0.012 254)`  | `oklch(0.98 0.003 254)` | Sidebar, bottom panel, toolbox, layers panel — the supporting infrastructure |
| `--canvas`  | `oklch(0.27 0.012 254)`  | `oklch(0.99 0.003 254)` | The work surface where nodes live |
| `--card`    | `oklch(0.23 0.012 254)`  | `oklch(0.97 0.003 254)` | Node body fill — distinctly darker than canvas so nodes read as cells on the work surface |

Hue 254 (warm blue-grey) is the inherited neutral hue; specific lightness
values are Phase 72 recommitments.

**The Canvas-As-Lightest Rule.** Of all chrome surfaces, the canvas is the
lightest. Chrome darkest → panel mid → canvas lightest. Node bodies (`--card`)
sit slightly darker than canvas as a deliberate counter-step — they read as
"work cells on the surface", not "lifted cards above the surface".

### Layer accents (4 slots, locked)

| Layer | Dark | Light | Token |
|---|---|---|---|
| Hydraulic       | `oklch(0.62 0.16 240)` | `oklch(0.50 0.18 240)` | `--color-layer-hydraulic` |
| Thermal         | `oklch(0.74 0.15 75)`  | `oklch(0.60 0.16 75)`  | `--color-layer-thermal` |
| Sources         | `oklch(0.74 0.17 130)` | `oklch(0.60 0.18 130)` | `--color-layer-sources` |
| ReactorPhysics  | `oklch(0.62 0.22 15)`  | `oklch(0.48 0.22 15)`  | `--color-layer-reactor-physics` |

Hue rationale (domain intent + deuteranopia margin):
- Hydraulic blue — universal flow/water convention
- Thermal amber — universal heat convention, distinct from destructive red
  via hue (75° vs 27°)
- Sources yellow-green — input/source/indicator convention (LED green family),
  replaces arbitrary violet, survives deuteranopia better
- ReactorPhysics deep crimson — criticality convention, distinguished from
  `--destructive` via lightness step (~0.07 lower)

**Single source of truth:** `gui/src/lib/layerColors.ts` exports
`LAYER_COLOR_VAR: Record<LayerKey, string>` mapping each layer to its CSS var
expression. Every consumer (LayersPanel dots, StreamNode leading band) reads
from this map — there is no hardcoded layer hex anywhere in the codebase.

**The Layer-Accent-Is-Color Rule.** The 4-layer signal is hue, not texture or
icon. Alternatives were considered and rejected during shape: color is the
fastest categorical signal and what every reference tool (Houdini,
TouchDesigner, Rive, Linear) uses. Color-blindness margin is handled via
hue separation; redundant signals (text labels in LayersPanel, port shapes
for ports) cover the remaining edge cases.

### Functional roles

| Token | Dark | Light | Status |
|---|---|---|---|
| `--destructive`    | `oklch(0.704 0.191 22.216)` | `oklch(0.577 0.245 27.325)` | provisional (inherited, not yet redesigned) |
| `--ring`           | `oklch(0.65 0.10 240)`       | `oklch(0.55 0.14 240)`       | **locked** — Hydraulic-hue tint at low chroma; focus reads as "selected" with minor identity (Linear/Cursor lineage) |
| `--border`         | `oklch(0.30 0.012 254)`      | `oklch(0.88 0.005 254)`      | **locked** — solid OKLCH (was alpha-on-white; the alpha trickery violated OKLCH-only doctrine) |
| `--border-hover`   | `oklch(0.38 0.012 254)`      | `oklch(0.80 0.005 254)`      | **locked** — +Δ0.08 lightness step; Input + Select hover lift here |
| `--shadow-dialog`  | `0 16px 40px -12px oklch(0.05 0 0 / 0.55), 0 4px 12px -4px oklch(0.05 0 0 / 0.40)` | `0 16px 40px -12px oklch(0.05 0 0 / 0.18), 0 4px 12px -4px oklch(0.05 0 0 / 0.12)` | **locked** — atmospheric lift for modals (Dialog/AlertDialog/Sheet). Relocked post-Preferences when the scrim was banned; shadow now carries the lift work alone. |
| `--dialog-surface` | `oklch(0.13 0.012 254)`      | `oklch(0.93 0.012 254)`      | **locked** — modal body fill. Distinct tone OFF the chrome/panel/canvas trio so dialogs read as a tool overlay (CommandPalette lineage) rather than a lifted panel (popover lineage). |
| `--dialog-border`  | `oklch(0.24 0.012 254)`      | `oklch(0.86 0.012 254)`      | **locked** — pairs with `--dialog-surface`; one step lighter in dark / darker in light so the modal edge reads clean against its own body. |
| `--color-warning`  | `oklch(0.78 0.15 75)`        | `oklch(0.74 0.16 75)`        | **locked** |
| `--color-info`     | `oklch(0.72 0.16 240)`       | `oklch(0.62 0.18 240)`       | **locked** |

`--color-warning` and `--color-info` were introduced earlier to replace
raw `text-yellow-500` / `text-blue-500` in ValidationPanel. `--border-hover`
and `--shadow-dialog` were introduced in the primitive-layer shape pass.
`--dialog-surface` / `--dialog-border` and the relocked atmospheric
`--shadow-dialog` landed when the prior dim grey scrim + popover body
were banned project-wide (see Modal Lock below).

### Code editor lane carve-out (locked — BCEdge/CodePreview, 2026-05-23)

A documented exception to the project's perceptual palette: the CodePreview
syntax-highlighting palette is anchored to **One Dark Pro** (the most-installed
VSCode theme, and the Julia editor identity by lineage through Juno/Atom)
rather than derived from the canvas/chrome token system. Parallel to
WindowControls' macOS traffic-light hex exception: code editors are their own
established convention domain, and a bespoke "STREAM syntax palette" would
read as strange-without-purpose to engineers who live in VSCode/JetBrains
all day.

Five tokens, scoped to CodePreview's `TOKEN_CLASS` map only. Comments reuse
`--muted-foreground` (italic) — the muted family is already the right read
for "deprioritized prose inside code", no separate token earned.

| Token | Dark | Light | Julia tokens |
|---|---|---|---|
| `--syntax-keyword` | `oklch(0.74 0.16 295)` | `oklch(0.55 0.18 295)` | `function`, `end`, `return`, `if`, `using`, … |
| `--syntax-string`  | `oklch(0.78 0.14 145)` | `oklch(0.55 0.16 145)` | `"text"` |
| `--syntax-type`    | `oklch(0.78 0.11 230)` | `oklch(0.55 0.14 230)` | `Channel`, `Pump`, `HeatDiffusion` (Caps-named) |
| `--syntax-macro`   | `oklch(0.83 0.13 80)`  | `oklch(0.60 0.17 80)`  | `@named`, `@variables`, … |
| `--syntax-number`  | `oklch(0.78 0.13 50)`  | `oklch(0.58 0.17 50)`  | numeric literals |

**The Editor-Lane-Is-Convention Rule.** The `--syntax-*` tokens MUST NOT be
consumed by canvas, chrome, or any non-code surface. They exist to honor a
cross-tool convention; reusing them elsewhere would import that convention
into surfaces where it doesn't belong. New consumers of code-like rendering
(future error-tooltip with stack trace, future REPL panel) are valid; UI
chrome that happens to want a similar amber is not — use `--color-warning`.

### Code-link active state (locked — BCEdge/CodePreview, 2026-05-23)

The Phase 66 bidirectional link (hovering or pinning a sub-block in
CodePreview lights up the corresponding canvas nodes + connecting edges)
uses **`--foreground`** — the neutral high-contrast text color — for its
active stroke and ring, NOT a new hue token.

Reasoning: the link state is FOCUS (these things are the current attention
target), and `--foreground` is literally the token for "what's foregrounded."
A hue-distinct signal was rejected at shape: the canvas already carries 4
domain hues (layer accents) + 4 state hues (destructive, warning, info, ring);
adding a fifth "focus" hue would push the palette into the AI-workflow-tool
territory PRODUCT.md anti-references. Weight (strokeWidth, ring-2) plus
near-white-on-dark contrast carries the signal without earning a hue slot.

**Motion-led signal, not contrast-led** (iterated twice after live
verification):

The link state on edges is conveyed by a **marching-ants animation**, not
by stroke contrast or stroke thickness. Reuses the `flow-trace-march`
keyframe shared with the validation flow trace — same visual idiom, same
1.2 s linear infinite cycle (slightly faster than the validation trace's
1.5 s so the two read as distinct when both happen to be active).

The reasoning chain:
1. Static high-contrast strokes (`--foreground` solid) on many edges
   simultaneously overpower the canvas — the eye anchors on the lit edges
   instead of the components they connect.
2. Pure-color softening (mix toward canvas) helped contrast but didn't
   solve the "many edges = canvas pulse" problem when the cursor walks
   across the code panel.
3. A marching-ants pattern at near-rest stroke width is read as
   motion-conveys-state, not as "this edge is now LOUD." The eye registers
   "linked" without being pulled.

- **Hover** = `.code-link-active` class on the edge `<path>`: stroke
  `--foreground`, `stroke-dasharray: 6 4`, marching-ants animation. Stroke
  width unchanged from rest (1.5).
- **Pin** = `.code-link-active .code-link-pinned`: same animation, stroke
  width +0.25 px (1.75) — barely heavier than hover.
- `prefers-reduced-motion: reduce` stops the marching; the dashed pattern
  stays visible so the link can still be located.

Edge widths (BCEdge / HydraulicEdge):
- rest:    1.5 / smoothstep default, stroke = `--muted-foreground` (BC) or layer-tinted (Hydraulic), solid for Hydraulic / dashed-6/3 for BC
- hovered: 1.5 / 1.5, stroke = `--foreground`, marching dashed-6/4
- pinned:  1.75 / 1.75, stroke = `--foreground`, marching dashed-6/4

**Arrowhead is fixed-size.** A custom `<marker id="stream-hydraulic-arrow">`
is defined once in `CanvasPanel.tsx`, attached to hydraulic edges via
`markerEnd: "url(#stream-hydraulic-arrow)"` from `useStore.createEdges`.
The marker uses `markerUnits="userSpaceOnUse"` with fixed 12×12 user-unit
dimensions, so its size is fully decoupled from edge stroke width — the
arrow stays constant when the stroke fattens for pin (or hover, or future
states). Fill is `--muted-foreground` always; the arrow is **structural**
(reads as "flow direction"), not a state signal. Only the stroke conveys
state. xyflow's `MarkerType.ArrowClosed` (default `markerUnits="strokeWidth"`)
was the source of the "arrowhead gets huge on pin" bug observed in live
verification; the custom marker replaces it entirely.

**Active edges paint on top.** SVG paint order is purely DOM order — `z-index`
doesn't apply to SVG siblings. xyflow's `Edge.zIndex` is the supported
mechanism (xyflow translates it into DOM order at render). `enrichedEdges`
in `CanvasPanel.tsx` checks each edge: when BOTH endpoint UUIDs are in
`hoveredSourceIds` or `pinnedSourceIds` (matching BCEdge/HydraulicEdge's
per-component activation check), it bumps `zIndex` to 1500. xyflow's
default selected-edge zIndex is 1000, so 1500 puts code-active edges above
selected too — the link signal is the most important visual state to read
clearly. Without this bump, overlapping edges (e.g. parallel bottom-port
connections to two side-by-side targets) caused the marching dashes on the
active edge to appear behind the static line of its sibling.

Node ring (StreamNode, via inline `box-shadow` on the outer `<div>`; no
CSS transition, snaps on state flip):
- rest:         `0 0 0 1px var(--canvas), 0 0 0 2px var(--node-ring-rest)`
- code-hovered: `0 0 0 1px var(--canvas), 0 0 0 2px var(--foreground)`
- code-pinned:  `0 0 0 1px var(--canvas), 0 0 0 3px var(--foreground)`
- selected:     `0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)` — wins over both

**Priority: selected → code-pinned → code-hovered → rest.** Selected always
wins because it's the user's explicit canvas-side intent; code-link rings
are reactive to a remote (code-panel) input. Node-side rings are necessary
because component-definition lines (e.g. `@named pump = Pump(...)`) have a
single node sourceId and no edges in their sub-block — without the node
ring those lines produced no canvas feedback at all (a real bug observed
in live verification).

**The Node-Ring-Snaps Rule.** The transition on the box-shadow was removed
for code-link state changes (kept for `selected`, because the band thickens
in sync at 200 ms — gentle is right there). Code-link snaps because the
marching animation on the edges is the primary, ongoing signal; the
ring's job is to mark "which nodes" without contributing a second timing
budget. Live verification flagged the prior 200 ms ease as feeling
"laggy" on every code-panel click.

**Integer box-shadow spreads only.** The first pass used 2.5 px for the
pinned ring. Sub-pixel rounding in the browser made the bottom side render
fatter than the top on some zoom levels. Integer spreads (2 / 3) render
symmetrically across all zooms.

State marker is the `data-code-link` attribute on the node root
(`"hover"` / `"pinned"` / absent). Replaced the prior className-side
markers (`.stream-node--code-hover` / `.stream-node--code-pinned`) which
existed only because the CSS rules were no-ops anyway — a dead-state
marker pattern. Tests assert on `data-code-link`.

CodePreview sub-block (uses full `--foreground` because the small sub-block
ring against panel chrome doesn't suffer the multi-edge-pulse problem):
- rest:    no bg, no ring
- hover:   `bg-[color-mix(in_oklch,var(--foreground)_5%,transparent)]`, no ring
- pinned:  `bg-[color-mix(in_oklch,var(--foreground)_8%,transparent)]` + `ring-2 ring-[var(--foreground)]`
- flash:   `bg-[color-mix(in_oklch,var(--color-warning)_22%,transparent)]` + `ring-2 ring-[var(--color-warning)]`

The flash state uses `--color-warning` (already locked) — same semantic as
the canvas validation-flash navigation feedback. Distinct from the
steady-state pinned/hover so a one-shot navigation read doesn't get confused
with a sticky link.

### Popover surface (locked)

`--popover` is the 5th tonal slot in the hierarchy — one step lighter than
`--panel`, one step darker than `--canvas`. Used by Popover, DropdownMenu,
ContextMenu, Menubar, Select dropdown, Dialog body, Tooltip background
(via inverse), Sonner toast.

| Token | Dark | Light |
|---|---|---|
| `--popover` | `oklch(0.265 0.014 254)` | `oklch(0.985 0.003 254)` |

### Canvas grid (locked)

The canvas background uses two stacked `BackgroundVariant.Lines` layers from
xyflow, both 1 px solid, scaling with zoom:

| Tier | Gap @ 1.0 zoom | Dark | Light | Token |
|---|---|---|---|---|
| Minor | 12 px | `oklch(0.295 0.012 254)` | `oklch(0.97 0.003 254)` | `--color-canvas-grid-minor` |
| Major | 24 px | `oklch(0.32 0.012 254)`  | `oklch(0.94 0.003 254)` | `--color-canvas-grid-major` |

Tuned for "subtle structural texture, not decorative" — Δ from canvas is
0.02 (minor) / 0.05 (major), enough to give a sense of scale during pan
without competing with content.

**The Grid-Is-Texture Rule.** The grid is structural texture (sense of
scale, position reference during pan/drag), NOT visual decoration. If it
ever competes for attention with the nodes, tighten contrast further.

## 3. Typography

### Locked rules

- **Body line length capped at 65–75ch** in any reading-shaped surface
  (none currently exist; relevant if a long-form panel like a property
  description or help drawer appears).
- **Hierarchy uses scale + weight contrast**, ratio ≥1.25 between steps. Avoid
  flat scales (where every step is the same size with weight as the only
  differentiator).

### Type scale (locked — 1.25 Major Third)

| Token | Size | Use |
|---|---|---|
| micro   | 10 px | Layer headers, validator-id chips |
| label   | 11 px | Status bar chips, node value summary line |
| body    | 13 px | Inputs, menu items, node instance name |
| title   | 16 px | Panel headers, dialog titles |
| display | 20 px | Reserved for future major hierarchy moments (currently unused) |

Step ratio 1.25 (Major Third). Conventional for tools at this density;
matches Linear/Cursor/Rive lineage.

**Scale tokens (locked — primitive-layer shape, 2026-05-22).** Exposed via
`@theme inline` as `--text-{micro,label,body,title,display}`; Tailwind
generates `text-micro` / `text-label` / `text-body` / `text-title` /
`text-display` utilities. Primitive components consume the tokens (no more
`text-[Npx]` arbitrary values inside `gui/src/components/ui/`). Consumer
surfaces (panels, sidebars, dialogs body content) still carry the old
arbitrary values; consumer-side migration to the token scale is
`/impeccable polish` work at phase end.

### Separator idiom — middle-dot `·` (locked, 2026-05-28)

The canonical user-visible separator is **U+00B7 MIDDLE DOT** (`·`), surrounded
by one regular space on each side: ` · `. Use it to join short related
phrases in a single line — caption fragments, status-line segments, footer
state enumerations, tooltip "title · binding" pairs, inline filter chips
that read as `count · label`.

Current consumers (verified 2026-05-28):

- `AnatomyDialog` footer — outline state enumeration.
- `AnatomyDialog` body-rows caption.
- `ValidationStatusBar` close-button tooltip — `Close panel · Ctrl+\``.
- `ValidationPanel` header — `{N} issues · in <node> · clear`.

**Why `·` and not `/`.** The slash convention (Linear paths, `Workspace /
Project / Issue`) implies hierarchy. The middle-dot implies sibling
enumeration — multiple equally-weighted items joined into one line. The
Composer's separator usage is always the latter (state enumerations,
related-but-flat fragments), so `·` is the semantic match.

**Why not `•`, `,`, or `-`.** Bullet `•` (U+2022) reads heavier and
implies list. Comma reads as prose. Hyphen-minus `-` is ambiguous with
negatives and ranges. Em-dash `—` is on the locked Don't list. The
middle-dot is the unique semantic-neutral inline separator.

**Spacing.** Always ` · ` with a regular space on each side. No
non-breaking space, no narrow space — keeps copy editable without
character-pickers.

### Font choice (locked — 2026-05-28)

**Body / sans:** native system stack —
`-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif`.
Native rendering is high-quality across all three Tauri targets
(macOS / Windows / Linux) and the body face is not where the
engineering-voice lives. Deliberate non-commit.

**Mono: JetBrains Mono Variable (committed).** Bundled via
`@fontsource-variable/jetbrains-mono` (imported at `gui/src/main.tsx`),
exposed through the `--font-mono` token in `@theme inline`. Tailwind v4
generates `font-mono` from that token; all 40+ `font-mono` consumers
across the GUI (status-bar counts, validator IDs, keyboard hint chips,
node value summaries, CodePreview, AnatomyDialog labels) inherit it
automatically.

Why JetBrains Mono and not Berkeley / Commit / Geist Mono:

- **Free + OFL.** No license-management overhead; ships with the desktop
  bundle.
- **Tool lineage.** JetBrains IDEs, Linear's code blocks, Cursor — the
  font reads as engineering-voice rather than SaaS-decorative.
- **Numerics are honest.** Tabular figures, distinct `0` vs `O` and
  `1`/`l`/`I` — directly serves the status-bar count + validator-id use
  cases.
- **Variable font.** Single `woff2` covers all weights; no per-weight
  download.

Fallback chain (when the variable font fails to load):
`ui-monospace → SFMono-Regular → Menlo → Monaco → Consolas → Liberation Mono → Courier New → monospace`.

## 4. Elevation

### Locked rules

- **No glassmorphism.** Blurs and glass-cards used decoratively are
  prohibited. Rare and purposeful or nothing.
- **No decorative shadows.** Shadows are functional (focus indication,
  modal elevation, hover affordance) or absent. Ambient atmospheric shadow
  is prohibited.
- **Performance doctrine: zero-blur box-shadows on canvas-transformed
  children.** Blurred shadows on `@xyflow/react`-transformed nodes force
  full-layer repaint on every pan/zoom frame; measurably degrades canvas
  responsiveness. The pinned-node halo (`.stream-node--code-pinned`) is
  a worked example of this rule (crisp 1-px box-shadow halo, no blur).

### Depth approach (locked — 3-tier tonal layering)

Depth is conveyed primarily through the chrome → panel → canvas tonal
hierarchy (§2), with structural shadows only where elevation is functionally
meaningful (modals get `shadow-lg`, inputs get `shadow-xs`). The canvas
itself adds a faint grid as additional structural texture.

**The Tonal-Layering-First Rule.** Spatial separation comes from luminance
steps in the depth hierarchy first; shadows are reserved for state changes
(focus, modal lift) — never for ambient atmosphere.

### Shadow vocabulary (relocked — Preferences feedback, 2026-05-23)

**Single tier.** `--shadow-dialog` is the only structural shadow in the
system. Applied to Dialog, AlertDialog, and Sheet. **Atmospheric, not
hairline** — 16/40 px blur (was 8/24 px before the feedback). With the
modal scrim banned, the shadow carries the entire lift cue alone, so it
earns the heavier values.

**Zero shadow** on Popover, DropdownMenu, ContextMenu, Menubar, Tooltip,
Select dropdown, HoverCard, Sonner toast, Input, Textarea, Checkbox,
RadioGroup, Button, Toggle, ToggleGroup, Badge, Card, Tabs. These float on
the tonal step alone — `--popover` is one tone lighter than `--panel` and
darker than `--canvas`, which provides visible contrast on its own.

The inherited shadcn defaults (`shadow-xs`, `shadow-md`, `shadow-lg`,
`shadow-xl`) are no longer applied by any primitive.

### Modal lock (locked — Preferences feedback, 2026-05-23)

Triggered by `feedback_no_grey_modal_surface_or_scrim`. The prior locked
Dialog visual — `bg-popover` body + `bg-foreground/40` scrim — was
rejected outright as ugly. Both rules below are project-wide, not just
the Preferences surface.

**The No-Modal-Scrim Rule.** Modal dialogs MUST NOT dim the content
behind them. `DialogOverlay` and `AlertDialogOverlay` default to
`bg-transparent`; the canvas / chrome / panels stay fully visible while
the modal is open. The modal stands out via tone + shadow + border, not
by suppressing everything else. Consumers can opt INTO a scrim per-
instance via `overlayClassName` (no current consumer does, and adding
one needs a real reason).

**The Dialog-Body-Matches-Chrome Rule (locked — 2026-05-28).** Modal body
uses `bg-chrome` — the same tone as the top toolbar and bottom status
bar. The dialog reads as the app shell raised, not as a foreign panel
dropped in.

This supersedes the prior 2026-05-23 `--dialog-surface` doctrine (which
positioned the modal body on its own darker tone, Δ −0.03 below chrome
in dark mode). That tone was hard to read against in production and felt
visually disconnected from the rest of the app shell. After confirming
the chrome tone on AnatomyDialog + CommandPalette + AboutDialog (Phase
72 post-critique, 2026-05-28), the rule was unified across all dialogs.

The `--dialog-surface` / `--dialog-border` tokens are kept as
historical artifacts (still defined in `:root` + `.dark`) but no
primitive consumes them. Future surfaces can read them if a tonal
distinction needs to come back, but the default is chrome.

(Lifted panels are `bg-popover` territory — `Popover`, `DropdownMenu`,
`Menubar`, `Select` dropdown, etc., which keep using `--popover` unchanged.)

**The Shadow-Does-The-Lift Rule.** With the scrim gone, the
atmospheric `--shadow-dialog` (16/40 px) does the entire "this floats
above the canvas" job. The combination of (a) tone distinct from
chrome, (b) atmospheric shadow, (c) visible border at a hue-matched
tone is what reads as elevation. No scrim, no blur, no glassmorphism.

**Where it applies.** Dialog + AlertDialog primitives default to
`bg-chrome border-border` + atmospheric `--shadow-dialog`. The two
hand-rolled modal surfaces (UnsavedChangesDialog, AutoRecoverRestoreModal)
consume the same `bg-chrome` + `border-border` + `--shadow-dialog` inline.
CommandPalette and Preferences keep only their position + width +
zero-padding overrides specific to a top-anchored palette; the surface
tone is fully primitive-default.

**What's NOT affected.** `bg-popover` keeps its meaning everywhere it
already exists — Popover, DropdownMenu, ContextMenu, Menubar, Sonner
toast, Select dropdown, Tooltip background, plus the hover-tint /
selected-tint uses in ValidationPanel + ValidationStatusBar. Those are
lifted chrome surfaces, not modals.

## 5. Components

### Locked

- **shadcn (new-york style) + Radix UI** is the primitive layer. Don't
  introduce a competing primitive set; if a primitive is missing, add it
  from shadcn or build on Radix.
- **`Input` auto-select-on-focus is a chokepoint behavior, not styling.**
  The `requestAnimationFrame`-deferred `.select()` in
  `gui/src/components/ui/input.tsx` is load-bearing (see
  `feedback_input_select_on_focus`); restyling the component must preserve
  this chokepoint.
- **4-layer taxonomy** slots exist in `LayersPanel`, `StreamNode`,
  `ToolboxPanel`, layer-aware connect logic, layer dim/hide system. Visual
  treatment locked (color, per §2); structural existence permanent.

### StreamNode (locked — Phase 72 canvas shape)

| Property | Value |
|---|---|
| Outer wrapper | `relative rounded-md min-w-[140px]`, carries ring + outline classes, port handles attach here via xyflow; `data-stream-node-id={id}` for validation-flash targeting |
| Inner clipping wrapper | `rounded-md overflow-hidden` — clips band corners to match the rounded outline without clipping port handles |
| Leading band | 4 px tall (default) → 8 px tall (selected); full layer accent color; one segment per layer (split half/half for dual-layer nodes via `getDisplayLayers()`); `data-testid="stream-node-band"` |
| Body | `bg-card p-2`, contains icon + component label (11 px micro) + instance name (13 px body, font-semibold) + optional source-block value summary line (11 px label, muted) |
| Body radius | `rounded-md` (8 px via `--radius-md`) |
| Perimeter border | removed (band carries identity, no border needed) |
| Selected state | top band thickens 4 → 8 px + 2 px Hydraulic-blue ring (`var(--ring)`) with 1 px `var(--canvas)` offset; animates 200 ms via `transition-[box-shadow]` from the unselected mid-grey rest ring (`var(--node-ring-rest)`, hex `#6e6e6e` dark / `#c3c3c3` light) |
| Unselected rest ring | 1 px mid-grey ring (`var(--node-ring-rest)`) with 1 px `var(--canvas)` offset, always present on every node; same color for every component type so the canvas reads as a uniform field |
| Persistent error state | 2 px solid `var(--destructive)` outline |
| autoExtended state | 2 px dashed `var(--chart-5)` outline, `outline-offset: 2px` |
| Code-hovered / pinned (transient) | `.stream-node--code-hover` / `.stream-node--code-pinned` classes added to DOM as state markers (Phase 66 code-preview ↔ canvas linking); CSS rules are no-ops — visual treatment deferred to the queued `edges-and-code-preview` shape session |
| Render mechanism | Outline + box-shadow set via inline `style={}` on the outer wrapper (not via CSS classes) — bypasses a known partial-update issue in the Vite + Tailwind v4 + `.vite/deps` cache where `.stream-node--*` class rules served stale compiled output |
| Validation flash (navigation feedback) | `.validation-flash` class added by CanvasPanel.onNodeFlash; targets `data-stream-node-id` (NOT xyflow's `data-id` wrapper) so it lives on the same element as the persistent error outline; outline-offset 0, animates outline-color over 600 ms |
| Multi-layer split band | Components with both FlowPort AND ThermalPort (ChannelAndContacts today) render a 2-segment band: left half = first layer, right half = second layer. Detected via `getDisplayLayers()` in `gui/src/lib/layers.ts` |

### shadcn primitive layer (locked — primitive-layer shape, 2026-05-22)

Every primitive under `gui/src/components/ui/` has been recommitted. The
canonical decisions cascade to every consumer surface (no per-consumer
override is required to read on-brand; consumers that want to override
still can per-instance via `className`).

**Cross-cutting vocabulary**

| Axis | Commitment |
|---|---|
| Density | `h-8` (32 px) default for Button, Input, Toggle, Select trigger, Tabs trigger, Menubar root; `h-7` (28 px) `sm` variant for property-form density; `h-6` (24 px) `xs` for Badge / DropdownMenu items. No `h-9` / `h-10` in the primitive layer. |
| Radius | Two tiers: `rounded-sm` (4 px) for compact controls (Button, Input, Toggle, Checkbox, Badge, menu items, Tooltip pill); `rounded-md` (8 px) for surfaces (Popover, DropdownMenu, Select, Dialog, Sheet, Card, Tabs list container). No `rounded-lg` (12 px). |
| Motion | 100 ms fade-in / 80 ms fade-out on open/close; `transition-colors duration-[80ms]` on hover/active; `motion-reduce:!duration-0` collapses to instant under `prefers-reduced-motion: reduce`. No zoom-in/zoom-out. No slide-in-from-* (Sheet keeps slide-in-from-side as its identity). |
| Focus ring | `ring-2 ring-ring` at offset 0. Inset on Input/Textarea (so the ring lives inside the bounding box and doesn't overflow stacked rows). Outer on Button, Toggle, Checkbox, RadioGroup, Tabs trigger. Replaced the doubled shadcn `focus-visible:border-ring + ring-[3px] ring-ring/50` pattern. |
| Hover surface | `bg-card` (tonal step from current surface — chrome doesn't carry accent fill). |
| Aria-invalid | `ring-2 ring-destructive` (was `border-destructive` + `ring-destructive/20`). Consistent error vocabulary across all primitives. |
| Icons | Lucide stays the library. Sizes: `size-3.5` (14 px) in `h-8` controls, `size-3` (12 px) in chips/badges. Stroke `1.5` (was the Lucide default `2`; the new stroke matches the 13 px text weight). |
| Shortcut chips | `text-micro font-mono text-foreground/55` (was `text-xs tracking-widest text-muted-foreground` — `tracking-widest` is a SaaS-template letter-spacing pattern; mono font is the project's keyboard-hint idiom). |
| Primary posture | `Button variant="default"` = `bg-primary text-primary-foreground` neutral high-contrast slab. Already resolved that way in both themes (`--primary` is the light neutral text in dark mode and the canvas dark in light mode). Context-aware by surrounding scrim, not by separate variant. |
| Removed | `shadow-xs` on all form fields and small controls (doctrine §4); `transition-all` (sweeps layout properties); `dark:bg-input/30` and similar alpha-on-white hacks (token-side fix lets us delete the consumer-side workaround). |

**Token additions** (see §2 for token table values)

- `--border-hover` (Input + Select hover-lift target)
- `--popover` in light mode (was tracking `--background = #fff`)
- `--shadow-dialog` (the single structural shadow)
- `--text-micro`, `--text-label`, `--text-body`, `--text-title`, `--text-display`
  (full type-scale tokens; consumer-side migration deferred to polish pass)

**New primitive added**

- `Sheet` (built on Radix Dialog; edge-aligned panel with slide-in identity)
  — styled now even though no consumer exists, so the next surface that
  wants a side drawer doesn't reach for a Dialog instead.

**Per-primitive consumers to watch during the next session**

These primitives have visual deltas large enough that consuming surfaces
will read differently the first time they're seen:

- **Tooltip**: open delay 0 → 400 ms (deliberate-hover convention). Any
  consumer relying on "appears on glance" will feel slower; that's intended.
- **Badge**: `destructive` and `link` variants dropped. Any consumer using
  them must switch to a different variant + className with `text-destructive`.
- **Button**: `lg` and `icon-lg` sizes dropped (no consumers existed at
  shape time; subsequent additions must use `default` or `sm`).
- **Sonner**: every toast now consumes the project visual vocab via
  `toastOptions.classNames`. Custom-styled toasts in consumer code may
  need to be re-verified.

### ValidationPanel + ValidationStatusBar (locked — Phase 72, 2026-05-22)

The validator UX uses a **compiler-output silhouette**: every result row
reads like a `tsc TS2304:` or `eslint no-unused-vars:` line, not like a
SaaS alert card.

**Row layout (three columns, fixed pixel widths):**

| Column | Width | Style |
|---|---|---|
| Severity label  | 80 px (resizable, min 60 / max 120)  | Mono 13 px, color-tokenized via `--destructive` / `--color-warning` / `--color-info`. Labels: `error`, `warning`, `info` (lowercase full words, NOT the 3-letter prefix). **No Lucide AlertCircle/Triangle/Info icons.** |
| Validator id    | 140 px (resizable, min 80 / max 480)  | Mono 13 px, `foreground/85`, `truncate` with native `title` tooltip. **Leads the row** — Linear-issue-id pattern; the engineer reads the rule identity first. Default dropped 200 → 140 (Phase 72 critique) so MESSAGE gets the room it earns at default panel width; engineers with long rule ids drag the divider wider. |
| Message         | fluid remainder                       | Sans 13 px, `foreground`, `truncate` with native `title`. |

Pinned in absolute pixel widths (not `ch` units): the column-header row uses
mono 10 px and data rows use mono+sans 11–13 px, so `ch` would resolve
differently in each grid container and the header would drift left of the
data. Px keeps them locked.

**Row vocabulary that's banned:**

- No Lucide alert icons in any cell. Severity is conveyed by the mono
  lowercase-word label + color token alone.
- No FixAction buttons. The `FixAction` discriminated union and the
  `fixAction?` field on `ValidationResult` were deleted at the type level
  Phase 72. Validation is a recognize-and-locate surface, not a remediation
  surface (`feedback_no_validator_fixaction_buttons`).
- No `text-yellow-500` / `text-blue-500` raw Tailwind for severity colors.
  Severity flows through `--destructive` / `--color-warning` / `--color-info`
  tokens only.

**Panel header — progressive disclosure (Phase 72 critique P1-1):**

The header collapses at small result counts. The threshold is **count ≥ 4**
(`FULL_HEADER_THRESHOLD` in `ValidationPanel.tsx`): three results still scan
as a list, four becomes a table where headers + filters earn their visual
weight. With 1–3 rows, the management-widget header outweighs the content
and visually contradicts the locked compiler-output silhouette.

At **count ≥ 4** the header is two sub-rows:

1. Controls row — left side: `{N} issues` count in mono 11 px. Right side
   in this order: severity filter pills (`error 12   warning 4   info 2`,
   full lowercase words at mono 13 px / px-2.5 py-1.5; replaces the prior
   3-letter `ERR/WRN/INF` 11 px treatment) + sliders icon (16 px, padded
   px-2 py-1.5 to match pill silhouette) that opens a Group-by popover.
2. Column labels row — `SEV / RULE / MESSAGE` in mono 10 px uppercase
   `foreground/45`. Hairline `--border` underneath.

At **count 1–3** the header collapses to a single Controls row: `{N} issues`
+ group-by icon. The column-labels row is hidden (row contract is inferable
from the data at that scale). The severity filter pills are hidden too —
**unless** a severity filter is currently active, in which case the pills
remain so the user always has a way to toggle/clear it. Filter entry at
small N happens via the status-bar severity segments (the canonical entry
point); the panel header doesn't need to re-host that affordance.

The header has TWO draggable column-resize handles (between SEV/RULE and
RULE/MESSAGE), 6 px wide hit-zones with a **1 px `--border` hairline at
rest** (discoverability — Alex flag from the critique; the handles were
previously unmarked at rest) that lifts to **1 px `--ring`** on hover and
during drag. `col-resize` cursor. Drag updates BOTH the column-header row
and every data row via a shared `gridTemplate` state. The handles only
render when the column-labels row is visible (count ≥ 4); at small N the
column widths are at their defaults and resizing is not exposed.

**Filter pills** replace the prior `12 issues · ERR only · clear` inline
header. Click a pill to toggle its severity filter. Pills are
color-tokenized text without chip backgrounds (flat type with hover
background lift to `--popover`). Aria-label format: `Filter to ${severity}`
(or with ` (active)` suffix when active).

**Group-by popover** (sliders icon): single-select Toggle Group with
`None` / `Rule` / `Component`. Per-session local state, no persistence.
When grouped, identical-key rows collapse into expandable parent rows
reading `▸ N × rule` or `▸ N × node`. Parent's severity-glyph color
mirrors the highest-severity child.

**Selected-row indicator:** the most-recently-clicked row gets a 2 px
`--ring` left-edge stripe + a `bg-popover` row tint. Clears on filter
change or canvas click. Connects visually to the active loop-trace on
the canvas (the trace persists alongside the selected row).

**Empty state:** the literal string `No issues.` in mono 13 px,
`foreground/65`, left-aligned in the panel body. NOT centered with an
icon and consumer-SaaS framing.

### Unified bottom-chrome footer (locked — Phase 72, 2026-05-22)

A single 22 px strip pinned to the absolute bottom of the window is the
source of truth for `activeBottomTab`. Replaces the prior 14 px BottomPanel
stub strip + 22 px ValidationStatusBar pair (was 36 px of stacked chrome
with no content when the panel was closed).

**Layout:**

```
┌──────────────────────────────────────────────────────────────────┐
│  ⊗ 12   △ 4   ⓘ 2                Code  Validation        ⌄       │   ← 32 px footer (always)
├──────────────────────────────────────────────────────────────────┤
│  [ BottomPanel body when open ]                                  │
└──────────────────────────────────────────────────────────────────┘
```

- Bar height — **32 px** (bumped from 28 to accommodate the larger
  icon + count sizes below). Still in IDE-status-bar territory (VSCode
  22, JetBrains 27, Sublime 28-30, Eclipse 32). No external consumers
  of the prior 28 px value.
- Left cluster — severity count segments. **Icon + mono count**, NOT mono
  text labels: `CircleX 12   TriangleAlert 4   Info 2` (Lucide
  `CircleX` / `TriangleAlert` / `Info` at **18 px** / `stroke-1.75`,
  colored via `--destructive` / `--color-warning` / `--color-info`).
  Count text is `text-[15px] leading-[18px] tabular-nums font-mono`. The
  explicit `leading-[18px]` matches the icon's 18 px box exactly, so
  icon + number share a precisely-aligned line-box (top + bottom Y edges
  identical). Click any segment → opens panel on Validation tab with
  that severity filter pre-applied via `stream:validation-filter`. Zero
  counts dim to ~55% opacity (icon stays visible so "validation is
  running, no issues" still reads). 0 → N pulse on the error segment
  preserved.

  **The Status-Bar-Icons-Are-The-IDE-Convention exception.** Lucide alert
  icons are explicitly **banned** in the ValidationPanel result rows
  (those rows use the mono lowercase-word severity label — `error` /
  `warning` / `info` — see the row vocabulary block above). The status
  bar takes the opposite call: icons instead of words, because (a) the
  bar is a strip with no room for full words across three severity
  segments, (b) the IDE lineage (VSCode / IntelliJ / Sublime / Eclipse
  status bars all use exactly these glyphs at exactly this size) makes
  the icons read as tool-grade rather than SaaS-admin. The shadcn-admin
  liability of the icons exists in the panel-row context (icon + chip +
  hover-tinted row = the canonical "generic admin dashboard" pattern
  PRODUCT.md anti-references) and **not** in the compact status-bar
  context. Different surface, different convention, different read.
- Right cluster — `Code` / `Validation` tab buttons. Click an inactive tab
  while panel closed → opens on that tab. Click an inactive tab while
  open → switches without closing. Click the **active** tab while open →
  closes the panel. Active-tab indicator: 1 px `--ring` hairline at the
  tab's top edge. Plus an explicit `⌄` close chevron at the far right,
  visible only when the panel is open.
- The duplicate `Code | Validation` Tabs that used to live in BottomPanel's
  header are gone. BottomPanel header keeps Copy / Export buttons only.

**The Bottom-Chrome-Is-The-Tab-Source Rule.** Anything that needs to set
the active bottom tab dispatches through `setActiveBottomTab` — including
the right-click "Show generated Julia code" path, which had been opening
the panel without setting `activeBottomTab: "code"` (so users on the
Validation tab silently stayed there). Fixed by `useShowCodeFor.ts`.

### Loop-highlight system (locked — Phase 72, 2026-05-22)

Loop-scoped validation results (gravity sum, future loop-scoped rules)
highlight the entire offending cycle on the canvas via a **marching-ants
flow trace**.

**The Trace-Conveys-Loop-Direction Rule.** Animated dashes on edges move
in the cycle's flow direction (matching the original source→target
direction xyflow paths use). This is functional motion: it identifies
the loop AS a cycle and conveys flow direction simultaneously.
Per PRODUCT.md "no decorative motion" but motion-that-conveys-state is
in-bounds.

**CSS** (in `index.css`):

- `.validation-flash-persistent` — node-level. Steady-state pulse animation
  (1.5 s ease-in-out infinite), outline 2 px solid using
  `--validation-trace-color` (inline-set per severity).
- `.validation-flow-trace` — edge-level. Targets the inner `.react-flow__edge-path`.
  Sets `stroke: var(--validation-trace-color)`, `stroke-width: 2.5`,
  `stroke-dasharray: 6 4`, `animation: flow-trace-march 1.5s linear infinite`
  where the keyframe moves `stroke-dashoffset` from 0 to −10 (negative shifts
  dashes toward the path's target end).
- `prefers-reduced-motion: reduce` → animations stop. Dashed pattern stays
  visible so the user can still see which edges are in the loop.

**Severity → color mapping:**

| Severity | `--validation-trace-color` |
|---|---|
| error    | `var(--destructive)` |
| warning  | `var(--color-warning)` |
| info     | `var(--color-info)` |

**CanvasPanel handler:** when `stream:focus-validation-result` arrives with
≥2 node targets, treat as a loop trace — `fitBounds` to enclose, apply
`.validation-flash-persistent` to every node target + `.validation-flow-trace`
to every edge target. The trace **persists** until any `mousedown` inside
the ReactFlow viewport or a new focus event replaces it. Single-node-target
results keep the existing 600 ms one-shot `.validation-flash` navigation
behavior.

### No-project home surface (locked — Phase 72, 2026-05-27)

**Supersedes the 2026-05-22 "chromeless typographic anchor" doctrine**
and the prior letterhead-card `WelcomeOverlay`. Both treatments were
rejected during the 2026-05-27 critique session: the anchor read as "an
ugly thing barely visible on the canvas background," and the letterhead
read as a marketing splash (PRODUCT.md anti-reference). This subsection
is the new locked spec; the component is `NoProjectHome.tsx`.

**Topology — the canvas region renders the home surface when no project
is open.** Not an overlay floating on the canvas; the canvas region IS
the home. Renders when
`nodes.length === 0 && edges.length === 0 && !welcomeDismissed`. The
ReactFlow canvas stays mounted underneath (preserves xyflow internal
state for fast project-open); `NoProjectHome` is a full-bleed
`absolute inset-0 bg-canvas` opaque surface covering it. Result reads
as "no canvas because no project," not as "splash on top of canvas."

**Chrome behavior when no project is open:**

| Chrome | Behavior |
|---|---|
| Titlebar (CustomTitlebar) | Unchanged — always-on brand zone (brand mark + window title). |
| Menubar / File | New / Open / Open Recent: ENABLED (primary "create / open project" affordances). Save / Save As / Load preset / Save selection as preset / Export to Julia: **DISABLED** (act on a project that doesn't exist). |
| Menubar / Edit | Undo / Redo / Cut / Copy / Paste / Duplicate: **DISABLED** (canvas mutations). Preferences: ENABLED (global). |
| Menubar / View | Jump to (palette) / Toggle Code Preview / Theme: ENABLED. Bottom-panel content has its own empty states (CodePreview "No code yet.", ValidationPanel "No issues."). |
| Menubar / Help | All entries ENABLED (Shortcuts / Anatomy / About are global discovery surfaces). |
| Toolbox | ENABLED. Dragging a component onto the home surface fires the dashed drop-affordance border; on drop a fresh project is created and the component auto-places near canvas origin. The toolbox drag IS a `+ New` affordance. |
| LayersPanel | Layer-toggle buttons **DISABLED** (`disabled:opacity-50 disabled:cursor-not-allowed`). Section header + dots stay visible so the chrome structure reads continuously; the rows just don't respond. |
| Right sidebar (Properties) | "No selection" empty state. Unchanged. |
| Status bar | Theme + Snap + Lock + severity-counts (at zero) — fully functional, no behavior change. |
| Canvas overlay buttons (Zoom in/out, FitView, Lock, Snap) | **Hidden** when home is showing. They operate on canvas state and at `top-2 right-2` would collide with the dashed drop-affordance border. `CanvasPanel.tsx` gates this cluster on `!noProjectVisible`. |
| BottomPanel Copy / Export | Already disabled via `!hasNodes` check — no change needed. |

**The Gate Doctrine.** Every consumer that needs to know about no-project state subscribes to the same boolean primitive via `useStore`:

```ts
const noProjectVisible = useStore(
  (s) => s.nodes.length === 0 && s.edges.length === 0 && !s.welcomeDismissed,
);
```

Selector returns a boolean, so zustand value-equality means the consumer only re-renders on transition. The condition matches `NoProjectHome`'s own visibility gate verbatim — wherever the home shows, the gate is true; wherever it doesn't, the gate is false. Used today by FileMenu, EditMenu, LayersPanel, CanvasPanel (overlay buttons).

The chrome-continuity rule: opening a project swaps the home surface
for the canvas in-place; toolbox / layers / sidebar / status do not
reflow. This keeps the transition zero-cost and lets the toolbox drag
double as the project-creation entry point.

**Visual treatment — VSCode "Welcome" tab lineage:**

```
┌─ canvas region ────────────────────────────────────────────┐
│                                                            │
│                                                            │ ← top 15 % breathing room (pt-[15vh])
│                                                            │
│        ┌─── 720 px max ──────────────────────────┐         │
│        │  recent          │   start              │         │ ← SectionHeader (mb-4)
│        │                  │                      │         │
│        │  loop_v2         │   +  New project     │         │ ← Action rows (text-body mono, h ~28 px)
│        │  hex_cube_xxx    │   ⌗  Open project…   │         │
│        │  mtr_3plate      │                      │         │
│        │  plate_lof_demo  │   ──────────────     │         │ ← 1 px hairline (--border)
│        │                  │   templates          │         │ ← SectionHeader (only when templates exist)
│        │                  │   simple_loop        │         │
│        │                  │   two_channel_plate  │         │
│        └──────────────────┴──────────────────────┘         │
│                                                            │
│                                  [STREAM-wordmark] v0.1.0  │ ← bottom-right stamp
└────────────────────────────────────────────────────────────┘
```

- **Background:** `bg-canvas` (no card, no border, no shadow, no
  rounded panel wrapping the surface). The home IS the canvas region.
- **Two columns** separated by a 1 px vertical hairline `bg-border`,
  centered horizontally. Container max-width scales with viewport:
  `720 px` default → `920 px` at `xl:` (1280 px+) → `1120 px` at `2xl:`
  (1536 px+). At fullscreen the cluster grows to fill more horizontal
  real estate so the surface doesn't read as half-empty. Top padding
  similarly shrinks from `pt-[15vh]` default to `2xl:pt-[10vh]` so
  content lifts toward the top when the viewport is tall. The earlier
  watermark-icon-as-ambient-texture attempt was rejected by visual
  verification (read as decorative-marketing); growing the content
  cluster itself is the right answer.
- **Row vocabulary** shared across recents + actions + templates: full-
  width `<button>`, `text-body font-mono text-foreground`, `rounded-sm
  px-2 py-1.5`, `hover:bg-card`, `transition-colors duration-[80ms]
  motion-reduce:!duration-0`, `focus-visible:ring-2 ring-ring`. Action
  rows carry a small Lucide icon (Plus, FolderOpen) at `h-3.5 w-3.5
  stroke-1.5` in `text-foreground/55`.
- **Recents** show the basename stem (extension stripped) with full
  path via native `title=`. Max 10 entries (was 5; bumped so wider /
  taller viewports get a denser column for free). Empty state: a
  single mono line `no recent projects yet` in
  `text-foreground/45 text-label`.
- **Templates** section renders only when ≥1 template exists. No empty
  state — the section earns its pixels only with content.
- **No canvas grid.** Grid only renders when a project IS open; the
  home surface keeps a clean `bg-canvas` tone with no structural
  texture (no spatial reference earned without nodes).

**Identity stamp — bottom-right corner:**

The wordmark SVG at `gui/public/stream-wordmark.svg` (icon + STREAM.JL
text, brand blue `#003569`) at `h-9` (36 px tall, ~230 px wide), full
opacity, scaling to `h-11` at `2xl:` viewports. Next to it: the
Tauri-reported version in `text-label font-mono text-foreground/65`.
The stamp is the entire brand presence on this surface; titlebar still
carries the always-on brand mark.

**Important asset note:** the deployed `gui/public/stream-wordmark.svg`
has a **CROPPED viewBox** (`57 465 966 150`) tight on the actual icon+
text content. The original source asset at `gui/icons/SVG/horizontal_
blue.svg` carries `viewBox="0 0 1080 1080"` (square) with the content
occupying only the y=465–615 band — that's 14 % of the vertical
viewBox. At `h-N` the original asset rendered as a thin smudge because
the wordmark content shrank with the empty viewBox. The cropped copy
in `public/` produces a true-sized wordmark; `h-7` first iteration
(28 px) and even `h-9` (36 px) on the un-cropped asset were both
illegible. The source SVG is preserved as the original (re-derived
from it via viewBox override + path inline + `<g fill="...">`).

**Drop-affordance — static dashed border:**

When a Toolbox-component drag enters the home surface (HTML5 `dragenter`
with `application/streamcomponent` dataTransfer type), a CSS `<div>`
inset 16 px from the canvas edge fades in with `border: 2px dashed
var(--ring); border-radius: var(--radius-md)`. Tailwind's
`box-sizing: border-box` keeps the stroke strictly inside the
inset-4 bounds. The first iteration used an SVG rect with
`stroke-dashoffset` marching-ants animation reusing the
`flow-trace-march` keyframe; that approach over-painted past the
SVG viewport on WebKitGTK (percentage-coord rect on a sized SVG).
The static-border approach is simpler, respects bounds, and matches
the user's "drop file here" reference cleanly. On drop,
`newProject()` is called and the dragged component is `addNode()`ed
at flow-space `(160, 120)` — the project boots with a starter
component in place.

**The Drop-Is-The-Affordance Rule.** No "Drop file here" caption, no
overlay text. The dashed receptive border IS the affordance. Power
users learn it once; the canvas-region-as-receptive-zone metaphor
matches every other drop target in the app (xyflow's canvas pane
accepts the same toolbox drag with identical visual feedback once a
project is open).

**Copy doctrine:**
- Section labels lowercase: `recent`, `start`, `templates`. Never
  "Recent Projects" / "Start" / "Templates".
- Action labels title-case verb-led: `New project`, `Open project…`.
  Ellipsis on `Open` because it opens a native dialog (Apple HIG
  convention; the user is not committing to an open yet).
- Empty-state mono line for recents only: `no recent projects yet`.
  No empty state for templates section (it just doesn't render).
- No "Welcome to STREAM Composer", no "Get started", no walkthrough
  links, no tutorials.

**A11y:** every interactive row is a real `<button>` (no `div role=button`
shims). Keyboard tab order: recent rows → action rows → template rows.
Focus-visible ring tokenized. The corner stamp is decorative
(`select-none pointer-events-none`); the wordmark `<img>` carries
`alt="STREAM Composer"` so screen readers announce the app identity
once when entering the surface, not as repeating decoration.

**Performance:** gated on the same `isEmpty && !welcomeDismissed`
boolean derived from primitive selectors — does not repaint during
ReactFlow drags once a project is open (the wrapper unmounts entirely
once `welcomeDismissed === true`).

### Help system (locked — Phase 72, 2026-05-22)

Three coordinated artifacts that close the Critique P0-2 "no in-app help"
gap without drifting into consumer-SaaS documentation.

**1. Tooltip consumption discipline.**

The Phase-72-locked Radix Tooltip primitive (400 ms delay, no shadow, plain
fade open/close) is consumed under one rule:

> Tooltip exists for two reasons only:
> (a) icon-only chrome controls where the label is implicit, and
> (b) any clickable surface that has a keyboard shortcut whose binding
>     isn't already visibly displayed.
> Everything else stays bare.

Locked inventory at this commit:

| Surface | Tooltip content | Reason |
|---|---|---|
| `WindowControls` Min / Max / Close (Windows/Linux variant) | `Minimize` / `Maximize` (or `Restore`) / `Close` | Icon-only |
| `ValidationPanel` Group-by sliders icon | `Group by` | Icon-only |
| `ValidationStatusBar` close chevron (⌄) | `Close panel · Ctrl+\`` | Icon-only + shortcut |

Explicitly **excluded**: menubar items (shortcut chip already right-aligned
in the row — tooltip would repeat); `LayersPanel` rows (text-labeled, no
shortcut); `ValidationStatusBar` Code / Validation tab buttons (text-labeled,
share `Ctrl+\`` only for panel toggle, not per-tab); `App.tsx` collapsed-edge
re-expand strips (4 px wide, no shortcut — native `title=` is fine).

**The Tooltip-Earns-Its-Pixels Rule.** A 400 ms tooltip showing information
already visible at rest is friction. Adding tooltips broadly drifts toward
the consumer-SaaS "explain every button" anti-pattern. The discipline above
keeps the tooltip surface narrow and purposeful.

**2. Shortcut overview (cmdk shortcut mode).**

The existing `CommandPalette` gains an internal
`mode: "commands" | "shortcuts"` state. `Ctrl+P` opens with
`mode: "commands"` (current behavior); `?` (Shift+/) opens with
`mode: "shortcuts"`. The mode chip in the palette header swaps modes
in-place (no close + reopen); swapping clears the search query.

| Mode | Input placeholder | Empty state | Listing |
|---|---|---|---|
| `commands` | `Type to search components and resources...` | `No matches.` | Existing component / resource / project rows |
| `shortcuts` | `Type to search shortcuts...` | `No bindings.` | `SHORTCUTS_CATALOG` from `gui/src/lib/shortcuts.ts`, grouped by `File / Edit / View / Canvas / Help`, mono shortcut chip right-aligned |

The shortcuts catalog (`gui/src/lib/shortcuts.ts`) is the single source of
truth. New keybinds must be added there in addition to the real keydown
handler that owns the binding.

**The Shortcut-Row-Is-Read-Only Rule.** A `<CommandItem>` in shortcut mode
closes the palette on select but does NOT invoke the underlying action. The
shortcut row is a *reference*: the user reads the binding, dismisses, and
presses it. Duplicating action paths (palette row + keybind + menubar) would
create two cmdk-mount / file-dialog-mount surfaces per intent. Mirrors the
first-run keymap's "Shortcut-Is-Static-Text Rule".

**Trigger key = `?` (Shift+/).** Linear / Notion / Figma convention. Same
input-focus guard as `Ctrl+\`` and `Esc` — typing `?` into a text input
must still produce a literal `?`.

**3. Anatomy dialog.**

`gui/src/components/AnatomyDialog.tsx`. A modal visual legend for the canvas
vocabulary. Opens from `HelpMenu → "Anatomy"` via the `stream:open-anatomy`
custom event; no keybind by design (low-frequency reference doesn't earn a
binding, mirroring the menu-only `About` precedent).

**Surface:** Dialog at `w-[1300px] max-w-[95vw]`, top-anchored
(`top-[6vh]`). Body uses `bg-chrome` (top-toolbar tone) rather than the
darker `--dialog-surface` — the prior darker slab was hard to read against
and felt dropped-in. Atmospheric `--shadow-dialog` inherited from
`DialogContent` still carries the lift; the [[modal lock]] no-dim-scrim
doctrine still applies. `showCloseButton={false}` — click outside or press
Esc dismisses (the X read as ceremony for a panel that's already
two-action-away from canvas). Two showcases arranged horizontally with
`divide-x divide-border`. A single-line footer enumerates the four
outline states (rest / selected / error / preview) — the prior
"not-all-states-co-occur" disclaimer is unnecessary because the specimens
render rest state only.

**Typography (upsized 2026-05-28).** `DialogTitle` uses `text-display`
(20 px); section headers use `text-body uppercase`; inline node labels +
body-row caption + footer use `text-body text-foreground` (full opacity,
no `/55`/`/65` dim); edge row name uses `text-title`, description uses
`text-body`. The earlier `text-label`/`text-micro` + foreground/55-65
treatment was unreadable at the dialog's surface contrast.

**Distilled from the leader-and-chip diagram (Phase 72 critique P2-1,
2026-05-27).** The prior implementation was a 1340 px dialog with 640×520
tiles, dashed two-segment SVG leaders at constant slope (m=2.0), numbered
chips at the tile perimeter, and a two-column numbered legend below each
tile. The critique called it "a diagram, not a help surface" — a long-term
maintenance liability for a low-frequency reference panel. The leader
topology, slope math, chip-routing engine, and legend mapping are deleted;
each feature gets a plain text label positioned next to it (proximity =
relationship). Node specimen is ~220 px wide; total dialog is 800 px.

**Diagram source = visual mirror.** The dialog renders a *visual mirror* of
the production `StreamNode` rather than the real component, because
`StreamNode` reads from the global zustand store (`errorNodeIds`, `anchors`,
`hoveredSourceIds`, `pinnedSourceIds`, `activeLayers`, `hideOffLayer`) and
would need every selector path stubbed out to render in a non-canvas
context. The mirror consumes the same tokens (`--card`, `--color-layer-*`,
`--color-port-*`, `--border`) and matches the band geometry / body
structure / port placements. Only the **rest** state is shown — selected
ring, error outline, and Save Preset preview outline are documented in the
dialog footer line but not rendered on the specimen. When `StreamNode`
changes, update the mirror here too. Drift surface is intentionally small
(visual shell only, not behavior).

Edges are rendered as a list of four rows. Each row: `[96×28 SVG specimen]
{name} {one-line description}`. Specimens are inline SVG paths matching
`HydraulicEdge` (solid 1.5 px), `BCEdge` (dashed 6/3), `.validation-flow-
trace` (2.5 px warning-tinted dashed with marching ants), and a two-box
port-convention schematic. The marching-ants keyframe is scoped locally as
`anatomy-flow-march` to avoid depending on the global xyflow-scoped
`.validation-flow-trace .react-flow__edge-path` selector. Same
`prefers-reduced-motion` collapse rule.

**Inline labels (not callouts):** named features on the node specimen
(`anchor`, `flow in`, `layer band`, `thermal port`, `flow out`) are plain
mono text positioned absolutely next to the feature with
`text-foreground/65`. No numbered chips, no leader lines, no legend
mapping. The three body-text rows (component type, instance name, value
summary) share a single mono caption below the specimen — they are
self-evident from their visible content, so naming the row CATEGORY in
prose is enough.

**The Anatomy-Is-A-Legend-Not-Docs Rule.** Anatomy shows visual vocabulary;
it does NOT explain physics, components, or workflows. Documentation
(component reference, validation rule descriptions, STREAM.jl link-out)
explicitly stays out of scope — PRODUCT.md's "trust the expert" applies to
prose hand-holding, not to disambiguating visual cues. If a future need
arises for in-app rule documentation, that's a separate surface.

**HelpMenu entries (rebuilt):**
- `Shortcuts ?` — dispatches `stream:open-shortcuts`, opens palette in
  shortcut mode (mirrors `?` keybind path).
- `Anatomy` — dispatches `stream:open-anatomy`, opens AnatomyDialog.
- `About STREAM Composer` — unchanged (existing AboutDialog).

The prior disabled `Keyboard Shortcuts` stub is gone.

### Smart port-side convention (locked — Phase 72, 2026-05-22)

Replaces the original Phase 64 local-geometry algorithm in
`gui/src/lib/autoflip.ts`. The new algorithm is **convention-driven with
local-geometry refinement**.

1. **Dominant flow axis** is computed from the spread of NODE CENTERS
   (not full bboxes) with a **1.5× vertical bias**:
   `flowAxis = (spreadY × 1.5 ≥ spreadX) ? vertical : horizontal`.
   Hydraulic components are wide and short (~280 × 80 px); full-bbox
   spread misclassifies clearly vertical layouts. Center spread + bias
   matches the gravity-driven nature of hydraulic loops.

2. **Per-port local preference** aggregates `(dx, dy)` across ALL edges
   wired to that port (not first-edge-only). A pump.port_out feeding two
   consumers correctly resolves to "down" instead of arbitrarily picking
   left or right.

3. **Axis snap.** If a connected port's preference is perpendicular to the
   flow axis, snap to the natural side along the axis: port_in → TOP/LEFT,
   port_out → BOTTOM/RIGHT. **Disconnected ports are exempt** — D-11
   contract (registry-default for isolated ports) stays intact.

4. **Same-side collisions** resolve via convention: both ports go to their
   natural sides on the flow axis. The "tiebreak port_out wins" rule is
   gone; the convention wins on both-connected. When only one port is
   connected and the other is disconnected, the connected port keeps its
   preference and the disconnected one moves to the **opposite** side.

5. **Two ports never share a side.** Convention or opposite-displacement
   guarantees one-port-per-side. xyflow auto-spread of co-side handles is
   no longer relied on.

The Layer-Of-Flow-Convention Rule: even when local geometry would place
a port on a perpendicular side, the axis-snap forces the layout to read
as a clean "in from above, out below" (vertical) or "in from left, out
right" (horizontal) silhouette. Mixed-axis topologies still resolve
sanely because perpendicular preferences only snap when they conflict
with the flow axis.

### Obstacle-avoiding edge router (locked — Phase 72, 2026-05-22)

`gui/src/components/HydraulicEdge.tsx` consumes
`gui/src/lib/edgeRouting.ts`. xyflow's built-in `getSmoothStepPath`
treats edges as point-to-point and has zero awareness of node bboxes —
that produced the canonical "edge cuts through every node in the way"
bug.

**Router contract** (`computeRoutePoints({source, target, obstacles, ...})`):

1. Compute 5 candidate orthogonal paths: naive Z, plus wraps via the
   right / left / top / bottom lane. Each lane sits at
   `outermost-bbox-edge ± laneMargin` (default 32 px).
2. Wrap paths use **cluster-edge pivots**, not the port's own Y/X. For
   a T-shape topology where the port sits inside the cluster, the wrap
   extends from the port in its outward direction past the cluster bbox,
   travels along a side lane (outside all bboxes), and approaches target
   via the cluster-edge lane on the target's side.
3. Source and target nodes ARE included in `obstacles`. The path must
   stay outside their bodies, not just other nodes'.
4. Ranking priority: `(crossings, turns, length)`. The router always
   picks a zero-crossing candidate if any exists.

**Visual:** rounded corners (~6 px) via quadratic Bezier joints at each
turn. Matches the prior smoothstep visual style.

**The Edges-Never-Through-Bodies Rule.** Whatever the candidate cost,
zero bbox crossings is a hard invariant. If a future topology produces
no clean candidate, the candidate set is expanded (more lane variants,
multi-step detours), not relaxed.

### CodePreview (locked — Phase 72, 2026-05-23)

The bottom-panel code preview surface. Reads as a productized code panel
sitting inside the chrome, not a borrowed editor surface.

| Property | Value |
|---|---|
| Body background | inherits `--panel` from `BottomPanel` (no separate `--code-surface`); the chrome → panel → canvas depth hierarchy carries the surface step |
| Body text | `--foreground` mono 13 px, leading-1.55 |
| Section header | `text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-foreground` — no marker dot, no slab, no chip. mb-5 rhythm + typography contrast carries the divider (same idiom as ValidationPanel column-label row) |
| Sub-block — interactive | `px-3 py-1.5 rounded-sm cursor-pointer`. NO `border-l-2` colored stripe (PRODUCT.md absolute ban) — the pinned ring + bg tint provide the affordance |
| Sub-block — non-interactive scaffolding | `px-3 cursor-text` — plain code, no box affordance. Used for Imports header, `eqs = [` / `]`, Main `@named sys = …` block (sub-blocks with no `sourceIds`) |
| Hover state (interactive only) | `bg-[color-mix(in_oklch,var(--foreground)_5%,transparent)]`, no ring; `transition-colors duration-[80ms]` (matches primitive-layer motion vocabulary) |
| Pinned state | `bg-[color-mix(in_oklch,var(--foreground)_8%,transparent)]` + `ring-2 ring-[var(--foreground)]` |
| Flash state (one-shot navigation feedback) | `bg-[color-mix(in_oklch,var(--color-warning)_22%,transparent)]` + `ring-2 ring-[var(--color-warning)]`. Auto-clears after 1.5 s |
| Empty state | `text-muted-foreground italic text-xs` literal: `(empty — add components on the canvas to see generated Julia code)` |
| Syntax tinting | Consumes `--syntax-{keyword,string,type,macro,number}` per the §2 Code editor lane carve-out. Comments use `text-muted-foreground italic` (no separate token) |

The hover/pinned color is the canvas↔code link signal (see §2 Code-link
active state). Same token (`--foreground`) on both sides of the link: edges
+ canvas node rings on the canvas, sub-block ring + bg tint in the panel.
One signal, one token, no hue ambiguity with the layer accents or selection
ring.

### Preferences (locked — Phase 72, 2026-05-23)

User-global Preferences dialog reached from `Edit > Preferences…` and
`Ctrl+,` (Linear / Cursor / VSCode convention). Two-pane modal: 180 px
category rail (left) + dense setting rows (right). Locked Dialog vocab on
the outside; the ValidationPanel selected-row idiom on the rail.

**Strict user-global / per-project split.** Preferences carries strictly
app-scoped settings. Per-project values (`modelOptions.name`,
`description`, `default_fluid`, `g_default`, `solver`) stay on the
existing Project Options surface inside the Project tab. Settings that
moved from per-project to user-global in this phase (off-layer behavior,
snap to grid) drop from `.scp` on save and ignore on load — heavy-dev
policy (`feedback_no_back_compat_during_heavy_dev`) covers the file
break.

**Persistence.** `localStorage` with namespaced one-key-per-setting keys
(`stream-composer-pref.<category>.<setting>`). Per-key over one-blob so a
single corrupt value doesn't poison the whole prefs object, and future
Tauri config write-side maps cleanly to TOML. Cross-component sync via a
`stream:prefs-changed` CustomEvent broadcast on every `setPreference`.

**Surface dimensions.** Fixed `720 × 560` px. Desktop only (Tauri scope;
no responsive scaling). Categories list — Editor / Appearance / Files /
Validation / Code Export / Advanced — pinned in that order; Editor leads
because the canvas-behavior knobs are the highest-frequency reason to
open the dialog.

| Property | Value |
|---|---|
| Frame | Inherits the locked Dialog vocab (`--dialog-surface` + `--dialog-border` + atmospheric `--shadow-dialog` + transparent overlay). Top-anchored (`top-[80px] translate-y-0`) to match the CommandPalette + shortcuts-mode keymap lineage — the surfaces the user explicitly asked Preferences to "look like". |
| Header | `DialogTitle` "Preferences" at `text-title font-semibold`; no description string (self-explanatory); `DialogClose` X via the primitive default |
| Left rail | `w-[180px] shrink-0 border-r border-border bg-panel` — one tonal step darker than the popover body so it recedes |
| Rail row | `<button>` `h-9 px-3 mx-1 my-px rounded-sm text-body font-medium`; rest `text-foreground/65 hover:bg-card/60`; selected `bg-card text-foreground` + 2 px `--ring` left-edge stripe (mirrors ValidationPanel selected-row idiom — single project-wide selected-row vocabulary) |
| Right pane | `flex-1 overflow-y-auto px-6 py-5`; ScrollArea primitive; per-category header at the top uses the locked compact-uppercase-header idiom (`text-micro font-mono uppercase tracking-wide text-foreground/45`) |
| Setting row | `grid grid-cols-[1fr_auto] gap-6 items-center py-3 border-b border-border/40 last:border-b-0`; label-stack carries label (`text-body font-medium`) + one-line description (`text-label text-foreground/65`); right cell carries the control |
| Footer | `h-12 border-t border-border px-4`; left = `Reset all preferences` (ghost Button, destructive hover); right = `Done` (default Button, closes dialog); footer inline-replaces with a confirm row on Reset click (no separate AlertDialog — one less modal layer) |

**The Pref-Persists-Even-When-Unwired Rule.** Settings whose downstream
consumer doesn't read from the pref yet (Auto-flip ports, Density,
Reduce-motion override, Default zoom, Default open / export paths,
Code-export options, Daemon status, Performance overlay) render with a
disabled control + `Not yet wired.` mono micro line below the
description. The preference value still persists in localStorage on
change so future phases that wire the consumer don't need to touch the
dialog. The placeholder vocabulary (control disabled + mono note) is the
same for all such rows.

**The Theme-Lives-In-useTheme Rule.** Preferences > Appearance > Theme
consumes `useTheme()` directly, not a separate `appearance.theme` pref
key. `View > Theme` keeps its menu entry; both surfaces write to the
same `stream-composer-theme` localStorage key. Two entry points, one
source of truth. Mirrors the Off-layer / Snap to grid / Interactive
lock pattern: canonical state lives in the pref, multiple surfaces
write to it.

**The Canvas-Overlay-Buttons-Write-Through-Prefs Rule.** SnapToGridButton
and InteractiveLockButton on the canvas overlay no longer call
`useStore.setSnapToGrid` / `setInteractiveLocked` directly; they call
`setPreference("editor", "snapToGrid", …)` and the bridge
(`initPreferencesBridge` in `lib/preferences.ts`, mounted by App.tsx)
propagates the change back into the store's runtime mirrors. Reads
still come from useStore (selective primitive selectors) — the bridge
makes the canvas button and the Preferences dialog show the same
state without either knowing about the other.

**Reset all.** Inline confirm in the footer row — `Reset every
preference to its default?` + Cancel / Reset all buttons. On confirm,
`resetAllPreferences()` deletes every namespaced key and broadcasts a
single `stream:prefs-changed` event with `category: "*"`. Every
`usePreference` subscriber re-reads defaults. No Sonner toast — the
controls visibly reverting is the feedback.

**Wired side-effects** (downstream consumes the pref at run-time):
- `editor.offLayerBehavior` — useStore.hideOffLayer mirror via bridge
- `editor.snapToGrid` — useStore.snapToGrid mirror via bridge; canvas overlay button writes through
- `editor.interactiveLock` — useStore.interactiveLocked mirror via bridge; overlay button writes through
- `appearance.theme` — useTheme directly (not via pref store)
- `files.autorecoverEnabled` — gates `writer.schedule()` at fire-time
- `files.autorecoverIntervalMs` — read once at `initAutoRecover()`; changes require app restart
- `files.recentFilesMax` — read at `addToRecent` call-time
- `files.undoHistoryDepth` — read at `_pushSnapshot` call-time (inline localStorage to avoid pref-lib overhead on hot path)
- `validation.rulesEnabled` — runner filters validators at run-time
- `validation.defaultGroupBy`, `validation.defaultSeverityFilter` — ValidationPanel reads on mount (lazy initializer)

**Not-yet-wired** (pref persists; downstream doesn't read yet — surfaced
in the dialog with the disabled `Not yet wired.` placeholder vocab):
- `editor.autoFlipPortsOnConnect`
- `editor.showPortTypeOnHover`
- `editor.defaultZoomOnOpen`
- `appearance.density`
- `appearance.reduceMotion`
- `files.defaultOpenLocation`
- `validation.loopTracePersistence` (control is enabled — the loop-trace timeout consumer isn't wired yet but the dialog setting persists)
- `codeExport.defaultPath`, `indentWidth`, `includeSourceComments`, `openExportedFile`
- `advanced.showDaemonStatus`, `performanceOverlay`

**Switch primitive added.** `gui/src/components/ui/switch.tsx` — sliding
pill toggle (Radix Switch). The semantic for "binary on/off setting"
distinct from Toggle (toolbar press-button) and Checkbox (form-field
list selection). Documented radius exception: `rounded-full` (vs the
locked sm/md scale) because the pill shape IS the affordance —
"rounded-sm switch" reads as a wrong primitive. `h-5 w-9` (20 × 36 px)
matches Badge density. Off `bg-border`, on `bg-primary` (neutral
high-contrast slab matching Button primary posture). Thumb
`bg-background` so it reads against the track regardless of theme.

### Held open — per-surface decisions still queued

The non-`ui/` consumer surfaces below remain provisional. Each will be
decided in its own `/impeccable shape <surface>` session (see
`.planning/phases/72-gui-redesign/PROGRESS.md`).

**Application chrome**
- `CustomTitlebar` + `WindowControls`
- `SidebarPanel`
- `ResponsiveTabsList`

**Workflow surfaces**
- `CommandPalette` (cmdk-based)
- `ToolboxPanel` + `ToolboxItem`
- `PresetsPanel` + `PresetRow`
- Property forms in the sidebar (`SidebarPanel/*` subtree)
- BCs tab layout (Phase 65 deferred layout-fit issues land here)

**Menus + dialogs (consumer-side)**
- `EditMenu` / `ViewMenu` / `HelpMenu` / `FileMenu` / `NodeContextMenu`
- `AboutDialog`, `AutoRecoverRestoreModal`, `ExportConfirmDialog`,
  `SavePresetModal`, `UnsavedChangesDialog`

## 6. Do's and Don'ts

Locked, derived directly from PRODUCT.md + Phase 72 shape decisions. These
are **non-negotiable** across every surface decision in Phase 72 and beyond.

### Do:

- **Do** treat the canvas as the visually-lightest, most attention-claiming
  surface. Chrome recedes; canvas reaches out.
- **Do** write engineering-voice copy: terse, declarative, trust the expert.
  Every label, error, empty state, and tooltip assumes a reader who knows
  the domain.
- **Do** commit to every visual choice. Pick what fits the physical scene
  (engineer + desktop monitor + extended work session) and own it. No
  fence-sitting palettes, no "should we go dark or light," no defaults
  inherited from a starter template.
- **Do** optimize layout for an engineer running the build → export → run
  loop dozens of times an hour. Keyboard parity, command palette (cmdk
  is already in deps), zero unnecessary clicks.
- **Do** keep restraint as the default mode. Color appears with intent on
  the canvas; chrome surfaces stay neutral.
- **Do** match implementation complexity to aesthetic vision. Minimalism
  needs precision; if a surface chooses density, every spacing decision must
  be deliberate.
- **Do** preserve the `Input` auto-select-on-focus chokepoint across any
  restyling of input components.
- **Do** consume layer accents via the `LAYER_COLOR_VAR` map from
  `gui/src/lib/layerColors.ts` — never re-hardcode the hex.

### Don't:

- **Don't** drift toward generic shadcn / Vercel admin-dashboard look: gray
  cards, slate-50 backgrounds, lucide icons everywhere, rounded-lg on
  everything, illustrated empty states. (The current validator panel is the
  canonical bad example in this repo per
  `project_phase72_validator_ui_revisit`.)
- **Don't** add consumer-SaaS hand-holding: "Get started!" empty states,
  tooltips that explain the obvious, emoji in copy, conversational error
  messages, friendly framing.
- **Don't** drift toward legacy scientific UI (Java-Swing-era COMSOL/Ansys):
  gray panels, tiny system fonts, dozens of nested toolbars, modal-heavy
  workflows.
- **Don't** drift toward observability / SRE dashboard cliché: dark navy +
  cyan accents + gradient glow + monospace-everywhere.
- **Don't** ship anything that reads as "obviously LLM-generated":
  purple gradients, nested cards, gradient text, low-contrast labels,
  hero-metric templates, identical card grids.
- **Don't** use `border-left > 1px` or `border-right > 1px` as a colored
  accent stripe. Rewrite with full borders, background tints, leading
  numbers/icons, or nothing.
- **Don't** use `background-clip: text` with a gradient (gradient text).
  Use a solid color; emphasis via weight or size.
- **Don't** use `#000` or `#fff`. Tint every neutral toward hue 254 at
  chroma 0.003–0.005.
- **Don't** use em dashes in copy. Use commas, colons, semicolons, periods,
  or parentheses.
- **Don't** reach for a modal as the first thought. Exhaust inline and
  progressive alternatives before opening a `Dialog`.
- **Don't** nest cards. Nested cards are always wrong.
- **Don't** ship animations under `prefers-reduced-motion: reduce` other
  than instant transitions. (Cross-cutting `/impeccable harden` pass owns
  remediation across the codebase.)
- **Don't** introduce a primitive layer that competes with shadcn + Radix
  (another component library, hand-rolled buttons that bypass `Button`,
  ad-hoc dialogs that bypass `Dialog`).
- **Don't** use HSL or sRGB color tokens. Convert to OKLCH.
- **Don't** mix color spaces within a single visual surface.
- **Don't** preserve a current visual choice solely because "we already
  shipped it." Per `feedback_gui_no_design_inertia`, nothing currently
  visible is sacred. If a redesign suggestion improves on a current value,
  lean into it.
- **Don't** apply blurred `box-shadow` to `@xyflow/react`-transformed canvas
  nodes. Zero-blur only (perf doctrine — blurred shadows force full-layer
  repaint on every pan/zoom frame).
- **Don't** hardcode layer-accent hex anywhere. Use `LAYER_COLOR_VAR` from
  `gui/src/lib/layerColors.ts`. The 4 OKLCH values in §2 are the only
  canonical source.
- **Don't** target `[data-id]` (xyflow's wrapper) when adding visual
  classes to a node from outside React (e.g. `classList.add` in
  CanvasPanel). Target `[data-stream-node-id]` instead so the class lives
  on the same DOM element as the React-rendered persistent visual state.
