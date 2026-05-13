import { useEffect, useState } from "react";
import { Info } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import NumericField from "./NumericField";
import ResourceReferencePicker from "./ResourceReferencePicker";
import FunctionSelect from "./FunctionSelect";
import MatrixBadge from "./MatrixBadge";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { validateReal } from "@/lib/validation";
import type { ComponentDefinition, Parameter } from "@/registry/types";

// Plan 63.1-11 — D-10 type_union + input_modes contract.
//
// A type_union Parameter has no `param.type`; instead it carries a
// `type_union[]` of allowed value shapes and a paired `input_modes[]`. The
// stored value's runtime type is the discriminator:
//   typeof value === "number"      → scalar mode
//   Array.isArray(value)           → vector mode
//   typeof value === "string"      → callable mode
//   undefined                      → first input_mode (typically "scalar")
//
// The mode itself is NOT stored separately. Switching modes is purely visual
// until the user edits — switching scalar→vector→scalar without editing
// preserves the original number (no implicit write).
type TypeUnionMode = "scalar" | "vector" | "callable" | "controller";

function inferMode(
  value: unknown,
  inputModes: ReadonlyArray<string> | undefined
): TypeUnionMode {
  if (typeof value === "number") return "scalar";
  if (Array.isArray(value)) return "vector";
  if (typeof value === "string" && value.length > 0) return "callable";
  const first = inputModes?.[0];
  if (first === "vector" || first === "callable" || first === "controller") {
    return first;
  }
  return "scalar";
}

interface TypeUnionFieldProps {
  param: Parameter;
  value: unknown;
  n: unknown;
  onChange: (value: unknown) => void;
}

function TypeUnionField({ param, value, n, onChange }: TypeUnionFieldProps) {
  const inputModes = (param.input_modes ?? ["scalar"]) as ReadonlyArray<TypeUnionMode>;
  // Mode state is initialized from the existing value, then re-synced when the
  // upstream value transitions to a shape that mismatches the current mode
  // (e.g. parent re-keyed). Local visual switches do not trigger writes.
  const [activeMode, setActiveMode] = useState<TypeUnionMode>(() =>
    inferMode(value, inputModes)
  );
  useEffect(() => {
    const inferred = inferMode(value, inputModes);
    // Only force-sync when the inferred mode disagrees with current state AND
    // the incoming value is a concrete shape (number/array/non-empty string).
    if (
      inferred !== activeMode &&
      (typeof value === "number" ||
        Array.isArray(value) ||
        (typeof value === "string" && value.length > 0))
    ) {
      setActiveMode(inferred);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  const cellCount = typeof n === "number" && n >= 1 ? Math.floor(n) : 1;

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
      <SegmentedButtonGroup<TypeUnionMode>
        options={inputModes.map((m) => ({ value: m, label: m }))}
        active={activeMode}
        onChange={setActiveMode}
        size="sm"
      />
      {activeMode === "scalar" && (
        <ScalarInput
          value={typeof value === "number" ? value : param.default}
          unit={param.unit}
          onChange={(v) => onChange(v)}
        />
      )}
      {activeMode === "vector" && (
        <VectorEditor
          n={cellCount}
          value={value}
          fallback={
            typeof param.default === "number" ? param.default : 0
          }
          unit={param.unit}
          onChange={(arr) => onChange(arr)}
        />
      )}
      {activeMode === "callable" && (
        <SegmentedButtonGroup<"fn(t)" | "fn(t, i)">
          options={[
            { value: "fn(t)", label: "fn(t)" },
            { value: "fn(t, i)", label: "fn(t, i)" },
          ]}
          active={
            value === "fn(t)" || value === "fn(t, i)"
              ? (value as "fn(t)" | "fn(t, i)")
              : "fn(t)"
          }
          onChange={(sig) => onChange(sig)}
          size="sm"
        />
      )}
    </div>
  );
}

interface ScalarInputProps {
  value: unknown;
  unit?: string;
  onChange: (value: number) => void;
}

function ScalarInput({ value, unit, onChange }: ScalarInputProps) {
  const [localValue, setLocalValue] = useState(String(value ?? ""));
  const [error, setError] = useState<string | null>(null);

  // Re-sync local string when the upstream numeric value changes (parent
  // re-keys or sibling edits cascade). String-compare prevents thrashing while
  // the user is mid-edit.
  useEffect(() => {
    if (typeof value === "number" && String(value) !== localValue) {
      setLocalValue(String(value));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  function handleBlur() {
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

interface VectorEditorProps {
  n: number;
  value: unknown;
  fallback: number;
  unit?: string;
  onChange: (arr: number[]) => void;
}

function VectorEditor({ n, value, fallback, unit, onChange }: VectorEditorProps) {
  const initial: number[] = Array.isArray(value)
    ? (value as unknown[]).slice(0, n).map((v) => (typeof v === "number" ? v : fallback))
    : Array(n).fill(fallback);
  while (initial.length < n) initial.push(fallback);
  const [cells, setCells] = useState<string[]>(initial.map((v) => String(v)));

  // Re-sync local cell strings when n changes upstream.
  useEffect(() => {
    setCells((prev) => {
      const next = [...prev];
      while (next.length < n) next.push(String(fallback));
      return next.slice(0, n);
    });
  }, [n, fallback]);

  function commit(idx: number, raw: string) {
    const updated = [...cells];
    updated[idx] = raw;
    setCells(updated);
    const parsed = updated.map((s) => {
      const r = validateReal(s);
      return r.valid ? r.value : fallback;
    });
    onChange(parsed);
  }

  return (
    <div className="flex flex-col gap-[4px]">
      {cells.map((cell, i) => (
        <div key={i} className="flex items-center gap-[8px]">
          <Label className="text-[12px] w-[40px] text-muted-foreground">[{i + 1}]</Label>
          <div className="relative flex-1">
            <Input
              value={cell}
              onChange={(e) => {
                const updated = [...cells];
                updated[i] = e.target.value;
                setCells(updated);
              }}
              onBlur={(e) => commit(i, e.target.value)}
              inputMode="decimal"
              className={unit ? "pr-12" : undefined}
            />
            {unit && (
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-[13px] font-semibold pointer-events-none">
                {unit}
              </span>
            )}
          </div>
        </div>
      ))}
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
          n={values["n"]}
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
