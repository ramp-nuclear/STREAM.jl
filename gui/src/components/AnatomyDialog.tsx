// AnatomyDialog — Phase 72 (help-system shape v5, 2026-05-22).
//
// Visual legend for the canvas vocabulary. Renders a visual mirror of
// StreamNode plus three edge specimens + a port-side convention schematic.
// Numbered callouts use two-segment leaders: a horizontal stub from the
// feature, then a constant-angle diagonal up to a chip column.
//
// v5 layout (after v4 dev-server walkthrough):
//   - Numbers stacked compactly at the TOP corners of each tile (chips 1-4
//     on LEFT, 5-8 on RIGHT for the node tile; 1-2 / 3-4 for edges).
//     Consecutive chips are evenly spaced 32 px apart and close together.
//   - Every leader is two segments: a HORIZONTAL stub from the feature
//     outward (LEFT for LEFT chips, RIGHT for RIGHT chips), then a
//     CONSTANT-ANGLE diagonal (60° from horizontal, m = tan(60°) = 1.732)
//     up to the chip center.
//   - Because all diagonals share the same slope magnitude, they are
//     PARALLEL. Two parallel lines cannot cross. The horizontal stubs are
//     each at a different y (the feature's y), so they cannot cross each
//     other. And a horizontal at y=fy_j is reached by diagonal i only
//     at an x to the LEFT of horizontal j's start (because j's stub
//     extends further from chipX than i's diagonal hits y=fy_j when j's
//     chip is below i's chip). This is a proof-by-monotonic-sort that
//     no leaders cross.
//
// v2/v3/v4 carry-overs:
//   - No modal scrim (overlayClassName="bg-transparent").
//   - Palette surface tone matching CommandPalette / shortcut palette.
//   - Visual mirror of StreamNode (not the real component).
//   - Local marching-ants animation (anatomy-flow-march).

