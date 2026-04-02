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
import type { BCEntry } from "../lib/codeGenerator";
import {
  serializeProject,
  deserializeProject,
  addToRecent,
  reconstructInstanceCounters,
} from "../lib/projectIO";

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
  // Persistence state
  isDirty: boolean;
  currentFilePath: string | null;
  recentFiles: string[];
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
// Store
// ---------------------------------------------------------------------------

const useStore = create<AppState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      selectedNodeId: null,
      bcs: [],
      bottomPanelOpen: false,
      // Persistence initial state
      isDirty: false,
      currentFilePath: null,
      recentFiles: [],

      // ---------------------------------------------------------------------------
      // Canvas actions (content-mutating — set isDirty: true)
      // ---------------------------------------------------------------------------

      onNodesChange: (changes) =>
        set({ nodes: applyNodeChanges(changes, get().nodes), isDirty: true }),

      onEdgesChange: (changes) =>
        set({ edges: applyEdgeChanges(changes, get().edges), isDirty: true }),

      // selectNode is NOT content-mutating — do NOT set isDirty
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
        set({ nodes: [...get().nodes, newNode], isDirty: true });
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
          isDirty: true,
        });
      },

      removeNode: (nodeId) => {
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
        set({ edges: rfAddEdge(connection, get().edges), isDirty: true });
      },

      removeEdge: (edgeId) => {
        set({
          edges: get().edges.filter((e) => e.id !== edgeId),
          isDirty: true,
        });
      },

      addBC: (bc) => set({ bcs: [...get().bcs, bc], isDirty: true }),

      removeBC: (index) =>
        set({
          bcs: get().bcs.filter((_, i) => i !== index),
          isDirty: true,
        }),

      // toggleBottomPanel is NOT content-mutating — do NOT set isDirty
      toggleBottomPanel: () =>
        set({ bottomPanelOpen: !get().bottomPanelOpen }),

      // ---------------------------------------------------------------------------
      // setRecentFiles
      // ---------------------------------------------------------------------------

      setRecentFiles: (files) => set({ recentFiles: files }),

      // ---------------------------------------------------------------------------
      // saveProject (D-02)
      // ---------------------------------------------------------------------------

      saveProject: async () => {
        const { currentFilePath } = get();
        if (!currentFilePath) {
          return get().saveProjectAs();
        }
        try {
          const { writeTextFile } = await import("@tauri-apps/plugin-fs");
          const json = serializeProject(get().nodes, get().edges, get().bcs);
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
        try {
          const { save } = await import("@tauri-apps/plugin-dialog");
          const filePath = await save({
            defaultPath: "project.streamgui",
            filters: [
              {
                name: "STREAM Composer Projects",
                extensions: ["streamgui"],
              },
            ],
          });
          if (!filePath) return; // User cancelled

          const { writeTextFile } = await import("@tauri-apps/plugin-fs");
          const json = serializeProject(get().nodes, get().edges, get().bcs);
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
              {
                name: "STREAM Composer Projects",
                extensions: ["streamgui"],
              },
            ],
            multiple: false,
          });
          if (!filePath) return; // User cancelled
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

          // Reconstruct instanceCounters from the loaded node names (Pitfall 6)
          const reconstructed = reconstructInstanceCounters(project.nodes);
          clearInstanceCounters();
          Object.assign(instanceCounters, reconstructed);

          const updated = addToRecent(get().recentFiles, filePath);
          set({
            nodes: project.nodes,
            edges: project.edges,
            bcs: project.bcs,
            currentFilePath: filePath,
            isDirty: false,
            selectedNodeId: null,
            recentFiles: updated,
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
          currentFilePath: null,
          isDirty: false,
          selectedNodeId: null,
          bottomPanelOpen: false,
        });
        // Clear undo/redo history (temporal middleware)
        useStore.temporal.getState().clear();
      },
    }),
    {
      // Exclude isDirty, currentFilePath, recentFiles from zundo partialize.
      // isDirty is metadata; currentFilePath/recentFiles are session state, not undoable content.
      partialize: (state) => ({
        nodes: state.nodes,
        edges: state.edges,
        selectedNodeId: state.selectedNodeId,
        bcs: state.bcs,
      }),
      limit: 50,
    },
  ),
);

/**
 * Initialize recent files from disk on app startup.
 * Call this from App.tsx on mount.
 */
export async function initializeRecentFiles(): Promise<void> {
  const files = await loadRecentFiles();
  useStore.setState({ recentFiles: files });
}

export default useStore;
