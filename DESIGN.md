---
name: STREAM Composer
description: Desktop visual editor that produces STREAM.jl Julia scripts for MTR plate-fuel safety analysis
---

<!-- PARTIAL SEED — Phase 72 in progress.

LOCKED (from /impeccable shape canvas, 2026-05-21):
  - §2 Colors except --destructive / --ring / --border (still provisional)
  - §3 Type scale (1.25 Major Third); font choice + typography direction still TBD
  - §4 Depth approach (3-tier tonal layering with structural shadows); shadow vocab still TBD
  - §5 StreamNode visual treatment + canvas background (grid lines)

STILL HELD OPEN:
  - §3 Font choice and typography direction — pending /impeccable shape first-run + help-system
  - §4 Shadow vocabulary specifics — pending /impeccable shape shadcn-primitive-layer
  - §5 All non-StreamNode component surfaces — see "Held open" list at the end of §5

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
| `--ring`           | `oklch(0.50 0.01 250)`       | `oklch(0.708 0 0)`           | provisional |
| `--border`         | `oklch(1 0 0 / 11%)`         | `oklch(0.922 0 0)`           | provisional |
| `--color-warning`  | `oklch(0.78 0.15 75)`        | `oklch(0.74 0.16 75)`        | **locked** |
| `--color-info`     | `oklch(0.72 0.16 240)`       | `oklch(0.62 0.18 240)`       | **locked** |

`--color-warning` and `--color-info` were introduced this phase to replace
raw `text-yellow-500` / `text-blue-500` in ValidationPanel.

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
matches Linear/Cursor/Rive lineage. Tailwind utilities currently use
arbitrary `text-[Npx]` values — migration to a real scale (e.g.
`text-micro` / `text-label` / `text-body`) is deferred to the
shadcn-primitive shape session.

### Font choice — `[TBD]`

Current code uses the Tailwind default system stack:
`-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif`.

This is a *default*, not a chosen pairing. Decision deferred to the
`/impeccable shape first-run` or `/impeccable shape help-system` session
where typographic identity becomes load-bearing. Options on the table when
that decision lands: keep system fonts (good performance, native feel, no
commit); commit to a specific sans pairing (Inter / IBM Plex Sans / Söhne
/ Geist / Suisse Int'l); add a monospaced face for numerics and code
surfaces (JetBrains Mono / Berkeley Mono / Commit Mono / IBM Plex Mono).
The Composer is not a content-reading tool, so an editorial serif is
unlikely to earn its weight.

### Typography direction — `[TBD]`

Single sans / sans + mono pairing / mono-forward / sans with selective
serif. Same shape session as font choice will resolve this.

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

### Shadow vocabulary — `[TBD]`

Specific shadow values are still inherited shadcn defaults (`shadow-xs`,
`shadow-md`, `shadow-lg`, `shadow-xl`). Recommitment deferred to the
shadcn-primitive shape session.

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
| Selected state | top band thickens 4 → 8 px + `ring-2 ring-[var(--ring)] ring-offset-1 ring-offset-canvas` |
| Persistent error state | `outline outline-2 outline-[var(--destructive)]` (simpler than the prior outline+ring double signal) |
| autoExtended state | `outline outline-2 outline-dashed outline-[var(--chart-5)] outline-offset-2` |
| Code-hovered (transient) | `.stream-node--code-hover` class — outline 2 px, sky-400 placeholder (will be tokenized in edges-and-code-preview shape) |
| Code-pinned (transient) | `.stream-node--code-pinned` class — 3 px outline + zero-blur 1 px halo, sky-300 placeholder |
| Validation flash (navigation feedback) | `.validation-flash` class added by CanvasPanel.onNodeFlash; targets `data-stream-node-id` (NOT xyflow's `data-id` wrapper) so it lives on the same element as the persistent error outline; outline-offset 0, animates outline-color over 600 ms |
| Multi-layer split band | Components with both FlowPort AND ThermalPort (ChannelAndContacts today) render a 2-segment band: left half = first layer, right half = second layer. Detected via `getDisplayLayers()` in `gui/src/lib/layers.ts` |

### Held open — per-surface decisions (queued shape sessions)

All other component styling is **still provisional**. Existing shadcn
primitives provide working defaults; each is decided per-surface during
the queued `/impeccable shape` sessions (see
`.planning/phases/72-gui-redesign/PROGRESS.md` for the active queue).

Surfaces still requiring per-surface shape decisions:

**Application chrome**
- `CustomTitlebar` + `WindowControls`
- `BottomPanel` (collapsed-state stub strip + expanded body)
- `SidebarPanel`
- `ResponsiveTabsList`
- `WelcomeOverlay` (will be replaced by `/impeccable shape first-run`)

**Canvas + signature surfaces still pending**
- `BCEdge`, `HydraulicEdge` (typed edges + dashed BC edge variant) —
  `/impeccable shape edges-and-code-preview`
- Pinned-node halo + hover-ring color tokenization — same session

**Workflow surfaces**
- `CommandPalette` (cmdk-based)
- `ValidationPanel` + `ValidationStatusBar` — `/impeccable shape ValidationPanel`
- `ToolboxPanel` + `ToolboxItem`
- `PresetsPanel` + `PresetRow`
- `CodePreview` — `/impeccable shape edges-and-code-preview`
- Property forms in the sidebar (`SidebarPanel/*` subtree)
- BCs tab layout (Phase 65 deferred layout-fit issues land here)

**Menus + dialogs**
- `EditMenu` / `ViewMenu` / `HelpMenu` / `FileMenu` / `NodeContextMenu`
- `Dialog` + `AlertDialog` core presentation
- `AboutDialog`, `AutoRecoverRestoreModal`, `ExportConfirmDialog`,
  `SavePresetModal`, `UnsavedChangesDialog`

**shadcn primitives** — `/impeccable shape shadcn-primitive-layer`
- `Button` (variants + sizes), `Input`, `Textarea`, `Label`,
  `Checkbox`, `RadioGroup`, `Toggle`, `ToggleGroup`,
  `Select`, `DropdownMenu`, `Menubar`, `ContextMenu`,
  `Tabs`, `Popover`, `Tooltip`, `Separator`, `ScrollArea`,
  `Badge`, `Command`, `Sonner`

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
