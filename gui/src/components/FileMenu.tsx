import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarTrigger,
} from "./ui/menubar";
import useStore from "../store/useStore";

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
      </MenubarContent>
    </MenubarMenu>
  );
}
