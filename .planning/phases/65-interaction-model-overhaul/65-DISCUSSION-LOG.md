# Phase 65: Interaction model overhaul - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 65-interaction-model-overhaul
**Areas discussed:** AutoRecover mechanics, Snap-to-grid surfacing, Context-menu component & disambiguation, Clipboard scope & naming retrofit

---

## AutoRecover mechanics

### Cadence

| Option | Description | Selected |
|--------|-------------|----------|
| Debounced on dirty change | Write ~2s after the last edit while isDirty=true. Cheap, captures real work, no snapshots when idle. Skips if file is being saved this tick. | ✓ |
| Fixed timer (every 30s) | Wall-clock interval regardless of edits. Simpler but wasteful while idle and laggier on bursts. | |
| Both — debounced + safety timer | Debounced on edit, plus a 60s ceiling timer as a backstop. Belt-and-braces; tiny extra complexity. | |

### Crash detection

| Option | Description | Selected |
|--------|-------------|----------|
| Clean-shutdown marker file | Startup writes `running.lock` (with PID); graceful close deletes it. Sidecar + lockfile present at next launch + dead PID → crashed. | ✓ |
| Sidecar presence alone | If a sidecar exists at launch, treat as crash. Simpler but false-positives on concurrent instances or copy-paste of temp dir. | |
| PID-only check | Sidecar header carries last-running PID; if PID is dead at launch, prompt restore. Reliable on Linux/Mac, brittle on Windows PID reuse. | |

### Restore UX

| Option | Description | Selected |
|--------|-------------|----------|
| Modal dialog before workspace loads | Blocking dialog: "Recover unsaved work from <date> in <project>? [Recover] [Discard]". Decision happens before any other interaction — prevents accidental dismissal. | ✓ |
| Non-blocking banner at top of canvas | Yellow banner with Recover / Dismiss buttons; user can keep working. Risk: user clicks Dismiss out of habit and loses work. | |
| Auto-restore + toast | Silently load the recovered state; show a toast "Restored unsaved work from <time> — [Undo]". Most magical but surprises the user if they wanted a clean start. | |

### Untitled-project policy

| Option | Description | Selected |
|--------|-------------|----------|
| Snapshot in temp with synthetic name | Sidecar named `untitled-<uuid>.scp.autosave` in temp. Restore prompt shows "Unsaved project from <time>". User must Save As to make it permanent. | ✓ |
| Skip — only AutoRecover saved projects | If no .scp path is set, do not write sidecar. Simpler but loses brand-new work on crash. | |
| Snapshot but require explicit opt-in via Settings | Toggle defaults off; user can enable "AutoRecover untitled projects." Defers the question to user. | |

### Storage location

| Option | Description | Selected |
|--------|-------------|----------|
| appDataDir/autorecover/ — mirrored basename | Tauri `appDataDir()/STREAM-Composer/autorecover/`. Saved → `<basename>.scp.autosave`; untitled → `untitled-<uuid>.scp.autosave`. Survives reboots, scoped per app, easy to enumerate. | ✓ |
| OS temp dir (Tauri tempDir()) | Per the roadmap text. Truly transient, may be wiped by OS at reboot — less reliable for crash recovery across reboots. | |
| Sidecar next to the .scp file | `project.scp.autosave` next to `project.scp`. Simple discovery for saved projects but breaks for untitled, and clutters the user's project dir. | |

### Recovery scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full .scp content — same as Save | Sidecar IS a normal .scp serialization. Recovery is bit-identical to opening the file. No special path — reuses projectIO.serialize / deserialize end-to-end. | ✓ |
| Data model only — omit UI state | Strip layout block / activeLeftTab / layer view. Keeps sidecar smaller but adds a custom code path that can drift from the canonical schema. | |

**Notes:** Storage choice deviates from the roadmap text's "OS temp dir" wording — `appDataDir` chosen so AutoRecover survives reboots. Captured in CONTEXT.md D-05 with rationale.

