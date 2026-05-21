---
name: STREAM Composer
description: Desktop visual editor that produces STREAM.jl Julia scripts for MTR plate-fuel safety analysis
---

<!-- SEED: This DESIGN.md is a forward-looking scaffold, not a photograph of
current code. Per `feedback_gui_no_design_inertia`, the existing visual state
was Claude-generated without design skills; nothing visual is locked.

Most tokens are deliberately held open ([TBD per surface]). Current code values
are noted as "provisional" — visible for context, not enforced by audit.

Two-pass protocol per Impeccable's `document.md`:
  1. This seed file documents locked doctrine + held-open slots.
  2. As `/impeccable shape <surface>` decides per-surface values during
     Phase 72 execution, promote each [TBD] to a locked value here.
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

These are the only items in this document that are *not* up for redesign during
Phase 72. They are project-shape decisions, not visual ones.

- **Color space:** OKLCH only. No HSL or sRGB in tokens. Hex is acceptable for
  layer-accent prose names where the token is consumed in JS (e.g. inline node
  styling that bypasses Tailwind JIT); the underlying color is still chosen in
  OKLCH and converted.
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
  four physics layers in the domain, not because of a visual choice. Four
  distinct layers will be visually signaled in *some* way. *How* that signaling
  works (hue, texture, weight, position, icon, combination) is OPEN.

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
- **No `#000` or `#fff`.** Tint every neutral toward a chosen hue
  (chroma 0.005–0.01 is enough to read as warm or cool without registering
  as colored).
- **Restrained's "one accent ≤10%" rule applies only if Restrained is chosen.**
  Committed / Full palette / Drenched strategies exceed it on purpose.

### Color strategy

`[TBD]` — Restrained / Committed / Full palette / Drenched. Will be resolved at
the first per-surface `/impeccable shape <surface>` decision (likely the canvas
itself or the toolbox panel, since those drive global color identity). Until
then, every color choice in code is provisional and may be replaced wholesale.

### Held open — current values provisional, NOT enforced

#### Neutrals (current code uses chrome → panel → canvas tonal hierarchy)

The *concept* of a 3-tier depth hierarchy is provisional. It may survive into
the final system; it may be replaced by single-surface, ambient/active zones,
edge-light affordance, or another approach. Current values exist as a starting
point for the per-surface shape conversation:

- `--chrome` provisional: dark `oklch(0.19 0.011 254)` / light `oklch(0.92 0 0)`
- `--panel`  provisional: dark `oklch(0.215 0.012 254)` / light `oklch(0.97 0 0)`
- `--canvas` provisional: dark `oklch(0.24 0.012 254)` / light `oklch(1 0 0)`

Dark mode lineage (One Dark Pro warm blue-grey, hue ≈254) is a Claude default
inherited from a popular developer-tool aesthetic. It is **explicitly up for
redesign** — the fact that other tools use it is a reason to consider
alternatives, not a reason to keep it.

