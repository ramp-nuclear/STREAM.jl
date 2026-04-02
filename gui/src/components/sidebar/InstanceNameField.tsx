import { useState, useEffect } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { validateJuliaIdentifier } from "@/lib/validation";
import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

interface InstanceNameFieldProps {
  value: string;
  onChange: (name: string) => void;
}

export default function InstanceNameField({ value, onChange }: InstanceNameFieldProps) {
  const [localValue, setLocalValue] = useState(value);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLocalValue(value);
  }, [value]);

  function handleBlur() {
    const result = validateJuliaIdentifier(localValue);
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
        Name
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <Info className="h-3 w-3 text-muted-foreground cursor-default" />
            </TooltipTrigger>
            <TooltipContent>
              Julia variable name for this component in generated code
            </TooltipContent>
          </Tooltip>
        </TooltipProvider>
      </Label>
      <Input
        value={localValue}
        onChange={(e) => setLocalValue(e.target.value)}
        onBlur={handleBlur}
        className="text-base font-semibold"
      />
      {error && (
        <p className="text-destructive text-xs">{error}</p>
      )}
    </div>
  );
}
