import { useCallback, useLayoutEffect, useRef, useState } from "react";
import { MoreHorizontal, type LucideIcon } from "lucide-react";
import { TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export interface ResponsiveTab {
  value: string;
  label: string;
  icon?: LucideIcon;
}

interface ResponsiveTabsListProps {
  tabs: ResponsiveTab[];
  value: string;
  onValueChange: (value: string) => void;
  /** Pixel width to reserve for the overflow "..." button (text mode only). */
  overflowButtonWidth?: number;
}

/**
 * VS Code-style responsive tabs strip.
 *
 * Two render paths:
 *
 *   - **Icon-only mode** (every tab has an `icon`): custom `<button role="tab">`
 *     elements with state driven by the parent `<Tabs value>` prop. Bypasses
 *     shadcn TabsTrigger entirely so we own the color cascade — no fight with
 *     `data-[state=active]:text-foreground` and friends. Three 32×32 icons
 *     always fit the 120px minimum panel width, so no overflow needed.
 *
 *   - **Text mode** (any tab without an `icon`): falls through to the original
 *     TabsList + TabsTrigger path with ResizeObserver-based overflow into a
 *     "..." DropdownMenu. Kept for legacy text-tab callers.
 *
 * In icon mode the wrapping `<Tabs>` in the parent still tracks `value`, and
 * `<TabsContent value="...">` still switches based on it — only the trigger
 * row is custom. `role="tab"` + `aria-selected` + `aria-label` keep
 * accessible-name lookups (`getByRole("tab", { name: ... })`) passing.
 */
export function ResponsiveTabsList(props: ResponsiveTabsListProps) {
  const { tabs } = props;
  const iconOnly = tabs.length > 0 && tabs.every((t) => t.icon != null);
  if (iconOnly) return <IconTabsList {...props} />;
  return <TextTabsList {...props} />;
}

// =========================================================================
// Icon-only mode — custom buttons, no shadcn TabsTrigger
// =========================================================================

function IconTabsList({
  tabs,
  value,
  onValueChange,
}: ResponsiveTabsListProps) {
  return (
    <div className="flex items-center gap-1 px-1 h-[40px]" role="tablist">
      {tabs.map((tab) => {
        const Icon = tab.icon!;
        const isActive = tab.value === value;
        return (
          <Tooltip key={tab.value}>
            <TooltipTrigger asChild>
              <button
                type="button"
                role="tab"
                aria-selected={isActive}
                aria-label={tab.label}
                onClick={() => onValueChange(tab.value)}
                className={cn(
                  "flex items-center justify-center size-[32px] rounded-md transition-colors cursor-pointer",
                  "hover:bg-accent",
                  isActive
                    ? "text-primary"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                <Icon className="size-5" aria-hidden="true" />
                <span className="sr-only">{tab.label}</span>
              </button>
            </TooltipTrigger>
            <TooltipContent side="bottom">{tab.label}</TooltipContent>
          </Tooltip>
        );
      })}
    </div>
  );
}

// =========================================================================
// Text mode — shadcn TabsList with overflow detection (legacy path)
// =========================================================================

function TextTabsList({
  tabs,
  value,
  onValueChange,
  overflowButtonWidth = 28,
}: ResponsiveTabsListProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const measureRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [visibleCount, setVisibleCount] = useState(tabs.length);

  const recompute = useCallback(() => {
    const container = containerRef.current;
    if (!container) return;
    const containerWidth = container.clientWidth;
    if (containerWidth === 0) {
      setVisibleCount(tabs.length);
      return;
    }
    const widths = measureRefs.current.map((r) => (r ? r.offsetWidth : 0));
    if (widths.length !== tabs.length || widths.some((w) => w === 0)) return;
    const totalWidth = widths.reduce((sum, w) => sum + w, 0);
    if (totalWidth <= containerWidth) {
      setVisibleCount(tabs.length);
      return;
    }
    const availableWidth = containerWidth - overflowButtonWidth;
    let used = 0;
    let count = 0;
    for (let i = 0; i < widths.length; i++) {
      if (used + widths[i] <= availableWidth) {
        used += widths[i];
        count++;
      } else {
        break;
      }
    }
    setVisibleCount(Math.max(1, count));
  }, [tabs.length, overflowButtonWidth]);

  useLayoutEffect(() => {
    recompute();
    const container = containerRef.current;
    if (!container || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(recompute);
    ro.observe(container);
    return () => ro.disconnect();
  }, [recompute]);

  useLayoutEffect(() => {
    recompute();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabs.map((t) => t.label).join("|")]);

  const activeIndex = tabs.findIndex((t) => t.value === value);
  const visibleIndices = new Set<number>();
  for (let i = 0; i < visibleCount; i++) visibleIndices.add(i);
  if (activeIndex >= 0 && !visibleIndices.has(activeIndex)) {
    visibleIndices.delete(visibleCount - 1);
    visibleIndices.add(activeIndex);
  }
  const hiddenTabs = tabs.filter((_, i) => !visibleIndices.has(i));
  const triggerClass = "px-[10px] text-[12px] flex-none data-[state=active]:border-primary";

  return (
    <div
      ref={containerRef}
      className="relative flex items-center w-full h-[28px] border-b overflow-hidden"
    >
      <div
        aria-hidden="true"
        className="absolute top-0 left-0 -translate-y-[200%] flex items-center pointer-events-none"
      >
        {tabs.map((tab, i) => (
          <button
            key={`measure-${tab.value}`}
            ref={(el) => {
              measureRefs.current[i] = el;
            }}
            type="button"
            tabIndex={-1}
            className={cn(
              "inline-flex items-center justify-center whitespace-nowrap font-medium",
              triggerClass,
            )}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <TabsList
        variant="line"
        className="h-full justify-start rounded-none border-0 px-1 min-w-0 gap-2"
      >
        {tabs.map((tab, i) => (
          <TabsTrigger
            key={tab.value}
            value={tab.value}
            className={cn(triggerClass, !visibleIndices.has(i) && "hidden")}
          >
            {tab.label}
          </TabsTrigger>
        ))}
      </TabsList>
      {hiddenTabs.length > 0 && (
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              size="icon-xs"
              aria-label="More tabs"
              className="ml-auto mr-1 shrink-0"
            >
              <MoreHorizontal className="size-3.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {hiddenTabs.map((t) => (
              <DropdownMenuItem
                key={t.value}
                onSelect={() => onValueChange(t.value)}
              >
                {t.label}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </div>
  );
}
