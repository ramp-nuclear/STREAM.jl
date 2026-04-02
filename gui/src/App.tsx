import { useEffect, useRef, useState, useCallback } from "react";
import { ReactFlowProvider } from "@xyflow/react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import ToolboxPanel from "./components/ToolboxPanel";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";
import Toolbar from "./components/Toolbar";
import BottomPanel from "./components/BottomPanel";
import UnsavedChangesDialog from "./components/UnsavedChangesDialog";
import useStore from "./store/useStore";
import { initializeRecentFiles } from "./store/useStore";

type DialogCallback = (action: "save" | "discard" | "cancel") => void;

function App() {
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);

  const [dialogOpen, setDialogOpen] = useState(false);
  const dialogCallbackRef = useRef<DialogCallback | null>(null);

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

  // Initialize recent files on mount
  useEffect(() => {
    initializeRecentFiles();
  }, []);

  // Keyboard shortcuts (global)
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      // Ctrl+Shift+S or Cmd+Shift+S — Save As
      if ((e.ctrlKey || e.metaKey) && e.key === "s" && e.shiftKey) {
        e.preventDefault();
        await useStore.getState().saveProjectAs();
        return;
      }
      // Ctrl+S or Cmd+S — Save
      if ((e.ctrlKey || e.metaKey) && e.key === "s" && !e.shiftKey) {
        e.preventDefault();
        await useStore.getState().saveProject();
        return;
      }
      // Ctrl+O or Cmd+O — Open
      if ((e.ctrlKey || e.metaKey) && e.key === "o") {
        e.preventDefault();
        const { isDirty: dirty } = useStore.getState();
        if (dirty) {
          const action = await showUnsavedDialog();
          if (action === "cancel") return;
          if (action === "save") await useStore.getState().saveProject();
        }
        await useStore.getState().loadProject();
        return;
      }
      // Ctrl+N or Cmd+N — New
      if ((e.ctrlKey || e.metaKey) && e.key === "n") {
        e.preventDefault();
        const { isDirty: dirty } = useStore.getState();
        if (dirty) {
          const action = await showUnsavedDialog();
          if (action === "cancel") return;
          if (action === "save") await useStore.getState().saveProject();
        }
        await useStore.getState().newProject();
        return;
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [showUnsavedDialog]);

  // Window title sync
  useEffect(() => {
    const win = getCurrentWindow();
    const filename = currentFilePath
      ? currentFilePath.split(/[/\\]/).pop()
      : null;
    const dirty = isDirty ? "*" : "";
    const title = filename
      ? `${filename}${dirty} - STREAM Composer`
      : `STREAM Composer${dirty}`;
    win.setTitle(title);
  }, [isDirty, currentFilePath]);

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

  return (
    <ReactFlowProvider>
      <div className="flex flex-col h-screen w-screen overflow-hidden">
        <div className="flex flex-1 min-h-0">
          <ToolboxPanel />
          <div className="flex flex-col flex-1">
            <Toolbar onUnsavedCheck={showUnsavedDialog} />
            <CanvasPanel />
          </div>
          <SidebarPanel />
        </div>
        <BottomPanel />
      </div>
      <UnsavedChangesDialog
        open={dialogOpen}
        onSave={handleDialogSave}
        onDiscard={handleDialogDiscard}
        onCancel={handleDialogCancel}
      />
    </ReactFlowProvider>
  );
}

export default App;
