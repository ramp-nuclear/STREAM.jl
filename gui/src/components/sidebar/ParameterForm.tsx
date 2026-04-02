import { Separator } from "@/components/ui/separator";
import NumericField from "./NumericField";
import PipeGeometryPicker from "./PipeGeometryPicker";
import FunctionSelect from "./FunctionSelect";
import MatrixBadge from "./MatrixBadge";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
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
            <Label className="text-[13px] font-semibold leading-[1.4]">
              {param.name}
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
        return (
          <PipeGeometryPicker
            key={param.name}
            value={values[param.name]}
            onChange={(v) => onParamChange(param.name, v)}
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
    sections.push({ heading: "Advanced", params: matrixParams });
  }

  return (
    <div className="flex flex-col gap-[24px]">
      {sections.map((section, idx) => (
        <div key={section.heading}>
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
