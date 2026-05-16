import { useEffect, useState } from "react";
import { Copy, Check, Download, ChevronDown, ChevronUp } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "./ui/tabs";
import { Button } from "./ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import useStore from "../store/useStore";
import { useBottomPanelResize } from "../hooks/useBottomPanelResize";
import { getComponent } from "../registry";
import { generateCode, serializeSections } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";
import CodePreview from "./CodePreview";

export default function BottomPanel() {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const bottomPanelHeight = useStore((s) => s.bottomPanelHeight);
  const toggleBottomPanel = useStore((s) => s.toggleBottomPanel);
  const { onMouseDown } = useBottomPanelResize();

  // PERF — only subscribe to the things this component actually reads in its
  // render output. The Copy/Export click handlers read live state via
  // useStore.getState() at click time (a tick-old reference is fine).
  // Previously this component subscribed to the full `nodes` array (etc.),
  // which re-rendered the BottomPanel on every ReactFlow drag tick and was
  // an unrelated contributor to the code-tab lag.
  // We DO need a boolean for the disabled state on Copy/Export, so we
  // subscribe to a derived primitive instead of the array — re-renders fire
  // only when the canvas crosses the empty/non-empty boundary.
  const hasNodes = useStore((s) => s.nodes.length > 0);

  // 1.5s confirmation state for the Copy button (Research Pattern 8).
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1500);
    return () => clearTimeout(t);
  }, [copied]);

  async function handleCopy() {
    const s = useStore.getState();
    const sections = generateCode(
      s.nodes,
      s.edges,
      { anchors: s.anchors },
      getComponent,
      s.resources,
      { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
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
    const s = useStore.getState();
    const sections = generateCode(
      s.nodes,
      s.edges,
      { anchors: s.anchors },
      getComponent,
      s.resources,
      { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
    );
    // Boolean return discarded — exportCode handles its own validation gate
    // (writes validationResult side-effect for the existing dialog) and
    // user-cancel path. Matches Toolbar.tsx's handleExport behavior.
    await exportCode({ sections, nodes: s.nodes });
  }

  // Phase 68 D-10 — closed-state stub strip. Replaces the previous
  // `return null` early-exit so a persistent 20px (h-5) clickable affordance
  // always sits at the bottom of the window, mirroring VSCode's bottom-panel
  // collapsed state. Click anywhere on the strip to re-open the panel.
  // No animation between open/closed — switching is instantaneous per
  // UI-SPEC §4 (hidden mode does NOT animate).
  if (!bottomPanelOpen) {
    // Slimmer stub strip (Phase 68 UAT 2026-05-17 polish — keep until
    // Phase 72 full design pass). 14px tall, bg-background instead of
    // bg-chrome so it reads as a subtle edge affordance rather than a
    // persistent dark bar. Label drops to 10px to fit the new height.
    return (
      <div
        className="h-3.5 border-t flex items-center justify-center gap-1 cursor-pointer bg-background hover:bg-accent/40 transition-colors select-none"
        onClick={toggleBottomPanel}
        role="button"
        aria-label="Expand code panel"
      >
        <span className="text-[10px] font-normal text-muted-foreground leading-none">
          Code
        </span>
        <ChevronUp className="w-2.5 h-2.5 text-muted-foreground" />
      </div>
    );
  }

  return (
    <div style={{ height: bottomPanelHeight }} className="border-t flex flex-col bg-panel">
      {/* Drag handle — VS Code-style 4px sash: transparent at rest, subtle
          tint on hover. Phase 68 UAT 2026-05-17 polish (was h-2/8px). */}
      <div
        className="h-1 w-full cursor-row-resize hover:bg-ring/30 transition-colors flex-shrink-0"
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
            {/* Phase 68 D-10 — collapse button. Same toggleBottomPanel store
                action as the View-menu "Toggle Code Preview" item and the
                App.tsx Ctrl+` shortcut. Tooltip surfaces the keyboard
                shortcut so users discover the third entry point. */}
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={toggleBottomPanel}
                  aria-label="Collapse code panel"
                  className="h-7 w-7 p-0"
                >
                  <ChevronDown className="h-4 w-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Collapse (Ctrl+`)</TooltipContent>
            </Tooltip>
            <Button
              size="sm"
              variant="outline"
              disabled={!hasNodes}
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
              disabled={!hasNodes}
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
