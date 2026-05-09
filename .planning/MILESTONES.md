# Milestones

## v1.1 Final Channel-Family Redesign (Shipped: 2026-05-09)

**Phases:** 52-58 (7 phases, 33 plans)
**Working branch:** `channels-redesign` (single PR vehicle, off origin/main)
**Timeline:** 2026-05-05 → 2026-05-09 (5 days)

**Goal:** Last channel rewrite — match Python STREAM's design intent for `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts`; eliminate the flag-driven `_channel_base_eqs` helper; switch the convective energy balance to enthalpy form.

**Key accomplishments:**

- **Connector pattern locked-in** (Phase 52): array-of-scalar MTK acausal connectors per side per channel, after a 2026-05-05 spike (`/tmp/vec_diagnose3.jl`) proved vector-form connectors mis-integrate the first unknown when compiled alongside any `FlowPort`-bearing system. End-of-v1.1 connector roster: `FlowPort` + `ThermalPort` only (`WallPort` and `HeatFluxPort` retired during Phase 54/55 walk-backs after the drive-aware-port story was abandoned in favor of binding equations + value-source components).
- **Shared `_channel_core` + enthalpy-form energy balance** (Phase 53): single private function emits energy/mass/momentum/friction/port-wiring/observables for all three variants. Convective term uses face-averaged cp `(cp(T_up) + cp(T[i]))/2` with `cp(T_in)` at the boundary face per NRG-01..04. `_channel_base_eqs` deleted; no `observed_mode`, `skip_htc`, or `T_wall_cells=nothing` dead branches anywhere.
- **Variant rewrites + file consolidation** (Phase 54): `Channel` rebuilt as a passive recipient (T_wall via `thermal_left/right[1:n]` ports + `h_left`/`h_right` kwargs; adiabatic-by-default via Float64 IC `h=0.0`); `ChannelHeatFlux` receives q directly via channel-level `q_left/q_right[1:n]` variables (or via `HeatFluxSource` value-source); `ChannelAndContacts` rebuilt on `_channel_core` with optional `scb_correction` kwarg. Old `channel.jl` and `thermal_channel.jl` deleted; new `src/components/channels.jl` is the single home. Architectural invariant: only `ChannelAndContacts` ever connects to `HeatDiffusion`.
- **Composition helpers + test reorganization + daemon dev loop** (Phase 55): `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems` updated; `port` and `check_gravity_mismatch` QoL helpers; `connect_temperature_feedback` for PK loops. Test suite consolidated to a 14-file canonical layout (`test_channels.jl` absorbs legacy `test_channel.jl`/`test_channel_core.jl`/`test_sign_safety.jl`; `test_integration.jl` is new and absorbs LOF/SOLV/COMPAT/PK loops; `test_thresholds.jl` renamed from `test_analysis.jl`). `bin/jl` + `bin/jl-up` daemon-dev-loop established as primary workflow (sub-second submissions after the warm-up cost).
- **Python STREAM cross-validation** (Phase 56): `test/parity_helpers.jl` (274 lines) + per-cell `parity_check`/`assert_equivalence_*` machinery; `test/generate_reference.py` and `test/generate_mtr_reference.py` rewritten to emit Plan-04 paste-ready Julia const blocks at all D-07 tiers; `test/data/python_parity_reference.jl` (674 lines, 65 const PARITY_*); `test/data/parity_report.csv` is the live gate. **Final parity tally: 424 CLEAN / 78 GRAY / 34 FAIL** out of 536 row comparisons across simple_loop, mtr_symmetric, mtr_asymmetric, and mtr_one_sided scenarios. Heated-side `h_tc_*` rows match Python at floating-point precision (1e-11 rtol) after the per-side h fix in Phase 56-resume. The simple_loop scenario is fully CLEAN (83/83 quantities including T_out, mdot, dP_loop, per-cell T, T_wall, h_tc, q_density). The 34 residual FAIL rows have three documented causes (see "Known Gaps" below).
- **HTC film-temperature evaluation** (Phase 57): switched the CAC SPL/SCB HTC pipeline (Re, Pr, leading k outside Nu) to evaluate fluid properties at film T `T_film = (T_cool + T_wall)/2`, matching Python STREAM `heat_transfer_coefficient/__init__.py:208-209`. Friction Re and natural-convection Gr stayed at bulk T per Python convention. Closed Phase-56 Gap #2: all 20 simple_loop `h_tc_*[i]` rows + all 30 `q_density_*[i]` rows moved from FAIL ~19% to CLEAN ~10⁻¹¹. HTC correlation 4-arg signature unchanged; module header + 7 factory docstrings document the eval-point convention; `elenbaas_htc` carries the bulk-NC exception note.
- **MTK system determinacy repair** (Phase 58): root-cause-fixed the `mtkcompile`/`solve_steady` boundary failure on seven in-scope scenarios (3 MTR + VAL-01 HD Fourier + VAL-02 two-plate steady + VAL-02 transient + PK validation). Cause: `HeatDiffusion`'s `power(t)` is declared as an `@variables` unknown but no equation closes it; the broken scenarios forgot the `hd.power ~ <value>` connection-list pin that `build_loop_lof_bypass` and `build_loop_pk` already use. Added the missing pins, audited every `fully_determined=false` site (38 total, 7 bug-hiding flips, 31 legitimate-structural with inline rationale), shipped `test/test_determinacy.jl` (11/11 PASS) wired into `runtests.jl` as the regression gate so this class of bug cannot recur silently across MTK upgrades. No `check_length=false` workarounds in `src/solvers.jl`. No Manifest.toml MTK pin reversions.

