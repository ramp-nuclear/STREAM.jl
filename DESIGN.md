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
| `--shadow-dialog`  | `0 8px 24px -8px oklch(0.05 0.012 254 / 0.50), 0 2px 6px -2px oklch(0.05 0.012 254 / 0.30)` | `0 8px 24px -8px oklch(0.20 0.012 254 / 0.20), 0 2px 6px -2px oklch(0.20 0.012 254 / 0.10)` | **locked** — the ONE structural shadow in the system (Dialog/AlertDialog/Sheet only) |
| `--color-warning`  | `oklch(0.78 0.15 75)`        | `oklch(0.74 0.16 75)`        | **locked** |
| `--color-info`     | `oklch(0.72 0.16 240)`       | `oklch(0.62 0.18 240)`       | **locked** |

`--color-warning` and `--color-info` were introduced earlier to replace
raw `text-yellow-500` / `text-blue-500` in ValidationPanel. `--border-hover`
and `--shadow-dialog` were introduced in the primitive-layer shape pass.

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

### Shadow vocabulary (locked — primitive-layer shape, 2026-05-22)

**Single tier.** `--shadow-dialog` is the only structural shadow in the
system. Applied to Dialog, AlertDialog, and Sheet — the surfaces where the
modal scrim flattens the tonal hierarchy and a crisp lift cue is needed to
restore "this floats above the canvas." Tuned for "lift, not glow" — low
alpha, low blur, double-stop with a tight near-shadow.

**Zero shadow** on Popover, DropdownMenu, ContextMenu, Menubar, Tooltip,
Select dropdown, HoverCard, Sonner toast, Input, Textarea, Checkbox,
RadioGroup, Button, Toggle, ToggleGroup, Badge, Card, Tabs. These float on
the tonal step alone — `bg-popover` is one tone lighter than `--panel` and
darker than `--canvas`, which provides visible contrast on its own.

The inherited shadcn defaults (`shadow-xs`, `shadow-md`, `shadow-lg`,
`shadow-xl`) are no longer applied by any primitive. Consumer surfaces that
still reference them will get migrated during `/impeccable polish` at phase
end.

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
| Severity prefix | 32 px (resizable, min 28 / max 64) | Mono 11 px, color-tokenized via `--destructive` / `--color-warning` / `--color-info`. Labels: `ERR`, `WRN`, `INF`. **No Lucide AlertCircle/Triangle/Info icons.** |
| Validator id    | 200 px (resizable, min 80 / max 480)  | Mono 13 px, `foreground/85`, `truncate` with native `title` tooltip. **Leads the row** — Linear-issue-id pattern; the engineer reads the rule identity first. |
| Message         | fluid remainder                       | Sans 13 px, `foreground`, `truncate` with native `title`. |

Pinned in absolute pixel widths (not `ch` units): the column-header row uses
mono 10 px and data rows use mono+sans 11–13 px, so `ch` would resolve
differently in each grid container and the header would drift left of the
data. Px keeps them locked.

**Row vocabulary that's banned:**

- No Lucide alert icons in any cell. Severity is conveyed by the mono
  prefix + color token alone.
- No FixAction buttons. The `FixAction` discriminated union and the
  `fixAction?` field on `ValidationResult` were deleted at the type level
  Phase 72. Validation is a recognize-and-locate surface, not a remediation
  surface (`feedback_no_validator_fixaction_buttons`).
- No `text-yellow-500` / `text-blue-500` raw Tailwind for severity colors.
  Severity flows through `--destructive` / `--color-warning` / `--color-info`
  tokens only.

**Panel header (two sub-rows above the data):**

1. Controls row — left side: `{N} issues` count in mono 11 px. Right side
   in this order: severity filter pills (`ERR 12 WRN 4 INF 2`) + sliders
   icon that opens a Group-by popover.
2. Column labels row — `SEV / RULE / MESSAGE` in mono 10 px uppercase
   `foreground/45`. Hairline `--border` underneath.

