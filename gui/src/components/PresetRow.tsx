import { useEffect, useRef, useState } from "react";
import { GripVertical } from "lucide-react";
import { cn } from "@/lib/utils";
import { Input } from "./ui/input";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "./ui/context-menu";
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
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "./ui/tooltip";
import useStore from "@/store/useStore";
import {
  isValidPresetName,
  type PresetIndexEntry,
} from "@/lib/presetIO";

// Phase 70 Plan 70-04 — single preset row inside the Presets tab.
//
// Implements per-row interactions per UI-SPEC Surface 2/3/4:
//   - HTML drag (MIME type for preset payload, D-16)
//   - Inline rename (F2; Enter commits; Esc cancels; blur commits)
//   - Tooltip on name span showing description (side="right" when non-empty)
//   - Right-click context menu: Rename / Delete / separator / Reveal in Finder/Explorer
//   - Delete: AlertDialog confirmation modal per UI-SPEC Surface 4
//
// D-19.1 — Edit description action intentionally absent from the context menu.

interface PresetRowProps {
  entry: PresetIndexEntry;
  onRequestReveal: () => void;
}

export default function PresetRow({ entry, onRequestReveal }: PresetRowProps) {
  // ── Inline-rename state ────────────────────────────────────────────────────
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState(entry.name);
  const [renameError, setRenameError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  // ── Delete confirmation ────────────────────────────────────────────────────
  const [confirmOpen, setConfirmOpen] = useState(false);

  // Keep renameValue in sync if the underlying entry name changes externally.
  useEffect(() => {
    if (!renaming) {
      setRenameValue(entry.name);
    }
  }, [entry.name, renaming]);

  // Focus the rename input when entering rename mode.
  useEffect(() => {
    if (renaming) {
      const t = setTimeout(() => {
        inputRef.current?.focus();
        inputRef.current?.select();
      }, 0);
      return () => clearTimeout(t);
    }
  }, [renaming]);

  // ── Validation ─────────────────────────────────────────────────────────────
  function validateNewName(name: string): string | null {
    if (!name) return "Name is required.";
    if (!isValidPresetName(name)) {
      return "Use only letters, digits, underscores, or hyphens.";
    }
    // Collision check: look in the same store as this entry.
    const state = useStore.getState();
    const pool =
      entry.store === "project" ? state.projectPresets : state.libraryPresets;
    const collision = pool.some(
      (e) => e.name === name && e.filePath !== entry.filePath,
    );
    if (collision) {
      return `A preset with this name already exists in ${entry.store}.`;
    }
    return null;
  }

  // ── Handlers ───────────────────────────────────────────────────────────────
  function startRename() {
    setRenameValue(entry.name);
    setRenameError(null);
    setRenaming(true);
  }

  function cancelRename() {
    setRenaming(false);
    setRenameValue(entry.name);
    setRenameError(null);
  }

  async function commitRename() {
    // No-op if unchanged.
    if (renameValue === entry.name) {
      setRenaming(false);
      setRenameError(null);
      return;
    }
    const err = validateNewName(renameValue);
    if (err) {
      setRenameError(err);
      return; // Stay in rename mode.
    }
    try {
      await useStore.getState().renamePreset(entry.filePath, renameValue);
      setRenaming(false);
      setRenameError(null);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setRenameError(msg);
      // Stay in rename mode.
    }
  }

  async function handleConfirmedDelete() {
    await useStore.getState().deletePreset(entry.filePath);
    setConfirmOpen(false);
  }

  function handleRowKeyDown(e: React.KeyboardEvent) {
    if (renaming) return;
    if (e.key === "F2") {
      e.preventDefault();
      startRename();
    }
  }

  function handleDragStart(e: React.DragEvent) {
    e.dataTransfer.setData(
      "application/stream-preset",
      JSON.stringify({ filePath: entry.filePath, store: entry.store }),
    );
    e.dataTransfer.effectAllowed = "move";
  }

  // ── Row body ───────────────────────────────────────────────────────────────
  const rowBody = (
    <li
      draggable={!renaming}
      onDragStart={handleDragStart}
      onKeyDown={handleRowKeyDown}
      tabIndex={0}
      className="h-[22px] px-[8px] text-[13px] flex items-center gap-2 cursor-grab select-none min-w-0 overflow-hidden hover:bg-accent rounded-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
    >
      <GripVertical className="h-3 w-3 text-muted-foreground shrink-0" />

      {renaming ? (
        <div className="flex-1 min-w-0">
          <Input
            ref={inputRef}
            value={renameValue}
            onChange={(e) => {
              setRenameValue(e.target.value);
              setRenameError(validateNewName(e.target.value));
            }}
            className={cn(
              "h-[24px] py-0 px-[6px] text-[13px] shadow-none",
              renameError && "border-destructive ring-destructive/30",
            )}
            title={renameError ?? undefined}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                void commitRename();
              }
              if (e.key === "Escape") {
                e.preventDefault();
                cancelRename();
              }
              e.stopPropagation();
            }}
            onBlur={() => {
              void commitRename();
            }}
            aria-invalid={renameError ? true : undefined}
            aria-label={`Rename ${entry.name}`}
          />
        </div>
      ) : (
        <Tooltip>
          <TooltipTrigger asChild>
            <span className="truncate flex-1 min-w-0">{entry.name}</span>
          </TooltipTrigger>
          {entry.description && (
            <TooltipContent side="right" className="max-w-[200px] whitespace-normal">
              {entry.description}
            </TooltipContent>
          )}
        </Tooltip>
      )}
    </li>
  );

  // ── Context menu wrap ──────────────────────────────────────────────────────
  return (
    <>
      <ContextMenu>
        <ContextMenuTrigger asChild>{rowBody}</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuItem onSelect={startRename}>Rename</ContextMenuItem>
          <ContextMenuItem
            variant="destructive"
            onSelect={() => setConfirmOpen(true)}
          >
            Delete
          </ContextMenuItem>
          <ContextMenuSeparator />
          <ContextMenuItem onSelect={() => onRequestReveal()}>
            Reveal in Finder/Explorer
          </ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>

      {/* Delete confirmation modal (UI-SPEC Surface 4) */}
      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete preset?</AlertDialogTitle>
            <AlertDialogDescription>
              {`Delete ${entry.name}? This removes the file from ${
                entry.store === "library" ? "your library" : "this project"
              } and cannot be undone.`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep Preset</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={() => {
                void handleConfirmedDelete();
              }}
            >
              Delete Preset
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
