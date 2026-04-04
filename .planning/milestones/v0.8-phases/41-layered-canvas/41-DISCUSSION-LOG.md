# Phase 41: Layered Canvas - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 41-layered-canvas
**Areas discussed:** Dim vs hide, Toolbox filtering, Multi-layer membership, Toggle placement

---

## Dim vs hide

| Option | Description | Selected |
|--------|-------------|----------|
| Dimmed | Opacity ~20%, spatial context preserved, non-interactive | ✓ |
| Hidden | Completely removed from canvas in off-layer view | |

**User's choice:** Dimmed  
**Notes:** Non-interactive. User stressed: "it should be easy to swap between layers and it should be really obvious what is going on exactly."

---

## Toolbox filtering

| Option | Description | Selected |
|--------|-------------|----------|
| Filter toolbox by layer | Only layer-relevant components shown per view | ✓ |
| Always show all 12 | Toolbox unchanged regardless of active layer | |

**User's choice:** Filter toolbox by layer  
**Follow-up — ChannelAndContacts in toolbox:**

| Option | Description | Selected |
|--------|-------------|----------|
| Show in both Hydraulic and Thermal views | Dual-layer membership, always draggable | ✓ |
| Only in Both view | Restrict to Both mode only | |

**Notes:** ChannelAndContacts appears in both single-layer toolboxes due to its dual port type membership.

---

## Multi-layer membership

| Option | Description | Selected |
|--------|-------------|----------|
| Port-based auto-detection | Layer membership derived from `ports[].type`; no registry changes | ✓ |
| Explicit registry field | Add `layers: []` array to each registry entry | |

**User's choice:** Port-based auto-detection  
**Follow-up — handle dimming on dual-layer components:**

| Option | Description | Selected |
|--------|-------------|----------|
| Dim FlowPort handles in Thermal view | Only active-layer port handles interactive | ✓ |
| All handles always active | Simpler, but off-layer handles draggable | |

**Notes:** In Thermal view, ChannelAndContacts node is visible but its FlowPort handles are dimmed and non-interactive.

---

## Toggle placement

| Option | Description | Selected |
|--------|-------------|----------|
| Main toolbar (centered) | Segmented [Hydraulic] [Both] [Thermal] in toolbar | ✓ |
| Floating ReactFlow panel | Canvas overlay using ReactFlow Panel component | |

**User's choice:** Main toolbar  
**Notes:** User wants the toggle to be **visually prominent** — must clearly communicate it controls layer visibility, not look like a generic button. Tab key cycles layers: Hydraulic → Both → Thermal → Hydraulic. Tab must intercept and suppress the browser default focus-cycle when canvas has focus. "Make sure you disable whatever Tab does right now if it does something."

---

## Claude's Discretion

- Exact opacity for dimmed state
- Visual treatment for toggle prominence (label prefix, icon, active state color)
- CSS transition timing for layer switching
- Tab interception implementation approach

## Deferred Ideas

None.
