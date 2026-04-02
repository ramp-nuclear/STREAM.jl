import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipTrigger,
  TooltipContent,
} from "@/components/ui/tooltip";

interface PanelCollapseButtonProps {
  side: "left" | "right";
  collapsed: boolean;
  onToggle: () => void;
}

export default function PanelCollapseButton({
  side,
  collapsed,
  onToggle,
}: PanelCollapseButtonProps) {
  // Left side: collapsed = ChevronRight (expand), expanded = ChevronLeft (collapse)
  // Right side: collapsed = ChevronLeft (expand), expanded = ChevronRight (collapse)
  const showRight =
    (side === "left" && collapsed) || (side === "right" && !collapsed);
  const Icon = showRight ? ChevronRight : ChevronLeft;

  const panelName = side === "left" ? "toolbox" : "sidebar";
  const action = collapsed ? "Expand" : "Collapse";
  const tooltipText = `${action} ${panelName}`;

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant="ghost"
          size="icon-xs"
          className="shrink-0"
          onClick={onToggle}
          aria-label={tooltipText}
        >
          <Icon className="size-4" />
        </Button>
      </TooltipTrigger>
      <TooltipContent side={side === "left" ? "right" : "left"}>
        {tooltipText}
      </TooltipContent>
    </Tooltip>
  );
}
