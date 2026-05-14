import { useState, useEffect, useRef } from "react";
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
  // Ref used by the stream:focus-instance-name event listener (Phase 65 Plan 05 W7 rename).
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    setLocalValue(value);
  }, [value]);

  // Phase 65 Plan 05 W7: listen for rename focus event dispatched by NodeContextMenu Rename item.
  // selectNode(nodeId) fires before this event so the sidebar is already showing this field.
  // We do not filter by event.detail.nodeId because this component only mounts when a node
  // is selected — by the time the event fires the correct node is already active.
  useEffect(() => {
    function handleFocusEvent() {
      inputRef.current?.focus();
      inputRef.current?.select();
    }
    window.addEventListener("stream:focus-instance-name", handleFocusEvent);
    return () => {
      window.removeEventListener("stream:focus-instance-name", handleFocusEvent);
    };
  }, []);

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
        ref={inputRef}
        value={localValue}
        onChange={(e) => setLocalValue(e.target.value)}
        onBlur={handleBlur}
        className="text-base font-semibold"
        data-instance-name-input
      />
      {error && (
        <p className="text-destructive text-xs">{error}</p>
      )}
    </div>
  );
}
