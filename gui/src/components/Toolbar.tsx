import { useMemo } from "react";
import { Code2, Download } from "lucide-react";
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { Button } from "./ui/button";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";
import FileMenu from "./FileMenu";

interface Props {
  onUnsavedCheck: () => Promise<"save" | "discard" | "cancel">;
}

export default function Toolbar({ onUnsavedCheck }: Props) {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const bcs = useStore((s) => s.bcs);
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const isDirty = useStore((s) => s.isDirty);
  const currentFilePath = useStore((s) => s.currentFilePath);

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
      <div className="flex items-center gap-1">
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
