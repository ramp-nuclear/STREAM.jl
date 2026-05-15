import { useEffect, useRef, useState, useCallback } from "react";
import { ReactFlowProvider } from "@xyflow/react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import ToolboxPanel from "./components/ToolboxPanel";
import ResourcesTreePanel from "./components/resources/ResourcesTreePanel";
import ModelOptionsPanel from "./components/project/ModelOptionsPanel";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";
import Toolbar from "./components/Toolbar";
import BottomPanel from "./components/BottomPanel";
import UnsavedChangesDialog from "./components/UnsavedChangesDialog";
import ValidationDialog from "./components/ValidationDialog";
import AutoRecoverRestoreModal, {
  type RestoreCandidate,
} from "./components/AutoRecoverRestoreModal";
import { TooltipProvider } from "./components/ui/tooltip";
import { Tabs, TabsContent } from "@/components/ui/tabs";
import { ResponsiveTabsList } from "./components/ResponsiveTabsList";
import { Boxes, Library, Settings2 } from "lucide-react";
import useStore from "./store/useStore";
import { initializeRecentFiles, initAutoRecover } from "./store/useStore";
import { detectCrashOnLaunch } from "./lib/autoRecover";
import type { LockfileContent } from "./lib/autoRecover";
import { useResizable } from "./hooks/useResizable";
import { useTheme } from "./hooks/useTheme";

type DialogCallback = (action: "save" | "discard" | "cancel") => void;

