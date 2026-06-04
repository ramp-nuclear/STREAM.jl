# Phase 62: Resources panel architecture - Research

**Researched:** 2026-05-13
**Domain:** GUI architecture refactor (zustand store, React component decomposition, Radix UI primitives, Tauri file I/O, Julia source-helper + codegen)
**Confidence:** HIGH (codebase + design-doc grounding); MEDIUM only on the precise visual layout choices that CD-01..CD-05 explicitly leave to the planner

## Summary

Phase 62 is a structural refactor of the STREAM Composer GUI, not a new feature. The user has already locked the architecture in `62-CONTEXT.md` D-01 through D-30 + CD-01 through CD-05. The research job here is to map each locked decision onto the existing GUI surface — what code becomes a router, what is a new slice, which Radix primitive is the right anchor, where the codegen seam must be cut, and what test invariants gate the work.

Three big technical risks dominate planning quality:

1. **Resource-typed parameter shape on Component schemas.** The Phase 61 registry still spells the picker-bound field `type: "PipeGeometry"` (`components.json` line 24) and `type: "Matrix"` (line 983), NOT a new `"ResourceRef"` type. Phase 62 must decide (and the planner must say so explicitly) whether to reinterpret these existing type tags as Resource-FK markers OR to introduce a separate `"ResourceRef"` parameter type. Either choice is fine; ambiguity is not.
2. **Undo discipline with the new Resources slice.** The store does NOT use the `zundo` middleware that `package.json` advertises; `useStore.ts:211` implements an explicit `_pushSnapshot` discipline. Every Resource mutation (create / rename / update / delete) must extend this snapshot to keep undo/redo coherent across canvas+resource ops. This is a one-line discipline once you know it, and a silent correctness bug if you miss it.
3. **Hard cutover, not migration.** D-28 explicitly deletes the 5 stale `.streamgui` files and removes the v1/v2 migration shim in `projectIO.ts:87`. The "version" field semantics changes from numeric `1|2` to `format_version: "2.0"` string. The deserialize path stops being defensive and starts being strict.

**Primary recommendation:** Plan in three horizontal waves with the second wave parallelizable:

- **Wave 1 (sequential foundation):** Resources zustand slice + ModelOptions slice + activeLeftTab state + projectIO v2.0 rewrite + Tauri filter swap + `src/utilities.jl` (rebin_extensive + cosine_power_shape) + `test/test_utilities.jl` + STREAM.jl exports. (Library + state layer; no UI.)
- **Wave 2 (UI surfaces, parallelizable):** (a) shadcn `Popover` and `ContextMenu` shims under `gui/src/components/ui/`. (b) Left-panel `<Tabs>` shell + Resources tree + Project (Model Options) form body. (c) Refactor `PipeGeometryPicker` into `<GeometryResourceEditor>` + new `<PowerShapeResourceEditor>` + new `<ResourceReferencePicker>`. (d) `SidebarPanel` selection-kind router (CD-05).
- **Wave 3 (codegen + cutover):** Rework `codeGenerator.ts` to emit Resources block at top + lookups in component constructors + `rebin_extensive` call for `file_loaded`. Delete stale `.streamgui` files. Ship 1-2 fresh `.scp` examples. Wire `Ctrl+1/2/3` keyboard. Wire `Edit…` jump from picker to Resources tab.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Resource CRUD (create/rename/update/delete) | Frontend state (zustand store) | — | UUID-keyed records live entirely in browser memory; persisted by serialize on save |
| Reference resolution (component → resource name display) | Frontend render (React) | — | Lookup by UUID at render time; no caching needed |
| `.scp` file persistence | Frontend state ↔ Tauri filesystem | Tauri plugin-fs | `useStore.ts` orchestrates; `projectIO.ts` is pure serialize/deserialize; Tauri `writeTextFile` does the I/O |
| Resource-aware codegen | Frontend pure function (`codeGenerator.ts`) | — | Pure string emission; runs at "Code Preview" render time, not at save |
| `rebin_extensive` runtime regrid | Julia source (`src/utilities.jl`) | — | Runs at the user's `julia script.jl` invocation, NOT in the GUI process; the GUI only emits the call site |
| Power Shape recipe → matrix realization | Julia runtime | — | Materialization happens in the user's Julia script; the GUI stores only `{kind, params}` |
| Anchored popover for `+ New…` | Frontend UI (Radix `Popover`) | — | Browser DOM, headless primitive with `onInteractOutside` preventDefault |
| Undo/redo over Resource ops | Frontend state (`_pushSnapshot` extension) | — | Same explicit-history pattern that `useStore.ts:211-249` uses for canvas nodes/edges/bcs |

## User Constraints (from CONTEXT.md)

### Locked Decisions

Verbatim from `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` `<decisions>` block, D-01 through D-30. Reproduced as a single canonical reference for the planner; full annotations live in the source file.

**Shell layout — Pattern F (tabbed left panel):**
- **D-01:** Left panel keeps width/home, gains text-only tab strip `[Components] [Resources] [Project]`. Components default on cold start / new project; active tab persisted per project.
- **D-02:** Components tab body reuses today's `ToolboxPanel.tsx` unchanged (Hydraulic / Thermal / Sources / Reactor Physics drag sources, layer-filtered via existing `isComponentVisibleInLayer`). Drag flow unchanged.
- **D-03:** Resources tab body is a tree with three group headers (Geometries / Power Shapes / Fluids). Each header has trailing `+`. Each row: inline rename (F2 / double-click), context menu (Rename / Duplicate / Delete / Show usages), top search box. Flat-per-group, no nested rows. Fluids is placeholder-only (single non-editable `light_water` row).
- **D-04:** Project tab body IS the Model Options form (no inner selection). Fields: Name (string), Description (multi-line), Default fluid (read-only "water"), Default g (Real, default 9.80665), Solver defaults (planner TBD — see CD-04).
- **D-05:** Right Properties panel = router by selection kind. Three exclusive scopes: canvas node, resource row, project tab. Selecting in one clears the others. Esc clears.
- **D-06:** Right panel header text varies: `Properties` (component), `Geometry: <name>` / `Power Shape: <name>` (resource), `Project Options` (singleton). Single header component reads the discriminator.
- **D-07:** Keyboard: `Ctrl+1` Components, `Ctrl+2` Resources, `Ctrl+3` Project. NOT `Ctrl+Tab` (browser collision). Existing `App.tsx` bindings undisturbed.
- **D-08:** Active tab written to `.scp` `layout.active_left_tab`. Restored on load. Default `"Components"`.

**Foreign-key model + resource store:**
- **D-09:** Components reference Resources by stable UUID in fields named `<kind>_ref` (`geometry_ref`, `power_shape_ref`). No inline representation exists for these fields.
- **D-10:** Resource store is a new zustand slice (or extension) shaped as `{ geometries: Record<uuid, Geometry>, powerShapes: Record<uuid, PowerShape>, fluids: Record<uuid, Fluid> }`. Keyed by UUID. Names per-resource; uniqueness per kind.
- **D-11:** UUID strategy: planner picks (uuid v4 default; nanoid acceptable). Minted at Resource creation, never reused.
- **D-12:** Rename propagation is automatic by construction (lookup-at-render). No "broken refs" state exists.
- **D-13:** Copy-paste preserves FK (does NOT duplicate Resource). Smart-name-increment applies to component instance name only.

**Reference picker UX:**
- **D-14:** Dropdown (resources of the right kind) + `+ New…` + `Edit…`. `Edit…` disabled when no selection.
- **D-15:** `+ New…` opens **anchored popover** at the field. Contains name field (auto-suggested per D-19), kind selector where applicable, kind-specific numeric fields. `Create`/Enter creates + auto-selects + closes + moves focus to next Channel field. `Cancel`/Esc closes without creating.
- **D-16:** Popover does NOT dismiss on click-outside. Only Esc, Cancel, or successful Create dismisses.
- **D-17:** Popover anchors right of dropdown if room in Properties panel; otherwise overlaps canvas to left. Fixed width (~280px is the natural fit; planner finalizes).
- **D-18:** `Edit…` switches left tab to Resources, selects the row, right panel switches to its editor. Return is one click on the canvas node. No "Back" breadcrumb.
- **D-19:** Auto-suggested Resource name follows §3.5 smart-name-increment scoped per kind: `geometry_<lowest-free-integer>`, `power_shape_<lowest-free-integer>`. Names are valid Julia identifiers (ASCII). User can edit before Create; uniqueness validated on submit.
- **D-20:** Empty-state copy: `No geometries yet — click + New… or open the Resources tab.` / `No power shapes yet — …`. Italicized single line.

**Power Shape Resource semantics — recipe model:**
- **D-21:** Power Shape Resources store `{ kind, params }`, NOT a `[nz, nx]` matrix. Codegen emits a STREAM.jl call taking consumer's `(nz, nx)` at script runtime. Reusable across multiple HeatDiffusions.
- **D-22:** Four kinds:
  - `uniform` — no params. Codegen: `power_shape = ones(nz, nx)` (or a `STREAM.uniform_power_shape(nz, nx)` helper — planner decides).
  - `z_cosine` — `amplitude` / `peaking_factor` (Real, default 1.0). Uniform along x, cosine along z. Mirrors Python `uniform_x_power_shape`. Codegen: `STREAM.cosine_power_shape(nz, nx; amplitude)` helper in `src/utilities.jl`.
  - `file_loaded` — `path` relative to `.scp` location. Codegen uses `rebin_extensive` (D-25).
  - `unset` — no params. Codegen: `power_shape = ones(nz, nx)  # TODO: fill in your power shape`.
