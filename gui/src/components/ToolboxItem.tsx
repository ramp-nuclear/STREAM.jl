import { useRef } from "react";
import { getComponentIcon } from "@/registry/icons";

interface ToolboxItemProps {
  componentId: string;
  label: string;
}

export default function ToolboxItem({ componentId, label }: ToolboxItemProps) {
  const Icon = getComponentIcon(componentId);
  // The custom drag-image element. Rendered off-screen and used as the
  // setDragImage target so the cursor carries a compact chip with just the
  // component icon + name instead of the full toolbox row (which looked
  // janky — the entire hovered toolbox card followed the cursor).
  const ghostRef = useRef<HTMLDivElement | null>(null);

  const onDragStart = (event: React.DragEvent) => {
    event.dataTransfer.setData("application/streamcomponent", componentId);
    event.dataTransfer.effectAllowed = "move";
    if (ghostRef.current) {
      // Offset the ghost so the chip is positioned slightly below-right of
      // the cursor — easier to see where you're dropping than centered.
      event.dataTransfer.setDragImage(ghostRef.current, 12, 12);
    }
  };

  return (
    <>
      <div
        draggable
        onDragStart={onDragStart}
        title={label}
        className="flex items-center gap-2 text-[13px] px-2 h-[24px] rounded-md cursor-grab hover:bg-accent transition-colors min-w-0"
      >
        <Icon className="w-4 h-4 text-muted-foreground shrink-0" />
        <span className="truncate">{label}</span>
      </div>
      {/*
        Off-screen drag-image source. Must be in the DOM (not display:none —
        setDragImage requires a rendered element) and positioned so the user
        never sees it normally. -9999px is the canonical trick.
      */}
      <div
        ref={ghostRef}
        aria-hidden="true"
        className="absolute -left-[9999px] -top-[9999px] flex items-center gap-1.5 px-2 py-1 text-xs rounded-md bg-panel border shadow-md pointer-events-none whitespace-nowrap"
      >
        <Icon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
        <span>{label}</span>
      </div>
    </>
  );
}
