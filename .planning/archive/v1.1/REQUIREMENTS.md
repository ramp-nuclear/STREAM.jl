# Requirements: STREAM.jl — v1.1 Final Channel-Family Redesign

**Defined:** 2026-05-05
**Core Value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Branch:** `channels-redesign` (single PR at end)

---

## v1.1 Requirements

Final rewrite of the three Channel components so they match Python STREAM's design intent and never need touching again. Each requirement maps to exactly one phase in the v1.1 roadmap.

### Connectors

**Connector pattern:** scalar MTK acausal connectors instantiated as **arrays** per side per channel — matching the existing `ChannelAndContacts` pattern (`thermal_left[1:n]`, `thermal_right[1:n]`). Vector-form connectors (single per side carrying array variables) were investigated via spike on 2026-05-05 and rejected: they exhibit a reproducible MTK bug where the first unknown of the vector system mis-integrates when scalar-port systems (e.g., `FlowPort`) coexist in the same compiled session, which is unavoidable in any realistic `build_loop`.

- [x] **CONN-01**: New scalar MTK acausal connector type `WallPort` carrying `T_wall`, `h`, and `Q_flow` (the last as `[connect = Flow]`). Used by `Channel` as arrays `thermal_left[1:n]`, `thermal_right[1:n]`. Adiabatic when unconnected (port defaults give `q = 0` per cell automatically).
- [x] **CONN-02**: New scalar MTK acausal connector type `HeatFluxPort` carrying `q_flux` and `Q_flow` (the last as `[connect = Flow]`). Used by `ChannelHeatFlux` as arrays `thermal_left[1:n]`, `thermal_right[1:n]`. Zero-flux when unconnected. **Superseded by Phase 55 D-06 (2026-05-07):** `HeatFluxPort` is retired in Phase 55 because `ChannelHeatFlux` drops its per-cell ports in favor of channel-level external-input variables `q_left[1:n]` / `q_right[1:n]`. Direct binding eqns (`chf.q_left[i] ~ value`) and `HeatFluxSource` value-source components both replace the connector-based driver pattern. The architectural rule (`feedback_channel_hd_connection_rule.md`) — only `ChannelAndContacts` connects to `HeatDiffusion` — means CHF never needed a Flow-based port. Mirrors the Phase 54 walk-back of CONN-01 (`WallPort`). End-of-v1.1 connector roster: `FlowPort` + `ThermalPort` only.
- [x] **CONN-03**: `ChannelAndContacts` continues to expose per-cell, per-side `T_wall` via existing `ThermalPort` arrays (`thermal_left[1:n]`, `thermal_right[1:n]`); no connector change. Only verify it composes cleanly with the refactored `Channel` and `ChannelHeatFlux` variants.
- [x] **CONN-04**: All new connectors honor MTK acausal semantics: `connect()` works idiomatically, composition helpers can wire array-of-scalar ports per cell via existing patterns, no special-case wiring tricks required from callers.

### Shared Core

- [x] **CORE-01**: Single private `_channel_core(...; q_left_expr, q_right_expr)` function exists that emits energy balance, mass conservation, momentum ODE `(L/A)·D(mdot)`, friction `dp[i]`, port wiring, and observables (Re, Pe, P[i], T_sat, T_ONB, dP) — single source of truth for all three variants
- [x] **CORE-02**: `_channel_base_eqs` helper is removed entirely from `src/components/channel.jl`
- [x] **CORE-03**: No `observed_mode` flag in any helper or variant constructor; internal DAE-shape decisions (which symbols become observed vs. unknown) are private implementation details of each variant
- [x] **CORE-04**: No `skip_htc` flag anywhere; SCB correction is implemented entirely inside `ChannelAndContacts`'s h-computation, with no helper coordination
- [x] **CORE-05**: No `T_wall_cells=nothing` default or other dead branch in shared code; every code path is reachable by at least one variant

### Variants

- [x] **VAR-01**: `Channel` rewritten as a passive recipient: external `T_wall` arrives per-cell via the existing `ThermalPort` arrays (`thermal_left[1:n]`, `thermal_right[1:n]`); `h_left` and `h_right` are supplied as Channel constructor kwargs (each `Real | AbstractVector | Callable`, default `0.0`) → `q_side[i] = h_side[i] · (T_wall_side[i] − T[i])` → energy balance via `_channel_core`. Adiabatic by default: IC `h=0.0` + `ThermalPort`'s 1-across-1-flow Flow-rule auto-zero closes the system without user equations. WallPort (the original Phase 52 / CONN-01 deliverable) was retired during Phase 54 discuss after a spike (`/tmp/spike_input_true.jl`, 2026-05-07) confirmed that 2-across-1-flow connectors cannot deliver automatic adiabatic-when-unconnected via IC defaults or `[input = true]`. See `feedback_channel_hd_connection_rule.md`: only `ChannelAndContacts` ever connects to `HeatDiffusion`; `Channel` and `ChannelHeatFlux` never do.
- [x] **VAR-02**: `ChannelHeatFlux` rewritten to receive `q_left[i], q_right[i]` directly via the CONN-02 connector. Scalar `T_wall` parameter and internal h-correlation removed.
- [x] **VAR-03**: `ChannelAndContacts` rebuilt on `_channel_core`: receives per-cell, per-side `T_wall` via ThermalPort arrays; computes h via correlation; supports optional `scb_correction` keyword that augments the h expression (no flag plumbing).
- [x] **VAR-04**: `src/components/channel.jl` and `src/components/thermal_channel.jl` consolidated into a single file `src/components/channels.jl` (plural, matching the `connectors.jl`/`resistors.jl` pattern for files holding multiple related components). Old files deleted; `STREAM.jl` `include` line and `CLAUDE.md` File Structure Standard updated to reflect the new layout. No duplicated physics — one concrete location for friction, momentum, energy balance.

