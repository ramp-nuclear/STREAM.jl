// EdgeContextMenu.tsx — stateless context menu content for canvas edges (Phase 65 Plan 05)
// Rendered inside a DropdownMenu wrapper in CanvasPanel.tsx; dispatches store actions directly.
//
// Phase 65 Plan 11 iteration (UAT 2026-05-15): uses DropdownMenuItem (a Radix Menu primitive)
// so it participates in the outer DropdownMenu's roving-tabindex keyboard nav.

import { DropdownMenuItem } from "@/components/ui/dropdown-menu";
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
      <DropdownMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </DropdownMenuItem>
      {/* Phase 71: render Show errors item when validation state exists for edgeId */}
    </div>
  );
}
