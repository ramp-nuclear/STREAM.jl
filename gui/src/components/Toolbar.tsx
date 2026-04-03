import { useMemo } from "react";
import { Code2, Download, Layers } from "lucide-react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { Button } from "./ui/button";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";
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
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const bcs = useStore((s) => s.bcs);
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);
  const activeLayer = useStore((s) => s.activeLayer);
  const setActiveLayer = useStore((s) => s.setActiveLayer);

  const code = useMemo(
    () => generateCode(nodes, edges, bcs, getComponent),
    [nodes, edges, bcs],
  );

  async function handleExport() {
    const result = useStore.getState().validateAndGate();
    if (!result.valid) return; // Dialog will show via validationResult state

    const filePath = await save({
      defaultPath: "system.jl",
      filters: [{ name: "Julia files", extensions: ["jl"] }],
    });
    if (filePath) {
      await writeTextFile(filePath, code);
    }
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
          disabled={nodes.length === 0}
          onClick={handleExport}
        >
          <Download className="h-4 w-4 mr-1" />
          Export
        </Button>
      </div>
    </div>
  );
}
