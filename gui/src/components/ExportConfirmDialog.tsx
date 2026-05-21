/**
 * ExportConfirmDialog — Phase 71 UAT Test 14 follow-up (2026-05-21).
 *
 * Visibility is driven by useStore.pendingDiagnosticExport (set by exportCode
 * when it bails on diagnostic-only errors). Cancel / "Export anyway" route to
 * exportCode's cancelPendingExport / confirmPendingExport helpers, which own
 * the continuation closure.
 *
 * Mounted globally (App.tsx) so the same modal serves every caller of
 * exportCode (BottomPanel toolbar + FileMenu).
 *
 * Copy: terse engineering-tool voice. No "Are you sure?", no
 * "We strongly recommend...". Just the fact and the two buttons.
 */

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import useStore from "../store/useStore";
import {
  confirmPendingExport,
  cancelPendingExport,
} from "../lib/exportCode";

export default function ExportConfirmDialog() {
  const pending = useStore((s) => s.pendingDiagnosticExport);
  const open = pending !== null;
  const count = pending?.count ?? 0;

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (!next) cancelPendingExport();
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Export with errors</AlertDialogTitle>
          <AlertDialogDescription>
            {count} {count === 1 ? "error" : "errors"} present. Code will
            compile; solver may not converge.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel onClick={cancelPendingExport}>
            Cancel
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={() => {
              void confirmPendingExport();
            }}
          >
            Export anyway
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
