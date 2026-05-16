import { Code2, Download, Layers } from "lucide-react";
import { Button } from "./ui/button";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";
import type { LayerView } from "../lib/layers";
import FileMenu from "./FileMenu";
import ThemeMenu from "./ThemeMenu";
import type { Theme } from "../hooks/useTheme";

interface Props {
  onUnsavedCheck: () => Promise<"save" | "discard" | "cancel">;
  theme: Theme;
  resolvedTheme: "light" | "dark";
  setTheme: (t: Theme) => void;
}

export default function Toolbar({ onUnsavedCheck, theme, setTheme }: Props) {
  // PERF — only subscribe to the things this component actually reads in its
  // render output. The Export click handler reads live state via
  // useStore.getState() at click time. Previously Toolbar subscribed to the
  // full nodes/edges/anchors/resources/bcMode/bcSymmetric set just to pass
  // them to generateCode in handleExport — every one of those fired on every
  // ReactFlow drag tick (60 Hz), re-rendering the always-mounted Toolbar.
  // We still need a boolean for the disabled state on the Export button, so
  // we subscribe to a derived primitive (re-renders only when the canvas
  // crosses the empty/non-empty boundary). Same pattern as BottomPanel.tsx
  // (commit 6c08bcd) and the rule documented in gui/PERFORMANCE.md §3.
  const hasNodes = useStore((s) => s.nodes.length > 0);
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);
  const activeLayer = useStore((s) => s.activeLayer);
  const setActiveLayer = useStore((s) => s.setActiveLayer);

  // Phase 66 Plan 03: the Tauri save-dialog + file-write path moved into
  // gui/src/lib/exportCode.ts so Toolbar.tsx (here) and BottomPanel.tsx
  // (Plan 04) share the same util. `generateCode` is called inline at
  // export-time so the freshly-computed sections reflect the current store
  // state without paying for memoization that the now-unused
  // `serializeSections` wrap previously required.
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
    <div className="flex items-center justify-between h-9 px-2 bg-muted border-b">
      {/* Left section: FileMenu, filename, Code button */}
      <div className="flex items-center gap-1">
        <FileMenu onUnsavedCheck={onUnsavedCheck} />
        <span className="text-xs text-muted-foreground ml-2 select-none">
          {currentFilePath
            ? `${currentFilePath.split(/[/\\]/).pop()}${isDirty ? " *" : ""}`
            : isDirty
              ? "Untitled *"
              : ""}
        </span>
        <Button
          variant={bottomPanelOpen ? "default" : "outline"}
          size="sm"
          onClick={toggleBottomPanel}
        >
          <Code2 className="h-4 w-4 mr-1" />
          Code
        </Button>
      </div>

      {/* Center section: Layer toggle */}
      <div className="flex items-center gap-1.5">
        <Layers className="h-3.5 w-3.5 text-muted-foreground" />
        <span className="text-xs font-semibold text-muted-foreground select-none">Layer</span>
        <ToggleGroup
          type="single"
          value={activeLayer}
          onValueChange={(value: string) => {
            if (value) setActiveLayer(value as LayerView);
          }}
          variant="outline"
          size="sm"
          className="border rounded-md"
        >
          <ToggleGroupItem
            value="Hydraulic"
            className="data-[state=on]:bg-blue-500/25 data-[state=on]:text-blue-700 data-[state=on]:border-blue-400 dark:data-[state=on]:text-blue-300"
          >
            Hydraulic
          </ToggleGroupItem>
          <ToggleGroupItem
            value="Both"
            className="data-[state=on]:bg-slate-200 data-[state=on]:text-slate-700 dark:data-[state=on]:bg-slate-700 dark:data-[state=on]:text-slate-200"
          >
            Both
          </ToggleGroupItem>
          <ToggleGroupItem
            value="Thermal"
            className="data-[state=on]:bg-amber-500/25 data-[state=on]:text-amber-700 data-[state=on]:border-amber-400 dark:data-[state=on]:text-amber-300"
          >
            Thermal
          </ToggleGroupItem>
        </ToggleGroup>
      </div>

      {/* Right section: ThemeMenu + Export button */}
      <div className="flex items-center gap-1">
        <ThemeMenu theme={theme} setTheme={setTheme} />
        <Button
          variant="default"
          size="sm"
          disabled={!hasNodes}
          onClick={handleExport}
        >
          <Download className="h-4 w-4 mr-1" />
          Export
        </Button>
      </div>
    </div>
  );
}
