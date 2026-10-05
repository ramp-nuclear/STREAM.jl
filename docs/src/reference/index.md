# Reference

Every exported name, grouped by the module it lives in. The modules are layered, and each
reaches only the ones above it in this list:

| Module | What lives there |
|:---|:---|
| [Top level](stream.md) | geometry, dimensionless numbers, constants, design knobs |
| [`Substances`](substances.md) | coolants and their property correlations |
| [`HTC`](htc.md) | wall heat transfer models and Nusselt correlations |
| [`Friction`](friction.md) | Darcy friction factor models and correlations |
| [`LocalLoss`](local_loss.md) | minor losses at sudden area changes |
| [`Thresholds`](thresholds.md) | safety limits, and the analysis that applies them to a solution |
| [`Components`](components.md) | the components a model is built from |
| [`DecayHeat`](decay_heat.md) | decay heat contributions, and the source that feeds them to a model |
| [`Assemblies`](assemblies.md) | wiring verbs and ready-made arrangements of components |
| [Solvers](solvers.md) | steady and transient solves, and initial guesses |
| [`Utilities`](utilities.md) | resampling between meshes and axial profiles |
| [`Examples`](examples.md) | complete models built in one call |

`using STREAM` brings in the module names and the most common functions, so a name is written
either qualified, `Components.Channel` and `HTC.DittusBoelter()`, or bare after
`using STREAM.Components`. The reference shows each name with the module it belongs to.

In the REPL, `?name` shows the same text.
