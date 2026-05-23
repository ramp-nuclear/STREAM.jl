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
      {/* Backdrop — bg-foreground/40 matches the locked Dialog scrim (no blur,
          no glassmorphism per DESIGN.md §4). */}
      <div
        className="absolute inset-0 bg-foreground/40"
        onClick={onCancel}
      />
      {/* Dialog — bg-popover + --shadow-dialog match the locked Dialog vocab
          (DESIGN.md §4 single-tier structural shadow + popover tonal step). */}
      <div className="relative z-10 bg-popover border border-border rounded-md shadow-[var(--shadow-dialog)] p-6 w-80 flex flex-col gap-4">
        <div>
          <h2 className="text-title font-semibold mb-1">Save changes?</h2>
          <p className="text-body text-foreground/65">
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
