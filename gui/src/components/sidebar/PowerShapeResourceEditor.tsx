// PowerShapeResourceEditor.tsx — Phase 62 Plan 62-08 Task 1.
//
// Resource editor for a Power Shape resource. Same two mount-points as
// GeometryResourceEditor: the `+ New…` popover (62-08) and the right
// Properties panel for a selected Power Shape row (mount wired in 62-09).
//
// Form per UI-SPEC §"`+ New…` popover":
//   • Name field (smart-name-increment via nextResourceName, D-19)
//   • Kind selector — `uniform` / `z_cosine` / `file_loaded`
//     EXCLUDES `unset` per D-22 + D-26 (the sentinel is reserved, only
//     selectable via the picker's fixed top entry; not user-creatable
//     and not user-editable).
//   • Conditional fields per kind:
//       - uniform: no extra fields
//       - z_cosine: Amplitude NumericField (default 1.0)
//       - file_loaded: read-only Path display + `Browse…` button that
//         opens a Tauri file dialog with a CSV-only filter (D-23) and
//         converts the chosen absolute path to relative against
//         `currentFilePath` if available (D-24 + RESEARCH Pitfall 5).
//   • Action row: Cancel (outline) + Create / Save (default)
//
// Validation:
//   • Name: Julia identifier + per-kind uniqueness, verbatim UI-SPEC copy.
//   • file_loaded path: if the file does not exist on disk, show
//     `File not found: <path>` (destructive style) — verbatim UI-SPEC.

import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { cn } from "@/lib/utils";
import useStore, {
  nextResourceName,
  type PowerShapeResource,
} from "@/store/useStore";

// Subset of the store kinds that are user-creatable. `unset` is excluded
// because the sentinel is built-in (D-22 + D-26); the store also throws
// at `addPowerShape` time if kind === "unset".
export type PowerShapeUserKind = "uniform" | "z_cosine" | "file_loaded";

export interface PowerShapeSubmitPayload {
  name: string;
  kind: PowerShapeUserKind;
  params: PowerShapeResource["params"];
}

export interface PowerShapeResourceEditorProps {
  mode: "create" | "edit";
  initialName?: string;
  initialKind?: PowerShapeUserKind;
  initialParams?: PowerShapeResource["params"];
  onSubmit: (payload: PowerShapeSubmitPayload) => void;
  onCancel: () => void;
  editingUuid?: string;
}

const JULIA_IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

// Cross-platform absolute-path detection — mirrors `useStore.ts`
// `isAbsolutePath`. We duplicate the regex here so the editor can format
// the displayed path independent of the store and avoid an export churn.
function isAbsolutePath(p: string): boolean {
  return p.startsWith("/") || /^[A-Za-z]:[\\/]/.test(p);
}

// Compute a relative path from `fromDir` to `toAbs`. Mirrors `useStore.ts`
// `computeRelativePath`. Kept local so the editor can pre-compute the
// stored display path before submitting.
function computeRelativePath(fromDir: string, toAbs: string): string {
  const norm = (s: string) => s.replace(/\\/g, "/").replace(/\/+$/, "");
  const fromParts = norm(fromDir).split("/").filter((p) => p.length > 0);
  const toParts = norm(toAbs).split("/").filter((p) => p.length > 0);
  if (
    /^[A-Za-z]:$/.test(fromParts[0] ?? "") &&
    /^[A-Za-z]:$/.test(toParts[0] ?? "") &&
    fromParts[0].toLowerCase() !== toParts[0].toLowerCase()
  ) {
    return toAbs;
  }
  let i = 0;
  while (
    i < fromParts.length &&
    i < toParts.length &&
    fromParts[i] === toParts[i]
  ) {
    i++;
  }
  const ups = new Array(fromParts.length - i).fill("..");
  const downs = toParts.slice(i);
  const segments = [...ups, ...downs];
  return segments.length === 0 ? "." : segments.join("/");
}

