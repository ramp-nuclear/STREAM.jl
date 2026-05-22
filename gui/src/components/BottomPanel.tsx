import { useEffect, useState } from "react";
import { Copy, Check, Download } from "lucide-react";
import { Button } from "./ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import useStore from "../store/useStore";
import { useBottomPanelResize } from "../hooks/useBottomPanelResize";
import { getComponent } from "../registry";
import { generateCode, serializeSections } from "../lib/codeGenerator";
import { exportCode } from "../lib/exportCode";
import { validators } from "../lib/validation";
import CodePreview from "./CodePreview";
import ValidationPanel from "./ValidationPanel";

// Phase 71 UAT Test 14 follow-up: structural-vs-diagnostic split. Computed at
// module load (validators array is fixed). Mirror of the same set in exportCode.ts.
const STRUCTURAL_VALIDATOR_IDS = new Set(
  validators.filter((v) => v.structural === true).map((v) => v.id),
);

export default function BottomPanel() {
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const bottomPanelHeight = useStore((s) => s.bottomPanelHeight);
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
  // Phase 71 UAT Test 14 follow-up (2026-05-21): Export-button gate softened
  // to structural errors only. Diagnostic errors still fire the warning toast
  // (with an "Export anyway" override) but no longer disable the button.
  // STRUCTURAL_VALIDATOR_IDS mirrors the structural:true tag in validation/rules/*.
  const structuralErrorCount = useStore(
    (s) =>
      s.validationResults.filter(
        (r) =>
          r.severity === "error" &&
          STRUCTURAL_VALIDATOR_IDS.has(r.validatorId),
      ).length,
  );
  const activeBottomTab = useStore((s) => s.activeBottomTab);

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

  // Phase 72 — closed state renders nothing. The unified ValidationStatusBar
  // (sibling, mounted right below this component in App.tsx) carries the
  // `Code ⌃` toggle affordance, so the prior 14 px stub strip is gone.
  if (!bottomPanelOpen) return null;

  return (
    <div style={{ height: bottomPanelHeight }} className="border-t flex flex-col bg-panel">
      {/* Drag handle — VS Code-style 4px sash: transparent at rest, subtle
          tint on hover. Phase 68 UAT 2026-05-17 polish (was h-2/8px). */}
      <div
        className="h-1 w-full cursor-row-resize hover:bg-ring/30 transition-colors flex-shrink-0"
        onMouseDown={onMouseDown}
      />
      {/* Phase 72: the duplicate Tabs control was removed from this header.
          The ValidationStatusBar at the very bottom is the single source of
          truth for activeBottomTab (Code | Validation). The header now only
          carries the Copy / Export actions, right-aligned. */}
      <div className="mx-2 mt-1 flex items-center justify-end gap-1">
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
        <Tooltip>
          <TooltipTrigger asChild>
            <span
              tabIndex={structuralErrorCount > 0 || !hasNodes ? 0 : -1}
              className="inline-flex"
            >
              <Button
                size="sm"
                variant="outline"
                disabled={!hasNodes || structuralErrorCount > 0}
                onClick={handleExport}
                aria-label="Export generated Julia code to file"
              >
                <Download className="h-4 w-4 mr-1" />
                Export
              </Button>
            </span>
          </TooltipTrigger>
          <TooltipContent>
            {structuralErrorCount > 0
              ? `${structuralErrorCount} structural ${structuralErrorCount === 1 ? "error" : "errors"} — code won't compile`
              : !hasNodes
                ? "No components"
                : "Export Julia code"}
          </TooltipContent>
        </Tooltip>
      </div>
      <div className="flex-1 min-h-0">
        {activeBottomTab === "code" ? <CodePreview /> : <ValidationPanel />}
      </div>
    </div>
  );
}
