// AnatomyDialog — Phase 72 (help-system shape v2, 2026-05-22).
//
// A schematic-style visual legend for the canvas vocabulary. Renders a
// stylized StreamNode plus three edge specimens with numbered callouts
// connected by dashed orthogonal leader lines (technical-drawing
// convention). Opens from HelpMenu → "Anatomy" via the `stream:open-anatomy`
// custom event; no keybind by design.
//
// v2 redesign (2026-05-22, after user walkthrough of v1):
//   - No modal scrim (overlayClassName="bg-transparent"). Behavioural
//     intent: this is an opt-in reference card, not a state-blocking modal.
//     Matches CommandPalette's VS Code-style "tool overlay" idiom.
//   - Dialog surface tone matches CommandPalette / shortcut palette tone —
//     dedicated tool-overlay tier distinctly off chrome/panel/canvas
//     (oklch(0.93_0.012_254) light / oklch(0.13_0.012_254) dark).
//   - Dialog is much larger (~1200 × auto). Callouts have room to breathe.
//   - Leader lines: dashed, orthogonal-only (90° elbows), all numbers
//     aligned to a single vertical column per tile side. Matches
//     Houdini / Modelica / Bauhaus technical-drawing convention.
//   - Legend reads at text-body (13 px) not text-label (11 px).
//   - Engineering-voice copy. No em dashes (PRODUCT.md anti-pattern).
//   - autoExtended documented correctly as the "save-preview" outline
//     (Save Preset Modal flags BC-coupled neighbors with this violet
//     dashed outline — see SavePresetModal.tsx).
//
// Doctrine fidelity strategy unchanged from v1: render a *visual mirror* of
// StreamNode rather than the real component. The mirror consumes the same
// tokens and band geometry; when StreamNode changes visually, update here.

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

// Surface palette tone — same as CommandPalette so the help surfaces share
// one visual vocab. Defined as className strings to keep theme-switching
// working via Tailwind dark: variant.
const PALETTE_SURFACE = cn(
  "bg-[oklch(0.93_0.012_254)] dark:bg-[oklch(0.13_0.012_254)]",
  "border-[oklch(0.86_0.012_254)] dark:border-[oklch(0.24_0.012_254)]",
  "shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.18),0_4px_12px_-4px_oklch(0.05_0_0/0.12)]",
  "dark:shadow-[0_16px_40px_-12px_oklch(0.05_0_0/0.55),0_4px_12px_-4px_oklch(0.05_0_0/0.40)]",
);

