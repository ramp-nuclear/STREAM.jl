---
status: passed
phase: 41-layered-canvas
source: [41-VERIFICATION.md]
started: 2026-04-03T21:30:00Z
updated: 2026-04-03T22:00:00Z
---

## Current Test

Approved by user 2026-04-03

## Tests

### 1. Hydraulic View — Thermal Node Dimming
expected: HeatDiffusion node dims to ~20% opacity and cannot be clicked to select when in Hydraulic view
result: passed

### 2. Thermal View — Hydraulic Node Dimming
expected: Pump/Channel nodes dimmed; toolbox shows only Thermal components in Thermal view
result: passed

### 3. ChannelAndContacts Per-Handle Dimming (Thermal view)
expected: Node at full opacity; FlowPort handles faded (0.2); ThermalPort handles fully opaque
result: passed

### 4. ChannelAndContacts Per-Handle Dimming (Hydraulic view)
expected: Node at full opacity; ThermalPort handles faded (0.2); FlowPort handles fully opaque
result: passed

### 5. Edge Layer Dimming
expected: Amber (thermal) edges at 0.15 opacity in Hydraulic view; blue (flow) edges at 0.15 in Thermal view
result: passed

### 6. Tab Key Layer Cycling
expected: Tab on canvas background cycles Hydraulic→Both→Thermal→Hydraulic; Tab inside a text input does NOT cycle
result: passed

### 7. activeLayer Persistence Round-Trip
expected: Save with Thermal active → reopen → Thermal still active; .streamgui file contains version:2 and activeLayer:"Thermal"
result: passed

### 8. Toggle Button Active State Colors
expected: Hydraulic button shows blue tint (bg-blue-500/15) when active; Thermal shows amber tint (bg-amber-500/15) when active
result: passed

### 9. Dimmed Nodes Cannot Be Selected
expected: Clicking a dimmed (off-layer) node does not open the sidebar or select the node
result: passed

## Summary

total: 9
passed: 9
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
