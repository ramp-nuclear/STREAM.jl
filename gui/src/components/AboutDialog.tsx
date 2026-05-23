import { useEffect, useState } from "react";
import { getVersion } from "@tauri-apps/api/app";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Button } from "./ui/button";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * Informational About dialog (D-12, D-20).
 *
 * - Controlled via `open` / `onOpenChange` (same shape as ValidationDialog).
 * - Fetches `getVersion()` asynchronously (Pitfall 8: getVersion() is a
 *   Promise; rendering `{getVersion()}` directly would print
 *   "[object Promise]"). Phase 72 clarify — placeholder switched from
 *   em-dash to "unknown" (engineering-voice; em-dash is a locked Don't).
 * - GitHub URL is hardcoded inline per D-20.
 */
export default function AboutDialog({ open, onOpenChange }: Props) {
  const [version, setVersion] = useState<string>("unknown");

  useEffect(() => {
    getVersion()
      .then(setVersion)
      .catch(() => setVersion("unknown"));
  }, []);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>STREAM Composer</DialogTitle>
          <DialogDescription>Version {version}</DialogDescription>
        </DialogHeader>
        <div className="py-2 text-sm">
          <a
            href="https://github.com/ramp-nuclear/STREAM.jl"
            target="_blank"
            rel="noreferrer"
            className="underline underline-offset-2 hover:text-foreground"
          >
            View on GitHub
          </a>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Close
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
