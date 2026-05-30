---
phase: 62
slug: resources-panel-architecture
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-13
---

# Phase 62 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Julia)** | Test.jl via `bin/jl` daemon |
| **Framework (GUI)** | Vitest (TBC by planner — confirm in `gui/package.json`) |
| **Config file** | `Project.toml`; `gui/vitest.config.ts` |
| **Quick run command (Julia)** | `bin/jl test/test_utilities.jl` |
| **Full suite command (Julia)** | `bin/jl test/runtests.jl` |
| **Quick run command (GUI)** | `cd gui && npm test -- --run <slice>` |
| **Full suite command (GUI)** | `cd gui && npm test -- --run` |
| **Estimated runtime** | Julia full ~60–120s warm; GUI full ~10–30s |

---

## Sampling Rate

- **After every task commit:** quick command for the touched slice (Julia file or GUI test file)
- **After every plan wave:** full suite (Julia + GUI)
- **Before `/gsd-verify-work`:** both full suites must be green
- **Max feedback latency:** ~60s warm Julia path; ~30s GUI

---

## Per-Task Verification Map

> Populated by `gsd-planner`. Each task in each PLAN.md must point to one of the conservation/structural invariants below (CONS-* or INV-*) or carry an explicit manual entry.

| Task ID | Plan | Wave | Decision Ref | Invariant | Test Type | Automated Command | File Exists | Status |
|---------|------|------|--------------|-----------|-----------|-------------------|-------------|--------|
| 62-XX-YY | XX | N | D-NN | CONS-NN / INV-NN | unit | `bin/jl test/<file>` or `npm test --run <file>` | ✅ / ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

> Test files / fixtures that MUST exist (created or stubbed) before any wave-N task can commit. Derived from `62-RESEARCH.md` "Validation Architecture" section.

### Julia side
- [ ] `test/test_utilities.jl` — new; covers `rebin_extensive` sum-conservation and `cosine_power_shape` shape correctness
- [ ] `test/runtests.jl` — append `include("test_utilities.jl")` line (mirror rule, CLAUDE.md test layout)

### GUI side
- [ ] `gui/src/store/__tests__/resources.slice.test.ts` — new; Resources store-slice CRUD + uniqueness-per-kind + undo/redo snapshot integration
- [ ] `gui/src/store/__tests__/modelOptions.test.ts` — new; Model Options state + persistence
- [ ] `gui/src/store/__tests__/activeLeftTab.test.ts` — new; active tab persistence in `.scp` layout block
- [ ] `gui/src/lib/__tests__/projectIO.scp.test.ts` — new; `.scp` v2.0 round-trip (save → load → equal); rejects `.streamgui` cleanly
- [ ] `gui/src/lib/__tests__/codeGenerator.resources.test.ts` — new; Resources block emitted first; component constructor uses resource-variable name; four Power-Shape kinds emit per CONTEXT.md Specifics examples
- [ ] `gui/src/components/__tests__/ReferencePicker.test.tsx` — new; popover open / Esc dismiss / click-outside no-dismiss / Create commits + auto-selects / `Edit…` jump to Resources tab
- [ ] `gui/src/components/__tests__/ResourcesTab.test.tsx` — new; tree render, `+` add, inline rename (F2), context menu, search filter
- [ ] `gui/src/components/__tests__/ProjectTab.test.tsx` — new; Model Options form fields render and bind
- [ ] `gui/src/components/__tests__/SidebarRouter.test.tsx` — new; selection-kind exclusivity; header text per kind; Esc clears
- [ ] Fixture: `gui/src/__fixtures__/sample_v2.scp.json` — minimal valid v2.0 project for round-trip tests
- [ ] Fixture: `gui/src/__fixtures__/sample_power_shape.csv` — small CSV for `file_loaded` rebin test path

---

## Conservation & Structural Invariants

Derived from RESEARCH.md. Every executor task should cite an ID here in its acceptance criteria.

### Numerical conservation (Julia)
- **CONS-01** — `sum(rebin_extensive(A, (nz_out, nx_out))) ≈ sum(A)` to floating-point precision across upsampling, downsampling, non-integer ratios, and identity (D-25)
- **CONS-02** — `rebin_extensive` is identity when `(nz_out, nx_out) == size(A)` (no resampling artifacts)
- **CONS-03** — `cosine_power_shape(nz, nx; amplitude=1.0)` produces axial cosine, uniform along x (parity with Python STREAM `uniform_x_power_shape`)
- **CONS-04** — Codegen-emitted scripts that include `power_shape = ...` followed by HeatDiffusion with `(nz, nx)` solve to the same temperatures as the Python STREAM reference for the same model (golden parity)

