import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import type { ConstructorMode } from "@/registry/types";

interface ModeToggleProps {
  modes: ConstructorMode[];
  activeMode: string;
  onChange: (mode: string) => void;
}

const MODE_LABELS: Record<string, string> = {
  "fixed-dP": "Fixed dP",
  "fixed-mdot": "Fixed mdot",
};

function modeLabel(mode: string): string {
  return MODE_LABELS[mode] ?? mode;
}

export default function ModeToggle({
  modes,
  activeMode,
  onChange,
}: ModeToggleProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">Mode</Label>
      <div className="flex">
        {modes.map((m, idx) => (
          <Button
            key={m.mode}
            variant={m.mode === activeMode ? "default" : "outline"}
            size="sm"
            className={
              idx === 0
                ? "rounded-r-none"
                : idx === modes.length - 1
                  ? "rounded-l-none"
                  : "rounded-none"
            }
            onClick={() => onChange(m.mode)}
          >
            {modeLabel(m.mode)}
          </Button>
        ))}
      </div>
    </div>
  );
}