function App() {
  const [dialogOpen, setDialogOpen] = useState(false);
  const dialogCallbackRef = useRef<DialogCallback | null>(null);

  // Panel collapse state
  const toolboxCollapsed = useStore((s) => s.toolboxCollapsed);
  const sidebarCollapsed = useStore((s) => s.sidebarCollapsed);
  const setToolboxCollapsed = useStore((s) => s.setToolboxCollapsed);
  const setSidebarCollapsed = useStore((s) => s.setSidebarCollapsed);

  // Phase 62 D-01 / D-07 — left-panel tabs + Ctrl+1/2/3 accelerators
  const activeLeftTab = useStore((s) => s.activeLeftTab);
  const setActiveLeftTab = useStore((s) => s.setActiveLeftTab);

  // Panel resize hooks
  const toolboxResize = useResizable({ direction: "left", minWidth: 120, maxWidth: 360, defaultWidth: 240 });
  const sidebarResize = useResizable({ direction: "right", minWidth: 200, maxWidth: 400, defaultWidth: 320 });

  // Theme
  const { theme, resolvedTheme, setTheme } = useTheme();

  // Returns a promise that resolves when the user picks an action.
  const showUnsavedDialog = useCallback(
    (): Promise<"save" | "discard" | "cancel"> =>
      new Promise((resolve) => {
        dialogCallbackRef.current = resolve;
        setDialogOpen(true);
      }),
    [],
  );

  function handleDialogSave() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("save");
  }
  function handleDialogDiscard() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("discard");
  }
  function handleDialogCancel() {
    setDialogOpen(false);
    dialogCallbackRef.current?.("cancel");
  }

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 08: AutoRecover crash-detection + restore modal (D-03/D-04)
  // ---------------------------------------------------------------------------

  // null  = crash check not yet run (show boot splash)
  // []    = crash check done, no crash → normal workspace
  // [...] = crash detected → show blocking restore modal
  const [restoreCandidates, setRestoreCandidates] = useState<
    RestoreCandidate[] | null
  >(null);
  const teardownRef = useRef<(() => Promise<void>) | null>(null);

  // Helper: derive a RestoreCandidate from a basename + stale lockfile
  function buildRestoreCandidate(
    basename: string,
    staleLockfile: LockfileContent | null,
  ): RestoreCandidate {
    const isUntitled = basename.startsWith("untitled-");
    const displayName = isUntitled
      ? "Unsaved project"
      : basename.replace(/\.scp\.autosave$/, "");
    const modifiedAt = staleLockfile?.startedAt ?? new Date().toISOString();
    return { basename, displayName, modifiedAt };
  }

  useEffect(() => {
    let canceled = false;
    (async () => {
      // Get current PID via Tauri IPC
      let pid = 0;
      try {
        // v2 IPC: use ES-module import, not window.__TAURI__ (which is intentionally undefined). See autoRecover.ts header for the long-form rationale.
        const { invoke } = await import("@tauri-apps/api/core");
        pid = await invoke<number>("get_pid");
      } catch {
        // Non-Tauri env (e.g. browser preview) — treat as no crash
      }

      const result = await detectCrashOnLaunch(pid);
      if (canceled) return;

      if (result.crashed) {
        // Crash detected — show modal before workspace loads.
        // DEFER initAutoRecover until user resolves the modal (D-02: don't
        // clobber the stale lockfile while we're still inspecting it).
        const candidates = result.sidecars.map((basename) =>
          buildRestoreCandidate(basename, result.staleLockfile),
        );
        setRestoreCandidates(candidates);
      } else {
        // Clean launch — start the autoRecover writer + lockfile immediately.
        setRestoreCandidates([]);
        try {
          const { teardown } = await initAutoRecover();
          if (!canceled) {
            teardownRef.current = teardown;
          } else {
            // Effect cleaned up before init returned — tear down immediately
            await teardown();
          }
        } catch (err) {
          console.error("[AutoRecover] initAutoRecover on clean launch failed:", err);
        }
      }
    })();

    return () => {
      canceled = true;
      if (teardownRef.current) {
        void teardownRef.current();
        teardownRef.current = null;
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Modal resolution handlers (try/finally: initAutoRecover always runs even on
  // error, and modal always closes — user has committed to a choice)
  async function handleRecover(basename: string) {
    try {
      await useStore.getState().recoverFromSidecar(basename);
    } catch (err) {
      console.error("[AutoRecover] Recover failed:", err);
    } finally {
      try {
        const { teardown } = await initAutoRecover();
        teardownRef.current = teardown;
      } catch (err) {
        console.error("[AutoRecover] initAutoRecover after Recover failed:", err);
      }
      setRestoreCandidates([]);
    }
  }

  async function handleDiscard() {
    try {
      await useStore.getState().discardAllSidecars();
    } catch (err) {
      console.error("[AutoRecover] Discard failed:", err);
    } finally {
      try {
        const { teardown } = await initAutoRecover();
        teardownRef.current = teardown;
      } catch (err) {
        console.error("[AutoRecover] initAutoRecover after Discard failed:", err);
      }
      setRestoreCandidates([]);
    }
  }

  // Initialize recent files on mount
  useEffect(() => {
    initializeRecentFiles();
  }, []);

  // Keyboard shortcuts (global)
  // kbLock prevents re-entrant execution: on Linux, GTK native dialogs leak
  // keystrokes (e.g. Ctrl+N = new folder) into the WebView while open, which
  // would trigger newProject() mid-save and clear the canvas.
  const kbLock = useRef(false);
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      if (kbLock.current) return;
      try {
        // Ctrl+Shift+S — Save As
        if ((e.ctrlKey || e.metaKey) && e.key === "s" && e.shiftKey) {
          e.preventDefault();
          kbLock.current = true;
          await useStore.getState().saveProjectAs();
          return;
        }
        // Ctrl+S — Save
        if ((e.ctrlKey || e.metaKey) && e.key === "s" && !e.shiftKey) {
          e.preventDefault();
          kbLock.current = true;
          await useStore.getState().saveProject();
          return;
        }
        // Ctrl+O — Open
        if ((e.ctrlKey || e.metaKey) && e.key === "o") {
          e.preventDefault();
          kbLock.current = true;
          const { isDirty: dirty } = useStore.getState();
          if (dirty) {
            const action = await showUnsavedDialog();
            if (action === "cancel") return;
            if (action === "save") await useStore.getState().saveProject();
          }
          await useStore.getState().loadProject();
          return;
        }
        // Ctrl+N — New
        if ((e.ctrlKey || e.metaKey) && e.key === "n") {
          e.preventDefault();
          kbLock.current = true;
          const { isDirty: dirty } = useStore.getState();
          if (dirty) {
            const action = await showUnsavedDialog();
            if (action === "cancel") return;
            if (action === "save") await useStore.getState().saveProject();
          }
          await useStore.getState().newProject();
          return;
        }
      } catch (err) {
        console.error("[handleKeyDown] unhandled error:", err);
      } finally {
        kbLock.current = false;
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [showUnsavedDialog]);

  // Phase 62 D-07 / INV-12 — Ctrl+1 / Ctrl+2 / Ctrl+3 left-tab accelerators.
  // Bound globally on window per UI-SPEC §"Tab strip — preventDefault on
  // accelerator". Only bare Ctrl is honored — Ctrl+Shift+N / Alt+N / Meta+N
  // are passed through so Ctrl+Shift+S (Save As) still wins. Ctrl+Tab is
  // intentionally NOT intercepted (D-07: browser-collision avoidance).
  useEffect(() => {
    const handleLeftTabKey = (e: KeyboardEvent) => {
      if (!e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
      if (e.key === "1") {
        e.preventDefault();
        setActiveLeftTab("Components");
      } else if (e.key === "2") {
        e.preventDefault();
        setActiveLeftTab("Resources");
      } else if (e.key === "3") {
        e.preventDefault();
        setActiveLeftTab("Project");
      }
    };
    window.addEventListener("keydown", handleLeftTabKey);
    return () => window.removeEventListener("keydown", handleLeftTabKey);
  }, [setActiveLeftTab]);

  // Window title sync — subscribe outside React to bypass render batching.
  // On Linux/WebKitGTK, setTitle() IPC doesn't update the GTK title bar reliably;
  // we invoke the underlying command directly as a fallback.
  useEffect(() => {
    function syncTitle(filePath: string | null, dirty: boolean) {
      const filename = filePath ? filePath.split(/[/\\]/).pop() : null;
      const marker = dirty ? "*" : "";
      const title = filename
        ? `${filename}${marker} - STREAM Composer`
        : "STREAM Composer";
      document.title = title;
      getCurrentWindow().setTitle(title).catch(console.error);
    }

    // Run immediately with current state
    const s = useStore.getState();
    syncTitle(s.currentFilePath, s.isDirty);

    // Subscribe to future changes outside React render cycle
    const unsub = useStore.subscribe((state) => {
      syncTitle(state.currentFilePath, state.isDirty);
    });
    return unsub;
  }, []);

  // Window close guard — fixed: track unlisten via ref to avoid async race in Strict Mode
  const unlistenRef = useRef<(() => void) | null>(null);
  useEffect(() => {
    let active = true;

    getCurrentWindow()
      .onCloseRequested(async (event) => {
        const { isDirty: dirty } = useStore.getState();
        if (!dirty) return; // allow close

        event.preventDefault(); // must be synchronous before any await
        const action = await showUnsavedDialog();
        if (action === "save") {
          await useStore.getState().saveProject();
        }
        if (action !== "cancel") {
          // destroy() bypasses CloseRequested — avoids re-triggering this guard
          await getCurrentWindow().destroy();
        }
      })
      .then((fn) => {
        if (!active) {
          fn(); // effect already cleaned up — unlisten immediately
        } else {
          unlistenRef.current = fn;
        }
      });

    return () => {
      active = false;
      unlistenRef.current?.();
      unlistenRef.current = null;
    };
  }, [showUnsavedDialog]);

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 08: Render gate — AutoRecover modal or boot splash (D-03)
  // ---------------------------------------------------------------------------

  // While crash check hasn't completed: show a minimal boot splash.
  if (restoreCandidates === null) {
    return <div className="h-screen w-screen bg-background" />;
  }

  // Crash detected: show blocking modal BEFORE the canvas mounts (D-03).
  if (restoreCandidates.length > 0) {
    return (
      <AutoRecoverRestoreModal
        candidates={restoreCandidates}
        onRecover={handleRecover}
        onDiscard={handleDiscard}
      />
    );
  }

  return (
    <ReactFlowProvider>
      <TooltipProvider delayDuration={500} skipDelayDuration={300}>
        <div className="flex flex-col h-screen w-screen overflow-hidden">
          <div className="flex flex-1 min-h-0">
            {!toolboxCollapsed && (
              <div
                className="relative h-full border-r shrink-0 flex flex-col overflow-hidden"
                style={{ width: toolboxResize.width }}
              >
                {/* VS Code-style sash on inner edge: 4px hit area, transparent at
                    rest, subtle hover tint, double-click to collapse. The panel's
                    `border-r` is the 1px visible line; this overlay is the hit/drag
                    surface. */}
                <div
                  role="separator"
                  aria-orientation="vertical"
                  aria-label="Resize left panel"
                  className="absolute right-0 top-0 w-1 h-full cursor-col-resize z-10 hover:bg-primary/40 active:bg-primary/60 transition-colors"
                  onMouseDown={toolboxResize.onMouseDown}
                  onDoubleClick={() => setToolboxCollapsed(true)}
                />
                {/* Phase 62 D-01 — left-panel tab strip [Components][Resources][Project].
                    ResponsiveTabsList collapses overflowing tabs into a "..." menu
                    when the panel is too narrow. UI-SPEC §Tab strip: text-only,
                    bottom-border active indicator, no bg pill. */}
                <Tabs
                  value={activeLeftTab}
                  onValueChange={(v) =>
                    setActiveLeftTab(v as "Components" | "Resources" | "Project")
                  }
                  className="flex-1 min-h-0 gap-0"
                >
                  <ResponsiveTabsList
                    tabs={[
                      { value: "Components", label: "Components", icon: Boxes },
                      { value: "Resources", label: "Resources", icon: Library },
                      { value: "Project", label: "Project", icon: Settings2 },
                    ]}
                    value={activeLeftTab}
                    onValueChange={(v) =>
                      setActiveLeftTab(v as "Components" | "Resources" | "Project")
                    }
                  />
                  <TabsContent value="Components" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ToolboxPanel />
                  </TabsContent>
                  <TabsContent value="Resources" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ResourcesTreePanel />
                  </TabsContent>
                  <TabsContent value="Project" className="flex-1 min-h-0 overflow-hidden mt-0">
                    <ModelOptionsPanel />
                  </TabsContent>
                </Tabs>
              </div>
            )}
            {/* Collapsed-edge re-expand affordance for the left panel. Renders only
                when the panel is hidden: a 4px clickable strip flush with the canvas
                edge. Cursor + tooltip do the discovery work. */}
            {toolboxCollapsed && (
              <button
                type="button"
                aria-label="Expand left panel"
                title="Expand left panel"
                className="h-full w-1 shrink-0 border-r cursor-pointer hover:bg-primary/40 transition-colors"
                onClick={() => setToolboxCollapsed(false)}
              />
            )}
            <div className="flex flex-col flex-1 min-w-0">
              <Toolbar onUnsavedCheck={showUnsavedDialog} theme={theme} resolvedTheme={resolvedTheme} setTheme={setTheme} />
              <CanvasPanel resolvedTheme={resolvedTheme} />
            </div>
            {sidebarCollapsed && (
              <button
                type="button"
                aria-label="Expand right panel"
                title="Expand right panel"
                className="h-full w-1 shrink-0 border-l cursor-pointer hover:bg-primary/40 transition-colors"
                onClick={() => setSidebarCollapsed(false)}
              />
            )}
            {!sidebarCollapsed && (
              <SidebarPanel
                width={sidebarResize.width}
                onResizeMouseDown={sidebarResize.onMouseDown}
                onCollapse={() => setSidebarCollapsed(true)}
              />
            )}
          </div>
          <BottomPanel />
        </div>
        <UnsavedChangesDialog
          open={dialogOpen}
          onSave={handleDialogSave}
          onDiscard={handleDialogDiscard}
          onCancel={handleDialogCancel}
        />
        <ValidationDialog />
      </TooltipProvider>
    </ReactFlowProvider>
  );
}

export default App;
