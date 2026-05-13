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
// `+ New <SourceKind>` flow (D-20): when the Source-mode dropdown is empty,
// inline a button that:
//   1. Spawns a new value-source block via addNode(srcCompId, position) at
//      consumer.x - 120 (RESEARCH §"Pattern: + New inline").
//   2. Seeds n on the new block from the consumer Channel's n so the very
//      first source edge cannot trip _checkBCNMismatch (D-20 explicit).
//   3. Calls setBCMode with the new source-block id (which the action then
//      uses to materialize the BC edge AND auto-mirrors to the sibling if
//      symmetric ON).
// `addNode` returns void, so the new id is read back from the post-addNode
// state by diffing nodes (last added is the newest by store-append order).

import { useState } from "react";
import { Input } from "@/components/ui/input";
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
import NumericField from "./NumericField";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
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
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">
        {displayLabel}
      </Label>
      <div className="flex flex-col gap-[6px]">
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
            <SelectItem value="source">Source</SelectItem>
          </SelectContent>
        </Select>
        {entry === undefined && (
          <p className="text-xs text-destructive/80 mt-[6px]">
            BC required — select a mode
          </p>
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
    <NumericField param={param} value={value} onChange={onChange} />
  );
}

// ---------------------------------------------------------------------------
// Profile mode editor — preset switcher + per-preset fields
// ---------------------------------------------------------------------------

type ProfileEntry = Extract<BCModeEntry, { mode: "profile" }>;

function ProfileModeEditor({
  entry,
  onUpdate,
}: {
  entry: ProfileEntry;
  onUpdate: (e: BCModeEntry) => void;
}) {
  function selectPreset(preset: "cosine" | "file") {
    if (preset === "cosine") {
      onUpdate({
        mode: "profile",
        preset: "cosine",
        amplitude: entry.preset === "cosine" ? entry.amplitude : 1.0,
        peakingFactor: entry.preset === "cosine" ? entry.peakingFactor : 1.0,
      });
    } else {
      onUpdate({
        mode: "profile",
        preset: "file",
        path: entry.preset === "file" ? entry.path : "",
      });
    }
  }

  return (
    <div className="flex flex-col gap-[8px]">
      <SegmentedButtonGroup
        options={[
          { value: "cosine", label: "Cosine" },
          { value: "file", label: "File" },
        ]}
        active={entry.preset}
        onChange={selectPreset}
        size="sm"
      />
      {entry.preset === "cosine" ? (
        <>
          <NumericField
            param={{
              name: "amplitude",
              type: "Real",
              required: true,
              positional: false,
              default: entry.amplitude,
            }}
            value={entry.amplitude}
            onChange={(v) =>
              onUpdate({ ...entry, amplitude: v } as ProfileEntry)
            }
          />
          <NumericField
            param={{
              name: "peakingFactor",
              type: "Real",
              required: true,
              positional: false,
              default: entry.peakingFactor,
            }}
            value={entry.peakingFactor}
            onChange={(v) =>
              onUpdate({ ...entry, peakingFactor: v } as ProfileEntry)
            }
          />
        </>
      ) : (
        <ProfileFileBlock
          path={entry.path}
          onChange={(p) =>
            onUpdate({ mode: "profile", preset: "file", path: p })
          }
        />
      )}
    </div>
  );
}

function ProfileFileBlock({
  path,
  onChange,
}: {
  path: string;
  onChange: (p: string) => void;
}) {
  const [local, setLocal] = useState(path);
  return (
    <div className="flex flex-col gap-[4px]">
      <Label className="text-[12px] font-medium leading-[1.4]">CSV path</Label>
      <Input
        value={local}
        onChange={(e) => setLocal(e.target.value)}
        onBlur={() => onChange(local)}
        placeholder="profile.csv"
      />
      <Button variant="outline" size="sm" disabled>
        Choose file...
      </Button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Function mode editor
// ---------------------------------------------------------------------------

type FunctionEntry = Extract<BCModeEntry, { mode: "function" }>;

function FunctionModeEditor({
  entry,
  onUpdate,
}: {
  entry: FunctionEntry;
  onUpdate: (e: BCModeEntry) => void;
}) {
  const [name, setName] = useState(entry.functionName);
  return (
    <div className="flex flex-col gap-[8px]">
      <SegmentedButtonGroup
        options={[
          { value: "fn(t)", label: "fn(t)" },
          { value: "fn(t, i)", label: "fn(t, i)" },
        ]}
        active={entry.signature}
        onChange={(s) =>
          onUpdate({ ...entry, signature: s as FunctionEntry["signature"] })
        }
        size="sm"
      />
      <div className="flex flex-col gap-[4px]">
        <Label className="text-[12px] font-medium leading-[1.4]">
          Function name
        </Label>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          onBlur={() => onUpdate({ ...entry, functionName: name })}
        />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Source mode editor + + New <SourceKind> flow
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
  const sourceCompId = externalInput.source_component;
  const matching = nodes.filter(
    (n) =>
      (n.data as unknown as StreamNodeData | undefined)?.componentId ===
      sourceCompId,
  );

  function handleNewSource() {
    // Read fresh state — avoid stale closure on `nodes` prop.
    const state = useStore.getState();
    const consumerNode = state.nodes.find((n) => n.id === nodeId);
    if (!consumerNode) return;
    const consumerN =
      ((consumerNode.data as unknown as StreamNodeData).parameters?.n as
        | number
        | undefined) ?? 1;

    const beforeIds = new Set(state.nodes.map((n) => n.id));
    state.addNode(sourceCompId, {
      x: consumerNode.position.x - 120,
      y: consumerNode.position.y,
    });
    // Identify the freshly-added node by diffing pre/post id sets.
    const afterNodes = useStore.getState().nodes;
    const newNode = afterNodes.find((n) => !beforeIds.has(n.id));
    if (!newNode) return;

    // Seed n on the new source-block from the consumer FIRST so the subsequent
    // setBCMode (which materializes the BC edge AND fires _checkBCNMismatch)
    // does NOT flag the brand-new pair as mismatched (D-20 explicit).
    useStore.getState().updateNodeParams(newNode.id, {
      parameters: { n: consumerN },
    });
    useStore.getState().setBCMode(nodeId, fieldName, {
      mode: "source",
      sourceNodeId: newNode.id,
    });
  }

  if (matching.length === 0) {
    return (
      <Button variant="outline" size="sm" onClick={handleNewSource}>
        + New {sourceCompId}
      </Button>
    );
  }

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
