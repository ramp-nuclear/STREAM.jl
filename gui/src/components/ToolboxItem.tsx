interface ToolboxItemProps {
  componentId: string;
  label: string;
}

export default function ToolboxItem({ componentId, label }: ToolboxItemProps) {
  const onDragStart = (event: React.DragEvent) => {
    event.dataTransfer.setData("application/streamcomponent", componentId);
    event.dataTransfer.effectAllowed = "move";
  };

  return (
    <div
      draggable
      onDragStart={onDragStart}
      className="text-sm px-2 py-1.5 rounded-md cursor-grab hover:bg-accent transition-colors"
    >
      {label}
    </div>
  );
}
