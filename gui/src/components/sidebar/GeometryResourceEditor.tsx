// GeometryResourceEditor.tsx — Phase 62 Plan 62-08 Task 1.
//
// Resource editor for a Geometry resource. Renders inside the `+ New…`
// popover (anchored by ResourceCreationPopoverContent) AND inside the
// right Properties panel when a Geometry row is selected in the
// Resources tab (the right-panel mount is wired by 62-09). Same component,
// two mount points — the `mode` prop distinguishes "create" (popover) from
// "edit" (Properties panel).
//
// Form shape per UI-SPEC §"`+ New…` popover" body fields + Validation
// messages:
//   • Name (`InstanceNameField`-style — pre-filled via nextResourceName per
//     D-19; user can edit; validated against per-kind uniqueness +
//     Julia-identifier regex on submit with verbatim UI-SPEC copy)
//   • Kind toggle (circular / rectangular) — toggle-group
//   • Circular fields: L (Length, m) + D (Inner diameter, m)
//   • Rectangular fields: L (Length, m) + W (Width, m) + H (Height, m)
//   • Action row: Cancel (outline) + Create / Save (default variant)
//
// References:
//   • 62-CONTEXT.md D-19 (smart-name-increment per kind), D-21 (resource
//     stores `{kind, params}` not a materialized matrix — same shape applies
//     for Geometry via the type union of params), D-22 (kinds)
//   • 62-UI-SPEC.md §"`+ New…` popover" — labels, units, validation copy
//   • CLAUDE.md / memory `feedback_ascii_variable_names.md` — Julia ASCII
//     identifier rule on the Name field

import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { cn } from "@/lib/utils";
import useStore, {
  nextResourceName,
  type GeometryResource,
} from "@/store/useStore";

export type GeometryKind = "circular" | "rectangular";

export interface GeometrySubmitPayload {
  name: string;
  kind: GeometryKind;
  params: GeometryResource["params"];
}

export interface GeometryResourceEditorProps {
  /** Header copy switches by mode. */
  mode: "create" | "edit";
  /** Initial Name; if omitted in "create" mode, pre-filled via nextResourceName. */
  initialName?: string;
  /** Initial Kind; default "circular". */
  initialKind?: GeometryKind;
  /** Initial dimension params. */
  initialParams?: GeometryResource["params"];
  /**
   * Called when the user clicks Create / Save after a successful validation
   * pass. The popover/panel host is responsible for closing the popover and
   * routing to the store (`addGeometry` for create, `updateResource` for edit).
   */
  onSubmit: (payload: GeometrySubmitPayload) => void;
  /** Called when the user clicks Cancel. The host closes the popover. */
  onCancel: () => void;
  /**
   * In "edit" mode, the UUID of the resource being edited — used to skip
   * its own name in the uniqueness check (otherwise editing-without-rename
   * would always fire the collision error).
   */
  editingUuid?: string;
}

// Julia identifier regex — must match `gui/src/store/useStore.ts`
// `JULIA_IDENT_RE`. Duplicated here so the popover can show the error
// inline before invoking the store (which would throw the same string
// on collision/invalid-identifier per its validateResourceName).
const JULIA_IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

