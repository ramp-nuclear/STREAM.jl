// CanvasContextMenu.tsx — stateless context menu content for the empty canvas pane (Phase 65 Plan 05)
// Rendered inside a DropdownMenu wrapper in CanvasPanel.tsx.
//
// Phase 65 Plan 11 iteration (UAT 2026-05-15): the entire canvas right-click menu lives inside
// a single Radix DropdownMenu (set up in CanvasPanel.tsx). Add Component is now a real
// DropdownMenuSub — Radix gives Sub triggers native safe-polygon hover handling, keyboard
// navigation (ArrowRight/Enter to open, ArrowLeft/Esc to close), and viewport-collision-aware
// SubContent placement via Floating UI flip+shift. Previously we used Popover for the outer
// host + nested DropdownMenu(defaultOpen=true) for Add Component, which had to hand-roll
// hover-to-open with timers and produced flicker.

import {
  DropdownMenuItem,
  DropdownMenuPortal,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from "@/components/ui/dropdown-menu";
import useStore from "@/store/useStore";
import AddComponentSubmenu from "./AddComponentSubmenu";

interface CanvasContextMenuProps {
  flowPosition: { x: number; y: number };
  onClose: () => void;
}

export default function CanvasContextMenu({
  flowPosition,
  onClose,
}: CanvasContextMenuProps) {
  function handlePaste() {
    void useStore.getState().pasteFromClipboard();
    onClose();
  }

  return (
    <div role="menu" data-slot="canvas-context-menu">
      <DropdownMenuItem onSelect={handlePaste}>Paste</DropdownMenuItem>
      <DropdownMenuItem disabled>Auto-Layout (future)</DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuSub>
        <DropdownMenuSubTrigger>Add Component</DropdownMenuSubTrigger>
        <DropdownMenuPortal>
          <DropdownMenuSubContent sideOffset={2}>
            <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />
          </DropdownMenuSubContent>
        </DropdownMenuPortal>
      </DropdownMenuSub>
    </div>
  );
}
