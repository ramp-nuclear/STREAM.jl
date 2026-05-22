// AnatomyDialog — Phase 72 (help-system shape, 2026-05-22).
//
// A modal visual legend for the canvas vocabulary. Renders a stylized
// StreamNode + edge specimens with every state forced on simultaneously,
// numbered callouts over the diagram, and a side legend mapping number →
// description. Opens from HelpMenu → "Show Anatomy…"; no keybind (low-
// frequency reference doesn't earn one — see PROGRESS.md "Re-entry
// instructions").
//
// Doctrine fidelity strategy:
//   The dialog renders a *visual mirror* of `StreamNode` rather than the
//   real component, because StreamNode reads from the global zustand store
//   (errorNodeIds, anchors, hoveredSourceIds, activeLayers, ...) and would
//   need every selector path stubbed out to render in a non-canvas context.
//   The mirror consumes the same tokens (`--card`, `--ring`, `--destructive`,
//   `--color-layer-*`, `--node-ring-rest`) and the same band geometry, body
//   structure, and ring/outline values — so the legend stays accurate. When
//   StreamNode's visual changes, update the mirror here too. Drift surface
//   intentionally small (only the visual shell, not behavior).
//
// Edges are inline SVG paths with the same stroke vocabulary as HydraulicEdge
// + BCEdge — solid 1.5 px for default Hydraulic, dashed 6/3 for BC, and a
// marching-ants 2.5 px dashed for loop trace (severity = warning).
//
// PRODUCT.md anchor references: Houdini node-anatomy diagrams (single hero
// specimen + side legend), schematic-editor legend tradition.

import * as React from "react";
import { Anchor, Box as BoxIcon } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";

