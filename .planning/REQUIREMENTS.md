# Requirements: STREAM.jl

**Defined:** 2026-03-12
**Core Value:** A working forced-convection loop in MTK that matches Python STREAM, proving the Julia architecture is sound before large-scale porting begins.

## v1 Requirements

### Package Foundation

- [x] **FOUND-01**: Julia package skeleton (Project.toml, src/, test/) with MTK, DifferentialEquations, Sundials as dependencies
- [ ] **FOUND-02**: Light water fluid properties (ρ, cp, μ, k) as polynomial functions of T, registered via `@register_symbolic`, callable from any component without injection

### Connectors

- [ ] **CONN-01**: `FlowPort` connector with pressure (across variable), mass flow (through/flow variable), and temperature variables
- [ ] **CONN-02**: `ThermalPort` connector with temperature (across variable) and heat flow (through/flow variable)

### Components

- [ ] **COMP-01**: `Channel` — n-cell 1D finite-volume coolant, single-phase, Dittus-Boelter HTC, FlowPort in/out and ThermalPort for wall heat input
- [ ] **COMP-02**: `Pump` — constant pressure rise, FlowPort in/out
- [ ] **COMP-03**: `Friction` — Darcy-Weisbach pressure drop with Blasius friction factor, FlowPort in/out
- [ ] **COMP-04**: `Gravity` — hydrostatic pressure term (ρgh), FlowPort in/out

### System Assembly

- [ ] **SYS-01**: Single closed loop (Pump → Friction → Channel → back to Pump) assembles, connects, and compiles with `mtkcompile` without errors
- [ ] **SYS-02**: Clean user-facing API: construct components, connect them, set initial conditions, solve

### Solver Integration

- [ ] **SOLV-01**: Steady-state solver: run closed loop to steady state, return named output variables (T per cell, mass flow, pressures)
- [ ] **SOLV-02**: Transient solver: simulate step change in channel power, return time-series solution

### Validation

- [ ] **VAL-01**: Steady-state T_outlet and mass flow match Python STREAM within 1% on identical inputs
- [ ] **VAL-02**: Transient temperature response (step power change) qualitatively matches Python STREAM
- [ ] **VAL-03**: Test suite runs Python STREAM reference cases and compares Julia outputs automatically

## v2 Requirements

### Neutronics

- **NEUT-01**: Point kinetics (6-group delayed neutrons)
- **NEUT-02**: Decay heat models (fission products, actinides, activation)

### Solid Heat Transfer

- **SOLID-01**: 2D heat diffusion in fuel pin (r,z) — Cartesian and cylindrical

### Extended Thermal-Hydraulics

- **TH-01**: Subcooled boiling (Bergles-Rohsenow / McAdams)
- **TH-02**: Natural / free convection (Elenbaas)
- **TH-03**: Multiple HTC correlation options with regime-dependent switching
- **TH-04**: Multiple friction factor options (Colebrook, regime-dependent)

### Network Complexity

- **NET-01**: Multi-branch / multi-loop networks with full Kirchhoff flow balance
- **NET-02**: Flapper (passive check valve)

### Fluids

- **FLUID-01**: Heavy water (D2O) fluid properties
- **FLUID-02**: Sodium fluid properties

### Analysis

- **UQ-01**: Uncertainty quantification with systematic and statistical uncertainty propagation
- **THRESH-01**: Safety margin calculations (ONB, CHF, DNB, OFI)

### Interop

- **INTEROP-01**: Python adapter via juliacall for users migrating from Python STREAM

## Out of Scope

| Feature | Reason |
|---------|--------|
| Python adapter (juliacall) for v0.1 | Muddies architectural validation; post-v1.0 concern |
| Multiple correlation options in v0.1 | One correlation each is sufficient to validate architecture |
| 2D solid heat diffusion in v0.1 | Independent sub-system; validates separately |
| Multi-loop networks in v0.1 | Single loop sufficient to validate Kirchhoff / MTK connector semantics |
| UQ in v0.1 | Post-validation concern |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 1 — Foundation | Complete |
| FOUND-02 | Phase 1 — Foundation | Pending |
| CONN-01 | Phase 1 — Foundation | Pending |
| CONN-02 | Phase 1 — Foundation | Pending |
| COMP-01 | Phase 2 — Components | Pending |
| COMP-02 | Phase 2 — Components | Pending |
| COMP-03 | Phase 2 — Components | Pending |
| COMP-04 | Phase 2 — Components | Pending |
| SYS-01 | Phase 3 — Integration and Validation | Pending |
| SYS-02 | Phase 3 — Integration and Validation | Pending |
| SOLV-01 | Phase 3 — Integration and Validation | Pending |
| SOLV-02 | Phase 3 — Integration and Validation | Pending |
| VAL-01 | Phase 3 — Integration and Validation | Pending |
| VAL-02 | Phase 3 — Integration and Validation | Pending |
| VAL-03 | Phase 3 — Integration and Validation | Pending |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-12*
*Last updated: 2026-03-12 after roadmap creation*
