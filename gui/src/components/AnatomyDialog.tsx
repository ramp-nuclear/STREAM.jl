// AnatomyDialog — Phase 72 (help-system shape v6, 2026-05-22).
//
// Visual legend for the canvas vocabulary. Node tile uses dashed two-segment
// leaders (horizontal-stub-at-feature + constant-angle diagonal to chip);
// Edges tile uses leader-less numbered chips placed next to each edge.
//
// v6 fixes (after v5 dev-server walkthrough):
//   - NODE MIRROR IS MUCH LARGER (240×96 → 320×140). The smaller node
//     packed all 4 LEFT-side features (anchor + 3 body text rows) into
//     ~80 px of vertical real estate, so leaders converged crowdedly and
//     the diagonals had no room to fan. The larger node spreads body
//     rows to ~30 px apart and lets diagonals reach distinct points.
//   - SCALED-UP NODE TEXT AND PORTS. Band 8→12 px, body p-2→p-3,
//     body label 11→13 px, instance name text-sm→text-base, value
//     summary 11→13 px, icon w-3.5→w-5, port handles 12→16 px, anchor
//     icon w-3→w-4. Everything proportional so the bigger node reads
//     correctly, not as the small node in a stretched frame.
//   - DIAGONAL SLOPE m=2.0 (≈63°). v5 used 1.732 (60°), which left the
//     anchor's horizontal stub only ~7 px wide. m=2.0 keeps the visual
//     "tech diagram" angle while giving every leader's horizontal stub
//     at least 16 px of visible length.
//   - EDGES TILE NO LONGER USES LEADERS. Each edge specimen is already
//     a distinct horizontal stripe, so a numbered chip floating next to
//     its target port is unambiguous. Leader lines on top added noise
//     without information.
//   - Tile size 620×460 → 640×520 to host the larger node + extended
//     diagonals. Both tiles share these dimensions.
//
// Topology (non-crossing proof):
//   Each leader: feature → horizontal stub (outward at fy) → kink at
//   (kinkX, fy) → diagonal up to chip at (chipCenterX, chipY).
//   - All diagonals share the same slope magnitude (m=2.0). Parallel
//     lines cannot cross.
//   - Horizontal stubs each sit at their feature's fy. All horizontals
//     at distinct y → no horizontal-horizontal crossings.
//   - For LEFT side: diagonal i passes y=fy_j (j<i, j above in fy sort)
//     at x = chipCenter + (fy_j - chipY_i)/m, which is < kinkX_j
//     because chipY_j < chipY_i. So diagonal i's pass-through of
//     horizontal j's y happens to the LEFT of horizontal j's start;
//     no crossing. RIGHT mirrors.
//
// Carry-overs from v2/v3/v4/v5:
//   - No modal scrim (overlayClassName="bg-transparent").
//   - Palette surface tone matching CommandPalette / shortcut palette.
//   - Visual mirror of StreamNode (not the real component).
//   - Local marching-ants animation (anatomy-flow-march) for loop trace.

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
// Geometry constants.
// ---------------------------------------------------------------------------

const TILE_W = 640;
const TILE_H = 520;

// Node placement — centered horizontally, sized large enough that all body-
// text features are at least 30 px apart in y.
const NODE_LEFT = 160;
const NODE_TOP = 220;
const NODE_WIDTH = 320;
const NODE_HEIGHT = 140;

// Chip column geometry.
const CHIP_SIZE = 24;
const CHIP_SPACING = 36;
const FIRST_CHIP_Y = 100;
const LEFT_CHIP_X = 60;
const RIGHT_CHIP_X = 556;
const LEFT_CHIP_CENTER_X = LEFT_CHIP_X + CHIP_SIZE / 2;
const RIGHT_CHIP_CENTER_X = RIGHT_CHIP_X + CHIP_SIZE / 2;

// Diagonal slope magnitude — m = 2.0, angle = atan(2.0) ≈ 63° from
// horizontal. Steeper than v5's 60° to keep anchor's horizontal stub
// long enough to read.
const SLOPE = 2.0;

// Leader visuals.
const LEADER_STROKE = "var(--foreground)";
const LEADER_OPACITY = 0.55;
const LEADER_DASH = "4 3";
const LEADER_WIDTH = 1;
const MARKER_SIZE = 7;

// ---------------------------------------------------------------------------
// Callout types.
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

