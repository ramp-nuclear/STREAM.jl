import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import useStore from "../store/useStore";

/**
 * Edit menu (Phase 67 D-10, D-22).
 *
 * D-19 — Edit menu items fire unconditionally — no input-focus guard.
 * Phase 65 keyboard listeners in CanvasPanel.tsx:222-247 own the guard
 * for the Ctrl+* accelerators; the menu path is an explicit user intent
 * so it intentionally bypasses the guard.
 *
 * D-22 — Paste binds to `pasteFromClipboard` (NOT `pasteClipboard`).
 * Accelerator labels are display-only; the keydown listeners live in
 * Phase 65's CanvasPanel.
 */
export default function EditMenu() {
  // D-19 — Edit menu items fire unconditionally — no input-focus guard.
  // Phase 65 keyboard listeners in CanvasPanel.tsx:222-247 own the guard;
  // menu path is explicit user intent.
  const undo = useStore((s) => s.undo);
  const redo = useStore((s) => s.redo);
  const cutSelection = useStore((s) => s.cutSelection);
  const copySelection = useStore((s) => s.copySelection);
  const pasteFromClipboard = useStore((s) => s.pasteFromClipboard);
  const duplicateSelection = useStore((s) => s.duplicateSelection);

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="h-full rounded-none px-3 py-0 text-xs font-normal"
        >
          Edit
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuItem onClick={() => undo()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Undo</span>
            <span className="text-muted-foreground text-xs">Ctrl+Z</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => redo()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Redo</span>
            <span className="text-muted-foreground text-xs">Ctrl+Y</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => void cutSelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Cut</span>
            <span className="text-muted-foreground text-xs">Ctrl+X</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => void copySelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Copy</span>
            <span className="text-muted-foreground text-xs">Ctrl+C</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => void pasteFromClipboard()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Paste</span>
            <span className="text-muted-foreground text-xs">Ctrl+V</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => duplicateSelection()}>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Duplicate</span>
            <span className="text-muted-foreground text-xs">Ctrl+D</span>
          </span>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem disabled>
          <span className="flex justify-between w-full items-center gap-4">
            <span>Preferences...</span>
            <span className="text-muted-foreground text-xs"></span>
          </span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
