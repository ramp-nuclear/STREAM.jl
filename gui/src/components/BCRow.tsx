import { Button } from "./ui/button";
import { X } from "lucide-react";

interface BCRowProps {
  expression: string;
  onDelete: () => void;
}

export default function BCRow({ expression, onDelete }: BCRowProps) {
  return (
    <div className="inline-flex items-center gap-1 bg-muted rounded-md pl-3 pr-1 py-1 max-w-full">
      <span className="font-mono text-sm truncate">{expression}</span>
      <Button
        variant="ghost"
        size="icon"
        className="h-5 w-5 shrink-0 hover:text-destructive"
        onClick={onDelete}
        aria-label="Remove boundary condition"
      >
        <X className="h-3 w-3" />
      </Button>
    </div>
  );
}
