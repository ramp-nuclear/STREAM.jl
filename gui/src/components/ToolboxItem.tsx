import { getComponentIcon } from "@/registry/icons";

// TODO Phase 72 — drag preview redesign. Current state uses the browser's
// default HTML5 drag image (the row itself), which produces a janky UX:
// the cursor shows the no-drop indicator over non-droppable zones, then
// the drag image isn't visible over the canvas before drop. The
// `setDragImage` ghost-element approach was tried in 74a4371 and didn't
// render reliably in WebView2 (off-screen source elements are sometimes
// skipped). Defer to the design-system pass for a complete drag-feedback
// rethink.

interface ToolboxItemProps {
  componentId: string;
  label: string;
}

export default function ToolboxItem({ componentId, label }: ToolboxItemProps) {
  const Icon = getComponentIcon(componentId);

  const onDragStart = (event: React.DragEvent) => {
    event.dataTransfer.setData("application/streamcomponent", componentId);
    event.dataTransfer.effectAllowed = "move";
  };

  return (
    <div
      draggable
      onDragStart={onDragStart}
      title={label}
      className="flex items-center gap-2 text-[13px] px-2 h-[24px] rounded-md cursor-grab hover:bg-accent transition-colors min-w-0"
    >
      <Icon className="w-4 h-4 text-muted-foreground shrink-0" />
      <span className="truncate">{label}</span>
    </div>
  );
}