function buildLeaderedCallouts(features: readonly RawFeature[]): {
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
// Top-level dialog.
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
          "w-[1340px] max-w-[95vw] sm:max-w-[1340px]",
          "top-[4vh] translate-y-0",
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
// Leader & marker (shared between node tile and edges tile when needed).
// ---------------------------------------------------------------------------

function Leader({ callout }: { callout: Callout }): React.JSX.Element {
  const chipCenterX =
    callout.side === "L" ? LEFT_CHIP_CENTER_X : RIGHT_CHIP_CENTER_X;
  const sign = callout.side === "L" ? 1 : -1;
  // V5 topology: horizontal stub from feature at fy, then diagonal up to
  // chip. kinkX = chipCenter ± (fy - chipY)/m so the diagonal meets the
  // chip center at the configured slope.
  const kinkX = chipCenterX + (sign * (callout.fy - callout.chipY)) / SLOPE;
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

interface ChipBadgeProps {
  n: number;
  side: "L" | "R";
  y: number;
  /** Override the side-derived x position (used by the edges tile, which
   *  places chips at custom x positions next to edges). */
  xOverride?: number;
}

function ChipBadge({ n, side, y, xOverride }: ChipBadgeProps): React.JSX.Element {
  const left =
    xOverride !== undefined
      ? xOverride - CHIP_SIZE / 2
      : side === "L"
        ? LEFT_CHIP_X
        : RIGHT_CHIP_X;
  return (
    <span
      aria-hidden
      style={{
        position: "absolute",
        left,
        top: y - CHIP_SIZE / 2,
        width: CHIP_SIZE,
        height: CHIP_SIZE,
      }}
      className="inline-flex items-center justify-center rounded-sm font-mono text-label tabular-nums bg-popover text-foreground border border-border z-10"
    >
      {n}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Node features — 4 LEFT + 4 RIGHT. Numbering 1..4 LEFT top→bottom,
// 5..8 RIGHT top→bottom.
// ---------------------------------------------------------------------------

const NODE_FEATURES: readonly RawFeature[] = [
  {
    key: "anchor",
    fx: NODE_LEFT - 18,
    fy: NODE_TOP - 6,
    side: "L",
    legend: "Pressure anchor.",
  },
  {
    key: "label",
    fx: NODE_LEFT + 50,
    fy: NODE_TOP + 36,
    side: "L",
    legend: "Component type.",
  },
  {
    key: "name",
    fx: NODE_LEFT + 50,
    fy: NODE_TOP + 70,
    side: "L",
    legend: "Instance name.",
  },
  {
    key: "value",
    fx: NODE_LEFT + 50,
    fy: NODE_TOP + 100,
    side: "L",
    legend: "Value summary. Source blocks only.",
  },
  {
    key: "topPort",
    fx: NODE_LEFT + NODE_WIDTH / 2,
    fy: NODE_TOP - 6,
    side: "R",
    legend: "Flow port. Blue ports flow in, red ports flow out.",
  },
  {
    key: "band",
    fx: NODE_LEFT + NODE_WIDTH / 2,
    fy: NODE_TOP + 6,
    side: "R",
    legend: "Layer accent band. Split for dual-layer components.",
  },
  {
    key: "ring",
    fx: NODE_LEFT + NODE_WIDTH,
    fy: NODE_TOP + 20,
    side: "R",
    legend: "Selected ring.",
  },
  {
    key: "thermal",
    fx: NODE_LEFT + NODE_WIDTH + 2,
    fy: NODE_TOP + NODE_HEIGHT / 2,
    side: "R",
    legend: "Thermal port. Paired across opposing faces.",
  },
];

const { callouts: NODE_CALLOUTS, legendByN: NODE_LEGEND_BY_N } =
  buildLeaderedCallouts(NODE_FEATURES);

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
          <ChipBadge key={c.n} n={c.n} side={c.side} y={c.chipY} />
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// NodeMirror — scaled-up visual mirror of StreamNode. Larger band, larger
// body padding, larger text and icon, larger port handles.
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
          <div className="flex w-full" style={{ height: 12 }} aria-hidden>
            <div style={{ flex: 1, backgroundColor: "var(--color-layer-hydraulic)" }} />
            <div style={{ flex: 1, backgroundColor: "var(--color-layer-thermal)" }} />
          </div>
          <div className="bg-card p-3">
            <div className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
              <BoxIcon className="w-5 h-5" strokeWidth={1.5} />
              ChannelAndContacts
            </div>
            <div className="font-semibold text-base mt-1">channel_1</div>
            <div className="text-[13px] text-muted-foreground mt-1">
              L = 1.2 m  Dh = 12 mm
            </div>
          </div>
        </div>
        <Anchor
          aria-hidden
          className="w-4 h-4 text-foreground"
          style={{ position: "absolute", left: -22, top: -10 }}
        />
        {/* FlowPort in (top). */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            top: -8,
            left: "50%",
            transform: "translateX(-50%)",
            width: 16,
            height: 16,
            background: "#60a5fa",
            border: "1.5px solid #1d4ed8",
            borderRadius: "50%",
          }}
        />
        {/* FlowPort out (bottom). */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            bottom: -8,
            left: "50%",
            transform: "translateX(-50%)",
            width: 16,
            height: 16,
            background: "#f87171",
            border: "1.5px solid #b91c1c",
            borderRadius: "50%",
          }}
        />
        {/* ThermalPort (left). */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: -10,
            top: "50%",
            transform: "translateY(-50%) rotate(45deg)",
            width: 16,
            height: 16,
            background: "var(--color-layer-thermal)",
            border:
              "1.5px solid color-mix(in oklch, var(--color-layer-thermal) 75%, black)",
          }}
        />
        {/* ThermalPort (right). */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            right: -10,
            top: "50%",
            transform: "translateY(-50%) rotate(45deg)",
            width: 16,
            height: 16,
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
  return (
    <div className="px-6 pb-5 pt-3 grid grid-cols-2 gap-x-6 gap-y-2">
      <LegendColumn entries={entries.slice(0, half)} />
      <LegendColumn entries={entries.slice(half)} />
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
// Edges tile — NO LEADER LINES. Each edge specimen gets a numbered chip
// placed directly to the right of its target port. The legend below maps
// number → description.
// ---------------------------------------------------------------------------

const EDGE_SRC_X = 220;
const EDGE_TGT_X = 500;
const ROW_Y = [140, 240, 340];
const CONV_ROW_Y = 450;
const CONV_SRC_LEFT = 220;
const CONV_TGT_LEFT = 430;
const CONV_NODE_W = 70;
const CONV_NODE_H = 36;
const EDGES_CHIP_X = 540; // right of target ports

interface EdgeChip {
  n: number;
  y: number;
  x: number;
  legend: string;
}

const EDGE_CHIPS: readonly EdgeChip[] = [
  {
    n: 1,
    y: ROW_Y[0],
    x: EDGES_CHIP_X,
    legend: "Hydraulic edge.",
  },
  {
    n: 2,
    y: ROW_Y[1],
    x: EDGES_CHIP_X,
    legend:
      "Boundary-condition edge. Dashed. Side tag (L, R, L+R) marks which sides of the consumer it drives.",
  },
  {
    n: 3,
    y: ROW_Y[2],
    x: EDGES_CHIP_X,
    legend:
      "Validation loop trace. Marching ants. Tinted by severity (red, amber, blue).",
  },
  {
    n: 4,
    y: CONV_ROW_Y,
    x: EDGES_CHIP_X,
    legend:
      "Port-side convention. Flow enters from the top or left, exits from the bottom or right.",
  },
];

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
                left: EDGE_SRC_X - 8,
                top: y - 8,
                width: 16,
                height: 16,
                background: "#60a5fa",
                border: "1.5px solid #1d4ed8",
                borderRadius: "50%",
              }}
            />
            <span
              aria-hidden
              style={{
                position: "absolute",
                left: EDGE_TGT_X - 8,
                top: y - 8,
                width: 16,
                height: 16,
                background: "#f87171",
                border: "1.5px solid #b91c1c",
                borderRadius: "50%",
              }}
            />
          </React.Fragment>
        ))}

        {/* BC mid-edge side tag. */}
        <span
          className="absolute rounded border bg-background px-[6px] py-[2px] text-[11px] text-muted-foreground font-mono pointer-events-none"
          style={{
            left: (EDGE_SRC_X + EDGE_TGT_X) / 2 - 18,
            top: ROW_Y[1] - 12,
          }}
        >
          L+R
        </span>

        {/* Convention port dots. */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: CONV_SRC_LEFT - 8,
            top: CONV_ROW_Y - 8,
            width: 16,
            height: 16,
            background: "#60a5fa",
            border: "1.5px solid #1d4ed8",
            borderRadius: "50%",
          }}
        />
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: CONV_TGT_LEFT + CONV_NODE_W - 8,
            top: CONV_ROW_Y - 8,
            width: 16,
            height: 16,
            background: "#f87171",
            border: "1.5px solid #b91c1c",
            borderRadius: "50%",
          }}
        />

        {/* Numbered chips placed directly next to each edge. No leaders. */}
        {EDGE_CHIPS.map((c) => (
          <ChipBadge
            key={c.n}
            n={c.n}
            side="R"
            y={c.y}
            xOverride={c.x}
          />
        ))}
      </div>
    </div>
  );
}

function EdgesLegend(): React.JSX.Element {
  const entries = EDGE_CHIPS.map((c) => [c.n, c.legend] as [number, string]);
  return (
    <div className="px-6 pb-5 pt-3">
      <LegendColumn entries={entries} />
    </div>
  );
}
