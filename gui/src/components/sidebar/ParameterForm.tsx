import { useEffect, useState } from "react";
import { Info } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import NumericField from "./NumericField";
import ResourceReferencePicker from "./ResourceReferencePicker";
import FunctionSelect from "./FunctionSelect";
import MatrixBadge from "./MatrixBadge";
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
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { validateReal } from "@/lib/validation";
import {
  isSourceValueEntry,
  defaultSourceValueEntry,
  type SourceValueEntry,
} from "@/lib/sourceValueEntry";
import { ProfileModeEditor, FunctionModeEditor } from "./modeEditors";
import type { ComponentDefinition, Parameter } from "@/registry/types";

// Plan 63.1-11 — D-10 type_union + input_modes contract (scalar-only GUI for
// non-Sources params; mode-aware for Sources-category params per Plan 14).
//
// A type_union Parameter has no `param.type`; it carries a `type_union[]`
// of allowed value shapes and a paired `input_modes[]`. For Hydraulic-category
// components (Channel.h_left/h_right), the GUI ONLY exposes scalar editing —
// per project-feedback (heavy-dev, 2026-05-14). For Sources-category components
// (WallTemperature.T_wall, HeatFluxSource.q), the GUI exposes a 3-mode dropdown
// (Value / Profile / Function) — per Plan 14, GAP-RC-4.

interface TypeUnionFieldProps {
  param: Parameter;
  value: unknown;
  isSourceValueParam: boolean;
  onChange: (value: unknown) => void;
}

