import { useCallback, useEffect, useMemo, useRef } from "react";
import {
  ReactFlow,
  Background,
  BackgroundVariant,
  ConnectionLineType,
  SelectionMode,
  useReactFlow,
  type Connection,
  type Edge,
  type Node,
  type NodeTypes,
  type EdgeTypes,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import useStore from "../store/useStore";
import type { StreamNodeData } from "../store/useStore";
import { getComponent } from "../registry";
import {
  type LayerKey,
  getComponentLayers,
  isNodeVisible,
  isEdgeDimmed,
} from "../lib/layers";
import StreamNode from "./StreamNode";
import HydraulicEdge from "./HydraulicEdge";
import BCEdge from "./BCEdge";
import WelcomeOverlay from "./WelcomeOverlay";
import { useRightClickContextMenu } from "@/hooks/useRightClickContextMenu";
import { portType } from "@/lib/validation/rules/portType";
import type { ValidationSnapshot } from "@/lib/validation/snapshot";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
} from "@/components/ui/dropdown-menu";
import NodeContextMenu from "./canvasMenus/NodeContextMenu";
import EdgeContextMenu from "./canvasMenus/EdgeContextMenu";
import CanvasContextMenu from "./canvasMenus/CanvasContextMenu";
import SnapToGridButton from "./canvasMenus/SnapToGridButton";
import ZoomInButton from "./canvasMenus/ZoomInButton";
import ZoomOutButton from "./canvasMenus/ZoomOutButton";
import FitViewButton from "./canvasMenus/FitViewButton";
import InteractiveLockButton from "./canvasMenus/InteractiveLockButton";

export function getPortType(nodeId: string, handleId: string): string | null {
  const node = useStore.getState().nodes.find((n) => n.id === nodeId);
  if (!node) return null;
  const comp = getComponent((node.data as unknown as StreamNodeData).componentId);
  if (!comp) return null;
  const port = comp.ports.find((p) => p.name === handleId);
  return port?.type ?? null;
}

const nodeTypes: NodeTypes = {
  streamNode: StreamNode,
};

const edgeTypes: EdgeTypes = {
  hydraulicEdge: HydraulicEdge,
  bcEdge: BCEdge,
};

const defaultEdgeOptions = { type: "smoothstep" };

interface CanvasPanelProps {
  resolvedTheme?: "light" | "dark";
}

