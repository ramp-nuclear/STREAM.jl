// NodeContextMenu.tsx — stateless context menu content for canvas nodes (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx; dispatches store actions directly.

import {
  ContextMenuItem,
  ContextMenuSeparator,
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
    <>
      <ContextMenuItem onSelect={handleRename}>Rename</ContextMenuItem>
      <ContextMenuItem onSelect={handleDuplicate}>Duplicate</ContextMenuItem>
      <ContextMenuItem onSelect={handleShowCode}>
        Show generated Julia code
      </ContextMenuItem>
      {/* Phase 71: render Show errors item when validation state exists for nodeId */}
      <ContextMenuSeparator />
      <ContextMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </ContextMenuItem>
    </>
  );
}