import * as React from "react";
import { Anchor, Box as BoxIcon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import { cn } from "@/lib/utils";

interface AnatomyDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const PALETTE_SURFACE = cn(
  "bg-[oklch(0.93_0.012_254)] dark:bg-[oklch(0.13_0.012_254)]",
  "border-[oklch(0.86_0.012_254)] dark:border-[oklch(0.24_0.012_254)]",
  "shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.18),0_4px_12px_-4px_oklch(0.05_0_0/0.12)]",
  "dark:shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.55),0_4px_12px_-4px_oklch(0.05_0_0/0.40)]",
);

// ---------------------------------------------------------------------------
// Tile geometry (shared by both tiles).
// ---------------------------------------------------------------------------

const TILE_W = 620;
const TILE_H = 460;

// Node placement (centered horizontally in the tile).
const NODE_LEFT = 190;
const NODE_TOP = 220;
const NODE_WIDTH = 240;
const NODE_HEIGHT = 96;

// Chip column geometry. Chips sit at the top-LEFT and top-RIGHT of the
// tile in compact stacks. LEFT_CHIP_X / RIGHT_CHIP_X are the chip's left
// edges in tile coords; the LEFT/RIGHT centers are where diagonal leaders
// terminate. Symmetric around the tile midline.
const CHIP_SIZE = 22;
const CHIP_SPACING = 32;
const FIRST_CHIP_Y = 80;
const LEFT_CHIP_X = 60;
const RIGHT_CHIP_X = 538;
const LEFT_CHIP_CENTER_X = LEFT_CHIP_X + CHIP_SIZE / 2;
const RIGHT_CHIP_CENTER_X = RIGHT_CHIP_X + CHIP_SIZE / 2;

// Constant diagonal slope magnitude. m = tan(60°) ≈ 1.732 gives every
// leader's diagonal segment the same 60° pitch.
const SLOPE = Math.tan((60 * Math.PI) / 180);

const LEADER_STROKE = "var(--foreground)";
const LEADER_OPACITY = 0.55;
const LEADER_DASH = "4 3";
const LEADER_WIDTH = 1;
const MARKER_SIZE = 6;

// ---------------------------------------------------------------------------
// Callout — final form ready to render. Built by buildCallouts() from the
// per-tile RawFeature lists.
// ---------------------------------------------------------------------------

interface Callout {
  n: number;
  side: "L" | "R";
  fx: number;
  fy: number;
  chipY: number;
}

interface RawFeature {
  key: string;
  fx: number;
  fy: number;
  side: "L" | "R";
  legend: string;
}

/**
 * Sort each side by feature y, then assign chip slots top-to-bottom in
 * sort order. LEFT chips get numbers 1..N_L; RIGHT chips get N_L+1..N_L+N_R.
 * Matches the user's "1,2,3,4 / 5,6,7,8" layout (LEFT first, RIGHT after).
 */
function buildCallouts(features: readonly RawFeature[]): {
  callouts: Callout[];
  legendByN: Map<number, string>;
} {
  const leftSorted = features
    .filter((f) => f.side === "L")
    .sort((a, b) => a.fy - b.fy);
  const rightSorted = features
    .filter((f) => f.side === "R")
    .sort((a, b) => a.fy - b.fy);

  const callouts: Callout[] = [];
  const legendByN = new Map<number, string>();

  leftSorted.forEach((f, i) => {
    const n = i + 1;
    callouts.push({
      n,
      side: "L",
      fx: f.fx,
      fy: f.fy,
      chipY: FIRST_CHIP_Y + i * CHIP_SPACING,
    });
    legendByN.set(n, f.legend);
  });

  rightSorted.forEach((f, i) => {
    const n = leftSorted.length + i + 1;
    callouts.push({
      n,
      side: "R",
      fx: f.fx,
      fy: f.fy,
      chipY: FIRST_CHIP_Y + i * CHIP_SPACING,
    });
    legendByN.set(n, f.legend);
  });

  callouts.sort((a, b) => a.n - b.n);
  return { callouts, legendByN };
}

// ---------------------------------------------------------------------------
// Top-level component.
// ---------------------------------------------------------------------------

export default function AnatomyDialog({
  open,
  onOpenChange,
}: AnatomyDialogProps): React.JSX.Element {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        overlayClassName="bg-transparent"
        className={cn(
          "p-0 gap-0 overflow-hidden rounded-md",
          "w-[1300px] max-w-[95vw] sm:max-w-[1300px]",
          "top-[6vh] translate-y-0",
          PALETTE_SURFACE,
        )}
        data-testid="anatomy-dialog"
      >
        <DialogHeader className="px-6 pt-5 pb-3 border-b border-border/40">
          <DialogTitle className="text-title font-normal tracking-tight">
            Anatomy
          </DialogTitle>
          <DialogDescription className="sr-only">
            Visual legend for canvas components and their states.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-2 divide-x divide-border/40">
          <Section title="Node">
            <NodeTile />
            <NodeLegend />
          </Section>
          <Section title="Edges">
            <EdgesTile />
            <EdgesLegend />
          </Section>
        </div>

        <div className="border-t border-border/40 px-6 py-3 text-label text-foreground/65 font-mono leading-relaxed">
          Outline states (blue selected ring, red persistent error, violet
          auto-add preview) are mutually exclusive on a real node. The
          auto-add preview outline appears only while Save Preset is open,
          marking BC-coupled neighbors that would be pulled into the saved
          preset.
        </div>
      </DialogContent>
    </Dialog>
  );
}

interface SectionProps {
  title: string;
  children: React.ReactNode;
}

