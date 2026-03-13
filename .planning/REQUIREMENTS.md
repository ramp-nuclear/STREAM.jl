# Requirements: STREAM.jl

**Defined:** 2026-03-13
**Core Value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.

## v0.3 Requirements

Requirements for the HeatDiffusion milestone. Each maps to roadmap phases.

### Tech Debt (DEBT)

- [x] **DEBT-01**: Developer can call `_channel_base_eqs` without a dead `t_inlet` parameter (parameter removed, all call sites updated)
- [ ] **DEBT-02**: THERM-03 test directly asserts ChannelAndContacts behavioral output rather than validating via a proxy
- [x] **DEBT-03**: `09-01-SUMMARY.md` cosmetic documentation issue is corrected

### Channel Upgrade (CHAN)

- [x] **CHAN-01**: ChannelAndContacts exposes `thermal_left[1:n]` and `thermal_right[1:n]` ThermalPort arrays (replaces `thermal_ports[1:n]`)
- [x] **CHAN-02**: ChannelAndContacts `q_wall[i]` equals `thermal_left[i].Q_flow + thermal_right[i].Q_flow` (both sides contribute to cell energy balance)
- [ ] **CHAN-03**: User can connect only one side of ChannelAndContacts and the unconnected side defaults to adiabatic (Q_flow=0 verified by explicit test)

### HeatDiffusion Component (HDIFF)

- [ ] **HDIFF-01**: User can instantiate a HeatDiffusion component with 2D MTK state `T(t)[1:nz, 1:nx]` (row=axial z, col=lateral x — matching Python STREAM axis convention)
- [ ] **HDIFF-02**: HeatDiffusion computes x-direction (across-plate) heat diffusion via FD stencil using an internal `_diffusion_eqs` helper structured for future xz/r extension; top and bottom boundaries are adiabatic
- [ ] **HDIFF-03**: HeatDiffusion accepts `power_shape[1:nz, 1:nx]` (normalized spatial distribution, constructor parameter) and `power` (total watts, MTK parameter) as the volumetric heat source
- [ ] **HDIFF-04**: HeatDiffusion exposes `thermal_left[1:nz]` and `thermal_right[1:nz]` ThermalPort arrays for per-cell coupling to coolant channels
- [ ] **HDIFF-05**: User can leave one side of HeatDiffusion unconnected and it defaults to adiabatic (Q_flow=0 from MTK acausal semantics, verified by explicit test)

### Validation (VAL)

- [ ] **VAL-01**: Coupled HeatDiffusion + two ChannelAndContacts in MTR geometry produces steady-state T_outlet and T_plate matching Python STREAM reference within 1%
- [ ] **VAL-02**: Asymmetric left/right heating (left and right channels at different temperatures) produces a correct non-symmetric plate temperature profile
- [ ] **VAL-03**: One-sided coupling (HeatDiffusion connected to a channel on one side only) solves correctly with the unconnected face adiabatic

## Future Requirements

### v0.4

- **DIFF-01**: HeatDiffusion supports xz-diffusion mode (axial + lateral) via `_diffusion_eqs` helper with `dz`/`kz` arguments
- **DIFF-02**: HeatDiffusion supports r-diffusion mode (cylindrical geometry)
- **CHAN-04**: ChannelAndContacts supports a fuel plate on each side simultaneously (two plates, one channel)
- **KIN-01**: `power` parameter on HeatDiffusion can be driven by a PointKinetics component at runtime

## Out of Scope

| Feature | Reason |
|---------|--------|
| z-direction diffusion (xz mode) | Not required for MTR reference case validation; add in v0.4 after validation passes |
| r-diffusion (cylindrical) | No cylindrical validation target in v0.3 |
| Point kinetics coupling | Thermal-hydraulic architecture must be proven first; v0.4+ |
| Additional HTC correlations | Dittus-Boelter sufficient for turbulent MTR regime |
| Additional friction correlations | No new hydraulic components in v0.3 |
| Natural convection / subcooled boiling | No validation target |
| Non-uniform power shape from neutronics | Deferred until point kinetics is in scope |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DEBT-01 | Phase 10 | Complete |
| DEBT-02 | Phase 10 | Pending |
| DEBT-03 | Phase 10 | Complete |
| CHAN-01 | Phase 10 | Complete |
| CHAN-02 | Phase 10 | Complete |
| CHAN-03 | Phase 10 | Pending |
| HDIFF-01 | Phase 11 | Pending |
| HDIFF-02 | Phase 11 | Pending |
| HDIFF-03 | Phase 11 | Pending |
| HDIFF-04 | Phase 11 | Pending |
| HDIFF-05 | Phase 11 | Pending |
| VAL-01 | Phase 12 | Pending |
| VAL-02 | Phase 12 | Pending |
| VAL-03 | Phase 12 | Pending |

**Coverage:**
- v0.3 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-13*
*Last updated: 2026-03-13 — traceability confirmed against ROADMAP.md phases 10-12*