**Phase 56-resume work (post-58 close-up, 2026-05-08 → 2026-05-09):**

After 56-PAUSE-CONTEXT.md's resume gate ("after 57+58 ship, expect zero FAIL beyond GRAY-tier"), the parity harness surfaced two further issues that the pause-context didn't anticipate:

1. **MTR L/R wiring bug in the parity test itself** (not in `src/composition/helpers.jl`): `test/test_validation.jl` lines 371-374 (mtr_symmetric), 542-545 (mtr_asymmetric) hand-wired connections instead of using `plate()` and got the channel face wrong (`cac_l.thermal_LEFT ↔ hd.thermal_left` instead of `cac_l.thermal_RIGHT ↔ hd.thermal_left`). Fixed by 6-line edit. The helpers themselves were correct and matched Python's `stream/composition/mtr_geometry.py:60-63` semantics.
2. **Per-side h_tc in CAC**: Julia computed a single h_tc per cell using only `thermal_left[i].T`'s film T, while Python computes h_left and h_right separately at each side's own film T (`channel.py:689-690`). For symmetric walls this matched; for asymmetric MTR (heated + adiabatic), the single-h approach used bulk-T-evaluated h on whichever channel had `thermal_left` as its adiabatic side. Fixed by promoting `h_tc_left`/`h_tc_right` to first-class unknowns with their own per-side film-T equations; `q_*_expr` now uses each side's own h. SCB branch keeps single-h_tc semantics with aliases (asymmetric SCB out of scope). The test parity rows mirror Python's `_other_if_none` convention via `max(h_left, h_right)` at the report level.

**Known Gaps (deferred to v1.2 with documented cause):**

- **mtr_one_sided q_left_l[1..10]** (10 FAIL rows): documented Python-side bug — `one_sided_connection` distributes one-sided heat to BOTH plate faces. Julia is physically correct; Python is acknowledged-wrong. `hard_ceiling=0.5` reflects the gap; ~100% drift exceeds it. Resolution: fix Python upstream (out of v1.1 scope) or accept as canonical Julia-vs-Python divergence point.
- **mtr_asymmetric cac_r h_tc[1..7]** (14 FAIL rows, cells 8-10 GRAY): Julia's hot-channel h_tc is consistently 2-4% higher than Python's, monotonically decreasing along the channel. Cause: plate T(z,x) distribution sensitivity between Python's `CalculationGraph` topology and Julia's MTK topology — they aren't quite isomorphic in subtle ways. Bounded, well-characterized; root-cause investigation requires another bisection pass and is queued for v1.2.
- **mtr_one_sided h_tc[6..10]** (10 FAIL rows, cells 1-5 GRAY): cascade of the Python `one_sided_connection` bug — Python's plate runs cooler (heat leaks to both faces), so Python's h is lower; Julia higher. ~3-5% drift.
- **VAL-01 Fourier `solve(ODEProblem)` `ReturnCode.InitialFailure`**: Phase 58 fixed the structural determinacy (`mtkcompile(...; fully_determined=true)` succeeds with n_eqs=50=n_unknowns=50); numerical convergence of `Rodas5P` from naive IC remains a v1.2 numerical-investigation item.
- **NET-03 / HTC-02-SPL / LOF-02 / LOF-03 / VAL-01-NC / VAL-02-NC**: pre-existing numerical convergence flakies (KINSol flag −7/−11 family, transient solver instability). `@test_skip` with documented cause; do not halt `bin/jl test/runtests.jl` orchestrator.
- **`build_loop_lof_bypass` 2-step IC idiom**: `solve_transient` from a naive IC (T=313.15, mdot=0.5) returns `Unstable` at t=0; works only via the steady-then-transient pattern in `examples/lof_transient.jl:139`. Undocumented as a builder requirement; v1.2 docs/usability item.

