import { useEffect } from "react";
import { ReactFlowProvider } from "@xyflow/react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import ToolboxPanel from "./components/ToolboxPanel";
import CanvasPanel from "./components/CanvasPanel";
import SidebarPanel from "./components/SidebarPanel";
import Toolbar from "./components/Toolbar";
import BottomPanel from "./components/BottomPanel";
import { promptUnsavedChanges } from "./components/FileMenu";
import useStore from "./store/useStore";
import { initializeRecentFiles } from "./store/useStore";

function App() {
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);

  // Initialize recent files on mount
  useEffect(() => {
    initializeRecentFiles();
  }, []);

  // Keyboard shortcuts (global)
  useEffect(() => {
    const handleKeyDown = async (e: KeyboardEvent) => {
      // Ctrl+Shift+S or Cmd+Shift+S — Save As (must check shiftKey before plain Ctrl+S)
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
          const action = await promptUnsavedChanges();
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
          const action = await promptUnsavedChanges();
          if (action === "cancel") return;
          if (action === "save") await useStore.getState().saveProject();
        }
        await useStore.getState().newProject();
        return;
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

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

  // Window close guard
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    getCurrentWindow()
      .onCloseRequested(async (event) => {
        const { isDirty: dirty } = useStore.getState();
        if (!dirty) return; // Allow close

        event.preventDefault(); // MUST call synchronously before async work
        const action = await promptUnsavedChanges();
        if (action === "save") {
          await useStore.getState().saveProject();
          await getCurrentWindow().close();
        } else if (action === "discard") {
          // Temporarily clear isDirty so the recursive close doesn't re-trigger
          useStore.setState({ isDirty: false });
          await getCurrentWindow().close();
        }
        // "cancel" -> do nothing, window stays open
      })
      .then((fn) => {
        unlisten = fn;
      });

    return () => {
      unlisten?.();
    };
  }, []);

  return (
    <ReactFlowProvider>
      <div className="flex flex-col h-screen w-screen overflow-hidden">
        <div className="flex flex-1 min-h-0">
          <ToolboxPanel />
          <div className="flex flex-col flex-1">
            <Toolbar />
            <CanvasPanel />
          </div>
          <SidebarPanel />
        </div>
        <BottomPanel />
      </div>
    </ReactFlowProvider>
  );
}

export default App;
