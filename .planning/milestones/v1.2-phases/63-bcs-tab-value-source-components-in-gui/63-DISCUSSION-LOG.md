# Phase 63: BCs tab + value-source components in GUI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 63-bcs-tab-value-source-components-in-gui
**Areas discussed:** BCs tab visual structure, Profile/Function/Mark mode mechanics, Canvas BC connection mechanics, Source block visual + n-mismatch + global BCs tab fate

---

## BCs tab visual structure

### Mode picker rendering

| Option | Description | Selected |
|--------|-------------|----------|
| Segmented control (5 pills) | Matches existing `ModeToggle.tsx` pattern (Pump fixed-dP / fixed-mdot). Row of 5 buttons: [Value][Profile][Function][Mark][Source]. Editor renders below. Pro: visible affordance. Con: wider than 2-pill version; needs ~280px right panel fit. | ✓ |
| Select dropdown + editor below | Compact <Select>; editor renders below based on selection. Pro: less width. Con: hides options behind a click. | |
| Icon + label segmented control | 5 buttons each with icon + label. Pro: discoverable. Con: requires icon pass; risks consumer-SaaS feel vs §3.8 engineering-tool restraint. | |

**User's choice:** Segmented control (5 pills)
**Notes:** Matches the existing idiom in the codebase; engineering-tool restraint preserved.

### Field-pair layout

| Option | Description | Selected |
|--------|-------------|----------|
| Two separate stacked sections | Two explicit blocks (T_wall_left + T_wall_right). No shared/symmetric shortcut. | |
| Symmetric-by-default with asymmetric toggle | Top-level `Symmetric (L = R)` toggle default ON; one mode picker + one editor, code-gen emits to both. Toggle OFF expands to two stacked blocks. Mirrors the BC edge `:both` default. | ✓ |
| Tabs (L / R) within the BCs tab | Inner [Left][Right] tab strip. Compact, but tab-in-tab feels nested. | |

**User's choice:** Symmetric-by-default with asymmetric toggle
**Notes:** Matches the canvas BC-edge `:both` default; common case is one click to set both sides.

### Tab strip placement

| Option | Description | Selected |
|--------|-------------|----------|
| Below the instance-name + badge header | Header identifies component once; tabs switch aspect being edited. Mirrors browser tab strip below URL bar. | ✓ |
| Above the instance-name header | Tab strip topmost; header repeated in each tab. IDE-style. | |
| Same row as the panel title (compact) | `Properties` h2 + tab strip share a row. Saves vertical space; busier title row. | |

**User's choice:** Below the instance-name + badge header

### Tab memory across selection changes

| Option | Description | Selected |
|--------|-------------|----------|
| Reset to Properties on every selection change | Predictable; Properties is higher-frequency tab. | ✓ |
| Sticky-per-component | Remember last active tab per component instance; persist in `.scp` layout block. | |
| Sticky-globally | Whatever tab was active stays active; falls back when no BCs tab. | |

**User's choice:** Reset to Properties on every selection change

---

## Profile / Function / Mark mode mechanics

### Preset profile set for v1

| Option | Description | Selected |
|--------|-------------|----------|
| Axial cosine only | One preset: `axial_cosine(amplitude, peaking_factor)`. Imports cover anything else. Engineering-tool restraint. | ✓ |
| Cosine + Linear | Two presets; linear catches 'top-hotter, bottom-cooler' patterns. | |
| Cosine + Linear + Hot-spot + Chopped-cosine | Four presets covering reactor-physics shape vocabulary. | |

**User's choice:** Axial cosine only

### Import-from-file handling

| Option | Description | Selected |
|--------|-------------|----------|
| Strict n-match | File must have exactly `n` values; mismatch → error. Caller hand-resamples externally. | |
| Linear interpolation at codegen time | New `interpolate_to_n(vec, n)` helper. Convenient; hidden numerical transformation. | |
| Defer file-import in v1 — Profile mode is presets-only | Smallest scope; clean boundary. | |
| **`rebin_intensive` helper (user-proposed, accepted)** | New helper paralleling `rebin_extensive`; area-weighted-mean-conserving regridding. 1D + 2D signatures for API symmetry. Caller-trust posture: visible in generated code. | ✓ |

