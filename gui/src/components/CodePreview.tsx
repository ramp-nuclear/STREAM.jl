import { useMemo } from "react";
import { ScrollArea } from "./ui/scroll-area";
import useStore from "../store/useStore";
import { getComponent } from "../registry";
import { generateCode } from "../lib/codeGenerator";

export default function CodePreview() {
  const nodes = useStore((s) => s.nodes);
  const edges = useStore((s) => s.edges);
  const bcs = useStore((s) => s.bcs);
  const resources = useStore((s) => s.resources);

  const code = useMemo(
    () => generateCode(nodes, edges, bcs, getComponent, resources),
    [nodes, edges, bcs, resources],
  );

  return (
    <ScrollArea className="h-full">
      <pre className="font-mono text-[13px] leading-[1.6] whitespace-pre overflow-x-auto p-4 bg-muted text-foreground select-text">
        <code>{code}</code>
      </pre>
    </ScrollArea>
  );
}
