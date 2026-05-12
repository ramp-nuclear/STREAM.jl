// ModelOptionsPanel — Phase 62 plan 62-07 (D-04 + CD-04).
//
// Renders the Model Options form as the entire Project-tab body. There is no
// inner selection step (D-04). All editable fields commit via
// `useStore.setModelOptions(patch)` on field blur — the store wraps every patch
// in a `_pushSnapshot()` + isDirty flip (already wired by plan 62-02).
//
// Fields rendered:
//   - Name           (Input,    string)
//   - Description    (Textarea, string)
//   - Default fluid  (Input,    read-only "water" + disabled tooltip per UI-SPEC)
//   - Default g      (Input,    number,  default 9.80665 m/s^2)
//   - Solver Defaults
//       * abstol  (Input, number,  default 1e-8)
//       * reltol  (Input, number,  default 1e-6)
//       * dtmax   (Input, number?, blank => null = "no cap")
//
// Design note: the existing `NumericField` / `InstanceNameField` primitives in
// `gui/src/components/sidebar/` are coupled to the registry `Parameter` shape
// and Julia-identifier validation respectively — neither contract fits this
// form (no Parameter records; the project name is a free string, not a Julia
// identifier). Building inline `<Input>` / `<textarea>` rows with a local
// edit-buffer + `onBlur` commit keeps the API one level simpler and avoids
// inventing a fake `Parameter` per field.

import { useEffect, useState } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Info } from "lucide-react";
import { cn } from "@/lib/utils";
import useStore from "@/store/useStore";

// Stringify a number with a sensible default placeholder for empty / null.
// We preserve the user's literal entry (e.g. "1e-8") by keeping the edit
// buffer as a string and only coercing on blur.
function stringifyNumber(n: number | null | undefined): string {
  if (n === null || n === undefined) return "";
  return String(n);
}

