// modeEditors.tsx — Plan 63.1-14 GAP-RC-4.
//
// Shared sub-editor components extracted from BCsTabForm.tsx so they can be
// consumed by both BCsTabForm (consumer-side BCs tab) and ParameterForm
// (source-side Properties tab — WT.T_wall / HFS.q).
//
// ProfileModeEditor and FunctionModeEditor were originally defined inline in
// BCsTabForm.tsx (lines 558-697). They are now exported from here;
// BCsTabForm.tsx imports them via `from "./modeEditors"`.
//
// The `onUpdate` callback type is loosened to a 3-arm union (the same arms as
// SourceValueEntry) so that callers without the `mark`/`source` arms don't
// need to widen their handler. This is structurally a subtype of BCModeEntry
// so existing BCsTabForm callers continue to type-check.

import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import NumericField from "./NumericField";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
import type { BCModeEntry } from "@/lib/bcMode";

// Re-exported sub-types for consumers that need them.
export type ProfileEntry = Extract<BCModeEntry, { mode: "profile" }>;
export type FunctionEntry = Extract<BCModeEntry, { mode: "function" }>;

// 3-arm union shared by both consumers (SourceValueEntry arms + value arm).
type ThreeArmEntry =
  | { mode: "value"; value: number }
  | ProfileEntry
  | FunctionEntry;

// ---------------------------------------------------------------------------
// ProfileFileBlock — internal helper, not exported
// ---------------------------------------------------------------------------

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
// ProfileModeEditor — preset switcher + per-preset fields
// ---------------------------------------------------------------------------

export function ProfileModeEditor({
  entry,
  onUpdate,
}: {
  entry: ProfileEntry;
  onUpdate: (e: ThreeArmEntry) => void;
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

// ---------------------------------------------------------------------------
// FunctionModeEditor — fn(t) / fn(t, i) signature switcher + name input
// ---------------------------------------------------------------------------

export function FunctionModeEditor({
  entry,
  onUpdate,
}: {
  entry: FunctionEntry;
  onUpdate: (e: ThreeArmEntry) => void;
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
