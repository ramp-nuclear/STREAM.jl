import { useEffect, useMemo, useRef, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Textarea } from "./ui/textarea";
import { Label } from "./ui/label";
import { RadioGroup, RadioGroupItem } from "./ui/radio-group";
import { cn } from "@/lib/utils";
import useStore from "@/store/useStore";
import {
  autoExtendSelection,
  isValidPresetName,
} from "@/lib/presetIO";

// ---------------------------------------------------------------------------
// SavePresetModal
//
// Radix Dialog for saving the current selection as a named .scpr preset.
//
// Responsibilities:
//  - On open: focus the Name input and paint the amber dashed outline on any
//    nodes that are auto-extended by the BC-hop rule (D-12 / Surface 9).
//  - Validate the Name field live: required, charset [A-Za-z0-9_-]+, no
//    collision with existing presets in the chosen store (D-10, T-70-18).
//  - On save: call useStore.getState().saveSelectionAsPreset and close.
//  - On close (any path: Discard, Save, ESC, click-outside): clear the
//    data.autoExtended flag from every node (T-70-19).
// ---------------------------------------------------------------------------

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

/**
 * Modal dialog for saving the current canvas selection as a `.scpr` preset.
 *
 * Opened by triggers in plan 70-06 (FileMenu and NodeContextMenu). The amber
 * dashed outline on auto-extended nodes is painted on open and cleared on
 * every close path.
 *
 * # Arguments
 * - `open`          — Whether the dialog is open
 * - `onOpenChange`  — Called with `false` when the dialog should close
 */
