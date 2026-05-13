import { useEffect, useMemo, useRef, useState } from "react";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Popover,
  PopoverAnchor,
  PopoverContent,
} from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import useStore, {
  type GeometryResource,
  type PowerShapeResource,
  type FluidResource,
  type StreamNodeData,
} from "@/store/useStore";

// Phase 62 Plan 62-06 — single Resource row inside the Resources tree.
//
// Implements per-row interactions per UI-SPEC §"Resources tree":
//   - selection (single-click → selectResource(uuid, kind))
//   - inline rename (F2 OR double-click; Enter commits; Esc cancels;
//     click-outside commits; collision blocks commit and stays in rename mode)
//   - per-row context menu (Rename / Duplicate / Delete / Show usages)
//   - Delete: immediate if usage count == 0; AlertDialog if usage count > 0
//   - Show usages: anchored Popover listing consuming component instances
//
// Keyboard navigation across rows (Up/Down/Home/End on role="treeitem") is
// intentionally deferred per UI-SPEC §"Inside Resources tab — keyboard nav
// after switch" (CD-01 leeway — Tab-only nav for v1). Document the decision
// here so the next maintainer knows where to add it.

export type ResourceKind = "geometry" | "powerShape" | "fluid";

// Phase 62-13: detect both the registry param name (live ParameterForm path)
// and the _ref-suffixed legacy key (codeGenerator fallback, .scp fixtures).
// ParameterForm.tsx writes UUIDs under `param.name` ("geometry" / "power_shape"),
// while legacy fixtures and existing .scp files store them under
// "geometry_ref" / "power_shape_ref". codeGenerator.ts:803 already does this
// dual-key fallback (`power_shape_ref ?? power_shape`); the usage scan here
// now mirrors that discipline so the AlertDialog fires in the live app, not
// just under the legacy fixture key.
const PARAM_KEY_BY_KIND: Record<ResourceKind, readonly string[]> = {
  geometry: ["geometry", "geometry_ref"],
  powerShape: ["power_shape", "power_shape_ref"],
  fluid: [],
};

export interface ResourceRowProps {
  resource: GeometryResource | PowerShapeResource | FluidResource;
  kind: ResourceKind;
  isSelected: boolean;
}

