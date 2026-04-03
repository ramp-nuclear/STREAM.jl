import { create } from "zustand";
import {
  Node,
  Edge,
  Connection,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge as rfAddEdge,
  NodeChange,
  EdgeChange,
  MarkerType,
} from "@xyflow/react";
import { getComponent } from "../registry";
import type { BCEntry } from "../lib/codeGenerator";
import { validateTopology, type TopologyResult } from "../lib/validation";
import {
  serializeProject,
  deserializeProject,
  addToRecent,
  reconstructInstanceCounters,
} from "../lib/projectIO";
import type { LayerView } from "../lib/layers";

// Snapshot of undoable canvas content (not UI state like selection or panels).
interface CanvasSnapshot {
  nodes: Node[];
  edges: Edge[];
  bcs: BCEntry[];
}

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
  bcs: BCEntry[];
  bottomPanelOpen: boolean;
  toolboxCollapsed: boolean;
  sidebarCollapsed: boolean;
  setToolboxCollapsed: (collapsed: boolean) => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  // Topology validation (Phase 39)
  errorNodeIds: Set<string>;
  validationResult: TopologyResult | null;
  validateAndGate: () => TopologyResult;
  clearValidation: () => void;
  // Layer view state (persisted in .streamgui, but NOT in undo stack)
  activeLayer: LayerView;
  setActiveLayer: (layer: LayerView) => void;
  cycleLayer: () => void;
  // Persistence state
  isDirty: boolean;
  currentFilePath: string | null;
  recentFiles: string[];
  // Undo/redo — explicit history stack, not auto-tracked middleware
  _undoPast: CanvasSnapshot[];
  _undoFuture: CanvasSnapshot[];
  /** Push a snapshot of the current canvas state before a mutation. Call before set(). */
  _pushSnapshot: () => void;
  undo: () => void;
  redo: () => void;
  // Canvas actions
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  selectNode: (nodeId: string | null) => void;
  addNode: (componentId: string, position: { x: number; y: number }) => void;
  removeNode: (nodeId: string) => void;
  addEdge: (connection: Connection) => void;
  removeEdge: (edgeId: string) => void;
  updateNodeParams: (nodeId: string, patch: Partial<StreamNodeData>) => void;
  addBC: (bc: BCEntry) => void;
  removeBC: (index: number) => void;
  toggleBottomPanel: () => void;
  // File I/O actions
  saveProject: () => Promise<void>;
  saveProjectAs: () => Promise<void>;
  loadProject: () => Promise<void>;
  loadProjectFromPath: (path: string) => Promise<void>;
  newProject: () => Promise<void>;
  setRecentFiles: (files: string[]) => void;
}

// Per-type instance counters for default naming (module-level, not tracked by zundo)
const instanceCounters: Record<string, number> = {};

function getNextInstanceName(componentId: string): string {
  const count = (instanceCounters[componentId.toLowerCase()] ?? 0) + 1;
  instanceCounters[componentId.toLowerCase()] = count;
  return `${componentId.toLowerCase()}_${count}`;
}

function clearInstanceCounters(): void {
  Object.keys(instanceCounters).forEach((k) => delete instanceCounters[k]);
}

// ---------------------------------------------------------------------------
// recent.json helpers (module-level async, not store actions)
// ---------------------------------------------------------------------------

const RECENT_FILE_NAME = "recent.json";

async function loadRecentFiles(): Promise<string[]> {
  try {
    // Dynamic imports to avoid breaking vitest (Tauri APIs unavailable in node env)
    const { appDataDir, join } = await import("@tauri-apps/api/path");
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const dir = await appDataDir();
    const path = await join(dir, RECENT_FILE_NAME);
    const content = await readTextFile(path);
    const parsed = JSON.parse(content) as { files?: string[] };
    return Array.isArray(parsed.files) ? parsed.files : [];
  } catch {
    return [];
  }
}

async function saveRecentFiles(files: string[]): Promise<void> {
  try {
    const { appDataDir, join } = await import("@tauri-apps/api/path");
    const { writeTextFile, mkdir } = await import("@tauri-apps/plugin-fs");
    const dir = await appDataDir();
    await mkdir(dir, { recursive: true });
    const path = await join(dir, RECENT_FILE_NAME);
    await writeTextFile(path, JSON.stringify({ files }, null, 2));
  } catch {
    // Silent failure — don't block user if recent.json write fails
  }
}

// ---------------------------------------------------------------------------
// Edge enrichment: arrowheads + parallel offset for bidirectional pairs
// ---------------------------------------------------------------------------

