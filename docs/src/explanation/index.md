# Explanation

These pages explain the physics STREAM.jl models and the choices behind the models: which
equations each component solves, which correlations it uses, where they came from, and what
choosing them implies for a result. They are for reading, not for following step by step.

**The model**

- [How a model is built](modelling.md): acausal components, connectors, and what compiling a
  model does
- [ModelingToolkit in brief](mtk/index.md): unknowns, parameters, observed variables and the
  rest of MTK's vocabulary, on an electric circuit, masses on springs and a pendulum
- [Relation to Python STREAM](python.md): where STREAM.jl departs from it, and how the two are
  checked against each other

**Physics of the components**

- [The coolant channel](channel.md): the energy and momentum balances of a cooled channel
- [Wall heat transfer](heat_transfer.md): single-phase convection and subcooled boiling
- [Heat exchangers and the heat sink](heat_exchanger.md): the ideal exchanger, the
  effectiveness-NTU model behind the finite ones, and how a heat sink is lost
- [Pressure drop](pressure_drop.md): friction, local losses, gravity and inertia
- [Heat conduction in fuel](conduction.md): plates and rods, clad and with contact
  resistances, on a finite-volume mesh
- [Point kinetics and feedback](point_kinetics.md): reactor power and its temperature feedback
- [Decay heat](decay_heat.md): the power that remains after shutdown
- [Loss of coolant](loca.md): tanks, breaks and the steady state of a free surface
- [Events and control](events.md): trips and state machines
- [Uncertainty quantification](uncertainty.md): how uncertain inputs reach the outputs, and
  where the derivatives come from

**Thermal-hydraulic limits**

- [Overview](limits/overview.md): how the limits relate to each other
- [Onset of nucleate boiling](limits/onb.md)
- [Onset of significant void](limits/osv.md)
- [Onset of flow instability](limits/ofi.md)
- [Critical heat flux](limits/chf.md)
- [Wall temperature limit](limits/twall.md)
- [Margins](limits/margins.md): turning limits into numbers to compare against criteria
