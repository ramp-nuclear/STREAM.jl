---
title: GUI Redesign — Architectural Decisions and Design Contract
date_started: 2026-05-10
status: working draft (incremental — being updated as exploration continues)
context: gsd:explore session re-evaluating the v0.8 STREAM Composer GUI under SNAP research, atop the v1.1 channels-redesign architecture
session_lineage: see "Conversation Lineage" section at bottom
---

# GUI Redesign — Architectural Decisions and Design Contract

This document is the canonical, on-disk memory of the GUI redesign exploration
that began under `/gsd:explore` on 2026-05-10. It is updated incrementally as
the conversation continues. **If anything in conversation context appears to
disagree with this document, this document is authoritative** — re-sync from
here, do not invent.

The motivating frame: the v0.8 STREAM Composer GUI shipped a working but basic
Tauri 2 + React + ReactFlow code-generation tool. The user obtained substantial
SNAP research (RELAP5 graphical preprocessor, NUREG/CR-6974 architectural
report) which surfaced architectural patterns and features worth incorporating.
Mid-conversation, a parallel codebase milestone — **v1.1 channels-redesign**
(PR #15, commit `cd3a073`, currently on branch `channels-redesign`, 1 commit
ahead of `origin/main`, FF-mergeable) — was confirmed to be merging into main
shortly. The GUI redesign work is scoped *atop* that new channel architecture.

---

## 1. Hard Constraints

These are load-bearing decisions that frame everything else. **Do not relitigate
without explicit user instruction.**

- **The GUI is a code-generation tool, not a simulation environment.** No Julia
  runtime is embedded in the GUI. The output is a `.jl` script the user runs
  outside the GUI. This rules out (from SNAP recommendations): in-process solve,
  named IC sets from real solves, post-solve variable browser, MTK compile
  diagnostics from a live system, solve monitor, integrated plots from
  solutions, equation-view of compiled MTK system.
- **The shell stays Tauri 2 + React + ReactFlow.** The architectural shifts in
  this milestone are state-shape refactors + UX overhauls + new features atop
  the existing stack, not a framework swap.
- **One static panel layout, with resizable splits.** No dockable workspaces, no
  user-rearrangeable panel positions.
- **No multi-view of the same model.** Zoom in/out is sufficient for STREAM-scale
  models.
- **No manual edge waypoint dragging.** Edge routing is fully automatic; user
  controls layout via component placement and (per Section 3.3) implicit
  per-port autoflip.
- **Per-channel signed gravity (`g`)**, not a global. Verified in
  `src/examples.jl:401-413` and `check_gravity_mismatch` in
  `src/composition/helpers.jl`. A future polish could introduce a model-level
  default magnitude inherited unless overridden, but `g` itself is per-component.
- **v1.1 channel architecture is the source of truth.** Under PR #15:
  - `Channel` has **no thermal port** — exposes per-cell `T_wall_left[1:n]` /
    `T_wall_right[1:n]` as channel-level `@variables` plus `h_left` / `h_right`
    constructor kwargs (`Real | AbstractVector | Function`).
  - `ChannelHeatFlux` has **no thermal port** — exposes per-cell `q_left[1:n]` /
    `q_right[1:n]` as channel-level `@variables`.
  - `ChannelAndContacts` is the **only** variant with ThermalPorts —
    `thermal_left[1:n]` / `thermal_right[1:n]` arrays.
  - Two new value-source components, `WallTemperature` and `HeatFluxSource`,
    close `Channel`'s `T_wall_*` and `ChannelHeatFlux`'s `q_*` variables via
    binding equations.
  - **Architectural invariant from `feedback_channel_hd_connection_rule.md` and
    the redesign docstring:** *only `ChannelAndContacts` ever connects to
    `HeatDiffusion`.* `Channel` and `CHF` never do.

---

## 2. Design Philosophy

Stated by the user in their own words throughout the conversation; consolidated
here as the *why* behind the *what*.

- **"Designed with intention so work is smooth and stuff is where you expect it
  after learning to use it."** — This is the user's actual goal, not a specific
  visual aesthetic. Visual style is decoration; the *rules* are what make it
  feel intentional.
- **The visual identity target is professional engineering software, not
  consumer-SaaS playgrounds.** The user named the existing v0.8 look as feeling
  like "a more amateur playbox instead of a professional, nuclear reactor
  thermohydraulic design tool." This is THE guiding principle for the
  design-system phase. Reference fingerprints: **NUREG / ANSYS / Aspen Plus /
  SmartPlant** for *seriousness*; **Figma / Linear** for *polish discipline*;
  not Notion / Vercel for surface aesthetic. Concretely:
  - Reduce decorative chrome — sharper edges, less shadow, less rounded
    card-styling, less whitespace.
  - Increase information density — show more values on the canvas itself.
    Engineering tools have more inline info than consumer tools.
  - Numerical values visible where relevant (BC values, parameters, validation
    state) — not buried behind clicks.
  - Muted, deliberate color palette — neutrals dominate; existing accents stay
    rigorous.
  - Tighter typography (smaller comfortable size; restricted type scale).
  - Status surfaces (validation, layer, dirty, connection counts) in fixed
    locations — not popups or animations.
- **The GUI must let the user design 99.9% of possible STREAM systems** without
  dropping to code. Some genuinely odd custom things may still require code;
  that is acceptable.
- **The user is responsible for laying out components nicely.** The GUI does
  not attempt to magically auto-route around bad layouts.
- **Premium feel ≠ chasing a specific app's aesthetic.** It means: consistency
  rules, predictability, smooth workflow, no surprises after the user has
  learned the tool. Surface aesthetic is layered on top.
- **Everything findable via menus, not buried.** Command palette and other
  shortcuts are *additive*, never the only path.
- **Simplicity over capability where capability has no obvious payoff.** The
  user explicitly rejected dockable workspaces, full command palette
  (action-invocation flavor), multi-view, and manual edge waypoints because the
  basic shape of the tool doesn't justify them.
- **No Unicode in Julia variable names** (existing project rule, applies to any
  generated code as well).

---

## 3. Architectural Decisions

### 3.1 Correlation Refactor — `geom`-first Convention

**Codebase-side change**, lives in `src/physical_models/htc/correlations.jl` and
`src/physical_models/friction/correlations.jl`. Drives the GUI's ability to
introspect correlation parameters cleanly.

**The problem.** Today, factory closures that need geometry capture it at
construction time as separate kwargs:
- `laminar_friction(aspect_ratio)`
- `elenbaas_htc(; b, L, Dh, g)`
- `fully_developed_laminar_h_spl(; Dh, aspect_ratio)`
- `developing_laminar_h_spl(; Dh, develop_length, aspect_ratio)`
- `regime_dependent(; htc_natural, Dh, g, ...)`

The GUI renders these kwargs as editable fields, even though the parent channel
already has a `PipeGeometry` carrying all those values. Result: duplicate input,
risk of drift between channel.geom and correlation params.

**The convention.** Every correlation factory that needs *any* value from
`PipeGeometry` takes `geom::PipeGeometry` as its first positional argument and
derives what it needs internally. After refactor:

```julia
fric_fn = laminar_friction(geom)
htc_fd  = fully_developed_laminar_h_spl(geom)
htc_dev = developing_laminar_h_spl(geom; develop_length=0.5)
htc_nc  = elenbaas_htc(geom; g=g_acc)
```

**Stateless direct functions stay direct functions** — `dittus_boelter`,
`blasius_friction`, `turbulent_friction`. They have no captured state, don't
need a factory, don't need geom.

**Pure tuning kwargs stay kwargs** — `Re_transition`, `Nu` for
`constant_Nusselt`, `develop_length` for `developing_laminar_h_spl`,
`epsilon` for turbulent friction, `htc_natural` (the inner closure) for
`regime_dependent`.

**`regime_dependent` specifically.** It receives already-constructed closures
(htc_laminar, htc_turbulent, friction_laminar, friction_turbulent, htc_natural),
which themselves have their own geom baked in. But `regime_dependent` itself
performs the `Gr/Re² > 1` calculation and needs `Dh` and `g` for that. Under
the new convention:

```julia
regime_dependent(geom;
    htc_laminar::HTCCorrelation, htc_turbulent::HTCCorrelation,
    friction_laminar::Function, friction_turbulent::Function,
    htc_natural::Union{HTCCorrelation,Nothing}=nothing,
    g=nothing, Re_transition=2300)
```

`geom` is positional first; used internally for the Gr formula. Inner closures
stay as already-constructed.

**Type alias for closure-arg clarity:**

```julia
const HTCCorrelation = Function
```

Used in signatures (`htc_laminar::HTCCorrelation`) to communicate "this expects
an already-built closure, not a factory." Documentation value; not enforcement.

**Hard invariant: nowhere does any factory take `Dh` / `L` / `depth` / `width`
/ `aspect_ratio` as a separate arg.** Only `geom`. If a value is needed, derive
it from `geom` inside the factory.

**Scope.** Real, non-trivial early sub-phase of the GUI redesign milestone.
Not a minor tweak. Even though it touches `src/`, it is correctly part of the
GUI milestone because it is *driven by* GUI requirements.

**Test plan.**
- Port every existing correlation test to the new signature.
- Checklist that no surface API still takes `Dh`/`L`/`depth`/`width` directly.
- Round-trip example re-validation against Python STREAM reference numbers
  (`build_loop_vertical`, `build_loop_transient`, MTR assembly) post-refactor
  to catch any silent semantic drift. The new parity harness in
  `test/data/python_parity_reference.jl` provides this gate.