interface AnatomyDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export default function AnatomyDialog({
  open,
  onOpenChange,
}: AnatomyDialogProps): React.JSX.Element {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="!max-w-[920px] w-[92vw] p-0 gap-0 overflow-hidden"
        data-testid="anatomy-dialog"
      >
        <DialogHeader className="px-5 pt-4 pb-3 border-b border-border/60">
          <DialogTitle className="text-title font-normal tracking-tight">
            Anatomy
          </DialogTitle>
          <DialogDescription className="sr-only">
            Visual legend for canvas components and their states.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-2 gap-0 divide-x divide-border/60">
          <Section title="Node" legend={NODE_LEGEND}>
            <NodeShowcase />
          </Section>
          <Section title="Edges" legend={EDGES_LEGEND}>
            <EdgesShowcase />
          </Section>
        </div>

        <div className="border-t border-border/60 px-5 py-2 text-micro font-mono text-foreground/55">
          not all states co-occur on a real node
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Section — one column of the dialog. Contains a labeled diagram tile and a
// numbered legend list. Tile uses the canvas grid tone behind it so the
// rendered node/edges sit on the same texture they appear on in the canvas.
// ---------------------------------------------------------------------------

interface LegendEntry {
  /** Display number ("1", "2", ...). Mono chip both in the diagram and the
   *  legend. */
  n: string;
  /** Short engineering-voice description; no sentence-final period. */
  text: string;
}

interface SectionProps {
  title: string;
  legend: readonly LegendEntry[];
  children: React.ReactNode;
}

function Section({ title, legend, children }: SectionProps): React.JSX.Element {
  return (
    <div className="flex flex-col">
      <div className="px-5 pt-4 pb-2 text-micro font-mono uppercase tracking-wide text-foreground/55">
        {title}
      </div>
      <div className="px-5 pb-3">
        <div
          className="relative rounded-md border border-border/60 min-h-[260px] flex items-center justify-center overflow-hidden"
          style={{
            // Match the actual canvas grid texture. Two stacked linear-
            // gradient layers replicate xyflow's BackgroundVariant.Lines.
            backgroundColor: "var(--canvas)",
            backgroundImage:
              "linear-gradient(to right, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
              "linear-gradient(to bottom, var(--color-canvas-grid-minor) 1px, transparent 1px), " +
              "linear-gradient(to right, var(--color-canvas-grid-major) 1px, transparent 1px), " +
              "linear-gradient(to bottom, var(--color-canvas-grid-major) 1px, transparent 1px)",
            backgroundSize: "12px 12px, 12px 12px, 24px 24px, 24px 24px",
          }}
        >
          {children}
        </div>
      </div>
      <div className="px-5 pb-4 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-label">
        {legend.map((entry) => (
          <React.Fragment key={entry.n}>
            <span className="font-mono text-foreground/85 tabular-nums">
              {entry.n}
            </span>
            <span className="text-foreground/85">{entry.text}</span>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// CalloutChip — a small numbered marker overlaid on the diagram tile.
// Absolutely positioned by parent; consumes plain CSS top/left props.
// 18×18 px, rounded-sm, mono micro. Hairline 1 px border so it reads on either
// a dark or light grid background.
// ---------------------------------------------------------------------------

interface CalloutChipProps {
  n: string;
  /** Absolute position relative to the parent tile. */
  top: string | number;
  left: string | number;
}

function CalloutChip({ n, top, left }: CalloutChipProps): React.JSX.Element {
  return (
    <span
      aria-hidden
      style={{ top, left }}
      className="absolute inline-flex items-center justify-center w-[18px] h-[18px] rounded-sm font-mono text-micro tabular-nums bg-popover text-foreground/85 border border-border z-10"
    >
      {n}
    </span>
  );
}

// ---------------------------------------------------------------------------
// NodeShowcase — a visual mirror of StreamNode with every state forced on.
// See doctrine-fidelity note at file top.
// ---------------------------------------------------------------------------

function NodeShowcase(): React.JSX.Element {
  // Dimensions roughly matching a real CAC node (~220 × ~80). Hardcoded so
  // the callout positions stay deterministic; the real node auto-sizes to
  // content.
  const NODE_W = 220;
  const NODE_H = 88;
  const BAND_H = 8; // selected state → 8 px (locked DESIGN.md §5)

  return (
    <div className="relative" style={{ width: 360, height: 220 }}>
      {/* Centered node wrapper */}
      <div
        className="absolute"
        style={{
          left: (360 - NODE_W) / 2,
          top: (220 - NODE_H) / 2,
          width: NODE_W,
        }}
      >
        {/* Outer wrapper — carries selected ring + persistent error outline.
            Mirrors StreamNode's outer div line for line. */}
        <div
          className="relative rounded-md"
          style={{
            // Selected: 8 px band + 3 px Hydraulic-blue ring with 1 px
            // canvas-offset. Tracks StreamNode.tsx style={} block.
            boxShadow:
              "0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)",
            // Persistent error outline (one of three mutually-exclusive
            // outline states; we show error here. autoExtended dashed is
            // shown via a small "callout 8" sample below).
            outline: "2px solid var(--destructive)",
            outlineOffset: "0",
          }}
        >
          <div className="rounded-md overflow-hidden">
            {/* Dual-layer split band — Hydraulic (left) + Thermal (right),
                each half the width. Matches getDisplayLayers() output for
                ChannelAndContacts. */}
            <div
              className="flex w-full"
              style={{ height: BAND_H }}
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

          {/* Anchor indicator (same Anchor lucide as StreamNode, same offset). */}
          <Anchor
            aria-hidden
            className="w-3 h-3 text-foreground"
            style={{ position: "absolute", left: -16, top: -6 }}
          />

          {/* Fake port handles, matching StreamNode geometry. FlowPort:
              circular 12 px, blue-on-blue-border (in) / red-on-red-border
              (out). ThermalPort: rotated 45° square 12 px, amber-on-darker. */}
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
          {/* ThermalPort (left, paired CAC) */}
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
          {/* ThermalPort (right, paired CAC) */}
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

      {/* Callout overlays. Positions are tuned against the rendered node;
          each chip sits ~6 px outside the feature it labels. */}
      {/* 1 — Hydraulic layer band (left half) */}
      <CalloutChip n="1" top={47} left={70} />
      {/* 2 — Thermal layer band (right half) */}
      <CalloutChip n="2" top={47} left={196} />
      {/* 3 — Component icon + label */}
      <CalloutChip n="3" top={70} left={28} />
      {/* 4 — Instance name */}
      <CalloutChip n="4" top={92} left={28} />
      {/* 5 — Value summary line */}
      <CalloutChip n="5" top={112} left={28} />
      {/* 6 — Flow ports (top + bottom) */}
      <CalloutChip n="6" top={50} left={172} />
      {/* 7 — Selected ring */}
      <CalloutChip n="7" top={62} left={302} />
      {/* 8 — Error outline */}
      <CalloutChip n="8" top={150} left={302} />
      {/* 9 — Anchor */}
      <CalloutChip n="9" top={62} left={50} />

      {/* Tiny inline sample tiles for outline variants — autoExtended (dashed
          chart-5) + flash. Stacking all outline states on a single hero would
          be visually impossible (they're mutually exclusive). The legend
          mentions both; here they sit as 24×16 micro-samples in the corner so
          the legend's claim is grounded in something visual. */}
      <div className="absolute bottom-2 right-2 flex gap-2 items-center bg-popover/60 backdrop-blur-0 rounded-sm border border-border px-2 py-1">
        <div
          aria-hidden
          title="autoExtended"
          style={{
            width: 24,
            height: 16,
            outline: "2px dashed var(--chart-5)",
            outlineOffset: 2,
            borderRadius: 4,
            background: "var(--card)",
          }}
        />
        <span className="font-mono text-foreground/65 text-micro">
          10 autoExtended
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// EdgesShowcase — three edge specimens stacked vertically.
//
//   1. Hydraulic default — solid 1.5 px stroke, rounded orthogonal path,
//      ports at each end.
//   2. BC dashed — 1.5 px stroke, 6/3 dasharray (matches BCEdge.tsx), with
//      the mid-edge `L+R` tag.
//   3. Loop trace — 2.5 px warning-tinted stroke, 6/4 dasharray with
//      marching-ants animation (matches `.validation-flow-trace`). Severity
//      tint = `--color-warning`.
// ---------------------------------------------------------------------------

function EdgesShowcase(): React.JSX.Element {
  const W = 360;
  const H = 220;
  const colX = { src: 60, mid: W / 2, tgt: W - 60 };

  // Three horizontal rows, evenly spaced.
  const rowY = [60, 110, 160];

  return (
    <div className="relative" style={{ width: W, height: H }}>
      <svg
        width={W}
        height={H}
        viewBox={`0 0 ${W} ${H}`}
        className="absolute inset-0"
      >
        {/* Row 1 — hydraulic default. Rounded orthogonal (straight here for
            clarity; the real router would route around obstacles). */}
        <path
          d={`M${colX.src + 10},${rowY[0]} L${colX.tgt - 10},${rowY[0]}`}
          stroke="var(--foreground)"
          strokeOpacity={0.65}
          strokeWidth={1.5}
          fill="none"
          strokeLinecap="round"
        />
        {/* Row 2 — BC dashed */}
        <path
          d={`M${colX.src + 10},${rowY[1]} L${colX.tgt - 10},${rowY[1]}`}
          stroke="var(--muted-foreground)"
          strokeWidth={1.5}
          strokeDasharray="6 3"
          fill="none"
          strokeLinecap="round"
        />
        {/* Row 3 — loop trace marching ants */}
        <path
          d={`M${colX.src + 10},${rowY[2]} L${colX.tgt - 10},${rowY[2]}`}
          stroke="var(--color-warning)"
          strokeWidth={2.5}
          strokeDasharray="6 4"
          fill="none"
          strokeLinecap="round"
          className="anatomy-flow-march"
        />
        {/* Local marching-ants keyframe — scoped here so we don't depend on
            the global xyflow-scoped `.validation-flow-trace` selector. */}
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

      {/* Edge endpoint dots (8 dots: source + target for each of 3 rows + a
          single port-convention pair on the leftmost / topmost). Drawn as
          small circles using the FlowPort palette so the user reads the
          dots as ports. */}
      {rowY.map((y, i) => (
        <React.Fragment key={i}>
          <span
            aria-hidden
            style={{
              position: "absolute",
              left: colX.src - 6,
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
              left: colX.tgt - 6,
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

      {/* BC mid-edge side tag — matches BCEdge's EdgeLabelRenderer
          rendering. Static "L+R" here. */}
      <span
        className="absolute rounded border bg-background px-[6px] py-[2px] text-[11px] text-muted-foreground font-mono pointer-events-none"
        style={{
          left: colX.mid - 18,
          top: rowY[1] - 12,
        }}
      >
        L+R
      </span>

      {/* Callout chips — one per edge specimen + one for port-side convention. */}
      <CalloutChip n="1" top={rowY[0] - 22} left={colX.mid - 10} />
      <CalloutChip n="2" top={rowY[1] - 36} left={colX.mid + 30} />
      <CalloutChip n="3" top={rowY[2] - 22} left={colX.mid - 10} />
      {/* 4 — Port-side convention indicator: left dot = port_in, right dot =
          port_out. Anchored to the top row's source port. */}
      <CalloutChip n="4" top={rowY[0] - 22} left={colX.src - 18} />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Legend content. Numbers MUST match the callout chips above.
// ---------------------------------------------------------------------------

const NODE_LEGEND: readonly LegendEntry[] = [
  { n: "1", text: "Hydraulic layer band" },
  { n: "2", text: "Thermal layer band (dual-layer split)" },
  { n: "3", text: "Component icon and type label" },
  { n: "4", text: "Instance name" },
  { n: "5", text: "Value summary (source blocks)" },
  { n: "6", text: "Flow ports — round, blue = in, red = out" },
  { n: "7", text: "Selected ring (8 px band, blue ring)" },
  { n: "8", text: "Persistent error outline (red)" },
  { n: "9", text: "Pressure anchor" },
  { n: "10", text: "autoExtended outline (dashed, violet)" },
];

const EDGES_LEGEND: readonly LegendEntry[] = [
  { n: "1", text: "Hydraulic edge (default)" },
  { n: "2", text: "Boundary condition (dashed, L / R / L+R tag)" },
  { n: "3", text: "Loop trace (marching ants, validation)" },
  { n: "4", text: "Port-side convention (in from top / left, out from bottom / right)" },
];
