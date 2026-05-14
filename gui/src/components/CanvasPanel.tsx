import { useCallback, useEffect, useMemo, useRef } from "react";
import {
  ReactFlow,
  Controls,
  MiniMap,
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
import { isNodeDimmed, isEdgeDimmed } from "../lib/layers";
import StreamNode from "./StreamNode";
import HydraulicEdge from "./HydraulicEdge";
import BCEdge from "./BCEdge";
import WelcomeOverlay from "./WelcomeOverlay";
import { isAllowedBCConnection } from "@/lib/bcMode";
import { useRightClickContextMenu } from "@/hooks/useRightClickContextMenu";
import { Popover, PopoverAnchor, PopoverContent } from "@/components/ui/popover";
import NodeContextMenu from "./canvasMenus/NodeContextMenu";
import EdgeContextMenu from "./canvasMenus/EdgeContextMenu";
import CanvasContextMenu from "./canvasMenus/CanvasContextMenu";
import SnapToGridButton from "./canvasMenus/SnapToGridButton";

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
  const { nodes, edges, onNodesChange, onEdgesChange, addNode, addEdge, selectNode } =
    useStore();
  const activeLayer = useStore((s) => s.activeLayer);
  // Phase 65 D-09: snap-to-grid state read from store
  const snapEnabled = useStore((s) => s.snapToGrid);
  // B3 guard: useReactFlow is called ONCE at the component top level — never
  // inside callbacks or useEffect. setNodes/setEdges are stable identities per
  // @xyflow/react v12 docs.
  const { screenToFlowPosition, setNodes, setEdges } = useReactFlow();
  const containerRef = useRef<HTMLDivElement>(null);

  // Phase 65 Plan 03: right-click pan-vs-context-menu disambiguation (D-12).
  // rcMenu.state is consumed by Plan 05 — no menu UI is rendered here.
  const rcMenu = useRightClickContextMenu();

  // Enrich nodes with dimming styles based on active layer
  const enrichedNodes = useMemo(() => {
    if (activeLayer === "Both") return nodes;
    return nodes.map(node => {
      const nodeData = node.data as unknown as StreamNodeData;
      const dimmed = isNodeDimmed(nodeData.componentId, activeLayer, getComponent);
      if (!dimmed) return node;
      return {
        ...node,
        style: {
          ...node.style,
          opacity: 0.2,
          pointerEvents: "none" as const,
          transition: "opacity 150ms ease",
        },
      };
    });
  }, [nodes, activeLayer]);

  // Enrich edges with dimming styles based on active layer
  const enrichedEdges = useMemo(() => {
    if (activeLayer === "Both") return edges;
    return edges.map(edge => {
      const isThermalEdge = edge.style?.stroke === "#f59e0b";
      const dimmed = isEdgeDimmed(isThermalEdge, activeLayer);
      if (!dimmed) return edge;
      return {
        ...edge,
        style: {
          ...edge.style,
          opacity: 0.15,
          transition: "opacity 150ms ease",
        },
      };
    });
  }, [edges, activeLayer]);

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();
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
    },
    [addEdge],
  );

  const onNodeClick = useCallback(
    (_event: React.MouseEvent, node: Node) => {
      const nodeData = node.data as unknown as StreamNodeData;
      const dimmed = isNodeDimmed(nodeData.componentId, useStore.getState().activeLayer, getComponent);
      if (dimmed) return; // Don't select dimmed nodes
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
    // Port-type enforcement (per D-05): FlowPort-to-FlowPort only, ThermalPort-to-ThermalPort only
    const sourceType = getPortType(connection.source, connection.sourceHandle);
    const targetType = getPortType(connection.target, connection.targetHandle);
    if (sourceType && targetType && sourceType !== targetType) return false;
    // Phase 63 D-21 — BCPort allow-list. Pure read-only registry check (no
    // store mutation here per RESEARCH Pitfall 7; n-mismatch flagging lives
    // in `useStore.addEdge` / `setBCMode`).
    if (sourceType === "BCPort") {
      const srcNode = useStore.getState().nodes.find((n) => n.id === connection.source);
      const tgtNode = useStore.getState().nodes.find((n) => n.id === connection.target);
      if (!srcNode || !tgtNode) return false;
      const srcCompId = (srcNode.data as unknown as StreamNodeData).componentId;
      const tgtCompId = (tgtNode.data as unknown as StreamNodeData).componentId;
      return isAllowedBCConnection(srcCompId, tgtCompId);
    }
    return true;
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
      // Tab cycles layers globally; skip when a text input has focus
      if (e.key === "Tab") {
        const target = e.target as HTMLElement;
        if (
          target instanceof HTMLInputElement ||
          target instanceof HTMLTextAreaElement ||
          target instanceof HTMLSelectElement ||
          target.isContentEditable
        ) {
          return;
        }
        e.preventDefault();
        useStore.getState().cycleLayer();
      }
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

  // Phase 65 Plan 05: convert rcMenu screen coords to flow coords for pane menus.
  // D-11: we use Popover as the host (NOT a controlled ContextMenu.Root) because
  // Radix ContextMenu.Root does not support a controlled `open` at arbitrary screen coords.
  // ContextMenuItem / ContextMenuSub* items are used inside PopoverContent for visual parity.
  const flowPosition =
    rcMenu.state.kind === "pane"
      ? screenToFlowPosition({ x: rcMenu.state.screenX, y: rcMenu.state.screenY })
      : null;

  return (
    <div ref={containerRef} className="flex-1 h-full relative focus:outline-none" tabIndex={-1}>
      <ReactFlow
        colorMode={resolvedTheme === "dark" ? "dark" : "light"}
        style={resolvedTheme === "dark" ? ({ "--xy-background-color": "#282c34" } as React.CSSProperties) : undefined}
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
        panOnDrag={[2]}
        selectionOnDrag
        selectionMode={SelectionMode.Partial}
        deleteKeyCode={["Delete", "Backspace"]} // Del/Backspace deletes nodes AND edges via ReactFlow built-in — closes v0.8 user-list item #2
        // Phase 65 D-08/D-09: 16px fixed grid snapping via ReactFlow built-in props
        snapToGrid={snapEnabled}
        snapGrid={[16, 16]}
        fitView
      >
        <Controls />
        <MiniMap />
        <Background variant={BackgroundVariant.Dots} color={resolvedTheme === "dark" ? "#4b5263" : "#ccc"} />
      </ReactFlow>
      {/* Phase 65 D-07: snap-to-grid overlay button — top-right canvas corner (W9 lock: no Panel import) */}
      <div className="absolute top-2 right-2 z-10">
        <SnapToGridButton />
      </div>
      <WelcomeOverlay />
      {/* Phase 65 Plan 05 — context menus via Popover (W10 lock / D-11).
          PopoverAnchor is a 1×1 invisible fixed element at the right-click coords;
          Radix Floating UI anchors PopoverContent to it via side/align. */}
      <Popover
        open={rcMenu.state.kind !== null}
        onOpenChange={(open) => { if (!open) rcMenu.close(); }}
      >
        <PopoverAnchor
          style={{
            position: "fixed",
            left: rcMenu.state.screenX,
            top: rcMenu.state.screenY,
            width: 1,
            height: 1,
            pointerEvents: "none",
          }}
          aria-hidden
        />
        <PopoverContent
          align="start"
          side="bottom"
          sideOffset={0}
          className="p-1 w-auto min-w-[8rem]"
          onEscapeKeyDown={() => rcMenu.close()}
          onPointerDownOutside={() => rcMenu.close()}
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
        </PopoverContent>
      </Popover>
    </div>
  );
}
