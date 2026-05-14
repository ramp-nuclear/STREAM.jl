// NodeContextMenu.tsx — stateless context menu content for canvas nodes (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx; dispatches store actions directly.
//
// Architecture note (W10): ContextMenuItem requires Radix MenuContentContext which is
// unavailable inside a Popover. We use PopoverMenuItem / PopoverMenuSeparator from
// context-menu.tsx — styled identically but context-free (plain HTML + Tailwind).

import {
  PopoverMenuItem,
  PopoverMenuSeparator,
} from "@/components/ui/context-menu";
import useStore from "@/store/useStore";

interface NodeContextMenuProps {
  nodeId: string;
  onClose: () => void;
}

export default function NodeContextMenu({ nodeId, onClose }: NodeContextMenuProps) {
  function handleRename() {
    // W7 lock: select the node so the sidebar opens to it, then dispatch focus event.
    useStore.getState().selectNode(nodeId);
    window.dispatchEvent(
      new CustomEvent("stream:focus-instance-name", { detail: { nodeId } }),
    );
    onClose();
  }

  function handleDuplicate() {
    // Select the node first so duplicateSelection targets it.
    useStore.getState().selectNode(nodeId);
    useStore.getState().duplicateSelection();
    onClose();
  }

  function handleShowCode() {
    // W8 lock: open the bottom panel if closed; do NOT toggle off if already open.
    if (useStore.getState().bottomPanelOpen === false) {
      useStore.getState().toggleBottomPanel();
    }
    // TODO: Phase 66 — listen to stream:show-code-for and scroll the CodePreview to
    // the matching section.
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
      <PopoverMenuItem onSelect={handleRename}>Rename</PopoverMenuItem>
      <PopoverMenuItem onSelect={handleDuplicate}>Duplicate</PopoverMenuItem>
      <PopoverMenuItem onSelect={handleShowCode}>
        Show generated Julia code
      </PopoverMenuItem>
      {/* Phase 71: render Show errors item when validation state exists for nodeId */}
      <PopoverMenuSeparator />
      <PopoverMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </PopoverMenuItem>
    </div>
  );
}
