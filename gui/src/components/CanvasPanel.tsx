import { useCallback, useEffect, useMemo, useRef } from "react";
import {
  ReactFlow,
  Controls,
  MiniMap,
  Background,
  BackgroundVariant,
  ConnectionLineType,
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
import WelcomeOverlay from "./WelcomeOverlay";

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
};

const defaultEdgeOptions = { type: "smoothstep" };

interface CanvasPanelProps {
  resolvedTheme?: "light" | "dark";
}

export default function CanvasPanel({ resolvedTheme }: CanvasPanelProps = {}) {
  const { nodes, edges, onNodesChange, onEdgesChange, addNode, addEdge, selectNode } =
    useStore();
  const activeLayer = useStore((s) => s.activeLayer);
  const { screenToFlowPosition } = useReactFlow();
  const containerRef = useRef<HTMLDivElement>(null);

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
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  return (
    <div ref={containerRef} className="flex-1 h-full relative focus:outline-none" tabIndex={-1}>
      <ReactFlow
        colorMode={resolvedTheme === "dark" ? "dark" : "light"}
        nodes={enrichedNodes}
        edges={enrichedEdges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onDrop={onDrop}
        onDragOver={onDragOver}
        onNodeClick={onNodeClick}
        onPaneClick={onPaneClick}
        onNodeDragStart={onNodeDragStart}
        isValidConnection={isValidConnection}
        nodeTypes={nodeTypes}
        edgeTypes={edgeTypes}
        defaultEdgeOptions={defaultEdgeOptions}
        connectionLineType={ConnectionLineType.SmoothStep}
        deleteKeyCode={["Delete", "Backspace"]}
        fitView
      >
        <Controls />
        <MiniMap />
        <Background variant={BackgroundVariant.Dots} color={resolvedTheme === "dark" ? "#555" : "#ccc"} />
      </ReactFlow>
      <WelcomeOverlay />
    </div>
  );
}
