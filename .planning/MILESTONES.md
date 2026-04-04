# Milestones

## v0.8 STREAM Composer GUI (Shipped: 2026-04-04)

**Phases completed:** 13 phases, 32 plans, 47 tasks

**Timeline:** 2026-04-01 → 2026-04-04 (3 days)
**TypeScript/React LOC:** ~43,334 insertions across 232 files

**Key accomplishments:**

- Tauri 2 + React + ReactFlow desktop app scaffold with three-panel layout, Zustand store, Tailwind v4 + shadcn design tokens, Vitest configured; JSON registry of all 12 STREAM.jl components with TypeScript types and 14 validation tests
- Drag-drop canvas: ReactFlow wired with FlowPort connection validation, Delete/Backspace node removal, Ctrl+Z undo/redo (10+ ops), Hydraulic/Thermal toolbox categories; 30 tests all passing
- Parameter editing sidebar: registry-driven form dispatching, on-blur validation, PipeGeometry picker, Pump mode toggle, factory correlation pickers (regime_dependent, elenbaas_htc, maximal_htc) with nested sub-parameter fields
- Pure code generator transforms canvas graph → valid STREAM.jl Julia code with positional/keyword arg handling, factory param recursion, and default elision; live preview panel + Tauri file save export
- Project persistence: save/load .streamgui JSON, unsaved-changes guard, WelcomeOverlay with recent files, keyboard shortcuts (Ctrl+S/O/N/Shift+S), close guard with dialog; 7 real-runtime bug fixes including WSLg title workaround and kbLock mutex
- UI suite: Lucide icon map, shadcn/ui throughout, topology validation (11 TDD tests, error rings, gated export), thermal composition code-gen (symmetric_plate/plate/one_sided_connection detection), layered canvas (Hydraulic/Thermal toggle with dimming), arrowhead + parallel edge routing + FlowPort polarity colors, light/dark/system theme toggle with FOUC prevention

**Known Gaps (tech debt):**

- FileMenu has no Open Recent submenu — recent projects only accessible via WelcomeOverlay (PERS-04 partial)
- Windows .exe installer deferred — requires Windows + Rust build environment (SCAF-02 partial)
- Dead prop: resolvedTheme in Toolbar Props not destructured in function body (Phase 44)

---

## v0.7 Safety Physics & Pressure Field (Shipped: 2026-04-01)

**Phases:** 27, 27.1, 28, 29, 30, 31, 32 (7 phases, 13 plans)
**Julia LOC:** 7,715 (src + test) at completion
**Timeline:** 2026-03-27 → 2026-04-01 (5 days)
**Requirements:** 34 total (33 complete + 1 intentionally deferred: VAL-PRES-01)

**Key accomplishments:**

- Per-cell pressure field (dp[i], P[i]) across all three channel variants; dP refactored to exact sum; sat_temperature @register_symbolic; T_sat[i] and T_ONB[i] as @observed in ChannelAndContacts and ChannelHeatFlux (PRES-01..04)
- Distributed momentum ODE (L/A)*Dt(mdot) in Channel, ChannelAndContacts, ChannelHeatFlux; P[i] with distributed inertia correction; all PRES-05..12 transient tests passing (PRES-05..12)
- Subcooled boiling suite: McAdams + Bergles-Rohsenow SCB correlations, partial_SCB_correction, regime_dependent_q_scb factory, in-loop SCB correction for ChannelAndContacts via ifelse(T_wall >= T_ONB) (SCB-01..04, ISCB-01..02)
- Nuclear safety threshold analysis: 8 physics functions (Bergles-Rohsenow T_ONB, q_OFI Whittle-Forgan, q_OSV Saha-Zuber, 3×CHF, twall_limit) + ChannelState struct + threshold_analysis() dispatcher + chfr() factory + 8 pre-built wrappers (THRS-01..09)
- Complete HTC/friction correlation library: Marco_Han_Nusselt, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc, turbulent_friction (Colebrook-White), viscosity_correction; correlations.jl split into htc/ + friction/ subdirs (HTC-01..04, FRIC-01..02)
- Audit gap closure: 27-VERIFICATION.md written retroactively from VALIDATION.md evidence; _extract_channel_state ArgumentError guard + E2E solve→extract→analyze pipeline test; Phase 30 in-system smoke tests with ifelse() fix for MTK symbolic tracing

