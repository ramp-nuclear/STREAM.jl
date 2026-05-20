import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarSeparator,
  MenubarTrigger,
} from "./ui/menubar";
import { useReactFlow } from "@xyflow/react";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";

interface Props {
  onUnsavedCheck: () => Promise<"save" | "discard" | "cancel">;
}

/**
 * File menu (Phase 67 D-10).
 *
 * Round 2 — migrated from DropdownMenu to shadcn Menubar primitive so the
 * parent <Menubar> in CustomTitlebar coordinates click-once switching
 * between sibling menus (Office / VSCode / IntelliJ pattern — UAT round 2 #5).
 *
 * Trigger styles override the Menubar defaults to match the chrome strip:
 * full titlebar height, zero rounding, ghost hover, text-xs font-normal —
 * preserving the round-2 Task 3 trigger height work.
 */
export default function FileMenu({ onUnsavedCheck }: Props) {
  const isDirty = useStore((s) => s.isDirty);
  const saveProject = useStore((s) => s.saveProject);
  const saveProjectAs = useStore((s) => s.saveProjectAs);
  const loadProject = useStore((s) => s.loadProject);
  const newProject = useStore((s) => s.newProject);

  async function handleNew() {
    if (isDirty) {
      const action = await onUnsavedCheck();
      if (action === "cancel") return;
      if (action === "save") await saveProject();
    }
    await newProject();
  }

  async function handleOpen() {
    if (isDirty) {
      const action = await onUnsavedCheck();
      if (action === "cancel") return;
      if (action === "save") await saveProject();
    }
    await loadProject();
  }

  async function handleSave() {
    await saveProject();
  }

  async function handleSaveAs() {
    await saveProjectAs();
  }

  // Phase 70 D-15.1 — Preset menu handlers.
  // FileMenu is rendered inside ReactFlowProvider (App.tsx line 457), so
  // useReactFlow() is safe here.
  const { getViewport } = useReactFlow();
  const selectedNodeCount = useStore((s) => s.nodes.filter((n) => n.selected).length);

  // Pre-paint the auto-extend amber outline BEFORE opening the modal so the
  // highlight is visible while the modal animates in (defensive UX — the modal's
  // own useEffect also paints, but doing it here avoids a one-frame flash).
  function handleSaveSelectionAsPreset() {
    const { nodes, edges } = useStore.getState();
    const selectedIds = new Set(nodes.filter((n) => n.selected).map((n) => n.id));
    import("../lib/presetIO").then(({ autoExtendSelection }) => {
      const { extendedIds } = autoExtendSelection(selectedIds, nodes, edges);
      const extras = new Set([...extendedIds].filter((id) => !selectedIds.has(id)));
      if (extras.size > 0) {
        useStore.setState((state) => ({
          nodes: state.nodes.map((n) =>
            extras.has(n.id) ? { ...n, data: { ...n.data, autoExtended: true } } : n,
          ),
        }));
      }
      window.dispatchEvent(new CustomEvent("stream:open-save-preset"));
    });
  }

  async function handleLoadPreset() {
    const vp = getViewport();
    // D-17: bbox-center at the current viewport center.
    const centerX = (-vp.x + window.innerWidth / 2) / vp.zoom;
    const centerY = (-vp.y + window.innerHeight / 2) / vp.zoom;
    try {
      await useStore.getState().loadPresetFromPath({ x: centerX, y: centerY });
    } catch (err) {
      console.error("[FileMenu] Load preset failed", err);
    }
  }

  // Phase 68 D-09 — Export to Julia rehomed from the now-deleted secondary
  // toolbar strip. Same generateCode + exportCode arg shape as the previous
  // toolbar Export handler so the menu entry and the BottomPanel Export
  // button (D-12, kept by design) are behaviorally identical.
  async function handleExportToJulia() {
    const s = useStore.getState();
    const sections = generateCode(
      s.nodes,
      s.edges,
      { anchors: s.anchors },
      getComponent,
      s.resources,
      { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
    );
    await exportCode({ sections, nodes: s.nodes });
  }

  return (
    <MenubarMenu>
      <MenubarTrigger className="h-full rounded-none px-3 py-0 text-xs font-normal hover:bg-accent hover:text-accent-foreground">
        File
      </MenubarTrigger>
      <MenubarContent align="start">
        <MenubarItem onClick={handleNew}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>New</span>
            <span className="text-muted-foreground text-xs">Ctrl+N</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={handleOpen}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Open...</span>
            <span className="text-muted-foreground text-xs">Ctrl+O</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={handleSave}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Save</span>
            <span className="text-muted-foreground text-xs">Ctrl+S</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={handleSaveAs}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Save As...</span>
            <span className="text-muted-foreground text-xs">Ctrl+Shift+S</span>
          </span>
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem onClick={handleLoadPreset}>
          Load preset…
        </MenubarItem>
        <MenubarItem
          onClick={handleSaveSelectionAsPreset}
          disabled={selectedNodeCount < 2}
        >
          Save selection as preset…
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem
          onClick={handleExportToJulia}
          className="text-xs font-normal"
        >
          Export to Julia…
        </MenubarItem>
      </MenubarContent>
    </MenubarMenu>
  );
}
