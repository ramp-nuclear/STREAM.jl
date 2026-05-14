// CanvasContextMenu.tsx — stateless context menu content for the empty canvas pane (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx.
//
// Architecture note (W10): uses PopoverMenuItem / PopoverMenuSub* (context-free) instead of
// ContextMenuItem / ContextMenuSub* — styled identically but no Radix Root context required.

import {
  PopoverMenuItem,
  PopoverMenuSeparator,
  PopoverMenuSub,
  PopoverMenuSubContent,
  PopoverMenuSubTrigger,
} from "@/components/ui/context-menu";
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
    // Phase 65 v1.2: paste lands at the offset Plan 04 computes, NOT at the right-click
    // position. Revisit if user feedback demands click-anchored paste.
    void useStore.getState().pasteFromClipboard();
    onClose();
  }

  return (
    <div role="menu" data-slot="canvas-context-menu">
      <PopoverMenuItem onSelect={handlePaste}>Paste</PopoverMenuItem>
      <PopoverMenuItem disabled>Auto-Layout (future)</PopoverMenuItem>
      <PopoverMenuSeparator />
      <PopoverMenuSub>
        <PopoverMenuSubTrigger>Add Component</PopoverMenuSubTrigger>
        <PopoverMenuSubContent>
          <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />
        </PopoverMenuSubContent>
      </PopoverMenuSub>
    </div>
  );
}
