// CanvasContextMenu.tsx — stateless context menu content for the empty canvas pane (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx.
//
// Architecture note (Phase 65 Plan 11): Add Component is now hosted inside a Radix
// DropdownMenu (defaultOpen=true) so its per-category submenus (DropdownMenuSub*) get
// Floating-UI viewport-collision-aware placement. Paste / Auto-Layout / Separator
// remain plain PopoverMenuItem / PopoverMenuSeparator (leaves of the Popover host).

import { ChevronRightIcon } from "lucide-react";
import {
  PopoverMenuItem,
  PopoverMenuSeparator,
} from "@/components/ui/context-menu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuPortal,
  DropdownMenuTrigger,
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
      <DropdownMenu
        defaultOpen={true}
        onOpenChange={(open) => {
          if (!open) onClose();
        }}
      >
        <DropdownMenuTrigger asChild>
          <div
            role="menuitem"
            tabIndex={0}
            data-slot="popover-menu-item"
            className="relative flex cursor-default items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-hidden select-none hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground data-[state=open]:bg-accent data-[state=open]:text-accent-foreground"
          >
            Add Component
            <ChevronRightIcon className="ml-auto size-4" />
          </div>
        </DropdownMenuTrigger>
        <DropdownMenuPortal>
          <DropdownMenuContent side="right" align="start" sideOffset={4}>
            <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />
          </DropdownMenuContent>
        </DropdownMenuPortal>
      </DropdownMenu>
    </div>
  );
}
