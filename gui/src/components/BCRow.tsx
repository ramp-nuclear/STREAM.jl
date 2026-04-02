import { Button } from "./ui/button";
import { X } from "lucide-react";

interface BCRowProps {
  expression: string;
  onDelete: () => void;
}

export default function BCRow({ expression, onDelete }: BCRowProps) {
  return (
    <div className="flex items-center justify-between bg-muted rounded-md px-3 py-1.5">
      <span className="font-mono text-sm">{expression}</span>
      <Button
        variant="ghost"
        size="icon"
        className="h-6 w-6 hover:text-destructive"
        onClick={onDelete}
        aria-label="Remove boundary condition"
      >
        <X className="h-4 w-4" />
      </Button>
    </div>
  );
}