export default function CanvasPanel({ resolvedTheme }: CanvasPanelProps = {}) {
  // PERF — destructuring `useStore()` with NO selector subscribes to the
  // entire store, re-rendering CanvasPanel (and ReactFlow inside it) on
  // any store change anywhere — hoveredSourceIds toggles, pinned-id flips,
  // BC-mode mutations, every unrelated slice. Split into individual
  // selectors: actions (`onNodesChange`, `onEdgesChange`, `addNode`,
  // `addEdge`, `selectNode`) are stable refs by zustand contract, and
  // `nodes`/`edges` are the live arrays ReactFlow needs as props. See
  // gui/PERFORMANCE.md §1.
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const onNodesChange = useStore((s) => s.onNodesChange);
  const onEdgesChange = useStore((s) => s.onEdgesChange);
  const addNode = useStore((s) => s.addNode);
  const addEdge = useStore((s) => s.addEdge);
  const selectNode = useStore((s) => s.selectNode);
  const activeLayers = useStore((s) => s.activeLayers);
  const hideOffLayer = useStore((s) => s.hideOffLayer);
  // Phase 72 — subscribe to hover/pin sets so the enrichedEdges memo can
  // bump zIndex on code-link active edges (SVG paint order is DOM order;
  // xyflow's `Edge.zIndex` is the supported mechanism to reorder). The
  // PERF comment above warns against whole-store subscriptions — these
  // SELECTIVE subscriptions are intentional and the re-render frequency
  // is bounded (hover toggles fire on code sub-block mouseenter/leave;
  // pin toggles on click). Compared to node-drag (~60 Hz), this is rare.
  const hoveredSourceIds = useStore((s) => s.hoveredSourceIds);
  const pinnedSourceIds = useStore((s) => s.pinnedSourceIds);
  // Phase 65 D-09: snap-to-grid state read from store
  const snapEnabled = useStore((s) => s.snapToGrid);
  // Phase 65 Plan 13: interactive lock — when true, all interactions disabled.
  const interactiveLocked = useStore((s) => s.interactiveLocked);
  // B3 guard: useReactFlow is called ONCE at the component top level — never
  // inside callbacks or useEffect. setNodes/setEdges/setCenter/getNode are
  // stable identities per @xyflow/react v12 docs.
  const { screenToFlowPosition, setNodes, setEdges, setCenter, getNode, fitBounds } = useReactFlow();
  const containerRef = useRef<HTMLDivElement>(null);

  // Phase 65 Plan 03: right-click pan-vs-context-menu disambiguation (D-12).
  // rcMenu.state is consumed by Plan 05 — no menu UI is rendered here.
  const rcMenu = useRightClickContextMenu();

  // Phase 68 Plan 03: per-node enrichment for the 4-layer independent-toggle
  // API. Visibility is "any of the node's layers active" (D-02); off-layer
  // nodes are either hidden (hideOffLayer=true) or dimmed + locked
  // non-interactive (selectable/draggable false) in dim mode. Nodes with no
  // layer association (e.g. Resources) are always visible.
  const enrichedNodes = useMemo(() => {
    return nodes.map((node) => {
      const nodeData = node.data as unknown as StreamNodeData;
      const comp = getComponent(nodeData.componentId);
      if (!comp) return node;
      if (isNodeVisible(comp, activeLayers)) return node;
      if (hideOffLayer) {
        return { ...node, hidden: true };
      }
      return {
        ...node,
        style: {
          ...node.style,
          opacity: 0.2,
          pointerEvents: "none" as const,
          transition: "opacity 150ms ease",
        },
        selectable: false,
        draggable: false,
      };
    });
  }, [nodes, activeLayers, hideOffLayer]);

  // Phase 68 Plan 03: per-edge enrichment. Edges follow their OWN layer (D-04)
  // — derive LayerKey from `edge.type` ("hydraulicEdge" → Hydraulic,
  // "bcEdge" → Sources, anything else → Thermal — the thermal styling pass in
  // useStore.addEdge does not set a custom type, so it's the residual case).
  // In hide mode also suppress edges whose BOTH endpoints are hidden to avoid
  // phantom dangling edges (Pitfall 5).
  const enrichedEdges = useMemo(() => {
    const hiddenNodeIds = new Set<string>();
    if (hideOffLayer) {
      for (const n of enrichedNodes) {
        if ((n as { hidden?: boolean }).hidden) hiddenNodeIds.add(n.id);
      }
    }
    return edges.map((edge) => {
      let edgeLayerKey: LayerKey | null;
      if (edge.type === "hydraulicEdge") edgeLayerKey = "Hydraulic";
      else if (edge.type === "bcEdge") edgeLayerKey = "Sources";
      else edgeLayerKey = "Thermal";
      const dimmed = isEdgeDimmed(edgeLayerKey, activeLayers);
      // Phase 72 — code-link z-order bump. When BOTH endpoint nodes are in
      // the hovered or pinned source-id set, this edge is in the active
      // state (matches BCEdge / HydraulicEdge's per-component check).
      // Bumping zIndex above xyflow's default 0 (selected = 1000) ensures
      // the marching-ants animation is never visually obscured by an
      // overlapping inactive edge. Without this, when two edges share an
      // endpoint or overlap (e.g. parallel bottom-port connections),
      // whichever sibling renders later in the SVG paints on top — the
      // active edge's dashes appeared to flicker behind the static line.
      const isCodeActive =
        (hoveredSourceIds.has(edge.source) && hoveredSourceIds.has(edge.target)) ||
        (pinnedSourceIds.has(edge.source) && pinnedSourceIds.has(edge.target));
      const zIndexBump = isCodeActive ? { zIndex: 1500 } : undefined;
      if (hideOffLayer) {
        const endpointsHidden =
          hiddenNodeIds.has(edge.source) && hiddenNodeIds.has(edge.target);
        if (dimmed || endpointsHidden) {
          return { ...edge, hidden: true };
        }
        return zIndexBump ? { ...edge, ...zIndexBump } : edge;
      }
      if (!dimmed) return zIndexBump ? { ...edge, ...zIndexBump } : edge;
      return {
        ...edge,
        ...zIndexBump,
        style: {
          ...edge.style,
          opacity: 0.15,
          transition: "opacity 150ms ease",
        },
      };
    });
  }, [
    edges,
    activeLayers,
    hideOffLayer,
    enrichedNodes,
    hoveredSourceIds,
    pinnedSourceIds,
  ]);

  const onDrop = useCallback(
    async (event: React.DragEvent) => {
      event.preventDefault();

      // Phase 70 D-16 — preset drop: bbox-center at cursor on release.
      // loadPresetAtPosition uses the anchor as the bbox-center target and
      // subtracts layout half-extents internally (plan 70-03, action B step 4).
      const presetRaw = event.dataTransfer.getData("application/stream-preset");
      if (presetRaw) {
        try {
          const payload = JSON.parse(presetRaw) as {
            filePath: string;
            store: "project" | "library";
          };
          const flowPos = screenToFlowPosition({
            x: event.clientX,
            y: event.clientY,
          });
          await useStore.getState().loadPresetAtPosition(payload.filePath, {
            x: flowPos.x,
            y: flowPos.y,
          });
        } catch (err) {
          console.error("[CanvasPanel] Preset drop failed", err);
        }
        return;
      }

      const componentId = event.dataTransfer.getData(
        "application/streamcomponent",
      );
      if (!componentId) return;
      const position = screenToFlowPosition({
        x: event.clientX,
        y: event.clientY,
      });
      addNode(componentId, position);
      // Defer focus past the browser's own drag-end focus bookkeeping.
      setTimeout(() => containerRef.current?.focus(), 0);
    },
    [screenToFlowPosition, addNode],
  );

  // Snapshot canvas state at drag start so the entire move is one undo step.
  const onNodeDragStart = useCallback(() => {
    useStore.getState()._pushSnapshot();
  }, []);

  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onConnect = useCallback(
    (connection: Connection) => {
      addEdge(connection);
      // Phase 68 Plan 03: layer-aware connect (D-04 forgiving rule). After the
      // connection is added, walk both endpoints and auto-enable any layer
      // they belong to that is currently off. Never blocks the connection;
      // store is read via getState() so the callback is stable.
      const state = useStore.getState();
      const currentNodes = state.nodes;
      const currentActive = state.activeLayers;
      const setLayerVisible = state.setLayerVisible;
      for (const nodeId of [connection.source, connection.target]) {
        if (!nodeId) continue;
        const node = currentNodes.find((n) => n.id === nodeId);
        if (!node) continue;
        const comp = getComponent(
          (node.data as unknown as StreamNodeData).componentId,
        );
        if (!comp) continue;
        for (const key of getComponentLayers(comp)) {
          if (!currentActive[key]) setLayerVisible(key, true);
        }
      }
    },
    [addEdge],
  );

  const onNodeClick = useCallback(
    (_event: React.MouseEvent, node: Node) => {
      // Phase 68 Plan 03: the off-layer dim guard is gone — off-layer nodes
      // now carry `selectable: false` from `enrichedNodes`, so ReactFlow
      // never fires this handler for them. No `isNodeDimmed(...)` check
      // needed here anymore.
      selectNode(node.id);
    },
    [selectNode],
  );

  const onPaneClick = useCallback(() => {
    selectNode(null);
  }, [selectNode]);

  const isValidConnection = useCallback((connection: Edge | Connection) => {
    if (
      !connection.source ||
      !connection.target ||
      !connection.sourceHandle ||
      !connection.targetHandle
    ) {
      return false;
    }

    const s = useStore.getState();
    const srcNode = s.nodes.find((n) => n.id === connection.source);
    const tgtNode = s.nodes.find((n) => n.id === connection.target);
    if (!srcNode || !tgtNode) return false;

    // Build a synthetic single-edge snapshot for one-shot portType validation.
    // D-19: do NOT run the full validator suite here — only the portType rule.
    // (RESEARCH Pitfall 2: full runValidators would call loopTraversal on every hover tick.)
    const syntheticEdge: Edge = {
      id: "__pending__",
      source: connection.source,
      target: connection.target,
      sourceHandle: connection.sourceHandle,
      targetHandle: connection.targetHandle,
    };
    const snapshot: ValidationSnapshot = {
      nodes: [srcNode, tgtNode],
      edges: [syntheticEdge],
      anchors: {},  // not used by portType
      bcMode: s.bcMode,
      resources: s.resources,
      getComponentDef: getComponent,
    };
    const results = portType.run(snapshot);
    return results.length === 0;
  }, []);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
        e.preventDefault();
        useStore.getState().undo();
      }
      if (
        (e.ctrlKey || e.metaKey) &&
        ((e.key === "z" && e.shiftKey) || e.key === "y")
      ) {
        e.preventDefault();
        useStore.getState().redo();
      }
      // Phase 65 Plan 04: clipboard shortcuts (D-15, D-16). Skipped when text input has focus (above).
      if ((e.ctrlKey || e.metaKey) && e.key === "c") {
        const target = e.target as HTMLElement;
        if (
          target instanceof HTMLInputElement ||
          target instanceof HTMLTextAreaElement ||
          target instanceof HTMLSelectElement ||
          target.isContentEditable
        ) {
          // fall through to browser-native copy
        } else {
          e.preventDefault();
          void useStore.getState().copySelection();
        }
      }
      if ((e.ctrlKey || e.metaKey) && e.key === "x") {
        const target = e.target as HTMLElement;
        if (
          !(target instanceof HTMLInputElement) &&
          !(target instanceof HTMLTextAreaElement) &&
          !(target instanceof HTMLSelectElement) &&
          !target.isContentEditable
        ) {
          e.preventDefault();
          void useStore.getState().cutSelection();
        }
      }
      if ((e.ctrlKey || e.metaKey) && e.key === "v") {
        const target = e.target as HTMLElement;
        if (
          !(target instanceof HTMLInputElement) &&
          !(target instanceof HTMLTextAreaElement) &&
          !(target instanceof HTMLSelectElement) &&
          !target.isContentEditable
        ) {
          e.preventDefault();
          void useStore.getState().pasteFromClipboard();
        }
      }
      if ((e.ctrlKey || e.metaKey) && e.key === "d") {
        const target = e.target as HTMLElement;
        if (
          !(target instanceof HTMLInputElement) &&
          !(target instanceof HTMLTextAreaElement) &&
          !(target instanceof HTMLSelectElement) &&
          !target.isContentEditable
        ) {
          e.preventDefault();
          useStore.getState().duplicateSelection();
        }
      }
      // Phase 68 D-06: the Tab→cycleLayer shortcut is removed. The floating
      // Layers chip is the sole layer-toggle UI; Tab now follows browser
      // default focus traversal.
      // Esc clears selection (nodes AND edges); skip when a text input has focus
      if (e.key === "Escape") {
        const target = e.target as HTMLElement;
        if (
          target instanceof HTMLInputElement ||
          target instanceof HTMLTextAreaElement ||
          target instanceof HTMLSelectElement ||
          target.isContentEditable
        ) {
          return;
        }
        useStore.getState().selectNode(null);
        // setNodes/setEdges from useReactFlow are stable identities — safe to omit from deps
        setNodes((ns) => ns.map((n) => (n.selected ? { ...n, selected: false } : n)));
        setEdges((es) => es.map((edge) => (edge.selected ? { ...edge, selected: false } : edge)));
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // setNodes/setEdges from useReactFlow are stable identities — safe to omit from deps

  // Click-to-focus from ValidationPanel rows. Two modes:
  //
  //   SINGLE-NODE result (1 node target) → pan to that node and play the
  //   600 ms one-shot .validation-flash on it. Existing behavior.
  //
  //   MULTI-NODE result (≥2 node targets, e.g. gravity_sum_per_loop) → treat
  //   as a loop/subgraph TRACE:
  //     - fitBounds to enclose every node target
  //     - apply .validation-flash-persistent to every node target (steady
  //       severity-tinted pulse, no auto-clear)
  //     - apply .validation-flow-trace to every edge target (marching-ants
  //       flow direction)
  //     - persist until the user clicks anywhere on the canvas OR a different
  //       result row replaces the trace
  //
  // Severity → trace color via inline `--validation-trace-color`:
  //   error → --destructive, warning → --color-warning, info → --color-info.
  useEffect(() => {
    // Module-scoped active trace state — cleared on canvas click or replaced
    // by a new focus event. Stored on window so the click-clear listener
    // (also installed in this effect) sees the same state without React deps.
    let activeTrace: { nodeIds: string[]; edgeIds: string[] } | null = null;

    function clearActiveTrace() {
      if (!activeTrace) return;
      for (const nodeId of activeTrace.nodeIds) {
        const el = document.querySelector<HTMLElement>(`[data-stream-node-id="${nodeId}"]`);
        if (!el) continue;
        el.classList.remove("validation-flash-persistent");
        el.style.removeProperty("--validation-trace-color");
      }
      for (const edgeId of activeTrace.edgeIds) {
        const el = document.querySelector<HTMLElement>(
          `.react-flow__edge[data-id="${edgeId}"]`,
        );
        if (!el) continue;
        el.classList.remove("validation-flow-trace");
        el.style.removeProperty("--validation-trace-color");
      }
      activeTrace = null;
    }

    function applyTrace(
      nodeIds: string[],
      edgeIds: string[],
      severity: "error" | "warning" | "info",
    ) {
      const colorVar =
        severity === "error"
          ? "var(--destructive)"
          : severity === "info"
            ? "var(--color-info)"
            : "var(--color-warning)";

      for (const nodeId of nodeIds) {
        const el = document.querySelector<HTMLElement>(`[data-stream-node-id="${nodeId}"]`);
        if (!el) continue;
        el.style.setProperty("--validation-trace-color", colorVar);
        el.classList.add("validation-flash-persistent");
      }
      for (const edgeId of edgeIds) {
        const el = document.querySelector<HTMLElement>(
          `.react-flow__edge[data-id="${edgeId}"]`,
        );
        if (!el) continue;
        el.style.setProperty("--validation-trace-color", colorVar);
        el.classList.add("validation-flow-trace");
      }
      activeTrace = { nodeIds, edgeIds };
    }

    const onFocusResult = (e: Event) => {
      const ce = e as CustomEvent<{ result: import("@/lib/validation/types").ValidationResult }>;
      const result = ce.detail?.result;
      if (!result) return;

      const nodeIds: string[] = [];
      const edgeIds: string[] = [];
      for (const target of result.targets) {
        if (target.kind === "node" || target.kind === "port") {
          if (!nodeIds.includes(target.nodeId)) nodeIds.push(target.nodeId);
        } else if (target.kind === "edge") {
          if (!edgeIds.includes(target.edgeId)) edgeIds.push(target.edgeId);
        }
      }

      // Always clear any previous trace before starting a new one.
      clearActiveTrace();

      if (nodeIds.length === 0) return;

      // Compute bounding box from node positions.
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
      let validCount = 0;
      for (const nodeId of nodeIds) {
        const n = getNode(nodeId);
        if (!n) continue;
        const x = n.position.x;
        const y = n.position.y;
        const w = (n as { measured?: { width?: number } }).measured?.width ?? 120;
        const h = (n as { measured?: { height?: number } }).measured?.height ?? 40;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x + w);
        maxY = Math.max(maxY, y + h);
        validCount++;
      }

      if (validCount === 0) return;

      const isMulti = nodeIds.length >= 2;

      if (isMulti) {
        // Multi-target: zoom-to-fit the entire trace + persistent highlight.
        const pad = 80;
        fitBounds(
          {
            x: minX - pad,
            y: minY - pad,
            width: maxX - minX + 2 * pad,
            height: maxY - minY + 2 * pad,
          },
          { duration: 300 },
        );
        // RAF so the xyflow nodes have measured / rendered before we attach
        // classes (otherwise the data-id elements may not yet exist).
        requestAnimationFrame(() => applyTrace(nodeIds, edgeIds, result.severity));
      } else {
        // Single-target: preserve existing pan + one-shot flash behavior.
        const cx = (minX + maxX) / 2;
        const cy = (minY + maxY) / 2;
        setCenter(cx, cy, { duration: 300 });
        window.dispatchEvent(
          new CustomEvent("stream:node-flash", { detail: { nodeIds } }),
        );
      }
    };

    const onNodeFlash = (e: Event) => {
      const ce = e as CustomEvent<{ nodeIds: string[] }>;
      const nodeIds = ce.detail?.nodeIds ?? [];
      for (const nodeId of nodeIds) {
        const el = document.querySelector(`[data-stream-node-id="${nodeId}"]`);
        if (!el) continue;
        el.classList.add("validation-flash");
        setTimeout(() => el.classList.remove("validation-flash"), 700);
      }
    };

    // Canvas-click clear: any click on the canvas surface (pane, node, edge)
    // collapses the persistent trace. The clear listener is on the document
    // because xyflow's pane/node/edge handlers fire after their own state
    // updates and we want this to be cheap + universal.
    const onCanvasClick = (ev: MouseEvent) => {
      if (!activeTrace) return;
      // Only clear when the click is inside the ReactFlow viewport.
      const target = ev.target as Element | null;
      if (target?.closest(".react-flow")) {
        clearActiveTrace();
      }
    };

    window.addEventListener("stream:focus-validation-result", onFocusResult as EventListener);
    window.addEventListener("stream:node-flash", onNodeFlash as EventListener);
    document.addEventListener("mousedown", onCanvasClick, true);
    return () => {
      clearActiveTrace();
      window.removeEventListener("stream:focus-validation-result", onFocusResult as EventListener);
      window.removeEventListener("stream:node-flash", onNodeFlash as EventListener);
      document.removeEventListener("mousedown", onCanvasClick, true);
    };
    // xyflow setters (setCenter / fitBounds / getNode) are stable identities.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Phase 65 Plan 05: convert rcMenu screen coords to flow coords for pane menus.
  // D-11: we use Popover as the host (NOT a controlled ContextMenu.Root) because
  // Radix ContextMenu.Root does not support a controlled `open` at arbitrary screen coords.
  // ContextMenuItem / ContextMenuSub* items are used inside PopoverContent for visual parity.
  const flowPosition =
    rcMenu.state.kind === "pane"
      ? screenToFlowPosition({ x: rcMenu.state.screenX, y: rcMenu.state.screenY })
      : null;

  return (
    <div ref={containerRef} className="flex-1 h-full relative focus:outline-none bg-canvas" tabIndex={-1}>
      {/* Phase 72 — custom SVG marker definitions for hydraulic edge
          arrowheads. Defined ONCE here so every HydraulicEdge instance
          can reference them by URL. `markerUnits="userSpaceOnUse"` is
          the load-bearing attribute: it decouples marker size from the
          edge's stroke-width, so the arrow stays fixed when an edge
          fattens for hover/pin/code-link active states. xyflow's default
          `MarkerType.ArrowClosed` uses `markerUnits="strokeWidth"`
          (scaling with the stroke), which is the wrong behavior for our
          code-link UX. fill = --muted-foreground always (the arrow is
          structural, NOT a state signal — only the stroke conveys state).
          width=8 / height=8 user units = ~12 px on a normal stroke,
          matching the prior MarkerType.ArrowClosed visual weight. */}
      <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden>
        <defs>
          <marker
            id="stream-hydraulic-arrow"
            viewBox="0 0 12 12"
            refX="11"
            refY="6"
            markerUnits="userSpaceOnUse"
            markerWidth="12"
            markerHeight="12"
            orient="auto"
          >
            <path d="M 0 0 L 12 6 L 0 12 z" fill="var(--muted-foreground)" />
          </marker>
        </defs>
      </svg>
      <ReactFlow
        colorMode={resolvedTheme === "dark" ? "dark" : "light"}
        // Phase 72 — drop the hardcoded `--xy-background-color: #282c34` dark
        // override (One Dark Pro lineage). The parent wrapper carries
        // `bg-canvas` which tracks the new `--canvas` token (dark + light);
        // ReactFlow's pane is transparent over that.
        style={{ "--xy-background-color": "transparent" } as React.CSSProperties}
        // Hide the bottom-right "React Flow" attribution. We're not under
        // a Pro license (and don't need one for this — the attribution is a
        // visual nuisance for a scientific tool, not a meaningful brand
        // touchpoint). xyflow accepts this opt-out on the open-source tier
        // per their docs; if they ever revoke that, we'll revisit.
        proOptions={{ hideAttribution: true }}
        nodes={enrichedNodes}
        edges={enrichedEdges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onDrop={onDrop}
        onDragOver={onDragOver}
        onEdgeContextMenu={rcMenu.onEdgeContextMenu}
        onNodeClick={onNodeClick}
        onNodeContextMenu={rcMenu.onNodeContextMenu}
        onNodeDragStart={onNodeDragStart}
        onPaneClick={onPaneClick}
        onPaneContextMenu={rcMenu.onPaneContextMenu}
        isValidConnection={isValidConnection}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        defaultEdgeOptions={defaultEdgeOptions}
        connectionLineType={ConnectionLineType.SmoothStep}
        // Phase 65 Plan 13: interactiveLocked drives interaction props. When true,
        // node drag / connect / select are disabled and panOnDrag is fully off
        // (selection-on-drag remains but elementsSelectable=false makes it a no-op).
        nodesDraggable={!interactiveLocked}
        nodesConnectable={!interactiveLocked}
        elementsSelectable={!interactiveLocked}
        panOnDrag={interactiveLocked ? false : [2]}
        selectionOnDrag
        selectionMode={SelectionMode.Partial}
        deleteKeyCode={["Delete", "Backspace"]} // Del/Backspace deletes nodes AND edges via ReactFlow built-in — closes v0.8 user-list item #2
        // Phase 65 D-08/D-09: 16px fixed grid snapping via ReactFlow built-in props
        snapToGrid={snapEnabled}
        snapGrid={[16, 16]}
        fitView
      >
        {/* Phase 72 — CAD/Houdini-style grid lines replace the ReactFlow
            default dot pattern. Two stacked Background layers give a
            dual-tier grid: minor every 12 px, major every 24 px (xyflow
            scales both with zoom). Colors resolve via CSS custom
            properties — they swap automatically with dark/light theme. */}
        <Background
          id="grid-minor"
          variant={BackgroundVariant.Lines}
          gap={12}
          lineWidth={1}
          color="var(--color-canvas-grid-minor)"
        />
        <Background
          id="grid-major"
          variant={BackgroundVariant.Lines}
          gap={24}
          lineWidth={1}
          color="var(--color-canvas-grid-major)"
        />
      </ReactFlow>
      {/* Phase 65 Plan 13: top-right overlay — Zoom/Fit/Lock replace ReactFlow built-in Controls panel; SnapToGridButton from Plan 06.
          Phase 68 UAT 2026-05-17 — LayersChip moved out of this overlay
          into the docked left-sidebar LayersPanel; this column is now icons-only. */}
      <div className="absolute top-2 right-2 z-10 flex flex-col gap-1">
        <ZoomInButton />
        <ZoomOutButton />
        <FitViewButton />
        <InteractiveLockButton />
        <SnapToGridButton />
      </div>
      <WelcomeOverlay />
      {/* Phase 65 Plan 05 — context menus via Popover (W10 lock / D-11).
          PopoverAnchor is a 1×1 invisible fixed element at the right-click coords;
          Radix Floating UI anchors PopoverContent to it via side/align. */}
      {/*
        Canvas right-click menu (Phase 65 Plan 11 iteration, UAT 2026-05-15).
        Outer wrapper is a Radix DropdownMenu (was Popover). DropdownMenu hosts
        Radix Menu primitives — DropdownMenuItem and DropdownMenuSub — which give
        Add Component native safe-polygon hover handling. The previous Popover +
        nested DropdownMenu hybrid had to hand-roll hover-to-open with timers,
        which produced flicker.

        Virtual anchor: a 1x1 fixed-positioned, pointer-events:none div wrapped
        in DropdownMenuTrigger gives Floating-UI a real DOM element to anchor
        against at (screenX, screenY) without intercepting clicks.
      */}
      <DropdownMenu
        open={rcMenu.state.kind !== null}
        onOpenChange={(open) => { if (!open) rcMenu.close(); }}
      >
        <DropdownMenuTrigger asChild>
          <div
            style={{
              position: "fixed",
              left: rcMenu.state.screenX,
              top: rcMenu.state.screenY,
              width: 1,
              height: 1,
              pointerEvents: "none",
            }}
            aria-hidden
            tabIndex={-1}
          />
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="start"
          side="bottom"
          sideOffset={0}
          className="p-1 w-auto min-w-[8rem]"
          onEscapeKeyDown={() => rcMenu.close()}
          onPointerDownOutside={() => rcMenu.close()}
          onCloseAutoFocus={(e: Event) => e.preventDefault()}
          /* Radix DropdownMenu does NOT expose onOpenAutoFocus — Menu requires
             the first item to be focused so keyboard nav can start. We rely on
             :focus-visible (not :focus) styling on DropdownMenuItem so a
             programmatic auto-focus from a mouse-triggered open does not draw
             a persistent visual highlight. */
        >
          {rcMenu.state.kind === "node" && (
            <NodeContextMenu nodeId={rcMenu.state.targetId!} onClose={rcMenu.close} />
          )}
          {rcMenu.state.kind === "edge" && (
            <EdgeContextMenu edgeId={rcMenu.state.targetId!} onClose={rcMenu.close} />
          )}
          {rcMenu.state.kind === "pane" && flowPosition && (
            <CanvasContextMenu flowPosition={flowPosition} onClose={rcMenu.close} />
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
