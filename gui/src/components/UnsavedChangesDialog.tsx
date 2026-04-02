import { Button } from "./ui/button";

interface Props {
  open: boolean;
  onSave: () => void;
  onDiscard: () => void;
  onCancel: () => void;
}

export default function UnsavedChangesDialog({
  open,
  onSave,
  onDiscard,
  onCancel,
}: Props) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/50"
        onClick={onCancel}
      />
      {/* Dialog */}
      <div className="relative z-10 bg-background border rounded-lg shadow-lg p-6 w-80 flex flex-col gap-4">
        <div>
          <h2 className="text-base font-semibold mb-1">Save changes?</h2>
          <p className="text-sm text-muted-foreground">
            Your project has unsaved changes that will be lost if you don't save.
          </p>
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="outline" size="sm" onClick={onCancel}>
            Cancel
          </Button>
          <Button variant="outline" size="sm" onClick={onDiscard}>
            Don't Save
          </Button>
          <Button size="sm" onClick={onSave}>
            Save
          </Button>
        </div>
      </div>
    </div>
  );
}
