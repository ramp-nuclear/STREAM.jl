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
  onChange: (value: number) => void;
}

export default function NumericField({ param, value, onChange }: NumericFieldProps) {
  const [localValue, setLocalValue] = useState(
    String(value ?? param.default ?? "")
  );
  const [error, setError] = useState<string | null>(null);

  function handleBlur() {
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