**User's choice:** `rebin_intensive` (1D + 2D signatures, symmetric with `rebin_extensive`)
**Notes:** User asked whether a `rebin_intensive` companion was feasible. Assessed: yes — same separable algorithm, normalized differently. The two-helper architecture (extensive vs intensive) cleanly partitions the conservation-law distinction (sum vs area-weighted mean). 2D added for forward compatibility with future intensive-field imports.

### Function mode editor + body location

| Option | Description | Selected |
|--------|-------------|----------|
| Stub-and-edit-in-code | BCs-tab editor minimal: signature picker `[fn(t)][fn(t,i)]` + auto function name. Codegen emits stub + binding. User edits body in generated `.jl`. | ✓ |
| Inline Julia textarea inside the BCs tab | Self-contained but turns GUI into a (bad) code editor. | |
| Function Resource (new Resource kind) | Reusable; bigger phase surface; new Resource kind. | |

**User's choice:** Stub-and-edit-in-code
**Notes:** Engineering-tool restraint; visible in code, not hidden in GUI.

### Default BC state on a brand-new Channel

| Option | Description | Selected |
|--------|-------------|----------|
| Required-unset (red-flagged) | No mode pill active; inline `BC required — select a mode` hint. Codegen emits TODO comment + no equation. Phase 71 owns gating; Phase 63 ships the visual unset state. | ✓ |
| Mark in code by default | Always-valid state; blurs intentional-Mark vs never-touched. | |
| Value 0 | Runnable on day one; silently bogus (0 K wall is wrong). | |

**User's choice:** Required-unset
**Notes:** Matches Phase 62's `unset` Power Shape sentinel; engineering-tool 'don't silently default to a wrong value.'

---

## Canvas BC connection mechanics

### Drop target on the consumer Channel

| Option | Description | Selected |
|--------|-------------|----------|
| Whole-component drop zone, ReactFlow custom node | Drop target = Channel's whole body, activated only by BCPort drags. Faint dashed outline + 'Connect BC' chip on hover. Matches §3.11 'onto the block body, not a specific handle.' | ✓ |
| Conditional invisible target handles (3 handles) | Reveals 3 hit-test handles (left/right/both) during BCPort drag. Side picked at connect time. | |
| Drop-and-pick-side modal | Drop anywhere; popover at drop point asks [L/R/Both]. Extra click for the common `:both` case. | |

**User's choice:** Whole-component drop zone, ReactFlow custom node

### Target-side picker (:left / :right / :both)

| Option | Description | Selected |
|--------|-------------|----------|
| Inline edge label only — click-to-cycle | Mid-edge chip shows `L+R` (default); click cycles `L+R → L → R → L+R`. Always visible — side is part of edge's identity. | ✓ |
| Right-click context menu only | Right-click → [Left/Right/Both]. Edge body shows no inline label. | |
| Both: inline chip + right-click menu | Maximal discoverability; small UX redundancy. | |

**User's choice:** Inline edge label only — click-to-cycle
**Notes:** Right-click semantics are Phase 65's interaction-model overhaul; Phase 63 stays minimal.

### Dashed BCPort edge style

| Option | Description | Selected |
|--------|-------------|----------|
| Dashed muted-foreground, 1.5px, 6-3 pattern | stroke=`var(--muted-foreground)`, theme-aware. Reads as 'metadata link.' Phase 72 can override centrally. | ✓ |
| Dashed Sources-layer accent color, 1.5px, 6-3 pattern | Uses Sources/BCs-layer accent per §3.8. Accent palette is decided in Phase 72 — would be a placeholder. | |
| Dashed neutral, 1px, 4-2 pattern (thinner) | Reads more clearly as 'wire.' Thin dashes fade on low-DPI displays. | |

**User's choice:** Dashed muted-foreground, 1.5px, 6-3 pattern

### Behavior when no source block exists yet

| Option | Description | Selected |
|--------|-------------|----------|
| Inline `+ New WallTemperature` button in the picker | Empty dropdown shows the button; click spawns a node on canvas, auto-selects it, creates the edge. Parallels Phase 62's `+ New…` Resource pattern. | ✓ |
| Source mode disabled with hint | Source pill greyed out; user must switch to Components tab, drag, then come back. | |
| Source mode active but picker shows empty + nudge text | Source pill selectable; dropdown nudges. Confusing state. | |

**User's choice:** Inline `+ New WallTemperature` button in the picker
**Notes:** Keeps the user in flow inside the BCs tab; mirrors Phase 62 reference-picker discipline.

---

## Source block visual + n-mismatch + global BCs tab fate