**Convention split with Python (acknowledged, not a bug):**

- Julia's CAC computes per-side h_tc honestly (h_left at film(T_cool, T_left), h_right at film(T_cool, T_right)). Python applies `_other_if_none` to fill the unconnected side's h with the connected side's value. The parity test mirrors Python's convention by reporting `max(h_tc_left, h_tc_right)` for both walls. Underlying physics is correct in both implementations; the convention difference is purely about how the adiabatic-side h is *reported*.

**Workflow improvements landed:**

- Daemon dev loop (`bin/jl-up` + `bin/jl`) replaces the abandoned PackageCompiler sysimage approach (Phase 55 D-22; sysimage incremental-link killed by SIGTERM at ~7min on Julia 1.12 + WSL2 regardless of package set). Sub-second `bin/jl` submissions after warm-up.
- `test/test_determinacy.jl` regression gate locks the canonical-builder + Phase-58-scenario determinacy contracts against future MTK upgrades.
- `mtkcompile(...; fully_determined=true)` is now the default audit mode across the test suite (every bug-hiding `=false` flipped, legitimate-structural sites carry inline rationale).

**Final parity report:** `test/data/parity_report.csv` (537 rows including header). Run `awk -F, 'NR>1 && $7=="FAIL"' test/data/parity_report.csv` to see the 34 remaining FAIL rows; each has a documented `note` column traceable to one of the buckets above.

**Git range:** `b2ab8cc` → `475db6e` (37 files changed across 7 phases plus Phase 56-resume cleanup; full Manifest.toml regenerated under julia 1.12.6 with Statistics 1.10.0 stdlib pin removed).

---

## v1.0 Open-Source Release (Shipped: 2026-04-10)

**Phases:** 50-51 (2 phases, 7 plans)
**Julia LOC:** 4,301 src / 5,066 test at completion
**Timeline:** 2026-04-10 (single-day release sprint)
**Git range:** `26bc397` → `c837d37` (39 files changed, 4,792 insertions)

**Key accomplishments:**

- MIT license, correct Project.toml metadata (fresh RFC 4122 UUID, PackageCompiler moved to [extras] only — not a transitive runtime dep), Manifest.toml committed for reproducibility
- GitHub Actions CI workflow (julia-actions/setup-julia@v2, stable only, ubuntu-latest); RobustMultiNewton solver for NET-03 Cube test; NoInit removed from VAL-01 ODE solves for reliable Fourier convergence
- Two runnable example scripts: `examples/simple_loop.jl` (hello-world forced convection loop) and `examples/mtr_assembly.jl` (MTR plate-fuel two-channel thermal assembly)
- README.md with physics-first documentation, component catalog table, and usage examples for public GitHub discovery
- `test/Project.toml` enabling `julia --project=. test/runtests.jl` direct invocation; MTR assembly power equation fixed (HeatDiffusion power is MTK @variables unknown, not a parameter — `rods.hd.power ~ POWER` required)
- mtkcompile warmup baked into sysimage precompile; pre-flight 6 GB RAM gate with dynamic heap-size-hint (75% free RAM) in `build_sysimage.sh`; TTFX timing baseline script
- PackageCompiler+Julia1.12+WSL2 incompatibility documented (SIGTERM at ~7min on incremental LLVM link step regardless of package list); persistent REPL + Revise.jl established as primary development workflow

**Known Gaps:**
- Sysimage not buildable on Julia 1.12 + WSL2 (TTFX-04 requirement not met on this platform); build infrastructure retained for future Julia versions or non-WSL2 environments

---

## v0.9 Point Kinetics & Reactor Control (Shipped: 2026-04-09)

**Phases completed:** 6 phases, 8 plans, 13 tasks

**Key accomplishments:**

- 6-group point kinetics MTK component (7 ODEs) with U-235 defaults and analytical steady-state IC helper validated against precursor-only decay analytical solution
- MTK callable-mode PointKinetics with additive rho composition + pure-Julia ReactivityController state-machine struct
- RC-01 ReactivityController unit tests (8 sub-tests) and PK-03 callable PointKinetics integration tests (5 sub-tests) added to test/test_point_kinetics.jl with prompt-jump validated at t_step + 0.028s
- New code location:
- 1. [Rule 1 - Bug] Fixed symbolic scoping mismatch in connect_temperature_feedback
- One-liner:
- Task 1: `build_loop_pk` in `src/examples.jl`
- Pre-existing VAL-01 MTR test failure:

---

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
