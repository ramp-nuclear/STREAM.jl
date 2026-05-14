import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { validateInt, validateReal } from "@/lib/validation";
import type { Parameter } from "@/registry/types";
import { cn } from "@/lib/utils";
import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

interface NumericFieldProps {
  param: Parameter;
  value: unknown;
  onChange: (value: number | undefined) => void;
}

export default function NumericField({ param, value, onChange }: NumericFieldProps) {
  const [localValue, setLocalValue] = useState(
    String(value ?? param.default ?? "")
  );
  const [error, setError] = useState<string | null>(null);

  function handleBlur() {
    const trimmed = localValue.trim();

    // Three-branch blank-on-blur rule (§3.5 reset-to-empty, Plan 65-02):
    if (trimmed === "") {
      if (param.default != null) {
        // Branch 1: registry default exists — restore it.
        const defaultVal = param.default as number;
        setError(null);
        setLocalValue(String(defaultVal));
        onChange(defaultVal);
      } else if (param.required) {
        // Branch 2: required, no default — surface error.
        setError("required");
      } else {
        // Branch 3: optional, no default — omit from code-gen.
        setError(null);
        onChange(undefined);
      }
      return;
    }

    const result =
      param.type === "Int" ? validateInt(localValue) : validateReal(localValue);
    if (result.valid) {
      setError(null);
      onChange(result.value);
    } else {
      setError(result.message);
    }
  }

  return (
    <div className="flex flex-col gap-[4px] min-w-0">
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
      <div className="relative">
        <Input
          value={localValue}
          onChange={(e) => setLocalValue(e.target.value)}
          onBlur={handleBlur}
          inputMode={param.type === "Int" ? "numeric" : "decimal"}
          className={cn(
            param.unit && "pr-12",
            error && "border-destructive"
          )}
        />
        {param.unit && (
          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-[13px] font-semibold pointer-events-none">
            {param.unit}
          </span>
        )}
      </div>
      {error && (
        <p className="text-destructive text-xs">{error}</p>
      )}
    </div>
  );
}
