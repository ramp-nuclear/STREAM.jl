import { AlertTriangle } from "lucide-react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";
import useStore from "../store/useStore";

export default function ValidationDialog() {
  const validationResult = useStore((s) => s.validationResult);

  const isOpen = validationResult !== null && !validationResult.valid;
  const nodeErrors = validationResult?.nodeErrors ?? [];
  const systemErrors = validationResult?.systemErrors ?? [];

  function handleDismiss() {
    // Clear validationResult to close dialog, but keep errorNodeIds for red rings
    useStore.setState({ validationResult: null });
  }

  return (
    <AlertDialog open={isOpen} onOpenChange={(open) => { if (!open) handleDismiss(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle className="flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 text-destructive" />
            Validation Failed
          </AlertDialogTitle>
          <AlertDialogDescription>
            Fix the following issues before exporting.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="space-y-4 py-2">
          {nodeErrors.length > 0 && (
            <div>
              {systemErrors.length > 0 && (
                <h4 className="text-xs font-semibold mb-2">Node Errors</h4>
              )}
              <ul className="space-y-1">
                {nodeErrors.map((err, i) => (
                  <li key={i} className="text-sm">
                    {err.instanceName}: {err.portName} unconnected
                  </li>
                ))}
              </ul>
            </div>
          )}
          {systemErrors.length > 0 && (
            <div>
              {nodeErrors.length > 0 && (
                <h4 className="text-xs font-semibold mb-2">System Errors</h4>
              )}
              <ul className="space-y-1">
                {systemErrors.map((err, i) => (
                  <li key={i} className="text-sm">{err.message}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
        <AlertDialogFooter>
          <AlertDialogAction onClick={handleDismiss}>
            Back to Canvas
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