export default function AnatomyDialog({
  open,
  onOpenChange,
}: AnatomyDialogProps): React.JSX.Element {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        // No scrim — this is an opt-in reference card, not state-blocking
        // chrome. Click-outside-to-close still works because DialogOverlay
        // mounts; it just paints nothing.
        overlayClassName="bg-transparent"
        className={cn(
          "p-0 gap-0 overflow-hidden rounded-md",
          "w-[1200px] max-w-[95vw] sm:max-w-[1200px]",
          "top-[8vh] translate-y-0",
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
// Section — column wrapper. Hosts the diagram tile and the legend.
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
// NodeTile — the hero node with callouts. Layout grid:
//   tile is 560 × 360
//   node body is 240 × 96, centered around (280, 200)
//     (node spans x=160..400, y=152..248)
//   LEFT  number column at x=44 (chip right edge at x=44+18=62)
//   RIGHT number column at x=498 (chip left edge at x=498)
//   Each callout's number is y-aligned to its feature so the dashed leader
//   is a single horizontal segment (no elbows). Where two features sit too
//   close, the closer number is offset and a 2-segment Z-leader is drawn
//   instead — but in practice the body lines (label/instance/value) are at
//   y={172, 188, 208}, enough spacing for 18-px chips.
// ---------------------------------------------------------------------------

interface Callout {
  /** Display number. */
  n: number;
  /** Number-chip side. "L" → left column; "R" → right column. */
  side: "L" | "R";
  /** Feature pointer x in the SVG coord system. */
  fx: number;
  /** Feature pointer y in the SVG coord system. */
  fy: number;
  /** Number-chip y (defaults to fy so the leader is pure horizontal). */
  ny?: number;
}

const NODE_TILE_W = 560;
const NODE_TILE_H = 380;
const LEFT_CHIP_X = 44;
const RIGHT_CHIP_X = 498;
const CHIP_SIZE = 18;

const NODE_CALLOUTS: Callout[] = [
  // LEFT column (5 features)
  { n: 1, side: "L", fx: 160, fy: 156, ny: 132 }, // layer band (top edge of band)
  { n: 2, side: "L", fx: 160, fy: 174, ny: 160 }, // component icon + label
  { n: 3, side: "L", fx: 160, fy: 192, ny: 188 }, // instance name
  { n: 4, side: "L", fx: 160, fy: 212, ny: 216 }, // value summary
  { n: 5, side: "L", fx: 142, fy: 148, ny: 244 }, // pressure anchor (icon outside node)
  // RIGHT column (4 features)
  { n: 6, side: "R", fx: 280, fy: 145, ny: 140 }, // flow port (top, in)
  { n: 7, side: "R", fx: 408, fy: 200, ny: 172 }, // thermal port (paired, right)
  { n: 8, side: "R", fx: 400, fy: 152, ny: 200 }, // selected ring (upper-right corner)
  { n: 9, side: "R", fx: 400, fy: 244, ny: 228 }, // persistent error outline (lower-right)
];

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
        {/* Rendered node (HTML, absolutely positioned in the tile's coord
            system). Coords match the leader fx/fy constants. */}
        <NodeMirror left={160} top={152} width={240} />

        {/* SVG overlay for leader lines, beneath the chips so chips paint
            over the line ends cleanly. */}
        <svg
          width={NODE_TILE_W}
          height={NODE_TILE_H}
          viewBox={`0 0 ${NODE_TILE_W} ${NODE_TILE_H}`}
          className="absolute inset-0 pointer-events-none"
          aria-hidden
        >
          {NODE_CALLOUTS.map((c) => (
            <LeaderLine key={c.n} callout={c} />
          ))}
        </svg>

        {/* Number chips. */}
        {NODE_CALLOUTS.map((c) => (
          <ChipBadge key={c.n} callout={c} />
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// NodeMirror — visual mirror of StreamNode. See file header for the
// fidelity strategy.
// ---------------------------------------------------------------------------

interface NodeMirrorProps {
  left: number;
  top: number;
  width: number;
}

function NodeMirror({ left, top, width }: NodeMirrorProps): React.JSX.Element {
  return (
    <div
      className="absolute"
      style={{ left, top, width }}
    >
      <div
        className="relative rounded-md"
        style={{
          // Selected ring + 1 px canvas offset. Matches StreamNode selected
          // box-shadow vocabulary line for line.
          boxShadow:
            "0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)",
          // Persistent error outline. (Selected + error coexist on the hero
          // to populate two callouts; the footer note explains they're
          // mutually exclusive in production.)
          outline: "2px solid var(--destructive)",
          outlineOffset: "0",
        }}
      >
        <div className="rounded-md overflow-hidden">
          {/* Dual-layer split band. Selected = 8 px tall. */}
          <div
            className="flex w-full"
            style={{ height: 8 }}
            aria-hidden
          >
            <div
              style={{
                flex: 1,
                backgroundColor: "var(--color-layer-hydraulic)",
              }}
            />
            <div
              style={{
                flex: 1,
                backgroundColor: "var(--color-layer-thermal)",
              }}
            />
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

        {/* Pressure anchor (icon left of node, matches StreamNode offset). */}
        <Anchor
          aria-hidden
          className="w-3 h-3 text-foreground"
          style={{ position: "absolute", left: -18, top: -8 }}
        />

        {/* FlowPort in (top, circular blue-on-blue). */}
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
        {/* FlowPort out (bottom, circular red-on-red). */}
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
        {/* ThermalPort (left, paired). */}
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
        {/* ThermalPort (right, paired). */}
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
// LeaderLine — dashed orthogonal polyline from number chip to feature.
// Pure horizontal when feature.y === chip.y; otherwise a 2-segment Z
// (horizontal → vertical → horizontal) with the elbow at a fixed lane x.
// ---------------------------------------------------------------------------

const LEFT_LANE_X = 132;
const RIGHT_LANE_X = 432;

function LeaderLine({ callout }: { callout: Callout }): React.JSX.Element {
  const chipY = callout.ny ?? callout.fy;
  // The line starts at the inner edge of the chip (so it appears to
  // emanate from the chip's number side).
  const startX =
    callout.side === "L" ? LEFT_CHIP_X + CHIP_SIZE : RIGHT_CHIP_X;
  const laneX = callout.side === "L" ? LEFT_LANE_X : RIGHT_LANE_X;
  const endX = callout.fx;
  const endY = callout.fy;

  // Build the polyline points.
  //  L: chip-edge → lane → vertical → feature.x → feature.y
  //  R: chip-edge → lane → vertical → feature.x → feature.y (mirrored)
  // When chipY === endY, the vertical segment collapses; the lane point
  // and the elbow are coincident, and the path reads as a single straight
  // horizontal line.
  const points: [number, number][] = [
    [startX, chipY],
    [laneX, chipY],
    [laneX, endY],
    [endX, endY],
  ];

  const pathD = points
    .map(([x, y], i) => `${i === 0 ? "M" : "L"}${x},${y}`)
    .join(" ");

  return (
    <path
      d={pathD}
      stroke="var(--foreground)"
      strokeOpacity={0.45}
      strokeWidth={1}
      strokeDasharray="4 3"
      fill="none"
      shapeRendering="crispEdges"
    />
  );
}

// ---------------------------------------------------------------------------
// ChipBadge — the numbered chip itself, absolutely positioned on the tile.
// ---------------------------------------------------------------------------

function ChipBadge({ callout }: { callout: Callout }): React.JSX.Element {
  const chipY = callout.ny ?? callout.fy;
  const left = callout.side === "L" ? LEFT_CHIP_X : RIGHT_CHIP_X;
  return (
    <span
      aria-hidden
      style={{
        position: "absolute",
        left,
        top: chipY - CHIP_SIZE / 2,
        width: CHIP_SIZE,
        height: CHIP_SIZE,
      }}
      className="inline-flex items-center justify-center rounded-sm font-mono text-micro tabular-nums bg-popover text-foreground/85 border border-border z-10"
    >
      {callout.n}
    </span>
  );
}

// ---------------------------------------------------------------------------
// NodeLegend — two-column legend matching the callout numbers. Reads at
// text-body (13 px). Engineering voice. No em dashes.
// ---------------------------------------------------------------------------

interface LegendItem {
  n: number;
  text: string;
}

const NODE_LEGEND_LEFT: readonly LegendItem[] = [
  { n: 1, text: "Layer accent band. Split for dual-layer components." },
  { n: 2, text: "Component type." },
  { n: 3, text: "Instance name." },
  { n: 4, text: "Value summary. Source blocks only." },
  { n: 5, text: "Pressure anchor." },
];

const NODE_LEGEND_RIGHT: readonly LegendItem[] = [
  { n: 6, text: "Flow port. Blue ports flow in, red ports flow out." },
  { n: 7, text: "Thermal port. Paired across opposing faces." },
  { n: 8, text: "Selected ring." },
  { n: 9, text: "Persistent validation error outline." },
];

function NodeLegend(): React.JSX.Element {
  return (
    <div className="px-6 pb-5 pt-3 grid grid-cols-2 gap-x-6 gap-y-2">
      <LegendColumn items={NODE_LEGEND_LEFT} />
      <LegendColumn items={NODE_LEGEND_RIGHT} />
    </div>
  );
}

function LegendColumn({ items }: { items: readonly LegendItem[] }): React.JSX.Element {
  return (
    <div className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-2 text-body items-baseline">
      {items.map((item) => (
        <React.Fragment key={item.n}>
          <span className="font-mono text-foreground/85 tabular-nums">
            {item.n}
          </span>
          <span className="text-foreground/85 leading-snug">{item.text}</span>
        </React.Fragment>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// EdgesTile — three edge specimens stacked vertically + a port-side
// convention diagram. Same leader-line system as the node tile.
// ---------------------------------------------------------------------------

const EDGES_TILE_W = 560;
const EDGES_TILE_H = 380;
const EDGE_SRC_X = 130;
const EDGE_TGT_X = 430;

// Three specimen rows. Port-side convention sits below as a small 2-node
// schematic.
const ROW_Y = [88, 152, 216];
const CONV_ROW_Y = 304;

const EDGES_CALLOUTS: Callout[] = [
  { n: 1, side: "R", fx: EDGE_TGT_X - 30, fy: ROW_Y[0] },
  { n: 2, side: "R", fx: EDGE_TGT_X - 30, fy: ROW_Y[1] },
  { n: 3, side: "R", fx: EDGE_TGT_X - 30, fy: ROW_Y[2] },
  { n: 4, side: "R", fx: EDGE_TGT_X - 30, fy: CONV_ROW_Y },
];

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
          {/* Row 1 — hydraulic default (solid 1.5 px). */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[0]} L${EDGE_TGT_X - 10},${ROW_Y[0]}`}
            stroke="var(--foreground)"
            strokeOpacity={0.7}
            strokeWidth={1.5}
            fill="none"
            strokeLinecap="round"
          />
          {/* Row 2 — BC dashed 6/3. */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[1]} L${EDGE_TGT_X - 10},${ROW_Y[1]}`}
            stroke="var(--muted-foreground)"
            strokeWidth={1.5}
            strokeDasharray="6 3"
            fill="none"
            strokeLinecap="round"
          />
          {/* Row 3 — loop trace marching ants (warning severity). */}
          <path
            d={`M${EDGE_SRC_X + 10},${ROW_Y[2]} L${EDGE_TGT_X - 10},${ROW_Y[2]}`}
            stroke="var(--color-warning)"
            strokeWidth={2.5}
            strokeDasharray="6 4"
            fill="none"
            strokeLinecap="round"
            className="anatomy-flow-march"
          />

          {/* Port-side convention — 2-node mini schematic. Source on the
              left, target on the right, with a clear "port_in at top/left,
              port_out at bottom/right" silhouette. */}
          {/* Source node body */}
          <rect
            x={EDGE_SRC_X - 30}
            y={CONV_ROW_Y - 14}
            width={50}
            height={28}
            rx={3}
            stroke="var(--foreground)"
            strokeOpacity={0.6}
            strokeWidth={1}
            fill="var(--card)"
          />
          {/* Target node body */}
          <rect
            x={EDGE_TGT_X - 50}
            y={CONV_ROW_Y - 14}
            width={50}
            height={28}
            rx={3}
            stroke="var(--foreground)"
            strokeOpacity={0.6}
            strokeWidth={1}
            fill="var(--card)"
          />
          {/* Edge between them */}
          <path
            d={`M${EDGE_SRC_X + 20},${CONV_ROW_Y} L${EDGE_TGT_X - 50},${CONV_ROW_Y}`}
            stroke="var(--foreground)"
            strokeOpacity={0.7}
            strokeWidth={1.5}
            fill="none"
            strokeLinecap="round"
          />

          {/* Leader lines */}
          {EDGES_CALLOUTS.map((c) => (
            <LeaderLine key={c.n} callout={c} />
          ))}

          {/* Local marching-ants keyframe (scoped to this file to avoid
              dependence on xyflow's `.validation-flow-trace` global). */}
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

        {/* Endpoint port dots for the three specimens. */}
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

        {/* BC mid-edge side tag, matching BCEdge's EdgeLabelRenderer. */}
        <span
          className="absolute rounded border bg-background px-[6px] py-[2px] text-[11px] text-muted-foreground font-mono pointer-events-none"
          style={{
            left: (EDGE_SRC_X + EDGE_TGT_X) / 2 - 18,
            top: ROW_Y[1] - 12,
          }}
        >
          L+R
        </span>

        {/* Port-side convention ports: port_in (blue) at LEFT of source,
            port_out (red) at RIGHT of target. */}
        <span
          aria-hidden
          style={{
            position: "absolute",
            left: EDGE_SRC_X - 30 - 6,
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
            left: EDGE_SRC_X + 20 - 6,
            top: CONV_ROW_Y - 6,
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
            left: EDGE_TGT_X - 50 - 6,
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
            left: EDGE_TGT_X - 6,
            top: CONV_ROW_Y - 6,
            width: 12,
            height: 12,
            background: "#f87171",
            border: "1.5px solid #b91c1c",
            borderRadius: "50%",
          }}
        />

        {/* Number chips. */}
        {EDGES_CALLOUTS.map((c) => (
          <ChipBadge key={c.n} callout={c} />
        ))}
      </div>
    </div>
  );
}

const EDGES_LEGEND: readonly LegendItem[] = [
  { n: 1, text: "Hydraulic edge." },
  { n: 2, text: "Boundary-condition edge. Dashed. Side tag (L, R, L+R) marks which sides of the consumer it drives." },
  { n: 3, text: "Validation loop trace. Marching ants. Tinted by severity (red, amber, blue)." },
  { n: 4, text: "Port-side convention. Flow enters from the top or left, exits from the bottom or right." },
];

function EdgesLegend(): React.JSX.Element {
  return (
    <div className="px-6 pb-5 pt-3">
      <LegendColumn items={EDGES_LEGEND} />
    </div>
  );
}