- **D-23:** `file_loaded` file format: CSV only for v1.
- **D-24:** `file_loaded` storage in `.scp`: relative path, NOT embedded. On file-not-found at load: user-visible error with `Locate file…` action.
- **D-25:** `rebin_extensive` helper in **new** `src/utilities.jl`. Conservative area-weighted regridding; preserves `sum(out) ≈ sum(in)` to floating-point precision. Separable algorithm (z then x). Public, exported from `STREAM.jl`. Tested in `test/test_utilities.jl` (sum-conservation across upsampling / downsampling / non-integer / identity). Codegen for `file_loaded`:
  ```julia
  power_shape_mtr = rebin_extensive(
      readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','),
      (nz, nx),
  )
  ```
  Rebin runs at script runtime. Visible in generated code, not hidden — caller-trust posture.
- **D-26:** `unset` picker UX: fixed top entry `(leave unset — fill in code)` above named Power Shapes. Selecting it is a real persistent choice (FK is `<uuid-of-the-unset-singleton>` OR a sentinel — planner decides). Codegen emits `ones(nz, nx)` + `# TODO` comment.

**`.scp` file format + cutover:**
- **D-27:** Extension `.scp`. `format_version: "2.0"`. Schema per §3.2.
- **D-28:** Hard cutover from `.streamgui`. No migration shim. Rename `projectIO.ts`, `useStore.ts`, error strings, Tauri filter, tests. Delete the 5 stale `gui/export_examples/*.streamgui` files (predate v1.1; won't load anyway). Ship fresh `.scp` examples.
- **D-29:** `layout` block carries canvas positions + view state + `active_left_tab` (D-08). Layout-only edits do not dirty the simulation-relevant diff.

**Sources toolbox category:**
- **D-30:** Ship Sources category header in Components tab. Visible structure: `Hydraulic / Thermal / Sources` (Reactor Physics later). Sources empty until Phase 63. No inert affordances in 62.

### Claude's Discretion

- **CD-01:** Tree widget choice (hand-rolled `<ul>` vs `react-arborist`). Hand-rolled likely simpler given shallow shape and §3.8 restraint.
- **CD-02:** Popover primitive (Radix `Popover` vs custom). Radix likely match given shadcn surface. Non-dismiss-on-click-outside is the only non-default knob.
- **CD-03:** UUID lib (`uuid` v4 vs `nanoid`). v4 the default.
- **CD-04:** Solver-defaults field set in Model Options (`abstol`, `reltol`, `dtmax` are the natural minimum). Planner asks if unclear.
- **CD-05:** `SidebarPanel` refactor shape — per-selection-kind switcher with sub-components vs grow existing file with conditional rendering. Selection-kind router pattern is what matters.

### Deferred Ideas (OUT OF SCOPE)

- Embed-in-`.scp` mode for file-loaded Power Shapes (path-reference only for v1)
- Power Shape file formats beyond CSV
- Resources / Reactivity Controllers tree group (deferred to PK GUI integration)
- "Show usages" visualization beyond a simple list (in scope as a context-menu action only)
- `.scpr` presets format + Save-selection-as-preset + Presets toolbox (Phase 70)
- Resource "Embed" / "Re-link to source file" toggles
- Auto-interpolation / bilinear smoothing alternatives to `rebin_extensive`
- Multi-fluid Fluids group beyond placeholder
- Right-panel "Back to <component>" breadcrumb after `Edit…` jump
- `Ctrl+Tab` as left-tab switcher
- Project tab as a selectable entry vs the form itself

## Phase Requirements

Phase 62 has no formally enumerated `REQ-XX` IDs in `REQUIREMENTS.md` (which still scopes v1.1 only). The CONTEXT.md `<decisions>` block (D-01..D-30 + CD-01..CD-05) is authoritative.

| ID | Description | Research Support |
|----|-------------|------------------|
| D-01..D-08 | Shell layout, tabs, keyboard, persistence | Radix `Tabs` already present (`tabs.tsx`); `crypto.randomUUID()` already in use (`useStore.ts:304`); `_pushSnapshot` extension pattern documented |
| D-09..D-13 | FK model + resource store | New zustand slice shape; `useStore.ts:211` snapshot discipline must extend |
| D-14..D-20 | Reference picker UX | `@radix-ui/react-popover@1.1.15` already in lockfile via `radix-ui`; `onInteractOutside` preventDefault is the documented Radix mechanism |
| D-21..D-26 | Power Shape recipe + rebin | Python `uniform_x_power_shape` lines 297-335 as reference; `src/utilities.jl` is a NEW file under the per-file test rule |
| D-27..D-29 | `.scp` format + hard cutover | `projectIO.ts:69` v1→v2 migration shim is the locus that gets stripped, not extended; current Tauri filter at `useStore.ts:516,547` is the rename surface |
| D-30 | Sources category placeholder | `ToolboxPanel.tsx:11-21` uses `getComponentsByCategory("Sources")` — registry already has `WallTemperature` and `HeatFluxSource` in that category; rendering it shows the empty group until Phase 63 wires the drag-from-toolbox behavior. The Phase 61-05 deferred-items list confirms Sources visibility is Phase 62's job. |

## Project Constraints (from CLAUDE.md)

These directives are AS authoritative as locked decisions. Plans MUST honor them.

- **Branching policy:** GSD never creates branches. Working branch is `gui-redesign`. `.planning/config.json` `git.branching_strategy` MUST stay `"none"`. Verify `git rev-parse --abbrev-ref HEAD` is `gui-redesign` before committing.
- **File structure standard:**
  - New `src/utilities.jl` follows the "new component file → new test file" rule with `test/test_utilities.jl`.
  - All public exports go in `src/STREAM.jl`. Never add `export` inside component files. Add `rebin_extensive` and `cosine_power_shape` to the export list there.
- **Daemon dev loop:** `bin/jl test/runtests.jl` is the primary runner. Worktree-isolated executors bypass the daemon and use cold-start `julia ...`.
- **Component authoring:** Keyword-only `name` (provided by `@named`). Internal helpers prefixed `_` and not exported. Every exported name has a docstring with description / Arguments / Returns.
- **MTK patterns:** `@register_symbolic` for opaque fluid functions; `ifelse()` for symbolic conditionals; `vars=[]` when state is auto-promoted; `@observed` for diagnostic quantities. (Phase 62 touches MTK lightly — `rebin_extensive` is a pure-Julia function, not a `@named` component, so MTK patterns don't apply to the new file.)
- **ASCII-only Julia identifiers** (memory `feedback_ascii_variable_names.md`). Auto-suggested Resource names (D-19) must be valid Julia identifiers; the smart-increment rule already enforces this.
- **Caller-trust on power_shape** (memory `feedback_power_shape_trust_caller.md`). `rebin_extensive` must NOT normalize, validate, or assert; trust the caller. `[CITED: feedback_power_shape_trust_caller.md]`

## Standard Stack

### Core (already in place — Phase 62 reuses)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `zustand` | `^5.0.12` | State store | Already the project's state primitive (`useStore.ts:1`); explicit `_pushSnapshot` pattern instead of zundo middleware (see store comment at line 200-206) |
| `@xyflow/react` | `^12.10.2` | Canvas | Phase 62 does NOT change canvas interaction (out of scope per Phase 65) |
| `radix-ui` (meta) | `^1.4.3` | Headless primitives | `@radix-ui/react-popover@1.1.15` and `@radix-ui/react-context-menu@2.2.16` transitively present in lockfile lines 1410-1843. No new install needed. |
| `@tauri-apps/plugin-fs` | `^2.4.5` | File I/O | Already used at `useStore.ts:484, 523, 569` |
| `@tauri-apps/plugin-dialog` | `^2.6.0` | Open/Save dialogs | Already used at `useStore.ts:493, 514, 544` — filter extension changes from `streamgui` to `scp` |
| `vitest` | `^4.1.2` | Test runner | Existing GUI test framework (`gui/src/{components,lib,store,registry}/__tests__/`) |
| `@testing-library/react` | `^16.3.2` | Component tests | Existing pattern in `PipeGeometryPicker.test.tsx`, `SidebarPanel.test.tsx` |

### Supporting (new shims to add)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Local `gui/src/components/ui/popover.tsx` (new) | — | shadcn wrapper around `radix-ui` `Popover` | The `+ New…` anchored popover (D-15). Pattern matches existing `tabs.tsx`, `scroll-area.tsx` (both import from `"radix-ui"` aggregator, not the per-package npm name). |
| Local `gui/src/components/ui/context-menu.tsx` (new) | — | shadcn wrapper around `radix-ui` `ContextMenu` | Per-row Resources context menu (D-03): Rename / Duplicate / Delete / Show usages. |

**Verification of Radix Popover availability** `[VERIFIED: package-lock.json grep lines 1410, 1841]`:
- `@radix-ui/react-popover` 1.1.15 — transitively pinned via `radix-ui@1.4.3`
- `@radix-ui/react-context-menu` 2.2.16 — same

No `npm install` required. The shims import from the `radix-ui` aggregator namespace, matching the project's existing shadcn convention (`scroll-area.tsx:2`: `import { ScrollArea as ScrollAreaPrimitive } from "radix-ui"`).

### UUID generation `[VERIFIED: useStore.ts:304]`

`crypto.randomUUID()` is already used for node IDs. **Recommendation: use `crypto.randomUUID()` for Resource UUIDs too.** No new dependency. Web Crypto API is available in Tauri WebView. (CD-03 says uuid v4 default acceptable; `crypto.randomUUID()` IS uuid v4 by spec.)

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled `<ul>`-tree (CD-01) | `react-arborist` | react-arborist adds ~30KB and complexity for a 3-group flat-per-group tree. Hand-rolled is the §3.8-aligned choice. **Recommend hand-rolled.** |
| `crypto.randomUUID()` | `uuid` v4 package | uuid package adds 8KB for zero functional benefit. **Recommend crypto.randomUUID().** |
| Radix `Popover` | Custom fixed-position div with manual portal | Radix gives keyboard focus management, ARIA attrs, and anchor positioning for free. The `onInteractOutside={(e) => e.preventDefault()}` knob is the entire non-default config. **Recommend Radix Popover.** |
| Sentinel UUID for "unset" Power Shape | `null` `power_shape_ref` or distinct shape kind | Sentinel is simplest (no special-case render path; the dropdown just lists it as the always-present top entry). **Recommend sentinel UUID** `"00000000-0000-0000-0000-000000000000"` with the singleton record `{ uuid: SENTINEL, name: "(leave unset — fill in code)", kind: "unset", params: {} }` baked into the store's initial state, NOT serialized to `.scp`. This makes the picker uniform and the codegen branch trivial. |

**Installation (Wave 2):** `npm install` is NOT required. The shadcn wrapper files are pure source additions.

**Version verification (Wave 1, Julia side):**
```bash
# In src/utilities.jl, the rebin_extensive helper uses no new Julia dependencies.
# DelimitedFiles (for readdlm) is a Base stdlib — already a transitive in test_validation.jl.
# Confirm: bin/jl -e 'using DelimitedFiles; println(pkgversion(DelimitedFiles))'
```

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GUI (Tauri WebView, React)                          │
│                                                                             │
│   ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐   │
│   │ Left Panel (NEW)   │  │ Canvas (UNCHANGED) │  │ Right Panel (NEW)  │   │
│   │ ┌────────────────┐ │  │  ReactFlow         │  │  selection-kind    │   │
│   │ │ Tab Strip      │ │  │  StreamNodes       │  │  router            │   │
│   │ │ [C][R][P]      │ │  │                    │  │ ┌────────────────┐ │   │
│   │ └────────┬───────┘ │  │                    │  │ │ Component edit │ │   │
│   │          │         │  │                    │  │ │   uses picker  │ │   │
│   │   ┌──────┴──────┐  │  │                    │  │ │   (popover)    │ │   │
│   │   │ Components  │  │  │                    │  │ ├────────────────┤ │   │
│   │   │  ToolboxPanel  │  │                    │  │ │ Resource edit  │ │   │
│   │   │  (REUSED)   │  │  │                    │  │ │   geometry or  │ │   │
│   │   │  + Sources  │  │  │                    │  │ │   power shape  │ │   │
│   │   │    header   │  │  │                    │  │ ├────────────────┤ │   │
│   │   ├─────────────┤  │  │                    │  │ │ Project edit   │ │   │
│   │   │ Resources   │◄─┼──┼─────Edit… jump─────┼──┤ │   no-op (D-04) │ │   │
│   │   │  tree       │  │  │                    │  │ └────────────────┘ │   │
│   │   ├─────────────┤  │  │                    │  │                    │   │
│   │   │ Project     │  │  │                    │  │                    │   │
│   │   │  Model Opts │  │  │                    │  │                    │   │
│   │   │  form (D-04)│  │  │                    │  │                    │   │
│   │   └─────────────┘  │  │                    │  │                    │   │
│   └────────────────────┘  └────────────────────┘  └────────────────────┘   │
│                                                                             │
│                          ┌──────────────────────┐                           │
│                          │ zustand store        │                           │
│                          │  nodes, edges        │                           │
│                          │  + resources (NEW)   │                           │
│                          │  + modelOptions(NEW) │                           │
│                          │  + activeLeftTab(NEW)│                           │
│                          │  _pushSnapshot       │                           │
│                          │   covers all slices  │                           │
│                          └────┬─────────────────┘                           │
│                               │                                             │
│         ┌─────────────────────┼─────────────────────┐                       │
│         ▼                     ▼                     ▼                       │
│   ┌──────────┐         ┌──────────┐         ┌──────────────┐                │
│   │ projectIO│         │codeGen   │         │ Tauri        │                │
│   │  (REWRITE│         │  (REWRITE│         │ writeTextFile│                │
│   │   to v2.0│         │   resource│        │ readTextFile │                │
│   │   .scp)  │         │   block   │        │ filter: .scp │                │
│   └────┬─────┘         │   first)  │        └──────┬───────┘                │
│        │               └────┬──────┘               │                        │
└────────┼────────────────────┼──────────────────────┼────────────────────────┘
         │                    │                      │
         ▼                    ▼                      ▼
   .scp JSON file       .jl code preview        .scp on disk
                              │
                              │ user runs at shell
                              ▼
                        ┌───────────────────────────────────────┐
                        │ Julia process                         │
                        │   using STREAM                        │
                        │   readdlm(...) → rebin_extensive(...) │ ← Phase 62
                        │   cosine_power_shape(nz, nx; ...)     │ ← Phase 62
                        │   PipeGeometry_rectangular(...)       │
                        │   @named cac_1 = ChannelAndContacts.. │
                        │   mtkcompile → solve                  │
                        └───────────────────────────────────────┘
```

### Component Responsibilities

| Layer | File(s) | Responsibility (Phase 62 delta) |
|-------|---------|----------------------------------|
| App shell | `gui/src/App.tsx` | Wrap `ToolboxPanel` in `<Tabs>`; bind `Ctrl+1/2/3`; route active tab to body component |
| Components tab body | `gui/src/components/ToolboxPanel.tsx` | UNCHANGED behavior; ADD Sources category header rendering (D-30) — reads `getComponentsByCategory("Sources")` which returns `WallTemperature` and `HeatFluxSource` from the v1.1 registry. Currently it ignores those because `ToolboxPanel.tsx:13-14` only fetches Hydraulic + Thermal. Phase 62 adds the Sources fetch + header but does NOT wire drag handlers (Phase 63's job) — header renders with an empty body. |
| Resources tab body | `gui/src/components/resources/ResourcesTreePanel.tsx` (NEW) | Render tree with 3 group headers, `+` buttons, search box, inline rename, context menu. Hand-rolled `<ul>` per CD-01. |
| Project tab body | `gui/src/components/project/ModelOptionsPanel.tsx` (NEW) | Model Options form. Renders directly (no inner selection per D-04). |
| Resource editors | `gui/src/components/sidebar/GeometryResourceEditor.tsx` (NEW, extracts from `PipeGeometryPicker`), `gui/src/components/sidebar/PowerShapeResourceEditor.tsx` (NEW) | The same fields used in `+ New…` popover and in the right Properties panel when a Resource row is selected. Composition pattern: one editor component, two mount points. |
| Reference picker | `gui/src/components/sidebar/ResourceReferencePicker.tsx` (NEW) | Dropdown + `+ New…` (opens popover wrapping the Resource editor) + `Edit…` (dispatches store action `selectResource`). Generic over Resource kind. Used by `ParameterForm.tsx` for `geometry_ref` and `power_shape_ref` fields. |
| Sidebar router | `gui/src/components/sidebar/SidebarPanel.tsx` | Per CD-05: branch on `selectionKind` discriminator. Either grow file with conditional rendering OR refactor into `<ComponentEditor>` + `<ResourceEditor>` + `<ProjectEditor>` (planner picks). |
| Store | `gui/src/store/useStore.ts` | Add slices: `resources`, `modelOptions`, `activeLeftTab`, `selectionKind`, `selectedResourceId`. Add actions: `addResource`, `removeResource`, `renameResource`, `updateResource`, `setActiveLeftTab`, `setModelOptions`, `selectResource`. Extend `_pushSnapshot` to capture Resource state. Rename Tauri filter at lines 516/547 from `streamgui` to `scp`. Update error strings at lines 557, 597. |
| Persistence | `gui/src/lib/projectIO.ts` | Rewrite for `format_version: "2.0"` schema. DROP the v1→v2 migration shim (line 87-89). Now strict: throw on unknown `format_version`. New `StreamProject` shape includes `resources`, `model_options`, and `layout.active_left_tab`. |
| Codegen | `gui/src/lib/codeGenerator.ts` | Insert a `# Resources` block before the component declarations. For each Resource in the store, emit one Julia line (helper or constructor). Component constructor emission swaps the inline value formatter for a lookup that emits the resource's variable name (e.g., `geom_mtr` not `PipeGeometry_rectangular(0.6, 0.07, ...)`). The flat-string emit shape stays (section-block UI rework is Phase 66). |
| Julia source | `src/utilities.jl` (NEW), `src/STREAM.jl` (edit exports) | `rebin_extensive(source::AbstractMatrix, target_shape::Tuple{Int,Int}) -> Matrix` and `cosine_power_shape(nz::Int, nx::Int; amplitude::Real=1.0) -> Matrix`. Both ASCII-only, both exported. |
| Julia tests | `test/test_utilities.jl` (NEW) | Sum-conservation, identity, integer up/down, non-integer ratios, single-row/column edge cases, cosine reference parity vs Python. |

### Recommended Project Structure (delta)

```
gui/src/
├── components/
│   ├── App.tsx                                # MODIFIED — Tabs shell + Ctrl+1/2/3
│   ├── ToolboxPanel.tsx                       # MODIFIED — add Sources header (empty body)
│   ├── SidebarPanel.tsx                       # MODIFIED — selection-kind router
│   ├── resources/                             # NEW
│   │   ├── ResourcesTreePanel.tsx
│   │   ├── ResourceRow.tsx
│   │   └── ResourceGroupHeader.tsx
│   ├── project/                               # NEW
│   │   └── ModelOptionsPanel.tsx
│   ├── sidebar/
│   │   ├── ParameterForm.tsx                  # MODIFIED — route geometry/power_shape to picker
│   │   ├── PipeGeometryPicker.tsx             # DELETED (split into Editor + Picker)
│   │   ├── GeometryResourceEditor.tsx         # NEW
│   │   ├── PowerShapeResourceEditor.tsx       # NEW
│   │   └── ResourceReferencePicker.tsx        # NEW
│   └── ui/
│       ├── popover.tsx                        # NEW (shadcn shim around radix-ui Popover)
│       └── context-menu.tsx                   # NEW (shadcn shim)
├── store/
│   └── useStore.ts                            # MODIFIED — resources/modelOptions/activeLeftTab slices
├── lib/
│   ├── projectIO.ts                           # REWRITTEN — v2.0 schema, hard cutover
│   └── codeGenerator.ts                       # MODIFIED — Resources block + lookups
└── registry/
    └── (unchanged — Phase 61 locked the shape)

gui/export_examples/
├── *.streamgui                                # DELETED (all 5: abc, dwkada, project, second, test)
├── simple_loop.scp                            # NEW
└── mtr_assembly.scp                           # NEW (optional second; planner decides)

src/
├── STREAM.jl                                  # MODIFIED — include "utilities.jl"; export rebin_extensive, cosine_power_shape
└── utilities.jl                               # NEW

test/
├── runtests.jl                                # MODIFIED — add include("test_utilities.jl")
└── test_utilities.jl                          # NEW
```

### Pattern 1: Resource store slice with snapshot integration

```typescript
// gui/src/store/useStore.ts (additions)
// Source: extends existing _pushSnapshot pattern at useStore.ts:211-249

interface GeometryResource {
  uuid: string;            // crypto.randomUUID()
  name: string;            // unique per kind; valid Julia identifier
  kind: "rectangular" | "circular";
  params: { L: number; W?: number; H?: number; D?: number };
}

interface PowerShapeResource {
  uuid: string;
  name: string;
  kind: "uniform" | "z_cosine" | "file_loaded" | "unset";
  params: { amplitude?: number; path?: string };
}

interface ResourcesSlice {
  resources: {
    geometries: Record<string, GeometryResource>;
    powerShapes: Record<string, PowerShapeResource>;
    fluids: Record<string, { uuid: string; name: string }>;  // placeholder
  };
  addGeometry: (g: Omit<GeometryResource, "uuid">) => string;     // returns new uuid
  updateGeometry: (uuid: string, patch: Partial<GeometryResource>) => void;
  renameGeometry: (uuid: string, newName: string) => void;
  removeGeometry: (uuid: string) => void;
  // ... same shape for powerShapes
}

// CRITICAL: every mutation calls _pushSnapshot() first, like canvas mutations do
addGeometry: (g) => {
  get()._pushSnapshot();
  const uuid = crypto.randomUUID();
  set((s) => ({
    resources: {
      ...s.resources,
      geometries: { ...s.resources.geometries, [uuid]: { ...g, uuid } },
    },
    isDirty: true,
  }));
  return uuid;
}
```

**The snapshot shape must extend.** Current `CanvasSnapshot` (`useStore.ts:25-29`):
```typescript
interface CanvasSnapshot {
  nodes: Node[];
  edges: Edge[];
  bcs: BCEntry[];
}
```
becomes:
```typescript
interface CanvasSnapshot {
  nodes: Node[];
  edges: Edge[];
  bcs: BCEntry[];
  resources: ResourcesSlice["resources"];      // NEW
  modelOptions: ModelOptionsSlice["modelOptions"];  // NEW
}
```
and `_pushSnapshot`/`undo`/`redo` must read/write these fields. Each Resource action calls `get()._pushSnapshot()` before mutating, identical to `addNode` at `useStore.ts:303`. `activeLeftTab` is NOT in the snapshot (it's UI state, not content state — same exclusion principle as `selectedNodeId`).

### Pattern 2: Radix Popover with click-outside disabled

```typescript
// gui/src/components/sidebar/ResourceReferencePicker.tsx
// Source: https://www.radix-ui.com/primitives/docs/components/popover
//         + Radix issue #646 known caveat about preventDefault and focus

import { Popover } from "radix-ui";

<Popover.Root open={popoverOpen} onOpenChange={setPopoverOpen}>
  <Popover.Trigger asChild>
    <Button>+ New…</Button>
  </Popover.Trigger>
  <Popover.Portal>
    <Popover.Content
      align="start"
      side="right"
      sideOffset={4}
      collisionPadding={8}
      // D-16: do NOT dismiss on outside click
      onInteractOutside={(e) => e.preventDefault()}
      // Esc still works — Radix invokes onEscapeKeyDown separately
      onEscapeKeyDown={() => setPopoverOpen(false)}
    >
      <GeometryResourceEditor
        initialName={autoSuggestedName}
        onCreate={(g) => {
          const uuid = addGeometry(g);
          onChange(uuid);              // auto-select in dropdown
          setPopoverOpen(false);
          focusNextField();            // D-15
        }}
        onCancel={() => setPopoverOpen(false)}
      />
    </Popover.Content>
  </Popover.Portal>
</Popover.Root>
```

**Known Radix gotcha** `[CITED: https://github.com/radix-ui/primitives/issues/646]`: `e.preventDefault()` in `onInteractOutside` prevents the underlying mousedown, which can interfere with focus operations on the trigger after dismiss. Workaround if observed: blur the popover content explicitly in the Cancel/Create handlers before calling `setPopoverOpen(false)`. Smoke-test before declaring done.

**Anchor strategy for D-17:** Radix Popover does collision-aware positioning by default. `side="right"` + `align="start"` + `collisionPadding={8}` gives "right of field if room, else flip to left side." Width: set inline style `style={{ width: 280 }}` on `Popover.Content` for a fixed visual.

### Pattern 3: Codegen Resource emission

```typescript
// gui/src/lib/codeGenerator.ts (rework outline)

export function generateCode(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
  resources: ResourcesSlice["resources"],   // NEW arg
  getComponent: (id: string) => ComponentDefinition | undefined,
): string {
  const lines: string[] = [];

  lines.push("using ModelingToolkit, STREAM");
  lines.push("using ModelingToolkit: t_nounits as t");
  lines.push("using DelimitedFiles  # for file_loaded power shapes");  // conditional
  lines.push("");

  // --- Resources block (NEW) ---
  lines.push("# Resources");
  for (const g of Object.values(resources.geometries)) {
    if (g.kind === "rectangular") {
      lines.push(`${g.name} = PipeGeometry_rectangular(${formatReal(g.params.L)}, ${formatReal(g.params.W!)}, ${formatReal(g.params.H!)})`);
    } else {
      lines.push(`${g.name} = PipeGeometry_circular(${formatReal(g.params.L)}, ${formatReal(g.params.D!)})`);
    }
  }
  // Note: HeatDiffusion consumers pass nz/nx; the Resource is generic.
  // Codegen emits the helper call inline at the consumer site, NOT here, because
  // the helper takes (nz, nx) as a positional arg. See per-component branch below.
  lines.push("");

  // --- Components ---
  for (const node of nodes) {
    const data = node.data as StreamNodeData;
    // When emitting geometry param: look up by geometry_ref UUID, emit resource.name
    // When emitting power_shape param: emit the recipe call (uniform/z_cosine/file_loaded/unset)
    //   using THIS component's nz/nx parameter values.
    // ...
  }
}
```

Power Shape emission per kind (inline at the HeatDiffusion consumer):

```julia
# uniform
power_shape_<name> = ones(nz, nx)

# z_cosine
power_shape_<name> = cosine_power_shape(nz, nx; amplitude=1.0)

# file_loaded
power_shape_<name> = rebin_extensive(
    readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','),
    (nz, nx),
)

# unset (sentinel)
power_shape_<name> = ones(nz, nx)  # TODO: fill in your power shape
```

The `nz` and `nx` literals in each emit are the consumer HeatDiffusion's parameter values at codegen time, not the literal string `nz`. (Same convention as the existing array-port `[connect(...) for i in 1:${nVal}]` emission at `codeGenerator.ts:763`.)

### Pattern 4: Selection-kind router

```typescript
// gui/src/store/useStore.ts (additions)
type SelectionKind = "none" | "component" | "resource" | "project";

interface SelectionSlice {
  selectionKind: SelectionKind;
  selectedNodeId: string | null;           // existing
  selectedResourceId: string | null;        // NEW (uuid)
  selectedResourceKind: "geometry" | "powerShape" | null;  // NEW
  selectNode: (id: string | null) => void;  // existing — clears resource selection
  selectResource: (uuid: string, kind: "geometry" | "powerShape") => void;  // NEW — clears node selection
  selectProjectTab: () => void;             // NEW — clears both
  clearSelection: () => void;               // Esc handler (D-05)
}
```

`SidebarPanel.tsx` branches on `selectionKind` (per CD-05, planner picks file structure):

```typescript
function SidebarPanel(...) {
  const { selectionKind } = useStore(...);
  switch (selectionKind) {
    case "component": return <ComponentEditor />;     // today's body
    case "resource":  return <ResourceEditor />;       // new
    case "project":   return <ProjectEditor />;        // D-04: panel either shows nothing or echoes the tab body
    case "none":
    default:          return <NoSelection />;          // today's empty-state body
  }
}
```

### Anti-Patterns to Avoid

- **Storing Resources as JSON arrays instead of UUID-keyed records.** Components reference Resources by UUID; an array means O(n) lookup per render. D-10 specifies `Record<uuid, T>` for a reason. Use a Record (object map), not an Array. Convert to array only at serialize time.
- **Forgetting to push a snapshot on Resource mutations.** Every Resource CRUD action MUST call `get()._pushSnapshot()` BEFORE the `set()`. Skip this and undo is broken across canvas+resource boundaries — and the bug is silent until the user undoes a sequence and the canvas reverts but the Resource doesn't.
- **Emitting `null` for "unset" Power Shape FK.** The picker should always have a real value to display. Sentinel UUID is cleaner: the picker always renders something; the codegen branches on `resource.kind === "unset"`.
- **Adding `validation` or `assert` to `rebin_extensive`.** Caller-trust posture (D-25 + memory `feedback_power_shape_trust_caller.md`). The helper accepts any matrix shape and any target shape and returns a matrix of the target shape. No "shape must be positive" guards. No "sum must equal expected" assertions. The test suite verifies the invariant; the function does not.
- **Migrating `.streamgui` to `.scp` on load.** D-28 says hard cutover. `projectIO.ts:87` v1→v2 migration shim is the locus that gets removed, not extended. If we leave a shim "just in case," it becomes a maintenance liability the moment someone opens a stale file.
- **Reading `Tauri` file extension from a magic string in two places.** Currently `useStore.ts:516` and `useStore.ts:547` independently spell `"streamgui"`. Extract a constant (`PROJECT_FILE_EXTENSION = "scp"`) at module top so the next renamer can grep one symbol.
- **Coupling popover anchor calculation to manual positioning.** Radix does it. Don't manually compute `getBoundingClientRect`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tab strip with persisted active tab | Custom `<button>` switcher | `radix-ui` `Tabs` (already wrapped at `gui/src/components/ui/tabs.tsx`) | Keyboard nav, ARIA, controlled mode all free |
| Anchored popover with focus trap | Custom fixed-position div + `useEffect` outside-click handler | `radix-ui` `Popover` with `onInteractOutside={(e) => e.preventDefault()}` | Focus trap, collision detection, portal — all free; the non-default knob is one line |
| Right-click context menu | Custom event handler + portal | `radix-ui` `ContextMenu` | Same — keyboard nav + ARIA |
| UUID generation | `Math.random()`-based pseudo-UUID | `crypto.randomUUID()` | Already used at `useStore.ts:304`; Web Crypto API is uuid v4 compliant |
| Conservative 2D regridding | Hand-rolled bilinear interp (which doesn't conserve!) | Separable area-weighted 1D pass twice | Conservative regridding is a 30-line algorithm well-trodden in atmospheric science; bilinear silently loses/gains power on resample (this is exactly the alternative rejected per `<deferred>` in CONTEXT.md) |
| `.scp` ↔ Julia identifier name uniqueness | `name in [array]` linear scan | A `Set` derived from the kind-scoped resources record | O(1) lookup; matches the shape of the store |
| Smart-name-increment (D-19) | Reinvent | Reuse the §3.5 algorithm in `useStore.ts:reconstructInstanceCounters` — generalize it into a kind-scoped helper | The §3.5 rule is the same rule; one implementation, two call sites |

**Key insight:** Almost every Phase 62 widget has a direct Radix primitive. The novelty is composition and state shape, not visual chrome. Resist the urge to hand-roll because the project is "an engineering tool" — that ethos is about visual restraint, not building primitives from `<div>` up.

## Runtime State Inventory

This is a structural refactor; the most likely runtime-state surprises are in the file-extension cutover and Tauri config.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `gui/export_examples/*.streamgui` — 5 files (abc, dwkada, project, second, test). All predate v1.1 channel-family redesign and won't load under the new registry per CONTEXT.md D-28. | **Delete** (D-28 explicit). DO NOT migrate. Replace with 1-2 fresh `.scp` examples. |
| Stored data | `appDataDir()/recent.json` (`useStore.ts:108-136`). May contain absolute paths to `.streamgui` files from prior sessions. | On load, paths to non-existent / wrong-extension files should be silently filtered. Current behavior at `loadRecentFiles` already swallows errors — confirm `recent.json` with stale `.streamgui` entries simply renders as unopenable list items. (Acceptable degradation; no migration code.) |
| Live service config | None — this is a desktop application; no n8n / Datadog / external services. | None — verified by inspecting `Tauri` invocations only. |
| OS-registered state | Tauri filename association for `.streamgui` — check `gui/src-tauri/tauri.conf.json` for `mimeTypes` / `fileAssociations`. If present, must be updated to `.scp`. | Read `tauri.conf.json` during planning. If file associations exist, add to renamer surface. If not, no action. |
| Secrets/env vars | None — no env vars reference the file extension. | None — verified by grep. |
| Build artifacts | `gui/dist/`, `gui/src-tauri/target/` — rebuilt by `vite build` / `cargo build`. | Force `npm run build` after the rename to make sure no string baked into a dist bundle still references `.streamgui`. |
| In-memory state | `useStore` `recentFiles` array (`useStore.ts:197`). | Stale entries point to deleted `.streamgui` files; degrades gracefully on click (load fails, dialog shows error). Acceptable. |

**Nothing found in OS-registered state** beyond the potential Tauri association — planner should verify `tauri.conf.json` as a Wave 1 task.

## Common Pitfalls

### Pitfall 1: Radix Popover preventDefault prevents trigger focus return

**What goes wrong:** After Cancel or Esc, the focus does not return cleanly to the dropdown that opened the popover; some keystroke handlers feel unresponsive.

**Why it happens:** `e.preventDefault()` in `onInteractOutside` cancels the mousedown that Radix would otherwise use to restore focus. `[CITED: github.com/radix-ui/primitives/issues/646]`

**How to avoid:** In the Cancel and Create handlers, explicitly call `triggerRef.current?.focus()` after `setPopoverOpen(false)`. Smoke-test by opening a picker, hitting Esc, then verifying that `Tab` from the now-closed popover moves to the next field in the property panel (not somewhere random).

**Warning signs:** Reports of "the Tab order is weird after I cancel a New Geometry."

### Pitfall 2: Snapshot push omitted on Resource rename

**What goes wrong:** User creates a Geometry, references it from a Channel, renames the Geometry. Then Ctrl+Z. The Channel's `geometry_ref` UUID stays valid (good), but the Resource's name change reverts (good) — except if the rename action forgot to call `_pushSnapshot()`, the rename change is permanent and not undoable.

**Why it happens:** The store's `_pushSnapshot` is explicit, not automatic. Easy to forget.

**How to avoid:** Make every Resource action follow the same shape:
```typescript
addResource: (...) => { get()._pushSnapshot(); set(...) },
renameResource: (...) => { get()._pushSnapshot(); set(...) },
updateResource: (...) => { get()._pushSnapshot(); set(...) },
removeResource: (...) => { get()._pushSnapshot(); set(...) },
```
Code-review checklist: any function in `useStore.ts` that touches the `resources` slice and sets `isDirty: true` MUST call `_pushSnapshot()` first.

**Warning signs:** Unit test `"undo reverts a Resource rename"` failing.

### Pitfall 3: Schema strictness breaks the empty-state path

**What goes wrong:** Brand-new project (zero resources, zero components) serializes to a `.scp` with empty arrays/objects. If `deserializeProject` is over-strict ("`resources.geometries` must be an array"), reloading an empty project errors.

**Why it happens:** Tightening the schema feels like a virtue, but the empty case is a real case (every new project starts there).

**How to avoid:** Test serialize-then-deserialize round-trip on `newProject()` output. Treat missing or empty `resources` / `model_options` / `layout.active_left_tab` fields as `{}` / `{}` / `"Components"`, not as errors. The only field with a strict version check is `format_version`.

**Warning signs:** "New Project, Save, Open → error dialog."

### Pitfall 4: Codegen emits invalid Julia when Resource name collides with a registry component name

**What goes wrong:** User names a Geometry `pump` (it's a valid Julia identifier). Codegen emits:
```julia
pump = PipeGeometry_rectangular(...)
@named pump_1 = Pump(...)
```
That's valid Julia (no collision). But if user names a Geometry `pump_1` (also valid), codegen emits:
```julia
pump_1 = PipeGeometry_rectangular(...)
@named pump_1 = Pump(...)
```
Now `pump_1` is shadowed — invalid Julia.

**Why it happens:** Resource name uniqueness is per-kind (D-10), but the generated Julia file has a single namespace.

**How to avoid:** Two options (planner picks):
1. **Conservative:** Validate at codegen time and emit a `# WARNING: name <X> collides with component <Y>` comment, like the existing `validateJuliaIdentifier` warning at `codeGenerator.ts:194`. Acceptable for v1 — the user sees the warning and renames.
2. **Aggressive:** Add a global uniqueness check across {component instance names, resource names} at validation time. Belongs to Phase 71 (validation framework), so Phase 62 should NOT take this on. Option 1 is the Phase 62 choice.

**Warning signs:** User reports "my generated code doesn't compile."

### Pitfall 5: `file_loaded` Power Shape path is absolute, not relative

**What goes wrong:** User picks a CSV via a Tauri file dialog. The dialog returns an absolute path. We store it. On `Save`, the `.scp` has an absolute path. User moves the project folder, breaks.

**Why it happens:** Tauri dialogs return absolute paths; relative-to-`.scp` is a derived quantity.

**How to avoid:** When the user picks a CSV path AND a `currentFilePath` exists on the project (i.e., the `.scp` is saved), compute and store the relative path. If the project is unsaved (no `currentFilePath` yet), store the absolute path temporarily and recompute on first save. The Julia codegen emits `joinpath(@__DIR__, "shapes/mtr.csv")` style — `@__DIR__` makes the call site relative to the `.jl` file, so the `.scp` path must be relative to the `.jl` output directory (which is the user's choice on Export). For now, treat "relative to the `.scp`" as the canonical form and let Phase 66's code-export rework solve the `.jl`-vs-`.scp` directory question. `[ASSUMED]` — confirm with user that "relative to `.scp`" is the right anchor for v1 (CONTEXT.md says it is per D-24).

**Warning signs:** "I emailed my project and the recipient can't find the CSV."

### Pitfall 6: `rebin_extensive` separable order matters for non-commutative cases

**What goes wrong:** Rebin-along-z then rebin-along-x produces a result that differs from rebin-along-x then rebin-along-z in degenerate cases (e.g., source has integer ratio along one axis and non-integer along the other).

**Why it happens:** Area-weighted reassignment is associative and commutative for the linear case, but floating-point rounding accumulates differently in different orders.

**How to avoid:** Pick one order (z then x) and document it. Test that `sum(out) == sum(in)` to a tight tolerance (1e-12 relative for Float64) in BOTH orders. The actual matrix values may differ at the last ULP between orders; only `sum` is the invariant. `[VERIFIED: standard conservative regridding behavior per ESMF docs]`

**Warning signs:** A test like "rebin (10×5) → (3×7) along z-then-x equals rebin along x-then-z" would FAIL — and that's fine. Don't write that test. Write the sum-conservation test instead.

## Code Examples

Verified patterns sourced from the codebase or design-decisions doc.

### Example 1: Conservative 1D area-weighted rebin (the inner kernel)

```julia
# src/utilities.jl — proposed
# Source: standard conservative regridding (atmospheric science literature)
#   ESMF, HARP, xESMF all use this same pattern.
# Algorithm: cell-overlap area-weighted reassignment.

"""
    _rebin_1d(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}

Conservatively rebin a 1D vector `v` of length `n_in` to length `n_out`,
preserving `sum(out) ≈ sum(in)` to floating-point precision.

# Arguments
- `v`     : Source vector. Each entry represents an extensive (integrated)
            quantity over a uniform sub-interval of [0, 1].
- `n_out` : Target length (must be `≥ 1`).

# Returns
A `Vector{Float64}` of length `n_out` where `sum(out) ≈ sum(v)`.

# Algorithm
Treat each source cell `i` as occupying interval `[(i-1)/n_in, i/n_in]` and
each target cell `j` as occupying `[(j-1)/n_out, j/n_out]`. For every
(i, j) pair, compute the overlap length and assign the fraction
`overlap / (1/n_in)` of `v[i]` to `out[j]`.

# Internal helper — not exported.
"""
function _rebin_1d(v::AbstractVector{<:Real}, n_out::Integer)
    n_in = length(v)
    out  = zeros(Float64, n_out)
    if n_in == n_out
        copyto!(out, v)
        return out
    end
    # Source cells occupy [(i-1)/n_in, i/n_in].
    # Target cells occupy [(j-1)/n_out, j/n_out].
    # Width of each source cell = 1/n_in.
    inv_n_in = 1.0 / n_in
    for i in 1:n_in
        src_lo = (i - 1) * inv_n_in
        src_hi = i * inv_n_in
        # First target cell that could overlap source cell i:
        j_lo = max(1, floor(Int, src_lo * n_out) + 1)
        j_hi = min(n_out, ceil(Int, src_hi * n_out))
        for j in j_lo:j_hi
            tgt_lo = (j - 1) / n_out
            tgt_hi = j / n_out
            overlap = max(0.0, min(src_hi, tgt_hi) - max(src_lo, tgt_lo))
            # Fraction of v[i] that lives in target cell j:
            out[j] += v[i] * overlap * n_in
        end
    end
    return out
end
```

### Example 2: Separable 2D wrapper

```julia
# src/utilities.jl — proposed

"""
    rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}

Conservatively rebin a 2D matrix `M` to a target shape `(nz, nx)`, preserving
`sum(out) ≈ sum(M)` to floating-point precision.

Caller-trust posture: this function does NOT validate or normalize `M`. Pass
in whatever extensive 2D quantity you want resampled.

# Arguments
- `M`            : Source matrix of any size.
- `target_shape` : `(nz, nx)` target dimensions.

# Returns
A `Matrix{Float64}` of size `target_shape`.

# Algorithm
Separable 1D pass: first rebin along axis 1 (rows / z-axis), then along
axis 2 (cols / x-axis). Order is fixed for reproducibility.
"""
function rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int})
    nz_out, nx_out = target_shape
    nz_in, nx_in   = size(M)
    # Pass 1: rebin each column along z.
    intermediate = Matrix{Float64}(undef, nz_out, nx_in)
    for j in 1:nx_in
        intermediate[:, j] = _rebin_1d(view(M, :, j), nz_out)
    end
    # Pass 2: rebin each row along x.
    out = Matrix{Float64}(undef, nz_out, nx_out)
    for i in 1:nz_out
        out[i, :] = _rebin_1d(view(intermediate, i, :), nx_out)
    end
    return out
end
```

`[ASSUMED]` algorithm sketch — the planner / executor should run a Python cross-check against a small known case (e.g., a 3×3 of all-ones rebinned to 5×5, sum should be 9 ± floating-point) before declaring correct.

### Example 3: Cosine power shape (matches Python `uniform_x_power_shape`)

```julia
# src/utilities.jl — proposed
# Source: Python STREAM stream/composition/mtr_geometry.py lines 297-335
# `uniform_x_power_shape` uses cosine_shape along z and uniform along x.
# We simplify: caller-trust on amplitude / peaking factor scaling.

"""
    cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real=1.0) -> Matrix{Float64}

Build a `(nz, nx)` power-shape matrix with a cosine profile along the
axial (z) direction and uniform distribution along the lateral (x) direction.

# Arguments
- `nz`        : Number of axial cells.
- `nx`        : Number of lateral cells.
- `amplitude` : Cosine amplitude scale; `1.0` matches the unit-mean case.

# Returns
`Matrix{Float64}` of size `(nz, nx)`. Caller is responsible for any
further normalization — this function does not normalize.
"""
function cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real=1.0)
    # Cosine evaluated at cell centers in [0, π].
    zaxis = [cos(π * (i - 0.5) / nz - π/2)^2 for i in 1:nz]
    # Scale and broadcast uniformly across nx.
    col = amplitude .* zaxis
    return repeat(col, 1, nx)
end
```

`[ASSUMED]` — exact cosine form (cell-centered vs cell-boundary, squared vs not) should be cross-checked against Python's `cosine_shape` at `/home/itay/projects/STREAM/stream/composition/mtr_geometry.py` near the call. Phase 62 executor should run a parity spike before locking the algorithm.

### Example 4: `.scp` v2.0 round-trip stub (vitest)

```typescript
// gui/src/lib/__tests__/projectIO.test.ts (new test)
import { describe, it, expect } from "vitest";
import { serializeProject, deserializeProject } from "../projectIO";

describe(".scp v2.0 round-trip", () => {
  it("preserves resources, model_options, and active_left_tab", () => {
    const project = {
      format_version: "2.0",
      model_options: { name: "demo", fluid: "water", g_default: 9.80665 },
      resources: {
        geometries: [
          { uuid: "g-1", name: "mtr_channel", kind: "rectangular",
            params: { L: 0.6, W: 0.07, H: 0.0025 } },
        ],
        power_shapes: [
          { uuid: "ps-1", name: "axial_cos", kind: "z_cosine",
            params: { amplitude: 1.0 } },
        ],
      },
      components: [
        { uuid: "c-1", type: "ChannelAndContacts",
          geometry_ref: "g-1", instanceName: "cac_1", parameters: { n: 10 } },
      ],
      connections: [],
      layout: { active_left_tab: "Resources" },
    };
    const json = serializeProject(project);
    const round = deserializeProject(json);
    expect(round).toEqual(project);
  });

  it("rejects format_version other than '2.0'", () => {
    const bad = JSON.stringify({ format_version: "1.5" });
    expect(() => deserializeProject(bad)).toThrow();
  });

  it("rejects legacy version: 2 numeric (hard cutover, D-28)", () => {
    const bad = JSON.stringify({ version: 2, nodes: [], edges: [], bcs: [] });
    expect(() => deserializeProject(bad)).toThrow();
  });
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Inline `PipeGeometry_rectangular(...)` per component | Named Resource at top of file, components reference by name | Phase 62 | Cleaner codegen output, parity with hand-written Julia |
| `.streamgui` v2 JSON | `.scp` v2.0 JSON with `resources` / `model_options` / `layout` blocks | Phase 62 | Hard cutover; no migration code |
| `PipeGeometryPicker` per-component inline editor | Split into Resource editor + reference picker | Phase 62 | Same component used in 2 mount points (popover, Resources tab) |
| Single right-panel "Properties" view | Selection-kind router (component / resource / project) | Phase 62 | The Inspector pattern (Unity / Simulink Model Explorer) |
| Flat-string codegen (no Resources block) | Flat-string codegen with Resources block prepended | Phase 62 | Section-block UI rework is Phase 66 — Phase 62 is content change only |
| zundo middleware (in package.json, unused) | Explicit `_pushSnapshot` discipline | Already in place (`useStore.ts:200-206`) | Just extend the existing pattern — do NOT introduce zundo |

**Deprecated/outdated:**
- The 5 `gui/export_examples/*.streamgui` files: pre-v1.1, won't load under the new registry. Delete.
- `projectIO.ts:87-89` v1 → v2 migration shim: stripped in Phase 62.
- `StreamProject.version: 1 | 2`: replaced by `format_version: "2.0"` string.
- Any `tauri.conf.json` `.streamgui` association (if present): update to `.scp`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Existing registry `type: "PipeGeometry"` and `type: "Matrix"` parameters are the right anchor for Resource-ref rendering, OR planner introduces a new `"ResourceRef"` type. CONTEXT.md does not pin this. | Architecture Patterns, Pattern 4 | Misalignment with Phase 61's registry shape; the planner needs to pick one and document it. |
| A2 | `crypto.randomUUID()` is uuid v4 by spec and is acceptable in place of the `uuid` package per CD-03. | Standard Stack > UUID generation | Low — the spec is clear; if user wants explicit uuid package for some reason, planner can switch. |
| A3 | Radix Popover's `onInteractOutside={(e) => e.preventDefault()}` correctly suppresses click-outside dismissal without breaking Esc handling. Radix issue #646 known caveat about focus return. | Pattern 2 | Medium — needs an early smoke-test in Wave 2 (a) to confirm. |
| A4 | The cosine power shape formula in Example 3 above matches Python STREAM's `uniform_x_power_shape`. The exact discretization (cell-centered cosine squared) is the natural choice but should be parity-tested. | Code Examples, Example 3 | Medium — wrong formula gives wrong physics. Phase 62 executor should run a parity spike before locking. |
| A5 | Sentinel UUID `"00000000-0000-0000-0000-000000000000"` is acceptable for the `unset` Power Shape. Alternative is `null power_shape_ref` or a dedicated "kind". | Standard Stack > Alternatives | Low — easy to switch later if user prefers. |
| A6 | The 5 `gui/export_examples/*.streamgui` files truly don't load under v1.1 registry. CONTEXT.md asserts this; I have not verified by running the load path. | Runtime State Inventory > Stored data | Low — even if some do load, D-28 explicit deletes them. |
| A7 | `tauri.conf.json` does NOT currently register `.streamgui` as a file association. I did not read the file in this research pass. | Runtime State Inventory > OS-registered state | Low — Wave 1 will read and update if needed. |
| A8 | Power Shape file path is canonically "relative to `.scp` file." For the `.jl` codegen, the rebin call uses `@__DIR__` which is relative to the `.jl` file — semantics of where the CSV "lives" need user confirmation when the user exports `.jl` to a different directory than the `.scp`. D-24 + Pitfall 5. | Common Pitfalls > Pitfall 5 | Medium — get explicit user confirmation. Phase 62 v1 ships "relative to .scp" + the user copies the CSV manually when they export `.jl` to a different folder. |
| A9 | The separable z-then-x order for `rebin_extensive` is canonical. Sum-conservation holds regardless of order (per ESMF), but matrix values may differ at ULP between orders. Test should only assert sum-conservation. | Pitfall 6 | Low — pick one order and document. |
| A10 | Phase 62 keeps the existing flat-string codegen shape (just inserts a Resources block prefix). Section-block UI (Phase 66) is out of scope. | CONTEXT.md OOS list confirms this. | None — explicitly locked. |

**Action for planner / discuss-phase:** All `[ASSUMED]` items above (especially A1, A4, A8) are worth surfacing to the user as quick confirmation questions before Wave 1 starts.

## Open Questions

1. **`tauri.conf.json` file association.**
   - What we know: Tauri 2 supports `fileAssociations` in `tauri.conf.json` for the desktop OS to associate `.streamgui` with the Composer app.
   - What's unclear: Whether the project currently uses this. I did not read the config in this research pass.
   - Recommendation: Wave 1 read `gui/src-tauri/tauri.conf.json`. If `fileAssociations` exists for `.streamgui`, add to the renamer surface in `D-28`.

2. **Codegen seam for the per-HD Power Shape recipe call.**
   - What we know: Per D-21, the helper takes `(nz, nx)` at script runtime. The HeatDiffusion consumer's `nz`/`nx` are component parameters known at codegen time.
   - What's unclear: Whether to emit the recipe call as a SEPARATE statement per HeatDiffusion (e.g., `power_shape_mtr_for_hd_1 = cosine_power_shape(10, 5)`) or inline at the constructor call (`@named hd_1 = HeatDiffusion(; ..., power_shape=cosine_power_shape(10, 5; amplitude=1.0))`). The Specifics CONTEXT examples show the separate-statement form. Plan should follow that — separate statement gives the user a named variable to inspect/tweak in the generated `.jl`.
   - Recommendation: Separate statement per HD consumer. Resource gets emitted once per HD consumer; the variable name encodes the resource and consumer (e.g., `power_shape_<resource_name>_for_<hd_instance>`) OR a global per-resource if only one HD consumes it. Planner picks the naming convention.

3. **Fluids placeholder editor body.**
   - What we know: Single non-editable `light_water` row (D-03).
   - What's unclear: Whether selecting it shows ANY right-panel content or stays on "No selection."
   - Recommendation: Selecting `light_water` shows a read-only fluid editor body with "rho, cp, mu, k are baked in for v1; AbstractFluid abstraction is v0.6+." Helps the user understand why they can't edit it.

4. **Empty-state copy variations.**
   - What we know: D-20 fixes the single-line for "no geometries yet" and "no power shapes yet."
   - What's unclear: What the dropdown shows when it has the `unset` sentinel as its only entry (i.e., zero user-defined Power Shapes). Does the empty-state copy still appear, or does the sentinel make it "non-empty"?
   - Recommendation: Sentinel is a real entry — empty-state copy does NOT show. Make this explicit in the plan to prevent regression.

5. **Tree widget — search box scope.**
   - What we know: D-03 says top search box on the Resources tab.
   - What's unclear: Whether search is per-group or global across all three groups.
   - Recommendation: Global. The user types `mtr` and any Geometry / Power Shape / Fluid with `mtr` in the name highlights. Simpler implementation; matches expectation.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `radix-ui` (meta) | `Popover`, `ContextMenu` shims | ✓ | `^1.4.3` | — |
| `@radix-ui/react-popover` | New popover.tsx shim | ✓ (transitive) | `1.1.15` | — |
| `@radix-ui/react-context-menu` | New context-menu.tsx shim | ✓ (transitive) | `2.2.16` | — |
| `zustand` | Resources slice | ✓ | `^5.0.12` | — |
| `vitest` + `@testing-library/react` | New tests | ✓ | `^4.1.2` / `^16.3.2` | — |
| `crypto.randomUUID()` | Resource UUIDs | ✓ (Web Crypto API in Tauri WebView) | — | `uuid` package (not needed) |
| Julia `DelimitedFiles` | `readdlm` in codegen-emitted scripts | ✓ (Base stdlib) | — | — |
| `bin/jl-up` + daemon | Running `test_utilities.jl` fast | ✓ | — | Cold-start `julia --project=. test/test_utilities.jl` |
| `npm` / `cargo` | Build verification | ✓ | — | — |

**No missing dependencies.** No new `npm install` or `Project.toml` edits required.

## Validation Architecture

> Nyquist Dimension 8 — conservation laws, invariants, round-trip equalities. Phase 62 has rich invariants because the entire phase is about state consistency.

### Test Framework

| Property | Value |
|----------|-------|
| GUI framework | vitest 4.1.2 + happy-dom 20.8.9 + @testing-library/react 16.3.2 |
| GUI config file | `gui/vitest.config.ts` (existing; not changed) |
| GUI quick run | `cd gui && npx vitest run --passWithNoTests` |
| GUI full suite | `cd gui && npm test` |
| Julia framework | `Test` (Base stdlib) + custom orchestrator at `test/runtests.jl` |
| Julia config file | `test/runtests.jl` |
| Julia quick run | `bin/jl test/test_utilities.jl` |
| Julia full suite | `bin/jl test/runtests.jl` |
| Phase gate | Both suites green before `/gsd-verify-work` |

### Conservation Laws and Invariants (the heart of this phase)

| Invariant | What it Asserts | Where to Test |
|-----------|-----------------|---------------|
| **CONS-01:** `sum(rebin_extensive(M, target)) ≈ sum(M)` to ≤ 1e-12 rel | The conservative regrid preserves total integrated quantity. Tested across: identity (n→n), integer up (3→9), integer down (9→3), non-integer (5→7), 1×N degenerate row, N×1 degenerate column, all-zeros, all-ones, random uniform [0,1] | `test/test_utilities.jl` |
| **CONS-02:** `rebin_extensive(M, size(M)) == M` (identity case) | Strict equality when source and target shapes match | `test/test_utilities.jl` |
| **CONS-03:** `rebin_extensive(ones(a, b), (c, d)) ≈ (a * b / c / d) * ones(c, d)` | Uniform input rebins to scaled uniform output (the simplest non-trivial case) | `test/test_utilities.jl` |
| **CONS-04:** `cosine_power_shape(nz, nx)` produces a matrix uniform along x for every z | All columns equal; rows show cosine profile | `test/test_utilities.jl` |
| **INV-01:** UUID uniqueness — for every resource added, its UUID is not already in the store | Resource creation invariant | `gui/src/store/__tests__/useStore.test.ts` (Resources slice) |
| **INV-02:** Name uniqueness per kind — two geometries cannot share a name; a geometry and a power shape CAN share a name | D-10 explicit | Store unit test |
| **INV-03:** Rename propagation — after renaming a geometry, all `geometry_ref` lookups still resolve | Lookup-at-render shape | Component test (`ResourceReferencePicker.test.tsx`) |
| **INV-04:** Copy-paste preserves FK — duplicating a component does NOT duplicate its Resource | D-13 | Store test (`duplicateNode` action) |
| **INV-05:** Deleting a referenced Resource leaves dangling refs — Phase 62 does NOT cascade-delete components; it leaves the FK dangling. The dangling-ref UX (warning ring / red highlight) is Phase 71's job. | Store + render test asserting that deleting Resource X leaves component with `geometry_ref: X` and the picker shows it as `(missing: X)` or similar | Store test |
| **INV-06:** Active-left-tab persists in `.scp` `layout` block — save then load round-trips the tab. | D-08 / D-29 | `projectIO.test.ts` |
| **INV-07:** Hard cutover — `deserializeProject` of a legacy `{ version: 2, nodes: [...] }` (numeric, no `format_version`) THROWS, does not silently migrate. | D-28 | `projectIO.test.ts` |
| **INV-08:** `_pushSnapshot` covers Resource ops — `addResource` → `undo` reverts; `renameResource` → `undo` reverts; `removeResource` → `undo` reverts | Snapshot extension correctness | `useStore.test.ts` |
| **INV-09:** Selection scope is exclusive — selecting a Resource clears `selectedNodeId`; selecting a node clears `selectedResourceId`; Esc clears both. | D-05 | `useStore.test.ts` + `SidebarPanel.test.tsx` |
| **INV-10:** Codegen — for every Resource in the store, the generated code declares a Julia variable matching the Resource's `name`. Component constructor emission uses that variable name, not the inline value. | Whole-phase invariant | `codeGenerator.test.ts` (a new test) |
| **INV-11:** Codegen — `unset` Power Shape emits `ones(nz, nx)  # TODO: fill in your power shape` | D-26 | `codeGenerator.test.ts` |
| **INV-12:** Codegen — `file_loaded` Power Shape emits `rebin_extensive(readdlm(...), (nz, nx))` with the consumer's `nz`/`nx` literal values | D-25 | `codeGenerator.test.ts` |
| **INV-13:** Save round-trip — for any in-memory store state, `deserializeProject(serializeProject(state)) === state` (structurally). | Persistence safety | `projectIO.test.ts` |
| **INV-14:** Tauri filter & extension — every Tauri save/open dialog filter spells `.scp`, never `.streamgui`. (Codebase grep test.) | D-28 cleanup | `useStore.test.ts` or a static grep in CI |
| **INV-15:** `ResourceReferencePicker` empty-state copy — when zero resources of the kind exist, the dropdown shows the D-20 string. | D-20 | `ResourceReferencePicker.test.tsx` |
| **INV-16:** `+ New…` popover — `onInteractOutside` does not dismiss; Esc does. | D-16 | `ResourceReferencePicker.test.tsx` with user-event |
| **INV-17:** `Edit…` jump — clicking `Edit…` sets `activeLeftTab = "Resources"`, `selectedResourceId = <uuid>`, `selectedNodeId = null` | D-18 | `useStore.test.ts` |

### Phase Requirements → Test Map

Decision IDs map to test IDs (since the phase has no formal REQ-IDs).

| Decision | Behavior | Test Type | Automated Command | File Exists? |
|----------|----------|-----------|-------------------|--------------|
| D-01 / D-07 | Left-panel tab strip + Ctrl+1/2/3 keyboard | component | `npx vitest run src/components/__tests__/AppShell.test.tsx` | ❌ Wave 0 |
| D-03 | Resources tree renders 3 group headers + `+` + context menu | component | `npx vitest run src/components/resources/__tests__/ResourcesTreePanel.test.tsx` | ❌ Wave 0 |
| D-04 | Project tab body IS the Model Options form (no inner selection) | component | `npx vitest run src/components/project/__tests__/ModelOptionsPanel.test.tsx` | ❌ Wave 0 |
| D-05 / D-09 / D-10 / INV-01..05, INV-08, INV-09 | Resources slice + selection-kind router | unit (store) | `npx vitest run src/store/__tests__/useStore.test.ts -t resources` | ✅ extend |
| D-08 / INV-06 | active_left_tab serializes/deserializes | unit (lib) | `npx vitest run src/lib/__tests__/projectIO.test.ts` | ✅ extend |
| D-14..D-20 / INV-15, INV-16, INV-17 | Reference picker (dropdown + + New… + Edit…) | component | `npx vitest run src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx` | ❌ Wave 0 |
| D-21..D-26 / CONS-01..04 | rebin_extensive + cosine_power_shape | Julia unit | `bin/jl test/test_utilities.jl` | ❌ Wave 0 |
| D-25 / INV-12 | Codegen emits `rebin_extensive(readdlm(...), (nz, nx))` | unit (lib) | `npx vitest run src/lib/__tests__/codeGenerator.test.ts -t "Resources block"` | ✅ extend |
| D-26 / INV-11 | Codegen emits `ones(nz, nx)  # TODO` for unset | unit (lib) | `npx vitest run src/lib/__tests__/codeGenerator.test.ts -t unset` | ✅ extend |
| D-27 / D-28 / INV-07, INV-13, INV-14 | `.scp` v2.0 serialize/deserialize + reject legacy + Tauri filter says `.scp` | unit (lib + store) | `npx vitest run src/lib/__tests__/projectIO.test.ts` + grep test | ✅ extend |
| D-30 | Sources category header renders empty | component | `npx vitest run src/components/__tests__/ToolboxPanel.test.tsx` | ❌ Wave 0 (no existing test for ToolboxPanel) |

### Sampling Rate

- **Per task commit:** `cd gui && npx vitest run --passWithNoTests` for any GUI-touching task; `bin/jl test/test_utilities.jl` for any `src/utilities.jl` change.
- **Per wave merge:** Full vitest (`npm test`) + full Julia (`bin/jl test/runtests.jl`).
- **Phase gate:** Both suites green; `npm run build` produces no new tsc errors above the 7-error baseline documented in `.planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md`.

### Wave 0 Gaps (new test files / fixtures needed)

- [ ] `test/test_utilities.jl` — covers CONS-01 through CONS-04
- [ ] `gui/src/components/__tests__/AppShell.test.tsx` (or extend an existing) — covers D-01 / D-07
- [ ] `gui/src/components/__tests__/ToolboxPanel.test.tsx` — covers D-30 (file does not exist today)
- [ ] `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx` — covers D-03
- [ ] `gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx` — covers D-04
- [ ] `gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx` — covers D-14..D-20
- [ ] `gui/src/components/sidebar/__tests__/GeometryResourceEditor.test.tsx` — extracted from existing `PipeGeometryPicker.test.tsx`
- [ ] `gui/src/components/sidebar/__tests__/PowerShapeResourceEditor.test.tsx` — covers D-22 kind selector
- [ ] `gui/export_examples/simple_loop.scp` — fixture for `loadProjectFromPath` round-trip test (also serves as a real example file shipped to users)
- [ ] Extend `gui/src/lib/__tests__/projectIO.test.ts` for INV-06, INV-07, INV-13
- [ ] Extend `gui/src/store/__tests__/useStore.test.ts` for INV-01..05, INV-08, INV-09, INV-17
- [ ] Extend `gui/src/lib/__tests__/codeGenerator.test.ts` (or create — file currently is `codeGenerator.test.ts` at `gui/src/lib/codeGenerator.test.ts`, not in `__tests__/`) for INV-10..12

## Sources

### Primary (HIGH confidence)

- `/home/itay/projects/Julia-STREAM/.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` — D-01..D-30 + CD-01..CD-05 + Specifics + Deferred. The single most authoritative source for this phase.
- `/home/itay/projects/Julia-STREAM/.planning/notes/gui-redesign-design-decisions.md` §3.2 (lines 204-310), §3.5 (lines 490-545), §3.8, §3.14 (lines 1151-1232), §4 cross-cutting invariants (lines 1236-1260) — design contract.
- `/home/itay/projects/Julia-STREAM/CLAUDE.md` — Branching policy, file structure standard, MTK patterns, daemon dev loop.
- `/home/itay/projects/Julia-STREAM/gui/src/store/useStore.ts` lines 200-249 — `_pushSnapshot` discipline (the foundation Phase 62 extends).
- `/home/itay/projects/Julia-STREAM/gui/src/lib/projectIO.ts` lines 36-92 — current serialize/deserialize; lines 87-89 are the v1→v2 migration that gets removed.
- `/home/itay/projects/Julia-STREAM/gui/src/lib/codeGenerator.ts` lines 182-255, 566-823 — current codegen seam.
- `/home/itay/projects/Julia-STREAM/gui/src/registry/components.json` lines 1-105, 970-1015 — Phase 61's v1.1 registry that Phase 62 consumes unchanged. Confirms `geometry` is currently `type: "PipeGeometry"`, `power_shape` is `type: "Matrix"` — NOT yet a `"ResourceRef"` type.
- `/home/itay/projects/Julia-STREAM/gui/src/registry/types.ts` lines 85-202 — `Parameter` + `ExternalInput` shapes.
- `/home/itay/projects/Julia-STREAM/gui/package-lock.json` lines 1410, 1841 — confirms `@radix-ui/react-context-menu@2.2.16` and `@radix-ui/react-popover@1.1.15` are transitively available via the `radix-ui` aggregator.
- `/home/itay/projects/Julia-STREAM/src/components/heat_diffusion.jl` lines 1-100 — `power_shape[i,j]` is dimensionless, normalized externally; caller-trust.
- `/home/itay/projects/Julia-STREAM/src/STREAM.jl` lines 1-104 — export discipline; Phase 62 adds `rebin_extensive`, `cosine_power_shape` to the export list at the appropriate `export` block.
- `/home/itay/projects/STREAM/stream/composition/mtr_geometry.py` lines 297-335 — Python `uniform_x_power_shape` reference shape.
- `/home/itay/projects/Julia-STREAM/.planning/phases/61-registry-audit-rewrite-for-v1-1/61-05-SUMMARY.md` — confirms Phase 61 deliberately did NOT touch GUI rendering for new categories; Sources visibility is Phase 62's responsibility.

### Secondary (MEDIUM confidence, web-verified)

- `https://www.radix-ui.com/primitives/docs/components/popover` — Radix Popover API surface; `onInteractOutside` is the documented escape hatch.
- `https://github.com/radix-ui/primitives/issues/646` — Known caveat: `e.preventDefault()` in `onInteractOutside` prevents focus return. Relevant to Pitfall 1.
- `https://github.com/radix-ui/primitives/discussions/1997` — Radix's stance on dismissable-layer interaction. Confirms the `e.preventDefault()` pattern is intended for this use case.
- `https://earthsystemmodeling.org/regrid/` and `https://gmd.copernicus.org/articles/17/415/2024/` — Conservative regridding background; area-weighted reassignment is the standard "first-order conservative remap" used by ESMF, xESMF, HARP. Confirms the separable 1D approach is canonical.

### Tertiary (LOW confidence, flagged for validation)

- The exact cosine discretization for `cosine_power_shape` (cell-centered cosine-squared) is my best guess at Python parity. A small parity spike in Wave 1 should confirm before locking the formula. `[ASSUMED]` A4 above.
- The Tauri 2 `fileAssociations` field shape — I did not read `tauri.conf.json` in this pass. Wave 1 read is needed. `[ASSUMED]` A7.

## Metadata

**Confidence breakdown:**
- User decisions / locked constraints: HIGH — CONTEXT.md is authoritative and exhaustive for this phase.
- Standard stack: HIGH — every package is already in `package-lock.json`; no new dependencies needed.
- Architecture patterns (store extension, selection router, codegen seam): HIGH — directly grounded in existing code with line numbers.
- Radix Popover non-dismiss: HIGH — primary API; MEDIUM on the focus-return caveat (cite is solid; needs smoke-test).
- `rebin_extensive` algorithm sketch: MEDIUM — algorithm is canonical, code sketch is `[ASSUMED]` and should be cross-checked with a Python comparison spike before locking.
- `cosine_power_shape` formula: MEDIUM — same caveat; Python parity spike needed.
- File-extension cutover surface: HIGH — grep-able and well-bounded.
- Test invariants list: HIGH — derived from D-NN with explicit cross-references.

**Research date:** 2026-05-13
**Valid until:** 2026-06-13 (1 month; the foundation pieces are stable. Radix versions may drift but won't break the API.)

---

*Phase: 62-resources-panel-architecture*
*Research complete: 2026-05-13*
