---
phase: 62
slug: resources-panel-architecture
status: approved
shadcn_initialized: true
preset: existing (style=new-york, baseColor=zinc, cssVariables=true, iconLibrary=lucide)
created: 2026-05-13
reviewed_at: 2026-05-13
---

# Phase 62 — UI Design Contract

> Visual and interaction contract for the Resources Panel Architecture phase.
> Pre-populated from `62-CONTEXT.md` D-01..D-30 + CD-01..CD-05, `62-RESEARCH.md`,
> `.planning/notes/gui-redesign-design-decisions.md` §3.2/§3.5/§3.8/§3.14/§4,
> and the existing GUI surface scouted in `gui/src/`. The §3.8 commitment
> *engineering tool, not consumer-SaaS playground* is the load-bearing
> aesthetic constraint — visual restraint outranks polish.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | shadcn (already initialized — `gui/components.json` present) |
| Preset | style=`new-york`, baseColor=`zinc`, cssVariables=true, rsc=false, tsx=true |
| Component library | Radix UI primitives (`radix-ui@1.4.3` aggregator) wrapped under `gui/src/components/ui/` |
| Icon library | lucide-react (already used: `Info` in `PipeGeometryPicker.tsx`, etc.) |
| Font | system font stack from `gui/src/index.css:122` — `-apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif`. **No new font.** |
| CSS framework | Tailwind v4 (`@tailwindcss/vite@4.2.2`) with `tw-animate-css` for shadcn animations |
| Theme | `:root` (light) + `.dark` (One Dark Pro inspired) — both already defined in `index.css`. New panel surfaces inherit existing tokens. |

**New shadcn primitives to add (shim only, no npm install — Radix transitively present):**

| File (new) | Wraps | Why |
|-----------|-------|-----|
| `gui/src/components/ui/popover.tsx` | `@radix-ui/react-popover@1.1.15` | Anchored `+ New…` popover (D-15) |
| `gui/src/components/ui/context-menu.tsx` | `@radix-ui/react-context-menu@2.2.16` | Per-row Resources context menu (D-03) |

**Already in `gui/src/components/ui/`** (do NOT reinvent): `tabs.tsx`, `scroll-area.tsx`, `badge.tsx`, `separator.tsx`, `button.tsx`, `input.tsx`, `label.tsx`, `select.tsx`, `tooltip.tsx`, `dropdown-menu.tsx`, `alert-dialog.tsx`.

---

## Spacing Scale

The codebase has already converged on an 8-point scale expressed as
inline pixel values (`p-[16px]`, `mt-[24px]`, `gap-[8px]`, etc.) in
`SidebarPanel.tsx` and the sidebar primitives. Phase 62 reuses these
tokens verbatim — do not introduce new multiples.

| Token | Value | Phase 62 usage |
|-------|-------|----------------|
| xs    | 4px   | Icon ↔ label gap inside `Label` (matches `PipeGeometryPicker.tsx:57` `gap-1`); resource-row tight internal padding |
| sm    | 8px   | Resource-row vertical padding; gap between dropdown ↔ `+ New…` ↔ `Edit…`; tree-row icon ↔ name; popover internal field gaps (`gap-[8px]`) |
| md    | 16px  | Panel padding (`p-[16px]` — already used in `SidebarPanel.tsx:30`); group-header bottom margin; popover total padding; tree group header → first row gap |
| lg    | 24px  | Section breaks inside the right Properties panel (matches `mt-[24px]` and `my-[24px]` in `SidebarPanel.tsx:91, 101`); spacing between resource groups in the tree |
| xl    | 32px  | Top padding of panel content (`pt-[32px]` in `SidebarPanel.tsx:30`); between "No selection" prompt header and body |
| 2xl   | 48px  | Reserved for v1.2 design-system phase (Phase 72) — not used in 62 |

**Tab strip height (NEW for this phase):** 36px fixed height for the
`[Components] [Resources] [Project]` tab strip. Rationale: matches Radix
`Tabs.List` defaults in shadcn `new-york` style and aligns with the
existing 36px-equivalent rhythm in `Toolbar.tsx`. Tab triggers use
horizontal padding `px-[12px]` (between sm and md) — text-only triggers,
no icons (visual restraint per §3.8).

**Popover surface (NEW for this phase):** fixed width `280px` (D-17 +
RESEARCH §Pattern 2). Inner padding `16px`. Inner field gap `8px`.
Bottom action row gap `8px` between Cancel and Create.

