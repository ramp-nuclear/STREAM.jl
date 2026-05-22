// AnatomyDialog — Phase 72 (help-system shape v3, 2026-05-22).
//
// A schematic-style visual legend for the canvas vocabulary. Renders a
// visual mirror of StreamNode plus four edge specimens with numbered
// callouts connected by dashed *diagonal* leader lines (technical-drawing
// convention, vertebra-anatomy-diagram lineage).
//
// v3 redesign (after user walkthrough of v2):
//   - Leader lines are SINGLE-SEGMENT DIAGONALS at varying angles, not
//     orthogonal Z-bends. Matches the inspiration the user named (medical
//     anatomy diagram with fanned-out angled leaders).
//   - Two number columns per tile (LEFT + RIGHT) instead of single-column.
//     With scattered source points, a single-column fan is geometrically
//     forced to cross some pairs of leaders; two columns split the load.
//   - Within each column, features are sorted top-to-bottom by feature y
//     and assigned slots top-to-bottom by chip y, which guarantees no
//     crossing within that column (sorted bipartite matching property).
//   - Every feature gets a small filled-square MARKER (~5×5 px) at its
//     anchor point so the leader's destination is unambiguous.
//   - Chips slightly larger (20×20 px) for better legibility.
//   - Numbering goes 1..9 top-to-bottom in spatial order across both
//     columns combined, so the diagram reads naturally as the eye scans
//     the node from top to bottom.
//   - Legend stays below the tile (per user direction; labels do NOT
//     ride alongside the chips in the diagram).
//
// v2 carry-overs unchanged:
//   - No modal scrim (overlayClassName="bg-transparent").
//   - Palette surface tone matching CommandPalette / shortcut palette.
//   - Visual mirror of StreamNode (not the real component — see file
//     header on v1/v2 for the fidelity rationale).
//   - Local marching-ants animation (anatomy-flow-march) for the loop
//     trace specimen, scoped to this file so it doesn't depend on the
//     xyflow-global `.validation-flow-trace` selector.

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

// Leader line shared style. Single dashed segment from feature marker to
// chip; varies in angle per callout. shapeRendering="auto" lets diagonals
// antialias smoothly.
const LEADER_STROKE = "var(--foreground)";
const LEADER_OPACITY = 0.5;
const LEADER_DASH = "4 3";
const LEADER_WIDTH = 1;
const MARKER_SIZE = 5; // filled square at feature anchor

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
          Outline states (selected ring, persistent error, auto-add preview)
          are mutually exclusive on a real node. The auto-add preview outline
          appears only while Save Preset is open, marking BC-coupled
          neighbors that would be pulled into the saved preset.
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Section — tile + legend column wrapper.
// ---------------------------------------------------------------------------

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
// Callout — one numbered marker. `n` is the display number; (fx, fy) is the
// feature anchor in tile coords; `side` picks the chip column; `chipY` is
// the chip's y-position in tile coords (caller computes from sorted slot).
// ---------------------------------------------------------------------------

interface Callout {
  n: number;
  side: "L" | "R";
  fx: number;
  fy: number;
  chipY: number;
}

const CHIP_SIZE = 20;
const LEFT_CHIP_X = 24;
const RIGHT_CHIP_X_NODE = 596;
const RIGHT_CHIP_X_EDGES = 596;

// Inner edge of each chip — the point where the leader line attaches.
function chipAttachmentPoint(c: Callout, tileSide: "node" | "edges"): {
  x: number;
  y: number;
} {
  const rightChipX = tileSide === "node" ? RIGHT_CHIP_X_NODE : RIGHT_CHIP_X_EDGES;
  if (c.side === "L") {
    return { x: LEFT_CHIP_X + CHIP_SIZE, y: c.chipY };
  }
  return { x: rightChipX, y: c.chipY };
}

// ---------------------------------------------------------------------------
// NodeTile — hero node with two-column callout fan.
//
// Layout:
//   tile 620 × 480
//   node body 240 × 96 positioned at (130, 220) — spans y=220..316
//   LEFT  chip column at x=24 (chip occupies x=24..44)
//   RIGHT chip column at x=596 (chip occupies x=596..616)
//
// Feature positions (anchors for leader lines) and their column assignments
// follow the natural "left or right side of the node" partition.
// ---------------------------------------------------------------------------

const NODE_TILE_W = 620;
const NODE_TILE_H = 480;
const NODE_LEFT = 130;
const NODE_TOP = 220;
const NODE_WIDTH = 240;
const NODE_HEIGHT = 96;

// Raw feature anchor positions on the rendered node. Computed from the
// NodeMirror layout (see NodeMirror() below). Each is annotated with which
// chip column hosts its callout. The number assignment (1..9) is then
// computed by sorting all features by fy ascending (so the diagram reads
// top-to-bottom).
interface RawFeature {
  key: string;
  fx: number;
  fy: number;
  side: "L" | "R";
  legend: string;
}

