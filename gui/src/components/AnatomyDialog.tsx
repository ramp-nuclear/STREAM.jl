// AnatomyDialog — distilled (Phase 72 critique P2-1, 2026-05-27) then
// upsized 2026-05-28 per feedback_chrome_color_for_anatomy_modals and
// feedback_avoid_low_opacity_text.
//
// Visual legend for the canvas vocabulary. The prior implementation was a
// 1340 px dialog with 640×520 tiles, dashed two-segment SVG leaders at
// slope-2, numbered chips and a numbered legend — "a diagram, not a help
// surface." Distilled to inline labels positioned next to each named
// feature; edges become a list of [specimen | name | description] rows.
//
// Surface uses `bg-chrome` (top-toolbar color) instead of the previously-
// locked `--dialog-surface`, so the dialog reads as part of the app shell
// rather than a separate darker slab. No close X — click outside or press
// Esc to dismiss. Typography bumped a tier across the board; opacity-dimmed
// grey text removed in favor of full foreground.

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

// Inline node-feature labels — full foreground, mono, text-body. No opacity
// dimming (the surface contrast is already low; layering /55 or /65 on top
// pushed legibility into the unacceptable band per the 2026-05-28 review).
const LABEL_CLASS =
  "absolute font-mono text-body text-foreground leading-none whitespace-nowrap pointer-events-none";

// ---------------------------------------------------------------------------
// Top-level dialog
// ---------------------------------------------------------------------------

export default function AnatomyDialog({
  open,
  onOpenChange,
}: AnatomyDialogProps): React.JSX.Element {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        overlayClassName="bg-transparent"
        showCloseButton={false}
        className={cn(
          "p-0 gap-0 overflow-hidden rounded-md",
          "w-[1300px] max-w-[95vw] sm:max-w-[1300px]",
          "top-[6vh] translate-y-0",
          // Chrome-toned surface (top-toolbar color), same border weight,
          // atmospheric shadow inherited from DialogContent default.
          "bg-chrome border-border",
        )}
        data-testid="anatomy-dialog"
      >
        <DialogHeader className="px-8 pt-6 pb-4 border-b border-border">
          <DialogTitle className="text-display font-normal tracking-tight text-foreground">
            Anatomy
          </DialogTitle>
          <DialogDescription className="sr-only">
            Visual legend for canvas components.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-2 divide-x divide-border">
          <Section title="Node">
            <NodeShowcase />
          </Section>
          <Section title="Edges">
            <EdgesShowcase />
          </Section>
        </div>

        <div className="border-t border-border px-8 py-4 text-body text-foreground font-mono leading-relaxed">
          Outline states: blue ring (selected) · red (validator error) · violet (Save Preset auto-add).
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
      <div className="px-8 pt-6 pb-4 text-body font-mono uppercase tracking-wider text-foreground/85">
        {title}
      </div>
      {children}
    </div>
  );
}

// ---------------------------------------------------------------------------
// FlowPortMirror — faithful render of StreamNode's flow-port disc + chevron.
// rotation: 0=right, 90=down, 180=left, 270=up.
// ---------------------------------------------------------------------------

interface FlowPortMirrorProps {
  rotation: number;
  size?: number;
  style?: React.CSSProperties;
}

