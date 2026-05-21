---
status: not-a-bug
resolved: 2026-05-21
resolved_in: |
  Closed as not-a-bug per owner 2026-05-21. Cross-platform behavior measured after Plan 65-14:
    - Windows build: smooth, no lag — accepted.
    - WSL2 build: very minor chop — accepted environmental floor (WebKitGTK + WSLg).
  Diagnosis still valid as a historical record:
    - (2) in-app contributors FIXED by Plan 65-14 — App.tsx title-sync subscribe (gui/src/App.tsx:407-415)
      now uses subscribeWithSelector with equalityFn so setTitle IPC fires only on currentFilePath
      or isDirty change; useStore autoRecover subscribe (gui/src/store/useStore.ts:3280-3286)
      gated to isDirty transitions only.
    - (1) WSL2 + WebKitGTK environmental floor — primary suspect for right-click pan chop —
      confirmed not actionable: Windows build is smooth, proving there is no in-app issue.
    - Autoflip per-port selectors remain unmemoized in StreamNode.tsx (resolveFlowPortAssignment /
      resolveThermalPairSides) but Windows-smooth-WSL2-acceptable result means no fix is warranted.
      If a future, much larger scene exposes drag chop on Windows, reopen and implement
      WeakMap-keyed memoization on (nodes, edges) identity.
trigger: "dragging with right click is not smooth (not something new but I will mention it now). It may be FPS locked or something like that, because it feels chopped to drag around and drag stuff around. Maybe the performance of the entire GUI is capped in some way?"
created: 2026-05-15T00:00:00Z
updated: 2026-05-21
---

## Current Focus

hypothesis: Initial — multiple candidates from caller's hypothesis list
test: Inspect CanvasPanel.tsx, useStore.ts, autoRecover.ts, tauri.conf.json, node component files; identify selectors firing on drag, subscribe callbacks, GPU/webview args
expecting: Find one or more specific contributors with file:line evidence; if WSL2/WebKitGTK is the dominant factor, say so plainly
next_action: Read all files listed in <files_to_read>; trace drag event flow from RF mousemove → onNodesChange → store set → subscribers

## Symptoms

expected: Right-click pan and node drag feel smooth, not visibly FPS-capped.
actual: User reports chopped/laggy drag and pan in STREAM Composer canvas; suspects FPS lock or GUI-wide perf cap.
errors: (none — perceived perf issue, no exceptions)
reproduction: Phase 65 UAT Test 4; pre-existing — long-standing.
started: long-standing (not Phase 65 specific)

## Eliminated
<!-- APPEND only -->

- hypothesis: Heavy SVG `<Background />` pattern is the cause
  evidence: CanvasPanel.tsx:330 uses `BackgroundVariant.Dots` — the cheapest variant; not a Lines pattern. Single shallow SVG layer.
  timestamp: 2026-05-15

- hypothesis: Strict-mode double-invoke is the cause
  evidence: Drag is steady-state, not initial-mount. Strict-mode affects mount/unmount only, not steady-state drag.
  timestamp: 2026-05-15

## Evidence
<!-- APPEND only -->

- timestamp: 2026-05-15
  checked: gui/src-tauri/tauri.conf.json + gui/src-tauri/src/lib.rs
  found: NO webview tuning. No `webviewArgs`, no `WEBKIT_DISABLE_COMPOSITING_MODE` / `WEBKIT_DISABLE_DMABUF_RENDERER` envs, no GPU flags. Tauri uses WebKitGTK defaults on Linux.
  implication: On WSL2 (Linux 6.6 microsoft-standard-WSL2), the WebKitGTK + WSLg/RDP GPU passthrough is known to cap effective framerate / introduce frame chop. This is an environmental floor that no in-app code change can lift.

- timestamp: 2026-05-15
  checked: gui/package.json
  found: zustand 5.0.12, @xyflow/react 12.10.2, react 19.1.0. zustand v5 default `useStore.subscribe(cb)` callback fires on EVERY `set()` regardless of selector unless `subscribeWithSelector` middleware is composed.
  implication: Any unconditional subscribe callback amplifies per-drag work.

- timestamp: 2026-05-15
  checked: gui/src/store/useStore.ts:781 — `create<AppState>()((set, get) => ({...}))`
  found: NO middleware. Plain `create(...)`. No `subscribeWithSelector`, no `combine`, no equality fn.
  implication: Every `useStore.subscribe(...)` registered by App.tsx fires on every `set()`, including per-pixel drag sets.

- timestamp: 2026-05-15
  checked: gui/src/store/useStore.ts:1014–1048 `onNodesChange`
  found: For a position change (non-contentless), code runs `set({ nodes: applyNodeChanges(changes, get().nodes), isDirty: true })`. New `nodes` array reference + `isDirty: true` written per mousemove tick.
  implication: Every pixel of node-drag = one full zustand set + new `nodes` reference + isDirty stays true.

- timestamp: 2026-05-15
  checked: gui/src/store/useStore.ts:2691 (initAutoRecover subscribe)
  found: `useStore.subscribe((state) => { if (state.isDirty) writer.schedule(); else writer.cancel(); })`. `writer.schedule()` runs `clearTimeout(timer); timer = setTimeout(..., 2000)`. During a drag isDirty stays true, so it calls schedule() on every mousemove tick (clearTimeout + setTimeout per pixel).
  implication: Cheap-but-not-free per-pixel timer-heap churn. Not catastrophic alone, but real allocation pressure.