/**
 * Enrich edges with hydraulic arrowheads and parallel offset for bidirectional pairs.
 * Pure function — does NOT call get(). Used by addEdge and loadProjectFromPath.
 *
 * Hydraulic edges use the custom "hydraulicEdge" type (HydraulicEdge component) which
 * reads data.parallelOffset to shift sourceY/targetY, producing true parallel lines.
 * ReactFlow's smoothstep pathOptions.offset controls step distance, not lateral position
 * — it cannot separate overlapping bidirectional edges.
 */
export function enrichEdges(edges: Edge[], nodes: Node[]): Edge[] {
  // Step 1: Set hydraulicEdge type + arrowhead for hydraulic; strip arrowhead from thermal.
  const typedEdges = edges.map((e) => {
    const srcNode = nodes.find((n) => n.id === e.source);
    if (!srcNode) return e;
    const srcComp = getComponent((srcNode.data as unknown as StreamNodeData).componentId);
    if (!srcComp) return e;
    const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
    if (srcPort?.type === "ThermalPort") {
      // Thermal edge: keep smoothstep, no arrowhead
      const { markerEnd, ...rest } = e as Edge & { markerEnd?: unknown };
      return rest;
    }
    // Hydraulic edge: custom type + filled arrowhead
    return {
      ...e,
      type: "hydraulicEdge",
      markerEnd: {
        type: MarkerType.ArrowClosed,
        width: 16,
        height: 16,
        color: "#b1b1b7",
      },
    };
  });

  // Step 2: Detect bidirectional pairs and apply Y-offset via data.parallelOffset.
  // HydraulicEdge shifts sourceY/targetY by this value to produce visually distinct paths.
  return typedEdges.map((e) => {
    const reverseEdge = typedEdges.find(
      (other) =>
        other.id !== e.id &&
        other.source === e.target &&
        other.target === e.source,
    );
    if (!reverseEdge) {
      // No partner — strip any stale parallelOffset
      const eData = e.data as Record<string, unknown> | undefined;
      if (eData?.parallelOffset !== undefined) {
        const { parallelOffset: _, ...restData } = eData;
        return { ...e, data: restData };
      }
      return e;
    }
    // Stable ordering: lower array index gets positive offset (shifts edge down)
    const isFirst = typedEdges.indexOf(e) < typedEdges.indexOf(reverseEdge);
    return { ...e, data: { ...(e.data ?? {}), parallelOffset: isFirst ? 7 : -7 } };
  });
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

const useStore = create<AppState>()((set, get) => ({
  nodes: [],
  edges: [],
  selectedNodeId: null,
  bcs: [],
  bottomPanelOpen: false,
  toolboxCollapsed: false,
  sidebarCollapsed: false,
  // Topology validation (Phase 39) initial state
  errorNodeIds: new Set<string>(),
  validationResult: null,
  // Layer view initial state
  activeLayer: "Both" as LayerView,
  // Persistence initial state
  isDirty: false,
  currentFilePath: null,
  recentFiles: [],

  // ---------------------------------------------------------------------------
  // Undo / redo — explicit history stack
  //
  // Why not zundo (temporal middleware)? ReactFlow fires many "noise" change
  // events (select, dimensions, intermediate drag positions) that caused
  // spurious history entries and required multiple Ctrl+Z presses.
  // Explicit push-before-mutation is simpler and fully predictable.
  // ---------------------------------------------------------------------------

  _undoPast: [],
  _undoFuture: [],

  _pushSnapshot: () => {
    const { nodes, edges, bcs, _undoPast } = get();
    set({
      _undoPast: [..._undoPast, { nodes, edges, bcs }].slice(-50),
      _undoFuture: [],
    });
  },

  undo: () => {
    const { nodes, edges, bcs, _undoPast, _undoFuture } = get();
    if (_undoPast.length === 0) return;
    const prev = _undoPast[_undoPast.length - 1];
    set({
      nodes: prev.nodes,
      edges: prev.edges,
      bcs: prev.bcs,
      _undoPast: _undoPast.slice(0, -1),
      _undoFuture: [{ nodes, edges, bcs }, ..._undoFuture].slice(0, 50),
      isDirty: true,
      errorNodeIds: new Set<string>(),
      validationResult: null,
    });
  },

  redo: () => {
    const { nodes, edges, bcs, _undoPast, _undoFuture } = get();
    if (_undoFuture.length === 0) return;
    const next = _undoFuture[0];
    set({
      nodes: next.nodes,
      edges: next.edges,
      bcs: next.bcs,
      _undoPast: [..._undoPast, { nodes, edges, bcs }].slice(-50),
      _undoFuture: _undoFuture.slice(1),
      isDirty: true,
      errorNodeIds: new Set<string>(),
      validationResult: null,
    });
  },

  // ---------------------------------------------------------------------------
  // Layer view actions (persisted in .streamgui — set isDirty so saves capture)
  // ---------------------------------------------------------------------------

  setActiveLayer: (layer) => set({ activeLayer: layer, isDirty: true }),

  cycleLayer: () => {
    const order: LayerView[] = ["Hydraulic", "Both", "Thermal"];
    const { activeLayer } = get();
    const idx = order.indexOf(activeLayer);
    set({ activeLayer: order[(idx + 1) % 3], isDirty: true });
  },

  // ---------------------------------------------------------------------------
  // Canvas actions (content-mutating — set isDirty: true)
  // ---------------------------------------------------------------------------

  onNodesChange: (changes) => {
    // Skip contentless events (selection highlight, layout measurement) — they
    // are not content mutations and must not dirty the document or push history.
    const isContentless = changes.every(
      (c) => c.type === "select" || c.type === "dimensions",
    );
    if (isContentless) {
      set({ nodes: applyNodeChanges(changes, get().nodes) });
      return;
    }

    // Keyboard-delete (Delete/Backspace on selected node): snapshot before removal.
    if (changes.some((c) => c.type === "remove")) {
      get()._pushSnapshot();
    }

    set({ nodes: applyNodeChanges(changes, get().nodes), isDirty: true });
  },

  onEdgesChange: (changes) => {
    const isContentless = changes.every((c) => c.type === "select");
    if (isContentless) return;

    // Keyboard-delete on selected edge: snapshot before removal.
    if (changes.some((c) => c.type === "remove")) {
      get()._pushSnapshot();
    }

    // Offset cleanup: if removing an edge that has data.parallelOffset,
    // clear parallelOffset from its surviving bidirectional partner
    const removedIds = changes
      .filter((c): c is EdgeChange & { type: "remove"; id: string } => c.type === "remove")
      .map((c) => c.id);
    if (removedIds.length > 0) {
      const currentEdges = get().edges;
      const removedEdges = currentEdges.filter((e) => removedIds.includes(e.id));
      let cleanedEdges = currentEdges;
      for (const removed of removedEdges) {
        if ((removed.data as Record<string, unknown>)?.parallelOffset === undefined) continue;
        const partnerIdx = cleanedEdges.findIndex(
          (e) =>
            !removedIds.includes(e.id) &&
            e.source === removed.target &&
            e.target === removed.source,
        );
        if (partnerIdx !== -1) {
          const partner = cleanedEdges[partnerIdx];
          const { parallelOffset: _, ...restData } = partner.data as Record<string, unknown>;
          cleanedEdges = [
            ...cleanedEdges.slice(0, partnerIdx),
            { ...partner, data: restData },
            ...cleanedEdges.slice(partnerIdx + 1),
          ];
        }
      }
      set({ edges: applyEdgeChanges(changes, cleanedEdges), isDirty: true });
      return;
    }

    set({ edges: applyEdgeChanges(changes, get().edges), isDirty: true });
  },

  // selectNode is NOT content-mutating — do NOT set isDirty
  selectNode: (nodeId) => set({ selectedNodeId: nodeId }),

  addNode: (componentId, position) => {
    get()._pushSnapshot();
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
    set({ nodes: [...get().nodes, newNode], isDirty: true });
  },

  updateNodeParams: (nodeId, patch) => {
    get()._pushSnapshot();
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
      isDirty: true,
    });
  },

  removeNode: (nodeId) => {
    get()._pushSnapshot();
    const { nodes, edges, bcs } = get();
    set({
      nodes: nodes.filter((n) => n.id !== nodeId),
      edges: edges.filter(
        (e) => e.source !== nodeId && e.target !== nodeId,
      ),
      bcs: bcs.filter((bc) => bc.nodeId !== nodeId),
      selectedNodeId: null,
      isDirty: true,
    });
  },

  addEdge: (connection) => {
    get()._pushSnapshot();
    const newEdges = rfAddEdge(connection, get().edges);

    // Apply thermal edge styling (per D-03, UI-SPEC): amber dashed for ThermalPort edges
    const styledEdges = newEdges.map((e) => {
      // Only style edges that don't already have a style (the newly added one)
      if (e.style) return e;
      // Check if this edge connects ThermalPorts
      const srcNode = get().nodes.find((n) => n.id === e.source);
      const tgtNode = get().nodes.find((n) => n.id === e.target);
      if (!srcNode || !tgtNode) return e;
      const srcComp = getComponent((srcNode.data as unknown as StreamNodeData).componentId);
      const tgtComp = getComponent((tgtNode.data as unknown as StreamNodeData).componentId);
      if (!srcComp || !tgtComp) return e;
      const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
      const tgtPort = tgtComp.ports.find((p) => p.name === e.targetHandle);
      if (srcPort?.type === "ThermalPort" && tgtPort?.type === "ThermalPort") {
        return { ...e, style: { stroke: "#f59e0b", strokeDasharray: "6 3" } };
      }
      return e;
    });

    // Apply hydraulic arrowheads and parallel offset for bidirectional pairs
    const finalEdges = enrichEdges(styledEdges, get().nodes);

    const { errorNodeIds } = get();

    if (errorNodeIds.size > 0) {
      const updatedErrors = new Set(errorNodeIds);
      for (const nodeId of [connection.source, connection.target]) {
        if (!nodeId || !updatedErrors.has(nodeId)) continue;
        const node = get().nodes.find((n) => n.id === nodeId);
        if (!node) continue;
        const data = node.data as { componentId: string };
        const def = getComponent(data.componentId);
        if (!def) continue;
        const flowPorts = def.ports.filter((p) => p.type === "FlowPort");
        const allConnected = flowPorts.every((port) => {
          const isInput = port.name.includes("in");
          return finalEdges.some((e) =>
            isInput
              ? e.target === nodeId && e.targetHandle === port.name
              : e.source === nodeId && e.sourceHandle === port.name,
          );
        });
        if (allConnected) updatedErrors.delete(nodeId);
      }
      set({ edges: finalEdges, isDirty: true, errorNodeIds: updatedErrors });
    } else {
      set({ edges: finalEdges, isDirty: true });
    }
  },

  removeEdge: (edgeId) => {
    get()._pushSnapshot();
    const currentEdges = get().edges;
    const removed = currentEdges.find((e) => e.id === edgeId);
    let edges = currentEdges.filter((e) => e.id !== edgeId);
    // Clean up partner parallelOffset when removing one edge of a bidirectional pair
    if (removed && (removed.data as Record<string, unknown>)?.parallelOffset !== undefined) {
      edges = edges.map((e) => {
        if (e.source === removed.target && e.target === removed.source) {
          const { parallelOffset: _, ...restData } = e.data as Record<string, unknown>;
          return { ...e, data: restData };
        }
        return e;
      });
    }
    set({ edges, isDirty: true });
  },

  addBC: (bc) => {
    get()._pushSnapshot();
    set({ bcs: [...get().bcs, bc], isDirty: true });
  },

  removeBC: (index) => {
    get()._pushSnapshot();
    set({ bcs: get().bcs.filter((_, i) => i !== index), isDirty: true });
  },

  // toggleBottomPanel is NOT content-mutating — do NOT set isDirty
  toggleBottomPanel: () => set({ bottomPanelOpen: !get().bottomPanelOpen }),

  // ---------------------------------------------------------------------------
  // Topology validation (Phase 39)
  // ---------------------------------------------------------------------------

  validateAndGate: () => {
    const { nodes, edges, bcs } = get();
    const result = validateTopology(nodes, edges, bcs, getComponent);
    const errorIds = new Set(result.nodeErrors.map((e) => e.nodeId));
    set({ errorNodeIds: errorIds, validationResult: result });
    return result;
  },

  clearValidation: () => {
    set({ errorNodeIds: new Set<string>(), validationResult: null });
  },

  // Panel collapse is NOT content-mutating — do NOT set isDirty
  setToolboxCollapsed: (collapsed) => set({ toolboxCollapsed: collapsed }),
  setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),

  // ---------------------------------------------------------------------------
  // setRecentFiles
  // ---------------------------------------------------------------------------

  setRecentFiles: (files) => set({ recentFiles: files }),

  // ---------------------------------------------------------------------------
  // saveProject (D-02)
  // ---------------------------------------------------------------------------

  saveProject: async () => {
    // Phase 39: validation gate (D-01, D-02)
    const result = get().validateAndGate();
    if (!result.valid) return;

    const { currentFilePath } = get();
    if (!currentFilePath) {
      return get().saveProjectAs();
    }
    try {
      const { writeTextFile } = await import("@tauri-apps/plugin-fs");
      const json = serializeProject(get().nodes, get().edges, get().bcs, get().activeLayer);
      await writeTextFile(currentFilePath, json);
      const updated = addToRecent(get().recentFiles, currentFilePath);
      set({ isDirty: false, recentFiles: updated });
      await saveRecentFiles(updated);
    } catch (err) {
      console.error("[saveProject] write failed:", err);
      try {
        const { message } = await import("@tauri-apps/plugin-dialog");
        await message(
          "Couldn't save project. Check that the file isn't read-only and there is enough disk space, then try again.",
          { title: "Save Failed", kind: "error" },
        );
      } catch (dialogErr) {
        console.error("[saveProject] error dialog failed:", dialogErr);
      }
    }
  },

  // ---------------------------------------------------------------------------
  // saveProjectAs (D-02)
  // ---------------------------------------------------------------------------

  saveProjectAs: async () => {
    // Phase 39: validation gate (D-01, D-02)
    const result = get().validateAndGate();
    if (!result.valid) return;

    try {
      const { save } = await import("@tauri-apps/plugin-dialog");
      const filePath = await save({
        defaultPath: "project.streamgui",
        filters: [
          { name: "STREAM Composer Projects", extensions: ["streamgui"] },
        ],
      });
      if (!filePath) return;

      const { writeTextFile } = await import("@tauri-apps/plugin-fs");
      const json = serializeProject(get().nodes, get().edges, get().bcs, get().activeLayer);
      await writeTextFile(filePath, json);
      const updated = addToRecent(get().recentFiles, filePath);
      set({ isDirty: false, currentFilePath: filePath, recentFiles: updated });
      await saveRecentFiles(updated);
    } catch (err) {
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Couldn't save project. Check that the file isn't read-only and there is enough disk space, then try again.",
        { title: "Save Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // loadProject (D-02)
  // ---------------------------------------------------------------------------

  loadProject: async () => {
    try {
      const { open } = await import("@tauri-apps/plugin-dialog");
      const filePath = await open({
        filters: [
          { name: "STREAM Composer Projects", extensions: ["streamgui"] },
        ],
        multiple: false,
      });
      if (!filePath) return;
      const path = Array.isArray(filePath) ? filePath[0] : filePath;
      await get().loadProjectFromPath(path);
    } catch (err) {
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Couldn't open this project. The file may be missing, corrupted, or not a valid .streamgui file.",
        { title: "Open Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // loadProjectFromPath
  // ---------------------------------------------------------------------------

  loadProjectFromPath: async (filePath: string) => {
    try {
      const { readTextFile } = await import("@tauri-apps/plugin-fs");
      const content = await readTextFile(filePath);
      const project = deserializeProject(content);

      const reconstructed = reconstructInstanceCounters(project.nodes);
      clearInstanceCounters();
      Object.assign(instanceCounters, reconstructed);

      // Re-enrich edges for arrowheads and parallel offset (handles pre-Phase-42 saves)
      const enrichedProjectEdges = enrichEdges(project.edges, project.nodes);

      const updated = addToRecent(get().recentFiles, filePath);
      set({
        nodes: project.nodes,
        edges: enrichedProjectEdges,
        bcs: project.bcs,
        activeLayer: (project.activeLayer ?? "Both") as LayerView,
        currentFilePath: filePath,
        isDirty: false,
        selectedNodeId: null,
        recentFiles: updated,
        _undoPast: [],
        _undoFuture: [],
        errorNodeIds: new Set<string>(),
        validationResult: null,
      });
      await saveRecentFiles(updated);
    } catch (err) {
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Couldn't open this project. The file may be missing, corrupted, or not a valid .streamgui file.",
        { title: "Open Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // newProject (D-11)
  // ---------------------------------------------------------------------------

  newProject: async () => {
    clearInstanceCounters();
    set({
      nodes: [],
      edges: [],
      bcs: [],
      activeLayer: "Both" as LayerView,
      currentFilePath: null,
      isDirty: false,
      selectedNodeId: null,
      bottomPanelOpen: false,
      toolboxCollapsed: false,
      sidebarCollapsed: false,
      _undoPast: [],
      _undoFuture: [],
      errorNodeIds: new Set<string>(),
      validationResult: null,
    });
  },
}));

/**
 * Initialize recent files from disk on app startup.
 * Call this from App.tsx on mount.
 */
export async function initializeRecentFiles(): Promise<void> {
  const files = await loadRecentFiles();
  useStore.setState({ recentFiles: files });
}

export default useStore;
