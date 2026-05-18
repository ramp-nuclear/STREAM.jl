---
status: partial
phase: 69-command-palette-jump-only
source: [69-VERIFICATION.md, 69-UAT-CHECKLIST.md]
started: 2026-05-18T21:30:26Z
updated: 2026-05-18T21:30:26Z
---

## Current Test

[awaiting human testing — run `cd gui && npm run tauri dev` then tick rows below]

## Tests

### 1. D-01 audit artifact inspection
expected: `69-CMDK-AUDIT.md` exists with `Audit verdict: PASS`
result: [pending]

### 2. Ctrl+P opens top-anchored overlay — D-02
expected: Palette appears top-anchored (~80px from top), ~640px wide, dimmed backdrop, input auto-focused
result: [pending]

### 3. Click-outside dismisses palette — D-02
expected: Clicking outside the palette closes it
result: [pending]

### 4. Esc dismisses palette AND pinned code-preview state UNCHANGED — D-02 + Pitfall 6 / P3
expected: Pin a code block first (right-click → Pin Code), open palette, press Esc — palette closes; pinned bottom-panel code-preview blocks survive
result: [pending]

### 5. Off-layer chip rendering — D-03 + D-08
expected: After toggling Hydraulic OFF, the pump row shows blue (#3b82f6) chip with text "Hydraulic off — will enable"
result: [pending]

### 6. Off-layer auto-enable on select — D-03
expected: Clicking off-layer pump row re-enables Hydraulic layer visibly in LayersPanel + selects pump
result: [pending]

### 7. setCenter + zoom floor at low zoom — D-04
expected: Canvas zoomed way out then jump to component → re-centers and zooms IN to 0.75 floor; node selected with ring
result: [pending]

### 8. setCenter preserves zoom when above floor — D-04
expected: Canvas at zoom ~1.5 then jump → preserves 1.5, does not drop to 0.75
result: [pending]

### 9. Project Options selection — D-05
expected: Click "Project Options" row → left tab switches to Project, ModelOptionsPanel visible, palette closes
result: [pending]

### 10. Jump-to-resource — D-06
expected: Select geometry resource → tab switches to Resources, matching ResourceRow scrolled into view (centered) + highlighted as selected
result: [pending]

### 11. No matched-character highlighting — D-07
expected: Typing "ch" against `heated_channel` row shows plain text — no bold/underline of "ch"
result: [pending]

### 12. Per-layer accent color comparison — D-08
expected: Hydraulic-off chip (blue #3b82f6) vs Thermal-off chip (amber #f59e0b) visibly differ
result: [pending]

### 13. Pitfall 1 — no native Print dialog leak — P1
expected: Pressing Ctrl+P with devtools open shows ONLY the palette; no browser/OS Print overlay flashes. Also try Ctrl+P while a Ctrl+S save dialog is awaiting IPC (Linux/GTK) — Print must still not leak (CR-02 fix)
result: [pending]

### 14. Pitfall 2 — no useReactFlow provider error — P2
expected: Console clean when opening palette; no "useReactFlow can only be used inside a ReactFlowProvider" error
result: [pending]

### 15. Pitfall 4 — single hoisted @radix-ui/react-dialog — P4
expected: `npm ls @radix-ui/react-dialog` reports a single version, no duplicate-instance warnings
result: [pending]

### 16. Browse-mode grouping — B1
expected: Empty input → groups appear in order Components / Geometries / Power Shapes / Fluids / Project; empty groups hidden
result: [pending]

### 17. Typed-mode flat list — B2
expected: Typing any char → group headings disappear; flat ranked results (cap 50)
result: [pending]

### 18. Ctrl+Shift+P NOT intercepted — B3
expected: Pressing Ctrl+Shift+P does NOT open the palette
result: [pending]

### 19. Ctrl+P in input swallows Print without toggling palette — B4
expected: Cursor in ModelOptions name input + Ctrl+P → no Print dialog, no palette toggle, cursor stays in input
result: [pending]

## Summary

total: 19
passed: 0
issues: 0
pending: 19
skipped: 0
blocked: 0

## Gaps