---

## Snap-to-grid surfacing

### Toggle UI surface

| Option | Description | Selected |
|--------|-------------|----------|
| Canvas-overlay button only | Toggle button in the existing top-right Controls/MiniMap stack on the canvas. Defer Settings-dialog wiring to Phase 67/72. | ✓ |
| Build minimal Settings dialog now | Stand up a basic Settings modal in Phase 65 with snap-to-grid (and AutoRecover) toggles. Phase 67/72 expands. Bigger Phase 65. | |
| View menu only (waits for Phase 67) | Hold the toggle until Phase 67 builds the menubar with View › Snap to Grid. No canvas-control button. | |

### Grid step size

| Option | Description | Selected |
|--------|-------------|----------|
| 16px fixed | Matches ReactFlow's default Background `gap=16` already used. No UI to expose, behaves visibly aligned to the dotted background. | ✓ |
| 8px fixed | Finer grain, less aggressive snapping. Easier for tiny adjustments but less visible alignment with the dot grid. | |
| 20px fixed | Coarser; more obviously 'snapped' layouts. Doesn't match the current background dot spacing. | |

### Snap timing

| Option | Description | Selected |
|--------|-------------|----------|
| Snap-on-drop only (ReactFlow built-in) | ReactFlow's `snapToGrid` + `snapGrid` props — snaps as user drags AND on drop. Built-in, free. Visually live so user sees alignment forming. | ✓ |
| Snap-on-drop only, free during drag | Custom: smooth drag, only quantize on drag-end. Avoids 'sticky' feel during drag but loses alignment preview. | |

### Default state

| Option | Description | Selected |
|--------|-------------|----------|
| OFF by default | Free positioning unless user opts in. Aligns with 'professional engineering tool' framing. Persisted per-project in `.scp` layout block. | ✓ |
| ON by default | Tidy layouts out of the box. Risk: user fights the snap before discovering the toggle. | |

---

## Context-menu component & disambiguation

### Component choice

| Option | Description | Selected |
|--------|-------------|----------|
| Radix ContextMenu wrapping each node + custom handler for canvas | Reuse the shadcn `ContextMenu` already in `gui/src/components/ui/context-menu.tsx`. Wrap nodes/edges with `<ContextMenuTrigger>`. Canvas right-click fires a custom-positioned Popover. | ✓ |
| Single custom popover at click coords for everything | Manually position a popover at `{clientX, clientY}` from ReactFlow events. More uniform code path but doesn't inherit Radix's focus trap / keyboard nav / dark-mode styling. | |
| ReactFlow events + Radix DropdownMenu via Portal | Use ReactFlow events to capture position, render via Radix DropdownMenu programmatically. Compromise — keyboard nav for free but no native ContextMenu UX. | |

### Pan-vs-menu disambiguation

| Option | Description | Selected |
|--------|-------------|----------|
| 5px movement threshold | Track `mousedown` coords on right-button; if `mouseup` is within 5px AND under 250ms, fire context menu. Otherwise pan. Tolerates micro-jitter. | ✓ |
| 3px movement threshold (strict) | Tighter. Risk of accidentally classifying jittery clicks as pans, especially on trackpads. | |
| ReactFlow built-in panOnDrag=[2] + onPaneContextMenu | Use ReactFlow defaults: both fire — we'd still need to suppress the menu after a non-trivial pan ourselves. | |

### Mac ctrl-click

| Option | Description | Selected |
|--------|-------------|----------|
| Inherit OS native behavior | Don't intercept. Browser already converts ctrl-click to a right-click event. Trackpad pan is two-finger, not ctrl-click — no conflict. | ✓ |
| Explicitly disable ctrl-click → context menu | Prevent the right-click event when ctrlKey is true. Requires Mac users to use two-finger trigger or right-click on a mouse. Fights the OS. | |

### Action scope

