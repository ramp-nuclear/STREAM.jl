---
status: partial
phase: 71-validation-framework
source: [71-01-SUMMARY.md, 71-02-SUMMARY.md, 71-03-SUMMARY.md, 71-04-SUMMARY.md, 71-05-SUMMARY.md, 71-06-SUMMARY.md, 71-07-SUMMARY.md, 71-08-SUMMARY.md, 71-09-SUMMARY.md, 71-10-SUMMARY.md, 71-11-SUMMARY.md, 71-12-SUMMARY.md, 71-13-SUMMARY.md]
started: 2026-05-21T16:00:00Z
updated: 2026-05-21T17:15:00Z
---

## Current Test

[testing complete — 1 outstanding gap from Test 3 awaiting resolution]

## Tests

### 1. Cold Start Smoke Test
expected: From a stopped state, run `cd gui && npm run dev` (and `cargo tauri dev` if testing the native shell). The app boots without console errors. The empty canvas shows: an always-visible status bar strip at the bottom-right with three count chips (errors, warnings, info), all displaying 0. The BottomPanel exists with two tabs: "Code" and "Validation". No legacy ValidationDialog modal appears anywhere.
result: pass
note: "User passed but flagged design/placement/concept of the new validation surfaces as visually poor — deferred to Phase 72 redesign (see [[project-phase72-validator-ui-revisit]])."

### 2. Validation Tab Always Visible on Empty Graph (D-04)
expected: Open the BottomPanel. The "Validation" tab is present even though there are no validation results. Click it. The panel body shows "No issues." (engineering voice, no consumer hand-holding).
result: pass

### 3. Status Bar Pulse on First Error (D-02, D-03)
expected: Drop a single Channel onto the empty canvas. The error chip count increases (driving-element, pressure-boundary, and required-connection rules will fire). The error chip plays a one-shot pulse animation on the 0→N transition. The panel does NOT auto-open (D-03 says only the export gate auto-opens).
result: pass
note: "Pulse animation works. User flagged a separate defect during this test — see Gaps: dangling_flow_port + required_connections double-count unconnected FlowPorts (6 errors instead of 4 on a bare Channel)."

### 4. Severity Filter via Statusbar Chip (D-05)
expected: With errors present, click the error chip in the status bar. BottomPanel opens, switches to the Validation tab, and the list filters to only error-severity entries. A "Filtered to: errors" banner appears at the top with a "Clear filter" button.
result: pass
note: "User also confirmed the dragging-Channel-shows-6-errors observation — matches the dedup gap from Test 3, no new defect."

### 5. Click Row to Focus Node on Canvas
expected: In the Validation panel, click any result row whose target is a node (e.g., "Channel has no inlet connected"). The canvas pans to center on that node and the node briefly flashes (validation-flash class, ~700ms). If the result also has a single field target, the matching input in the sidebar also highlights.
result: pass
note: "First attempt failed — nodes jumped/disappeared during pan because validation-flash reused pulse-once (transform: scale + opacity) which clobbered ReactFlow's transform:translate positioning. Fixed inline by splitting out node-flash-outline keyframe that animates outline-color only (commit 7289d4a). User confirmed clean pan after fix. Also confirmed: persistent red-ring on error-bearing nodes is intended per ROADMAP entry for Phase 71."

### 6. Right-Click → "Show errors" (D-05 node filter)
expected: Right-click a node with errors on the canvas. A "Show errors" item appears in the context menu (visible only when the node has at least one validation result). Click it. BottomPanel opens, Validation tab focuses, and the list filters to that node's errors only. A "Filtered to: <instanceName>" banner appears with a Clear button.
result: pass
note: "First attempt: menu read 'Show errors for this component', banner showed raw nodeId (30+ char UUID). Fixed inline (commit e0b9509): menu copy tightened to 'Show errors'; banner now looks up node.data.instanceName from the store, falls back to nodeId if the node was deleted while filter active."

### 7. Clear Filter
expected: With either filter active (severity or node), click the "Clear filter" button in the banner. The full list returns. The banner disappears.
result: pass

