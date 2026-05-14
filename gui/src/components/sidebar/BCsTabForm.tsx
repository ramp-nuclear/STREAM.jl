// BCsTabForm.tsx — Phase 63 Plan 63-C Task 03.
//
// The BCs-tab body for the right Properties panel. Renders one field-group
// per `external_inputs` pair (paired by the `_left`/`_right` suffix convention
// — registry does NOT declare `pair_with` on external_inputs per 63-B
// SUMMARY note), with:
//   • Symmetric / Asymmetric SegmentedButtonGroup (default Symmetric per
//     CD-05) collapsing/expanding paired fields (D-05; Phase 63.1 D-12
//     replaced the old "Symmetric (L = R)" custom switch).
//   • One inline shadcn Select per visible group as the BC mode picker
//     (Phase 63.1 D-11 replaced the legacy 5-pill BC mode picker).
//   • A per-mode editor body dispatched by the entry's `mode` discriminator.
//
// Critically, the form holds ZERO local state for BC values. Every mutation
// dispatches through the 63-B store actions (`setBCMode`, `clearBCMode`,
// `setBCSymmetric`). The symmetric mirror is performed inside `setBCMode`
// (useStore.ts:1133-1135) — this component only writes to the primary field.
//
// `componentId` (the consumer node's id) flows through bcModeKey(nodeId, name)
// to compose the store-slice key (D-23 single source-of-truth). The 63-B
// setBCMode action's first argument is the consumer node id despite the
// historical name; we follow that contract verbatim.
//
// Promote-to-shared-source flow (Phase 63.1 D-07 / D-08, supersedes the
// legacy "new source" outline button removed in Plan 08): a ghost Button
// rendered inline next to the Mode Select on every External-Inputs row
// whose externalInput.source_component is defined AND whose current entry
// is not already in `source` mode. Click dispatches the new store action
// `promoteToSharedSource(nodeId, externalInputName)` which spawns the
// value-source node at (consumer.x - 160, consumer.y - 40) per RESEARCH
// §A6, seeds the new node's `n` from the consumer Channel, and calls
// setBCMode (which materializes the dashed BC edge AND auto-mirrors to
// the sibling if symmetric ON). One click does what previously took
// "switch dropdown to Source → click + New".

import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { MoveUpRight } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import NumericField from "./NumericField";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
import { ProfileModeEditor, FunctionModeEditor } from "./modeEditors";
import { getComponent } from "@/registry";
import useStore, { type StreamNodeData } from "@/store/useStore";
import {
  bcModeKey,
  type BCMode,
  type BCModeEntry,
} from "@/lib/bcMode";
import type {
  ComponentDefinition,
  ExternalInput,
  Parameter,
} from "@/registry/types";

interface BCsTabFormProps {
  /** Selected consumer node's registry entry (Channel / ChannelHeatFlux). */
  component: ComponentDefinition;
  /** Selected consumer node's id (from store). */
  nodeId: string;
}

// ---------------------------------------------------------------------------
// Pair grouping (D-05) — _left/_right suffix convention
// ---------------------------------------------------------------------------

interface PairGroup {
  /** Base field name, e.g. "T_wall" (suffix stripped). */
  baseField: string;
  /** Primary external_input (alphabetically earlier — left). */
  primary: ExternalInput;
  /** Optional sibling (right side). */
  sibling?: ExternalInput;
}

function stripSideSuffix(name: string): string {
  if (name.endsWith("_left")) return name.slice(0, -"_left".length);
  if (name.endsWith("_right")) return name.slice(0, -"_right".length);
  return name;
}

