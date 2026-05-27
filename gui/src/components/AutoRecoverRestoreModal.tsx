// AutoRecoverRestoreModal.tsx — Blocking restore modal for AutoRecover (Phase 65 D-03/D-04)
//
// Rendered BEFORE the canvas mounts when a crash is detected on launch.
// Cannot be dismissed via Esc / outside-click — user MUST click Recover or Discard.
//
// Uses Radix @radix-ui/react-dialog directly (no shadcn dialog.tsx in this project).

import * as Dialog from "@radix-ui/react-dialog";
import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * A candidate for restoration. Typically one entry per crashed session.
 */
export interface RestoreCandidate {
  /** e.g. "foo.scp.autosave" or "untitled-<uuid>.scp.autosave" */
  basename: string;
  /** User-facing label: "foo" or "Unsaved project" */
  displayName: string;
  /** ISO timestamp from the staleLockfile.startedAt (D-03 "<timestamp>") */
  modifiedAt: string;
}

interface AutoRecoverRestoreModalProps {
  candidates: RestoreCandidate[];
  onRecover: (basename: string) => void;
  onDiscard: () => void;
}

/**
 * Blocking modal dialog shown on launch after a crash is detected.
 *
 * # Arguments
 * - `candidates` — sidecar basenames to offer for recovery (typically 1)
 * - `onRecover`  — called with the chosen basename when user clicks Recover
 * - `onDiscard`  — called when user clicks Discard (no arguments)
 *
 * # Returns
 * null if candidates is empty (defensive; App.tsx should not pass zero candidates)
 */
export default function AutoRecoverRestoreModal({
  candidates,
  onRecover,
  onDiscard,
}: AutoRecoverRestoreModalProps): React.ReactElement | null {
  if (candidates.length === 0) {
    return null;
  }

  if (candidates.length > 1) {
    console.warn(
      "[AutoRecover] Multiple sidecars detected; restoring most recent only.",
    );
  }

  const candidate = candidates[0]!;

  // Format the timestamp for display. Use the raw ISO string so the date
  // portion (YYYY-MM-DD) is always visible — locale formatting would obscure
  // the exact date/time which matters for crash recovery decisions (D-03).
  // Replace the 'T' separator with a space for readability (e.g. "2026-05-14 10:30:00Z").
  const displayTimestamp = candidate.modifiedAt.replace("T", " ");

  return (
    <Dialog.Root open={true}>
      {/* Portal renders the dialog as a sibling of document.body — above any canvas */}
      <Dialog.Portal>
        {/* Overlay covers the entire screen to prevent interaction with anything behind */}
        <Dialog.Overlay
          className="fixed inset-0 z-50 bg-transparent"
        />
        <Dialog.Content
          // Block Esc from closing the dialog (D-03 invariant — decision must be made)
          onEscapeKeyDown={(e) => e.preventDefault()}
          // Block outside-click from closing the dialog (D-03)
          onPointerDownOutside={(e) => e.preventDefault()}
          // Block focus leaving the dialog
          onInteractOutside={(e) => e.preventDefault()}
          className="fixed left-1/2 top-1/2 z-50 -translate-x-1/2 -translate-y-1/2 w-full max-w-md rounded-md border border-[var(--dialog-border)] bg-[var(--dialog-surface)] p-6 shadow-[var(--shadow-dialog)]"
          aria-describedby="autorecover-description"
        >
          {/* Header */}
          <Dialog.Title className="flex items-center gap-2 text-title font-semibold text-foreground">
            <AlertTriangle className="h-5 w-5 text-[color:var(--color-warning)] shrink-0" aria-hidden />
            Unsaved changes detected
          </Dialog.Title>

          {/* Body — verbatim D-03 wording */}
          <p
            id="autorecover-description"
            className="mt-3 text-body text-foreground/85 leading-relaxed"
          >
            Recover unsaved work from{" "}
            <span className="font-medium text-foreground">{displayTimestamp}</span>
            {" "}in{" "}
            <span className="font-medium text-foreground">{candidate.displayName}</span>?
          </p>

          <p className="mt-2 text-label text-muted-foreground">
            The app did not close gracefully last time. You can restore your
            unsaved changes or discard them and start fresh.
          </p>

          {/* Actions — switched from hand-rolled buttons (px-4 py-2 + rounded-md
              + transition-colors) to the Button primitive. The Discard button
              keeps its destructive intent via className overrides on the
              outline variant; locked Button doesn't carry a destructive-outline
              variant so the local override is the right surface for it. */}
          <div className="mt-6 flex justify-end gap-3">
            <Button
              variant="outline"
              onClick={() => onDiscard()}
              className="text-destructive hover:bg-destructive/10 hover:text-destructive"
            >
              Discard
            </Button>
            <Button onClick={() => onRecover(candidate.basename)}>
              Recover
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
