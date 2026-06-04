import { Info } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { Parameter } from "@/registry/types";

interface MatrixBadgeProps {
  param: Parameter;
}

export default function MatrixBadge({ param }: MatrixBadgeProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-body font-semibold leading-[1.4] flex items-center gap-1">
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
      <Badge variant="secondary">Matrix (edit in code)</Badge>
    </div>
  );
}
