import { useEffect, useLayoutEffect, useRef, useState } from "react";
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
 * VS Code-style responsive tabs strip. Renders TabsTriggers for tabs that fit
 * the available width; overflowing tabs are accessible through a "..." dropdown
 * at the right edge of the strip. The currently active tab is always kept
 * visible — if it would have overflowed, the last visible tab is swapped out
 * for it.
 *
 * Falls back to rendering all tabs when ResizeObserver is unavailable or the
 * container width measures 0 (the test/jsdom path), so accessibility role
 * assertions (`getByRole("tab", { name: ... })`) keep passing.
 */
export function ResponsiveTabsList({
  tabs,
  value,
  onValueChange,
  overflowButtonWidth = 28,
}: ResponsiveTabsListProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [visibleCount, setVisibleCount] = useState(tabs.length);

  const recompute = () => {
    const el = containerRef.current;
    if (!el) return;
    const containerWidth = el.clientWidth;
    if (containerWidth === 0) {
      setVisibleCount(tabs.length);
      return;
    }
    const widths = tabRefs.current.map((r) => (r ? r.offsetWidth : 0));
    if (widths.some((w) => w === 0)) {
      // Tabs not yet laid out; defer to next ResizeObserver tick.
      return;
    }
    let used = 0;
    let count = 0;
    for (let i = 0; i < widths.length; i++) {
      const isLast = i === widths.length - 1;
      const reserve = isLast ? 0 : overflowButtonWidth;
      if (used + widths[i] + reserve <= containerWidth) {
        used += widths[i];
        count++;
      } else {
        break;
      }
    }
    setVisibleCount(Math.max(1, count));
  };

  useLayoutEffect(() => {
    recompute();
    const el = containerRef.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(recompute);
    ro.observe(el);
    return () => ro.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabs.length, overflowButtonWidth]);

  // Re-run measurement when label text changes (e.g., i18n).
  useEffect(() => {
    recompute();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tabs.map((t) => t.label).join("|")]);

  // Ensure the active tab is always visible. If it would overflow, swap it
  // with the last visible tab.
  const activeIndex = tabs.findIndex((t) => t.value === value);
  let visibleIndices = new Set<number>(
    tabs.slice(0, visibleCount).map((_, i) => i),
  );
  if (activeIndex >= 0 && !visibleIndices.has(activeIndex)) {
    visibleIndices = new Set(visibleIndices);
    visibleIndices.delete(visibleCount - 1);
    visibleIndices.add(activeIndex);
  }

  const hiddenTabs = tabs.filter((_, i) => !visibleIndices.has(i));

  return (
    <div
      ref={containerRef}
      className="flex items-center w-full h-[28px] border-b overflow-hidden"
    >
      <TabsList
        variant="line"
        className="h-full w-auto justify-start rounded-none border-0 px-0 min-w-0"
      >
        {tabs.map((tab, i) => (
          <TabsTrigger
            key={tab.value}
            ref={(el) => {
              tabRefs.current[i] = el;
            }}
            value={tab.value}
            className={cn(
              "px-[10px] text-[12px] flex-none data-[state=active]:border-primary",
              !visibleIndices.has(i) && "hidden",
            )}
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