### State / persistence (GUI)
- **INV-01** — Component never carries an inline `geometry` / `power_shape` value; only `geometry_ref` / `power_shape_ref` UUIDs (D-09)
- **INV-02** — Renaming a Resource never produces a broken reference; all consumers re-render with the new label (D-12)
- **INV-03** — Copy-paste of a component preserves the FK; does NOT duplicate the Resource (D-13)
- **INV-04** — Per-kind name uniqueness enforced on add and on rename; `geometry_<n>` and `power_shape_<n>` may coexist (D-10)
- **INV-05** — UUIDs are minted once per Resource and never reused; deletion does not return the UUID to the pool (D-11)
- **INV-06** — `.scp` save→load round-trip is byte-equal for the semantic payload (resources, components, connections, model_options); layout block is preserved but excluded from the simulation-relevant diff (D-29)
- **INV-07** — `unset` Power Shape persists across save→load via the sentinel kind/UUID (D-22, D-26)
- **INV-08** — `format_version: "2.0"` is written on save; legacy `.streamgui` is rejected with a clear error (no migration shim) (D-27, D-28)
- **INV-09** — `file_loaded` Power Shape stores a path relative to the `.scp` file location; absolute paths are converted on save (D-24)
- **INV-10** — File-not-found on load surfaces a user-visible error with `Locate file…` action; does not crash the app (D-24)
- **INV-11** — Active left tab restores from `.scp` `layout.active_left_tab`; defaults to `"Components"` if missing (D-08)
- **INV-12** — `Ctrl+1/2/3` switches tabs without colliding with browser `Ctrl+Tab`; default-stop suppressed for the three accelerators only (D-07)

### UI behavior
- **INV-13** — Reference-picker popover does NOT dismiss on click-outside; only Esc / Cancel / successful Create dismiss (D-16)
- **INV-14** — On successful Create, dropdown auto-selects the new Resource, popover closes, focus moves to the next field (D-15)
- **INV-15** — `Edit…` switches the left tab to Resources, selects the row, right panel renders the Resource editor; one click on the canvas node returns to the component view (D-18)
- **INV-16** — Empty-state placeholder copy renders on every Resource-typed field when zero resources of that kind exist (D-20)
- **INV-17** — Selection-kind scopes are exclusive: selecting in one (canvas / resource / project) clears the others; Esc clears (D-05)

### Codegen
- **INV-CG-01** — Resource declarations are emitted BEFORE the first `@named` block in the generated Julia script (RESEARCH §codegen)
- **INV-CG-02** — Component constructors reference the resource by its emitted variable name (e.g., `geometry=geom_mtr`), never inline the resource's values
- **INV-CG-03** — For `file_loaded` Power Shapes, codegen emits the `rebin_extensive(readdlm(joinpath(@__DIR__, "shapes/<name>.csv"), ','), (nz, nx))` form (CONTEXT.md Specifics)
- **INV-CG-04** — For `unset` Power Shapes, codegen emits `power_shape_<name> = ones(nz, nx)  # TODO: fill in your power shape` (D-26)
- **INV-CG-05** — Generated scripts run end-to-end through `bin/jl` for at least one fresh `.scp` example fixture (smoke test)

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| Popover focus-return after Create | D-15 (Radix #646) | Radix `preventDefault` on `onInteractOutside` blocks autofocus chain; verify visually | Drop a Channel, open picker, `+ New…`, type a name, Enter → focus must land on the next Channel field |
| Brand-new-user discoverability flow | D-20 | One-time UX moment; not deterministic to assert via test | Fresh project, drop a Channel, observe empty-state copy renders and tooltip on `+ New…` makes the path obvious |
| Hard cutover from `.streamgui` | D-28 | Negative-case requires file-system state | Place a stale `.streamgui` in a temp dir, attempt to open, observe rejection without a migration prompt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags (use `--run` for vitest)
- [ ] Feedback latency < 60s (Julia warm) / < 30s (GUI)
- [ ] `nyquist_compliant: true` set in frontmatter after planner fills the Per-Task Verification Map

**Approval:** pending
