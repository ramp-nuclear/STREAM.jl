import { useEffect, useState } from "react";
import { Copy, Check, Download } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import { Button } from "./ui/button";
import useStore from "../store/useStore";
import { useBottomPanelResize } from "../hooks/useBottomPanelResize";
import { getComponent } from "../registry";
import { generateCode, serializeSections } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";
import CodePreview from "./CodePreview";

export default function BottomPanel() {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const bottomPanelHeight = useStore((s) => s.bottomPanelHeight);
  const { onMouseDown } = useBottomPanelResize();

  // Read-only store subs for the right-side Copy/Export action buttons.
  // (See Toolbar.tsx for the parallel call pattern — Phase 66 D-18 keeps
  // BOTH the Toolbar Export and this BottomPanel Copy/Export alive.)
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const anchors = useStore((s) => s.anchors);
  const resources = useStore((s) => s.resources);
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);

  // 1.5s confirmation state for the Copy button (Research Pattern 8).
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1500);
    return () => clearTimeout(t);
  }, [copied]);

  async function handleCopy() {
    const sections = generateCode(
      nodes,
      edges,
      { anchors },
      getComponent,
      resources,
      { bcMode, bcSymmetric },
    );
    try {
      await navigator.clipboard.writeText(serializeSections(sections));
      setCopied(true);
    } catch (err) {
      // Clipboard rejection (permission, http context, etc) — surface to
      // console; don't flip to "Copied" state.
      console.error("Copy to clipboard failed:", err);
    }
  }

  async function handleExport() {
    const sections = generateCode(
      nodes,
      edges,
      { anchors },
      getComponent,
      resources,
      { bcMode, bcSymmetric },
    );
    // Boolean return discarded — exportCode handles its own validation gate
    // (writes validationResult side-effect for the existing dialog) and
    // user-cancel path. Matches Toolbar.tsx's handleExport behavior.
    await exportCode({ sections, nodes });
  }

  if (!bottomPanelOpen) return null;

  return (
    <div style={{ height: bottomPanelHeight }} className="border-t flex flex-col">
      {/* Drag handle */}
      <div
        className="h-2 w-full cursor-row-resize hover:bg-ring/30 transition-colors flex-shrink-0"
        onMouseDown={onMouseDown}
      />
      <Tabs defaultValue="code" className="flex-1 min-h-0 flex flex-col">
        <div className="mx-2 mt-1 flex items-center">
          <TabsList>
            <TabsTrigger value="code" className="text-[13px] font-medium">
              Code
            </TabsTrigger>
          </TabsList>
          <div className="ml-auto flex items-center gap-1">
            <Button
              size="sm"
              variant="outline"
              disabled={nodes.length === 0}
              onClick={handleCopy}
              aria-label="Copy generated Julia code to clipboard"
            >
              {copied ? (
                <>
                  <Check className="h-4 w-4 mr-1" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="h-4 w-4 mr-1" />
                  Copy
                </>
              )}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={nodes.length === 0}
              onClick={handleExport}
              aria-label="Export generated Julia code to file"
            >
              <Download className="h-4 w-4 mr-1" />
              Export
            </Button>
          </div>
        </div>
        <TabsContent value="code" className="flex-1 min-h-0">
          <CodePreview />
        </TabsContent>
      </Tabs>
    </div>
  );
}
