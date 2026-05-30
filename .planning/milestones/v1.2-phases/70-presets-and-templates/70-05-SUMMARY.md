---
phase: 70-presets-and-templates
plan: "05"
subsystem: gui
tags: [preset-modal, stream-node, project-io, radix-dialog, auto-extend, amber-outline]
dependency_graph:
  requires:
    - 70-01 (Textarea, RadioGroup shadcn primitives)
    - 70-02 (presetIO: autoExtendSelection, isValidPresetName)
    - 70-03 (saveSelectionAsPreset store action, projectPresets/libraryPresets state)
  provides:
    - gui/src/components/SavePresetModal.tsx — Save-as-Preset modal (Radix Dialog)
    - gui/src/components/StreamNode.tsx — amber dashed outline for autoExtended nodes
    - gui/src/lib/projectIO.ts — serializeProject strips data.autoExtended (Pitfall 7)
    - gui/src/store/useStore.ts — StreamNodeData.autoExtended?: boolean type field
  affects:
    - gui/src/components/SavePresetModal.tsx (new)
    - gui/src/components/StreamNode.tsx (modified)
    - gui/src/lib/projectIO.ts (modified)
    - gui/src/store/useStore.ts (modified — StreamNodeData interface)
tech_stack:
  added: []
  patterns:
    - "Radix Dialog controlled open/onOpenChange — same chrome as AboutDialog"
    - "useEffect keyed on open for paint+cleanup of transient data.autoExtended"
    - "Live validation with useMemo existingNames set + inline nameError IIFE"
    - "sanitizedNodes map in serializeProject for transient-flag strip (defense-in-depth)"
key_files:
  created:
    - gui/src/components/SavePresetModal.tsx
  modified:
    - gui/src/components/StreamNode.tsx
    - gui/src/lib/projectIO.ts
    - gui/src/store/useStore.ts
decisions:
  - "autoExtended?: boolean added to StreamNodeData in useStore.ts (single source of truth for node data shape) rather than a local cast in StreamNode"
  - "nameError shown only when name.length > 0 to avoid showing 'required' error on initial empty state"
  - "cleanup in useEffect return function clears autoExtended on ALL close paths (ESC, click-outside, Discard, Save) via the open flip dependency"
  - "Store radio resets to 'library' default after successful save for next open"
metrics:
  duration: "~12 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 3
  tasks_total: 3
  files_created: 1
  files_modified: 3
---

# Phase 70 Plan 05: Save-as-Preset Modal Summary

## One-liner

SavePresetModal (Radix Dialog with Name/Description/Store + live validation), amber dashed canvas outline on auto-extended nodes, and serializeProject Pitfall-7 strip of data.autoExtended from the .scp schema.

## What Was Built

### Task 1 — serializeProject strips data.autoExtended (commit eb2fdf0)

Added a `sanitizedNodes` map pass inside `serializeProject` in `gui/src/lib/projectIO.ts`. Before assembling the `StreamProject` object, every node is checked for the presence of `data.autoExtended`; if found, the key is destructured out via leading-underscore convention (`_autoExtended`) and the sanitized node is used in the `components` field. This is the second independent gate for Pitfall 7 (the first is in `serializePreset` from plan 70-02), providing defense-in-depth against the transient visual flag leaking into a persisted `.scp` file.

### Task 2 — Amber dashed outline in StreamNode (commit ed0f7a4)

Two surgical changes:

1. **`gui/src/store/useStore.ts`** — Added `autoExtended?: boolean` to the `StreamNodeData` interface with a docstring explaining the transient lifecycle. This gives TypeScript a typed accessor in StreamNode rather than requiring a cast.

2. **`gui/src/components/StreamNode.tsx`** — Added a fourth conditional to the outer `<div className={...}>` string:
   ```
   nodeData.autoExtended
     ? "outline outline-2 outline-dashed outline-[oklch(0.769_0.188_70.08)] outline-offset-2"
     : ""
   ```
   Color is chart-3 amber-ish (`oklch(0.769 0.188 70.08)`), visually distinct from both the blue selection ring and the existing destructive-error outline. Offset-2 prevents the outline from overlapping node content.

