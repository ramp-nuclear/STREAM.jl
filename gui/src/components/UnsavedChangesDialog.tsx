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
      {/* Backdrop — transparent. Click-outside still cancels; no dim grey
          filter on the canvas (feedback_no_grey_modal_surface_or_scrim). */}
      <div
        className="absolute inset-0 bg-transparent"
        onClick={onCancel}
      />
      {/* Dialog — --dialog-surface + --dialog-border + atmospheric
          --shadow-dialog match the locked Dialog vocab post-Preferences. */}
      <div className="relative z-10 bg-[var(--dialog-surface)] border border-[var(--dialog-border)] rounded-md shadow-[var(--shadow-dialog)] p-6 w-80 flex flex-col gap-4">
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