export default function PowerShapeResourceEditor({
  mode,
  initialName,
  initialKind = "uniform",
  initialParams,
  onSubmit,
  onCancel,
  editingUuid,
}: PowerShapeResourceEditorProps) {
  const existingPowerShapes = useStore((s) => s.resources.powerShapes);
  const currentFilePath = useStore((s) => s.currentFilePath);

  const existingNames = useMemo(
    () =>
      new Set(
        Object.entries(existingPowerShapes)
          .filter(([uuid]) => uuid !== editingUuid)
          .map(([, p]) => p.name),
      ),
    [existingPowerShapes, editingUuid],
  );

  const [name, setName] = useState<string>(() => {
    if (initialName) return initialName;
    if (mode === "edit") return "";
    return nextResourceName(
      "powerShape",
      new Set(Object.values(existingPowerShapes).map((p) => p.name)),
    );
  });

  const [kind, setKind] = useState<PowerShapeUserKind>(initialKind);

  const [amplitude, setAmplitude] = useState<string>(
    initialParams?.amplitude != null
      ? String(initialParams.amplitude)
      : "1.0",
  );

  // Path stored as the relative-to-.scp string (or absolute if no .scp yet).
  const [path, setPath] = useState<string>(initialParams?.path ?? "");
  const [pathError, setPathError] = useState<string | null>(null);

  const [nameError, setNameError] = useState<string | null>(null);
  const [dimError, setDimError] = useState<string | null>(null);

  function validateName(): string | null {
    if (!JULIA_IDENT_RE.test(name)) {
      return "Letters, digits, underscores. Cannot start with a digit.";
    }
    if (existingNames.has(name)) {
      return `A power shape named ${name} already exists.`;
    }
    return null;
  }

  async function handleBrowse() {
    setPathError(null);
    try {
      const { open } = await import("@tauri-apps/plugin-dialog");
      // D-23: CSV-only filter.
      const picked = await open({
        filters: [{ name: "CSV (Power Shape)", extensions: ["csv"] }],
        multiple: false,
      });
      if (!picked) return;
      const absPath = Array.isArray(picked) ? picked[0] : picked;
      if (!absPath) return;

      // Verify the file exists on disk (defensive — the dialog should only
      // return paths to files that exist, but a race against an external
      // delete is possible).
      const fsApi = await import("@tauri-apps/plugin-fs");
      let exists = false;
      try {
        exists = await fsApi.exists(String(absPath));
      } catch {
        exists = false;
      }
      if (!exists) {
        // Verbatim UI-SPEC copy.
        setPathError(`File not found: ${absPath}`);
        return;
      }

      // D-24 + RESEARCH Pitfall 5: convert absolute -> relative-to-.scp.
      // If currentFilePath is null (project not saved yet), store absolute;
      // the save path will relativize at save time.
      let stored: string = String(absPath);
      if (currentFilePath && isAbsolutePath(String(absPath))) {
        try {
          const pathApi = await import("@tauri-apps/api/path");
          const dir = await pathApi.dirname(currentFilePath);
          stored = computeRelativePath(dir, String(absPath));
        } catch {
          stored = String(absPath);
        }
      }
      setPath(stored);
    } catch (err) {
      // Tauri unavailable (e.g., vitest happy-dom) — show as a path error
      // so the user sees something rather than a silent no-op.
      setPathError(`Could not open file dialog: ${(err as Error).message}`);
    }
  }

  function handleSubmit() {
    setNameError(null);
    setDimError(null);

    const nErr = validateName();
    if (nErr !== null) {
      setNameError(nErr);
      return;
    }

    const params: PowerShapeResource["params"] = {};
    if (kind === "uniform") {
      // no extra fields
    } else if (kind === "z_cosine") {
      const amp = Number(amplitude.trim());
      if (!Number.isFinite(amp)) {
        setDimError("Amplitude must be finite.");
        return;
      }
      params.amplitude = amp;
    } else if (kind === "file_loaded") {
      if (!path) {
        setDimError("Pick a CSV file via Browse.");
        return;
      }
      params.path = path;
    }

    onSubmit({ name, kind, params });
  }

  // Header copy per UI-SPEC §"`+ New…` popover" header table.
  // "New Power Shape" for create mode.
  // "Edit Power Shape" for edit mode.
  const headerCopy = mode === "create" ? "New Power Shape" : "Edit Power Shape";
  const submitLabel = mode === "create" ? "Create" : "Save";

  return (
    <div className="flex flex-col gap-[16px]">
      <h3 className="text-[16px] font-semibold leading-[1.3]">{headerCopy}</h3>

      {/* Name */}
      <div className="flex flex-col gap-[8px]">
        <Label className="text-[13px] font-semibold leading-[1.4]">Name</Label>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className={cn(nameError && "border-destructive")}
          autoFocus
        />
        {nameError && (
          <p className="text-destructive text-xs leading-[1.4]">{nameError}</p>
        )}
      </div>

      {/* Kind */}
      <div className="flex flex-col gap-[8px]">
        <Label className="text-[13px] font-semibold leading-[1.4]">Kind</Label>
        <Select
          value={kind}
          onValueChange={(v) =>
            setKind(v as PowerShapeUserKind)
          }
        >
          <SelectTrigger size="sm" className="w-full">
            <SelectValue placeholder="Kind" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="uniform">uniform</SelectItem>
            <SelectItem value="z_cosine">z_cosine</SelectItem>
            <SelectItem value="file_loaded">file_loaded</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {kind === "z_cosine" && (
        <div className="flex flex-col gap-[8px]">
          <Label className="text-[13px] font-semibold leading-[1.4]">
            Amplitude
          </Label>
          <Input
            value={amplitude}
            onChange={(e) => setAmplitude(e.target.value)}
            inputMode="decimal"
          />
        </div>
      )}

      {kind === "file_loaded" && (
        <div className="flex flex-col gap-[8px]">
          <Label className="text-[13px] font-semibold leading-[1.4]">Path</Label>
          <div className="flex items-center gap-[8px]">
            <div
              className={cn(
                "flex-1 truncate text-[13px] text-muted-foreground border border-input rounded-md px-2 h-9 flex items-center",
                pathError && "border-destructive",
              )}
              title={path || "(no file selected)"}
            >
              {path || "(no file selected)"}
            </div>
            <Button variant="outline" size="sm" onClick={handleBrowse}>
              Browse…
            </Button>
          </div>
          {pathError && (
            <p className="text-destructive text-xs leading-[1.4]">{pathError}</p>
          )}
        </div>
      )}

      {dimError && (
        <p className="text-destructive text-xs leading-[1.4]">{dimError}</p>
      )}

      <div className="flex justify-end gap-[8px] mt-[8px]">
        <Button variant="outline" size="sm" onClick={onCancel}>
          Cancel
        </Button>
        <Button size="sm" onClick={handleSubmit}>
          {submitLabel}
        </Button>
      </div>
    </div>
  );
}