export default function GeometryResourceEditor({
  mode,
  initialName,
  initialKind = "circular",
  initialParams,
  onSubmit,
  onCancel,
  editingUuid,
}: GeometryResourceEditorProps) {
  // Existing geometry names (for smart-increment default + uniqueness check).
  const existingGeometries = useStore((s) => s.resources.geometries);
  const existingNames = useMemo(
    () =>
      new Set(
        Object.entries(existingGeometries)
          .filter(([uuid]) => uuid !== editingUuid)
          .map(([, g]) => g.name),
      ),
    [existingGeometries, editingUuid],
  );

  // Pre-fill name via nextResourceName on mount (create mode only).
  const [name, setName] = useState<string>(() => {
    if (initialName) return initialName;
    if (mode === "edit") return "";
    return nextResourceName(
      "geometry",
      new Set(Object.values(existingGeometries).map((g) => g.name)),
    );
  });

  const [kind, setKind] = useState<GeometryKind>(initialKind);

  // Per-dimension local fields as strings (so we can render "" cleanly).
  const [L, setL] = useState<string>(
    initialParams?.L != null ? String(initialParams.L) : "",
  );
  const [D, setD] = useState<string>(
    initialParams?.D != null ? String(initialParams.D) : "",
  );
  const [W, setW] = useState<string>(
    initialParams?.W != null ? String(initialParams.W) : "",
  );
  const [H, setH] = useState<string>(
    initialParams?.H != null ? String(initialParams.H) : "",
  );

  const [nameError, setNameError] = useState<string | null>(null);
  const [dimError, setDimError] = useState<string | null>(null);

  function validateName(): string | null {
    if (!JULIA_IDENT_RE.test(name)) {
      // Verbatim UI-SPEC copy.
      return "Letters, digits, underscores. Cannot start with a digit.";
    }
    if (existingNames.has(name)) {
      // Verbatim UI-SPEC copy.
      return `A geometry named ${name} already exists.`;
    }
    return null;
  }

  function parsePositiveReal(raw: string, label: string): number | string {
    const trimmed = raw.trim();
    if (trimmed === "") return `${label} is required.`;
    const n = Number(trimmed);
    if (!Number.isFinite(n)) return `${label} must be a finite number.`;
    if (n <= 0) return `${label} must be positive.`;
    return n;
  }

  function handleSubmit() {
    setNameError(null);
    setDimError(null);

    const nErr = validateName();
    if (nErr !== null) {
      setNameError(nErr);
      return;
    }

    const params: GeometryResource["params"] = { L: 0 };
    if (kind === "circular") {
      const lv = parsePositiveReal(L, "L");
      if (typeof lv === "string") {
        setDimError(lv);
        return;
      }
      const dv = parsePositiveReal(D, "D");
      if (typeof dv === "string") {
        setDimError(dv);
        return;
      }
      params.L = lv;
      params.D = dv;
    } else {
      const lv = parsePositiveReal(L, "L");
      if (typeof lv === "string") {
        setDimError(lv);
        return;
      }
      const wv = parsePositiveReal(W, "W");
      if (typeof wv === "string") {
        setDimError(wv);
        return;
      }
      const hv = parsePositiveReal(H, "H");
      if (typeof hv === "string") {
        setDimError(hv);
        return;
      }
      params.L = lv;
      params.W = wv;
      params.H = hv;
    }

    onSubmit({ name, kind, params });
  }

  // Header copy per UI-SPEC §"`+ New…` popover" header table.
  // "New Geometry" for create mode.
  // "Edit Geometry" for edit mode.
  const headerCopy = mode === "create" ? "New Geometry" : "Edit Geometry";
  const submitLabel = mode === "create" ? "Create" : "Save";

  return (
    <div className="flex flex-col gap-[16px]">
      <h3 className="text-title font-semibold leading-[1.3]">{headerCopy}</h3>

      {/* Name */}
      <div className="flex flex-col gap-[8px]">
        <Label className="text-body font-semibold leading-[1.4]">Name</Label>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className={cn(nameError && "border-destructive")}
          autoFocus
        />
        {nameError && (
          <p className="text-destructive text-label leading-[1.4]">{nameError}</p>
        )}
      </div>

      {/* Kind */}
      <div className="flex flex-col gap-[8px]">
        <Label className="text-body font-semibold leading-[1.4]">Kind</Label>
        <ToggleGroup
          type="single"
          value={kind}
          onValueChange={(v) => {
            if (v === "circular" || v === "rectangular") setKind(v);
          }}
          variant="outline"
          size="sm"
        >
          <ToggleGroupItem value="circular">circular</ToggleGroupItem>
          <ToggleGroupItem value="rectangular">rectangular</ToggleGroupItem>
        </ToggleGroup>
      </div>

      {/* Dimensions */}
      {kind === "circular" ? (
        <>
          <DimensionField label="L" unit="m" value={L} onChange={setL} />
          <DimensionField label="D" unit="m" value={D} onChange={setD} />
        </>
      ) : (
        <>
          <DimensionField label="L" unit="m" value={L} onChange={setL} />
          <DimensionField label="W" unit="m" value={W} onChange={setW} />
          <DimensionField label="H" unit="m" value={H} onChange={setH} />
        </>
      )}

      {dimError && (
        <p className="text-destructive text-label leading-[1.4]">{dimError}</p>
      )}

      {/* Actions */}
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

interface DimensionFieldProps {
  label: string;
  unit: string;
  value: string;
  onChange: (v: string) => void;
}

function DimensionField({ label, unit, value, onChange }: DimensionFieldProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-body font-semibold leading-[1.4]">{label}</Label>
      <div className="relative">
        <Input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          inputMode="decimal"
          className="pr-12"
        />
        <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-body font-semibold pointer-events-none">
          {unit}
        </span>
      </div>
    </div>
  );
}
