# Phase 70: Presets and templates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-20
**Phase:** 70-presets-and-templates
**Areas discussed:** Preset storage & discovery, Selection → preset contents, Save / Load UX flow, Manage presets from the toolbox

---

## Pre-discussion — Already locked by §3.14

The design-decisions doc `.planning/notes/gui-redesign-design-decisions.md` §3.14 (Projects and Presets) had already locked the following — no re-discussion needed:

- File format `.scpr` JSON with `format_version`, `kind: "preset"`, `name`, `description`, embedded `resources`, `components`, `connections`, relative `layout`.
- No identity (Option 1, copy-paste templates per issue #14).
- On load: mint-new-UUIDs, smart-name collision handling, auto-create embedded resources, no auto-dedupe-by-content.
- Surfaces: "Save selection as preset…" right-click + File menu; "Load preset…" via File menu + Presets toolbox surface.
- Forward-compatible to passive identity (Option 3) later via UUID + version field.

---

## Area 1 — Preset surfacing (where the Presets UI lives)

User raised a concern with the initial framing: "Both [stores] is a good idea, but it sounds cluttered if you put it in the components tab (or is that wrong? are we adding another tab for presets)". Discussion split into two follow-up questions.

### Surfacing question

| Option | Description | Selected |
|--------|-------------|----------|
| One Presets category w/ sub-headers | Single "Presets" category appended to existing toolbox in Components tab; sub-headers "Project" and "Library" inside. Score: 7.5/10 | |
| Two sibling categories | "Presets (Project)" and "Presets (Library)" as side-by-side top-level categories in Components tab. Score: 8.0/10 | |
| Dedicated Presets tab (4th tab) | New left-panel tab next to Project / Resources / Components. Ctrl+4 binding. Search, store toggles, richer per-entry view. Score: 7.0/10 | ✓ |

**User's choice:** Dedicated Presets tab (4th tab).
**Notes:** This decision technically supersedes the literal "category in the toolbox" wording in §3.14. Semantically identical (presets still live in the left panel, drag-from-toolbox), but on their own tab. The driver was clutter avoidance once a user has 20+ library presets. Recorded in CONTEXT.md D-02 so downstream agents don't trip on the doc.

### Storage question

| Option | Description | Selected |
|--------|-------------|----------|
| Both: project + library | `<project>/presets/*.scpr` (git-shareable) + Tauri `appConfigDir/presets/*.scpr` (cross-project personal). File-system-watched. Score: 8.5/10 | ✓ |
| Library only, v1 | User-global library only; project store deferred. Score: 6.0/10 | |
| Project only, v1 | Project-local only; user library deferred. Score: 5.0/10 | |

**User's choice:** Both stores.
**Notes:** Mapped to CONTEXT.md D-04 (paths), D-05 (file-system watcher with debounce), D-06 (rebind Project store on project switch).

---

## Area 2 — Selection → preset contents

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-extend: pull in BC sources | One-hop extension along BC edges pulls unselected sources (WT, HFS) into the preset; cross-boundary FlowPort/thermal-pair edges drop; resources always embedded. Score: 9.0/10 | ✓ |
| Strict literal: selection only | Selection only; cross-boundary BC edges drop silently; user must lasso sources. Score: 5.5/10 | |
| Refuse to save with boundary warning | Modal per save: include sources, drop edges, or cancel. Score: 6.5/10 | |

**User's choice:** Auto-extend, one hop.
**Notes:** Mapped to CONTEXT.md D-12 (algorithm) and D-13 (one-hop only, not recursive). FlowPort and thermal-pair edges across the boundary drop; BC edges that connect to pulled-in sources stay. The WT-feeds-Channel-A-and-B example explicitly resolves to: pull in WT, drop WT-to-B edge.

---

## Area 3 — Save / Load UX

### Save dialog

| Option | Description | Selected |
|--------|-------------|----------|
| Modal with form: name, description, store | Radix Dialog. Name (text, ASCII validation), Description (textarea), Store (radio: Project / Library, default Library). Score: 8.5/10 | ✓ |
| Native save dialog (Tauri file picker) | OS file picker; description as follow-up modal. Score: 5.5/10 | |
| Inline rename in toolbox | New entry appears in Presets tab in rename mode; description set later via right-click. Score: 6.5/10 | |

**User's choice:** Modal with form.
**Notes:** Mapped to CONTEXT.md D-15 (modal contents) and D-15.1 (save surfaces — right-click on multi-select + File menu).

### Toolbox drop placement

| Option | Description | Selected |
|--------|-------------|----------|
| Bbox-center at cursor | Preset bbox center at the cursor on release; relative layout preserved. Score: 9.0/10 | ✓ |
| Top-left of bbox at cursor | Top-left lands at cursor; bundle offsets down-right. Score: 5.0/10 | |
| First/primary component at cursor | Anchor component at cursor; rest at saved offsets. Score: 6.0/10 | |

**User's choice:** Bbox-center at cursor.
**Notes:** CONTEXT.md D-16.

### File → Load preset placement

| Option | Description | Selected |
|--------|-------------|----------|
| Viewport center | Bbox-centered at the current viewport center. Score: 8.5/10 | ✓ |
| Last-known canvas cursor position | Cached `lastCanvasCursor`; falls back to viewport center if empty. Score: 6.5/10 | |
| Origin (0,0) | Bbox-top-left at canvas origin; user has to hunt. Score: 3.0/10 | |

**User's choice:** Viewport center.
**Notes:** CONTEXT.md D-17.

---

## Area 4 — Manage presets from the toolbox

| Option | Description | Selected |
|--------|-------------|----------|
| Rename + delete + reveal in FS | Three right-click actions; rename updates filename AND `name` field; description edited via re-save. Score: 8.5/10 | ✓ |
| Full edit: rename + delete + edit description + reveal | Same plus dedicated "Edit description" modal. Score: 7.5/10 | |
| Read-only in v1 (manage on disk) | No right-click ops; users edit `.scpr` files in OS file manager / text editor. Score: 5.5/10 | |
| Delete + reveal only (no rename in v1) | Two-action menu; rename via save-as-new-then-delete-old or on-disk edit. Score: 6.5/10 | |

**User's choice:** Rename + delete + reveal in FS.
**Notes:** Mapped to CONTEXT.md D-19 (three actions) and D-19.1 (no "Edit description"; re-save or edit-on-disk is the path).

---

## Claude's Discretion

- Preset tab visual style (density, accent colors): inherits Phase 62 patterns; Phase 72 design audit will sweep.
- Loading state / progress indicators while watcher initializes.
- Tooltip content on Presets tab entries (name + description; planner decides on count/layer metadata).
- Save modal field order and button labels.
- Empty-state copy for each section.
- Drag-image during toolbox drag (generic icon vs mini-render).

## Deferred Ideas

- Passive identity for presets (Option 3 from §3.14) — UUID + version, auto-link, prompt-to-update. Forward-compatible but explicit "wait for the pain" call.
- Auto-dedupe embedded resources by byte-identical content — §3.14 defers; manual merge for v1.
- Preset preview thumbnail in the tab listing — aesthetic; Phase 72 design audit may roll in.
- Dedicated "Edit description" right-click action — dropped from v1 (D-19.1); revisit if friction surfaces.
- Preset categories / tags inside the Presets tab — not v1.
- Bulk operations (multi-select to delete or export) — not v1.
- Import preset from URL / share — not v1.

### Reviewed Todos (not folded)

The four todos surfaced by `todo.match-phase 70` matched on generic keywords ("phase", "design", "selection") but do not intersect Phase 70's scope:

- `gui-visual-design-pass.md` — general visual polish; belongs in Phase 72 (design audit).
- `codegen-resource-naming-dedup.md` — codegen concern; backlog.
- `2026-05-16-phase72-handle-port-visual-rework.md` — explicitly Phase 72.
- `panel-resize-overflow-bounds.md` — layout bug; separate fix.

None folded.
</content>
</invoke>