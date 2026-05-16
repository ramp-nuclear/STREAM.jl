import { Code2, Download, Layers } from "lucide-react";
import { Button } from "./ui/button";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";
import type { LayerView } from "../lib/layers";

/**
 * Secondary toolbar strip (Phase 67 D-01/D-16/D-17).
 *
 * 32px full-width strip below the CustomTitlebar:
 *   [Layer toggle]            [Code button] [Export button]
 *
 * D-03/D-16 — ThemeMenu does NOT live here anymore (folded into ViewMenu);
 * FileMenu lives in CustomTitlebar.
 *
 * D-17 — Rendered at the root flex-col level, NOT inside the center column
 * (App.tsx restructure in Plan 03 Task 3 handles placement).
 */
export default function SecondaryToolbar() {
  // PERF — only subscribe to the things this component actually reads in its
  // render output. The Export click handler reads live state via
  // useStore.getState() at click time. We still need a boolean for the
  // disabled state on the Export button, so we subscribe to a derived
  // primitive (re-renders only when the canvas crosses the empty/non-empty
  // boundary). Same pattern as BottomPanel.tsx (commit 6c08bcd) and the rule
  // documented in gui/PERFORMANCE.md §3.
  const hasNodes = useStore((s) => s.nodes.length > 0);
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const activeLayer = useStore((s) => s.activeLayer);
  const setActiveLayer = useStore((s) => s.setActiveLayer);

  // Phase 66 Plan 03: the Tauri save-dialog + file-write path moved into
  // gui/src/lib/exportCode.ts so SecondaryToolbar.tsx (here) and
  // BottomPanel.tsx share the same util. `generateCode` is called inline at
  // export-time so the freshly-computed sections reflect the current store
  // state without paying for memoization.
  async function handleExport() {
    const s = useStore.getState();
    const sections = generateCode(
      s.nodes,
      s.edges,
      { anchors: s.anchors },
      getComponent,
      s.resources,
      { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
    );
    await exportCode({ sections, nodes: s.nodes });
  }

  return (
    <div className="flex items-center justify-between h-8 px-2 bg-chrome border-b w-full">
      {/* Left cluster: Layer toggle */}
      <div className="flex items-center gap-1.5">
        <Layers className="h-3.5 w-3.5 text-muted-foreground" />
        <span className="text-xs font-semibold text-muted-foreground select-none">
          Layer
        </span>
        <ToggleGroup
          type="single"
          value={activeLayer}
          onValueChange={(value: string) => {
            if (value) setActiveLayer(value as LayerView);
          }}
          size="sm"
          className="gap-0.5"
        >
          {/* Phase 67 Plan 04 — VSCode tab-style: no resting border, hover-only
              background, active gets a subtle filled bg (no border outline).
              The colored tint on active state preserves the hydraulic/thermal
              hue affordance without the boxed-control look. */}
          <ToggleGroupItem
            value="Hydraulic"
            className="h-7 px-2 text-xs font-normal border-0 bg-transparent hover:bg-accent data-[state=on]:bg-blue-500/15 data-[state=on]:text-blue-700 dark:data-[state=on]:text-blue-300"
          >
            Hydraulic
          </ToggleGroupItem>
          <ToggleGroupItem
            value="Both"
            className="h-7 px-2 text-xs font-normal border-0 bg-transparent hover:bg-accent data-[state=on]:bg-accent data-[state=on]:text-accent-foreground"
          >
            Both
          </ToggleGroupItem>
          <ToggleGroupItem
            value="Thermal"
            className="h-7 px-2 text-xs font-normal border-0 bg-transparent hover:bg-accent data-[state=on]:bg-amber-500/15 data-[state=on]:text-amber-700 dark:data-[state=on]:text-amber-300"
          >
            Thermal
          </ToggleGroupItem>
        </ToggleGroup>
      </div>

      {/* Right cluster: Code button + Export button.
          Phase 67 Plan 04 — ghost-style chrome controls. Code is a toggle
          (active = subtle accent bg, no border). Export is a flat chrome
          action — keeps the primary-fill ONLY when actively focused or
          hovered; otherwise sits flat alongside Code. */}
      <div className="flex items-center gap-0.5">
        <Button
          variant="ghost"
          size="sm"
          onClick={toggleBottomPanel}
          className={`h-7 px-2 text-xs font-normal ${bottomPanelOpen ? "bg-accent text-accent-foreground" : ""}`}
        >
          <Code2 className="h-3.5 w-3.5 mr-1" />
          Code
        </Button>
        <Button
          variant="ghost"
          size="sm"
          disabled={!hasNodes}
          onClick={handleExport}
          className="h-7 px-2 text-xs font-normal"
        >
          <Download className="h-3.5 w-3.5 mr-1" />
          Export
        </Button>
      </div>
    </div>
  );
}