const NODE_FEATURES: readonly RawFeature[] = [
  { key: "anchor",  fx: NODE_LEFT - 14,                 fy: NODE_TOP - 4,           side: "L", legend: "Pressure anchor." },
  { key: "topPort", fx: NODE_LEFT + NODE_WIDTH / 2,     fy: NODE_TOP - 4,           side: "R", legend: "Flow port. Blue ports flow in, red ports flow out." },
  { key: "band",    fx: NODE_LEFT + NODE_WIDTH / 2,     fy: NODE_TOP + 4,           side: "R", legend: "Layer accent band. Split for dual-layer components." },
  { key: "label",   fx: NODE_LEFT + 38,                 fy: NODE_TOP + 24,          side: "L", legend: "Component type." },
  { key: "ring",    fx: NODE_LEFT + NODE_WIDTH,         fy: NODE_TOP + 20,          side: "R", legend: "Selected ring." },
  { key: "name",    fx: NODE_LEFT + 38,                 fy: NODE_TOP + 44,          side: "L", legend: "Instance name." },
  { key: "thermal", fx: NODE_LEFT + NODE_WIDTH + 2,     fy: NODE_TOP + NODE_HEIGHT / 2, side: "R", legend: "Thermal port. Paired across opposing faces." },
  { key: "value",   fx: NODE_LEFT + 38,                 fy: NODE_TOP + 64,          side: "L", legend: "Value summary. Source blocks only." },
  { key: "error",   fx: NODE_LEFT + NODE_WIDTH,         fy: NODE_TOP + NODE_HEIGHT, side: "R", legend: "Persistent validation error outline." },
];

// Build callouts:
//   1. Sort features by fy ascending (then fx ascending for ties) → this
//      becomes the numbering order (1..9 top-to-bottom).
//   2. Partition into LEFT / RIGHT lists preserving fy order.
//   3. Assign chip y-positions to each list at equal spacing within
//      the chip column's vertical range. Because features in each list
//      are y-sorted AND slots are y-sorted, monotonic pairing within
//      each list guarantees no crossing within that column.
//   4. Cross-column crossings are impossible because LEFT chips are at
//      x=24..44 and RIGHT chips at x=596..616 — every LEFT leader stays
//      left of x=middle, every RIGHT stays right.
//
// Slot vertical range: y=180..420 for both columns (240 px tall).
const SLOT_TOP = 180;
const SLOT_BOTTOM = 420;

function buildCallouts(features: readonly RawFeature[]): {
  callouts: Callout[];
  legendByN: Map<number, string>;
} {
  const sorted = [...features].sort((a, b) =>
    a.fy === b.fy ? a.fx - b.fx : a.fy - b.fy,
  );
  // Assign numbers in sort order.
  const numbered = sorted.map((f, i) => ({ ...f, n: i + 1 }));

  // Partition by column, keeping internal y-order.
  const leftList = numbered.filter((f) => f.side === "L");
  const rightList = numbered.filter((f) => f.side === "R");

  function slotY(idx: number, total: number): number {
    if (total === 1) return (SLOT_TOP + SLOT_BOTTOM) / 2;
    return SLOT_TOP + (idx * (SLOT_BOTTOM - SLOT_TOP)) / (total - 1);
  }

  const callouts: Callout[] = [];
  const legendByN = new Map<number, string>();

  leftList.forEach((f, i) => {
    callouts.push({ n: f.n, side: "L", fx: f.fx, fy: f.fy, chipY: slotY(i, leftList.length) });
    legendByN.set(f.n, f.legend);
  });
  rightList.forEach((f, i) => {
    callouts.push({ n: f.n, side: "R", fx: f.fx, fy: f.fy, chipY: slotY(i, rightList.length) });
    legendByN.set(f.n, f.legend);
  });

  callouts.sort((a, b) => a.n - b.n);
  return { callouts, legendByN };
}

const { callouts: NODE_CALLOUTS, legendByN: NODE_LEGEND_BY_N } =
  buildCallouts(NODE_FEATURES);