**Resources tree row height:** 28px target (matches the dense
`text-[13px]` cadence; no padding above/below — only horizontal
`px-[8px]`). Rationale: matches `ToolboxPanel` `space-y-0.5` density
(`ToolboxPanel.tsx:40`); engineering-tool restraint per §3.8.

**Exceptions:** None. Reuse only.

---

## Typography

The codebase already converged on a four-size scale with two weights.
Phase 62 reuses these verbatim. Surveyed values in `gui/src/components/sidebar/*.tsx`:

| Role | Size | Weight | Line height | Phase 62 usage |
|------|------|--------|-------------|----------------|
| Caption / group header | 12px (`text-xs`) | 600 semibold | tight (default ~1.4) | `Hydraulic` / `Thermal` / `Sources` toolbox group headers (matches existing `ToolboxPanel.tsx:37` `text-xs font-semibold uppercase tracking-wide text-muted-foreground`); **Geometries / Power Shapes / Fluids** group headers in Resources tab use the **same** treatment for consistency |
| Body / label | 13px (`text-[13px]`) | 600 semibold | 1.4 (`leading-[1.4]`) | Form-field labels (matches `Label` treatment in `InstanceNameField.tsx:38`, `PipeGeometryPicker.tsx:57`, `NumericField.tsx:40`); resource-row name in the tree (regular 400 weight when not selected, 600 when selected — see Color); tab-trigger text (`Components` / `Resources` / `Project`) at 600 weight |
| Body — secondary | 14px (`text-[14px]`) | 400 regular | default ~1.5 | `SidebarPanel.tsx:35, 38` "No selection" prompt body; empty-state placeholder copy (italic — see Copy contract); error messages (text-destructive variant) |
| Section heading | 16px (`text-[16px]`) | 600 semibold | 1.3 (`leading-[1.3]`) | Right-panel header (matches `SidebarPanel.tsx:31, 63, 87`); Resource editor heading inside the popover and inside the right panel (`Geometry: <name>` / `Power Shape: <name>` / `Project Options`) |

**Tabular note.** The Resources tree row name is **13px regular** when
not selected and **13px semibold** when selected. Selection emphasis is
weight + background, never color hue (per §3.8 muted/deliberate-color
discipline).

**Inline-rename input (F2 / double-click).** Reuses `Input` primitive
from `gui/src/components/ui/input.tsx`, sized at 13px to match the
row text — but constrained to the row height so the swap is in-place
(no layout shift). Red `border-destructive` on collision (matches
`PipeGeometryPicker.tsx:76` pattern); error message rendered as a
sibling tooltip via `tooltip.tsx`, NOT a modal.

**No new sizes, no new weights** introduced in this phase. (§3.8
explicitly: "One type scale (e.g., 12 / 14 / 16 / 20 px) — do not
introduce new sizes." Phase 62 lands at 12 / 13 / 14 / 16 — already the
established scale; the 13px row is the existing engineering-density
specialization.)

---

## Color

The codebase already uses an OKLCH-based zinc neutral palette with two
locked accents. Phase 62 introduces ZERO new color tokens.