export default function ResourceRow({
  resource,
  kind,
  isSelected,
}: ResourceRowProps) {
  const isFluidPlaceholder = kind === "fluid";

  // Inline-rename state
  const [renaming, setRenaming] = useState(false);
  const [renameValue, setRenameValue] = useState(resource.name);
  const [renameError, setRenameError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement | null>(null);

  // Delete-with-usages confirmation
  const [confirmOpen, setConfirmOpen] = useState(false);

  // Show usages popover
  const [usagesOpen, setUsagesOpen] = useState(false);

  // Compute usage count and list (only for non-fluid kinds — fluids have no
  // usage tracking in Phase 62). Phase 62-13: scan BOTH the registry param
  // key (live ParameterForm path) AND the _ref-suffixed legacy key — see
  // PARAM_KEY_BY_KIND above and codeGenerator.ts:803 for the precedent.
  const nodes = useStore((s) => s.nodes);
  const usages = useMemo(() => {
    const paramKeys = PARAM_KEY_BY_KIND[kind];
    if (paramKeys.length === 0) return [];
    return nodes.filter((n) => {
      const data = n.data as unknown as StreamNodeData;
      const params = data?.parameters as Record<string, unknown> | undefined;
      if (!params) return false;
      return paramKeys.some((k) => params[k] === resource.uuid);
    });
  }, [nodes, kind, resource.uuid]);

  // Keep renameValue in sync if the underlying resource name changes
  // (e.g., another action renamed it while this row was not in rename mode).
  useEffect(() => {
    if (!renaming) {
      setRenameValue(resource.name);
    }
  }, [resource.name, renaming]);

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

  function startRename() {
    if (isFluidPlaceholder) return;
    setRenameValue(resource.name);
    setRenameError(null);
    setRenaming(true);
  }

  function commitRename() {
    // Special-case: trying to commit the unchanged name is a successful no-op.
    if (renameValue === resource.name) {
      setRenaming(false);
      setRenameError(null);
      return;
    }
    try {
      // The store action accepts kind "geometry" | "powerShape" only. Fluids
      // are the placeholder branch (rename suppressed via isFluidPlaceholder).
      useStore
        .getState()
        .renameResource(kind as "geometry" | "powerShape", resource.uuid, renameValue);
      setRenaming(false);
      setRenameError(null);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setRenameError(msg);
      // Stay in rename mode per UI-SPEC: "collision blocks commit but the
      // user stays in rename mode until they fix or cancel."
    }
  }

  function cancelRename() {
    setRenaming(false);
    setRenameError(null);
    setRenameValue(resource.name);
  }

  function handleRowClick() {
    if (renaming) return;
    useStore
      .getState()
      .selectResource(resource.uuid, kind);
  }

  function handleRowDoubleClick(e: React.MouseEvent) {
    if (isFluidPlaceholder) return;
    e.preventDefault();
    startRename();
  }

  function handleRowKeyDown(e: React.KeyboardEvent) {
    if (renaming) return;
    if (e.key === "F2") {
      e.preventDefault();
      startRename();
    }
  }

  function handleDuplicate() {
    if (isFluidPlaceholder) return;
    try {
      useStore
        .getState()
        .duplicateResource(kind as "geometry" | "powerShape", resource.uuid);
    } catch (err) {
      console.error("[ResourceRow] duplicate failed:", err);
    }
  }

  function handleDelete() {
    if (isFluidPlaceholder) return;
    if (usages.length > 0) {
      setConfirmOpen(true);
      return;
    }
    useStore
      .getState()
      .removeResource(kind as "geometry" | "powerShape", resource.uuid);
  }

  function handleConfirmedDelete() {
    useStore
      .getState()
      .removeResource(kind as "geometry" | "powerShape", resource.uuid);
    setConfirmOpen(false);
  }

  function handleShowUsages() {
    setUsagesOpen(true);
  }

  // Locked row class set per UI-SPEC §"Resources tree" — 28px height, 13px
  // text, weight 600 when selected. Fluid placeholder gets text-muted and
  // no hover bg shift.
  const rowClass = cn(
    "h-[22px] px-[8px] text-[13px] flex items-center cursor-pointer select-none min-w-0 overflow-hidden",
    isFluidPlaceholder
      ? "text-muted-foreground cursor-default"
      : "hover:bg-muted",
    isSelected && !isFluidPlaceholder && "bg-secondary font-medium",
    !isSelected && "font-normal",
  );

  // The inner row content — either the inline-rename Input or the name span.
  // Wrapping in a fragment-equivalent <span> keeps the DOM shape stable for
  // ContextMenuTrigger.
  const rowInner = renaming ? (
    <Input
      ref={inputRef}
      value={renameValue}
      onChange={(e) => {
        setRenameValue(e.target.value);
        if (renameError) setRenameError(null);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          commitRename();
        } else if (e.key === "Escape") {
          e.preventDefault();
          cancelRename();
        }
        // Stop propagation so the row-level keydown doesn't see F2 etc.
        e.stopPropagation();
      }}
      onBlur={() => {
        // Click-outside commits per UI-SPEC. If commit fails (collision),
        // commitRename keeps renaming=true and surfaces the error.
        commitRename();
      }}
      onClick={(e) => e.stopPropagation()}
      aria-invalid={renameError ? true : undefined}
      aria-label={`Rename ${resource.name}`}
      className={cn(
        "h-[24px] py-0 px-[6px] text-[13px] shadow-none",
        renameError && "border-destructive ring-destructive/30",
      )}
      title={renameError ?? undefined}
    />
  ) : (
    <span className="truncate" data-testid={`resource-row-name-${resource.uuid}`}>
      {resource.name}
    </span>
  );

  const baseRow = (
    <li
      role="treeitem"
      aria-selected={isSelected}
      tabIndex={0}
      data-resource-uuid={resource.uuid}
      data-resource-kind={kind}
      className={rowClass}
      onClick={handleRowClick}
      onDoubleClick={handleRowDoubleClick}
      onKeyDown={handleRowKeyDown}
    >
      {rowInner}
    </li>
  );

  // Fluid placeholder: skip context menu entirely (UI-SPEC).
  if (isFluidPlaceholder) {
    return baseRow;
  }

  return (
    <>
      <Popover open={usagesOpen} onOpenChange={setUsagesOpen}>
        <ContextMenu>
          <ContextMenuTrigger asChild>
            <PopoverAnchor asChild>{baseRow}</PopoverAnchor>
          </ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuItem onSelect={startRename}>Rename</ContextMenuItem>
            <ContextMenuItem onSelect={handleDuplicate}>Duplicate</ContextMenuItem>
            <ContextMenuItem variant="destructive" onSelect={handleDelete}>
              Delete
            </ContextMenuItem>
            <ContextMenuItem onSelect={handleShowUsages}>Show usages</ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
        {usagesOpen && (
          <PopoverContent
            align="start"
            side="right"
            sideOffset={4}
            className="w-[240px] p-0"
          >
            <div className="px-[12px] py-[8px] text-xs font-semibold border-b">
              Used by {usages.length} component(s)
            </div>
            <ScrollArea className="max-h-[200px]">
              <ul className="p-[4px]">
                {usages.length === 0 && (
                  <li className="text-[12px] italic text-muted-foreground px-[8px] py-[4px]">
                    No usages.
                  </li>
                )}
                {usages.map((n) => {
                  const data = n.data as unknown as StreamNodeData;
                  const label = data?.instanceName ?? n.id;
                  return (
                    <li
                      key={n.id}
                      className="text-[12px] px-[8px] py-[4px] hover:bg-muted cursor-pointer rounded-sm"
                      onClick={() => {
                        useStore.getState().selectNode(n.id);
                        setUsagesOpen(false);
                      }}
                    >
                      {label}
                    </li>
                  );
                })}
              </ul>
            </ScrollArea>
          </PopoverContent>
        )}
      </Popover>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete {kindLabel(kind)} {resource.name}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              {`Delete ${kindLabel(kind)} ${resource.name}? Used by ${usages.length} component(s).`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              onClick={handleConfirmedDelete}
            >
              Delete anyway
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

function kindLabel(kind: ResourceKind): string {
  if (kind === "geometry") return "geometry";
  if (kind === "powerShape") return "power shape";
  return "fluid";
}