function NodeTile(): React.JSX.Element {
  return (
    <div className="px-6 pb-2">
      <div
        className="relative rounded-sm border border-border/40 overflow-hidden"
        style={{
          width: NODE_TILE_W,
          height: NODE_TILE_H,
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
          width={NODE_TILE_W}
          height={NODE_TILE_H}
          viewBox={`0 0 ${NODE_TILE_W} ${NODE_TILE_H}`}
          className="absolute inset-0 pointer-events-none"
          aria-hidden
        >
          {NODE_CALLOUTS.map((c) => (
            <Leader key={c.n} callout={c} tileSide="node" />
          ))}
          {NODE_CALLOUTS.map((c) => (
            <FeatureMarker key={c.n} fx={c.fx} fy={c.fy} />
          ))}
        </svg>

        {NODE_CALLOUTS.map((c) => (
          <ChipBadge key={c.n} callout={c} tileSide="node" />
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Leader — dashed diagonal segment from feature marker to chip edge.
// Single straight line, no bends.
// ---------------------------------------------------------------------------

function Leader({
  callout,
  tileSide,
}: {
  callout: Callout;
  tileSide: "node" | "edges";
}): React.JSX.Element {
  const chip = chipAttachmentPoint(callout, tileSide);
  return (
    <line
      x1={callout.fx}
      y1={callout.fy}
      x2={chip.x}
      y2={chip.y}
      stroke={LEADER_STROKE}
      strokeOpacity={LEADER_OPACITY}
      strokeWidth={LEADER_WIDTH}
      strokeDasharray={LEADER_DASH}
      fill="none"
    />
  );
}

// ---------------------------------------------------------------------------
// FeatureMarker — small filled square at the leader's source point. Same
// visual idiom as the medical-anatomy diagram the user pointed to.
// ---------------------------------------------------------------------------

function FeatureMarker({ fx, fy }: { fx: number; fy: number }): React.JSX.Element {
  return (
    <rect
      x={fx - MARKER_SIZE / 2}
      y={fy - MARKER_SIZE / 2}
      width={MARKER_SIZE}
      height={MARKER_SIZE}
      fill="var(--foreground)"
      fillOpacity={0.85}
    />
  );
}

// ---------------------------------------------------------------------------
// ChipBadge — numbered chip in a column.
// ---------------------------------------------------------------------------

function ChipBadge({
  callout,
  tileSide,
}: {
  callout: Callout;
  tileSide: "node" | "edges";
}): React.JSX.Element {
  const rightChipX = tileSide === "node" ? RIGHT_CHIP_X_NODE : RIGHT_CHIP_X_EDGES;
  const left = callout.side === "L" ? LEFT_CHIP_X : rightChipX;
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
// NodeMirror — visual mirror of StreamNode. Same content as v2.
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
        {/* FlowPort in (top) */}
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
        {/* FlowPort out (bottom) */}
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
        {/* ThermalPort left */}
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
        {/* ThermalPort right */}
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
// NodeLegend
// ---------------------------------------------------------------------------

function NodeLegend(): React.JSX.Element {
  // Render numerically — 1..9 in two columns top-to-bottom.
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
// EdgesTile — three edge specimens + port-side convention schematic.
// Same two-column callout machinery. Four callouts; spread across LEFT and
// RIGHT columns.
// ---------------------------------------------------------------------------

const EDGES_TILE_W = 620;
const EDGES_TILE_H = 480;
const EDGE_SRC_X = 140;
const EDGE_TGT_X = 480;
const ROW_Y = [120, 200, 280];
const CONV_ROW_Y = 380;

// Convention mini-schematic positions.
const CONV_SRC_LEFT = 130;
const CONV_TGT_LEFT = 410;
const CONV_NODE_W = 50;
const CONV_NODE_H = 28;

// Edge-side features. Each callout points at a specific marker spot on or
// near its edge so the leader's destination is unambiguous.
const EDGES_FEATURES: readonly RawFeature[] = [
  {
    key: "hydraulic",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[0],
    side: "R",
    legend: "Hydraulic edge.",
  },
  {
    key: "bc",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[1],
    side: "L",
    legend:
      "Boundary-condition edge. Dashed. Side tag (L, R, L+R) marks which sides of the consumer it drives.",
  },
  {
    key: "loopTrace",
    fx: (EDGE_SRC_X + EDGE_TGT_X) / 2,
    fy: ROW_Y[2],
    side: "R",
    legend:
      "Validation loop trace. Marching ants. Tinted by severity (red, amber, blue).",
  },
  {
    key: "convention",
    fx: CONV_SRC_LEFT + CONV_NODE_W / 2,
    fy: CONV_ROW_Y - CONV_NODE_H / 2,
    side: "L",
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
          width: EDGES_TILE_W,
          height: EDGES_TILE_H,
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
          width={EDGES_TILE_W}
          height={EDGES_TILE_H}
          viewBox={`0 0 ${EDGES_TILE_W} ${EDGES_TILE_H}`}
          className="absolute inset-0"
          aria-hidden
        >
          {/* Row 1 — hydraulic default (solid). */}
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
          {/* Row 3 — marching-ants loop trace (warning severity). */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[2]} L${EDGE_TGT_X - 10},${ROW_Y[2]}`}
            stroke="var(--color-warning)"
            strokeWidth={2.5}
            strokeDasharray="6 4"
            fill="none"
            strokeLinecap="round"
            className="anatomy-flow-march"
          />

          {/* Port-side convention mini schematic — source rect + target
              rect + connecting edge. */}
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
            <Leader key={c.n} callout={c} tileSide="edges" />
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

        {/* Edge endpoint ports (blue source-side, red target-side). */}
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

        {/* Convention ports — port_in (blue) at source top/left + target
            top/left, port_out (red) at source bottom/right + target
            bottom/right. We render only the LEFT-most port_in and
            RIGHT-most port_out for clarity — same convention idea, less
            visual noise. */}
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
          <ChipBadge key={c.n} callout={c} tileSide="edges" />
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
