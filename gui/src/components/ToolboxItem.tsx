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
      className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-md cursor-grab hover:bg-accent transition-colors"
    >
      <Icon className="w-4 h-4 text-muted-foreground" />
      {label}
    </div>
  );
}
