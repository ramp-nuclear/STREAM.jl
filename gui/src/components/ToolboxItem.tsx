import { getComponentIcon } from "@/registry/icons";

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