**Code-gen impact.** The GUI's code generator emits cleaner Julia after this:
correlations are constructed once at the top of the file with their `geom`
reference, channels reference them.

---

### 3.2 Resources Panel and Foreign-Key Model

**The single biggest architectural shift in this milestone.** Components no
longer carry inline value-copies of reusable definitions. They reference
**named, definable, reusable model-level resources** by stable UUID.

**Navigator tree:**

```
Project (root)
├── Model Options                  (singleton — name, fluid, defaults, description)
├── Resources
│   ├── Geometries                 (PipeGeometry instances)
│   ├── Power Shapes               (uniform / z-cosine / file-loaded / leave-unset)
│   └── Fluids                     (placeholder — single light-water for now)
└── Components
    ├── Hydraulic                  (Pump, Channel, ChannelAndContacts, ChannelHeatFlux,
    │                               Friction, Gravity, Resistor, Inertia, HeatExchanger,
    │                               Flapper)
    ├── Thermal                    (HeatDiffusion, ConstantTemperature)
    ├── Sources                    (WallTemperature, HeatFluxSource — value-source
    │                               components binding to channel-level @variables;
    │                               see Section 3.11)
    └── Reactor Physics            (PointKinetics, ReactivityController — when
                                    PK GUI integration lands; see Section 6 parked)
```

Three sibling top-level branches: **Model Options**, **Resources**, **Components**.

- **Model Options** is a singleton — exactly one per model. Click to open editor.
  Holds: project name, description, comments, fluid (currently always water),
  default `g` magnitude, default solver settings.
- **Resources** are user-creatable, multi-instance, *named* entities. **No canvas
  presence** (no ports, not draggable). Selecting one in the navigator opens its
  editor in the same property panel that components use.
- **Components** has four sub-categories: **Hydraulic**, **Thermal**, **Sources**,
  and (eventually) **Reactor Physics**. Each is a toolbox category from which
  the user drags components onto the canvas.

**Storage in `.scp` JSON** (file extension finalized for v1: project file = `.scp`; preset file = `.scpr` — see Section 3.14):

```json
{
  "format_version": "2.0",
  "model_options": { "name": "...", "fluid": "water", "g_default": 9.80665, ... },
  "resources": {
    "geometries":   [ { "uuid": "...", "name": "mtr-channel", "kind": "rectangular", ... } ],
    "power_shapes": [ { "uuid": "...", "name": "cosine-axial", "kind": "z_cosine", ... } ]
  },
  "components": [ { "uuid": "...", "type": "ChannelAndContacts", "geometry_ref": "<uuid>", ... } ],
  "connections": [ ... ],
  "layout": { ... canvas positions, view state ... }
}
```

**Foreign-key references.** Components reference resources by UUID. Display
shows the resource's user-given `name`. Renaming a resource updates everywhere
it's referenced (no broken refs). Copy-paste of a component preserves the
reference (does NOT duplicate the resource).

**Eager-only resource creation.** Confirmed decision: there is no anonymous
inline geometry. To add a Channel, the user must first either pick an existing
Geometry from the dropdown OR create a new Geometry inline via "+ New" (which
creates a named Resource). Workflow: define resources → drag components → wire
them → pick from dropdowns. There is no "promote inline to Resource" — that
state never exists.

