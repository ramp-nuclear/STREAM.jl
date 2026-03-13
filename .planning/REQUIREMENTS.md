# Requirements: STREAM.jl

**Defined:** 2026-03-13
**Milestone:** v0.2 — Component & Network Expansion
**Core Value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.

## v0.2 Requirements

### Gravity & Vertical Loop

- [ ] **GRAV-01**: Vertical closed loop (Channel with g_acc set to 9.80665 + Gravity component on return leg of equal height) assembles, compiles, and solves correctly
- [ ] **GRAV-02**: Gravity cancellation test — equal height up/down gives the same steady-state flow as the horizontal reference loop within 1%

### Network Architecture

- [ ] **NET-01**: Resistor component: linear pressure drop `dp ~ R * mdot`, where R is a scalar resistance parameter
- [ ] **NET-02**: Cube problem (12 Resistors, 8 nodes, 1 Pump) assembled using multi-port `connect()` calls — no Junction component needed; MTK connection semantics handle flow conservation automatically
- [ ] **NET-03**: Cube problem flow distribution matches analytical solution (equivalent resistance = 5/6 R) within 1%

### Lumped Components

- [ ] **COMP-01**: Inertia component: `dp ~ (L/A) * D(mdot)`, validated against Python STREAM Inertia on a transient test case
- [ ] **COMP-02**: HeatExchanger component (public): fixed outlet temperature, no pressure drop — replaces internal `_make_temp_bc`; existing build_loop updated to use it

### Per-Cell Thermal Coupling

- [ ] **THERM-01**: ChannelAndContacts component: n ThermalPorts (one per axial cell), per-cell wall temperature in energy balance: `h_tc[i] * (π*Dh) * dz * (thermal[i].T - T[i])`
- [ ] **THERM-02**: Existing Channel (single ThermalPort) remains unchanged and all v0.1 tests continue to pass
- [ ] **THERM-03**: ChannelAndContacts steady-state result matches Channel result when all n ThermalPorts are driven by the same uniform wall temperature (within 0.1%)

## v3 Requirements (deferred)

### HeatDiffusion

- **HEAT-01**: HeatDiffusion component: 2D (x-z) finite-difference fuel plate with `T(t)[1:nx, 1:nz]` indexed MTK variables
- **HEAT-02**: HeatDiffusion exposes `thermal_left[1:n]` and `thermal_right[1:n]` ThermalPort arrays for left/right channel coupling
- **HEAT-03**: Coupled HeatDiffusion + ChannelAndContacts system solves and matches Python STREAM MTR reference case
- **HEAT-04**: Asymmetric left/right heating (two independent channels on either side of a plate) works without model changes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Junction component | MTK multi-port connect() is the junction — no explicit component needed |
| PointKinetics | v0.4+ — thermal-hydraulic architecture must be complete first |
| Additional HTC correlations (laminar, Marco-Han, etc.) | v0.4+ — minimal rewrite when added; not blocking anything now |
| Additional friction correlations (Colebrook, regime-dependent) | v0.4+ — same as HTC |
| Decay heat models | Irrelevant without neutronics |
| Heavy water / other fluids | v0.4+ — light water only through v0.3 |
| Solver wrapper structs (SteadySolution, TransientSolution) | ODESolution is sufficient; defer unless usage patterns demand it |
| Python adapter (juliacall) | If Julia-STREAM is good, use it from Julia |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GRAV-01 | — | Pending |
| GRAV-02 | — | Pending |
| NET-01 | — | Pending |
| NET-02 | — | Pending |
| NET-03 | — | Pending |
| COMP-01 | — | Pending |
| COMP-02 | — | Pending |
| THERM-01 | — | Pending |
| THERM-02 | — | Pending |
| THERM-03 | — | Pending |

**Coverage:**
- v0.2 requirements: 10 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 10 ⚠️

---
*Requirements defined: 2026-03-13*
*Last updated: 2026-03-13 after initial definition*