export default function SavePresetModal({ open, onOpenChange }: Props) {
  // ---------------------------------------------------------------------------
  // Store selectors
  // ---------------------------------------------------------------------------
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const currentFilePath = useStore((s) => s.currentFilePath);
  const projectPresets = useStore((s) => s.projectPresets);
  const libraryPresets = useStore((s) => s.libraryPresets);

  // ---------------------------------------------------------------------------
  // Local state
  // ---------------------------------------------------------------------------
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [store, setStore] = useState<"library" | "project">("library");
  const [saving, setSaving] = useState(false);
  const nameInputRef = useRef<HTMLInputElement | null>(null);

  // Project open when currentFilePath is not null.
  const projectIsOpen = currentFilePath !== null;

  // ---------------------------------------------------------------------------
  // WR-08: reset fields on every close (any path: Discard, ESC, click-outside)
  // so a re-open never shows stale name/description from a prior session.
  // ---------------------------------------------------------------------------
  useEffect(() => {
    if (open) return;
    setName("");
    setDescription("");
    setStore("library");
    setSaving(false);
  }, [open]);

  // ---------------------------------------------------------------------------
  // On open: focus name input + paint amber outline on auto-extended nodes.
  // Cleanup runs on every open change (including close), clearing the flag.
  // ---------------------------------------------------------------------------
  useEffect(() => {
    if (!open) return;

    // Focus the name field after the dialog animation frame.
    const t = setTimeout(() => nameInputRef.current?.focus(), 0);

    // Compute auto-extended IDs (nodes included by BC-hop but not selected).
    const selectedIds = new Set(
      useStore.getState().nodes.filter((n) => n.selected).map((n) => n.id),
    );
    const { extendedIds } = autoExtendSelection(
      selectedIds,
      useStore.getState().nodes,
      useStore.getState().edges,
    );
    const extras = new Set([...extendedIds].filter((id) => !selectedIds.has(id)));

    // Paint the transient amber outline flag on the extra nodes.
    if (extras.size > 0) {
      useStore.setState((state) => ({
        nodes: state.nodes.map((n) =>
          extras.has(n.id) ? { ...n, data: { ...n.data, autoExtended: true } } : n,
        ),
      }));
    }

    return () => {
      clearTimeout(t);
      // Clear autoExtended from every node when modal closes (any code path).
      // This is the single authoritative cleanup — ESC, click-outside, Discard,
      // and successful Save all trigger onOpenChange(false) → open flips → this
      // cleanup fires.
      useStore.setState((state) => ({
        nodes: state.nodes.map((n) => {
          if (!n.data || !("autoExtended" in (n.data as Record<string, unknown>)))
            return n;
          const { autoExtended: _x, ...rest } = n.data as Record<string, unknown>;
          return { ...n, data: rest as typeof n.data };
        }),
      }));
    };
  }, [open]);

  // ---------------------------------------------------------------------------
  // Auto-extended count for the info line (Surface 9, A-07).
  // Recomputed when open state or node/edge topology changes.
  // ---------------------------------------------------------------------------
  const autoExtendedCount = useMemo(() => {
    if (!open) return 0;
    const selectedIds = new Set(nodes.filter((n) => n.selected).map((n) => n.id));
    const { extendedIds } = autoExtendSelection(selectedIds, nodes, edges);
    return [...extendedIds].filter((id) => !selectedIds.has(id)).length;
  }, [open, nodes, edges]);

  // ---------------------------------------------------------------------------
  // Live validation
  // ---------------------------------------------------------------------------
  const existingNames = useMemo(() => {
    const arr = store === "library" ? libraryPresets : projectPresets;
    return new Set(arr.map((e) => e.name));
  }, [store, libraryPresets, projectPresets]);

  const nameError: string | null = (() => {
    if (name.length === 0) return "Name is required.";
    if (!isValidPresetName(name)) return "Use only letters, digits, underscores, or hyphens.";
    if (existingNames.has(name)) {
      const storeLabel = store === "library" ? "the library" : "this project";
      return "A preset with this name already exists in " + storeLabel + ".";
    }
    return null;
  })();

  // ---------------------------------------------------------------------------
  // Save handler
  // ---------------------------------------------------------------------------
  async function handleSave() {
    if (nameError) return;
    if (saving) return;
    setSaving(true);
    try {
      await useStore.getState().saveSelectionAsPreset(name, description, store);
      onOpenChange(false);
      // Field reset is handled by the close useEffect (WR-08).
    } catch (err) {
      console.error("Save preset failed", err);
    } finally {
      setSaving(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Save as Preset</DialogTitle>
        </DialogHeader>

        <div className="flex flex-col gap-[16px]">
          {/* Name */}
          <div className="flex flex-col gap-[8px]">
            <Label
              htmlFor="preset-name"
              className="text-body font-semibold leading-[1.4]"
            >
              Name
            </Label>
            <Input
              ref={nameInputRef}
              id="preset-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. mtr-fuel-assembly"
              aria-invalid={nameError !== null ? true : undefined}
              className={cn(nameError && "border-destructive ring-destructive/30")}
            />
            {nameError && name.length > 0 && (
              <p className="text-destructive text-label leading-[1.4]">{nameError}</p>
            )}
          </div>

          {/* Description */}
          <div className="flex flex-col gap-[8px]">
            <Label
              htmlFor="preset-desc"
              className="text-body font-semibold leading-[1.4]"
            >
              Description
            </Label>
            <Textarea
              id="preset-desc"
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Optional description shown on hover"
            />
          </div>

          {/* Store */}
          <div className="flex flex-col gap-[8px]">
            <Label className="text-body font-semibold leading-[1.4]">Store</Label>
            <RadioGroup
              value={store}
              onValueChange={(v) => setStore(v as "library" | "project")}
            >
              <div className="flex items-center gap-2">
                <RadioGroupItem value="library" id="store-library" />
                <Label htmlFor="store-library">Library (user-global)</Label>
              </div>
              <div
                className={cn(
                  "flex items-center gap-2",
                  !projectIsOpen && "opacity-50 cursor-not-allowed",
                )}
              >
                <RadioGroupItem
                  value="project"
                  id="store-project"
                  disabled={!projectIsOpen}
                />
                <Label htmlFor="store-project">Project (this project)</Label>
              </div>
            </RadioGroup>
            {!projectIsOpen && (
              <p className="text-label text-muted-foreground">Open a project first.</p>
            )}
          </div>

          {/* Auto-extend info (hidden when count is 0, per A-07) */}
          {autoExtendedCount > 0 && (
            <p className="text-label text-muted-foreground">
              {autoExtendedCount} additional component(s) included via BC connections.
            </p>
          )}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Discard
          </Button>
          <Button
            variant="default"
            disabled={!!nameError || saving}
            onClick={handleSave}
          >
            Save Preset
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