**Reference picker UX** in component property panel: when a field expects a
Resource (e.g., Channel's `geometry`), the field renders as:
- Dropdown of available Resources of the right type (showing each resource's `name`)
- "+ New…" button (opens inline mini-editor that creates a new Resource and
  selects it)
- "Edit…" button (jumps to the selected resource in Navigator and focuses its
  panel)

**Power Shapes specifically.** Resource type for HeatDiffusion's `power_shape`
parameter (currently the user references "set in code later"). Variants:
- **Uniform** — equal heating in all cells; one parameter.
- **z-axis cosine** — `uniform_x_power_shape`-style profile from Python STREAM;
  amplitude / peaking factor.
- **File-loaded** — user-supplied file, format TBD during implementation.
- **Leave unset** — code-gen omits it; user fills in `.jl` script after export.

**Fluids.** Right now light water is baked-in everywhere. Slot exists for
multi-fluid expansion (project memory `project_fluids_longterm.md` records the
agreed `AbstractFluid` + multiple-dispatch shape, deferred to v0.6+). A
single-fluid Model Options field is sufficient for now.

**User-defined constants** (e.g., `Q_total = 100kW` referenced from many
components): explicitly **NOT in scope** for v1 of this milestone. Architecture
allows it for free if added later as another Resource type.

**Code-gen change.** Today the GUI inlines `PipeGeometry_rectangular(...)` per
channel. After this, the generated Julia file declares each Resource once at
the top:

```julia
geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.0025, 0.066)
@named cac_1 = ChannelAndContacts(; n=10, geometry=geom_mtr, ...)
@named cac_2 = ChannelAndContacts(; n=10, geometry=geom_mtr, ...)
```

Cleaner output, mirrors how a hand-coder would write it.

**v0.8 file migration.** Dropped — no real `.streamgui` files exist in the
wild, so no migration code needed. New format starts fresh under the new
`.scp` extension.

---

### 3.3 Connection Routing — Autoflip + Asymmetric Placement (FlowPorts)

**The visual problem (verified from screenshots example_1.png through
example_5.png in the conversation):**

1. **Bidirectional pair overlap** — in any closed loop with two components, the
   two edges between them take near-identical wrap paths and look like one
   confused thick line. (`HydraulicEdge.tsx:6` even comments "Bidirectional
   pairs overlap slightly but arrowheads distinguish direction" — known
   concession.)
2. **Vertical-stack cascade** — every forward edge between vertically-adjacent
   components produces a small U-wrap on the right side of the icons because
   port_out is locked right and the next port_in is locked left. Multiple such
   Us pile up in a busy "right-side gutter."
3. **Long-distance return wraps** — return edges in any closed loop have to
   trace a giant rectangle around all components, often crossing over node
   bodies.

The user said #1 is the dominant offender. #2 is a major cascading issue. #3
is tolerable ("you have to close the loop somehow").

**Ground truth from code:**

- Edge type is already `smoothstep` (orthogonal Manhattan with rounded corners)
  — confirmed in `gui/src/components/HydraulicEdge.tsx:19`.
- `port_in` is always on left side, `port_out` always on right side — registry
  defaults in `gui/src/registry/components.json`.
- Under v1.1, `Channel` and `ChannelHeatFlux` have **no thermal ports** (only
  FlowPorts). Only `ChannelAndContacts` has thermal port handles (rendered as
  one logical handle per face, standing for the `[1:n]` array; see Section 3.4).

**The decision: per-port autoflip + asymmetric placement (FlowPorts).**

- Each FlowPort renders as exactly ONE handle (one blue dot for `port_in`, one
  red dot for `port_out`). **Never more than one of each visible.**
- For each port, the autoflip rule picks the side (left / right / top / bottom)
  facing the port's connected neighbor based on the dominant axis (`dx > dy`
  → horizontal, else vertical).
- When both ports of a single component end up flipped to the **same side**
  (e.g., both connect to a neighbor below → both want the bottom edge), they
  use **asymmetric placement**: `port_in` toward the LEFT end of that side,
  `port_out` toward the RIGHT end. This separates them visually.
- Default (no connections yet): registry default position (port_in left,
  port_out right).

**What this fixes:**

- **Example 1 bidirectional overlap** — pump above CAC: pump's both ports flip
  to bottom (port_in bottom-left, port_out bottom-right); CAC's both ports flip
  to top (port_in top-left, port_out top-right). Forward and return edges form
  an X-cross between the two components, not parallel U-shapes. **Major
  improvement** — confused thick line becomes two visibly distinct edges.
- **Examples 3 & 4 vertical-stack cascade** — every forward edge in a vertical
  stack becomes a straight vertical line because port_out flips to bottom of
  upper component and port_in flips to top of lower component. Right-side
  gutter eliminated. The single return edge wraps around the outside cleanly,
  no longer crossing forward edges.
- **Example 2 long-distance return** — diagonal layout: forward edge stays
  short and clean; return edge routes through the diagonal channel between
  the two components rather than wrapping around the canvas border.

**What it doesn't fully fix** (acceptable residuals):

- Example 1's X-cross has both edges pass through nearly the same midpoint.
  If still ugly in practice, add **anti-parallel offset for bidirectional
  pairs** as polish: bow one edge slightly left of the midline, the other
  slightly right, so they cross at a small distance. Custom-edge tweak; not
  architectural.
- Example 2's residual long return is unavoidable topology; user accepts.
- Pure-vertical 2-component bidirectional loops still have the X-cross in
  the gap. Acceptable.

**Per-component rotation (right-click → Rotate 90°)** was considered and
**rejected** because it requires per-component manual action across 10+
components in larger models. Autoflip provides the same effect automatically.
If autoflip turns out in practice to make wrong choices too often, fall back to
per-component rotation as the explicit override. (Backstop, not v1 scope.)

**Multi-side handles (more than one blue or one red dot visible)** were
considered and **rejected**. The user is firm: at most one blue and one red
visible per component.

---

### 3.4 Thermal Port Behavior Under Autoflip (CAC and HeatDiffusion only)

Under v1.1, **only `ChannelAndContacts` and `HeatDiffusion` have ThermalPorts.**
`Channel` and `ChannelHeatFlux` are pure FlowPort components — no thermal
handles render on them. This dramatically simplifies the thermal-port story
compared to the pre-v1.1 world.

Thermal ports differ from flow ports in two key ways that change the rule:

1. **`thermal_left` and `thermal_right` refer to physical faces of the
   component**, not in/out flow direction. They are spatial labels.
2. **They always come as opposing pairs** — never both on the same side of
   the icon. They're physically opposite faces.

**Aggregation: one logical handle per side, standing for the `[1:n]` array.**
CAC's `thermal_left[1:n]` array renders as a single thermal port handle on one
face of the icon; `thermal_right[1:n]` renders as a single handle on the
opposite face. The user draws **one** thermal connection per CAC face —
plate-to-channel coupling for the whole array, not per-cell. Code-gen detects
the topology and emits the appropriate composition helper (`symmetric_plate` /
`plate` / `one_sided_connection` / **`fuel_assembly`** — see Section 3.12). The
v0.8 GUI already does this aggregation; it carries forward unchanged.

**The autoflip rule:**

- The pair `thermal_left` / `thermal_right` always renders on opposite sides
  of the icon.
- The **axis** of the pair (horizontal — left/right — or vertical — top/bottom)
  autoflips based on where the *thermal-connected* neighbors actually are.
- If thermal neighbors favor horizontal axis (`dx > dy` average) →
  `thermal_left` on left edge, `thermal_right` on right edge.
- If favor vertical → `thermal_left` on top, `thermal_right` on bottom.
- No connections yet → registry default (CAC: top/bottom; HD: left/right).

**Asymmetric placement does NOT apply to thermal ports** — they're already on
opposite sides; no need to disambiguate them on the same side.

**Independence from flow ports** on the same component: CAC has both
ThermalPorts and FlowPorts; the two systems autoflip *independently* based on
their own connected neighbors. Standard MTR assembly rendering: hydraulic pump
on left, channel on right → flow ports stay left/right; plates above and below
CAC → thermal ports go top/bottom. Vertical-loop variant: flow ports flip to
top/bottom; if plates are now left/right, thermal ports flip to left/right.

**Edge case:** if both hydraulic AND thermal neighbors favor the same axis on
a single CAC, all four ports want the same two edges. Geometrically
constrained — interleave them along each edge with appropriate spacing, or the
validation framework surfaces it as a "topology hint" suggesting reposition.
Not load-bearing; rare in practice.

**Connection rendering:** one visual edge per logical port-pair regardless of
array length N. Amber color for thermal edges (already in code). Smoothstep
routing. The autoflip just changes *where* edges enter and exit icons,
eliminating L-shape mismatches we have today.

**Visual restyle (planned for the design-system phase, Section 3.8).**
Restyle the thermal port handle from the current yellow rotated diamond to
something cleaner: black / hollow / white-fill circle with chain-link state
overlays (red unfilled = required-but-missing, amber connected = OK). This
applies to all ThermalPort handles uniformly (CAC, HD, ConstantTemperature).
Universal, not variant-specific — Channel and CHF don't have thermal ports
under v1.1 so this only covers the plate-coupling family.

---

### 3.5 Interaction Model — Selection / Pan / Copy-Paste / Edge Deletion

**v0.8 ground truth:** ReactFlow defaults active. Left-click drag on empty
canvas pans; no marquee selection; no copy/paste; multi-select is shift-click
only. (Verified — `CanvasPanel.tsx` does not set `panOnDrag`,
`selectionOnDrag`, or any clipboard handler.) **Edge deletion is also unsupported
in v0.8** (user-list item #2) — fix in scope here.

**The decision:** diagrams.net / drawio convention.

| Action                       | Behavior                                                                  |
|------------------------------|---------------------------------------------------------------------------|
| Left-click empty drag        | Marquee selection rectangle. Selects nodes inside; edges between selected nodes implicitly included. |
| Left-click on node           | Select that node.                                                         |
| Left-click on edge           | Select that edge.                                                         |
| Left-click drag on selected  | Move it (and the rest of the selection if multi-selected).                |
| Shift-click                  | Add / remove from selection.                                              |
| Right-click drag             | Pan canvas.                                                               |
| Right-click no-drag          | Open context menu (ReactFlow distinguishes press-release-no-movement from press-drag-release). |
| Delete / Backspace           | Delete selected nodes AND/OR selected edges.                              |
| Esc                          | Clear selection / cancel current operation.                               |

**Context menu contents:**
- **On node:** Delete, Duplicate, Rename, Show generated Julia code, Show errors for this component (jump to validation panel).
- **On edge:** Delete, Show errors for this connection (if any).
- **On canvas:** Paste, Auto-Layout (future), Add Component › (component submenu).

**Copy / paste / cut / duplicate:**

- **Ctrl+C** — serialize selected nodes + edges to a JSON clipboard payload.
  Internal edges (both endpoints selected) included; external edges (one
  endpoint outside the selection) dropped.
- **Ctrl+V** — deserialize, mint new UUIDs for all pasted nodes and edges,
  place them at offset (+20px, +20px) from originals, select the pasted set.
  Multi-paste in succession increments offset further so they don't pile up.
- **Ctrl+X** — copy + delete.
- **Ctrl+D** — duplicate selection in place (= copy + paste at offset, single
  shortcut).
- **Resource references preserved verbatim.** Pasting a Channel that references
  a `mtr-channel` Geometry produces a new Channel pointing to the *same*
  Geometry resource UUID. Pasting components never duplicates Resources.

**Naming scheme on paste — smart-parse-and-increment:**

Single rule, two cases:

1. **Name ends in `_<digits>`** → increment the trailing number, find next free.
   - `pump_1` → `pump_2` (or `pump_3` if `_2` is taken)
   - `top_pump_1` → `top_pump_2`
2. **Name does not end in `_<digits>`** → append `_2`, then `_3`, etc.
   - `top_pump` → `top_pump_2` → `top_pump_3` …
   - `heated_channel` → `heated_channel_2`
   - `pump` → `pump_2`

**"Next free" semantics throughout.** If `pump_1` and `pump_3` exist but `pump_2`
doesn't, copying `pump_1` produces `pump_2` (lowest free, not "next after
highest"). Same rule applies to fresh toolbox drops: drop a Pump → name is
`pump_<lowest-free-integer>` across all components matching `pump_<digits>`.
Renaming `pump_1` to `top_pump` frees the `pump_1` slot.

**Multi-component paste:** each component named independently by the rule.
`[top_pump, heated_channel]` → `[top_pump_2, heated_channel_2]`. Internal
connections rewired to the new IDs.

**Edge case acceptable as noise:** `pump_v2` ends in digits, so the rule
produces `pump_v3`. If user meant "v2" as a literal label rather than
versioning, they can rename inline. All other rules have worse failure modes.

**All produced names are valid Julia identifiers** — no spaces, parens, hyphens.
Survives code-gen unchanged.

**Reset-to-empty rule (user-list item #4 — unifies field reset behavior):**

- A field that is **empty initially** is fine — the registry default (or a
  sensible computed default) is used, and code-gen omits the kwarg.
- When a user has *typed* a value and then clears it, the field returns to that
  same empty state (default applied, no error).
- The "required" error only fires if a field has *no usable default* AND is
  empty.
- Applies uniformly across all property fields and all BC-tab fields.

---

### 3.6 Custom Titlebar

**Why:** OS chrome (minimize/maximize/close) varies between Windows / Linux /
WSL / macOS — on WSLg it's outright ugly. Removing OS chrome and rendering a
custom titlebar is the only way to get cross-platform consistency.

**How (Tauri 2):**

- Set `decorations: false` in `tauri.conf.json` for the window.
- Implement a thin (~32-36px tall) horizontal HTML strip at the top of the app.
- Mark the empty area with `data-tauri-drag-region` so dragging it moves the window.
- Wire custom buttons to `getCurrentWindow().minimize() / .toggleMaximize() / .close()`
  from `@tauri-apps/api/window`.
- Double-click on drag region toggles maximize (one event handler).
- Edge-resize keeps working — the OS handles that even with decorations off.

**Layout (the strip, left to right):**

| Region | Contents |
|--------|----------|
| Left   | App icon + current project name + small dot (●) if there are unsaved changes + integrated File / Edit / View / Help menubar |
| Center | Empty (no command palette trigger here — the palette is Ctrl+P-only) |
| Right  | Min / Max-Restore / Close window-control buttons, custom-styled to match the app theme (light/dark aware), with proper hover states |

**File menu integrated into the titlebar** rather than below it, to save
vertical space (canvas is the main work area). Hamburger-menu Notion-style
rejected because the user wants menus exposed and findable, not hidden behind
discovery-poor affordances.

**Reference apps for style:** Linear, VS Code, Discord, Notion all use this
pattern. The visual style is layered on top per the design-system contract
(Section 3.8); the structural decision is settled here.

---

### 3.7 Command Palette — Jump-Only

**Scope: only the jump-to-component-by-name flavor.** Full
VS-Code-style action invocation explicitly **out of scope** for v1. May expand
later as polish.

**Rationale.** The user's tool is "basic-shaped" — most actions live on visible
affordances (toolbox, menus, buttons). Command palette as action-invocation
adds discovery cost without much speed payoff. But once a model has 10+
components with meaningful names like `top_pump`, `decay_loop_inlet`,
`heated_channel`, finding a specific node visually on the canvas gets slow.
Type-to-jump is the killer use case here.

**UX:**

- **Trigger:** `Ctrl+P`.
- **Input:** fuzzy search.
- **Search pool:** all component instance names + all Resource names
  (Geometries / Power Shapes / Fluids / Model Options children).
- **Result rendering:** shows kind icon + name + (for components) the
  component type label.
- **Action on selection:**
  - For a **component**: canvas pans / zooms to focus it and selects it;
    property panel auto-populates.
  - For a **Resource**: Navigator opens to that resource's category and
    selects the entry; property panel populates.
  - For **Model Options**: opens the Model Options editor.

**Out of scope:** action invocation ("Add Pump", "Save", "Toggle theme"), file
search, recent-projects search, fuzzy search across help docs. May come back
as a later polish iteration; not required for v1.

---

### 3.8 Design System / Interaction Contract

**Reframing.** The user's polish goal is not "look like Linear / Figma /
Notion." It is: *intentional design, smooth workflow, predictable layout
after learning the tool.* Visual style is layered on top of consistency rules.
The rules are the load-bearing decision; the visual style is the surface.

**The guiding principle (from Section 2):** *Professional engineering software,
not consumer-SaaS playground.* Reduce decorative chrome, increase information
density, show numerical values inline where relevant, muted/deliberate color,
tighter typography, fixed-location status surfaces. The user explicitly named
the existing v0.8 look as feeling "amateur playbox" — the design-system phase
must move it toward "nuclear thermohydraulic design tool."

**This is its own dedicated phase, not a polish-as-you-go mixed into feature
phases.** Rationale: trying to graft "make it polished" onto feature phases is
exactly what produces the never-finishes-being-polished problem the user is
trying to escape. By committing to a design contract document first and
auditing every panel against it later, polish becomes a *derivable* property,
not a never-ending touch-up cycle.

**Phase shape:** two sub-deliverables.

1. **The contract document** — write down the rules below in a binding format.
2. **Audit-and-apply pass** — walk every existing panel and feature surface
   against the contract; fix what doesn't match.

**The rules** (initial set; expand during the contract phase):

**Spatial consistency:**
- Every panel has a fixed home: titlebar top, navigator left, canvas center,
  properties right, code preview / message log bottom.
- Splits between panels are user-resizable.
- Panels are NOT user-reorderable (no dragging the navigator to the right side).
- Layout splits persist across sessions per project.

**Interaction consistency:**
- Right-click *always* opens a context menu (never sometimes); right-click drag
  always pans (per Section 3.5).
- Left-click *always* selects; left-click drag on selected always moves; on
  empty always starts marquee.
- The same shortcut does the same thing in every panel.
- `Esc` always cancels the current operation (drag, marquee, dialog, palette).
- `Enter` confirms; `Space` does not have a global meaning (avoid hidden
  meanings).

**Feedback consistency:**
- Every action has visible state. Selection rings on selected things; hover
  bg-shifts on interactive elements; dirty dot in titlebar when unsaved;
  validation errors shown both on the offending node (red ring) AND in a
  fixed status location (validation panel).
- No silent state changes. No background mutations the user doesn't see
  reflected somewhere.

**Predictable defaults:**
- Drop a component, it appears at cursor or canvas center (not random).
- Paste appears offset from original (not on top of original).
- Save warns about overwrites.
- Undo unwinds *everything* mutable.
- Themes apply without FOUC (already handled in v0.8).
- Files saved with explicit Ctrl+S; never silent auto-save without warning.

**Visual restraint applied consistently:**
- One type scale (e.g., 12 / 14 / 16 / 20 px) — do not introduce new sizes.
- One spacing unit (8px grid) for all margins / padding / gaps.
- Restricted accent palette: blue = Hydraulic, amber = Thermal (already in
  v0.8 — keep this discipline rigorously). New: a third accent for
  Sources/BCs and a fourth for Reactor Physics, picked during contract
  drafting; total accent palette ≤ 4 colors plus neutrals.
- One shadow vocabulary — subtle for depth (modals, popovers); none gratuitous.
- One border-radius scale.
- One font family with deliberate weight variation.

**Density expectations (the "professional engineering tool" feel):**
- Components on the canvas display key parameter values inline as a thin
  secondary line under the instance name (e.g., `n=10  Dh=2.5mm  L=600mm`).
- BC values surfaced inline as small badges on the component when set inline
  (not buried behind a tab click) — see Section 3.11.
- Validation state (warnings, errors, BC-missing markers) visible at a glance.
- Status bar at canvas bottom or in the titlebar shows: model dirty state,
  active layers, current selection summary, validation summary.

**Visual style (the surface, picked AFTER the rules above are committed):**
- User reaction to references: Linear too minimal in places; Notion OK; Figma
  nice; Tableau meh; Vercel dashboard unrelated.
- Likely landing zone: Figma-leaning curves + Linear-leaning density discipline
  + an engineering-tool seriousness inflection (sharper edges, denser layout
  than consumer SaaS).
- Specific font / color / shadow choices: TBD during contract phase.

**Validation framework's visual execution is a HARD requirement** under this
contract — clean placement, intentional design, recognizable error language.
(User: "we HAVE to land this very clean cut and clear. It HAS to look good.")

---

### 3.9 Validation Framework

**One unified, rule-pluggable framework** for everything introspectable that's
physically or structurally wrong with a STREAM model.

**Architecture:**

- **Validator registry** — each rule is a pluggable validator object
  implementing a uniform interface (name, severity, applicable scope, run
  function returning `ValidationResult`s).
- **Rules run continuously** — on any mutation that could affect them
  (component param edit, connection add/remove, resource change). Cached;
  re-run only what's affected.
- **`ValidationResult` shape:** target component(s) UUIDs (for marker placement
  and click-to-focus), severity (error / warning / info), description, optional
  fix action with kind (lossless-sync / value-transfer-picker /
  navigation-only).

**Severity taxonomy (from user-list "validation tab" bullet, refined):**

- **Error** — will produce broken Julia code or a guaranteed solver failure
  (missing required parameters, missing required connections, port type
  mismatch at connection time, unclosed flow loops in steady-state mode,
  cell-count or length mismatch on thermal connection, n-mismatch on
  WallTemperature/HeatFluxSource binding). **Gates code-gen export** —
  cannot export while any error is unresolved.
- **Warning** — technically allowed; possibly unintended; doesn't break the
  generated code. Examples: missing optional connections (h on Channel left as
  default 0 → adiabatic), gravity-sum-per-loop nonzero, dangling FlowPort
  with no connection (sometimes intentional for partial models).
- **Info** — informational hints, not problems (e.g., "this Channel has no
  thermal BC set — adiabatic per default").

**The UX (uniform across every rule):**

- **Validation panel** — fixed location at the bottom of the GUI (per Section 3.8
  spatial consistency). Lists all current `ValidationResult`s grouped or sorted
  by severity.
- **Each entry** has:
  - Icon for severity (error / warning / info).
  - Description: human-readable, names the components and the offending values.
  - **Click on entry** → the affected components on the canvas get highlighted
    (pulse / focus-ring), canvas pans to bring them into view.
  - **Action button** (if a fix is mechanically possible):
    - **Lossless sync** (one-click): instant apply. E.g., "Sync nz to plate (5)".
    - **Value-transfer picker** (small popover dialog): "Use plate's 0.5 / Use
      channel's 0.6 / Cancel". E.g., for length mismatches.
    - **Navigation-only** (no mechanical fix): just "Go to component" — the user
      decides the fix.
- **Red-ring marker on offending nodes** — the same `errorNodeIds` mechanism
  that v0.8's `StreamNode.tsx` already wires (`gui/src/components/StreamNode.tsx:33,57`).
  Red ring on canvas → user clicks → validation panel scrolls to and highlights
  the corresponding entry.
- **Right-click on a component** → context menu offers "Show errors for this
  component" → scrolls validation panel to entries involving it. Power-user
  shortcut, not the primary fix path.

**Lossless vs. value-transfer fix UX — important nuance.** Two flavors of "sync"
because two flavors of mismatch:

- **Lossless** (e.g., `z_N` between plate and channel cell-count, `n` between
  WallTemperature and Channel): the discretization can be changed without
  changing the physics meaningfully. One-click button picks the connected
  component's value and applies it.
- **Value-transfer** (e.g., `Length` between plate.Lz and channel.geom.L):
  changing length makes the component physically different. The GUI cannot
  guess which side the user actually meant. A small picker popover surfaces
  both values and the user picks. Never auto-applied.

**The fix action lives ONLY on the validation panel entry.** Not on a field's
right-click menu (too hidden); not on inline buttons next to fields (clutters
every form); not on right-click of the component on the canvas as the primary
path (couples disparate fixes together). Validation panel is THE place; canvas
red rings and right-click "show errors" are navigation aids that lead the user
there. This keeps the action UX uniform across all rules.

**Initial rule set** (expand during the framework phase):

- **z_N match** between thermally-connected `ChannelAndContacts.n` and
  `HeatDiffusion.nz` — error; lossless-sync fix.
- **Length match** between thermally-connected `cac.geom.L` and `plate.Lz` —
  error; value-transfer-picker fix.
- **n match** between a value-source (`WallTemperature`, `HeatFluxSource`) and
  its target `Channel` / `ChannelHeatFlux` — error; lossless-sync fix (same
  shape and UI as z_N — "same error, identical treatment").
- **Port type match** at connection time (FlowPort↔FlowPort, ThermalPort↔
  ThermalPort) — already in v0.8 as a hard block at connection time; preserve
  that hard-block behavior. **Generalize to all type-checked connections** —
  including BC bindings (`WallTemperature.T_wall_out → Channel.T_wall_*` is
  allowed; `WallTemperature.T_wall_out → ChannelHeatFlux.q_*` is hard-blocked
  at connection time).
- **Missing required connections — ALL types, not just flow** (user-list item
  #5). Examples: `ChannelAndContacts` thermal_left/right that should connect to
  a plate (warning if unconnected — adiabatic by default); a Channel whose
  T_wall_left/right aren't bound to anything (warning — silent default of 0K
  is almost certainly wrong).
- **Dangling FlowPort** — a hydraulic component with an unconnected port_in or
  port_out. Probably a *warning*, not an error — sometimes intentional for
  partially-built models.
- **Loop closure** — does the hydraulic graph form closed loops? Open loops
  are an error for steady-state, sometimes intentional for transients with a
  source/sink. Probably a warning + tag, not a blocker.
- **Gravity sum per closed loop** — extension of the existing
  `check_gravity_mismatch`: each closed loop's signed `g × L` contributions
  should sum to zero. Per-loop check, more precise than the current coarse one.
- **Geometry consistency across shared thermal coupling** — if two channels
  both thermally connect to the same plate, do their geometries agree on what
  must agree (probably only `L`)? Per-channel `Dh` can legitimately differ.

**Validation framework verdict per `ValidationResult` also gates code-gen
export** when severity is `error`. v0.8 already does this for FlowPort type
mismatches; generalize.

**Connection-time blocking vs warning:** decision for the framework — most
rules should *warn at connection time* (allow connection, show in panel) rather
than *hard-block* (refuse). Hard-block is reserved for invariants that
absolutely cannot produce a meaningful model (port type mismatch, BC binding
type mismatch). Cell-count / length / n-match mismatches are warnings — the
user might be in mid-edit and will fix the numbers; soft-warning is the right
UX as confirmed by the user.

**Note on user-list item conflict.** The user-list bullet about "strictly
forbid connecting thermals when length and N don't match... shake the port,
red notification" is **explicitly superseded** by the soft-warn approach
above. The list bullet was reconsidered in conversation; recorded here so
future readers see the decision and rationale. Hard-block would be wrong —
mid-edit iteration is the dominant workflow.

---

### 3.10 Channel Variants — Direction A (Three Explicit Components)

**Decision: keep the three channel variants (`Channel`, `ChannelHeatFlux`,
`ChannelAndContacts`) as three explicit, separately-draggable toolbox
components. No merge into a single ambiguous "Channel."** Visual uniformity is
achieved naturally under v1.1 (because Channel and CHF have no thermal ports,
they render visually identically) — not via GUI gymnastics like ghost ports or
mode-switching.

**Why three explicit, not merged:**

- **Power-user freedom.** A user who knows they're building a CAC-coupled
  fuel-plate assembly drags `ChannelAndContacts` directly. No mode-switch
  required. (User: "if you already know what you want to do, you are not
  allowed to just drag a CAC and set its properties" was the strongest
  argument against merge.)
- **Direct mapping to source.** The three variants have genuinely different
  MTK structure under v1.1 (different external-input variables, different
  port shape, different equations). Merging in the GUI would be a leaky
  abstraction at code-gen time.
- **Visual uniformity is automatic under v1.1.** Channel and CHF render
  identically (only FlowPorts) because they really *are* visually equivalent
  at the canvas level. No special handling needed. CAC has additional
  thermal ports because it physically has them — and that's the only
  configuration that connects to plates.

**Rejected alternatives (recorded so they're not relitigated):**

- **Direction I (full merge into one ambiguous "Channel"):** rejected. Mode
  determined by BC type (T+h → Channel; q → CHF; ThermalPort connection →
  CAC). Issues: mode change silently invalidates connections; leaky
  abstraction at code-gen; restricts power-user freedom.
- **Direction II (three explicit but with a "ghost" thermal port on CHF for
  visual symmetry with Channel):** rejected. Was a workaround for the
  pre-v1.1 inconsistency where Channel had a thermal port and CHF didn't.
  Under v1.1, *neither* has a thermal port, so the asymmetry no longer
  exists. No ghost port needed.

**Properties tab vs BCs tab — separation rule (a clean invariant under v1.1):**

- **Properties tab** holds *constructor arguments* of the component
  (`n`, `geometry`, `g`, `htc_correlation`, `friction_correlation`, `h_left`,
  `h_right`, `scb_correction`, etc.). These are how the component is
  constructed; they don't change at runtime once `mtkcompile` has run.
- **BCs tab** holds *external-input variables* that the component declares but
  doesn't close internally — `T_wall_left[1:n]` / `T_wall_right[1:n]` for
  `Channel`, `q_left[1:n]` / `q_right[1:n]` for `ChannelHeatFlux`. These are
  unknowns the user *must* close, either via direct value entry, a profile,
  an "import," a "mark-in-code," or a connection to a value-source block (see
  Section 3.11).

So:
- `h_left` / `h_right` for `Channel` = **Properties tab** (kwarg, not external
  input).
- `T_wall_*` for `Channel` = **BCs tab** (unbound `@variables`).
- `q_*` for `CHF` = **BCs tab** (unbound `@variables`).
- `CAC` has **no BCs tab** — its wall conditions come exclusively via the
  ThermalPort connections to a Plate. Its property panel only has the
  Properties tab.

This separation is a hard rule across all components. If a component has
external-input variables, the property panel shows two tabs. If it doesn't,
only Properties.

---

### 3.11 Boundary Conditions — Tab and Value-Source Components

Two equivalent paths for closing the external-input variables on `Channel`
and `ChannelHeatFlux`. Both produce the same code-gen output (Style 1 vs
Style 2 from `src/components/channels.jl` docstring); user picks per-instance
which is more convenient.

**Path A — BCs tab in the property panel (the default for simple cases).**

Selected in property panel for `Channel` or `CHF`. Shows fields for each
external-input variable (Channel: `T_wall_left`, `T_wall_right`; CHF:
`q_left`, `q_right`). Each field has a **mode picker** + per-mode editor:

| Mode             | Editor                                                              | Code-gen result                                                     |
|------------------|---------------------------------------------------------------------|---------------------------------------------------------------------|
| **Value**        | Single scalar input (`Real`).                                       | `[ch.T_wall_left[i] ~ <value> for i in 1:n]...`                     |
| **Profile**      | Picker for preset profile (e.g., axial cosine) + parameters; OR import a vector from a file. | `[ch.T_wall_left[i] ~ <profile_expr_at_i> for i in 1:n]...`         |
| **Function**     | Reference a callable parameter for time-varying BC.                | Channel constructed with callable-parameter pattern.                |
| **Mark in code** | No editor; a comment is emitted at the appropriate place in the generated `.jl`. | `# TODO: set ch.T_wall_left[i] here` (or similar). User edits manually. |
| **Driven by source block** | Dropdown of available `WallTemperature` / `HeatFluxSource` blocks on the canvas; selecting one creates the canvas connection (Path B). | `[ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...` |

The "Driven by source block" mode is the bidirectional bridge between the BCs
tab and the canvas — see below.

**Path B — Drag a value-source component onto the canvas.**

`WallTemperature` and `HeatFluxSource` are first-class components in the
`Sources` toolbox category (Section 3.2 navigator tree). They were introduced
by the v1.1 channels-redesign in `src/components/sources.jl` and exist as
canonical "value source" blocks for closing channel external-input variables.

**Their source signatures** (from PR #15 docstrings):
```julia
WallTemperature(; n, T_wall=<scalar | vector | function>) -> ODESystem  # exposes T_wall_out[1:n]
HeatFluxSource(;   n, q=<scalar | vector | function>)     -> ODESystem  # exposes q_out[1:n]
```

**GUI rendering:**

- Each value-source component is a small block on the canvas with **one
  output port** (a distinct visual idiom — neither blue/red FlowPort nor
  amber ThermalPort; proposed: a hollow square or open-chevron in a neutral
  color, or the new accent color for the Sources/BCs layer per Section 3.8).
- `WallTemperature` outputs `T_wall_out[1:n]` (single logical handle for the
  array); `HeatFluxSource` outputs `q_out[1:n]`.
- The block itself displays its current value or profile reference (e.g.,
  `T_wall = 320 K` or `T_wall = cosine_profile(amplitude=20)`).

**Connection mechanism — the "BC connection":**

- **Channel and CHF have NO permanent BC-inlet handle on the canvas.** They
  remain visually clean (only FlowPorts visible).
- The user **drags from the value-source's output handle onto the Channel /
  CHF block body** (anywhere on it, not requiring a specific target handle).
  The GUI creates the binding.
- The connection renders with a **distinct edge style** — dashed line, neutral
  color, clearly differentiable from solid blue (flow), amber (thermal), and
  any other edge type. (Final stroke specifics during design-system phase.)
- Each BC connection has a **target-side property** — `:left`, `:right`, or
  `:both`. Default on creation: `:both`. User changes via the connection's
  right-click menu or a small inline label on the edge ("L", "R", "L+R").
  For asymmetric (different left and right BCs), use two value-source blocks,
  connect each to its target side.
- **Bidirectional sync between BCs tab and canvas connection.** Setting the
  BC tab field's mode to "Driven by source block: `wt_1`" creates the canvas
  edge automatically. Deleting the canvas edge reverts the BC tab to its
  prior mode (or back to default if none). Two views of the same fact, never
  out of sync.

**Type-checking at connection time (hard-block, like FlowPort↔ThermalPort):**

- `WallTemperature.T_wall_out → Channel.T_wall_*` — allowed.
- `HeatFluxSource.q_out → ChannelHeatFlux.q_*` — allowed.
- `WallTemperature.T_wall_out → ChannelHeatFlux.q_*` — **hard-blocked at
  connection time** (different units, different physical quantity). Tooltip
  explains.
- `HeatFluxSource.q_out → Channel.T_wall_*` — same hard-block.
- `WallTemperature.T_wall_out → ChannelAndContacts.<anything>` — hard-blocked
  (CAC takes thermal port connections, not BC bindings).
- `WallTemperature` does NOT carry `h_left` / `h_right` for Channel — those
  are kwargs (Properties tab), not external-input variables. Only T_wall is
  bindable.

**`n`-match validation (Section 3.9 rule):** WallTemperature.n and the target
Channel.n must match. Mismatch → soft warning with lossless-sync action
button on the validation entry: "Sync n: WallTemperature → 10." Same UI shape
as the z_N rule; "same error, identical treatment."

---

### 3.12 `fuel_assembly` Composition Helper

**New codebase helper** introduced as part of the GUI redesign milestone
(driven by GUI requirements: code-gen needs to detect alternating CAC↔Plate
chains and emit the appropriate helper instead of N hand-rolled connect()
calls). Lives in `src/composition/helpers.jl` alongside `symmetric_plate`,
`plate`, `one_sided_connection`, `compose_systems`.

**Why:** reactor fuel assemblies are *exactly* alternating fuel plates and
coolant channels. Current helpers handle 1-CAC + 1-plate cases (`symmetric_plate`),
2-CACs + 1-plate (`plate`), and 1-CAC + 1-plate one-sided (`one_sided_connection`).
A multi-element chain is hand-rolled today. `fuel_assembly` closes that gap
in one helper that handles all four chain variants.

**Name:** `fuel_assembly`. Domain-honest. ("rod" is taken in nuclear engineering
for cylindrical fuel rods which are different geometry; "chain" is generic and
loses spatial intuition; "stack" is overloaded.)

**The four variants:**

```
Variant 1 (channel-bookended, +1 channel):
  [adiabatic] CAC1 ↔ Plate1 ↔ CAC2 ↔ Plate2 ↔ ... ↔ Platek ↔ CAC(k+1) [adiabatic]
  k plates, k+1 channels

Variant 2 (plate-bookended, +1 plate):
  [adiabatic] Plate1 ↔ CAC1 ↔ Plate2 ↔ ... ↔ CACk ↔ Plate(k+1) [adiabatic]
  k+1 plates, k channels

Variant 3 (mixed-bookended, equal counts):
  Plate1 ↔ CAC1 ↔ Plate2 ↔ CAC2 ↔ ... ↔ Platek ↔ CACk
  k plates, k channels (or the reverse)

Variant 4 (closed annular loop):
  CAC1 ↔ Plate1 ↔ CAC2 ↔ Plate2 ↔ ... ↔ CACk ↔ Platek ↔ CAC1 (wraps)
  k plates, k channels, ring topology
```

**Helper signature** (rough — final shape during planning):

```julia
fuel_assembly(channels::Vector{<:CAC}, plates::Vector{<:HD};
              bookend = :auto,    # :channel | :plate | :mixed — inferred from lengths
              closed = false,     # true → variant 4
              name::Symbol)
```

`fuel_assembly` walks the alternation pattern and emits the per-cell
`connect(port(...), port(...))` chain that `plate(...)` does for each adjacent
CAC↔Plate↔CAC triplet, plus the wrap-around connections in the closed case.

**GUI side — code-gen detection.** Extends the existing topology-detection
ruleset:

- 1 CAC + 1 plate, both faces of plate connected to same CAC → `symmetric_plate`
- 2 CACs + 1 plate, one face each → `plate`
- 1 CAC + 1 plate, only one face connected → `one_sided_connection`
- **Alternating CAC↔Plate↔CAC↔Plate sequence of length ≥ 3 (or ≥ 2 in the
  closed case)** → `fuel_assembly`. Detect the variant from endpoint types
  (CAC-bookended / Plate-bookended / mixed) and the wraparound check (closed
  if first and last share a thermal connection).
- Anything that doesn't match a helper pattern → fall back to direct
  `connect()` calls per cell.

**Implementation work:**
- New helper in `src/composition/helpers.jl` with all four variants — small,
  self-contained code change.
- Tests: parity against hand-rolled `connect()` chain for each variant; round-trip
  example against Python STREAM if Python has the analog.
- Code-gen detection update in the GUI.

**Scope.** Phase 1.5 of the GUI redesign milestone — small helper-only sub-phase
sequenced after the correlation refactor (Phase 1) and before the bulk of GUI
work, ~100 lines of helper + tests + code-gen update.

---

### 3.13 Layers System

**Existing v0.8 ground truth.** `gui/src/lib/layers.ts` and `StreamNode.tsx`:
three modes (All / Hydraulic / Thermal). Off-layer components and edges dim to
opacity 0.2 (don't disappear). For dual-layer components (CAC has both flow and
thermal ports), only the off-layer port handles dim. Edge classification is by
stroke color (amber = thermal, gray-ish = flow). Toggle is a control somewhere
in the chrome.

**The redesign — independent toggles, four layers, professional placement:**

**Four-layer taxonomy:**

| Layer            | Components                                                                          | Connection types                                |
|------------------|-------------------------------------------------------------------------------------|-------------------------------------------------|
| **Hydraulic**    | Pump, Channel, ChannelHeatFlux, ChannelAndContacts, Friction, Gravity, Resistor, Inertia, HeatExchanger, Flapper | FlowPort↔FlowPort                               |
| **Thermal**      | HeatDiffusion, ConstantTemperature; ChannelAndContacts (its thermal-port half)    | ThermalPort↔ThermalPort                         |
| **Sources / BCs**| WallTemperature, HeatFluxSource                                                     | BC binding (`T_wall_out → T_wall_*`, `q_out → q_*`) — dashed edge style |
| **Reactor Physics** | PointKinetics, ReactivityController (when PK GUI integration lands; see Section 6) | PK→HD `power` binding; temperature feedback bindings |

**Principle: layer = mechanism, not category.** Port-based connections (Flow,
Thermal) get their own layers; equation-binding connections (Sources/BCs,
Reactor Physics power & feedback) get their own layers. ConstantTemperature
lives in Thermal because it has a real ThermalPort (port-based), not in Sources
(which is for equation-binding sources).

**Independent checkbox toggles (not mode picker).** Four checkboxes — Hydraulic,
Thermal, Sources, Reactor Physics. User can show any combination simultaneously.
The "All" mode is just "all four checked" (it's not a separate fifth mode).

**UI placement: floating "Layers" chip pinned to the top-right of the canvas.**
Click to expand into a small popover with four checkboxes + the hide/dim
preference (see below). Always reachable, never blocks the canvas, scales
naturally if more layers get added later. (Two alternatives — navigator
"Visibility" section, status-bar bottom toggle — were considered and rejected;
the floating chip best matches the "professional tool" framing.)

The chip itself acts as a persistent **layer-state indicator**: four small
color squares (matching the layer accent colors), lit when the layer is
active, dim when hidden. This gives an at-a-glance reminder of which layers
are visible without committing to canvas-wide background tinting.

**Hide-vs-dim setting (in app Settings).**

- Toggle: *"Off-layer items: dim (default) / hide."*
- **Dim** (default) preserves spatial awareness — you see where things are
  even when not actively editing them. Opacity 0.2, current behavior.
- **Hide** removes them entirely from the canvas for fully decluttered views.
- User flips between the two via Settings; per-project preference, persisted.

**Off-layer items are LOCKED — non-interactive.** Whether dimmed or hidden,
off-layer components/edges/handles are not clickable, not selectable, not
draggable, not connectable, not editable. Prevents accidental edits. The
"All" mode (all checkboxes checked) remains the universal-edit fallback.

**Layer-aware connect tool — non-clunky implementation.** Off-layer ports
show as visually inert (no hover highlight, no snap-target indicator) when
the connect tool is active and the target layer is hidden. **The GUI does
not block** the user from connecting cross-layer; if the user *insists* on
dragging a connection onto an off-layer port, the connection is allowed and
the GUI auto-enables the relevant layer toggle so the user can see the result.
Forgiving, never fights the user.

**Rejected ideas (recorded so they're not relitigated):**

- **Canvas-wide background tint per active layer.** With multiple layers
  active simultaneously (independent checkboxes), tint blending across two
  or three colors gets murky fast — especially in dark mode. Rejected as
  "easy to do badly." The layer-state indicator on the chip itself replaces
  this need.
- **Component layer-membership badges in All mode** (small color dots next
  to component labels indicating "this is hydraulic" / "this is thermal" /
  etc.). Rejected as visual clutter. Existing left-border accent stripe and
  port colors already convey layer membership without extra badges.

---

### 3.14 Projects and Presets — File Format and Identity

Two distinct file kinds in the GUI:

- **Project (`.scp`)** — the existing concept under a new short extension. Holds
  the full model: components, connections, resources, model options, layout.
  Loaded to work on; exports to a Julia `.jl` file. Stored as JSON in the shape
  described in Section 3.2.
- **Preset (`.scpr`)** — a reusable sub-graph of components + their
  connections + parameter values + the resources they reference. Slimmed-down
  version of the `.scp` format (no project-level metadata; the resources the
  preset references are embedded in the preset file). Loaded into projects as
  copy-paste templates.

**Preset identity model: NONE (Option 1 — no identity, copy-paste templates).**

Settled after discussion in GitHub issue #14 ("Projects and preset identity in
the GUI"). esheder's concerns about elevating GUI files to sources of truth
(auto-conversion pressure, manual `.jl` edit divergence, sharing with hand-written
Julia) are legitimate. The clean resolution: separate "productivity within the
GUI" from "canonicality for the executable model." The Julia file stays
canonical for the executable. Presets are GUI-internal productivity templates.

Concrete behavior:
- Loading a preset into a project is **copy-paste with smart-name handling**
  (per the Section 3.5 naming rule). After load, the link to the preset file
  is gone.
- Updates to a preset file **do not propagate** to existing project
  instantiations. If the user wants the update, they re-load the preset
  (creating a new instance; the old one stays untouched).
- Preset files are check-in-able to git, shareable, editable as starting
  points — but they are **not source of truth for anything executable**.
- Resource handling on preset load: if the preset references a `mtr-channel`
  Geometry that doesn't exist in the target project, **auto-create it from
  the preset's embedded copy** (smart-name-increment if a same-name resource
  already exists). User can manually merge duplicate Resources after load if
  they want.
- "Save selection as preset…" right-click action on a multi-component
  selection + `File → Save selection as preset…` menu entry.
- "Load preset…" via `File → Load preset…` plus a **Presets category in the
  toolbox** showing the user's saved presets as drag-from-toolbox entries.
  Latter is the better UX (drag-to-canvas placement) and fits the existing
  toolbox metaphor.

**Door open to identity later (Option 3 — passive identity), forward-compatibly.**

If real usage shows users maintaining libraries of presets across many
projects and getting frustrated by manual update churn, identity can be
bolted on later by adding a UUID + version field to the preset file. Existing
identity-less presets stay treated as no-identity templates (backwards
compatible). Not v1; not preemptive; "wait for the pain" call.

**Rejected alternatives** (recorded so they're not relitigated):
- **Full identity (Option 2)**: changes to preset file auto-propagate
  everywhere. Causes the very pressures esheder flagged.
- **Passive identity (Option 3) in v1**: defensible but premature. We don't
  have evidence of the workflow that justifies the complexity.

**Scope.** New Phase 7.5 (Presets and templates), sequenced late in the
milestone — after the validation framework (Phase 8) but before the
design-system audit (Phase 9). Self-contained; doesn't block anything else.
Could even be deferred to a v2 of the milestone if scope pressure mounts.

**Preset file format storage:**

```json
{
  "format_version": "1.0",
  "kind": "preset",
  "name": "mtr-fuel-assembly",
  "description": "Single MTR fuel plate flanked by two CAC channels",
  "resources": { /* embedded copies of referenced resources */ },
  "components": [ /* the components in the preset */ ],
  "connections": [ /* the internal connections */ ],
  "layout": { /* relative canvas positions of the components */ }
}
```

On load, components and connections are mint-new-UUID'd and placed at the
cursor / drop location (with the preset's relative layout preserved).
Embedded resources are auto-created in the target project with smart-name
collision handling. The preset file itself is left untouched.

---

## 4. Cross-Cutting Invariants

Hard rules that span multiple decision areas. **Enforced everywhere; do not
violate without explicit user instruction.**

- **One blue dot per component, one red dot per component.** Never multiple
  visible FlowPort handles. (Re Section 3.3.)
- **Channel and ChannelHeatFlux render with no thermal ports** under v1.1.
  Their wall conditions are external-input `@variables`, not ports. (Re
  Section 1, Section 3.4.)
- **Only `ChannelAndContacts` ever connects to `HeatDiffusion`.** Channel and
  CHF never do. (Re Section 1, source code architectural invariant.)
- **One logical thermal handle per CAC face**, standing for the `[1:n]`
  array. The user draws one connection per face; code-gen detects topology and
  emits the appropriate composition helper. (Re Section 3.4.)
- **No anonymous Geometry.** Every component that needs a `PipeGeometry`
  references a named Resource by UUID. (Re Section 3.2.)
- **No `Dh` / `L` / `depth` / `width` / `aspect_ratio` passed independently
  from `geom`.** Only `geom`, derive from it. (Re Section 3.1.)
- **Properties tab vs BCs tab separation rule.** Properties tab = constructor
  kwargs. BCs tab = external-input `@variables`. h_left/h_right for Channel
  → Properties; T_wall_* for Channel → BCs; q_* for CHF → BCs; CAC has no
  BCs tab. (Re Section 3.10.)
- **BC connections render with a distinct dashed edge style** — neither blue
  (flow), amber (thermal), nor any port-based connection style. (Re Section 3.11.)
- **Thermal port pair always on opposing sides of the icon.** Never both on
  the same side. Only applies to CAC and HD under v1.1. (Re Section 3.4.)
- **All fix actions live on validation panel entries.** Not on field
  right-clicks or component right-clicks (those are navigation aids only).
  (Re Section 3.9.)
- **All Julia identifiers produced by the GUI are ASCII-only and valid.**
  No Unicode, no spaces, no parens, no hyphens. (Re Section 3.5; existing
  project rule.)
- **Layout (canvas positions) is persisted separately from semantic data**
  in the save file. Layout-only edits don't dirty the simulation-relevant
  diff. (Re Section 3.2 storage shape.)
- **Off-layer items are non-interactive.** Whether dimmed or hidden. The
  "All" layer mode (all four checkboxes checked) is the universal-edit
  fallback. (Re Section 3.13.)
- **Reset-to-empty rule.** Empty initially is fine (registry default).
  Typed-then-cleared returns to default. "Required" error fires only when
  there's no usable default AND the field is empty. (Re Section 3.5.)
- **Presets are copy-paste templates with no identity** in v1. Loading a
  preset breaks the link to its source file. Updates don't propagate.
  Embedded resources auto-create on load with smart-name collision handling.
  (Re Section 3.14.)
- **File extensions** are `.scp` for projects and `.scpr` for presets. No
  long-form extensions in v1.

---

## 5. Proposed Phase Decomposition

Rough plan for the GUI redesign milestone, dependency-ordered. Subject to
modification once the user's pending list items are walked through.

| #    | Phase                                            | Scope summary                                                                                  | Depends on |
|------|--------------------------------------------------|------------------------------------------------------------------------------------------------|------------|
| 0    | **v1.1 channels-redesign merge to main**         | PR #15 lands; not part of this milestone but unblocks everything below. Already FF-mergeable.  | —          |
| 1    | Correlation `geom`-first refactor                | `src/physical_models/`; signature normalization; tests + Python parity re-run.                 | 0          |
| 1.5  | `fuel_assembly` composition helper               | New helper in `src/composition/helpers.jl` with 4 variants; tests; code-gen detection update.  | 0, 1       |
| 1.6  | Registry audit + rewrite for v1.1                | `gui/src/registry/components.json` rewrite against v1.1 source; add `WallTemperature` / `HeatFluxSource` / `PointKinetics` / `ReactivityController` entries; collapse correlation sub-param trees per geom-first; add `scope` field per param to support Properties-tab vs BCs-tab split; bump `stream_version` to 1.1.0. | 0, 1.5     |
| 2    | Resources panel architecture                     | Navigator restructure; foreign-key model; save format (`.scp`); reference picker UX; Sources category. | 1.6        |
| 2.5  | BCs tab + value-source components in GUI         | BCs tab UX (5 modes); WallTemperature/HeatFluxSource toolbox entries; dashed BC edge style; bidirectional sync between BCs tab and canvas. | 2          |
| 3    | Connection routing                               | FlowPort autoflip + asymmetric placement; ThermalPort axis-flip for CAC/HD; anti-parallel offset polish (later). | 0, 2       |
| 4    | Interaction model overhaul                       | Marquee select, right-pan, copy/paste with smart-name, edge deletion, context menus, reset-to-empty rule. | —          |
| 5    | Custom titlebar                                  | Tauri config + HTML titlebar component + integrated File menu.                                 | —          |
| 6    | Layers system overhaul                           | 4-layer taxonomy; independent checkboxes; floating Layers chip top-right; hide/dim setting; off-layer locked; non-clunky layer-aware connect. | 2          |
| 7    | Command palette (jump-only)                      | Ctrl+P fuzzy search across instance + resource names; focus-on-canvas / focus-in-navigator.    | 2          |
| 7.5  | Presets and templates                            | `.scpr` file format; Save-selection-as-preset; Load-preset; Presets toolbox category; auto-resource-create on load. No identity (Option 1 per issue #14). | 2          |
| 8    | Validation framework                             | Pluggable validator registry; uniform panel UX with severity + click-to-focus + action buttons; initial rule set; red-ring markers; n/z_N/length sync actions; gates code-gen export. | 2; visually governed by 9 |
| 9    | Design system / interaction contract             | Write rules document + audit-and-apply pass over every existing panel. Establishes the "professional engineering tool" surface; commits visual-style decisions; restyles thermal port handles + introduces accent for Sources/BCs and Reactor Physics. Also delivers: tooltip system (item 1), settings dialog + canvas cheatsheet (item 3), AutoRecover (item 4 — though strictly Phase 4-adjacent), code-tab rework (item 5 — Phase 4.5 actually). | 1–8 functional surfaces in place |

Dependency notes:
- (0) is the unblocker — v1.1 channels-redesign must merge before any phase
  here can start, since the architecture assumed throughout depends on it.
- (1) is independent codebase work after (0); runs in parallel to anything
  else in the GUI.
- (1.5) extends (1) with the new `fuel_assembly` helper. Small.
- (2) is foundational for the GUI side of the milestone.
- (2.5) extends (2) with the Sources / BC connection surface.
- (3, 4, 5, 6, 7) are largely independent of each other once (2) is in place.
- (6) needs (2) for the Sources layer to make sense.
- (7) needs (2) for the resource search pool.
- (8) can be built in parallel to (9); its visual surface is governed by (9)'s
  contract.
- (9) needs all functional surfaces in place before its audit pass; the
  contract document itself can be drafted in parallel to (1)–(8).

---

## 6. Parked / Future Items

Tracked here so they're not lost; not in v1 milestone scope.

- **Reverse import** — load an existing hand-written STREAM.jl script and
  parse it into the GUI's model representation so the user can edit it
  visually. Inherently fuzzy (input not in any expected format), best-effort,
  no 100% target. Trigger: after the GUI's model is stable enough that there's
  a clear schema to parse INTO; probably post-milestone, possibly v3.
- **Per-component rotation (right-click → Rotate 90°)** — backstop in case
  autoflip turns out in practice to make wrong choices too often. Not v1.
- **Anti-parallel offset for bidirectional pairs** — small custom-edge tweak
  if the X-cross from autoflip still looks busy in practice. Polish, not
  architectural.
- **Command palette extension to action invocation** (full VS-Code-style) —
  later polish if jump-only proves insufficient.
- **User-defined constants** as a Resource type (e.g., `Q_total = 100kW`) —
  architecture supports it for free; not v1.
- **Multi-fluid support** — slot exists in Model Options + Resources; activate
  when heavy water (or other non-water) becomes a project requirement.
- **Pluto notebook export** of a model — SNAP analog: "Model Notebooks." Not
  v1 of the GUI; later milestone.
- **Parametric sweep as a first-class object** — design-for-it but don't
  build-it in v1.
- **3D visualization** — explicitly skipped; 2D canvas with autoflip is
  sufficient.
- **Drill-down (embedded sub-views) for compose_systems** — architectural
  slot exists implicitly; not v1.
- **Run code through GUI + result analysis** (user-list bullet) — explicitly
  future per user wording: "Later when the code is fully trusted to actually
  work and stable, we should revisit." Includes plotting (1D + pcolormesh +
  thermal-map heatmap of channels+plates with correct sizes), generic axis
  selection from MTKSolution unknowns + observables.
- **Point Kinetics GUI integration** (user-list bullet) — the Reactor
  Physics layer is reserved for it (Section 3.13), but full integration
  waits until PK is reworked and has a final I/O. Not v1.
- **Repo split (STREAM.jl source vs STREAM.jl GUI)** — user-list bullet.
  Major infrastructure question (two repos? one repo internally split?
  GSD workflow implications?). Deferred — proceed in current monorepo for
  now; revisit once milestone scope is clearer.
- **Channel-multiplicity ×N (`signify`)** — user-list item #1. Confirmed as
  the Python STREAM `signify` pattern: KCL-only weighting, thermal equations
  unchanged. **Codebase work** is required first (`replicate(ch, N)` helper +
  weighted-edge KCL handling); **GUI work** is the ×N badge consumer of that
  feature. Codebase work is *not* GUI work and is tracked as a separate
  parked item; GUI badge is added once the codebase feature lands.

---

## 7. Open Threads / TBD (from user's pending list, still to walk through)

Items from `.planning/notes/gui-redesign-user-list.md` that have not yet been
discussed in detail. To be processed one at a time, each one updating the
relevant section above.

- **On-hover component description tooltips** (user-list bullet). Tooltip
  panel with delay-on-hover; possibly scrollable; covers what the component
  is, what it expects, what its parameters mean.
- **Thermal port visual restyle** (user-list bullet). Black/no-fill or
  white-fill circles + chain-link state icons (red/orange/green for
  required-missing / optional-missing / connected). Already partially folded
  into Section 3.4 visual-restyle note; details and exact icon vocabulary
  to be settled during design-system phase (Section 3.8).
- **Settings tab revamp + canvas cheatsheet** (user-list bullet). "Appliance
  manual" dummy-component legend showing all possible visual elements with
  numbered legend / annotations. Lives in Settings or as a help-overlay.
- **Snap-to-grid toggle** (user-list bullet). Reasonable step sizes; toggle
  in Settings or as a canvas-control button.
- **Code-tab rework** (user-list bullet). Export button in code-tab window
  (and in File menu); copy-to-clipboard button; section blocks with
  hover/click → highlight source on canvas; possibly script formatting rules.
- **Defaults audit** (user-list item #3). Generic registry-wide audit of
  parameter defaults and presence — hunt for missing or wrong defaults
  across all component types. Needs a list of specific examples or a
  systematic walkthrough.
- ~~**Import subsystems from `.streamgui` files** (user-list item #7).~~
  **Resolved** as the Presets mechanism — see Section 3.14. The `.scpr` preset
  file IS the import-subsystem mechanism. Loading a preset is copy-paste with
  smart-name handling; no identity, no propagation, no source-of-truth claim.
- **"More info per screen" general layout reconsideration** (user-list
  bullet). Increase information density per the "professional engineering
  tool" framing. Folded into Section 3.8 (Design system) as a binding
  expectation; specific layout changes during the contract phase.
- **Boundary-condition visual representation on canvas** (user-list bullet
  + item #6). Small badge on the component when BC is set inline; dashed
  edge from value-source block when set via Path B. Folded into Section 3.11.

---

## 8. Conversation Lineage

- **Workflow invoked:** `/gsd:explore` (Socratic ideation routing per
  `.claude/get-shit-done/workflows/explore.md`).
- **Date started:** 2026-05-10.
- **Initial topic provided by user:** "GUI for STREAM.jl. We already have an
  implementation down and decisions taken, but we can raise the ground up
  and redo stuff if needed - all in order to get the best, most full result
  possible. Note that we did research on a similar code (SNAP) and the
  reports exist in .planning/."
- **SNAP source documents referenced:**
  - `snap-docs-extraction.md` (108-page RELAP5 Plug-in User Manual extraction)
  - `snap-report-extraction.md` (76-page CAFEAN Preprocessor API Main Report
    extraction, NUREG/CR-6974)
  - `snap-gui-analysis.md` (consolidated analysis cross-walking SNAP features
    to STREAM.jl applicability)
  - The user noted these moved location during a mid-session PC migration; their
    OneDrive copies remain authoritative.
- **Screenshots referenced** (in user's `~/screenshots/`):
  - `example_1.png`, `example_2.png` — closed-loop bidirectional overlap and
    diagonal long-wrap.
  - `example_3.png`, `example_4.png` — vertical-stack 4-component cascade.
  - `example_5.png` — mixed horizontal-vertical 4-component layout.
- **v1.1 channels-redesign reference** (referenced mid-conversation, drives
  Sections 1, 3.4, 3.10, 3.11):
  - Branch: `channels-redesign`. Currently 1 commit ahead of `origin/main`,
    FF-mergeable. PR #15.
  - Headline commit: `cd3a073` — "feat(v1.1): final channel-family redesign +
    Python STREAM parity harness." Phases 52–58 + Phase 56-resume.
  - Headline source file: `src/components/channels.jl` (consolidated; replaces
    old `channel.jl` + `thermal_channel.jl`).
  - Architectural invariant codified in docstring: only `ChannelAndContacts`
    ever connects to `HeatDiffusion`.
- **User's input list:** `.planning/notes/gui-redesign-user-list.md` —
  numbered fixes (1–7) followed by bullet points covering features / notes /
  bugs / overlooks. Items are walked through one by one and absorbed into
  this document.
- **Mid-session PC migration:** The session was paused, packaged for transfer,
  and resumed on a different PC with different absolute paths
  (`/home/itay/projects/Julia-STREAM/` instead of
  `/home/itayb/projects/STREAM.jl/`). Decisions and content are preserved;
  any path strings in this document are relative or have been updated to the
  new layout.
- **Prior project memory of relevance:**
  - `project_gui_redesign.md` — established that a dedicated GUI redesign
    phase was planned; current UI works but looks bad; visual polish deferred
    until after functional phases.
  - `project_signify_channel_multiplicity.md` — confirms KCL-only weighting
    semantics for channel multiplicity ×N (Section 6 parked item).
  - `feedback_channel_hd_connection_rule.md` — *only ChannelAndContacts
    connects to HeatDiffusion*. Reinforced by v1.1 architecture.
  - `feedback_design_validation_rigor.md` — run rigorous parity checks before
    declaring viability; relevant to the correlation refactor's parity-vs-Python
    re-validation requirement.
  - `feedback_separate_inertia_from_idiom.md` — engage with new design from
    first principles, do not anchor on inertia.
  - `feedback_no_execute_without_confirmation.md` — read and reason during
    planning; do not spawn executors mid-discussion.

---

*End of working draft. This document grows as the conversation continues.
Last meaningful update: 2026-05-10 — full pass absorbing the user-list items
discussed so far (BC/value-source story, channel variant decision (Direction A),
fuel_assembly helper, layers system, validation framework expansion,
"professional engineering tool" framing, properties-tab vs BCs-tab rule,
reset-to-empty rule, edge deletion, Sources toolbox category, v1.1 channels-redesign
integration). Next expected updates: walk through remaining list items in
Section 7 (on-hover tooltips, settings/cheatsheet, code-tab rework, snap-to-grid,
defaults audit, import-subsystems, etc.).*
