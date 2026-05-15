// NodeContextMenu.tsx — stateless context menu content for canvas nodes (Phase 65 Plan 05)
// Rendered inside a DropdownMenu wrapper in CanvasPanel.tsx; dispatches store actions directly.
//
// Phase 65 Plan 11 iteration (UAT 2026-05-15): switched from PopoverMenuItem (a hand-rolled
// div outside any Radix Menu context) to DropdownMenuItem. The new outer wrapper is a Radix
// DropdownMenu, which gives all items roving-tabindex keyboard nav and hover-driven highlight
// for free.

import {
  DropdownMenuItem,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import useStore from "@/store/useStore";

interface NodeContextMenuProps {
  nodeId: string;
  onClose: () => void;
}

export default function NodeContextMenu({ nodeId, onClose }: NodeContextMenuProps) {
  function handleRename() {
    useStore.getState().selectNode(nodeId);
    window.dispatchEvent(
      new CustomEvent("stream:focus-instance-name", { detail: { nodeId } }),
    );
    onClose();
  }

  function handleDuplicate() {
    useStore.getState().selectNode(nodeId);
    useStore.getState().duplicateSelection();
    onClose();
  }

  function handleShowCode() {
    if (useStore.getState().bottomPanelOpen === false) {
      useStore.getState().toggleBottomPanel();
    }
    window.dispatchEvent(
      new CustomEvent("stream:show-code-for", { detail: { nodeId } }),
    );
    onClose();
  }

  function handleDelete() {
    useStore.getState().removeNode(nodeId);
    onClose();
  }

  return (
    <div role="menu" data-slot="node-context-menu">
      <DropdownMenuItem onSelect={handleRename}>Rename</DropdownMenuItem>
      <DropdownMenuItem onSelect={handleDuplicate}>Duplicate</DropdownMenuItem>
      <DropdownMenuItem onSelect={handleShowCode}>
        Show generated Julia code
      </DropdownMenuItem>
      {/* Phase 71: render Show errors item when validation state exists for nodeId */}
      <DropdownMenuSeparator />
      <DropdownMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </DropdownMenuItem>
    </div>
  );
}