- timestamp: 2026-05-15
  checked: gui/src/App.tsx:288 (title-sync subscribe)
  found: `useStore.subscribe((state) => { syncTitle(state.currentFilePath, state.isDirty); })` runs unconditionally on every set. `syncTitle` calls `document.title = title` AND `getCurrentWindow().setTitle(title).catch(console.error)` — Tauri IPC call to the native window manager.
  implication: A Tauri IPC round-trip is issued on every mousemove during a node drag. IPC + GTK setTitle is meaningful overhead, and worse on WebKitGTK/WSLg. This is the most likely in-app contributor to chop on top of the WSL2 floor.

- timestamp: 2026-05-15
  checked: gui/src/components/StreamNode.tsx:161–235 (FlowPortHandle) + 247–305 (ThermalPortHandle)
  found: Each FlowPort handle calls `useStore(useCallback(s => resolveFlowPortAssignment(s.nodes, s.edges, nodeId, getComponent)[port.name] ?? defaultSide, [...]))`. Selector body is O(N) (nodes.find for self) + O(P) (FlowPort loop) + per-port O(E) edges.find + O(N) neighbor nodes.find. Same shape for ThermalPortHandle via resolveThermalPairSides. Zustand re-runs this selector on every set.
  implication: Per-mousemove-tick total work scales as O(Nodes_rendered × Ports_per_node × (Nodes + Edges)). Quadratic-ish in scene size, computed every pixel of drag. Returned values (`Side` strings, hasError booleans) ARE primitives, so re-renders are properly bounded once the side stabilizes — but the selector body still runs each set.

- timestamp: 2026-05-15
  checked: gui/src/components/StreamNode.tsx:309,317,323 (StreamNode root selectors)
  found: Three `useStore(useCallback(...))` selectors per node (hasError, hasBCError, activeLayer). hasBCError selector wraps `selectNodeErrors(s, id)` — non-trivial topology-validation function — and runs on every set.
  implication: Per-node-per-set: 3 selectors, one of which is non-trivial. For N nodes onscreen: 3N selector evaluations per drag tick.

- timestamp: 2026-05-15
  checked: gui/src/components/CanvasPanel.tsx:75–91, 94–109 (enrichedNodes, enrichedEdges)
  found: `useMemo([nodes, activeLayer])`. In `activeLayer === "Both"` default, returns `nodes` reference directly — no mapping cost. Otherwise creates a new mapped array per render.
  implication: Default mode is cheap; non-Both layer mode multiplies cost by per-node `.map` + spread. Default ≠ a problem here.

- timestamp: 2026-05-15
  checked: 65-UAT.md Test 4 user report
  found: User explicitly says "dragging with right click is not smooth" — right-click in our config is `panOnDrag={[2]}` (CanvasPanel.tsx:319), which is RF viewport pan, NOT node mutation. Viewport pan does NOT call `onNodesChange` and does NOT mutate our app store at all.
  implication: If RIGHT-CLICK PAN feels chopped, the dominant factor is OUTSIDE our app store / render chain. ReactFlow viewport pan is a CSS transform on the RF root — purely browser-level. Choppiness in viewport pan is dispositive evidence of a browser-rendering / GPU compositing floor — i.e., WebKitGTK + WSLg.

## Resolution

root_cause: |
  Two-component cause, ranked by dominance for each scenario:

  (1) PRIMARY for right-click PAN chop, AND a baseline contributor to node-drag chop:
  WSL2 + WebKitGTK GPU compositing path. Tauri default on Linux is WebKitGTK; WSL2 graphics
  go through WSLg's RDP-based forwarding. ReactFlow viewport pan is a pure CSS transform on
  RF root — it does NOT touch our store. The user reports chop on right-click pan, which
  means the chop is happening at the browser-paint / GPU-composite layer, BELOW any React
  state code. tauri.conf.json has no webview tuning; lib.rs sets no WEBKIT_* envs.
  This is environmental and not actionable inside the app without low-level WebKit env tweaks
  whose effect on WSL2 is unproven.

  (2) ADDITIONAL contributor for NODE-drag (compounds on top of (1)):
  Every mousemove tick during a node drag triggers:
   - `set({ nodes: ..., isDirty: true })` in useStore.ts:1048
   - Notifies ALL `useStore.subscribe` callbacks (zustand v5 has no selector by default; no
     `subscribeWithSelector` middleware is installed)
   - App.tsx:288 unconditionally calls `getCurrentWindow().setTitle(...)` — a Tauri IPC call
     into native window-manager code — on every pixel
   - useStore.ts:2691 (initAutoRecover) does `clearTimeout` + `setTimeout(2000)` per pixel
   - All visible StreamNode + per-port handle components re-evaluate selectors that scan the
     full nodes/edges arrays (autoflip's resolveFlowPortAssignment / resolveThermalPairSides)

  The Tauri-IPC setTitle per mousemove is the single most suspicious in-app contributor.
  The autoflip per-port full-array selectors are the next biggest scaling concern as the
  scene grows.

fix:
verification:
files_changed: []