function Section({ title, children }: SectionProps): React.JSX.Element {
  return (
    <div className="flex flex-col">
      <div className="px-6 pt-5 pb-2 text-micro font-mono uppercase tracking-wider text-foreground/55">
        {title}
      </div>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Leader — two-segment path: horizontal stub from feature outward, then a
// constant-angle diagonal up to the chip center.
// ---------------------------------------------------------------------------

function Leader({ callout }: { callout: Callout }): React.JSX.Element {
  const chipCenterX =
    callout.side === "L" ? LEFT_CHIP_CENTER_X : RIGHT_CHIP_CENTER_X;
  // Diagonal slope: positive for LEFT (going up-LEFT from feature),
  // negative for RIGHT (going up-RIGHT). Magnitude SLOPE for both. The
  // horizontal segment extends from feature toward the chip by exactly
  // enough that the diagonal at 60° hits the chip's center y.
  const dy = callout.fy - callout.chipY; // positive when chip is above feature
  const dxKinkFromChip = dy / SLOPE; // horizontal distance from chip to kink
  const sign = callout.side === "L" ? 1 : -1;
  const kinkX = chipCenterX + sign * dxKinkFromChip;
  const d = `M${callout.fx},${callout.fy} L${kinkX},${callout.fy} L${chipCenterX},${callout.chipY}`;
  return (
    <path
      d={d}
      stroke={LEADER_STROKE}
      strokeOpacity={LEADER_OPACITY}
      strokeWidth={LEADER_WIDTH}
      strokeDasharray={LEADER_DASH}
      fill="none"
    />
  );
}

function FeatureMarker({
  fx,
  fy,
}: {
  fx: number;
  fy: number;
}): React.JSX.Element {
  return (
    <rect
      x={fx - MARKER_SIZE / 2}
      y={fy - MARKER_SIZE / 2}
      width={MARKER_SIZE}
      height={MARKER_SIZE}
      fill="var(--foreground)"
    />
  );
}

function ChipBadge({ callout }: { callout: Callout }): React.JSX.Element {
  const left = callout.side === "L" ? LEFT_CHIP_X : RIGHT_CHIP_X;
  return (
    <span
      aria-hidden
      style={{
        position: "absolute",
        left,
        top: callout.chipY - CHIP_SIZE / 2,
        width: CHIP_SIZE,
        height: CHIP_SIZE,
      }}
      className="inline-flex items-center justify-center rounded-sm font-mono text-label tabular-nums bg-popover text-foreground border border-border z-10"
    >
      {callout.n}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Node features (4 LEFT + 4 RIGHT = 8 callouts).
// ---------------------------------------------------------------------------

const NODE_FEATURES: readonly RawFeature[] = [
  {
    key: "anchor",
    fx: NODE_LEFT - 14,
    fy: NODE_TOP - 4,
    side: "L",
    legend: "Pressure anchor.",
  },
  {
    key: "label",
    fx: NODE_LEFT + 38,
    fy: NODE_TOP + 24,
    side: "L",
    legend: "Component type.",
  },
  {
    key: "name",
    fx: NODE_LEFT + 38,
    fy: NODE_TOP + 44,
    side: "L",
    legend: "Instance name.",
  },
  {
    key: "value",
    fx: NODE_LEFT + 38,
    fy: NODE_TOP + 64,
    side: "L",
    legend: "Value summary. Source blocks only.",
  },
  {
    key: "topPort",
    fx: NODE_LEFT + NODE_WIDTH / 2,
    fy: NODE_TOP - 4,
    side: "R",
    legend: "Flow port. Blue ports flow in, red ports flow out.",
  },
  {
    key: "band",
    fx: NODE_LEFT + NODE_WIDTH / 2,
    fy: NODE_TOP + 4,
    side: "R",
    legend: "Layer accent band. Split for dual-layer components.",
  },
  {
    key: "thermal",
    fx: NODE_LEFT + NODE_WIDTH + 2,
    fy: NODE_TOP + NODE_HEIGHT / 2,
    side: "R",
    legend: "Thermal port. Paired across opposing faces.",
  },
  {
    key: "error",
    fx: NODE_LEFT + NODE_WIDTH,
    fy: NODE_TOP + NODE_HEIGHT,
    side: "R",
    legend: "Persistent validation error outline.",
  },
];

const { callouts: NODE_CALLOUTS, legendByN: NODE_LEGEND_BY_N } =
  buildCallouts(NODE_FEATURES);

function NodeTile(): React.JSX.Element {
  return (
    <div className="px-6 pb-2">
      <div
        className="relative rounded-sm border border-border/40 overflow-hidden"
        style={{
          width: TILE_W,
          height: TILE_H,
          backgroundColor: "var(--canvas)",
          backgroundImage:
            "linear-gradient(to right, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
            "linear-gradient(to bottom, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
            "linear-gradient(to right, var(--color-canvas-grid-major) 1px, transparent 1px), " +
            "linear-gradient(to bottom, var(--color-canvas-grid-major) 1px, transparent 1px)",
          backgroundSize: "12px 12px, 12px 12px, 24px 24px, 24px 24px",
        }}
      >
        <NodeMirror left={NODE_LEFT} top={NODE_TOP} width={NODE_WIDTH} />

        <svg
          width={TILE_W}
          height={TILE_H}
          viewBox={`0 0 ${TILE_W} ${TILE_H}`}
          className="absolute inset-0 pointer-events-none"
          aria-hidden
        >
          {NODE_CALLOUTS.map((c) => (
            <Leader key={c.n} callout={c} />
          ))}
          {NODE_CALLOUTS.map((c) => (
            <FeatureMarker key={c.n} fx={c.fx} fy={c.fy} />
          ))}
        </svg>

        {NODE_CALLOUTS.map((c) => (
          <ChipBadge key={c.n} callout={c} />
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// NodeMirror — visual copy of StreamNode (see v4 for fidelity rationale).
// ---------------------------------------------------------------------------

interface NodeMirrorProps {
  left: number;
  top: number;
  width: number;
}

function NodeMirror({ left, top, width }: NodeMirrorProps): React.JSX.Element {
  return (
    <div className="absolute" style={{ left, top, width }}>
      <div
        className="relative rounded-md"
        style={{
          boxShadow:
            "0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)",
          outline: "2px solid var(--destructive)",
          outlineOffset: "0",
        }}
      >
        <div className="rounded-md overflow-hidden">
          <div className="flex w-full" style={{ height: 8 }} aria-hidden>
            <div style={{ flex: 1, backgroundColor: "var(--color-layer-hydraulic)" }} />
            <div style={{ flex: 1, backgroundColor: "var(--color-layer-thermal)" }} />
          </div>
          <div className="bg-card p-2">
            <div className="flex items-center gap-1 text-[11px] text-muted-foreground">
              <BoxIcon className="w-3.5 h-3.5" strokeWidth={1.5} />
              ChannelAndContacts
            </div>
            <div className="font-semibold text-sm">channel_1</div>
            <div className="text-[11px] text-muted-foreground">
              L = 1.2 m  Dh = 12 mm
            </div>
          </div>
        </div>
        <Anchor
          aria-hidden
          className="w-3 h-3 text-foreground"
          style={{ position: "absolute", left: -18, top: -8 }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            top: -7,
            left: "50%",
            transform: "translateX(-50%)",
            width: 12,
            height: 12,
            background: "#60a5fa",
            border: "1.5px solid #1d4ed8",
            borderRadius: "50%",
          }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            bottom: -7,
            left: "50%",
            transform: "translateX(-50%)",
            width: 12,
            height: 12,
            background: "#f87171",
            border: "1.5px solid #b91c1c",
            borderRadius: "50%",
          }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: -8,
            top: "50%",
            transform: "translateY(-50%) rotate(45deg)",
            width: 12,
            height: 12,
            background: "var(--color-layer-thermal)",
            border:
              "1.5px solid color-mix(in oklch, var(--color-layer-thermal) 75%, black)",
          }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            right: -8,
            top: "50%",
            transform: "translateY(-50%) rotate(45deg)",
            width: 12,
            height: 12,
            background: "var(--color-layer-thermal)",
            border:
              "1.5px solid color-mix(in oklch, var(--color-layer-thermal) 75%, black)",
          }}
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Legends.
// ---------------------------------------------------------------------------

function NodeLegend(): React.JSX.Element {
  const entries = Array.from(NODE_LEGEND_BY_N.entries()).sort(
    (a, b) => a[0] - b[0],
  );
  const half = Math.ceil(entries.length / 2);
  const left = entries.slice(0, half);
  const right = entries.slice(half);
  return (
    <div className="px-6 pb-5 pt-3 grid grid-cols-2 gap-x-6 gap-y-2">
      <LegendColumn entries={left} />
      <LegendColumn entries={right} />
    </div>
  );
}

function LegendColumn({
  entries,
}: {
  entries: ReadonlyArray<[number, string]>;
}): React.JSX.Element {
  return (
    <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-2 text-body items-baseline">
      {entries.map(([n, text]) => (
        <React.Fragment key={n}>
          <span className="font-mono text-foreground/85 tabular-nums">{n}</span>
          <span className="text-foreground/85 leading-snug">{text}</span>
        </React.Fragment>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Edges tile.
// ---------------------------------------------------------------------------

const EDGE_SRC_X = 200;
const EDGE_TGT_X = 460;
const ROW_Y = [120, 200, 280];
const CONV_ROW_Y = 380;
const CONV_SRC_LEFT = 200;
const CONV_TGT_LEFT = 410;
const CONV_NODE_W = 50;
const CONV_NODE_H = 28;

const EDGES_FEATURES: readonly RawFeature[] = [
  {
    key: "hydraulic",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[0],
    side: "L",
    legend: "Hydraulic edge.",
  },
  {
    key: "loopTrace",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[2],
    side: "L",
    legend:
      "Validation loop trace. Marching ants. Tinted by severity (red, amber, blue).",
  },
  {
    key: "bc",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[1],
    side: "R",
    legend:
      "Boundary-condition edge. Dashed. Side tag (L, R, L+R) marks which sides of the consumer it drives.",
  },
  {
    key: "convention",
    fx: (CONV_SRC_LEFT + CONV_NODE_W + CONV_TGT_LEFT) / 2,
    fy: CONV_ROW_Y,
    side: "R",
    legend:
      "Port-side convention. Flow enters from the top or left, exits from the bottom or right.",
  },
];

const { callouts: EDGES_CALLOUTS, legendByN: EDGES_LEGEND_BY_N } =
  buildCallouts(EDGES_FEATURES);

function EdgesTile(): React.JSX.Element {
  return (
    <div className="px-6 pb-2">
      <div
        className="relative rounded-sm border border-border/40 overflow-hidden"
        style={{
          width: TILE_W,
          height: TILE_H,
          backgroundColor: "var(--canvas)",
          backgroundImage:
            "linear-gradient(to right, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
            "linear-gradient(to bottom, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
            "linear-gradient(to right, var(--color-canvas-grid-major) 1px, transparent 1px), " +
            "linear-gradient(to bottom, var(--color-canvas-grid-major) 1px, transparent 1px)",
          backgroundSize: "12px 12px, 12px 12px, 24px 24px, 24px 24px",
        }}
      >
        <svg
          width={TILE_W}
          height={TILE_H}
          viewBox={`0 0 ${TILE_W} ${TILE_H}`}
          className="absolute inset-0"
          aria-hidden
        >
          {/* Row 1 — hydraulic default. */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[0]} L${EDGE_TGT_X - 10},${ROW_Y[0]}`}
            stroke="var(--foreground)"
            strokeOpacity={0.7}
            strokeWidth={1.5}
            fill="none"
            strokeLinecap="round"
          />
          {/* Row 2 — BC dashed. */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[1]} L${EDGE_TGT_X - 10},${ROW_Y[1]}`}
            stroke="var(--muted-foreground)"
            strokeWidth={1.5}
            strokeDasharray="6 3"
            fill="none"
            strokeLinecap="round"
          />
          {/* Row 3 — marching-ants loop trace. */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[2]} L${EDGE_TGT_X - 10},${ROW_Y[2]}`}
            stroke="var(--color-warning)"
            strokeWidth={2.5}
            strokeDasharray="6 4"
            fill="none"
            strokeLinecap="round"
            className="anatomy-flow-march"
          />

          {/* Port-side convention schematic. */}
          <rect
            x={CONV_SRC_LEFT}
            y={CONV_ROW_Y - CONV_NODE_H / 2}
            width={CONV_NODE_W}
            height={CONV_NODE_H}
            rx={3}
            stroke="var(--foreground)"
            strokeOpacity={0.6}
            strokeWidth={1}
            fill="var(--card)"
          />
          <rect
            x={CONV_TGT_LEFT}
            y={CONV_ROW_Y - CONV_NODE_H / 2}
            width={CONV_NODE_W}
            height={CONV_NODE_H}
            rx={3}
            stroke="var(--foreground)"
            strokeOpacity={0.6}
            strokeWidth={1}
            fill="var(--card)"
          />
          <path
            d={`M${CONV_SRC_LEFT + CONV_NODE_W},${CONV_ROW_Y} L${CONV_TGT_LEFT},${CONV_ROW_Y}`}
            stroke="var(--foreground)"
            strokeOpacity={0.7}
            strokeWidth={1.5}
            fill="none"
            strokeLinecap="round"
          />

          {EDGES_CALLOUTS.map((c) => (
            <Leader key={c.n} callout={c} />
          ))}
          {EDGES_CALLOUTS.map((c) => (
            <FeatureMarker key={c.n} fx={c.fx} fy={c.fy} />
          ))}

          <style>
            {`
            .anatomy-flow-march {
              animation: anatomy-flow-march 1.5s linear infinite;
            }
            @keyframes anatomy-flow-march {
              to { stroke-dashoffset: -10; }
            }
            @media (prefers-reduced-motion: reduce) {
              .anatomy-flow-march { animation: none; }
            }
            `}
          </style>
        </svg>

        {/* Edge endpoint ports. */}
        {ROW_Y.map((y, i) => (
          <React.Fragment key={i}>
            <span
              aria-hidden
              style={{
                position: "absolute",
                left: EDGE_SRC_X - 6,
                top: y - 6,
                width: 12,
                height: 12,
                background: "#60a5fa",
                border: "1.5px solid #1d4ed8",
                borderRadius: "50%",
              }}
            />
            <span
              aria-hidden
              style={{
                position: "absolute",
                left: EDGE_TGT_X - 6,
                top: y - 6,
                width: 12,
                height: 12,
                background: "#f87171",
                border: "1.5px solid #b91c1c",
                borderRadius: "50%",
              }}
            />
          </React.Fragment>
        ))}

        <span
          className="absolute rounded border bg-background px-[6px] py-[2px] text-[11px] text-muted-foreground font-mono pointer-events-none"
          style={{
            left: (EDGE_SRC_X + EDGE_TGT_X) / 2 - 18,
            top: ROW_Y[1] - 12,
          }}
        >
          L+R
        </span>

        <span
          aria-hidden
          style={{
            position: "absolute",
            left: CONV_SRC_LEFT - 6,
            top: CONV_ROW_Y - 6,
            width: 12,
            height: 12,
            background: "#60a5fa",
            border: "1.5px solid #1d4ed8",
            borderRadius: "50%",
          }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: CONV_TGT_LEFT + CONV_NODE_W - 6,
            top: CONV_ROW_Y - 6,
            width: 12,
            height: 12,
            background: "#f87171",
            border: "1.5px solid #b91c1c",
            borderRadius: "50%",
          }}
        />

        {EDGES_CALLOUTS.map((c) => (
          <ChipBadge key={c.n} callout={c} />
        ))}
      </div>
    </div>
  );
}

function EdgesLegend(): React.JSX.Element {
  const entries = Array.from(EDGES_LEGEND_BY_N.entries()).sort(
    (a, b) => a[0] - b[0],
  );
  return (
    <div className="px-6 pb-5 pt-3">
      <LegendColumn entries={entries} />
    </div>
  );
}