function TypeUnionField({ param, value, isSourceValueParam, onChange }: TypeUnionFieldProps) {
  // For Sources-category params: derive the SourceValueEntry from the stored value.
  // Bare-number legacy values are treated as value-mode for display; the first
  // edit dispatches a SourceValueEntry (always-overwrite per Plan 11 Decision #2).
  const entry: SourceValueEntry | undefined = isSourceValueEntry(value)
    ? value
    : isSourceValueParam && typeof value === "number"
    ? defaultSourceValueEntry(value)
    : undefined;

  function handleModeChange(newMode: "value" | "profile" | "function") {
    if (newMode === "value") {
      const numericDefault =
        typeof param.default === "number"
          ? param.default
          : entry?.mode === "value"
          ? entry.value
          : 300.0;
      onChange({ mode: "value", value: numericDefault });
    } else if (newMode === "profile") {
      onChange({ mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.0 });
    } else {
      onChange({ mode: "function", signature: "fn(t)", functionName: "" });
    }
  }

  if (!isSourceValueParam) {
    // Scalar-only path for non-Sources params (Channel.h_left/h_right).
    const initialDisplay = typeof value === "number" ? value : param.default;
    return (
      <div className="flex flex-col gap-[6px] min-w-0">
        <Label className="text-[12px] font-medium leading-[1.4] flex items-center gap-1 min-w-0">
          {param.name}
          {param.description && (
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Info className="h-3 w-3 text-muted-foreground cursor-default" />
                </TooltipTrigger>
                <TooltipContent>{param.description}</TooltipContent>
              </Tooltip>
            </TooltipProvider>
          )}
        </Label>
        <ScalarInput
          value={initialDisplay}
          unit={param.unit}
          paramDefault={typeof param.default === "number" ? param.default : undefined}
          paramRequired={param.required ?? false}
          onChange={(v) => onChange(v)}
        />
        <p className="text-[11px] text-muted-foreground leading-[1.3]">
          Vector or function values — edit in the generated Julia.
        </p>
      </div>
    );
  }

  // Mode-aware path for Sources-category params (WT.T_wall, HFS.q).
  const currentMode = entry?.mode ?? "value";

  return (
    <div className="flex flex-col gap-[6px] min-w-0">
      <Label className="text-[12px] font-medium leading-[1.4] flex items-center gap-1 min-w-0">
        {param.name}
        {param.description && (
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Info className="h-3 w-3 text-muted-foreground cursor-default" />
              </TooltipTrigger>
              <TooltipContent>{param.description}</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}
      </Label>
      <Select
        value={currentMode}
        onValueChange={(m) => handleModeChange(m as "value" | "profile" | "function")}
      >
        <SelectTrigger className="w-full">
          <SelectValue placeholder="Select mode..." />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="value">Value</SelectItem>
          <SelectItem value="profile">Profile</SelectItem>
          <SelectItem value="function">Function</SelectItem>
        </SelectContent>
      </Select>
      {/* Editor body dispatch based on current mode */}
      {currentMode === "value" || entry === undefined ? (
        <ScalarInput
          value={entry?.mode === "value" ? entry.value : (typeof value === "number" ? value : undefined)}
          unit={param.unit}
          paramDefault={typeof param.default === "number" ? param.default : undefined}
          paramRequired={param.required ?? false}
          onChange={(v) => onChange({ mode: "value", value: v as number })}
        />
      ) : entry.mode === "profile" ? (
        <ProfileModeEditor
          entry={entry as Extract<SourceValueEntry, { mode: "profile" }>}
          onUpdate={(e) => onChange(e)}
        />
      ) : entry.mode === "function" ? (
        <FunctionModeEditor
          entry={entry as Extract<SourceValueEntry, { mode: "function" }>}
          onUpdate={(e) => onChange(e)}
        />
      ) : null}
    </div>
  );
}

interface ScalarInputProps {
  value: unknown;
  unit?: string;
  paramDefault?: number;
  paramRequired?: boolean;
  onChange: (value: number | undefined) => void;
}

function ScalarInput({ value, unit, paramDefault, paramRequired, onChange }: ScalarInputProps) {
  const [localValue, setLocalValue] = useState(
    typeof value === "number" ? String(value) : ""
  );
  const [error, setError] = useState<string | null>(null);

  // Re-sync local string when the upstream numeric value changes (parent
  // re-keys or sibling edits cascade). String-compare prevents thrashing while
  // the user is mid-edit. Non-scalar stored values render as an empty input —
  // the first edit overwrites them with a number (per project-feedback).
  useEffect(() => {
    if (typeof value === "number" && String(value) !== localValue) {
      setLocalValue(String(value));
    } else if (value === undefined || value === null) {
      // leave whatever the user has typed
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  function handleBlur() {
    const trimmed = localValue.trim();

    // Three-branch blank-on-blur rule (§3.5 reset-to-empty, Plan 65-02):
    if (trimmed === "") {
      if (paramDefault != null) {
        // Branch 1: registry default exists — restore it.
        setError(null);
        setLocalValue(String(paramDefault));
        onChange(paramDefault);
      } else if (paramRequired) {
        // Branch 2: required, no default — surface error.
        setError("required");
      } else {
        // Branch 3: optional, no default — omit from code-gen.
        setError(null);
        onChange(undefined);
      }
      return;
    }

    const result = validateReal(localValue);
    if (result.valid) {
      setError(null);
      onChange(result.value);
    } else {
      setError(result.message);
    }
  }

  return (
    <div className="flex flex-col gap-[2px] min-w-0">
      <div className="relative">
        <Input
          value={localValue}
          onChange={(e) => setLocalValue(e.target.value)}
          onBlur={handleBlur}
          inputMode="decimal"
          className={
            (unit ? "pr-12 " : "") + (error ? "border-destructive" : "")
          }
        />
        {unit && (
          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-[13px] font-semibold pointer-events-none">
            {unit}
          </span>
        )}
      </div>
      {error && <p className="text-destructive text-xs">{error}</p>}
    </div>
  );
}

interface ParameterFormProps {
  component: ComponentDefinition;
  activeMode: string;
  values: Record<string, unknown>;
  onParamChange: (name: string, value: unknown) => void;
}

export default function ParameterForm({
  component,
  activeMode,
  values,
  onParamChange,
}: ParameterFormProps) {
  // Determine visible parameters from the active constructor mode
  const modeSpec = component.constructorModes.find(
    (m) => m.mode === activeMode
  );
  const visibleNames = modeSpec?.parameters ?? component.parameters.map((p) => p.name);

  const visibleParams = visibleNames
    .map((name) => component.parameters.find((p) => p.name === name))
    .filter((p): p is Parameter => p !== undefined);

  // Group parameters by type. type_union params (D-10) — e.g. WT.T_wall, HFS.q,
  // Channel.h_left/h_right — have no `type` and are folded into scalarParams so
  // they ride the same "Parameters" section heading as Int/Real/Bool.
  const scalarParams = visibleParams.filter(
    (p) =>
      p.type === "Int" ||
      p.type === "Real" ||
      p.type === "Bool" ||
      p.type_union !== undefined
  );
  const geometryParams = visibleParams.filter(
    (p) => p.type === "PipeGeometry"
  );
  const functionParams = visibleParams.filter((p) => p.type === "Function");
  const matrixParams = visibleParams.filter((p) => p.type === "Matrix");

  function renderField(param: Parameter) {
    // type_union branch — runs BEFORE the type switch because type_union params
    // have no `param.type` (mutually exclusive per D-10). The switch's default
    // arm would otherwise return null, which is the RC-1 silent-drop bug.
    if (param.type_union !== undefined) {
      return (
        <TypeUnionField
          key={param.name}
          param={param}
          value={values[param.name]}
          isSourceValueParam={component.category === "Sources"}
          onChange={(v) => onParamChange(param.name, v)}
        />
      );
    }
    switch (param.type) {
      case "Int":
      case "Real":
        return (
          <NumericField
            key={param.name}
            param={param}
            value={values[param.name]}
            onChange={(v) => onParamChange(param.name, v)}
          />
        );
      case "Bool":
        return (
          <div key={param.name} className="flex flex-col gap-[8px]">
            <Label className="text-[13px] font-semibold leading-[1.4] flex items-center gap-1">
              {param.name}
              {param.description && (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Info className="h-3 w-3 text-muted-foreground cursor-default" />
                    </TooltipTrigger>
                    <TooltipContent>{param.description}</TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
            </Label>
            <Button
              variant={values[param.name] ? "default" : "outline"}
              size="sm"
              onClick={() => onParamChange(param.name, !values[param.name])}
            >
              {values[param.name] ? "On" : "Off"}
            </Button>
          </div>
        );
      case "PipeGeometry":
        // Phase 62 Plan 62-08 Task 2 — Assumption A1 reinterpretation.
        // The registry still tags this param as `type: "PipeGeometry"` (per
        // components.json lines 24, 128, 583) for `Channel.geometry`,
        // `ChannelHeatFlux.geometry`, and `ChannelAndContacts.geometry`.
        // Phase 62 keeps the tag string as-is and the consumer reinterprets
        // it as a Resource-FK marker (Geometry resource). The `value` stored
        // under `parameters.geometry` is now a UUID string, not the inline
        // {type: "circular"|"rectangular", ...} object.
        return (
          <ResourceReferencePicker
            key={param.name}
            resourceKind="geometry"
            value={
              typeof values[param.name] === "string"
                ? (values[param.name] as string)
                : null
            }
            onChange={(uuid) => onParamChange(param.name, uuid)}
          />
        );
      case "Function":
        return (
          <FunctionSelect
            key={param.name}
            param={param}
            value={values[param.name]}
            onChange={(v) => onParamChange(param.name, v)}
          />
        );
      case "Matrix":
        // Phase 62 Plan 62-08 Task 2 — Assumption A1 reinterpretation.
        // The registry tags `HeatDiffusion.power_shape` as `type: "Matrix"`
        // (components.json line 983). Phase 62 reinterprets the
        // Matrix-typed `power_shape` param as a Resource-FK marker
        // (Power Shape resource). Defensive: future Matrix-typed params
        // that are NOT `power_shape` fall back to MatrixBadge.
        if (param.name === "power_shape") {
          return (
            <ResourceReferencePicker
              key={param.name}
              resourceKind="powerShape"
              value={
                typeof values[param.name] === "string"
                  ? (values[param.name] as string)
                  : null
              }
              onChange={(uuid) => onParamChange(param.name, uuid)}
            />
          );
        }
        return <MatrixBadge key={param.name} param={param} />;
      default:
        return null;
    }
  }

  const sections: { heading: string; params: Parameter[] }[] = [];
  if (scalarParams.length > 0) {
    sections.push({ heading: "Parameters", params: scalarParams });
  }
  if (geometryParams.length > 0) {
    sections.push({ heading: "Geometry", params: geometryParams });
  }
  if (functionParams.length > 0) {
    sections.push({ heading: "Correlations", params: functionParams });
  }
  if (matrixParams.length > 0) {
    // Phase 62: Matrix-typed `power_shape` is now a Resource-FK picker, not
    // a placeholder badge. Use "Power Shape" as the section heading when the
    // only matrix param is `power_shape` (current registry shape per
    // components.json line 982). If a future plan adds a non-Resource Matrix
    // param, the heading falls back to "Advanced".
    const onlyPowerShape =
      matrixParams.length === 1 && matrixParams[0].name === "power_shape";
    sections.push({
      heading: onlyPowerShape ? "Power Shape" : "Advanced",
      params: matrixParams,
    });
  }

  return (
    <div className="flex flex-col gap-[12px] min-w-0">
      {sections.map((section, idx) => (
        <div key={section.heading} className="min-w-0">
          {idx > 0 && <Separator className="mb-[12px]" />}
          <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground leading-[1.3] mb-[8px]">
            {section.heading}
          </h3>
          <div className="flex flex-col gap-[8px]">
            {section.params.map((param) => renderField(param))}
          </div>
        </div>
      ))}
    </div>
  );
}
