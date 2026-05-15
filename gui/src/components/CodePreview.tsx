import { useMemo } from "react";
import { ScrollArea } from "./ui/scroll-area";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode, serializeSections } from "../lib/codeGenerator";

export default function CodePreview() {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  // Phase 63.1 Plan 04: anchors slice is passed directly to generateCode as
  // `{ anchors }` (Record-shape signature; no BCEntry[] adapter).
  const anchors = useStore((s) => s.anchors);
  const resources = useStore((s) => s.resources);
  // Phase 63: BC slices feed into the per-mode codegen emission.
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);

  // TEMP — Phase 66 Plan 04 takes over this consumer.
  // Plan 02 changed generateCode's return to CodeSection[]; we wrap with
  // serializeSections so the existing <pre><code> string render path keeps
  // working (modulo the D-12 `# === <Section> ===` section headers).
  // Plan 04 replaces this useMemo + <pre> with a section-by-section sub-block
  // renderer that wires up hover/click/show-code-for traceability.
  const code = useMemo(
    () =>
      serializeSections(
        generateCode(nodes, edges, { anchors }, getComponent, resources, {
          bcMode,
          bcSymmetric,
        }),
      ),
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
