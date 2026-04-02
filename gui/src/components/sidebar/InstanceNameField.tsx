import { useState, useEffect } from "react";
import { Input } from "@/components/ui/input";
import { validateJuliaIdentifier } from "@/lib/validation";

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
