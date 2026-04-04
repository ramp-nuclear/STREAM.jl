---
phase: 36-code-generation
plan: 03
subsystem: uat
tags: [verification, human-uat, code-generation]

provides:
  - Human verification of complete Phase 36 code generation feature
affects: []

key-files:
  created: []
  modified: []
---

## Summary

Human UAT passed for all Phase 36 features. One export bug found and fixed during verification.

## Tests Run

| # | Test | Result |
|---|------|--------|
| 1 | Empty canvas → placeholder comment, Export disabled | ✓ Pass |
| 2 | Pump+Channel loop → valid STREAM.jl code preview | ✓ Pass |
| 3 | BC editing: add/delete, appears in code | ✓ Pass |
| 4 | Parameter change reflected in code preview | ✓ Pass |
| 5 | Export via native file dialog | ✓ Pass (after fix) |
| 6 | Node deletion cleans up BCs | ✓ Pass |
| 7 | Default parameter elision | ✓ Pass |

## Issues Found During UAT

1. **Export silently failed** — `fs:default` permission only grants read access to app directories. Fixed by adding `fs:allow-write-text-file` + `fs:scope-home-recursive` to capabilities.
2. **Code button had no clear hover state** — Fixed: changed from `ghost` to `outline`/`default` toggle.
3. **Connection edges crossed in loops** — Fixed: switched to `smoothstep` edge type which routes around loop geometry.
4. **BC delete button far from text** — Fixed: BC rows are now compact inline pills instead of full-width rows.

## Deferred to Backlog

- Edge handle cursor glitches (React Flow internals) — `.planning/BACKLOG.md`
- Resizable panels — `.planning/BACKLOG.md`