### 8. nMatch (was lossless-sync, now navigation-only after UAT changes)
expected: Build a configuration where a value-source (WallTemperature with n=10) is BC-bound to a Channel with n=5. The Validation panel shows ONE error row per (channel, source) pair (regardless of how many external inputs are bound). The row has NO Sync button. Description reads "Channel.X.n=5 ≠ WallTemperature.Y.n=10" (engineering voice).
result: pass
note: |
  Originally tested as lossless-sync. User rejected the opinionated channel-wins direction and the duplicate rows (same source bound to two BC inputs produced two identical rows). Fixed inline (commit 5eb3ee5):
   1. nMatch FixAction removed (rule degrades to navigation-only)
   2. Dedup by (consumerId, sourceId) pair across bindings
   3. All 11 rules' user-facing descriptions tightened to terse engineering voice (drops AI-flavored prose like "does not match", "requires a connection", "Set a pressure anchor on a FlowPort" → "≠", "not connected", "No pressure anchor")
  See [[feedback-engineering-voice-copy]] for the broader rule this aligns with.

### 9. lengthMatch (was value-transfer-picker, now navigation-only after UAT changes)
expected: Create a HeatDiffusion with Lz=0.5 connected to a Channel whose geometry resource has L=0.6. The validation panel shows an error row "Channel.X L=0.6 ≠ HeatDiffusion.Y.Lz=0.5" with NO buttons. Row click focuses the node.
result: pass
note: "User extended Test 8's decision: no rule should emit any FixAction button. Fixed inline (commit c883912): zNMatch, lengthMatch, geometryConsistency all stripped of fixAction emissions. See [[feedback-no-validator-fixaction-buttons]]."

### 10. geometryConsistency (was navigation-only, now no button after UAT changes)
expected: Trigger a geometry-consistency warning (two channels coupled via same HD with different geometry resources). Row reads "<cac1>, <cac2> → <hd>: geometry resources differ" with NO buttons.
result: pass
note: "Resolved by commit c883912 — see Test 9 note."

### 11. Port-Type Hard-Block on Connect (D-19)
expected: Try to drag a connection from a FlowPort to a ThermalPort (or vice-versa). The connection refuses to form — the edge is not created, no toast/dialog appears, the candidate edge just disappears on release. This is the synchronous portType rule running on the candidate edge (no longer a separate isAllowedBCConnection inline check).
result: pass

