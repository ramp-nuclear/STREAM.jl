import { create } from "zustand";
import { temporal } from "zundo";
import {
  Node,
  Edge,
  Connection,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge as rfAddEdge,
  NodeChange,
  EdgeChange,
} from "@xyflow/react";
import { getComponent } from "../registry";

export interface StreamNodeData {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
  constructorMode?: string;
}

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  selectNode: (nodeId: string | null) => void;
  addNode: (componentId: string, position: { x: number; y: number }) => void;
  removeNode: (nodeId: string) => void;
  addEdge: (connection: Connection) => void;
  removeEdge: (edgeId: string) => void;
  updateNodeParams: (nodeId: string, patch: Partial<StreamNodeData>) => void;
}

// Per-type instance counters for default naming (module-level, not tracked by zundo)
const instanceCounters: Record<string, number> = {};

function getNextInstanceName(componentId: string): string {
  const count = (instanceCounters[componentId] ?? 0) + 1;
  instanceCounters[componentId] = count;
  return `${componentId.toLowerCase()}_${count}`;
}

const useStore = create<AppState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      selectedNodeId: null,
      onNodesChange: (changes) =>
        set({ nodes: applyNodeChanges(changes, get().nodes) }),
      onEdgesChange: (changes) =>
        set({ edges: applyEdgeChanges(changes, get().edges) }),
      selectNode: (nodeId) => set({ selectedNodeId: nodeId }),
      addNode: (componentId, position) => {
        const id = crypto.randomUUID();
        const component = getComponent(componentId);
        const defaultParams: Record<string, unknown> = {};
        if (component) {
          for (const param of component.parameters) {
            if (param.default !== undefined && param.default !== null) {
              defaultParams[param.name] = param.default;
            }
          }
        }
        const defaultMode =
          component?.constructorModes[0]?.mode ?? "default";
        const newNode: Node = {
          id,
          type: "streamNode",
          position,
          data: {
            componentId,
            instanceName: getNextInstanceName(componentId),
            parameters: defaultParams,
            constructorMode: defaultMode,
          } satisfies StreamNodeData,
        };
        set({ nodes: [...get().nodes, newNode] });
      },
      updateNodeParams: (nodeId, patch) => {
        const { nodes } = get();
        set({
          nodes: nodes.map((n) => {
            if (n.id !== nodeId) return n;
            const data = n.data as unknown as StreamNodeData;
            return {
              ...n,
              data: {
                ...data,
                ...(patch.instanceName !== undefined && {
                  instanceName: patch.instanceName,
                }),
                ...(patch.constructorMode !== undefined && {
                  constructorMode: patch.constructorMode,
                }),
                ...(patch.parameters !== undefined && {
                  parameters: { ...data.parameters, ...patch.parameters },
                }),
              },
            };
          }),
        });
      },
      removeNode: (nodeId) => {
        const { nodes, edges } = get();
        set({
          nodes: nodes.filter((n) => n.id !== nodeId),
          edges: edges.filter(
            (e) => e.source !== nodeId && e.target !== nodeId,
          ),
          selectedNodeId: null,
        });
      },
      addEdge: (connection) => {
        set({ edges: rfAddEdge(connection, get().edges) });
      },
      removeEdge: (edgeId) => {
        set({ edges: get().edges.filter((e) => e.id !== edgeId) });
      },
    }),
    {
      partialize: (state) => ({
        nodes: state.nodes,
        edges: state.edges,
        selectedNodeId: state.selectedNodeId,
      }),
      limit: 50,
    },
  ),
);

export default useStore;
