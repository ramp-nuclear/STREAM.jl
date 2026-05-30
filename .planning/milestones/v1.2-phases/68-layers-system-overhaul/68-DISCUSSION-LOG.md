# Phase 68: Layers system overhaul - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-16
**Phase:** 68-layers-system-overhaul
**Areas discussed:** Layer accent colors, Dual-layer visibility rule, Tab shortcut fate, Floating chip vs SecondaryToolbar

---

## Layer accent colors

| Option | Description | Selected |
|--------|-------------|----------|
| Green | Distinct from Blue/Amber, standard for supplementary data | |
| Purple / Violet | Further from Blue and Amber on the color wheel, distinctive for value-source concept | ✓ (Claude) |
| Teal / Cyan | Between Blue and Green, risks blending with Hydraulic blue | |

**User's choice:** "Whatever you think is best" (Claude's discretion)
**Notes:** Purple/violet picked for Sources layer — most distinct from the existing Blue and Amber accents. Same "let Claude decide" for Reactor Physics → red/rose chosen for strong nuclear connotation.

---

## Dual-layer visibility rule

| Option | Description | Selected |
|--------|-------------|----------|
| Visible if ANY of its layers is active | CAC stays visible as long as at least one layer is on | ✓ |
| Visible only if ALL of its layers are active | CAC dims when either layer is off — confusing in practice | |
| Visible but partial port dimming | Stays visible, but off-layer handles dim individually | |

**User's choice:** "Visible if ANY of its layers is active"
**Notes:** Matches existing v0.8 behavior for dual-layer nodes. Follow-up question confirmed: when a dual-layer component is visible but one layer is off, its off-layer port handles dim + are locked, and off-layer edges also dim.

---

## Tab shortcut fate

### Tab key behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Remove it | No sensible cycle in a 4-checkbox world; chip is always visible | ✓ |
| Remap to toggle-all-off / restore | Useful for full-model vs filtered comparison | |
| Keep cycling in a fixed order | Odd UX with 4 independent layers | |

**User's choice:** "Remove it"

### View menu Layer submenu

| Option | Description | Selected |
|--------|-------------|----------|
| Replace with 4 checkboxes in View menu | Keeps menu path discoverable | |
| Remove the Layer submenu from View menu | Floating chip is canonical; no duplication | ✓ |

**User's choice:** "The view menu no longer has the layers there. Be updated. It was not a good idea to put there at all so i told you to remove it."
**Notes:** User explicitly flagged this as a correction to Phase 67 D-11. The View menu Layer radio group is removed; floating chip is the sole layer UI.

---

## Floating chip vs SecondaryToolbar

### Layer toggle in SecondaryToolbar

| Option | Description | Selected |
|--------|-------------|----------|
| Delete it — strip becomes [Code toggle] [Export] | No duplication | ✓ |
| Keep a collapsed layer indicator there | Two entry points, adds redundancy | |

**User's choice:** "I guess we can remove layers from the secondary toolbar."

### SecondaryToolbar fate (emergent discussion)

User raised: "I wonder what the point is of having a whole toolbar just for two buttons." Claude proposed removing the SecondaryToolbar entirely and migrating the two remaining controls:
- Export → File menu
- Code Preview toggle → bottom panel's own header

**User's choice:** Accepted both proposals. Code Preview placement: "I guess its fine if we can't think of anything else. We can try it out and see how it looks."
**Notes:** User wanted Code Preview toggle to be "somewhere you can always access but actually makes sense" — the bottom panel header approach (VS Code / JetBrains pattern with a persistent thin stub strip when closed) was accepted as the best available option.

---

## Claude's Discretion

- **Sources layer accent color:** Purple/violet
- **Reactor Physics layer accent color:** Red/rose
- **State shape:** `activeLayers: Record<LayerKey, boolean>` + `hideOffLayer: boolean`; store actions `toggleLayer`, `setLayerVisible`, `setAllLayersVisible`
- **Layer membership derivation:** `category` field from registry (not port-type detection)
- **Off-layer locking mechanism:** Per-node ReactFlow `{ selectable: false, draggable: false }` + `{ hidden: true }` in hide mode
- **Floating chip placement detail:** Near existing Phase 65 overlay buttons; exact cluster arrangement at planner's discretion
- **Auto-enable on connect:** Via `onConnect` callback post-hoc; never block

## Deferred Ideas

- Extended accent palette application (node borders, port handles): Phase 72
- Settings dialog shell: Phase 72
- Reactor Physics layer component content (PK/RC GUI integration): future phase
