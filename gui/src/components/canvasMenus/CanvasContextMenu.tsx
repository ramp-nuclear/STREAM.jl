// CanvasContextMenu.tsx — stateless context menu content for the empty canvas pane (Phase 65 Plan 05)
// Rendered inside a Popover wrapper in CanvasPanel.tsx.
//
// Architecture note (Phase 65 Plan 11): Add Component is hosted inside a Radix
// DropdownMenu so its per-category submenus (DropdownMenuSub*) get Floating-UI
// viewport-collision-aware placement. Paste / Auto-Layout / Separator remain
// plain PopoverMenuItem / PopoverMenuSeparator (leaves of the Popover host).
//
// Phase 65 Plan 11 iteration (UAT 2026-05-15): the DropdownMenu is now
// hover-driven, not `defaultOpen={true}`. The previous always-open behavior
// showed the categories panel before the user hovered Add Component, which
// looked like the item was permanently "selected". A 150ms grace timer
// bridges the gap when the pointer travels from the trigger to the portalled
// content.

import { useEffect, useRef, useState } from "react";
import { ChevronRightIcon } from "lucide-react";
import {
  PopoverMenuItem,
  PopoverMenuSeparator,
} from "@/components/ui/context-menu";
import {
  DropdownMenu,
  DropdownMenuContent,
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
  const [submenuOpen, setSubmenuOpen] = useState(false);
  const closeTimerRef = useRef<number | null>(null);

  function cancelClose() {
    if (closeTimerRef.current !== null) {
      window.clearTimeout(closeTimerRef.current);
      closeTimerRef.current = null;
    }
  }

  function scheduleClose() {
    cancelClose();
    closeTimerRef.current = window.setTimeout(() => {
      setSubmenuOpen(false);
    }, 150);
  }

  useEffect(() => cancelClose, []);

  function handlePaste() {
    void useStore.getState().pasteFromClipboard();
    onClose();
  }

  return (
    <div role="menu" data-slot="canvas-context-menu">
      <PopoverMenuItem onSelect={handlePaste}>Paste</PopoverMenuItem>
      <PopoverMenuItem disabled>Auto-Layout (future)</PopoverMenuItem>
      <PopoverMenuSeparator />
      <DropdownMenu open={submenuOpen} onOpenChange={setSubmenuOpen}>
        <DropdownMenuTrigger asChild>
          <div
            role="menuitem"
            tabIndex={0}
            onMouseEnter={() => { cancelClose(); setSubmenuOpen(true); }}
            onMouseLeave={scheduleClose}
            onClick={() => { cancelClose(); setSubmenuOpen(true); }}
            data-slot="popover-menu-item"
            // No `onFocus={open}` here — Radix Popover/Dropdown close routines shuffle
            // focus during teardown, which would re-fire onFocus and re-open the submenu
            // ("closes for a second and reopens" bug, UAT 2026-05-15). Keyboard users
            // can open via Enter/Space/ArrowRight — Radix DropdownMenuTrigger handles
            // those natively. `focus-visible:` (not `focus:`) so programmatic focus
            // during open/close transitions doesn't draw a persistent highlight.
            className="relative flex cursor-default items-center gap-2 rounded-sm px-2 py-1.5 text-sm outline-hidden select-none hover:bg-accent hover:text-accent-foreground focus-visible:bg-accent focus-visible:text-accent-foreground data-[state=open]:bg-accent data-[state=open]:text-accent-foreground"
          >
            Add Component
            <ChevronRightIcon className="ml-auto size-4" />
          </div>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          side="right"
          align="start"
          sideOffset={4}
          onMouseEnter={cancelClose}
          onMouseLeave={scheduleClose}
        >
          <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );
}