function buildPairGroups(inputs: ReadonlyArray<ExternalInput>): PairGroup[] {
  const byBase = new Map<string, { left?: ExternalInput; right?: ExternalInput; single?: ExternalInput }>();
  for (const inp of inputs) {
    if (inp.name.endsWith("_left")) {
      const base = stripSideSuffix(inp.name);
      const slot = byBase.get(base) ?? {};
      slot.left = inp;
      byBase.set(base, slot);
    } else if (inp.name.endsWith("_right")) {
      const base = stripSideSuffix(inp.name);
      const slot = byBase.get(base) ?? {};
      slot.right = inp;
      byBase.set(base, slot);
    } else {
      const slot = byBase.get(inp.name) ?? {};
      slot.single = inp;
      byBase.set(inp.name, slot);
    }
  }
  const groups: PairGroup[] = [];
  for (const [base, slot] of byBase.entries()) {
    if (slot.left && slot.right) {
      groups.push({ baseField: base, primary: slot.left, sibling: slot.right });
    } else if (slot.left) {
      groups.push({ baseField: base, primary: slot.left });
    } else if (slot.right) {
      groups.push({ baseField: base, primary: slot.right });
    } else if (slot.single) {
      groups.push({ baseField: base, primary: slot.single });
    }
  }
  return groups;
}

// ---------------------------------------------------------------------------
// defaultEntryFor — used when the picker fires onChange with a new mode.
// ---------------------------------------------------------------------------