### Energy Balance Scheme (Enthalpy Form)

- [x] **NRG-01**: Convective term numerator uses face-averaged cp between cell `i` and its upstream neighbor: `(cp(T_up) + cp(T[i])) / 2`
- [x] **NRG-02**: At the boundary face of cell 1 (forward flow) and cell n (reverse flow), upstream cp is `cp(T_in)` from the appropriate `instream(port_in.T)` / `instream(port_out.T)` — not `cp(T[1])` or `cp(T[n])`
- [x] **NRG-03**: Heat-capacity denominator retains local `cp(T[i])` (Python's `c_bulk`); the two cp values do not cancel
- [x] **NRG-04**: Flow reversal: same `ifelse(mdot ≥ 0, ...)` pattern that already selects upstream T also selects upstream cp; symmetric in both directions

### Tests, Examples, Composition

- [x] **TEST-01**: `test/test_channels.jl` rewritten under the new design (Channel/CHF/CAC variant unit tests + `_channel_core` enthalpy-form physics + flow-reversal sign tests, all merged in); legacy `test/test_channel.jl` deleted; surviving `CHAN-*`, `GRAV-*`, `THERM-*`, `PHY-*` test concepts re-derived in their canonical homes (variant-level tests in `test_channels.jl`, full-loop solves in `test_integration.jl`). Wording updated 2026-05-07 during Phase 55 discuss to reflect the rewrite-not-port frame and the test-layout consolidation onto Python STREAM rules — see `.planning/phases/55-composition-helpers-examples-test-suite/55-CONTEXT.md` D-17.
- [x] **TEST-02**: All shipped builders (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`, `build_loop_pk`) and any scripts in `examples/` build and solve without regression
- [x] **TEST-03**: Composition helpers (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems` in `src/composition/helpers.jl`) updated for new connector types; MTR assembly tests pass
- [x] **TEST-04**: Cross-validation against Python STREAM passes: simple_loop scenario fully CLEAN at ≤1e-11 rtol; MTR scenarios at 424 CLEAN / 78 GRAY / 34 FAIL with all FAILs traced to documented Python-side bugs or asymmetric MTR topology drift (deferred to v1.2 with named cause per MILESTONES.md v1.1 entry)
- [x] **TEST-05**: Full test suite passes locally via `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl` without the daemon)

---

## Out of Scope

Explicitly excluded from v1.1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| New HTC or friction correlations | None needed for the redesign; existing library (`src/physical_models/htc/` and `src/physical_models/friction/`) is sufficient |
| New fluid properties or pressure-dependent ρ | Per-cell `@register_symbolic` evaluation already correct; matches Python's saturated-liquid assumption |
| HeatDiffusion redesign | Stable; only its connection points may need adjustment to match new connector types (covered under TEST-03) |
| New simulation features beyond the Channel family | Out of v1.1 mandate ("LAST channel rewrite, nothing else") |
| GUI component-registry sync | Defer to a later GUI milestone if registry JSON needs updating; v1.1 is library-only |
| Migrating to a multi-fluid (`AbstractFluid`) abstraction | Out of scope; light water remains the only fluid through v1.1 |
| Python adapter / juliacall coupling | Validation is by hardcoded reference constants in tests, not runtime Python invocation |

---

## Traceability

Each requirement maps to exactly one phase in the v1.1 roadmap (Phases 52-56).

| Requirement | Phase | Status |
|-------------|-------|--------|
| CONN-01 | Phase 52 | Complete |
| CONN-02 | Phase 52 | Complete |
| CONN-03 | Phase 52 | Complete |
| CONN-04 | Phase 52 | Complete |
| CORE-01 | Phase 53 | Complete |
| CORE-02 | Phase 53 | Complete |
| CORE-03 | Phase 53 | Complete |
| CORE-04 | Phase 53 | Complete |
| CORE-05 | Phase 53 | Complete |
| VAR-01 | Phase 54 | Complete |
| VAR-02 | Phase 54 | Complete |
| VAR-03 | Phase 54 | Complete |
| VAR-04 | Phase 54 | Complete |
| NRG-01 | Phase 53 | Complete |
| NRG-02 | Phase 53 | Complete |
| NRG-03 | Phase 53 | Complete |
| NRG-04 | Phase 53 | Complete |
| TEST-01 | Phase 55 | Complete |
| TEST-02 | Phase 55 | Complete |
| TEST-03 | Phase 55 | Complete |
| TEST-04 | Phase 56 | Complete |
| TEST-05 | Phase 55 | Complete |

**Coverage:**
- v1.1 requirements: 22 total
- Mapped to phases: 22 ✓
- Unmapped: 0

**Per-phase rollup:**

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 52 — Channel Connectors | CONN-01, CONN-02, CONN-03, CONN-04 | 4 |
| Phase 53 — Shared `_channel_core` + Enthalpy-Form Energy Balance | CORE-01..05, NRG-01..04 | 9 |
| Phase 54 — Variant Rewrites & File Consolidation | VAR-01, VAR-02, VAR-03, VAR-04 | 4 |
| Phase 55 — Composition Helpers, Examples & Test Suite | TEST-01, TEST-02, TEST-03, TEST-05 | 4 |
| Phase 56 — Python STREAM Cross-Validation | TEST-04 | 1 |

---

*Requirements defined: 2026-05-05*
*Last updated: 2026-05-09 — all 22 v1.1 requirements Complete: VAR-01..04 (Phase 54), TEST-04 (Phase 56-resume close-up: simple_loop fully CLEAN, MTR scenarios 424/78/34 with all FAILs traced to documented Python-side bugs or v1.2-deferred topology drift per MILESTONES.md v1.1 entry).*
