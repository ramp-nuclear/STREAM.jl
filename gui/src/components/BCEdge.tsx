import { memo } from "react";
import {
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  type EdgeProps,
} from "@xyflow/react";
import useStore from "../store/useStore";
import type { BCEdgeData } from "../lib/bcMode";

/**
 * Custom BC edge — Phase 63.
 *
 * Dashed muted-foreground stroke (D-12, no arrowhead) carrying a mid-edge
 * inline chip ("L+R" / "L" / "R") that cycles `targetSide` on click via the
 * store action `cycleBCEdgeTargetSide` (D-11).
 *
 * Visual idiom is fixed — we do NOT consume the inbound `style` / `markerEnd`
 * EdgeProps (unlike `HydraulicEdge`), because the BC visual style must remain
 * uniform across all BC edges regardless of any enrichEdges styling.
 */
function BCEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
}: EdgeProps) {
  const [path, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
  });

  const edgeData = data as BCEdgeData | undefined;
  const targetSide = edgeData?.targetSide ?? "both";
  const chipLabel =
    targetSide === "both" ? "L+R" : targetSide === "left" ? "L" : "R";

  const cycle = useStore((state) => state.cycleBCEdgeTargetSide);

  return (
    <>
      <BaseEdge
        id={id}
        path={path}
        style={{
          stroke: "var(--muted-foreground)",
          strokeWidth: 1.5,
          strokeDasharray: "6 3",
        }}
      />
      <EdgeLabelRenderer>
        <div
          className="nopan absolute"
          style={{
            transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
            pointerEvents: "all",
          }}
        >
          <button
            type="button"
            onClick={() => cycle(id)}
            className="rounded border bg-background px-[6px] py-[2px] text-xs text-muted-foreground hover:bg-accent"
          >
            {chipLabel}
          </button>
        </div>
      </EdgeLabelRenderer>
    </>
  );
}

export default memo(BCEdge);