**Known Gaps (intentional deferrals):**

- VAL-PRES-01: Python STREAM pressure cross-validation (@test_skip placeholder) — requires Python reference data generation

---

## v0.6 Flow Reversal Systems (Shipped: 2026-03-27)

**Phases completed:** 8 phases, 14 plans, 23 tasks

**Key accomplishments:**

- ifelse() bidirectional upwinding and port_in.T ~ T[1] fix applied to all three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux)
- 1. [Rule 1 - Bug] Reverted incorrect port_in.T equation from Plan 20-01
- beta_water with @register_symbolic, Gr/Ra/Re/Pe dimensionless utilities, and 4-arg HTC interface (Re, Pr, T_bulk, T_wall) extended across all correlation closures and channel components
- Elenbaas 1942 parallel-plate natural convection correlation with pluggable 4-arg HTC factory, validated against Python STREAM MTR reference values
- Three-method Pump dispatch with MTK callable parameter pattern, positional solve_transient API, and callable T_wall support in build_loop_transient
- PUMP-01/02/03 test suite with analytical ODE validation, SOLV-02/VAL-02 migrated to positional API, all Pump call sites updated to positional dispatch
- Flapper check-valve with MTK SymbolicContinuousCallback latch: T_open=1e30 sentinel, affect_neg fires on downward ref_mdot crossing, Hermite cubic C1 ramp from R_closed to R_open
- Flapper test suite with 10 passing tests: closed-state sentinel assertion (FLAP-05), Inertia-decay open-transition with ramp completion (FLAP-06), and user ContinuousCallback forwarding via solve_transient (SOLV-01)
- LOF transient validation loop (series Pump(0)+Inertia+HX+ChannelHeatFlux+Flapper) with energy balance 0.09% rtol across forced-flow and natural-circulation regimes
- 1. [Rule 1 - Bug] Updated test_channel.jl equation count test
- Series-loop LOF validation: 5 bypass tests covering Flapper firing, flow reversal, energy balance (5% rtol), and gravity-driven NC stability check, all passing cleanly
- Migrated 6 component signatures from keyword-only to positional (Resistor, Gravity, Inertia, HeatExchanger, ConstantTemperature, laminar_friction) across 16 files with zero test failures
- One-liner:
- VAL-02 NC temperature-rise assertion via Elenbaas HTC (ratio 0.997), build_loop_lof deleted, all three 24.1 verification gaps SC1/SC2/SC5 closed

---

## v0.5 Code Quality (Shipped: 2026-03-16)

**Phases:** 17-19 (3 phases, 6 plans)
**Julia LOC:** ~3,750 (src + test) at completion
**Timeline:** 2026-03-16 (1 day)
**Git range:** `feat(17-01)` → `feat(19-02)` (49 files changed, +6,409/-2,780 lines)

**Key accomplishments:**

- Source reorganized into canonical layout: `geometry.jl`, `src/components/` (6 files), `src/physical_models/`, `src/composition/`, `src/examples.jl` — matches CLAUDE.md contract exactly (STR-01..05)
- Monolithic `runtests.jl` split into 13 self-contained `test_*.jl` files; each file has its own `using` block and runs independently (TEST-01)
- `solve_transient` converted to keyword-only signature, completing project-wide keyword-only API convention (QOL-01)
- Structured Julia docstrings added to all 28 exported names (`# Arguments`, `# Ports`, `# Returns`) — full REPL `?help` coverage (DOC-01..04)
- CLAUDE.md rewritten with **Why:** rationale after every rule and a 5-pattern MTK Patterns reference section for `@register_symbolic`, `ifelse()`, `vars=[]`, `@observed`, and `mtkcompile` (QOL-03)
- `Project.toml` bumped to `0.5.0`; `ChannelHeatFlux` confirmed exported, tested, and documented (QOL-04/05)

**Archive:** `.planning/milestones/v0.5-ROADMAP.md`

---

## v0.4 Composability & Physics (Shipped: 2026-03-16)

