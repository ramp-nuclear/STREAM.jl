# Milestones

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

