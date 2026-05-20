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
import { autoExtendSelection } from "@/lib/presetIO";

interface NodeContextMenuProps {
  nodeId: string;
  onClose: () => void;
}

export default function NodeContextMenu({ nodeId, onClose }: NodeContextMenuProps) {
  // Phase 70 D-15.1 — read selection count synchronously from the store at
  // render time (Pitfall 9: must reflect the full multi-selection, not just
  // the right-clicked node).
  const selectionCount = useStore((s) => s.nodes.filter((n) => n.selected).length);

  // Mirrors the FileMenu handler: pre-paint auto-extend amber outline then
  // dispatch the custom event to open SavePresetModal in App.tsx.
  // CR-03: use static import (presetIO is already in the main bundle via
  // SavePresetModal) so autoExtendSelection + dispatchEvent run synchronously
  // before onClose(), eliminating the stale-autoExtended race.
  function handleSaveSelectionAsPreset() {
    const { nodes, edges } = useStore.getState();
    const selectedIds = new Set(nodes.filter((n) => n.selected).map((n) => n.id));
    const { extendedIds } = autoExtendSelection(selectedIds, nodes, edges);
    const extras = new Set([...extendedIds].filter((id) => !selectedIds.has(id)));
    if (extras.size > 0) {
      useStore.setState((state) => ({
        nodes: state.nodes.map((n) =>
          extras.has(n.id) ? { ...n, data: { ...n.data, autoExtended: true } } : n,
        ),
      }));
    }
    window.dispatchEvent(new CustomEvent("stream:open-save-preset"));
    onClose();
  }

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
      {/* Phase 70 D-15.1: visible only when ≥ 2 nodes are selected (render guard,
          not disabled — per UI-SPEC Surface 6). */}
      {selectionCount >= 2 && (
        <DropdownMenuItem onSelect={handleSaveSelectionAsPreset}>
          Save selection as preset…
        </DropdownMenuItem>
      )}
      <DropdownMenuSeparator />
      <DropdownMenuItem variant="destructive" onSelect={handleDelete}>
        Delete
      </DropdownMenuItem>
    </div>
  );
}