The header has TWO draggable column-resize handles (between SEV/RULE and
RULE/MESSAGE), 6 px wide hit-zones with a 1 px `--ring` visible on hover
and `col-resize` cursor. Drag updates BOTH the column-header row and
every data row via a shared `gridTemplate` state.

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
│  ERR 12   WRN 4   INF 2          Code  Validation        ⌄       │   ← 22 px footer (always)
├──────────────────────────────────────────────────────────────────┤
│  [ BottomPanel body when open ]                                  │
└──────────────────────────────────────────────────────────────────┘
```

- Left cluster — severity count segments. `ERR` / `WRN` / `INF` mono labels
  + tabular-nums count. Click any segment → opens panel on Validation tab
  with that severity filter pre-applied via `stream:validation-filter`.
  Zero counts dim to ~55% opacity. 0 → N pulse on the error segment
  preserved.
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

### First-run empty-canvas hint (locked — Phase 72, 2026-05-22)

Replaces `WelcomeOverlay`'s prior centered card with a chromeless typographic
anchor on the canvas surface. Renders only when
`nodes.length === 0 && edges.length === 0` (gated on a single boolean
primitive selector so it doesn't repaint during ReactFlow drags). Resolves
Audit P0-1 + P2-1 + Critique P1-1.

**Visual:** no card, no shadow, no border, no rounded panel, no wordmark.
Block is `w-[280px]`, centered horizontally and vertically inside the
canvas, pointer-events-none on the outer wrapper so the empty area still
accepts drag-drop / pan / zoom; pointer-events-auto on the inner block so
recent rows are clickable.

**Layout:**

```
recent                              ← text-micro mono uppercase foreground/45 (only when ≥1 recent)
loop_v2                             ← text-label mono foreground/85, <button>, rounded-sm
hex_cube_transient                    hover bg-card, 80 ms transition-colors, focus-visible ring-2 ring
mtr_3plate                            extension stripped; native title= for full path
plate_lof_demo                        max 5 rows
                                    ← hairline --border, my-2 mx-2 (only when ≥1 recent)
Ctrl+O   open project               ← shortcut chip (text-micro mono foreground/55, w-16 fixed)
Ctrl+N   new                          + sans label (text-label foreground/65)
Ctrl+P   command palette              static text — the keybind IS the affordance
```

Cold-start (no recents) collapses to the keymap alone — no `recent`
section label, no separator.

**Copy doctrine:**
- Section label `recent` lowercase. NOT "Recent Projects."
- Shortcut labels lowercase, action-only: `open project`, `new`,
  `command palette`. No "Open Project…" with title-case + ellipsis.
- No "Welcome to STREAM Composer", no "to get started", no drag-drop
  instruction text. The empty canvas + visible toolbox panel + menubar
  already say "drop something here."

**Shortcut idiom:** plain `Ctrl+...` text matching the menubar
(FileMenu / EditMenu / etc.). No `⌘` glyph branching; consistency with
the menubar wins over per-platform glyph correctness in a tool whose
primary deployment is Linux/WSL2 desktop.

**The Shortcut-Is-Static-Text Rule.** The keymap rows are documentation,
not click affordances. Users press the keybind; they don't click the
shortcut chip. Duplicating the menubar's click paths on the canvas
would introduce two cmdk-mount / file-dialog-mount paths for the same
action. Recents ARE buttons because they encode a *specific path*
(`loop_v2.scp`) the menubar's "Open Recent" submenu doesn't anchor on
the eye-landing spot.

**A11y:** recent rows are real `<button>` elements with native keyboard
nav, `focus-visible:ring-2 ring-ring`, and `motion-reduce:!duration-0`
on the hover transition. Replaces the prior `div onClick` a11y
violation. Shortcut rows are static text (no role, no tabIndex —
nothing to focus).

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

**Held open — per-surface decisions still queued**

The non-`ui/` consumer surfaces below remain provisional. Each will be
decided in its own `/impeccable shape <surface>` session (see
`.planning/phases/72-gui-redesign/PROGRESS.md`).

**Application chrome**
- `CustomTitlebar` + `WindowControls`
- `SidebarPanel`
- `ResponsiveTabsList`

**Canvas + signature surfaces still pending**
- `BCEdge` (dashed BC edge variant) — HydraulicEdge already done
- Pinned-node halo + hover-ring color tokenization

**Workflow surfaces**
- `CommandPalette` (cmdk-based)
- `ToolboxPanel` + `ToolboxItem`
- `PresetsPanel` + `PresetRow`
- `CodePreview`
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
