import { memo, useCallback } from "react";
import {
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  type EdgeProps,
} from "@xyflow/react";
import useStore from "../store/useStore";
import { bcModeKey, type BCEdgeData } from "../lib/bcMode";

// stripSideSuffix is a private helper in useStore.ts; re-implement the same
// trivial rule here to avoid exporting store-internal helpers.
function stripSideSuffix(name: string): string {
  if (name.endsWith("_left")) return name.slice(0, -"_left".length);
  if (name.endsWith("_right")) return name.slice(0, -"_right".length);
  return name;
}

/**
 * Custom BC edge — Phase 63 / amended Plan 63.1-12.
 *
 * Dashed muted-foreground stroke (D-12, no arrowhead) carrying a mid-edge
 * read-only side tag ("L+R" / "L" / "R"). The tag is DERIVED at render time
 * from the canonical `bcMode` slice — the BCs tab is the single source of
 * truth for BC state. The legacy click-to-cycle interaction (D-11) was
 * removed (2026-05-14): cycling the chip only updated `edge.data.targetSide`
 * without touching `bcMode`, which produced silent state drift between the
 * canvas tag and the BCs tab.
 *
 * Visual idiom is fixed — we do NOT consume the inbound `style` / `markerEnd`
 * EdgeProps (unlike `HydraulicEdge`).
 */
function BCEdge({
  id,
  source,
  target,
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

  // Phase 66 — same code-panel <-> edge bidirectional traceability pattern as
  // HydraulicEdge: light up when BOTH endpoint UUIDs are in the hovered or
  // pinned source-ids set, which happens when a BC-anchor comment sub-block
  // (`# TODO: set channel_1.T_wall_left[i] here`) carrying both consumer +
  // source UUIDs is hovered/pinned in the code panel.
  const isCodeHovered = useStore(
    useCallback(
      (s: { hoveredSourceIds: Set<string> }) =>
        s.hoveredSourceIds.has(source) && s.hoveredSourceIds.has(target),
      [source, target],
    ),
  );
  const isCodePinned = useStore(
    useCallback(
      (s: { pinnedSourceIds: Set<string> }) =>
        s.pinnedSourceIds.has(source) && s.pinnedSourceIds.has(target),
      [source, target],
    ),
  );

  // Read both sibling bcMode entries and check whether each points to this
  // edge's source. The label collapses to "L+R" when both bind, "L" / "R"
  // when only one does. Use a primitive-returning selector to keep zustand's
  // shallow equality stable across re-renders.
  const sideTag = useStore(
    useCallback(
      (
        s: {
          bcMode: Record<string, { mode: string; sourceNodeId?: string }>;
        },
      ): "L+R" | "L" | "R" | "" => {
        if (!edgeData) return "L+R";
        const baseField = stripSideSuffix(edgeData.externalInputName);
        const leftKey = bcModeKey(edgeData.componentId, `${baseField}_left`);
        const rightKey = bcModeKey(edgeData.componentId, `${baseField}_right`);
        const leftEntry = s.bcMode[leftKey];
        const rightEntry = s.bcMode[rightKey];
        const leftMatch =
          leftEntry?.mode === "source" && leftEntry.sourceNodeId === source;
        const rightMatch =
          rightEntry?.mode === "source" && rightEntry.sourceNodeId === source;
        if (leftMatch && rightMatch) return "L+R";
        if (leftMatch) return "L";
        if (rightMatch) return "R";
        return "";
      },
      [edgeData, source],
    ),
  );

  return (
    <>
      <BaseEdge
        id={id}
        path={path}
        // Phase 72 — code-link active state is a CLASS (not inline style)
        // so the marching-ants animation can be reuse the global
        // .code-link-active rule shared with HydraulicEdge, and so
        // prefers-reduced-motion can target it. The class overrides
        // stroke + stroke-dasharray + adds the animation via !important;
        // stroke-width is the only state-dependent inline value (kept
        // very close to rest so the dashed-pattern motion is what reads
        // as "active", not stroke thickness).
        className={
          isCodePinned
            ? "code-link-active code-link-pinned"
            : isCodeHovered
              ? "code-link-active"
              : ""
        }
        style={{
          stroke: "var(--muted-foreground)",
          strokeWidth: 1.5,
          strokeDasharray: "6 3",
        }}
      />
      {sideTag && (
        <EdgeLabelRenderer>
          <span
            className="nopan absolute rounded border bg-background px-[6px] py-[2px] text-label text-muted-foreground"
            style={{
              transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
              pointerEvents: "none",
            }}
          >
            {sideTag}
          </span>
        </EdgeLabelRenderer>
      )}
    </>
  );
}

export default memo(BCEdge);