function FlowPortMirror({
  rotation,
  size = 22,
  style,
}: FlowPortMirrorProps): React.JSX.Element {
  return (
    <svg aria-hidden width={size} height={size} viewBox="0 0 14 14" style={style}>
      <circle
        cx="7"
        cy="7"
        r="6"
        fill="var(--color-port-disc)"
        stroke="var(--color-port-disc-border)"
        strokeWidth="1"
      />
      <polygon
        points="5.5,4.5 8.5,7 5.5,9.5"
        fill="var(--color-port-chevron)"
        transform={`rotate(${rotation} 7 7)`}
      />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// NodeMirror — visual mirror of StreamNode at rest state. Selected ring +
// error outline live in the dialog footer line; the specimen here shows
// rest only.
// ---------------------------------------------------------------------------

function NodeMirror(): React.JSX.Element {
  return (
    <div className="relative rounded-md w-[340px]">
      <div className="rounded-md overflow-hidden border border-border">
        {/* Two-tone layer band */}
        <div className="flex w-full" style={{ height: 14 }} aria-hidden>
          <div style={{ flex: 1, backgroundColor: "var(--color-layer-hydraulic)" }} />
          <div style={{ flex: 1, backgroundColor: "var(--color-layer-thermal)" }} />
        </div>
        {/* Body */}
        <div className="bg-card px-3.5 py-3">
          <div className="flex items-center gap-2 text-body text-foreground">
            <BoxIcon className="w-5 h-5" strokeWidth={1.5} />
            ChannelAndContacts
          </div>
          <div className="font-semibold text-title mt-1">channel_1</div>
          <div className="text-body text-foreground mt-1">
            L = 1.2 m  Dh = 12 mm
          </div>
        </div>
      </div>

      {/* Pressure anchor — top-left exterior */}
      <Anchor
        aria-hidden
        className="w-5 h-5 text-foreground"
        style={{ position: "absolute", left: -28, top: -12 }}
      />
      {/* Flow port IN — top edge, chevron down */}
      <FlowPortMirror
        rotation={90}
        style={{
          position: "absolute",
          top: -11,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      />
      {/* Flow port OUT — bottom edge, chevron down (flow leaves downward) */}
      <FlowPortMirror
        rotation={90}
        style={{
          position: "absolute",
          bottom: -11,
          left: "50%",
          transform: "translateX(-50%)",
        }}
      />
      {/* Thermal port — left side (diamond) */}
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
      {/* Thermal port — right side (diamond) */}
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
  );
}

// ---------------------------------------------------------------------------
// NodeShowcase — node specimen with inline labels positioned next to each
// named feature. Labels are children of a `<div className="relative">`
// sized to the node-mirror, so each label's offset from its feature stays
// constant regardless of dialog/column width.
// ---------------------------------------------------------------------------

function NodeShowcase(): React.JSX.Element {
  return (
    <div className="px-8 pb-8">
      <div className="relative h-[360px] flex items-center justify-center">
        <div className="relative">
          <NodeMirror />

          {/* Anchor — sits to the LEFT of the anchor icon. */}
          <span
            className={LABEL_CLASS}
            style={{ top: -4, right: "calc(100% + 38px)" }}
          >
            anchor
          </span>

          {/* Flow in — centered above the top port. */}
          <span
            className={LABEL_CLASS}
            style={{
              bottom: "calc(100% + 36px)",
              left: "50%",
              transform: "translateX(-50%)",
            }}
          >
            flow in
          </span>

          {/* Layer band — to the RIGHT of the band area. */}
          <span
            className={LABEL_CLASS}
            style={{ top: 2, left: "calc(100% + 22px)" }}
          >
            layer band
          </span>

          {/* Thermal port — vertically centered with the right thermal
              diamond. */}
          <span
            className={LABEL_CLASS}
            style={{
              top: "50%",
              left: "calc(100% + 22px)",
              transform: "translateY(-50%)",
            }}
          >
            thermal port
          </span>

          {/* Flow out — centered below the bottom port. */}
          <span
            className={LABEL_CLASS}
            style={{
              top: "calc(100% + 36px)",
              left: "50%",
              transform: "translateX(-50%)",
            }}
          >
            flow out
          </span>
        </div>
      </div>

      {/* Body-row vocabulary — names the three visible body rows in prose. */}
      <p className="mt-2 text-body text-foreground font-mono leading-relaxed">
        Body lines: component type · instance name · value summary (source blocks only).
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// EdgesShowcase — list of edge types, each row: [specimen | name + description].
// ---------------------------------------------------------------------------

function EdgesShowcase(): React.JSX.Element {
  return (
    <div className="px-8 pb-8 flex flex-col gap-6">
      <EdgeRow
        edge={<HydraulicSpecimen />}
        name="hydraulic"
        description="Default flow edge."
      />
      <EdgeRow
        edge={<BCSpecimen />}
        name="BC"
        description={
          <>
            Dashed. Side tag (<code className="font-mono">L</code>,{" "}
            <code className="font-mono">R</code>,{" "}
            <code className="font-mono">L+R</code>) marks driven sides.
          </>
        }
      />
      <EdgeRow
        edge={<LoopTraceSpecimen />}
        name="loop trace"
        description="Marching ants. Tinted by severity."
      />
      <EdgeRow
        edge={<PortConventionSpecimen />}
        name="port convention"
        description="Flow enters from top or left, exits from bottom or right."
      />
    </div>
  );
}

interface EdgeRowProps {
  edge: React.ReactNode;
  name: string;
  description: React.ReactNode;
}

function EdgeRow({ edge, name, description }: EdgeRowProps): React.JSX.Element {
  return (
    <div className="flex items-center gap-6">
      <div className="shrink-0 w-[140px] flex items-center justify-center">
        {edge}
      </div>
      <div className="min-w-0">
        <div className="font-mono text-title text-foreground leading-tight">
          {name}
        </div>
        <div className="text-body text-foreground leading-snug mt-1">
          {description}
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Edge specimens — 140×40 SVGs sharing dimensions and flow-port endpoints
// so the rows align vertically as a list.
// ---------------------------------------------------------------------------

function HydraulicSpecimen(): React.JSX.Element {
  return (
    <SpecimenSvg>
      <FlowDot cx={14} cy={20} />
      <path
        d="M24,20 L116,20"
        stroke="var(--foreground)"
        strokeOpacity={0.85}
        strokeWidth={2}
        fill="none"
        strokeLinecap="round"
      />
      <FlowDot cx={126} cy={20} />
    </SpecimenSvg>
  );
}

function BCSpecimen(): React.JSX.Element {
  return (
    <SpecimenSvg>
      <FlowDot cx={14} cy={20} />
      <path
        d="M24,20 L116,20"
        stroke="var(--foreground)"
        strokeOpacity={0.65}
        strokeWidth={2}
        strokeDasharray="7 4"
        fill="none"
        strokeLinecap="round"
      />
      <FlowDot cx={126} cy={20} />
    </SpecimenSvg>
  );
}

function LoopTraceSpecimen(): React.JSX.Element {
  return (
    <SpecimenSvg>
      <FlowDot cx={14} cy={20} />
      <path
        d="M24,20 L116,20"
        stroke="var(--color-warning)"
        strokeWidth={3}
        strokeDasharray="7 5"
        fill="none"
        strokeLinecap="round"
        className="anatomy-flow-march"
      />
      <FlowDot cx={126} cy={20} />
      <style>
        {`
        .anatomy-flow-march { animation: anatomy-flow-march 1.5s linear infinite; }
        @keyframes anatomy-flow-march { to { stroke-dashoffset: -12; } }
        @media (prefers-reduced-motion: reduce) { .anatomy-flow-march { animation: none; } }
        `}
      </style>
    </SpecimenSvg>
  );
}

function PortConventionSpecimen(): React.JSX.Element {
  // Render order: both rects first, then connector + dots, so the
  // flow-port glyphs sit ON TOP of the rect edges (right rect's --card
  // fill would otherwise paint over its left-edge dot).
  return (
    <SpecimenSvg>
      <rect
        x={14}
        y={9}
        width={42}
        height={22}
        rx={3}
        stroke="var(--foreground)"
        strokeOpacity={0.7}
        strokeWidth={1.25}
        fill="var(--card)"
      />
      <rect
        x={84}
        y={9}
        width={42}
        height={22}
        rx={3}
        stroke="var(--foreground)"
        strokeOpacity={0.7}
        strokeWidth={1.25}
        fill="var(--card)"
      />
      <path
        d="M62,20 L78,20"
        stroke="var(--foreground)"
        strokeOpacity={0.85}
        strokeWidth={2}
        fill="none"
        strokeLinecap="round"
      />
      <FlowDot cx={56} cy={20} />
      <FlowDot cx={84} cy={20} />
    </SpecimenSvg>
  );
}

function SpecimenSvg({ children }: { children: React.ReactNode }): React.JSX.Element {
  return (
    <svg width="140" height="40" viewBox="0 0 140 40" aria-hidden>
      {children}
    </svg>
  );
}

// FlowDot — compact inline-svg variant of FlowPortMirror sized for the edge
// specimens. Uses the same disc + chevron tokens as the production port.
function FlowDot({ cx, cy }: { cx: number; cy: number }): React.JSX.Element {
  return (
    <g aria-hidden>
      <circle
        cx={cx}
        cy={cy}
        r={7}
        fill="var(--color-port-disc)"
        stroke="var(--color-port-disc-border)"
        strokeWidth={1}
      />
      <polygon
        points={`${cx - 2.2},${cy - 3.5} ${cx + 2.4},${cy} ${cx - 2.2},${cy + 3.5}`}
        fill="var(--color-port-chevron)"
      />
    </g>
  );
}
