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
  /** Accessible name. Used as the tooltip text and the dropdown-menu label. */
  label: string;
  /** Optional icon. When provided, the strip shows an icon-only trigger with
   *  `label` as the accessible name + tooltip, VS Code Activity Bar style. */
  icon?: LucideIcon;
}

interface ResponsiveTabsListProps {
  tabs: ResponsiveTab[];
  value: string;
  onValueChange: (value: string) => void;
  /** Pixel width to reserve for the overflow "..." button. */
  overflowButtonWidth?: number;
}

/**
 * VS Code-style responsive tabs strip.
 *
 * Each tab renders as either:
 *   - Text (when `icon` is not provided)
 *   - Icon-only with tooltip + sr-only label (when `icon` is provided)
 *
 * Tabs that don't fit fall into a "..." dropdown at the right edge. The
 * dropdown only renders when at least one tab actually overflows. The active
 * tab is pinned visible — if it would have overflowed, it's swapped in for
 * the last fitting tab.
 *
 * Implementation: tab widths are measured from a separate off-screen layer
 * that always contains all tabs at natural width, so visibility state in the
 * visible row cannot poison subsequent measurements. Falls back to rendering
 * every tab when ResizeObserver is unavailable or the container width is 0
 * (the test/jsdom path), keeping `getByRole("tab", { name: ... })` green.
 */
export function ResponsiveTabsList({
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
    if (widths.length !== tabs.length || widths.some((w) => w === 0)) {
      return;
    }
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

  // Trigger style. Icon tabs render as 28×28 squares with hover outline; text
  // tabs render with horizontal padding. Both keep variant="line"'s
  // bottom-border active indicator from the TabsList parent.
  function triggerContent(tab: ResponsiveTab) {
    if (tab.icon) {
      const Icon = tab.icon;
      return (
        <>
          <Icon className="size-5" aria-hidden="true" />
          <span className="sr-only">{tab.label}</span>
        </>
      );
    }
    return tab.label;
  }

  function triggerClassFor(tab: ResponsiveTab) {
    if (tab.icon) {
      // Icon-only trigger: square, no border at any state. Active/hover are
      // communicated by icon color + a subtle background tint. The
      // variant=line `after` bottom-bar indicator is force-suppressed.
      return cn(
        "flex-none size-[32px] p-0 rounded-md border-0",
        // All icons stay at full foreground color (no dim). Hover and active
        // both apply a subtle bg-accent fill — active is the persistent form
        // of the hover state. !-prefixed so the shadcn TabsTrigger base
        // rules (data-[state=active]:bg-background, dark:text-muted-
        // foreground, etc.) do not win the cascade.
        "!text-foreground dark:!text-foreground",
        "!bg-transparent",
        "hover:!bg-accent",
        "data-[state=active]:!bg-accent dark:data-[state=active]:!bg-accent",
        "data-[state=active]:after:!opacity-0",
      );
    }
    return "px-[10px] text-[12px] flex-none data-[state=active]:border-primary";
  }

  return (
    <div
      ref={containerRef}
      className="relative flex items-center w-full h-[40px] overflow-hidden"
    >
      {/* Off-screen measurement layer — all tabs at natural width, never hidden. */}
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
              triggerClassFor(tab),
            )}
          >
            {triggerContent(tab)}
          </button>
        ))}
      </div>

      <TabsList
        variant="line"
        className="h-full justify-start rounded-none border-0 px-1 min-w-0 gap-2"
      >
        {tabs.map((tab, i) => {
          const triggerEl = (
            <TabsTrigger
              key={tab.value}
              value={tab.value}
              aria-label={tab.icon ? tab.label : undefined}
              className={cn(triggerClassFor(tab), !visibleIndices.has(i) && "hidden")}
            >
              {triggerContent(tab)}
            </TabsTrigger>
          );
          if (!tab.icon) return triggerEl;
          return (
            <Tooltip key={tab.value}>
              <TooltipTrigger asChild>{triggerEl}</TooltipTrigger>
              <TooltipContent side="bottom">{tab.label}</TooltipContent>
            </Tooltip>
          );
        })}
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
            {hiddenTabs.map((t) => {
              const Icon = t.icon;
              return (
                <DropdownMenuItem
                  key={t.value}
                  onSelect={() => onValueChange(t.value)}
                >
                  {Icon && <Icon className="size-4 mr-2" aria-hidden="true" />}
                  {t.label}
                </DropdownMenuItem>
              );
            })}
          </DropdownMenuContent>
        </DropdownMenu>
      )}
    </div>
  );
}
