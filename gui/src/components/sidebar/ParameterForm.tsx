import { Info } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import NumericField from "./NumericField";
import ResourceReferencePicker from "./ResourceReferencePicker";
import FunctionSelect from "./FunctionSelect";
import MatrixBadge from "./MatrixBadge";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { ComponentDefinition, Parameter } from "@/registry/types";

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

  // Group parameters by type
  const scalarParams = visibleParams.filter(
    (p) => p.type === "Int" || p.type === "Real" || p.type === "Bool"
  );
  const geometryParams = visibleParams.filter(
    (p) => p.type === "PipeGeometry"
  );
  const functionParams = visibleParams.filter((p) => p.type === "Function");
  const matrixParams = visibleParams.filter((p) => p.type === "Matrix");

  function renderField(param: Parameter) {
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
    <div className="flex flex-col gap-[24px] min-w-0">
      {sections.map((section, idx) => (
        <div key={section.heading} className="min-w-0">
          {idx > 0 && <Separator className="mb-[24px]" />}
          <h3 className="text-[16px] font-semibold leading-[1.3] mb-[16px]">
            {section.heading}
          </h3>
          <div className="flex flex-col gap-[16px]">
            {section.params.map((param) => renderField(param))}
          </div>
        </div>
      ))}
    </div>
  );
}
