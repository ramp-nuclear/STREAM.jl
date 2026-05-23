import {
  MenubarContent,
  MenubarItem,
  MenubarMenu,
  MenubarSeparator,
  MenubarShortcut,
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
      <MenubarTrigger className="h-full rounded-none px-3 py-0 font-normal hover:bg-accent hover:text-accent-foreground">
        Edit
      </MenubarTrigger>
      <MenubarContent align="start">
        <MenubarItem onClick={() => undo()}>
          Undo
          <MenubarShortcut>Ctrl+Z</MenubarShortcut>
        </MenubarItem>
        <MenubarItem onClick={() => redo()}>
          Redo
          <MenubarShortcut>Ctrl+Y</MenubarShortcut>
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem onClick={() => void cutSelection()}>
          Cut
          <MenubarShortcut>Ctrl+X</MenubarShortcut>
        </MenubarItem>
        <MenubarItem onClick={() => void copySelection()}>
          Copy
          <MenubarShortcut>Ctrl+C</MenubarShortcut>
        </MenubarItem>
        <MenubarItem onClick={() => void pasteFromClipboard()}>
          Paste
          <MenubarShortcut>Ctrl+V</MenubarShortcut>
        </MenubarItem>
        <MenubarItem onClick={() => duplicateSelection()}>
          Duplicate
          <MenubarShortcut>Ctrl+D</MenubarShortcut>
        </MenubarItem>
        <MenubarSeparator />
        <MenubarItem
          onClick={() =>
            window.dispatchEvent(new CustomEvent("stream:open-preferences"))
          }
        >
          Preferences...
          <MenubarShortcut>Ctrl+,</MenubarShortcut>
        </MenubarItem>
      </MenubarContent>
    </MenubarMenu>
  );
}
