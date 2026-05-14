// CanvasContextMenu.tsx — stateless context menu content for the empty canvas pane (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx.

import {
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuSub,
  ContextMenuSubContent,
  ContextMenuSubTrigger,
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
    <>
      <ContextMenuItem onSelect={handlePaste}>Paste</ContextMenuItem>
      <ContextMenuItem disabled>Auto-Layout (future)</ContextMenuItem>
      <ContextMenuSeparator />
      <ContextMenuSub>
        <ContextMenuSubTrigger>Add Component</ContextMenuSubTrigger>
        <ContextMenuSubContent>
          <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />
        </ContextMenuSubContent>
      </ContextMenuSub>
    </>
  );
}