### Source block visual idiom

| Option | Description | Selected |
|--------|-------------|----------|
| Hollow-square BCPort + standard StreamNode rectangle | Block: standard rectangle. Port: hollow square, no fill, 1.5px stroke, `muted-foreground`. Distinct from FlowPort circle and ThermalPort chain-link. Matches §3.11 'hollow square in neutral color.' | ✓ |
| Open-chevron BCPort + standard rectangle | Chevron port signals directional output. Harder to hit-test. | |
| Hollow-square BCPort + distinct compact card (rounded, accent border) | New chrome variant before Phase 72 finalizes accent palette; risks rework. | |

**User's choice:** Hollow-square BCPort + standard StreamNode rectangle

### Block label content

| Option | Description | Selected |
|--------|-------------|----------|
| Instance name + mode-aware compact value | Top = instance name. Bottom = mode-aware: `T_wall = 320 K` / `vector (n=10)` / `fn(t)` / `(unset)`. Truthful without false precision. | ✓ |
| Instance name + full value with truncation | Truncated vectors / functions can mislead. | |
| Instance name only + tooltip with details | Cleanest canvas; hostile to skim-reading complex diagrams. | |

**User's choice:** Instance name + mode-aware compact value

### n-mismatch handling at connect time

| Option | Description | Selected |
|--------|-------------|----------|
| Soft warning + red ring on both nodes; allow the connection | Edge created; red ring + red-text hint in BCs tab + source block; code-gen still emits equations (compile-time error visible in code). Matches §3.9 / §3.11 'soft warning.' | ✓ |
| Hard-block at connect time | Connection refused; shake + red toast. §3.11 calls n-mismatch soft, not hard — and prevents creating source-first-then-fixing-n. | |
| Soft warning + auto-sync n option in the warning | Inline `[Sync n: WT → 12]` action button. Phase 71 explicitly owns validation-framework action buttons. | |

**User's choice:** Soft warning + red ring on both nodes
**Notes:** Phase 71 owns the inline lossless-sync action button. Phase 63 ships only the visual shape (red-ring + red-text hint).

### Fate of `BottomPanel` BCs tab (pressure anchors)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep BottomPanel BCs tab unchanged | Two BC mechanisms coexist: per-component BCs tab (external_inputs) + BottomPanel BCs tab (pressure-anchor equations on derived port state). Mathematically different objects. | ✓ |
| Retire BottomPanel BCs tab + fold pressure anchors into a unified 'BCs' panel | One mental model; blurs external_input vs port-anchor distinction; bigger scope. | |
| Retire BottomPanel BCs tab; pressure anchors move to FlowPort-handle property | Localizes BC to where it physically lives; larger UX change. Belongs in Phase 65 or follow-up. | |

**User's choice:** Keep BottomPanel BCs tab unchanged
**Notes:** Clean semantic boundary. Future consolidation deferred.

---

## Claude's Discretion

- **CD-01:** Exact code-gen text for the unset / Mark TODO comment.
- **CD-02:** Exact name of the cosine helper used for Profile mode (consider reusing Phase 62's `cosine_power_shape` mathematically).
- **CD-03:** Whole-component drop-target activation specifics in ReactFlow.
- **CD-04:** Smart-name-increment counter sharing between toolbox-drag and inline `+ New` source-block creation.
- **CD-05:** Whether the symmetric-toggle state is per-component-instance (persisted in `.scp`) or session-only. Per-component-persistent is the natural default.

## Deferred Ideas

- Additional Profile presets (linear ramp, hot-spot, chopped cosine, polynomial).
- Lossless-sync action button on n-mismatch (`[Sync n: WT → 12]`) → Phase 71.
- Gates-code-gen-export rule for unset BCs → Phase 71.
- Right-click context menu on BC edges → Phase 65.
- Bidirectional `select-on-canvas → highlight-in-BCs-tab` polish.
- Pressure anchors as FlowPort-property metadata → Phase 65 or follow-up.
- Function Resource kind (4th Resources group).
- Inline Julia code editor in the GUI for Function mode (explicitly rejected).
- Source-block accent palette + chain-link connected/unconnected port icons → Phase 72.
- 2D `rebin_intensive` real-workflow validation (added for API symmetry; reassess in 2 milestones).
- Hover tooltip on source block → Phase 72 tooltip system.
- Bidirectional sync for non-Source BC modes (code → BCs tab updates).
