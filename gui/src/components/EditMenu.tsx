import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarSeparator,
  MenubarTrigger,
} from "./ui/menubar";
import useStore from "../store/useStore";

/**
 * Edit menu (Phase 67 D-10, D-22).
 *
 * Round 2 — migrated from DropdownMenu to shadcn Menubar so the parent
 * <Menubar> in CustomTitlebar coordinates click-once switching between
 * sibling menus (UAT round 2 #5).
 *
 * D-19 — Edit menu items fire unconditionally — no input-focus guard.
 * Phase 65 keyboard listeners in CanvasPanel.tsx:222-247 own the guard
 * for the Ctrl+* accelerators; the menu path is an explicit user intent
 * so it intentionally bypasses the guard.
 *
 * D-22 — Paste binds to `pasteFromClipboard` (NOT `pasteClipboard`).
 * Accelerator labels are display-only; the keydown listeners live in
 * Phase 65's CanvasPanel.
 */
export default function EditMenu() {
  // D-19 — Edit menu items fire unconditionally — no input-focus guard.
  // Phase 65 keyboard listeners in CanvasPanel.tsx:222-247 own the guard;
  // menu path is explicit user intent.
  const undo = useStore((s) => s.undo);
  const redo = useStore((s) => s.redo);
  const cutSelection = useStore((s) => s.cutSelection);
  const copySelection = useStore((s) => s.copySelection);
  const pasteFromClipboard = useStore((s) => s.pasteFromClipboard);
  const duplicateSelection = useStore((s) => s.duplicateSelection);

  return (
    <MenubarMenu>
      <MenubarTrigger className="h-full rounded-none px-3 py-0 text-xs font-normal hover:bg-accent hover:text-accent-foreground">
        Edit
      </MenubarTrigger>
      <MenubarContent align="start">
        <MenubarItem onClick={() => undo()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Undo</span>
            <span className="text-muted-foreground text-xs">Ctrl+Z</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={() => redo()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Redo</span>
            <span className="text-muted-foreground text-xs">Ctrl+Y</span>
          </span>
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem onClick={() => void cutSelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Cut</span>
            <span className="text-muted-foreground text-xs">Ctrl+X</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={() => void copySelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Copy</span>
            <span className="text-muted-foreground text-xs">Ctrl+C</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={() => void pasteFromClipboard()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Paste</span>
            <span className="text-muted-foreground text-xs">Ctrl+V</span>
          </span>
        </MenubarItem>
        <MenubarItem onClick={() => duplicateSelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Duplicate</span>
            <span className="text-muted-foreground text-xs">Ctrl+D</span>
          </span>
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem disabled>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Preferences...</span>
            <span className="text-muted-foreground text-xs"></span>
          </span>
        </MenubarItem>
      </MenubarContent>
    </MenubarMenu>
  );
}