Light mode currently uses pure achromatic neutrals (chroma 0). Whether the
chosen hue should tint light mode (per the no-#fff rule above) is OPEN.

#### Layer accents (4 slots required; visual treatment OPEN)

The 4-layer taxonomy needs distinct per-layer signaling. *Whether* that signal
is color is itself open. Current code uses 4 Tailwind-default hues, all
provisional, all Claude defaults:

- Hydraulic    provisional `#3b82f6` (blue-500)
- Thermal      provisional `#f59e0b` (amber-500)
- Sources      provisional `#8b5cf6` (violet-500)
- ReactorPhysics provisional `#f43f5e` (rose-500)

Known issue (Phase 72 cleanup target): these hex values are duplicated between
`StreamNode.tsx` and `LayersPanel.tsx` with no shared token. Whatever signaling
scheme replaces this must live in a single source of truth.

#### Functional roles (all provisional)

- `--destructive` (error / delete / dangerous action) — provisional
  `oklch(0.577 0.245 27.325)` light / `oklch(0.704 0.191 22.216)` dark
- `--ring` (keyboard focus indicator) — provisional `oklch(0.708 0 0)` light /
  `oklch(0.50 0.01 250)` dark
- `--border` (chrome separators) — provisional `oklch(0.922 0 0)` light /
  `oklch(1 0 0 / 11%)` dark
- Chart data palette (5 slots) — all provisional, all open

Known drift target (Phase 72 cleanup): validation warning highlight currently
uses `hsl(38 92% 50%)` mixed with the OKLCH `--destructive`. The HSL value
violates the OKLCH-only rule above and will be replaced when the color
strategy is decided.

### Named Rules

Deferred until color strategy is resolved. Reserved slot:
**The [TBD] Rule.** [content set at first per-surface shape decision]

## 3. Typography

### Locked rules

- **Body line length capped at 65–75ch** in any reading-shaped surface
  (none currently exist; relevant if a long-form panel like a property
  description or help drawer appears).
- **Hierarchy uses scale + weight contrast**, ratio ≥1.25 between steps. Avoid
  flat scales (where every step is the same size with weight as the only
  differentiator).

### Held open

#### Font choice — `[TBD]`

Current code uses the Tailwind default system stack:
`-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif`.

This is a *default*, not a chosen pairing. Options for the per-surface shape
conversation: keep system fonts (good performance, native feel, no commit);
commit to a specific sans pairing (Inter / IBM Plex Sans / Söhne / Geist /
Suisse Int'l, etc.); add a monospaced face for numerics and code surfaces
(JetBrains Mono / Berkeley Mono / Commit Mono / IBM Plex Mono); add a display
face for any rare typographic moments. The Composer is not a content-reading
tool, so an editorial serif is unlikely to earn its weight.

#### Type scale — `[TBD]`

Current code uses an ad-hoc scale that emerged from per-component decisions:
10 px (layer header micro-labels), 11 px (status bar), 13 px (inputs, layer rows,
menu items), 14 px (default `text-sm`), 18 px (`DialogTitle`). This is not a
designed scale. Whether to commit to a 1.25 (Major Third) / 1.33 (Perfect
Fourth) / 1.5 / custom-derived scale is OPEN.

#### Typography direction — `[TBD]`

Single sans / sans + mono pairing / mono-forward / sans with selective serif
for distinctive moments. Resolved at first per-surface shape conversation.

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
  responsiveness. The existing pinned-node halo is a worked example of
  this rule (crisp 1-px box-shadow halo, no blur).

### Held open

#### Depth approach — `[TBD]`

How depth is conveyed across the app is OPEN. Current code uses tonal layering
(the chrome/panel/canvas hierarchy from §2) plus minimal shadow-xs on inputs +
shadow-lg on modals (inherited from shadcn defaults). Whether to keep that
approach, go fully flat with stronger borders and rely on tonal layering alone,
or adopt a different elevation language entirely is decided per-surface.

#### Shadow vocabulary — `[TBD]`

If shadows survive, the vocabulary (number of steps, intensity, hue, whether
single-side or radial) will be defined when the elevation approach is decided.

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
  `ToolboxPanel`, layer-aware connect logic, layer dim/hide system. Their
  *visual* treatment is open; their *structural* existence is locked.

### Held open — per-surface decisions

All component styling is **provisional**. Existing shadcn primitives provide
working defaults; whether each one stays as-is, gets restyled, or gets
replaced is decided per-component during `/impeccable shape <surface>` work.

Surfaces requiring per-surface decisions (alphabetical; not priority order):

**Application chrome**
- `CustomTitlebar` + `WindowControls`
- `BottomPanel` (collapsed-state stub strip + expanded body)
- `SidebarPanel`
- `ResponsiveTabsList`
- `WelcomeOverlay`

**Canvas + signature surfaces**
- `CanvasPanel` (background, grid, overlays)
- `StreamNode` (the signature node — heavy current customization)
- `BCEdge`, `HydraulicEdge` (typed edges + dashed BC edge variant)
- `LayersPanel` floating chip and dropdown
- Layer accent system (4-slot signaling — color/texture/weight/etc. OPEN)
- Pinned-node halo + hover-ring (currently placeholder sky-400/300)
- Marquee selection rectangle

**Workflow surfaces**
- `CommandPalette` (cmdk-based)
- `ValidationPanel` + `ValidationStatusBar` — explicitly flagged for
  fundamentals revisit per `project_phase72_validator_ui_revisit`
- `ToolboxPanel` + `ToolboxItem`
- `PresetsPanel` + `PresetRow`
- `CodePreview`
- Property forms in the sidebar (`SidebarPanel/*` subtree)
- BCs tab layout (Phase 65 deferred layout-fit issues land here)

**Menus + dialogs**
- `EditMenu` / `ViewMenu` / `HelpMenu` / `FileMenu` / `NodeContextMenu`
- `Dialog` + `AlertDialog` core presentation
- `AboutDialog`, `AutoRecoverRestoreModal`, `ExportConfirmDialog`,
  `SavePresetModal`, `UnsavedChangesDialog`

**shadcn primitives (each may need restyling)**
- `Button` (variants: default / destructive / outline / secondary / ghost /
  link; sizes: xs / sm / default / lg / icon / icon-xs / icon-sm / icon-lg)
- `Input`, `Textarea`, `Label`
- `Checkbox`, `RadioGroup`, `Toggle`, `ToggleGroup`
- `Select`, `DropdownMenu`, `Menubar`, `ContextMenu`
- `Tabs`, `Popover`, `Tooltip`, `Separator`, `ScrollArea`
- `Badge`, `Command`, `Sonner` (toaster)

Each surface decided in isolation; the decisions roll up into a coherent system
through this DESIGN.md as values get promoted from `[TBD]` to locked.

## 6. Do's and Don'ts

Locked, derived directly from PRODUCT.md. These are **non-negotiable** across
every surface decision in Phase 72 and beyond.

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
- **Do** keep restraint as the default mode. Color appears with intent.
  Visual interest comes from typography contrast and spatial rhythm.
- **Do** match implementation complexity to aesthetic vision. Minimalism
  needs precision; if a surface chooses density, every spacing decision must
  be deliberate.
- **Do** preserve the `Input` auto-select-on-focus chokepoint across any
  restyling of input components.

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
- **Don't** use `#000` or `#fff`. Tint every neutral toward the chosen hue.
- **Don't** use em dashes in copy. Use commas, colons, semicolons, periods,
  or parentheses.
- **Don't** reach for a modal as the first thought. Exhaust inline and
  progressive alternatives before opening a `Dialog`.
- **Don't** nest cards. Nested cards are always wrong.
- **Don't** ship animations under `prefers-reduced-motion: reduce` other
  than instant transitions.
- **Don't** introduce a primitive layer that competes with shadcn + Radix
  (another component library, hand-rolled buttons that bypass `Button`,
  ad-hoc dialogs that bypass `Dialog`).
- **Don't** use HSL or sRGB color tokens. Convert to OKLCH.
- **Don't** mix color spaces within a single visual surface. (Current
  validation field highlight mixes HSL warning with OKLCH destructive —
  Phase 72 cleanup target.)
- **Don't** preserve a current visual choice solely because "we already
  shipped it." Per `feedback_gui_no_design_inertia`, nothing currently
  visible is sacred. If a redesign suggestion improves on a current value,
  lean into it.
- **Don't** apply blurred `box-shadow` to `@xyflow/react`-transformed canvas
  nodes. Zero-blur only (perf doctrine — blurred shadows force full-layer
  repaint on every pan/zoom frame).
- **Don't** assume the 4-layer accent colors `#3b82f6 / #f59e0b / #8b5cf6 /
  #f43f5e` are correct. They were grabbed from Tailwind defaults and are
  fully open for redesign.
- **Don't** assume the One Dark Pro dark mode lineage is correct. It is a
  Claude default, not a chosen aesthetic.
- **Don't** assume the chrome/panel/canvas 3-tier depth concept is correct.
  It survived from Phase 67 Plan 04 as a Claude default; if Impeccable
  suggests a different elevation language for a surface, evaluate it on
  merits, not on "we already use this."
