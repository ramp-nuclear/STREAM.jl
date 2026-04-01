export default function SidebarPanel() {
  return (
    <div className="w-80 h-full border-l p-4 overflow-y-auto">
      <h2 className="text-lg font-semibold mb-4">Properties</h2>
      <p className="text-sm text-muted-foreground">
        Select a component on the canvas to view its properties.
      </p>
    </div>
  );
}