**Phases:** 13-16 (4 phases, 7 plans)
**Julia LOC:** ~3,268 at completion
**Timeline:** 2026-03-14 → 2026-03-16 (~2 days)
**Git range:** `3788148` → `0298a38` (72 files changed, +8,029/-6,616 lines)

**Key accomplishments:**

- PipeGeometry redesigned with 6 fields and factory constructors; MTR hydraulic diameter corrected from 10 mm → 2.5 mm, fixing a 4× geometry error (PHY-01)
- Pump extended with dual-mode dispatch (`Pump(mdot0=...)` for fixed-flow scenarios) (PHY-05)
- Six pluggable HTC/friction correlation functions in `src/correlations.jl` with KAERI rectangular laminar correction and `regime_dependent` Re-switching (PHY-02/03/04)
- ChannelAndContacts gains 10 MTK `@observed` variables (Re, Nu, velocity, Pe, wall T/q) + `port()`/`check_gravity_mismatch()` helpers (QOL-01/02/03)
- Four MTK composition helpers (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`) collapse 10-20 line wiring loops into single calls (COMP-01/02/03/04)
- Three quantitative VAL assertions: Fourier series transient, two-plate one-channel topology, T_max adiabatic-face formula (VAL-01/02/03)

**Archive:** `.planning/milestones/v0.4-ROADMAP.md`

---

## v0.3 HeatDiffusion (Shipped: 2026-03-14)

**Phases:** 10-12.1 (4 phases, 8 plans)
**Julia LOC:** ~1,003 src at completion
**Tests:** 161 total at completion
**Timeline:** 2026-03-13 → 2026-03-14 (~1.5 days)
**Git range:** `feat(10-01)` → `feat(12.1-02)` (79 files changed, +9,345/-302 lines)

**Key accomplishments:**

- ChannelAndContacts rewritten with dual `thermal_left[1:n]` / `thermal_right[1:n]` ThermalPort arrays; adiabatic default verified by explicit test (CHAN-01/02/03 + DEBT-01/02/03)
- HeatDiffusion implemented: 2D FD solid plate with `T(t)[nz,nx]` MTK ODE state, `_diffusion_eqs` helper, dual ThermalPort arrays, and power_shape/power source (HDIFF-01..05)
- MTR fuel assembly validated: HeatDiffusion + 2× ChannelAndContacts solves with symmetric, asymmetric, and one-sided configurations (VAL-01/02/03)
- PipeGeometry struct introduced with `circular` / `rectangular` outer constructors, fixing a 4.46× geometry error in the MTR reference case (Phase 12.1 inserted)
- Quantitative VAL assertions: VAL-01/02/03 pass at ≤1% rtol against hardcoded Python STREAM rectangular MTR reference constants

**Archive:** `.planning/milestones/v0.3-ROADMAP.md`

---

## v0.2 Component & Network Expansion (Shipped: 2026-03-13)

**Phases:** 6-9 (4 phases, 7 plans)
**Julia LOC:** 818 src / 545 test at completion
**Tests:** 86 total (54→86, +32 new)
**Timeline:** ~7 hours (single day, 2026-03-13)

**Key accomplishments:**

- Gravity validation: vertical closed loop with Channel(g_acc) + Gravity(H) reversed-port wiring; hydrostatic cancellation within 1% (GRAV-01/02)
- Resistor component: linear hydraulic resistor (dP = R·ṁ) as building block for multi-branch networks (NET-01)
- Cube network: 12-Resistor cube assembled via MTK variadic connect(), 5/6·R analytical match within 1% — no Junction component needed (NET-02/03)
- Inertia ODE component: L/A·D(ṁ) pressure drop, RL-decay analytical match to 2.6×10⁻⁶ rtol (COMP-01)
- HeatExchanger public API: `_make_temp_bc` promoted to exported component, all build_loop variants updated (COMP-02)
- ChannelAndContacts + ChannelHeatFlux: per-cell ThermalPort array via `_channel_base_eqs` shared helper; v0.3 HeatDiffusion interface contract established (THERM-01/02/03)

**Archive:** `.planning/milestones/v0.2-ROADMAP.md`

---

## v0.1 MVP (Shipped: 2026-03-12)

**Phases completed:** 5 phases, 12 plans, 0 tasks

**Key accomplishments:**

- (none recorded)

---
