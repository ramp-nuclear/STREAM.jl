---
status: partial
phase: 63-bcs-tab-value-source-components-in-gui
source: [63-VERIFICATION.md]
started: 2026-05-13T18:05:00Z
updated: 2026-05-13T18:05:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. BCs tab manual smoke (D-10 whole-body drop overlay)
expected: cd gui && npm run tauri dev → drop Channel, drag from WallTemperature.T_wall_out, expect dashed-outline overlay + 'Connect BC' chip on Channel body, release → dashed BC edge created with targetSide='both'.
result: [pending]

### 2. + New WallTemperature end-to-end (D-20)
expected: Empty canvas → drop Channel (n=12) → select → BCs tab → click Source pill → empty Source-mode dropdown shows '+ New WallTemperature' button → click → new WT node appears ~120px left of Channel, auto-selected in dropdown, dashed BC edge auto-created. The new WT's parameters.n equals 12 (no bc-n-mismatch fires).
result: [pending]

### 3. Visual red-ring on n-mismatch (D-22)
expected: WT(n=10) + Channel(n=12) → connect on canvas → both nodes paint with ring-destructive class visibly red (unit test verifies class application; this confirms CSS resolves to a visible ring).
result: [pending]

### 4. Goal-level decision: do CR-01/CR-02/CR-03 block phase completion?
expected: Owner decides whether the three state-sync gaps (canvas-drag-no-bcMode; symmetric-toggle-left-undefined; symmetric-toggle-source-mode-no-edge-resync) are blocking the v1.2 milestone or can be deferred to a polish/correctness phase. The phase goal specifically lists 'bidirectional sync' as an in-scope deliverable, and CR-01 partially breaks it; CR-02 and CR-03 are narrower transition-only correctness gaps. If deferred, file as a follow-up phase before milestone close.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
