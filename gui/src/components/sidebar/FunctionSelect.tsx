import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Label } from "@/components/ui/label";
import { Info } from "lucide-react";
import NumericField from "./NumericField";
import type { Parameter, FactoryCorrelationValue } from "@/registry/types";

interface FunctionSelectProps {
  param: Parameter;
  value: unknown;
  onChange: (value: string | FactoryCorrelationValue) => void;
}

/** Extract the Select string value from whatever the store holds:
 *  - plain string  → use directly
 *  - FactoryCorrelationValue → extract .value (the factory name)
 *  - anything else → fall back to param.default or ""
 */
function extractSelectValue(value: unknown, defaultVal: unknown): string {
  if (typeof value === "string") return value;
  if (
    value !== null &&
    typeof value === "object" &&
    "kind" in value &&
    (value as FactoryCorrelationValue).kind === "factory"
  ) {
    return (value as FactoryCorrelationValue).value;
  }
  return String(defaultVal ?? "");
}

/** Extract subParams from an existing FactoryCorrelationValue in the store,
 *  or return an empty object if none exist yet. */
function extractSubParams(value: unknown): Record<string, unknown> {
  if (
    value !== null &&
    typeof value === "object" &&
    "kind" in value &&
    (value as FactoryCorrelationValue).kind === "factory"
  ) {
    return (value as FactoryCorrelationValue).subParams ?? {};
  }
  return {};
}

export default function FunctionSelect({
  param,
  value,
  onChange,
}: FunctionSelectProps) {
  const options = param.options;
  if (!options || options.length === 0) return null;

  const currentValue = extractSelectValue(value, param.default);

  // The selected option object (null when nothing matched)
  const selectedOption = options.find((o) => o.value === currentValue) ?? null;
  const isFactory = selectedOption?.kind === "factory";
  const subParams = selectedOption?.sub_parameters ?? [];

  // Current sub-param values: pull from store if value is FactoryCorrelationValue
  const currentSubParams = isFactory ? extractSubParams(value) : {};

  function handleSelectChange(newValue: string) {
    const option = options!.find((o) => o.value === newValue);
    if (option?.kind === "factory") {
      // Factory selected: emit FactoryCorrelationValue with empty subParams (D-05: discard previous)
      onChange({ kind: "factory", value: newValue, subParams: {} });
    } else {
      // Simple closure: emit plain string (D-06)
      onChange(newValue);
    }
  }

  function handleSubParamChange(subParamName: string, subParamValue: unknown) {
    // Merge updated sub-param into existing FactoryCorrelationValue
    onChange({
      kind: "factory",
      value: currentValue,
      subParams: { ...currentSubParams, [subParamName]: subParamValue },
    });
  }

  return (
    <div className="flex flex-col gap-[8px]">
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
      <Select value={currentValue} onValueChange={handleSelectChange}>
        <SelectTrigger className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      {/* Sub-field container: only shown when a factory option is selected and has sub_parameters */}
      {isFactory && subParams.length > 0 && (
        <div className="border-l-2 border-muted pl-3 mt-1 flex flex-col gap-[12px]">
          {subParams.map((subParam) => {
            if (subParam.type === "Function") {
              // Sub-dropdown: only simple closures from sub_param.options (D-11 enforced by registry)
              return (
                <FunctionSelect
                  key={subParam.name}
                  param={subParam}
                  value={currentSubParams[subParam.name]}
                  onChange={(v) => handleSubParamChange(subParam.name, v)}
                />
              );
            }
            if (subParam.type === "Real" || subParam.type === "Int") {
              return (
                <NumericField
                  key={subParam.name}
                  param={subParam}
                  value={currentSubParams[subParam.name]}
                  onChange={(v) => handleSubParamChange(subParam.name, v)}
                />
              );
            }
            return null;
          })}
        </div>
      )}
    </div>
  );
}
