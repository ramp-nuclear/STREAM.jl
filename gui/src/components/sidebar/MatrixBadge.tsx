import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import type { Parameter } from "@/registry/types";

interface MatrixBadgeProps {
  param: Parameter;
}

export default function MatrixBadge({ param }: MatrixBadgeProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">
        {param.name}
      </Label>
      <Badge variant="secondary">Matrix (edit in code)</Badge>
    </div>
  );
}
