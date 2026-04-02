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
import type { Parameter } from "@/registry/types";

interface FunctionSelectProps {
  param: Parameter;
  value: unknown;
  onChange: (value: string) => void;
}

export default function FunctionSelect({
  param,
  value,
  onChange,
}: FunctionSelectProps) {
  const options = param.options;
  if (!options || options.length === 0) return null;

  const currentValue = String(value ?? param.default ?? "");

  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">
        {param.name}
      </Label>
      <TooltipProvider>
        <Select value={currentValue} onValueChange={onChange}>
          <SelectTrigger className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {options.map((option) =>
              option.kind === "factory" ? (
                <Tooltip key={option.value}>
                  <TooltipTrigger asChild>
                    <div>
                      <SelectItem
                        value={option.value}
                        disabled
                        className="text-muted-foreground"
                      >
                        {option.label}
                      </SelectItem>
                    </div>
                  </TooltipTrigger>
                  <TooltipContent side="right">
                    Factory correlation editing coming in a future update
                  </TooltipContent>
                </Tooltip>
              ) : (
                <SelectItem key={option.value} value={option.value}>
                  {option.label}
                </SelectItem>
              )
            )}
          </SelectContent>
        </Select>
      </TooltipProvider>
    </div>
  );
}