// Field-row layout helper — keeps spacing consistent and avoids repeating the
// "label + input + optional info tooltip" snippet for every field.
function FieldRow({
  id,
  label,
  description,
  unit,
  children,
}: {
  id: string;
  label: string;
  description?: string;
  unit?: string;
  children: (inputId: string, unitVisible: boolean) => React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-[8px] mb-[16px]">
      <Label
        htmlFor={id}
        className="text-[13px] font-semibold leading-[1.4] flex items-center gap-1"
      >
        {label}
        {description && (
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Info className="h-3 w-3 text-muted-foreground cursor-default" />
              </TooltipTrigger>
              <TooltipContent>{description}</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}
      </Label>
      <div className="relative">
        {children(id, Boolean(unit))}
        {unit && (
          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-[13px] font-semibold pointer-events-none">
            {unit}
          </span>
        )}
      </div>
    </div>
  );
}

export default function ModelOptionsPanel() {
  const modelOptions = useStore((s) => s.modelOptions);
  const setModelOptions = useStore((s) => s.setModelOptions);

  // Local edit-buffer mirrors so the in-progress edit isn't constantly
  // round-tripping through Zustand (and so we can preserve the user's literal
  // numeric input — "1e-8" stays "1e-8" rather than becoming "1e-8" -> 1e-8 ->
  // "1.0000000000000002e-8"). Commits happen on blur.
  const [localName, setLocalName] = useState(modelOptions.name);
  const [localDescription, setLocalDescription] = useState(modelOptions.description);
  const [localG, setLocalG] = useState(stringifyNumber(modelOptions.g_default));
  const [localAbstol, setLocalAbstol] = useState(
    stringifyNumber(modelOptions.solver.abstol),
  );
  const [localReltol, setLocalReltol] = useState(
    stringifyNumber(modelOptions.solver.reltol),
  );
  const [localDtmax, setLocalDtmax] = useState(
    stringifyNumber(modelOptions.solver.dtmax),
  );

  // Re-sync the edit-buffers when the store value changes from somewhere else
  // (undo / redo / project load). Without this, the form would silently show
  // stale data after a Ctrl+Z.
  useEffect(() => setLocalName(modelOptions.name), [modelOptions.name]);
  useEffect(
    () => setLocalDescription(modelOptions.description),
    [modelOptions.description],
  );
  useEffect(
    () => setLocalG(stringifyNumber(modelOptions.g_default)),
    [modelOptions.g_default],
  );
  useEffect(
    () => setLocalAbstol(stringifyNumber(modelOptions.solver.abstol)),
    [modelOptions.solver.abstol],
  );
  useEffect(
    () => setLocalReltol(stringifyNumber(modelOptions.solver.reltol)),
    [modelOptions.solver.reltol],
  );
  useEffect(
    () => setLocalDtmax(stringifyNumber(modelOptions.solver.dtmax)),
    [modelOptions.solver.dtmax],
  );

  // Commit helpers — each one calls setModelOptions with the minimum patch.
  // Solver subobject merges are shallow-on-shallow per the UI-SPEC contract;
  // see the dedicated solver helpers below.
  function commitName() {
    if (localName !== modelOptions.name) {
      setModelOptions({ name: localName });
    }
  }

  function commitDescription() {
    if (localDescription !== modelOptions.description) {
      setModelOptions({ description: localDescription });
    }
  }

  function commitG() {
    const trimmed = localG.trim();
    if (trimmed === "") {
      // Empty -> revert to current store value (no commit). g_default cannot
      // be null (it is `number`, not `number | null`), so we refuse blank.
      setLocalG(stringifyNumber(modelOptions.g_default));
      return;
    }
    const n = Number(trimmed);
    if (!Number.isFinite(n)) {
      // Reject NaN / Infinity by reverting to the current value.
      setLocalG(stringifyNumber(modelOptions.g_default));
      return;
    }
    if (n !== modelOptions.g_default) {
      setModelOptions({ g_default: n });
    }
  }

  // Solver-subobject commit: SHALLOW MERGE on the solver subtree. We splat the
  // current solver and override only the targeted key so that editing `abstol`
  // never zaps `reltol` / `dtmax`. This is the dual of `setModelOptions`'s
  // top-level shallow merge.
  function commitSolverNumber(key: "abstol" | "reltol", localStr: string) {
    const trimmed = localStr.trim();
    if (trimmed === "") {
      // abstol/reltol cannot be null. Refuse blank by reverting.
      const reverted = stringifyNumber(modelOptions.solver[key]);
      if (key === "abstol") setLocalAbstol(reverted);
      else setLocalReltol(reverted);
      return;
    }
    const n = Number(trimmed);
    if (!Number.isFinite(n)) {
      const reverted = stringifyNumber(modelOptions.solver[key]);
      if (key === "abstol") setLocalAbstol(reverted);
      else setLocalReltol(reverted);
      return;
    }
    if (n !== modelOptions.solver[key]) {
      setModelOptions({ solver: { ...modelOptions.solver, [key]: n } });
    }
  }

  // dtmax has the special-case "blank means null = no cap" semantics per
  // CD-04 + UI-SPEC §"Project tab body — Solver defaults exposure".
  function commitDtmax() {
    const trimmed = localDtmax.trim();
    if (trimmed === "") {
      if (modelOptions.solver.dtmax !== null) {
        setModelOptions({ solver: { ...modelOptions.solver, dtmax: null } });
      }
      return;
    }
    const n = Number(trimmed);
    if (!Number.isFinite(n)) {
      setLocalDtmax(stringifyNumber(modelOptions.solver.dtmax));
      return;
    }
    if (n !== modelOptions.solver.dtmax) {
      setModelOptions({ solver: { ...modelOptions.solver, dtmax: n } });
    }
  }

  return (
    <div className="p-[16px] pt-[32px] overflow-y-auto h-full">
      <h2 className="text-[16px] font-semibold leading-[1.3] mb-[24px]">
        Project Options
      </h2>

      {/* Name -------------------------------------------------------------- */}
      <FieldRow id="mo-name" label="Name">
        {(id) => (
          <Input
            id={id}
            value={localName}
            onChange={(e) => setLocalName(e.target.value)}
            onBlur={commitName}
          />
        )}
      </FieldRow>

      {/* Description ------------------------------------------------------- */}
      <div className="flex flex-col gap-[8px] mb-[16px]">
        <Label
          htmlFor="mo-description"
          className="text-[13px] font-semibold leading-[1.4]"
        >
          Description
        </Label>
        {/* Plain styled <textarea> rather than a new shadcn `textarea.tsx`
            shim: single use, doesn't justify a reusable primitive yet. The
            className spine matches `<Input>` for visual consistency. */}
        <textarea
          id="mo-description"
          value={localDescription}
          onChange={(e) => setLocalDescription(e.target.value)}
          onBlur={commitDescription}
          rows={3}
          className={cn(
            "w-full min-w-0 rounded-md border border-input bg-transparent px-3 py-2 text-base shadow-xs",
            "transition-[color,box-shadow] outline-none",
            "selection:bg-primary selection:text-primary-foreground",
            "placeholder:text-muted-foreground",
            "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
            "md:text-sm dark:bg-input/30",
            "resize-y",
          )}
        />
      </div>

      {/* Default fluid (read-only, with disabled tooltip per UI-SPEC) ------ */}
      <div className="flex flex-col gap-[8px] mb-[16px]">
        <Label
          htmlFor="mo-default-fluid"
          className="text-[13px] font-semibold leading-[1.4]"
        >
          Default fluid
        </Label>
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              {/* Wrap in a span so the disabled <input> still receives pointer
                  events for the tooltip (Radix needs a focusable trigger). */}
              <span className="inline-block w-full">
                <Input
                  id="mo-default-fluid"
                  value="water"
                  readOnly
                  disabled
                  className="opacity-75"
                />
              </span>
            </TooltipTrigger>
            <TooltipContent>
              Multi-fluid support is planned for a future release.
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </div>

      {/* Default g --------------------------------------------------------- */}
      <FieldRow
        id="mo-g-default"
        label="Default g"
        description="Gravitational acceleration applied to channels with non-zero g."
        unit="m/s^2"
      >
        {(id, unitVisible) => (
          <Input
            id={id}
            value={localG}
            onChange={(e) => setLocalG(e.target.value)}
            onBlur={commitG}
            inputMode="decimal"
            placeholder="9.80665"
            className={unitVisible ? "pr-12" : undefined}
          />
        )}
      </FieldRow>

      {/* Solver Defaults section ------------------------------------------ */}
      <Separator className="my-[24px]" />
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-[16px]">
        Solver Defaults
      </h3>

      <FieldRow
        id="mo-solver-abstol"
        label="abstol"
        description="Absolute tolerance for solve_steady / solve_transient. Default 1e-8."
      >
        {(id) => (
          <Input
            id={id}
            value={localAbstol}
            onChange={(e) => setLocalAbstol(e.target.value)}
            onBlur={() => commitSolverNumber("abstol", localAbstol)}
            inputMode="decimal"
            placeholder="1e-8"
          />
        )}
      </FieldRow>

      <FieldRow
        id="mo-solver-reltol"
        label="reltol"
        description="Relative tolerance for solve_steady / solve_transient. Default 1e-6."
      >
        {(id) => (
          <Input
            id={id}
            value={localReltol}
            onChange={(e) => setLocalReltol(e.target.value)}
            onBlur={() => commitSolverNumber("reltol", localReltol)}
            inputMode="decimal"
            placeholder="1e-6"
          />
        )}
      </FieldRow>

      <FieldRow
        id="mo-solver-dtmax"
        label="dtmax"
        description="Maximum solver timestep (transient only). Leave blank for no cap."
      >
        {(id) => (
          <Input
            id={id}
            value={localDtmax}
            onChange={(e) => setLocalDtmax(e.target.value)}
            onBlur={commitDtmax}
            inputMode="decimal"
            placeholder="(blank = no cap)"
          />
        )}
      </FieldRow>
    </div>
  );
}