| Role | Value (CSS var) | Usage in Phase 62 |
|------|-----------------|--------------------|
| Dominant (60%) | `--background` (`oklch(1 0 0)` light / `oklch(0.24 0.012 254)` dark) | Canvas surface, left + right panel bodies, popover surface |
| Secondary (30%) | `--card` / `--sidebar` / `--secondary` / `--muted` | Tab strip background; resource-row hover bg (use `--muted`); tree-row selected bg (use `--secondary` — already the convention in `select.tsx` and `dropdown-menu.tsx`); inline-rename input bg (`--input`); separator (`--border`) |
| Accent (10%) | `--primary` (zinc-black light / warm-grey dark from `--foreground`) | **Reserved for:** (a) active-tab underline / bottom-border on the selected tab in the tab strip — 2px solid `--primary`; (b) `+ New…` button primary variant when the field is focused; (c) `Create` button primary variant inside the popover. **Not used** for resource-row selection (that's a `--secondary` bg, see above) — selection emphasis is achieved via weight + bg, not accent color, per §3.8. |
| Destructive | `--destructive` (`oklch(0.577 0.245 27.325)` light / `oklch(0.704 0.191 22.216)` dark) | Inline-rename collision border; Delete row's text + icon inside the context menu (`destructive` variant); error message text below a field |
| Hydraulic accent (existing, frozen) | `#3b82f6` blue-500 (`StreamNode.tsx:12`) | NOT touched in Phase 62 — used by canvas nodes only |
| Thermal accent (existing, frozen) | `#f59e0b` amber-500 (`StreamNode.tsx:13`) | NOT touched in Phase 62 — used by canvas nodes only |

**Accent reserved for:** (1) active-tab indicator underline; (2) primary
button variant on `+ New…`, `Create`, `Save Project`; (3) right-panel
header text when a resource is selected (keep at `--foreground` —
semantic weight comes from the *content* `Geometry: <name>`, not the
hue). Explicitly **not** used for hover states, dropdown chevrons, focus
rings (Radix uses `--ring`, already defined), or tree-row selection bg.

**Popover surface uses `--popover` / `--popover-foreground`** (already
defined in both themes; OKLCH lightness slightly above background for
"floating" feel without a shadow — minimal-shadow vocabulary per §3.8).

**Sources category header** (D-30): same `text-muted-foreground`
treatment as Hydraulic / Thermal group headers. **No new accent color**
for Sources in Phase 62. (§3.8 reserves a future third accent for
Sources/BCs but explicitly defers it to Phase 72 contract drafting —
"picked during contract drafting; total accent palette ≤ 4 colors plus
neutrals." Phase 62 does not introduce that color.)

**Hover state for resource rows:** `bg-muted` (existing token). No
animation/transition — instant swap. (Visual restraint per §3.8: "no
animated chrome.")

---

## Copywriting Contract

All strings below are LOCKED for Phase 62. The executor copies these
verbatim. Strings flagged `[USER-FACING]` must NOT be paraphrased or
translated. Strings flagged `[CODE]` flow into Julia codegen and must
stay ASCII (no smart quotes, no em-dash — use plain hyphens).

### Tab strip labels

| Element | Copy | Notes |
|---------|------|-------|
| Tab 1 (default) | `Components` | Mirrors existing `ToolboxPanel.tsx:33` `<h2>Components</h2>` heading |
| Tab 2 | `Resources` | Singular `Resource` for context-menu items; plural `Resources` for the tab + tree |
| Tab 3 | `Project` | Singular — there is only one project per model |

### Resources tab — group headers

| Element | Copy |
|---------|------|
| Group header 1 | `GEOMETRIES` (uppercase, matches `ToolboxPanel.tsx:37` `uppercase tracking-wide` treatment) |
| Group header 2 | `POWER SHAPES` |
| Group header 3 | `FLUIDS` |
| Group `+` button | aria-label `Add geometry` / `Add power shape` / `Add fluid` (Fluids `+` is disabled for v1 — see disabled-state below) |

### Resources tab — top search

| Element | Copy |
|---------|------|
| Search placeholder | `Search resources…` (with U+2026 ellipsis to match existing convention; this is a placeholder string, not a Julia identifier — Unicode allowed here) |

### Resources tab — per-row context menu (order locked)

| Order | Label | Notes |
|-------|-------|-------|
| 1 | `Rename` | Activates the inline-rename input on the same row (same as F2 / double-click) |
| 2 | `Duplicate` | Smart-name-increment per kind; new row appears immediately below; auto-selected |
| 3 | `Delete` | `destructive` variant; opens existing `alert-dialog.tsx` if the resource has any usages; deletes immediately with no confirm if usage count is 0 |
| 4 | `Show usages` | Renders a small popover list of consuming component instance names; click an entry = canvas selects that node (see "Show usages" UX below) |

### Resources tab — empty group placeholder

When a group has zero rows (e.g., brand-new project, no geometries yet):

| Element | Copy |
|---------|------|
| Empty group body | `(none yet — click +)` |
| Style | 12px `text-[12px]` italic `text-muted-foreground`, indented one row-padding-unit (`pl-[8px]`); single line; not interactive |

### Fluids placeholder row (D-03 + project memory `project_fluids_longterm.md`)

| Element | Copy |
|---------|------|
| Single non-editable row | `light_water` |
| Disabled hover affordance | none — row is rendered with `text-muted-foreground` and no hover bg shift; context-menu and rename suppressed |
| Group `+` button | disabled (`disabled` attribute on the button); tooltip on hover: `Multi-fluid support is planned for a future release.` |

### Reference picker (dropdown — appears on every Resource-typed field)

The picker renders for `geometry_ref` and `power_shape_ref` fields per
Phase 61 registry. Layout: `[ dropdown ............. ] [ + New… ] [ Edit… ]`
on a single row. Dropdown uses `select.tsx` (existing); buttons use
`button.tsx` with `variant="outline"` `size="sm"`.

| Element | Copy |
|---------|------|
| `+ New…` button | `+ New…` (literal — plus sign then space then `New` then U+2026 ellipsis) |
| `Edit…` button | `Edit…` |
| Dropdown placeholder when zero resources of that kind exist | `No geometries yet — click + New… or open the Resources tab.` (geometries case) / `No power shapes yet — click + New… or open the Resources tab.` (power shapes case) [USER-FACING] |
| Empty-state style | 14px `text-[14px]` italic `text-muted-foreground`; rendered inside the `select.tsx` trigger as the placeholder text; **single line, no wrap, ellipsis on overflow** (`truncate`) |
| `Edit…` disabled tooltip | `Select a resource to edit it.` |

**Power Shape picker — extra fixed top entry (D-26):**

| Position | Copy | Notes |
|----------|------|-------|
| Always first in the dropdown, above user resources | `(leave unset — fill in code)` | Italic in the listbox; selectable; persists as the chosen value (sentinel UUID `00000000-0000-0000-0000-000000000000` per RESEARCH §"Alternatives Considered") |
| Separator | (Radix `Select.Separator`) | Below the sentinel, above the user's named power shapes |

### `+ New…` popover (anchored, NOT modal — D-15/D-16)

Popover header (16px semibold):

| Resource kind | Header copy |
|---------------|-------------|
| Geometry | `New Geometry` |
| Power Shape | `New Power Shape` |

Popover body fields:

| Field | Label | Notes |
|-------|-------|-------|
| Name | `Name` | Pre-filled with smart-increment per D-19 (`geometry_1` / `power_shape_1`, etc.); user can edit; validated against per-kind uniqueness + Julia-identifier ASCII rule on submit |
| Kind (Geometry only) | `Kind` | `circular` / `rectangular` toggle group; reuses existing `toggle-group.tsx` |
| Kind (Power Shape only) | `Kind` | `uniform` / `z_cosine` / `file_loaded` `select.tsx`; `unset` is **not** offered here (selection-only via the picker top entry) |
| Geometry circular fields | `L` (Length, m) / `D` (Inner diameter, m) | Reuses `NumericField` primitive (existing) |
| Geometry rectangular fields | `L` (Length, m) / `W` (Width, m) / `H` (Height, m) | Same |
| Power Shape z_cosine fields | `Amplitude` (Real, default 1.0) | `NumericField` |
| Power Shape file_loaded fields | `Path` (relative to .scp) + `Browse…` button | Path is read-only display; `Browse…` opens Tauri file dialog; on dialog return, the absolute path is converted to relative (per RESEARCH Pitfall 5) |
| Action row — primary | `Create` | `button.tsx` default variant; submits the form |
| Action row — secondary | `Cancel` | `button.tsx` `variant="outline"` |

Validation messages inside the popover:

| Condition | Copy | Style |
|-----------|------|-------|
| Name collides with existing of same kind | `A geometry named <X> already exists.` (or `power shape`) | 12px destructive text below the Name field; Name field gets `border-destructive` |
| Name has invalid Julia identifier chars (non-ASCII, starts with digit, contains hyphen/space) | `Use ASCII letters, digits, and underscores; must not start with a digit.` | Same style |
| Numeric field below zero or empty | (reuse existing `NumericField` error rendering) | — |
| `file_loaded` path not found | `File not found: <path>` | Destructive text below Browse row |

### Right Properties panel — header text (D-06)

Locked one-to-one mapping. The header is a single 16px semibold line
(matches `SidebarPanel.tsx:31` treatment):

| Selection scope | Header copy | Notes |
|-----------------|-------------|-------|
| Component (canvas node) | `Properties` | Unchanged from today |
| Geometry resource | `Geometry: <name>` | `<name>` is the literal resource name; the colon + name pattern is borrowed from VS Code's tab-title convention |
| Power Shape resource | `Power Shape: <name>` | Same |
| Project tab active (no other selection) | (panel shows no-selection prompt — see below) | Per D-04, the Project tab body IS the form; the right panel is unused while editing Project |
| No selection | `Properties` + `No selection` body | Unchanged from `SidebarPanel.tsx:31-44` |

### Right Properties panel — no-selection body

Unchanged from today. Locking the strings:

| Element | Copy |
|---------|------|
| Body heading | `No selection` |
| Body description | `Select a component on the canvas to view its properties.` |
| New variant when Resources tab is active and no resource is selected | `Select a resource on the left to edit it.` |
| New variant when Project tab is active | (panel hidden / shows `No selection` — D-04 is no-op) |

### Sources toolbox category header (D-30)

| Element | Copy |
|---------|------|
| Group header | `SOURCES` |
| Empty body | (no body; the group header is rendered as a heading with no rows underneath) |
| Tooltip on hover of the empty header | none (per D-30 "no inert affordances"; do not invite the user to click) |

### Destructive confirmations (Delete row)

| Trigger | Copy |
|---------|------|
| Delete a resource with 0 usages | (no confirmation — immediate delete, undoable via Ctrl+Z) |
| Delete a resource with 1+ usages | `Delete <kind> <name>? It is used by <N> component(s).` with action buttons `Delete anyway` (destructive) / `Cancel` |
| Confirmation primitive | Reuses existing `gui/src/components/UnsavedChangesDialog.tsx` shape adapted into the resource-delete branch, OR a fresh `alert-dialog.tsx` instance — executor picks; either is in shadcn surface today |

### `Edit…` jump return — no breadcrumb

Per D-18, no "Back to <component>" UI is added. The right panel header
text `Geometry: <name>` is itself the orientation cue. Clicking the
canvas node returns. Locked by §3.8 "no decorative chrome."

### Esc precedence (interaction contract, see Interaction section below)

The Esc key cascade has documented precedence. No copy needed — this is
captured under Interaction contracts.

---

## Interaction Contracts

This section pins the non-copy interaction rules. Each row is a contract
the executor implements and the auditor verifies.

### Tab strip (`[Components] [Resources] [Project]`)

| Contract | Behavior | Source |
|----------|----------|--------|
| Default tab on cold start / new project | `Components` | D-01 |
| Persistence | Active tab written to `.scp` `layout.active_left_tab`; restored on load; defaults to `"Components"` if missing | D-08 |
| Keyboard accelerator | `Ctrl+1` → Components; `Ctrl+2` → Resources; `Ctrl+3` → Project | D-07 |
| `preventDefault()` on accelerator | Required — must suppress browser tab-switch / number-row default | D-07 + browser-collision avoidance |
| Focus management on tab switch | Focus moves to the **tab trigger** (not into the tab body). Tab key from a focused trigger advances focus into the panel content. Mirrors Radix `Tabs` default keyboard model — no custom override. | RESEARCH §"Don't Hand-Roll" |
| Visual treatment of active tab | 2px bottom border (`border-b-2`) in `--primary`; inactive tabs have `border-b-2 border-transparent`. Text color shifts from `text-muted-foreground` (inactive) to `text-foreground` (active). No bg pill, no shadow. | §3.8 visual restraint |
| Hover treatment | Inactive tab triggers get a 1px `border-b-muted` on hover. No animation/transition. | §3.8 |
| Disabled state | None of the three tabs is ever disabled. `Project` tab and `Resources` tab are always available even with a fresh project. | D-01 |

### Resources tree (Resources tab body)

| Contract | Behavior | Source |
|----------|----------|--------|
| Tree widget choice | Hand-rolled `<ul>`/`<li>` with `role="tree"` + `role="treeitem"` ARIA. Three top-level group headers, flat list under each. NO `react-arborist`. | CD-01 + RESEARCH §"Alternatives Considered" |
| Group expansion | Always expanded — no collapse affordance in v1 (three groups are always visible). | D-03 |
| `+` button on group header | Trailing right; 16x16 lucide `Plus` icon; `button.tsx` `variant="ghost"` `size="icon"`. Click opens the same `+ New…` popover that the field picker uses, anchored to the `+` button. Newly created resource is appended at the bottom of the group and auto-selected (selection moves to right panel). | D-03, D-15 |
| Row selection | Single-select; selecting a row clears canvas selection (D-05); right panel header becomes `Geometry: <name>` / `Power Shape: <name>`. | D-05/D-06 |
| Row hover | `bg-muted`; cursor `pointer`. No transition. | §3.8 |
| Row selected | `bg-secondary`; text weight 600. | §3.8 |
| Inline rename | F2 OR double-click activates; the row name becomes an `Input` constrained to row height. Enter commits; Esc cancels (reverts to pre-edit name and exits rename mode); click outside the input commits (saves the typed value). Collision shows `border-destructive` + tooltip; collision blocks commit but the user stays in rename mode until they fix or cancel. | D-03 |
| Per-row context menu | Right-click row → Radix `ContextMenu` with order Rename / Duplicate / Delete / Show usages. | D-03 |
| Search box | Top of Resources tab, above the first group. Filters across all three groups by case-insensitive substring match on resource name. Empty groups (post-filter) collapse to a single empty-group placeholder line. Clearing the search restores full view. | D-03 |
| Drag-and-drop reorder | Not in v1. Order is creation-order. | D-03 (silence implies no) |
| Show usages | Click the context-menu item → opens a Radix `Popover` anchored to the row containing a 12px scrollable list of `<component-instance-name>` rows; clicking a list row triggers `selectNode(uuid)` and closes the popover. Popover header: `Used by <N> component(s)`. | D-03 + RESEARCH §Deferred Ideas |

### Reference picker (on Resource-typed component fields)

| Contract | Behavior | Source |
|----------|----------|--------|
| Layout | Single row: `[ dropdown grows-flex ] [ + New… ]  [ Edit… ]` with gap-[8px] | D-14 |
| Dropdown source | All resources of the matching kind, by name (alphabetical NOT enforced; creation order). For Power Shape, sentinel `(leave unset — fill in code)` is the always-present first entry. | D-14, D-26 |
| `+ New…` click | Opens anchored popover (D-15) — see below | D-15 |
| `Edit…` click | If dropdown has a current selection: switch left tab to `Resources`, call `selectResource(<uuid>)`, right panel re-renders as resource editor. If dropdown is on `(leave unset)` for power shape: button is enabled but click is a no-op (sentinel is non-editable). If dropdown is empty: button is disabled. | D-14, D-18 |
| `Edit…` round-trip | One click on the canvas node returns the user to the component's Properties view. No breadcrumb. | D-18 |
| Auto-select after Create | Popover's `Create` action: (1) mints the new Resource via `addResource(...)`, (2) sets the picker's dropdown to the new UUID, (3) closes popover, (4) moves focus to the next focusable element in the parent form (per D-15). | D-15 |
| Empty-state copy | See Copywriting Contract — single italic line in the dropdown placeholder. | D-20 |

### `+ New…` anchored popover

| Contract | Behavior | Source |
|----------|----------|--------|
| Primitive | Radix `Popover` via new `gui/src/components/ui/popover.tsx` shim | CD-02 + RESEARCH §Pattern 2 |
| Anchor | `side="right"` `align="start"` `sideOffset={4}` `collisionPadding={8}` — Radix collision-aware positioning auto-flips to the left when the right panel has no room. Width fixed at `280px` inline. | D-17, RESEARCH §Pattern 2 |
| Click-outside dismiss | **Disabled** via `onInteractOutside={(e) => e.preventDefault()}`. Click-outside does nothing — popover stays open. | D-16 |
| Esc | Closes popover without creating. Triggered by Radix `onEscapeKeyDown`. | D-15 |
| Cancel button | Closes popover without creating. | D-15 |
| Create button (or Enter key on a valid form) | Creates resource → closes → auto-selects → focuses next field. | D-15 |
| Focus return on dismiss | After Cancel / Esc / Create, call `triggerRef.current?.focus()` explicitly to work around Radix issue #646 (preventDefault on `onInteractOutside` cancels the mousedown Radix would use to restore focus). MANDATORY workaround. | RESEARCH §Pitfall 1 |
| Backdrop | None. The popover is borderless-floating with a subtle shadow (`shadow-md` from Tailwind — Radix shadcn default in `popover.tsx`). No darkened backdrop. §3.8: no modal ceremony for small actions. | §3.8, D-15 |
| Visual depth | 1px border `--border` + `shadow-md`; uses `--popover` / `--popover-foreground` tokens. | existing shadcn `new-york` style |

### Right Properties panel router (selection-kind discriminator)

| Contract | Behavior | Source |
|----------|----------|--------|
| Discriminator | A single store-derived value `selectionKind: "component" \| "resource" \| "none"`. Project tab being active is NOT a selection kind — it routes via tab body, not the right panel. | D-05 |
| Mutual exclusivity | Selecting a canvas node clears `selectedResourceId`. Selecting a resource clears `selectedNodeId`. Single-source-of-truth derivation in the store. | D-05 |
| Esc behavior (cascade — precedence locked) | 1. If a popover is open → close popover only. 2. Else if an inline-rename input is active → cancel rename only. 3. Else if a context menu is open → close menu only (Radix handles). 4. Else if `selectionKind != "none"` → clear selection (both `selectedNodeId` and `selectedResourceId`); right panel reverts to no-selection state. 5. Else → no-op. | D-05 + §3.8 "`Esc` always cancels the current operation" |
| Header text per selection kind | See Copywriting Contract above (`Properties` / `Geometry: <name>` / `Power Shape: <name>` / no-selection) | D-06 |
| Refactor shape | The executor MAY refactor `SidebarPanel.tsx` into per-kind sub-components (`ComponentEditor`, `GeometryEditor`, `PowerShapeEditor`) OR keep one file with a single switch on `selectionKind`. Either is acceptable; the **router pattern** is mandatory; the **file layout** is implementation taste. | CD-05 |

### Project tab body (Model Options form — D-04)

| Contract | Behavior | Source |
|----------|----------|--------|
| Body IS the form | No inner selection step. The Project tab content area renders the Model Options form directly. | D-04 |
| Right panel state while Project tab is active | Right panel shows the no-selection prompt (with the variant copy `Select a resource on the left to edit it.` only if the user came from Resources; otherwise the standard `No selection` body). The Model Options form is NOT rendered in the right panel. | D-04 |
| Fields | `Name` (Input), `Description` (Textarea — needs new `textarea.tsx` shim, or reuse `Input` with `as="textarea"` if available — executor picks), `Default fluid` (read-only display `water`, with the same disabled tooltip as the Fluids `+`), `Default g` (NumericField, m/s², default 9.80665), Solver defaults section. | D-04, CD-04 |
| Solver defaults exposure | Three fields: `abstol` (default 1e-8), `reltol` (default 1e-6), `dtmax` (default `nothing` / blank — interpreted as no cap). Each is a NumericField with help-icon tooltips citing `solve_steady` / `solve_transient` semantics. Per CD-04 minimum. | CD-04 |
| Save behavior | Form-level — values are written to `modelOptions` store slice on field blur (same convention as existing component params); `_pushSnapshot()` is called before each mutation; isDirty flips true. | RESEARCH §Pattern 1, §Pitfall 2 |

### Tab switch focus behavior

| Contract | Behavior | Source |
|----------|----------|--------|
| Ctrl+1/2/3 | preventDefault on the keydown; calls `setActiveLeftTab("Components" \| "Resources" \| "Project")`; focus moves to the newly active tab trigger (NOT into the body). User then Tab to enter content. | D-07 + Radix Tabs default |
| Inside Resources tab — keyboard nav after switch | Arrow keys traverse rows once focus is in the tree (Radix doesn't manage `role="tree"` keyboard nav; hand-rolled `<ul>` must implement Up/Down/Home/End — or accept Tab-only nav for v1. Executor decision; default to Tab-only and revisit if usability flags it. Document the decision in code comment.) | CD-01 |

### Sources toolbox category header (D-30)

| Contract | Behavior | Source |
|----------|----------|--------|
| Render condition | Always render the `SOURCES` header in the Components tab, between `THERMAL` and (future) `REACTOR PHYSICS` | D-30 |
| Empty body | Render zero rows. Do NOT render a "(none yet — click +)" placeholder here — the Sources category does not accept user creation (no `+` button); Phase 63 lands the drag entries. | D-30 |
| Drag handlers | None wired in Phase 62. The header is structural only. | D-30 |
| `getComponentsByCategory("Sources")` | Returns `WallTemperature` and `HeatFluxSource` per Phase 61 registry, BUT Phase 62 does not iterate these into the visible body. The header alone signals the future shape. | RESEARCH §Component Responsibilities — `ToolboxPanel.tsx` |

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| shadcn official (new-york style, zinc base) | New shims: `popover.tsx`, `context-menu.tsx`. Existing wrappers reused: `tabs.tsx`, `scroll-area.tsx`, `badge.tsx`, `separator.tsx`, `button.tsx`, `input.tsx`, `label.tsx`, `select.tsx`, `tooltip.tsx`, `dropdown-menu.tsx`, `alert-dialog.tsx`, `toggle-group.tsx`. | not required — shadcn official source |
| Third-party registries | none declared | not applicable |

**Safety verification:** Phase 62 introduces zero third-party registry
imports. The two new shim files (`popover.tsx`, `context-menu.tsx`) are
hand-written wrappers around Radix primitives already transitively
present in `package-lock.json` (lines 1410, 1841 per RESEARCH.md
verification). No `npx shadcn add` invocation against an external
registry is needed; the shims follow the same write-by-hand pattern as
the existing `tabs.tsx` / `scroll-area.tsx` already in the project
(verified: both files in `gui/src/components/ui/` import from the
`radix-ui` aggregator namespace, NOT per-package npm names).

---

## Visual Restraint Audit (§3.8 alignment)

Phase 62 is the first non-trivial GUI shell change since v0.8. The §3.8
contract explicitly names v0.8 as "amateur playbox" and commits to
moving toward "nuclear thermohydraulic design tool." Every visual choice
above is grounded in §3.8 rules. Restating the constraints this phase
holds to:

| §3.8 rule | Phase 62 compliance |
|-----------|---------------------|
| One type scale (12 / 14 / 16 / 20 px) | This phase uses 12 / 13 / 14 / 16. The 13px row is the existing engineering-density variant already in `gui/src/components/sidebar/`. No new sizes introduced. |
| One spacing unit (8px grid) | All sizes are multiples of 4; primary cadence is 8/16/24/32. No new exceptions. |
| Restricted accent palette (blue Hydraulic, amber Thermal) | Untouched. Phase 62 does NOT add a Sources accent color; that's parked for Phase 72 contract drafting. |
| One shadow vocabulary | Only `shadow-md` on the popover (existing shadcn `new-york` default). No new shadow tokens. |
| One border-radius scale | Uses existing `--radius` tokens (`radius-sm` / `radius-md` / `radius-lg` already defined in `index.css`). |
| One font family with deliberate weight variation | System font stack (unchanged); two weights only (400 / 600). No italic except for empty-state and sentinel-resource copy where italic carries semantic weight (placeholder vs real value). |
| Right-click *always* opens a context menu | Per-row context menu on Resources tree honors this. |
| `Esc` always cancels the current operation | Cascade specified above; popover-close > rename-cancel > menu-close > selection-clear. |
| `Enter` confirms | Popover form `Create`, inline-rename commit. |
| Predictable defaults (drop → appears at cursor) | Out of scope for Phase 62 (canvas interaction unchanged). |
| Density expectations (inline values, not buried) | Resources tree shows name only in v1; future phases (Phase 71 validation, Phase 72 contract) may add inline metadata. Phase 62 is structural — no premature density choices. |
| No animated chrome | All hover/selection swaps are instant (no `transition-*` utilities). Radix Popover ships with a default open/close fade (~150ms); we accept the default — that is platform-grade, not chrome. |

---

## Cross-Cutting Invariants (§4 alignment)

| §4 invariant | Phase 62 commitment |
|--------------|--------------------|
| No anonymous Geometry | Phase 62 enforces eager-only resource creation through the picker UX (`+ New…` is the only path). The reference picker has no "inline value" fallback. |
| Layout persisted separately from semantic data | `active_left_tab` lives in `.scp` `layout` block per D-29; layout-only edits do not dirty the simulation-relevant diff. |
| All Julia identifiers ASCII-only and valid | Auto-suggested resource names follow smart-increment (`geometry_<n>`, `power_shape_<n>`); user-edited names are validated against the Julia identifier rule on popover submit. |
| Reset-to-empty rule for property fields (§3.5) | Inherits from existing `NumericField` behavior; not modified in this phase. |

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending

---

## Notes for Planner / Executor / Auditor

**Read order:** This document is a *contract*, not exploratory research.
Each row in each table is binding. The planner uses these locked values
in task acceptance criteria. The executor copies strings verbatim and
implements interaction contracts as specified. The auditor verifies
each row post-implementation.

**What this document does NOT specify:**

- Exact tailwind utility class strings for every element (the executor
  picks the most idiomatic class composition, given the values locked
  here).
- Internal component file layout under `gui/src/components/resources/`,
  `gui/src/components/project/`, `gui/src/components/sidebar/` (planner
  decomposes; this contract dictates visual + interaction, not file
  topology — except where RESEARCH §"Recommended Project Structure"
  guides).
- Test naming or test file structure for Vitest specs (planner picks;
  RESEARCH.md §"Code Examples" has Patterns 1-4 to seed test shapes).

**What is locked and not negotiable in plan/exec time:**

- The four-size typography scale (12 / 13 / 14 / 16 px).
- The two-weight font scheme (400 / 600).
- The spacing tokens (4/8/16/24/32 + 280px popover width + 36px tab strip height + 28px tree row height).
- The OKLCH-based color tokens already in `index.css` (no new color additions).
- All `[USER-FACING]` and `[CODE]` copy strings.
- The interaction precedence cascades (Esc, focus return, tab switch).
- The Radix Popover `onInteractOutside` preventDefault gate + the
  Pitfall 1 focus-return workaround.

Any deviation from a locked row above requires returning to UI-research
(this agent) for a new locked value — not a planner / executor decision.