function defaultEntryFor(
  mode: BCMode,
  ctx: {
    consumerComponentLabel: string;
    externalInputName: string;
    existingSources: ReadonlyArray<{ id: string; instanceName: string }>;
  },
): BCModeEntry {
  switch (mode) {
    case "value":
      return { mode: "value", value: 0 };
    case "profile":
      return { mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.0 };
    case "function":
      return {
        mode: "function",
        signature: "fn(t)",
        functionName: `${ctx.consumerComponentLabel}_${ctx.externalInputName}_fn`,
      };
    case "mark":
      return { mode: "mark" };
    case "source":
      return {
        mode: "source",
        sourceNodeId: ctx.existingSources[0]?.id ?? "",
      };
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function BCsTabForm({ component, nodeId }: BCsTabFormProps) {
  const bcMode = useStore((s) => s.bcMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);
  const nodes = useStore((s) => s.nodes);
  const setBCMode = useStore((s) => s.setBCMode);
  const setBCSymmetric = useStore((s) => s.setBCSymmetric);

  const groups = buildPairGroups(component.external_inputs ?? []);

  if (groups.length === 0) {
    // Defensive — SidebarPanel only renders the BCs tab when external_inputs
    // is non-empty, so this branch should be unreachable.
    return (
      <p className="text-xs text-muted-foreground">
        This component has no external inputs.
      </p>
    );
  }

  // ---- Per-group rendering --------------------------------------------------
  return (
    <div className="flex flex-col gap-[16px] min-w-0">
      {groups.map((group, idx) => (
        <div key={group.baseField} className="min-w-0">
          {idx > 0 && <Separator className="mb-[16px]" />}
          <GroupBlock
            group={group}
            component={component}
            nodeId={nodeId}
            bcMode={bcMode}
            bcSymmetric={bcSymmetric}
            nodes={nodes}
            setBCMode={setBCMode}
            setBCSymmetric={setBCSymmetric}
          />
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// GroupBlock — one pair / singleton group
// ---------------------------------------------------------------------------

interface GroupBlockProps {
  group: PairGroup;
  component: ComponentDefinition;
  nodeId: string;
  bcMode: Record<string, BCModeEntry>;
  bcSymmetric: Record<string, boolean>;
  nodes: ReturnType<typeof useStore.getState>["nodes"];
  setBCMode: (
    componentId: string,
    externalInputName: string,
    entry: BCModeEntry,
  ) => void;
  setBCSymmetric: (
    nodeId: string,
    baseField: string,
    symmetric: boolean,
  ) => void;
}

function GroupBlock({
  group,
  component,
  nodeId,
  bcMode,
  bcSymmetric,
  nodes,
  setBCMode,
  setBCSymmetric,
}: GroupBlockProps) {
  const symKey = `${nodeId}::${group.baseField}`;
  const isPaired = group.sibling !== undefined;
  const isSymmetric = isPaired ? (bcSymmetric[symKey] ?? true) : false;

  function modeChangeFor(externalInputName: string, mode: BCMode) {
    const consumerNode = nodes.find((n) => n.id === nodeId);
    const consumerComponentLabel =
      (consumerNode?.data as unknown as StreamNodeData | undefined)?.componentId ??
      component.id;
    // Source-block list for the given external_input (filtered by registry
    // source_component contract; D-21).
    const sourceCompId = group.primary.source_component;
    const existingSources = nodes
      .filter(
        (n) =>
          (n.data as unknown as StreamNodeData | undefined)?.componentId ===
          sourceCompId,
      )
      .map((n) => ({
        id: n.id,
        instanceName:
          (n.data as unknown as StreamNodeData | undefined)?.instanceName ??
          n.id,
      }));

    if (mode === "source" && existingSources.length === 0) {
      // Handled by GroupBlock's inline +New button onClick; should not reach here.
      return;
    }
    const entry = defaultEntryFor(mode, {
      consumerComponentLabel,
      externalInputName,
      existingSources,
    });
    setBCMode(nodeId, externalInputName, entry);
  }

  return (
    <>
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground leading-[1.3] mb-[8px]">
        {group.baseField}
      </h3>

      {isPaired && (
        // Phase 63.1 D-12: labeled SegmentedButtonGroup replaces the legacy
        // "Symmetric (L = R)" custom switch. The boolean store value is
        // preserved at the boundary — `"sym" → true`, `"asym" → false`.
        // Copy lock-in (UI-SPEC §"Copy lock-in"): the full words
        // "Symmetric" / "Asymmetric" are load-bearing; never shorten.
        <div className="mb-[8px]">
          <SegmentedButtonGroup
            options={[
              { value: "sym", label: "Symmetric" },
              { value: "asym", label: "Asymmetric" },
            ]}
            active={isSymmetric ? "sym" : "asym"}
            onChange={(v) =>
              setBCSymmetric(nodeId, group.baseField, v === "sym")
            }
            size="sm"
          />
        </div>
      )}

      {!isPaired || isSymmetric ? (
        <FieldRow
          fieldName={group.primary.name}
          displayLabel={isPaired ? group.baseField : group.primary.name}
          component={component}
          nodeId={nodeId}
          externalInput={group.primary}
          entry={bcMode[bcModeKey(nodeId, group.primary.name)]}
          onModeChange={(m) => modeChangeFor(group.primary.name, m)}
          onEntryUpdate={(e) => setBCMode(nodeId, group.primary.name, e)}
          nodes={nodes}
        />
      ) : (
        <div className="flex flex-col gap-[16px]">
          <FieldRow
            fieldName={group.primary.name}
            displayLabel={`${group.primary.name}${group.primary.shape ?? ""}`}
            component={component}
            nodeId={nodeId}
            externalInput={group.primary}
            entry={bcMode[bcModeKey(nodeId, group.primary.name)]}
            onModeChange={(m) => modeChangeFor(group.primary.name, m)}
            onEntryUpdate={(e) => setBCMode(nodeId, group.primary.name, e)}
            nodes={nodes}
          />
          <Separator />
          {group.sibling &&
            (() => {
              const sib = group.sibling;
              return (
                <FieldRow
                  fieldName={sib.name}
                  displayLabel={`${sib.name}${sib.shape ?? ""}`}
                  component={component}
                  nodeId={nodeId}
                  externalInput={sib}
                  entry={bcMode[bcModeKey(nodeId, sib.name)]}
                  onModeChange={(m) => modeChangeFor(sib.name, m)}
                  onEntryUpdate={(e) => setBCMode(nodeId, sib.name, e)}
                  nodes={nodes}
                />
              );
            })()}
        </div>
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// FieldRow — picker + per-mode editor
// ---------------------------------------------------------------------------

interface FieldRowProps {
  fieldName: string;
  displayLabel: string;
  component: ComponentDefinition;
  nodeId: string;
  externalInput: ExternalInput;
  entry: BCModeEntry | undefined;
  onModeChange: (mode: BCMode) => void;
  onEntryUpdate: (entry: BCModeEntry) => void;
  nodes: ReturnType<typeof useStore.getState>["nodes"];
}

function FieldRow({
  fieldName,
  displayLabel,
  component,
  nodeId,
  externalInput,
  entry,
  onModeChange,
  onEntryUpdate,
  nodes,
}: FieldRowProps) {
  // Phase 63.1 D-11: inline shadcn Select replaces the legacy 5-pill BC mode
  // picker. The 5-mode dropdown takes the full row width so the per-mode
  // value editor below gets the same width. When `entry === undefined` the
  // trigger shows the placeholder and a destructive hint is rendered below
  // (D-09 carry-over, verbatim from the legacy copy).
  //
  // Phase 63.1 D-07 / D-08: the Promote-to-shared-source ghost button
  // sits inline at the end of the Mode-Select row (same flex container,
  // `flex-shrink-0` so it does not push the Select narrower; if the row
  // becomes narrower than ~240px it wraps below). Visibility rules per
  // UI-SPEC §"Promote-to-Shared-Source Button — Visibility rules":
  //   1. externalInput.source_component is defined (registry has a paired
  //      value-source — `WallTemperature` / `HeatFluxSource`).
  //   2. entry?.mode !== "source" — the input is not already promoted.
  // When hidden, no placeholder: the dropdown occupies the full row.
  const showPromote =
    !!externalInput.source_component && entry?.mode !== "source";
  // Plan 63.1-13 (GAP-MINOR-SOURCE-GATE): "Source" mode is only meaningful
  // when at least one Sources-category node already exists on the canvas.
  // Gate it via aria-disabled on the SelectItem.
  const hasAnySourceNode = nodes.some((n) => {
    const compId = (n.data as unknown as StreamNodeData | undefined)
      ?.componentId;
    return compId ? getComponent(compId)?.category === "Sources" : false;
  });
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">
        {displayLabel}
      </Label>
      <div className="flex items-center gap-[8px]">
        <div className="flex flex-col gap-[6px] flex-1 min-w-0">
          <Select
            value={entry?.mode ?? ""}
            onValueChange={(m) => onModeChange(m as BCMode)}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Select BC mode..." />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="value">Value</SelectItem>
              <SelectItem value="profile">Profile</SelectItem>
              <SelectItem value="function">Function</SelectItem>
              <SelectItem value="mark">Mark</SelectItem>
              <SelectItem value="source" disabled={!hasAnySourceNode}>
                Source
              </SelectItem>
            </SelectContent>
          </Select>
          {entry === undefined && (
            <p className="text-xs text-destructive/80 mt-[6px]">
              BC required — select a mode
            </p>
          )}
        </div>
        {showPromote && (
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Promote to shared source"
                  className="flex-shrink-0"
                  onClick={() =>
                    useStore
                      .getState()
                      .promoteToSharedSource(nodeId, externalInput.name)
                  }
                >
                  <MoveUpRight className="w-4 h-4" />
                </Button>
              </TooltipTrigger>
              <TooltipContent>Promote to shared source</TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}
      </div>
      <ModeEditorBody
        entry={entry}
        component={component}
        nodeId={nodeId}
        externalInput={externalInput}
        fieldName={fieldName}
        onEntryUpdate={onEntryUpdate}
        nodes={nodes}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// ModeEditorBody — dispatches per-mode editor sub-component
// ---------------------------------------------------------------------------

interface ModeEditorBodyProps {
  entry: BCModeEntry | undefined;
  component: ComponentDefinition;
  nodeId: string;
  externalInput: ExternalInput;
  fieldName: string;
  onEntryUpdate: (entry: BCModeEntry) => void;
  nodes: ReturnType<typeof useStore.getState>["nodes"];
}

function ModeEditorBody({
  entry,
  component,
  nodeId,
  externalInput,
  fieldName,
  onEntryUpdate,
  nodes,
}: ModeEditorBodyProps) {
  if (entry === undefined) return null;
  switch (entry.mode) {
    case "value":
      return (
        <ValueModeEditor
          value={entry.value}
          onChange={(v) => onEntryUpdate({ mode: "value", value: v })}
        />
      );
    case "profile":
      return <ProfileModeEditor entry={entry} onUpdate={onEntryUpdate} />;
    case "function":
      return <FunctionModeEditor entry={entry} onUpdate={onEntryUpdate} />;
    case "mark":
      return (
        <p className="text-xs text-muted-foreground">
          Marked in code — set {component.id}.{fieldName}[i] manually in
          generated .jl.
        </p>
      );
    case "source":
      return (
        <SourceModeEditor
          entry={entry}
          externalInput={externalInput}
          nodeId={nodeId}
          fieldName={fieldName}
          onUpdate={onEntryUpdate}
          nodes={nodes}
        />
      );
  }
}

// ---------------------------------------------------------------------------
// Value mode editor
// ---------------------------------------------------------------------------

function ValueModeEditor({
  value,
  onChange,
}: {
  value: number;
  onChange: (v: number) => void;
}) {
  const param: Parameter = {
    name: "Value",
    type: "Real",
    required: true,
    positional: false,
    default: value,
  };
  return (
    <NumericField
      param={param}
      value={value}
      onChange={(v) => {
        // NumericField.onChange is (number | undefined); ValueModeEditor's
        // param.default is always set to `value` so undefined is never
        // returned in practice. Guard for type safety.
        if (v !== undefined) onChange(v);
      }}
    />
  );
}

// ---------------------------------------------------------------------------
// Source mode editor — picks an existing canvas source node. Spawn-a-new-one
// path now lives in `promoteToSharedSource` (FieldRow ghost button), not here.
// ---------------------------------------------------------------------------

type SourceEntry = Extract<BCModeEntry, { mode: "source" }>;

function SourceModeEditor({
  entry,
  externalInput,
  nodeId,
  fieldName,
  onUpdate,
  nodes,
}: {
  entry: SourceEntry;
  externalInput: ExternalInput;
  nodeId: string;
  fieldName: string;
  onUpdate: (e: BCModeEntry) => void;
  nodes: ReturnType<typeof useStore.getState>["nodes"];
}) {
  // Phase 63.1 D-07 / D-08: the legacy "new source" outline button that
  // lived here has been removed. The Promote-to-shared-source ghost
  // button (rendered next to the Mode Select in FieldRow) supersedes it:
  // the user no longer has to first switch the dropdown to `Source` and
  // then click the legacy spawn button; one Promote click does both. Reaching the empty
  // source-mode state via mode-dropdown is now the rare path. When it
  // happens (e.g. the user selects `Source` then deletes the canvas
  // source node), the source-list `Select` simply renders empty — the
  // user can either pick a different mode from the dropdown or click
  // Promote (which is visible again as soon as entry.mode !== "source").
  const sourceCompId = externalInput.source_component;
  const matching = nodes.filter(
    (n) =>
      (n.data as unknown as StreamNodeData | undefined)?.componentId ===
      sourceCompId,
  );
  void nodeId;
  void fieldName;

  return (
    <Select
      value={entry.sourceNodeId}
      onValueChange={(id) =>
        onUpdate({ mode: "source", sourceNodeId: id })
      }
    >
      <SelectTrigger>
        <SelectValue placeholder="Select source..." />
      </SelectTrigger>
      <SelectContent>
        {matching.map((n) => (
          <SelectItem key={n.id} value={n.id}>
            {(n.data as unknown as StreamNodeData | undefined)?.instanceName ??
              n.id}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
