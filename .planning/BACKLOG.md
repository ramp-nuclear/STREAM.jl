# STREAM Project Backlog

Deferred items, polish tasks, and future work captured during development.

---

## Edge handle visual bugs (from Phase 36 UAT)
- Hover over edge drag buttons causes mouse cursor glitches or disappearance
- Dragging an edge handle to nowhere produces weird cursor states
- Source: React Flow internals, not custom code
- Priority: low (cosmetic)
- When to fix: UI polish phase (Phase 38 or similar)

---

## Resizable panels (from Phase 36 UAT)
- User wants draggable dividers between panels (canvas <-> bottom panel, canvas <-> sidebar)
- Currently all panel sizes are fixed
- Implementation: use a drag-handle component or CSS `resize`, applied consistently to all panels
- Priority: medium (quality of life)
- When to fix: UI polish phase (Phase 38 or similar)

---

## Edge arrowheads and loop routing (from Phase 36 post-UAT)
- Root cause: React Flow renders edges in SVG, nodes in HTML on top — arrowheads at node
  borders get clipped by the node background
- Loop routing (pump above channel): both edges travel right-to-left through same space,
  smoothstep routes them distinctly but without arrowheads
- Fix option A: floating handles — position handles ~8px outside the node bounding box so
  arrowheads and endpoints sit outside the HTML layer
- Fix option B: midpoint arrowhead — compute bezier midpoint + tangent, draw arrowhead as
  an SVG path element (not a marker) at that point, always away from node borders
- Priority: medium
- When to fix: UI polish phase (Phase 38 or similar)
- **2026-05-11 update:** mostly superseded by the v1.2 GUI redesign milestone (Phase 64:
  Connection routing — autoflip + asymmetric placement). The remaining edge-handle cursor
  glitches (entry #1 in this file) are still real but smaller in scope after Phase 64.

---

## Reverse import — `.jl` script → GUI loadable model (from v1.2 GUI redesign session, 2026-05-11)

- Goal: load an existing hand-written STREAM.jl script and parse it into the GUI's model
  representation so the user can edit it visually
- Inherently fuzzy — the input is not in any expected format; best-effort, no 100% target
- Trigger condition: after the GUI's model schema is stable (post-v1.2) and there's a clear
  parse target. Probably a v2.x milestone or later.
- Priority: low (forward-looking; users have alternative workflows in the meantime)
- Captured during `/gsd:explore` session producing `gui-redesign-design-decisions.md`
  (see Section 6 parked items)

---

## Run code through GUI + result analysis (from v1.2 GUI redesign session, 2026-05-11)

- Goal: revisit embedding Julia execution in the GUI for steady-state and transient solves
  with built-in result analysis (1D plots, pcolormesh-style heatmaps, a thermal-map of
  channels + plates with correct relative sizes)
- Trigger condition: after the source code is fully trusted to work and stable, and after
  users have demonstrated need for in-GUI iteration cycles
- Hard constraint flip: this would reverse the v1.2 "no Julia runtime in GUI" hard
  constraint — should be a deliberate architectural pivot, not a feature slide
- Priority: future (post-v1.2 GUI ships and proves out the code-gen-only workflow)
- Captured during `/gsd:explore` session — Section 6 parked items in
  `gui-redesign-design-decisions.md`

---

## Point Kinetics GUI integration (from v1.2 GUI redesign session, 2026-05-11)

- Goal: full GUI integration for `PointKinetics` and `ReactivityController` — drag-onto-canvas
  blocks, `connect_temperature_feedback` wiring via the Reactor Physics layer
- Trigger condition: after PK is reworked and has a finalized I/O surface (PK rework is
  separate scope, not yet planned)
- v1.2 reserves the Reactor Physics layer slot in the layers system (Phase 68) and a
  toolbox category for these components, but does not implement the integration
- Priority: medium (the v0.9 PK work shipped a working source-side feature; GUI catchup
  is a productivity gap, not a functional gap)
- Captured during `/gsd:explore` session — Section 6 parked items

---

## Channel multiplicity ×N (`signify`) (from v1.2 GUI redesign session, 2026-05-11)

- Goal: implement the Python STREAM `signify` pattern in Julia STREAM — KCL-only weighting
  on channel networks where N parallel channels share thermal equations but contribute ×N
  flow at the network nodes
- Two-part work:
  1. **Codebase**: `replicate(ch, N)` helper + weighted-edge KCL handling in the network
     equations. Not GUI work.
  2. **GUI**: ×N badge on the multiplied channel on the canvas; UI for setting N on a
     channel. Depends on codebase work landing first.
- Trigger condition: codebase work is independent and can be scheduled separately; GUI
  badge work waits on that
- Reference: project memory `project_signify_channel_multiplicity.md` records the agreed
  KCL-only semantics
- Priority: medium-high — real research use case (multi-element MTR cores)
- Captured during `/gsd:explore` session — Section 6 parked items

---

## Repo split decision — STREAM.jl source vs GUI repo (from v1.2 GUI redesign session, 2026-05-11)

- Question: should the GUI eventually live in a separate repo from the Julia source, with
  some kind of version-tracking against the source's `main` branch?
- Motivation: GUI development cadence may diverge from source development; GUI should be
  responsible for verifying it matches the latest source commit
- Options to evaluate:
  - Two separate GitHub repos (most common; standard tooling for cross-repo versioning)
  - One monorepo with internal subdirectory boundary (current state, simpler git story)
  - Some hybrid like git submodules (often more pain than payoff)
- Open concern: GSD workflow currently treats one repo as one project; managing two GSD
  projects sounds painful. Alternative: GUI uses non-GSD Claude Code skills, while
  source stays on GSD
- Trigger condition: revisit once the v1.2 GUI milestone has more concrete scope and the
  cadence question is real. Deferred for v1.2 — milestone proceeds in current monorepo.
- Priority: medium (infrastructure decision, no immediate user-visible impact)
- Captured during `/gsd:explore` session — Section 6 parked items

---

## KFW-1: StreamNode per-port `resolveFlowPortAssignment` is O(N²) per store update (from Phase 66 perf sweep, 2026-05-16)

- Source: `gui/src/components/StreamNode.tsx:187` (FlowPortHandle) and `:261` (ThermalPortHandle)
- Problem: each StreamNode subscribes via `useStore(useCallback((s) => resolveFlowPortAssignment(s.nodes, s.edges, ...)[port.name], ...))`. The selector body walks the entire `nodes` + `edges` graph. With N nodes × ~3 ports each × O(N+M) work, every store mutation triggers O(N²) work across all StreamNodes — including unrelated mutations like `setHoveredSourceIds` from hovering a code-panel sub-block.
- Current impact: typical STREAM circuits are 5–30 components — well within the safe zone (<1ms per drag tick). At 50+ nodes it becomes perceptible; at 100+ it dominates frame cost.
- Suggested fix: lift port-assignment computation into an App-level `useMemo<Map<string, Side>>` keyed by `{nodeId, portName}`, recomputed only when `nodes`/`edges` actually change (via the `useShallow` pattern that ignores positions). Each `<Handle>` then subscribes to a single primitive string from the Map.
- Risk: port autoflip (Phase 64) is intricate and user-facing. Regression here is visually loud (handles snap to wrong sides during edits). Refactor needs careful manual verification, not just unit tests.
- Documented in: `gui/PERFORMANCE.md` Known Followup Work section
- Priority: medium-low (only bites at scale; current behavior is correct, just wasteful)
- When to fix: dedicated Phase 67+ perf phase (estimate 3–5 focused hours)
- Captured during `/gsd:execute-phase 66` UAT, post perf-sweep commit 6325be2
