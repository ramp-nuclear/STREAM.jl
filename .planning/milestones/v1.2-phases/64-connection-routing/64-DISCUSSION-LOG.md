# Phase 64: Connection routing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 64-connection-routing
**Areas discussed:** Recomputation & persistence, Anti-parallel offset scope, Asymmetric placement geometry, Edge cases (ties + crowding)

---

## Recomputation & Persistence

### Recompute trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Live during drag | Recompute handle sides on every position update while dragging. User sees the fix form in real time. | ✓ |
| On drag-end only | Handles snap to new sides when the user releases the mouse. Less visual noise but a single resolved layout per drag. | |
| Only on connect/disconnect | Sides recompute when an edge is added or removed, never on position change. Cheapest but stale on move. | |

**User's choice:** Live during drag (Recommended).

### Where does resolved side live?

| Option | Description | Selected |
|--------|-------------|----------|
| Pure derivation, no persistence | Function of (connections, node positions); nothing new in node data or .scp. | ✓ |
| Persist resolved side on each node | Store `flowSides` field on node data, written to .scp. Opens door for manual override later. | |
| Cache in React state, not in .scp | Memoized for perf but not serialized. Same end result as pure derivation. | |

**User's choice:** Pure derivation, no persistence (Recommended).

### Anchor glyph follows handle?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — anchor follows handle | When port_in flips to bottom, anchor moves with it. Consistent visual story. | ✓ |
| No — anchor stays at registry default | Only the connection dot autoflips; anchor stays put. | |

**User's choice:** Yes — anchor follows handle (Recommended).

### Layer dimming and autoflip

| Option | Description | Selected |
|--------|-------------|----------|
| Always uses all connections | Dimming is purely visual; data unchanged. No re-routing on layer switch. | ✓ |
| Dimmed-layer connections ignored | Switching layers may visibly re-route edges; can be disorienting. | |

**User's choice:** Yes — autoflip always uses all connections (Recommended).

---

## Anti-Parallel Offset Scope

### In scope or deferred?

| Option | Description | Selected |
|--------|-------------|----------|
| In scope as custom-edge polish | Detect bidirectional pairs, bow forward/return slightly off midline. Closes Example-1 X-cross fully. | ✓ |
| Defer to its own phase | Ship autoflip + asymmetric placement only; X-cross at midpoint accepted. | |

**User's choice:** In scope as custom-edge polish (Recommended).

### Bow magnitude

| Option | Description | Selected |
|--------|-------------|----------|
| Small constant bow (±8px) | Hard-coded perpendicular offset; tune in implementation. | ✓ |
| Distance-proportional bow | Offset scales with node-pair distance. | |
| User-tunable in Settings | Settings-panel knob. Probably overkill for v1. | |
| Skip — deferred | Moot if offset is deferred. | |

**User's choice:** Small constant bow ±8px (Recommended).

### Pair-detection rule

| Option | Description | Selected |
|--------|-------------|----------|
| Same two nodes, opposite directions, any port pair | (sourceNode, targetNode) of one == reverse of the other. Handles closed-loop case cleanly. | ✓ |
| Stricter — same port pair too | Both edges must use the same (port_a, port_b) handle pair. Risks under-detecting. | |
| Skip — deferred | Moot if offset is deferred. | |

**User's choice:** Same two nodes, opposite directions, any port pair (Recommended).

---

## Asymmetric Placement Geometry

### Spacing when two ports share a side

| Option | Description | Selected |
|--------|-------------|----------|
| 25% / 75% along the side | Symmetric inset; scales with node width via percentage offsets. | ✓ |
| 33% / 67% (tighter clustering) | Wider corner gap, narrower port gap. More centered look. | |
| Pixel offset from corner (16px) | Fixed inset; doesn't scale with node width. | |

**User's choice:** 25% / 75% (Recommended).

### Orientation of "leading end"

| Option | Description | Selected |
|--------|-------------|----------|
| Reading direction — left/top is 'first' | port_in always at reading start, port_out at end. | ✓ |
| Flow direction — in is closer to upstream neighbor | Geometrically optimal per edge but inconsistent across nodes. | |

**User's choice:** Reading direction (Recommended).

### Default (zero connections) behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Registry default until first connection | Per §3.3; toolbox drops look unchanged until wired. | ✓ |
| Autoflip with axis = horizontal as tiebreaker | Treats no-connection case as a degenerate horizontal axis. | |

**User's choice:** Registry default until first connection (Recommended).

### Thermal-pair asymmetric placement

| Option | Description | Selected |
|--------|-------------|----------|
| N/A — thermal pair always opposite faces | §3.4 locks this; no same-side case for thermals. | ✓ |
| Apply asymmetric placement when flow + thermal both want same edge | Interleave 4 handles along shared edges. | |

**User's choice:** N/A — thermal pair stays opposite-faces (Recommended).

---

## Edge Cases (ties + crowding)

### Tie-breaking when |dx| ≈ |dy|

| Option | Description | Selected |
|--------|-------------|----------|
| Prefer horizontal | `|dx| ≥ |dy| → horizontal`. Deterministic, no hysteresis. | ✓ |
| Prefer registry default axis | Tie uses the per-port registry default axis. | |
| Hysteresis — sticky to last resolved side | Margin before flipping. Adds state; complicates pure derivation. | |

**User's choice:** Prefer horizontal (Recommended).

### Dead zone for live-drag axis switching

| Option | Description | Selected |
|--------|-------------|----------|
| No dead zone — strict comparison | Simplest; 1-pixel flicker band at exactly 45°. | ✓ |
| 10° dead zone around 45° | Stays on previously resolved axis in the band; adds state. | |
| Defer hysteresis to a 'feels janky' future patch | Ship strict compare; add later if needed. | |

**User's choice:** No dead zone — strict comparison (Recommended).

### Crowded-edge case (4 handles on 2 edges)

| Option | Description | Selected |
|--------|-------------|----------|
| Interleave handles + topology-hint warning | Place all 4 along shared edges, surface yellow validation chip. | ✓ |
| Interleave only — no warning | Stuff 4 handles on 2 edges silently. | |
| Validation warning only — don't interleave | Thermal stays at registry default; warning surfaces issue. | |

**User's choice:** Interleave + topology-hint validation chip (Recommended).

### Neighbor anchor point for dx/dy

| Option | Description | Selected |
|--------|-------------|----------|
| Node center to node center | (x + width/2, y + height/2). Cheap, stable. | ✓ |
| Component edge midpoints | More 'optical' but jittery on close / overlapping nodes. | |
| Handle position to handle position | Circular dependency; rejected. | |

**User's choice:** Node center to node center (Recommended).

---

## Claude's Discretion

- Internal data shape of the autoflip selector (Zustand selector / `useMemo` / custom hook) — pick what fits cleanly with the current `StreamNode.tsx` rendering path.
- Exact filename and location of the autoflip function — e.g., `gui/src/lib/autoflip.ts` vs colocated in `StreamNode.tsx`.
- Validation chip wiring details — follow Phase 63.1 BC-error panel precedent.
- Test surface — unit tests for geometric rules + representative ReactFlow layouts covering the §3.3 example cases.

## Deferred Ideas

- Per-component rotation override (right-click → Rotate 90°)
- Manual handle override (user drags a port to a different side)
- Distance-proportional anti-parallel bow
- User-tunable bow in Settings
- 10° dead zone / hysteresis for axis switching
- Thermal handle visual restyle (yellow diamond → cleaner glyph)
- Auto-Layout (full-graph reflow)