### Task 3 — SavePresetModal component (commit afc87b6)

New `gui/src/components/SavePresetModal.tsx` (274 lines), default export `SavePresetModal`, props `{ open: boolean; onOpenChange: (open: boolean) => void }`.

**Field groups (per UI-SPEC Surface 5, field order verbatim):**
- **Name** — project `<Input>` wrapper (auto-selects on focus per `feedback_input_select_on_focus`), `placeholder="e.g. mtr-fuel-assembly"`, live validation, error shown below when `name.length > 0`
- **Description** — shadcn `<Textarea>` `rows={3}`, `placeholder="Optional description shown on hover"`, no validation
- **Store** — shadcn `<RadioGroup>` with Library (default) and Project options; Project is `disabled={!projectIsOpen}` with `"Open a project first."` helper text below when disabled

**Auto-extend preview (Surface 9):**
- `useEffect` keyed on `open`: on open, computes `autoExtendSelection` against current store state, sets `data.autoExtended = true` on the extra nodes (BC-hop-included but not selected), focuses Name input
- Cleanup function (runs on every `open` change including close): strips `data.autoExtended` from all nodes unconditionally — covers ESC, click-outside, Discard, and successful Save
- `autoExtendedCount` from `useMemo` displays `"{N} additional component(s) included via BC connections."` when N > 0 (hidden when 0)

**Validation (T-70-18, T-70-21):**
- `nameError` IIFE: "Name is required." (empty), "Use only letters, digits, underscores, or hyphens." (charset), "A preset with this name already exists in {store}." (collision)
- Save Preset button `disabled={!!nameError || saving}`
- Collision check via `useMemo existingNames` set re-computed when `store`, `libraryPresets`, or `projectPresets` change

**Save handler:** calls `useStore.getState().saveSelectionAsPreset(name, description, store)`, then `onOpenChange(false)` and resets fields. Errors logged to console (no toast infra yet in this phase — plan 70-06 wires the trigger context).

**Footer:** `Button variant="ghost"` "Discard" / `Button variant="default"` "Save Preset" — verbatim copywriting contract.

## Deviations from Plan

None — plan executed exactly as written.

## Threat Model Compliance

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-70-18 | MITIGATED | Live `isValidPresetName` (charset gate) + collision check block the Save Preset button. Path traversal chars (`.`, `/`, `\`) rejected. |
| T-70-19 | MITIGATED | useEffect cleanup unconditionally strips data.autoExtended on every modal close. serializeProject in projectIO.ts also strips at save time (two independent gates). |
| T-70-20 | ACCEPTED | Description shown only as tooltip in PresetsPanel; no leakage path. |
| T-70-21 | MITIGATED | Live collision check against both projectPresets and libraryPresets in store; Save Preset disabled on collision. |

## Known Stubs

None — the modal fully implements the save flow. Trigger sites (FileMenu and NodeContextMenu) land in plan 70-06.

## Threat Flags

None — no new network endpoints, auth paths, file-access patterns, or schema changes at trust boundaries beyond what is in the plan's threat model.

## Self-Check: PASSED

- [x] `gui/src/components/SavePresetModal.tsx` exists, default export `SavePresetModal`
- [x] `grep -c autoExtended gui/src/lib/projectIO.ts` = 3 (>= 1 required)
- [x] `grep -c autoExtended gui/src/components/StreamNode.tsx` = 1 (>= 1 required)
- [x] `grep -c autoExtended gui/src/components/SavePresetModal.tsx` = 8 (>= 2 required)
- [x] `grep -c 'outline-\[oklch' gui/src/components/StreamNode.tsx` = 1 (>= 1 required)
- [x] Copywriting contract strings count = 6 (>= 4 required)
- [x] SavePresetModal.tsx: zero tsc errors in this file
- [x] `saveSelectionAsPreset|autoExtendSelection` count in SavePresetModal = 5
- [x] Commit eb2fdf0 exists (Task 1)
- [x] Commit ed0f7a4 exists (Task 2)
- [x] Commit afc87b6 exists (Task 3)
- [x] No modifications to PresetsPanel.tsx or PresetRow.tsx (sibling plan 70-04 territory)
