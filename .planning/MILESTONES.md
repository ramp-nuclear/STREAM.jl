# Milestones

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

