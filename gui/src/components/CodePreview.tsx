import { useMemo } from "react";
import { ScrollArea } from "./ui/scroll-area";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode, type BCEntry } from "../lib/codeGenerator";

export default function CodePreview() {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  // Phase 63.1 D-02: subscribe to anchors; synthesize BCEntry[] adapter
  // until Plan 04 retires the legacy generateCode signature.
  const anchors = useStore((s) => s.anchors);
  const resources = useStore((s) => s.resources);
  // Phase 63: BC slices feed into the per-mode codegen emission.
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);

  const code = useMemo(
    () => {
      const bcsAdapter: BCEntry[] = Object.entries(anchors).map(
        ([nodeId, entry]) => ({
          nodeId,
          portField: entry.portField,
          value: entry.value,
        }),
      );
      return generateCode(nodes, edges, bcsAdapter, getComponent, resources, {
        bcMode,
        bcSymmetric,
      });
    },
    [nodes, edges, anchors, resources, bcMode, bcSymmetric],
  );

  return (
    <ScrollArea className="h-full">
      <pre className="font-mono text-[13px] leading-[1.6] whitespace-pre overflow-x-auto p-4 bg-muted text-foreground select-text">
        <code>{code}</code>
      </pre>
    </ScrollArea>
  );
}
