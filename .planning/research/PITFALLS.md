# Pitfalls Research

**Domain:** Tauri 2 + React + ReactFlow desktop GUI with Julia code generation for STREAM.jl v0.8
**Researched:** 2026-04-01
**Confidence:** MEDIUM-HIGH (ReactFlow and Tauri 2 pitfalls verified via official docs and GitHub issues; code generation pitfalls derived from STREAM.jl source analysis; cross-platform pitfalls from documented bug reports)

---

## Critical Pitfalls

### Pitfall 1: ReactFlow Stale Closures in Custom Node Callbacks

**What goes wrong:**
Custom node components capture stale references to `nodes` or `edges` arrays in event handlers. When a user edits a parameter in the sidebar, the callback reads an outdated snapshot of the graph state, causing silent data loss -- the user's edit appears to "revert" on the next render cycle, or worse, overwrites another node's data.

**Why it happens:**
React's closure semantics mean that any function created inside a render captures the state values at that render time. ReactFlow's `useNodesState` and `useEdgesState` hooks return new array references on every change, but callbacks memoized with `useCallback` without proper dependency arrays hold stale references. React 18's automatic batching makes this worse by collapsing multiple state updates into one render, so intermediate states are never seen.

**How to avoid:**
- Use Zustand as the state store (ReactFlow's official recommendation for non-trivial apps). Zustand's `useStore` with selectors avoids the stale closure problem because selectors subscribe to specific slices of state, not the whole array.
- Never pass raw `nodes`/`edges` arrays as dependencies to `useCallback` -- use Zustand selectors or `useStoreApi` for imperative access inside callbacks.
- For the parameter editing sidebar: read node data via `useStore(state => state.nodes.find(n => n.id === selectedId)?.data)` with a selector, not by closing over `nodes`.

**Warning signs:**
- Parameter edits in the sidebar that "bounce back" to previous values.
- `console.log` inside a callback showing old state while the UI shows new state.
- Tests pass when actions are slow but fail when automated (timing-dependent).

**Phase to address:**
Phase 34 (Canvas & Node Editor) -- establish the Zustand store pattern before any custom node logic is written. Phase 35 (Parameter Editing) inherits this pattern.

---

### Pitfall 2: ReactFlow Re-renders Cascade from Node/Edge Array Mutations

**What goes wrong:**
Every custom node component re-renders whenever the `nodes` array reference changes -- including when a completely unrelated node moves. With 20+ nodes on canvas, dragging one node causes O(n) re-renders per frame, making the UI visibly janky. The parameter sidebar, if it depends on the `nodes` array, also re-renders on every drag, causing input fields to lose focus or lag.

**Why it happens:**
ReactFlow passes the `nodes` array to its internal renderer. If custom nodes are not wrapped in `React.memo`, React re-renders them all. Even with `React.memo`, if node data objects are recreated (new references) on each state update, the shallow comparison fails and every node re-renders anyway.

**How to avoid:**
- Wrap ALL custom node components in `React.memo()` from day one. This is non-negotiable.
- Wrap ALL custom edge components in `React.memo()` as well.
- Store node data as stable references in Zustand. When updating a single node's parameter, mutate only that node's data slice using Zustand's `immer` middleware or manual spread, ensuring other nodes keep the same reference.
- The parameter sidebar must subscribe to only the selected node's data, not the entire nodes array: `useStore(s => s.nodes.find(n => n.id === selectedId))`.
- Memoize all props passed to `<ReactFlow>`: `nodeTypes`, `edgeTypes`, `defaultEdgeOptions`, callback functions.

**Warning signs:**
- React DevTools Profiler shows all nodes re-rendering on single-node drag.
- Input fields in the sidebar lose focus when typing.
- Canvas becomes sluggish with 15+ nodes.

**Phase to address:**
Phase 34 (Canvas & Node Editor) -- define `nodeTypes` and `edgeTypes` outside the component or memoize them. Phase 35 (Parameter Editing) -- ensure sidebar uses precise selectors.

---

### Pitfall 3: Code Generation Emits Wrong Constructor Signatures

**What goes wrong:**
Generated Julia code uses keyword arguments where STREAM.jl expects positional arguments (or vice versa). Example: generating `Pump(dP_pump=30000.0)` instead of `Pump(30000.0)`, or `Channel(n=10, geometry=PipeGeometry_circular(0.6, 0.01))` missing the keyword syntax. The generated file runs but produces a `MethodError` at runtime, and the user blames the GUI.

**Why it happens:**
STREAM.jl has a mixed convention (documented in CLAUDE.md): single-physics-parameter components use positional args with dispatch (`Pump(dP::Real; name)`, `Resistor(R; name)`), while multi-parameter components use keyword-only (`Channel(; n, geometry, ...)`). Factory functions (`PipeGeometry_rectangular`, `PipeGeometry_circular`) use positional args. This is non-obvious and easy to get wrong in a code generator that treats all parameters uniformly.

**How to avoid:**
- The component metadata registry JSON must encode constructor mode explicitly: `"argStyle": "positional"` vs `"argStyle": "keyword"` per parameter. This is already planned in SCAF-03.
- The code generator must read this metadata and emit the correct syntax. Write a dedicated `formatConstructorCall(component, params)` function with unit tests for every component type.
- Add a test suite that generates code for each of the 9 components and asserts the output matches a known-good `.jl` snippet character-by-character. This is cheap insurance.
- For Pump's dual-mode dispatch: `Pump(30000.0)` for scalar dP vs `Pump(; mdot0=0.5)` for fixed flow. The registry must encode both modes.

**Warning signs:**
- `MethodError: no method matching Pump(; dP_pump=30000.0)` when running generated code.
- Subtle: code generates but produces wrong physics (e.g., wrong constructor overload selected).

**Phase to address:**
Phase 33 (Scaffold) -- registry must encode constructor signatures correctly. Phase 36 (Code Generation) -- unit tests for every component's generated output.

---

### Pitfall 4: Code Generation Produces Unconnected or Misordered Systems

**What goes wrong:**
Generated code compiles but the MTK system is ill-posed: missing pressure anchor (system is underdetermined), missing `mtkcompile`, components listed in wrong order in `compose()`, or `connect()` calls reference nonexistent port names. The user gets a cryptic MTK/Sundials error instead of a helpful message.

**Why it happens:**
The code generator translates a visual graph into text. Unlike a compiler, it has no type checker -- it emits strings. If the graph has disconnected subgraphs, or the user forgot a boundary condition, or an edge connects incompatible port types, the generator happily produces syntactically valid but semantically broken Julia code.

**How to avoid:**
- Implement topology validation (VALD-01/02/03) BEFORE the code generator is considered complete. The validation layer should catch:
  - Unconnected mandatory ports (every FlowPort must have an edge).
  - No pressure anchor in the system (at least one `pump.inlet.P ~ value`).
  - No driving element (at least one Pump or Gravity).
  - Disconnected subgraphs (all nodes must be reachable).
- The code generator should emit components in a deterministic order (alphabetical by instance name, or topological). MTK does not care about declaration order, but deterministic output makes diffs meaningful and debugging easier.
- Always emit `mtkcompile(sys)` -- never let the user accidentally skip it.
- Emit comments in generated code: `# Boundary conditions`, `# Component instantiation`, `# Connections` -- makes it auditable.

**Warning signs:**
- Generated code runs but Sundials throws `SingularException` or `LinearAlgebra.SingularException`.
- MTK's `mtkcompile` reports "system is structurally singular" -- usually means missing equation (missing BC or missing connection).

**Phase to address:**
Phase 36 (Code Generation) for deterministic output. Phase 39 (Topology Validation) for pre-generation checks. Order matters: validation should ideally be built before or alongside code generation, not after.

---

### Pitfall 5: Tauri 2 Capability/Permission Denials at Runtime

**What goes wrong:**
The app builds and runs in dev mode, but the production build silently fails when trying to open a file dialog, read a file, or write a `.jl` export. The user clicks "Save" and nothing happens. No error is shown because the Tauri IPC call is rejected by the ACL system and the frontend does not handle the rejection.

**Why it happens:**
Tauri 2 replaced the v1 boolean allowlist with a fine-grained ACL system. Every plugin command (file dialog open, file system read, file system write) requires an explicit permission entry in `src-tauri/capabilities/*.json`. Developers test in dev mode where permissions may be more relaxed, or they add the permission for `open` but forget `save`, or they grant read but not write to the app data directory.

**How to avoid:**
- Create a single `src-tauri/capabilities/default.json` capability file during scaffold (Phase 33) that grants all permissions the app will ever need: `dialog:allow-open`, `dialog:allow-save`, `fs:allow-read-text-file`, `fs:allow-write-text-file`, `fs:allow-exists`, plus scope to `$APPDATA` and user-selected paths.
- Every Tauri IPC call in the frontend must have a `.catch()` handler that shows an error toast. Never fire-and-forget.
- Test the production build (not just dev mode) on both Windows and Linux before any milestone is considered complete. Dev mode and production mode have different permission enforcement.

**Warning signs:**
- Console error: `"[plugin-name].command not allowed"` in the webview developer console.
- File dialog opens but the subsequent read/write silently fails.
- Works in `npm run tauri dev` but breaks in the installed AppImage/.exe.

**Phase to address:**
Phase 33 (Scaffold) -- set up all capabilities. Phase 37 (Persistence) -- verify save/load works in production build.

---

### Pitfall 6: Thermal Port Array Handles Break ReactFlow's Connection Model

**What goes wrong:**
ChannelAndContacts has `thermal_left[1:n]` and `thermal_right[1:n]` -- arrays of ports where `n` is a user-configurable parameter. Standard ReactFlow handles are static (defined at component registration time). When `n` changes, the number of handles on the node must change dynamically. If implemented naively, existing edges connected to `thermal_left[3]` become invalid when `n` is reduced to 2, causing React errors or orphaned edges in the graph state.

**Why it happens:**
ReactFlow's handle system assumes handles are stable. Handle IDs are used as edge endpoints. When handles are added/removed dynamically, ReactFlow does not automatically clean up edges pointing to removed handles. The developer must manually prune invalid edges when `n` changes.

**How to avoid:**
- When `n` changes on a ChannelAndContacts or HeatDiffusion node, run an edge cleanup pass that removes any edges connected to handles with index > new `n`.
- Show a confirmation dialog if reducing `n` would disconnect existing thermal edges.
- Use handle IDs that encode the port type and index: `thermal_left_0`, `thermal_left_1`, etc. Parse these IDs in the code generator to emit `port(cac, :thermal_left, 1)` calls.
- Consider setting a minimum `n` (e.g., 1) and a maximum (e.g., 50) with validation to prevent degenerate cases.

**Warning signs:**
- React error: "Cannot find handle with id thermal_left_5" after reducing `n`.
- Edges visually attached to a position where no handle exists.
- Generated code references `port(cac, :thermal_left, 11)` when `n` is 10.

**Phase to address:**
Phase 40 (Thermal Composition) -- this is the phase that introduces dynamic port arrays. Must be designed carefully from the start.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store all state in `useState` instead of Zustand | Faster initial development, fewer dependencies | Stale closures, re-render cascades, no undo/redo support | Never -- Zustand is required for ReactFlow apps with parameter editing |
| Inline `nodeTypes`/`edgeTypes` inside JSX | Fewer files, "simpler" code | Causes full re-mount of all nodes on every parent render (React creates new component references) | Never -- define outside component or memoize with `useMemo` |
| Generate code as string concatenation | Quick to implement | Impossible to test individual parts, brittle to whitespace, no AST validation | MVP only -- migrate to template functions with unit tests by Phase 36 |
| Skip production build testing | Saves CI time | Permission/capability failures discovered by users, not developers | Never -- test production build on both platforms every phase |
| Hardcode component metadata in TypeScript | No JSON parsing overhead | Cannot add components without recompilation, violates SCAF-04 | Never -- registry JSON is a core requirement |
| Use `onNodesChange` for undo history | Captures every change "for free" | Captures drag micro-movements, history fills with noise, undo is unusable | Never -- use Zundo with selective recording (pause during drag, record on drop) |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| shadcn/ui Popover inside ReactFlow node | Popover portals to `document.body`, z-index conflicts with ReactFlow's canvas layers; popover appears behind nodes or is unclickable | Set `container` prop on the Popover to portal within the ReactFlow wrapper div; add `pointer-events-auto` to interactive elements inside portaled components |
| shadcn/ui Select inside ReactFlow custom node | Click on Select triggers ReactFlow's node selection/drag instead of opening the dropdown | Add `noDragHandle` class or `onPointerDown={(e) => e.stopPropagation()}` on interactive form elements inside custom nodes; use ReactFlow's `nodeDragThreshold` |
| shadcn/ui Dialog for confirmation prompts | Dialog backdrop blocks ReactFlow canvas interaction after dialog closes if cleanup is incomplete | Use the `onOpenChange` callback to properly reset state; prefer shadcn AlertDialog for destructive confirmations (it handles focus trapping correctly) |
| Tauri file dialog + ReactFlow state | User saves project, file dialog returns path, but by the time the save completes the ReactFlow state has changed (user kept editing during save) | Snapshot the graph state synchronously before opening the file dialog; write the snapshot, not the live state |
| Zustand + ReactFlow `useReactFlow` hook | Trying to call `useReactFlow()` inside a Zustand action (outside React component tree) fails because hooks cannot be called outside components | Pass ReactFlow instance methods to Zustand via `useEffect` initialization, or use `useStoreApi` for imperative access from within actions |
| ReactFlow minimap + custom node styling | Minimap renders simplified node shapes that ignore custom node CSS, making it look broken | Use ReactFlow's `MiniMap` `nodeColor` prop to set colors by node type; do not expect minimap to mirror custom node internals |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Subscribing sidebar to entire `nodes` array | Sidebar re-renders on every node drag (60fps of wasted renders); input fields lose focus | Use Zustand selector: `useStore(s => s.nodes.find(n => n.id === id)?.data)` | Noticeable with 10+ nodes |
| Regenerating Julia code on every keystroke in parameter fields | Code preview panel flickers; browser tab becomes unresponsive with complex graphs | Debounce code generation (300ms); or generate only on blur/explicit refresh | Noticeable with 15+ components |
| Storing full undo history without limits | Memory grows unbounded; after 30 min of editing, tab uses 500MB+ | Cap undo history at 50-100 entries; discard oldest on overflow | After ~200 undo steps |
| ReactFlow `fitView` on every node addition | Canvas jumps around as user adds nodes, breaking spatial memory | Only `fitView` on initial load and explicit user action (button click); use `setCenter` for new node focus | Annoying from node 3 onward |
| JSON serialization of large graph state for save | Save blocks the UI thread for 100ms+ with 50+ nodes and full parameter data | Use `structuredClone` + web worker for serialization; or serialize in Rust via Tauri command | 50+ nodes with complex params |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Writing user-supplied component names directly into generated Julia code without sanitization | Code injection: a name like `pump; rm -rf /` would execute when the `.jl` file is run | Validate names against Julia identifier regex `^[a-zA-Z_][a-zA-Z0-9_]*$`; reject anything else. CODE-07 covers this. |
| Storing recent file paths in localStorage without sanitization | Path traversal in display; minor risk since paths come from OS dialog | Always display paths via `<span>` not `dangerouslySetInnerHTML`; truncate long paths |
| Allowing arbitrary file extensions in export dialog | User accidentally overwrites a system file | Default to `.jl` extension; use Tauri dialog `filters` to restrict to `.jl` and `.streamgui` |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No visual feedback when code generation has errors | User exports a `.jl` file, runs it, gets a wall of Julia errors with no connection to what they did in the GUI | Show topology validation warnings as colored badges on nodes and a banner; make the export button disabled or orange when warnings exist |
| Port handles too small to click | Users struggle to start edge connections, especially on high-DPI displays | Make handles at least 12x12px with an invisible 20x20px hit area; show a tooltip on hover identifying the port |
| Undo undoes too much or too little | User expects undo to revert "add node" but it reverts 15 micro-position-changes from dragging | Use Zundo with selective recording: pause history during `onNodeDragStart`, resume on `onNodeDragStop`; record discrete actions (add, delete, parameter change) explicitly |
| No indication of which node is selected | User clicks a node, opens sidebar, edits parameters, but is not sure which node they are editing | Highlight selected node with a visible border/glow; show node name prominently at top of sidebar |
| Boundary condition panel is hidden or non-obvious | User creates a valid-looking graph but generated code is missing `pump.inlet.P ~ 1.0e5`, causing MTK to fail | Show a dedicated "Boundary Conditions" section in the sidebar or as a canvas overlay; pre-populate with the most common BC (pressure anchor) when a Pump is added |

## "Looks Done But Isn't" Checklist

- [ ] **Code generation:** Often missing `using STREAM` import at top of generated file -- verify generated code is a complete runnable script, not just the system composition
- [ ] **Code generation:** Often missing `using ModelingToolkit: t` -- the `t` independent variable must be imported or defined
- [ ] **Boundary conditions:** Often missing pressure anchor `pump.inlet.P ~ 1.0e5` -- verify generated code always includes at least one pressure reference
- [ ] **Save/load:** Often missing canvas viewport state (zoom, pan position) -- verify opening a saved project restores the exact visual layout
- [ ] **Save/load:** Often missing the STREAM.jl version tag -- verify `.streamgui` files record which library version the project targets
- [ ] **Undo/redo:** Often missing edge deletion from undo stack -- verify that deleting an edge can be undone, not just node operations
- [ ] **Parameter editing:** Often missing validation for empty fields -- verify that clearing a required field shows an error, not silently sets the value to 0 or NaN
- [ ] **Cross-platform:** Often missing high-DPI scaling test -- verify nodes, handles, and text are properly sized on 4K displays (Windows scaling 150%/200%)
- [ ] **Production build:** Often missing the capability for `fs:allow-write-text-file` -- verify `.jl` export works in the installed app, not just dev mode
- [ ] **Thermal composition:** Often missing edge cleanup when `n` changes -- verify reducing cell count removes orphaned thermal edges

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong constructor signatures in generated code | LOW | Fix the registry JSON entries and `formatConstructorCall`; add regression tests per component |
| Stale closure bugs in sidebar | MEDIUM | Migrate from `useState` to Zustand store; refactor all callbacks to use selectors. Harder if deeply embedded. |
| Re-render cascade (no `React.memo`) | LOW-MEDIUM | Add `React.memo` wrappers to all custom node/edge components; define `nodeTypes`/`edgeTypes` outside component. Mechanical fix. |
| Missing Tauri capabilities in production | LOW | Add missing permissions to `capabilities/default.json`; rebuild. No code changes needed. |
| Undo history full of drag noise | MEDIUM | Integrate Zundo properly with pause/resume around drag events; may need to clear existing history data format |
| Thermal port array handle orphaning | MEDIUM | Add edge cleanup logic to `n`-change handler; migrate existing saved projects by running cleanup on load |
| Code generation string concatenation spaghetti | HIGH | Rewrite code generator as structured template functions with AST-like intermediate representation; significant refactor if deferred too long |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Stale closures in custom nodes | Phase 34 (Canvas) | React DevTools Profiler shows no stale state in callbacks; parameter edit from sidebar persists correctly |
| Re-render cascades | Phase 34 (Canvas) | Profiler shows only moved node re-renders during drag; sidebar does not re-render on unrelated node movement |
| Wrong constructor signatures | Phase 33 (Scaffold, registry) + Phase 36 (Code Gen) | Unit test per component: generated snippet matches known-good Julia code |
| Unconnected/misordered systems | Phase 36 (Code Gen) + Phase 39 (Validation) | Generate code for 3 reference topologies (simple loop, vertical loop with gravity, two-plate assembly); run through Julia and verify `mtkcompile` succeeds |
| Tauri capability denials | Phase 33 (Scaffold) + Phase 37 (Persistence) | Production build smoke test: open file, save file, export `.jl` on both Windows and Linux |
| shadcn/ui portal z-index conflicts | Phase 35 (Parameter Editing) | Manual test: open a Select dropdown inside a custom node; verify it renders above the canvas and is clickable |
| Thermal port array handle orphaning | Phase 40 (Thermal Composition) | Automated test: create ChannelAndContacts with n=5, connect thermal edges, reduce n to 3, verify edges to indices 4-5 are removed |
| Undo/redo noise from dragging | Phase 34 (Canvas, CANV-07) | Undo after drag-then-parameter-edit reverts the parameter edit (not the drag); undo after add-node removes the node |
| Cross-platform path handling | Phase 37 (Persistence) | Save a project on Windows with a path containing spaces and backslashes; open on Linux; verify it loads without error |
| Code injection via component names | Phase 36 (Code Gen, CODE-07) | Attempt to set component name to `pump; println("injected")`; verify it is rejected by the identifier validator |
| Linux AppImage WebKitGTK dependency | Phase 33 (Scaffold, SCAF-02) | Build AppImage on Ubuntu 22.04; run on Ubuntu 22.04 and 24.04; verify webview loads |

## Platform-Specific Pitfalls

### Windows

| Issue | Detail | Mitigation |
|-------|--------|------------|
| File dialog `defaultPath` ignores forward slashes | Tauri's dialog plugin on Windows requires backslash (`\`) separators in `defaultPath`; forward slashes cause the dialog to open in an unexpected directory | Use `path.sep` or Rust's `PathBuf` normalization; never hardcode `/` in paths sent to the dialog API |
| WebView2 auto-updates | Microsoft Edge WebView2 updates independently of the app; a new WebView2 version could break CSS or JS behavior | Pin minimum WebView2 version in `tauri.conf.json` if needed; test with the latest Edge stable before releases |
| High-DPI scaling (150%/200%) | Custom nodes, handles, and text may appear blurry or misaligned on scaled displays | Use CSS `rem` units and SVG for icons; test at 100%, 150%, and 200% scaling in Windows Display Settings |

### Linux

| Issue | Detail | Mitigation |
|-------|--------|------------|
| WebKitGTK version varies by distro | Ubuntu 22.04 ships WebKitGTK 2.36; Ubuntu 24.04 ships 2.44; CSS features and JS API support differ | Target WebKitGTK 2.36+ as minimum; avoid bleeding-edge CSS (e.g., CSS nesting, `:has()` selector) that requires newer WebKit |
| AppImage glibc compatibility | AppImage built on Ubuntu 24.04 will not run on Ubuntu 22.04 due to glibc version mismatch | Build AppImage on the oldest supported distro (Ubuntu 22.04) using Docker or CI |
| Missing `libwebkit2gtk-4.1-dev` on build machines | Tauri 2 requires `libwebkit2gtk-4.1-dev` (not 4.0); some CI images and older distros only have 4.0 | Document build prerequisites; use a Docker image with all Tauri Linux deps pre-installed |
| AppImage missing `libwebkit2gtkinjectedbundle.so` | Known Tauri bug: the injected bundle `.so` is not included in AppImage, causing runtime warnings | Monitor tauri-apps/tauri#12463 for a fix; the warning is cosmetic for most use cases but may affect some WebKit features |

## Sources

- [ReactFlow: State Management (official docs)](https://reactflow.dev/learn/advanced-use/state-management)
- [ReactFlow: Performance (official docs)](https://reactflow.dev/learn/advanced-use/performance)
- [ReactFlow: Common Errors](https://reactflow.dev/learn/troubleshooting/common-errors)
- [ReactFlow: Connection Validation](https://reactflow.dev/examples/interaction/validation)
- [ReactFlow: Undo/Redo Example](https://reactflow.dev/examples/interaction/undo-redo)
- [Tauri 2: Inter-Process Communication](https://v2.tauri.app/concept/inter-process-communication/)
- [Tauri 2: Capabilities](https://v2.tauri.app/security/capabilities/)
- [Tauri 2: Dialog Plugin](https://v2.tauri.app/plugin/dialog/)
- [Tauri 2: File System Plugin](https://v2.tauri.app/plugin/file-system/)
- [tauri-apps/tauri#8074 -- defaultPath ignores forward slashes on Windows](https://github.com/tauri-apps/tauri/issues/8074)
- [tauri-apps/tauri#12463 -- AppImage missing libwebkit2gtkinjectedbundle.so](https://github.com/tauri-apps/tauri/issues/12463)
- [tauri-apps/tauri#14796 -- AppImage linuxdeploy failures](https://github.com/tauri-apps/tauri/issues/14796)
- [tauri-apps/discussions#10026 -- Linux AppImage bundling with WebKitGTK](https://github.com/orgs/tauri-apps/discussions/10026)
- [Radix UI primitives#1317 -- Z-index issues with Dialog.Portal + Popover](https://github.com/radix-ui/primitives/issues/1317)
- [shadcn-ui/ui#1511 -- Popover not working in Modal Dialog](https://github.com/shadcn-ui/ui/issues/1511)
- [Zundo -- Zustand undo/redo middleware](https://github.com/charkour/zundo)
- [Synergy Codes -- ReactFlow State Management (ebook)](https://www.synergycodes.com/blog/state-management-in-react-flow)
- [Medium -- Optimize React Flow Performance](https://medium.com/@lukasz.jazwa_32493/the-ultimate-guide-to-optimize-react-flow-project-performance-42f4297b2b7b)

---
*Pitfalls research for: STREAM Composer GUI (Tauri 2 + React + ReactFlow + Julia code generation)*
*Researched: 2026-04-01*
