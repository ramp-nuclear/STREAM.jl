# Phase 33: Project Scaffold - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 33-project-scaffold
**Areas discussed:** Repo location, Which components, Scaffold depth

---

## Repo Location

| Option | Description | Selected |
|--------|-------------|----------|
| gui/ inside Julia-STREAM (monorepo) | Single git history, CLAUDE.md in scope, one PR covers Julia + GUI changes | ✓ |
| Separate sibling repo (~/projects/stream-composer) | Clean separation, own git/CI, more coordination overhead | |

**User's choice:** Plain directory at `gui/` inside Julia-STREAM (monorepo, not submodule)

**Follow-up:** Submodule vs plain directory — user chose plain directory.

---

## Which Components

| Option | Description | Selected |
|--------|-------------|----------|
| All 12 components | Full export list from src/STREAM.jl | ✓ |
| 9 hydraulic only | Exclude ConstantTemperature and HeatDiffusion | |
| 10 (include Friction) | Acknowledge "9" was approximate | |

**User's choice:** All 12 components. User correctly challenged the "9" assumption — registry is data, not rendering, so there's no reason to omit components just because their ThermalPort handles aren't rendered until Phase 40.

**Notes:** The "9" in REQUIREMENTS.md and ROADMAP.md is an undercount. Needs correction. ConstantTemperature placement: canvas node (not BC panel), confirmed by user.

---

## Scaffold Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Foundation: Zustand + panel shells | Store + layout structure set up in Phase 33 | ✓ |
| Minimal: bare canvas only | Just ReactFlow renders; state management left for Phase 34 | |

**User's choice:** Foundation — Zustand store (nodes, edges, selectedNodeId) + three-panel layout shells.

**Follow-up:** Vitest setup — user chose to set up Vitest + React Testing Library in Phase 33 with a registry-loading test as the first test.

---

## Claude's Discretion

- TypeScript configuration
- Package manager (npm vs pnpm)
- Tauri 2 init template choice
- Exact Zustand store shape beyond the minimum
- Registry JSON field names/schema versioning

## Deferred Ideas

- Update REQUIREMENTS.md SCAF-03 and ROADMAP.md to say "12 components" not "9 hydraulic"
- ConstantTemperature as BC panel entry (considered, rejected — canvas node instead)
