import { useCallback, useLayoutEffect, useRef, useState } from "react";
import { MoreHorizontal } from "lucide-react";
import { TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export interface ResponsiveTab {
  value: string;
  label: string;
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
 * Renders TabsTriggers for tabs that fit the available width; overflowing
 * tabs are accessible through a "..." dropdown at the right edge. The active
 * tab is pinned visible — if it would have overflowed, it's swapped in for
 * the last fitting tab.
 *
 * The "..." button only renders when at least one tab actually overflows.
 * When all tabs fit, the strip looks identical to a vanilla TabsList.
 *
 * Implementation: tab widths are measured from a separate off-screen layer
 * that always contains all tabs at their natural width. The visible strip's
 * `hidden` flags do not affect measurement, so the visible count can recover
 * upward when the container is widened again. Falls back to rendering every
 * tab when ResizeObserver is unavailable or the container width measures 0
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
      // Measurement layer not laid out yet; defer.
      return;
    }
    const totalWidth = widths.reduce((sum, w) => sum + w, 0);
    // Happy path: all tabs fit without an overflow button.
    if (totalWidth <= containerWidth) {
      setVisibleCount(tabs.length);
      return;
    }
    // Reserve for the "..." button and count tabs greedily from the start.
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

  // Re-measure when label text changes (rare; covers i18n / dynamic labels).
  useLayoutEffect(() => {
    recompute();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabs.map((t) => t.label).join("|")]);

  // Pin the active tab visible — if it would overflow, swap it for the last
  // fitting tab.
  const activeIndex = tabs.findIndex((t) => t.value === value);
  const visibleIndices = new Set<number>();
  for (let i = 0; i < visibleCount; i++) visibleIndices.add(i);
  if (activeIndex >= 0 && !visibleIndices.has(activeIndex)) {
    visibleIndices.delete(visibleCount - 1);
    visibleIndices.add(activeIndex);
  }

  const hiddenTabs = tabs.filter((_, i) => !visibleIndices.has(i));

  // Tailwind class string applied to both the off-screen measurement buttons
  // and the visible TabsTriggers so their content widths match exactly. The
  // measurement layer uses bare `<span>` elements, so it does not include
  // Radix Trigger base classes — empirically the px-[10px] + text-[12px]
  // padding dominates the natural width.
  const triggerClass = "px-[10px] text-[12px] flex-none data-[state=active]:border-primary";

  return (
    <div
      ref={containerRef}
      className="relative flex items-center w-full h-[28px] border-b overflow-hidden"
    >
      {/* Off-screen measurement layer. Rendered absolutely outside the
          viewport but kept in the layout flow at zero height so its
          children get real offsetWidth values. */}
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
              "inline-flex h-[28px] items-center justify-center whitespace-nowrap font-medium",
              triggerClass,
            )}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <TabsList
        variant="line"
        className="h-full justify-start rounded-none border-0 px-0 min-w-0"
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
