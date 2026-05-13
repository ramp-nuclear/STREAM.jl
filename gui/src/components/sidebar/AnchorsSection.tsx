// AnchorsSection.tsx — Phase 63.1 Plan 06 (UI for the per-component
// pressure anchor; D-02, D-04).
//
// Responsibility (UI-SPEC §"Anchors Section — Row Anatomy"):
//   • Renders nothing when the selected component has no FlowPort (D-04).
//   • Empty state (anchors[nodeId] === undefined): muted "No anchor set"
//     + outline "+ Add anchor" button. Clicking sets a default
//     { portField: "port_in.P", value: 0 } entry, transitioning the row
//     into populated state in place.
//   • Populated state: Port label + Select (port_in.P | port_out.P) +
//     Pressure label + NumericField + ghost "Clear anchor" button.
//
// All copy strings are verbatim from UI-SPEC §"Copywriting Contract" —
// they are load-bearing. The host (SidebarPanel ComponentTabs body) is
// responsible for the "Anchors" section header above this component.
//
// Wiring (D-02): consumes setAnchor / clearAnchor from the zustand store
// (anchors slice landed in Plan 03). Each store read uses a primitive-ish
// selector to keep zustand shallow equality stable.

import { useCallback } from "react";
import useStore from "@/store/useStore";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import NumericField from "./NumericField";
import type { ComponentDefinition, Parameter } from "@/registry/types";

interface AnchorsSectionProps {
  nodeId: string;
  component: ComponentDefinition;
}

export default function AnchorsSection({ nodeId, component }: AnchorsSectionProps) {
  // D-04 — FlowPort presence gate. A component with no FlowPort cannot
  // carry a pressure anchor (RESEARCH §"FlowPort presence gate pattern").
  const hasFlowPort = component.ports.some((p) => p.type === "FlowPort");
  if (!hasFlowPort) return null;

  // Read the per-node anchor entry. The selector returns either an
  // AnchorEntry (object) or undefined — zustand's strict equality is
  // sufficient here because setAnchor always replaces the entry by
  // reference (the action body at useStore.ts:1071-1078 spreads into a
  // new Record), so a stable entry yields a stable reference and a
  // changed entry yields a fresh one.
  const entry = useStore(
    useCallback((s) => s.anchors[nodeId], [nodeId]),
  );
  const setAnchor = useStore((s) => s.setAnchor);
  const clearAnchor = useStore((s) => s.clearAnchor);

  // ------- Empty state (UI-SPEC State A) ----------------------------------
  if (entry === undefined) {
    return (
      <div data-testid="anchors-section">
        <p className="text-xs text-muted-foreground mb-[8px]">No anchor set</p>
        <Button
          variant="outline"
          size="sm"
          data-testid="anchor-add"
          onClick={() =>
            setAnchor(nodeId, { portField: "port_in.P", value: 0 })
          }
        >
          + Add anchor
        </Button>
      </div>
    );
  }

  // ------- Populated state (UI-SPEC State B) ------------------------------
  // Synthetic Parameter for the NumericField — mirrors the
  // BCsTabForm.ValueModeEditor idiom (BCsTabForm.tsx:479-496) so the
  // user gets validateReal + aria-invalid + unit suffix for free.
  const pressureParam: Parameter = {
    name: "Pressure",
    type: "Real",
    required: true,
    positional: false,
    default: entry.value,
    unit: "Pa",
  };

  return (
    <div
      data-testid="anchors-section"
      className="flex flex-col gap-[8px] min-w-0"
    >
      <div className="flex flex-col gap-[4px] min-w-0">
        <Label className="text-[12px] font-medium leading-[1.4]">Port</Label>
        <Select
          value={entry.portField}
          onValueChange={(v) =>
            setAnchor(nodeId, {
              portField: v as "port_in.P" | "port_out.P",
              value: entry.value,
            })
          }
        >
          <SelectTrigger className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="port_in.P">port_in.P</SelectItem>
            <SelectItem value="port_out.P">port_out.P</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <NumericField
        param={pressureParam}
        value={entry.value}
        onChange={(v) =>
          setAnchor(nodeId, {
            portField: entry.portField,
            value: typeof v === "number" ? v : entry.value,
          })
        }
      />

      <Button
        variant="ghost"
        size="sm"
        data-testid="anchor-clear"
        className="self-start"
        onClick={() => clearAnchor(nodeId)}
      >
        Clear anchor
      </Button>
    </div>
  );
}
