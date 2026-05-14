// EdgeContextMenu.tsx — stateless context menu content for canvas edges (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx; dispatches store actions directly.
//
// Architecture note (W10): uses PopoverMenuItem (context-free) instead of ContextMenuItem.

import { PopoverMenuItem } from "@/components/ui/context-menu";
import useStore from "@/store/useStore";

interface EdgeContextMenuProps {
  edgeId: string;
  onClose: () => void;
}

export default function EdgeContextMenu({ edgeId, onClose }: EdgeContextMenuProps) {
  function handleDelete() {
    useStore.getState().onEdgesChange([{ id: edgeId, type: "remove" }]);
    onClose();
  }

  return (
    <div role="menu" data-slot="edge-context-menu">
      <PopoverMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </PopoverMenuItem>
      {/* Phase 71: render Show errors item when validation state exists for edgeId */}
    </div>
  );
}
