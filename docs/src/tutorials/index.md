# Tutorials

The tutorials teach STREAM.jl by building models, one step at a time, from a single loop to a
loss of flow in a pool reactor. Each builds its model by hand, so you see every component and
connection, and each ends by checking the result against physics you can work out on paper.
Read them in order: each assumes what the ones before it taught.

| | Tutorial | What you learn |
|:---|:---|:---|
| 1 | [A first loop](01_first_loop.md) | components, connections, compiling, a steady solve, reading results |
| 2 | [Hydraulic networks](02_hydraulic_networks.md) | parallel branches, junctions, gravity and buoyancy-driven flow |
| 3 | [Pump coastdown](03_pump_coastdown.md) | inertia, inputs that change in time, transients |
| 4 | [A fuel plate between two channels](04_plate_and_channels.md) | solid conduction, thermal coupling, axial power shapes, safety margins |
| 5 | [A fuel assembly of many plates](05_fuel_assembly.md) | a chain of plates and channels, parallel flow, the cross-section of an assembly |
| 6 | [Reactivity insertion with feedback](06_reactivity_insertion.md) | point kinetics, temperature feedback, the prompt jump |
| 7 | [Loss of flow in a pool reactor](07_pool_lofa.md) | everything together: trips, a check valve, decay heat, flow reversal, margins over time |

Every tutorial can be downloaded as a Julia script or a Jupyter notebook from the link at its
top, and run as it is.

Once you know your way around, the [How-to guides](../howto/index.md) answer specific
questions, and the [Explanation](../explanation/index.md) pages give the physics behind the
models.