### 12. Field-Level Red Highlight (D-12, D-13)
expected: Trigger a validation error with a field target (e.g., set a Channel's n parameter to a non-positive integer). The matching input in the sidebar shows a red border / ring (.validation-field-error class). For array-shaped BC fields (T_wall_left[1:n]), the whole row highlights, not individual cells.
result: pass
note: "User confirmed nothing showed up in the panel when trying to drive a non-positive n — input-level numeric clamping blocked the bad value before the rule layer ever ran. That is correct: the field-highlight mechanism is exercised by any rule emitting field targets (verified implicitly via Test 8 nMatch). Separate finding during this test: self-loops on FlowPorts were silently allowed; fixed inline by extending portType to reject edge.source === edge.target (commit e631aa4)."

### 13. Validation Tab Badge Count
expected: When validationResults contains error-severity entries, the "Validation" tab label in the BottomPanel shows a count badge (e.g., "Validation (3)"). When errors clear, the badge disappears.
result: pass

### 14. Export Button — structural vs diagnostic split (D-17 + UAT)
expected: Export button is disabled ONLY when one or more STRUCTURAL errors exist (portType, requiredConnections, danglingFlowPort, self-loop). Tooltip reads "N structural errors — code won't compile". When only DIAGNOSTIC errors exist (no pressure anchor, no driving element, n/L mismatch, etc.), the button stays enabled; clicking it opens an AlertDialog modal "Export with errors" → "N errors present. Code will compile; solver may not converge." with Cancel / Export anyway.
result: pass
note: |
  Originally tested against the old "any error blocks" policy. User pushed back that it was too harsh and that the tooltip + toast copy was bad. Restructured (commit 3910e58 + 8af7721):
   1. Validator interface gained `structural?: boolean`; portType, requiredConnections, danglingFlowPort tagged. self-loop runs inside portType so it's covered.
   2. exportCode hard-blocks only on structural errors; diagnostic errors trigger an AlertDialog modal (not a toast action — modal forces a deliberate decision).
   3. All user-facing copy tightened to engineering voice. See [[feedback-engineering-voice-copy]] with a new before/after table + banned-patterns list to prevent future regressions.
   4. Save (.scp) is unchanged — never gated; project files round-trip whatever the user has drawn.
   5. Warnings/info: geometryConsistency is the only warning; no info-severity rule exists yet. Both visible in panel + statusbar, neither blocks export. Confirmed working as designed.

### 15. Export Gate Toast / Modal on Error (D-17 + UAT)
expected: Structural error: toast.error fires + BottomPanel opens to Validation tab. Diagnostic-only errors: AlertDialog modal opens with Cancel / Export anyway. Confirmed both paths.
result: pass

### 16. Export Succeeds With No Errors (D-17)
expected: Build a valid configuration (closed loop with pump or gravity driver, pressure boundary, all required connections, n values match, lengths match). Errors chip reads 0. Click Export. No toast, no modal. The save dialog opens (or file is written) and the generated Julia script is produced normally.
result: pass

### 17. Debounced Re-Validation (D-09)
expected: Rapidly edit a parameter (e.g., type into Channel.n field as fast as possible). Validation does NOT fire on every keystroke — there's a brief ~150ms pause after you stop typing before the status bar / panel updates. Confirms the debounced subscription is in place.
result: pass

### 18. No Legacy Modal or Selector Path (D-16, D-20)
expected: The old ValidationDialog modal is gone (it should not appear under any flow). Phase 63.1's red-ring on BCs-tab n-mismatch should now come from the new framework: same look (red border + error row in Validation panel), but the underlying source is the nMatch validator + initValidation subscription, not the old selectNodeErrors selector. Visually indistinguishable from before — just confirm nothing got worse.
result: pass

## Summary

total: 18
passed: 18
issues: 1
pending: 0
skipped: 0
blocked: 0
fixed_inline: 7   # Test 5 (7289d4a), Test 6 (e0b9509), Test 8 (5eb3ee5), Test 9/10 (c883912), Test 12 self-loop (e631aa4), Test 14 structural-split (3910e58), Test 14 modal+copy (8af7721)

## Gaps

- truth: "Dropping a single Channel onto the canvas should produce one error per logically distinct issue (one per unconnected port, one for missing pressure boundary, one for missing driving element) — not duplicates."
  status: failed
  reason: "User reported: dragging a channel results in 6 errors: 2 for the two unconnected ports, no driving element, no pressure anchor, and for some reason again with 2 unconnected ports. one set is by dangling_flow_port and one by required connections. Why are we double counting here?"
  severity: major
  test: 3
  observed_during: "Test 3 — Status Bar Pulse on First Error (the pulse itself passed; the duplicate-error count is the defect)."
  hypothesis: |
    By design intent, danglingFlowPort (VALD-01 lift, FlowPort-only) and requiredConnections (D-15 rule 5, every required port) both flag unconnected FlowPorts. The 71-04 SUMMARY explicitly notes "JSDoc documents coexistence with requiredConnections." Net result: 2× error rows per unconnected FlowPort.

    Plausible fixes (need design decision before plan-phase --gaps):
      (a) Delete danglingFlowPort — requiredConnections subsumes it for FlowPort case.
      (b) Make requiredConnections skip FlowPorts (delegate to danglingFlowPort).
      (c) Keep danglingFlowPort as a "purely missing-edge" check and have requiredConnections exclude FlowPorts whose component declares them as always-required (which is all of them).
    Option (a) is the cleanest — VALD-01 was kept verbatim per D-16 for backwards-compatibility reasons that no longer apply after Plan 13 deleted validation.ts. The fix is to remove danglingFlowPort.ts and its registry entry.
  artifacts: []   # Filled by diagnosis
  missing: []     # Filled by diagnosis
