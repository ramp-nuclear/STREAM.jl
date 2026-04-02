import { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { validatePositiveReal } from "@/lib/validation";
import { cn } from "@/lib/utils";

type PipeGeometryValue =
  | { type: "circular"; L: number | ""; D: number | "" }
  | { type: "rectangular"; L: number | ""; W: number | ""; H: number | "" }
  | undefined;

interface PipeGeometryPickerProps {
  value: unknown;
  onChange: (value: PipeGeometryValue) => void;
}

function parseValue(value: unknown): PipeGeometryValue {
  if (
    value &&
    typeof value === "object" &&
    "type" in value &&
    ((value as { type: string }).type === "circular" ||
      (value as { type: string }).type === "rectangular")
  ) {
    return value as PipeGeometryValue;
  }
  return { type: "circular", L: "", D: "" };
}

interface DimensionFieldProps {
  label: string;
  value: string;
  onChange: (value: string) => void;
  onBlur: () => void;
  error: string | null;
}

function DimensionField({
  label,
  value,
  onChange,
  onBlur,
  error,
}: DimensionFieldProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">
        {label}
      </Label>
      <div className="relative">
        <Input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onBlur={onBlur}
          inputMode="decimal"
          className={cn("pr-12", error && "border-destructive")}
        />
        <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-[13px] font-semibold pointer-events-none">
          m
        </span>
      </div>
      {error && <p className="text-destructive text-xs">{error}</p>}
    </div>
  );
}

export default function PipeGeometryPicker({
  value,
  onChange,
}: PipeGeometryPickerProps) {
  const parsed = parseValue(value);
  const geoType = parsed?.type ?? "circular";

  const [localFields, setLocalFields] = useState<Record<string, string>>(() => {
    if (!parsed) return { L: "", D: "" } as Record<string, string>;
    if (parsed.type === "circular") {
      return { L: String(parsed.L), D: String(parsed.D) } as Record<string, string>;
    }
    return {
      L: String(parsed.L),
      W: String(parsed.W),
      H: String(parsed.H),
    } as Record<string, string>;
  });

  const [errors, setErrors] = useState<Record<string, string | null>>({});

  // Sync from prop changes
  useEffect(() => {
    const p = parseValue(value);
    if (!p) return;
    if (p.type === "circular") {
      setLocalFields({ L: String(p.L), D: String(p.D) });
    } else {
      setLocalFields({
        L: String(p.L),
        W: String(p.W),
        H: String(p.H),
      });
    }
  }, [value]);

  const handleTypeSwitch = useCallback(
    (newType: "circular" | "rectangular") => {
      setErrors({});
      if (newType === "circular") {
        setLocalFields({ L: "", D: "" });
        onChange({ type: "circular", L: "", D: "" });
      } else {
        setLocalFields({ L: "", W: "", H: "" });
        onChange({ type: "rectangular", L: "", W: "", H: "" });
      }
    },
    [onChange]
  );

  function handleFieldBlur(field: string) {
    const result = validatePositiveReal(localFields[field] ?? "");
    if (result.valid) {
      setErrors((prev) => ({ ...prev, [field]: null }));
      // Build updated geometry value
      if (geoType === "circular") {
        const updated = {
          type: "circular" as const,
          L: field === "L" ? result.value : numOrEmpty(localFields.L),
          D: field === "D" ? result.value : numOrEmpty(localFields.D),
        };
        onChange(updated);
      } else {
        const updated = {
          type: "rectangular" as const,
          L: field === "L" ? result.value : numOrEmpty(localFields.L),
          W: field === "W" ? result.value : numOrEmpty(localFields.W),
          H: field === "H" ? result.value : numOrEmpty(localFields.H),
        };
        onChange(updated);
      }
    } else {
      setErrors((prev) => ({ ...prev, [field]: result.message }));
    }
  }

  function numOrEmpty(s: string): number | "" {
    const n = Number(s);
    return isNaN(n) || s === "" ? "" : n;
  }

  const circularFields = [
    { label: "L", key: "L" },
    { label: "D", key: "D" },
  ];

  const rectangularFields = [
    { label: "L", key: "L" },
    { label: "W", key: "W" },
    { label: "H", key: "H" },
  ];

  const fields = geoType === "circular" ? circularFields : rectangularFields;

  return (
    <div className="flex flex-col gap-[16px]">
      <div className="flex">
        <Button
          variant={geoType === "circular" ? "default" : "outline"}
          size="sm"
          className="rounded-r-none"
          onClick={() => handleTypeSwitch("circular")}
        >
          Circular
        </Button>
        <Button
          variant={geoType === "rectangular" ? "default" : "outline"}
          size="sm"
          className="rounded-l-none"
          onClick={() => handleTypeSwitch("rectangular")}
        >
          Rectangular
        </Button>
      </div>
      {fields.map((f) => (
        <DimensionField
          key={f.key}
          label={f.label}
          value={localFields[f.key] ?? ""}
          onChange={(v) =>
            setLocalFields((prev) => ({ ...prev, [f.key]: v }))
          }
          onBlur={() => handleFieldBlur(f.key)}
          error={errors[f.key] ?? null}
        />
      ))}
    </div>
  );
}
