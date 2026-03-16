# Milestones

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