| Option | Description | Selected |
|--------|-------------|----------|
| Match §3.5 spec exactly — stub deferred items | Full menu inventories per §3.5. 'Auto-Layout (future)' grayed-out. 'Show errors' hidden until Phase 71 lights up. | ✓ |
| Bare minimum — Delete + Duplicate + Paste only | Defer Rename / Show code / Show errors / Add-Component-submenu to later phases. Smaller surface but immediately misses obvious affordances. | |

**Notes:** Initial question batch was rephrased after the user asked for clarification on what we were discussing; no decisions changed, only the prose was simplified. Final answers as recorded above.

---

## Clipboard scope & naming retrofit

### Clipboard scope

| Option | Description | Selected |
|--------|-------------|----------|
| OS clipboard via JSON | Serialize to JSON and write to `navigator.clipboard.writeText`. Cross-window paste between two STREAM Composer windows works. Tauri webview supports the Clipboard API natively. | ✓ |
| In-app Zustand-only | Store payload in a `clipboard` slice of useStore. Simpler. Cross-window paste won't work. Loses payload on app restart. | |
| OS clipboard with a magic prefix | Same as option 1 but with `__STREAM_COMPOSER_CLIPBOARD__::` prefix. Defensive against pasting random copied text. | |

### Naming retrofit

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — unify on lowest-free everywhere | Replace `getNextInstanceName` with a lowest-free scan mirroring `nextResourceName` from Phase 62. One naming algorithm, one mental model. | (subset of next ✓) |
| No — keep toolbox at next-after-highest, paste uses lowest-free | Two algorithms coexist. Less code change, but §3.5 explicitly says lowest-free applies to fresh toolbox drops too. | |
| Yes — lowest-free everywhere AND drop the module-level counter | Same as option 1, plus delete the `instanceCounters` module variable. Cleaner, removes hidden state desync after undo/load. | ✓ |

### Paste cross-component-type behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Paste preserves component types as-is | A copied `Channel` pastes as a `Channel`; resource references kept intact (per §3.5). External edges silently dropped. Internal edges rewired to new UUIDs. | ✓ |
| Same as above + warn when dropping external edges | Spec behavior plus a non-blocking toast: 'N connections to external components were dropped during paste'. | |

### Ctrl+D path

| Option | Description | Selected |
|--------|-------------|----------|
| Separate code path — doesn't touch clipboard | Ctrl+D = serialize+deserialize selection in-memory with new UUIDs and +20px offset. Leaves OS clipboard alone. | ✓ |
| Literal copy+paste — overwrites OS clipboard | Ctrl+D writes to clipboard then immediately reads back. Simpler implementation but trashes whatever the user had on the clipboard. | |

---

## Claude's Discretion

- File layout for new modules (`gui/src/lib/clipboard.ts`, `gui/src/lib/autoRecover.ts`, context-menu module locations) — planner picks.
- Exact wiring of the right-click 5px/250ms threshold (custom hook vs inline handler) — planner picks.
- Test surface — vitest unit tests for naming, serialize/deserialize round-trip; component tests for context menu and restore modal; manual UAT for crash detection.
- Whether `running.lock` is JSON or `<pid>\n<iso8601>` — implementation detail.

## Deferred Ideas

- Right-click context menus on side-panel rows (BC rows, Resource rows) — flagged by Phase 63.1 as Phase-65 candidate, kept deferred to Phase 72 design-system audit.
- Cross-app clipboard interop (paste from drawio etc.) — door open, not in scope.
- Settings dialog — Phase 67/72.
- Auto-Layout (full-graph reflow) — grayed-out menu stub only.
- AutoRecover history / multiple sidecars — overwrite-in-place in v1.2.
- AutoRecover for in-flight Julia simulation runs — out of scope.
- User-tunable debounce / grid step size — fixed in v1.2.
- Per-canvas / per-selection snap toggle — global per-project only.
- OS clipboard payload validation prefix — rejected; JSON parse + shape-check is sufficient.
- Active error indicators on components (vs passive context-menu surfacing) — Phase 71's job.
