# Uncertainty quantification

A model's inputs are known to some accuracy: a power calibrated to a few percent, a gap
machined to a tolerance, an inlet temperature read off a thermocouple. The [`UQ`](@ref) module
answers how much that moves the outputs, to first order, the way Python STREAM's
`stream.analysis.UQ` does. [Propagate input uncertainties](../howto/uncertainty.md) shows how
to use it.

## Two kinds of uncertainty

An [`Uncertainty`](@ref STREAM.UQ.Uncertainty) splits what is known about an input into a
systematic part and a statistical part. The systematic part is a bias: a calibration that
reads high, or a tolerance that every plate in a batch shares. The statistical part is a
standard deviation: scatter between measurements, independent from one to the next. Both can
be given relative to the nominal value or in the input's units.

They propagate differently. Near the nominal inputs ``x_0`` an output moves as

```math
y(x) ≈ y(x_0) + J (x - x_0)
```

with ``J`` the Jacobian, ``J_{ij} = ∂y_i/∂x_j``. A bias ``s`` moves an output by ``J s``, and
for a vector input, such as a temperature per cell, all of its entries move together. A
standard deviation ``σ`` gives an output the standard deviation ``(∑_j (J_{ij} σ_j)^2)^{1/2}``
when the entries are independent. [`uq`](@ref STREAM.UQ.uq) returns both. Different inputs are
taken as independent, so their systematic contributions add as magnitudes and their
statistical ones in quadrature. This matches what Python STREAM computes, and the test suite
checks the two codes against each other on the same inputs.

How the two are combined into an acceptance criterion is a matter for the safety analysis.
Research reactor practice expresses the same idea as hot channel factors, applied either
multiplicatively or statistically [IAEA1980](@cite); see [Margins](limits/margins.md).

## Where the derivatives come from

Python STREAM takes ``J`` by finite differences, solving the model again with each input
moved by a relative step of ``10^{-6}``. That carries two errors. Truncation is proportional to
the step. The solver's error is divided by it: a root converged to a relative tolerance of
``10^{-8}`` gives derivatives good to about 1%, so the step and the tolerance have to be chosen
together.

STREAM.jl differentiates instead. ForwardDiff carries dual numbers, a value with its
derivatives along each input, through the arithmetic of the model. The result is exact to
rounding, for every input in one pass, with nothing to tune.

A steady state needs one more step, since the root it lands on comes out of an iteration
rather than a formula. If ``F(u, p) = 0`` are the steady equations for the unknowns ``u`` and the
parameters ``p``, then differentiating that identity gives

```math
∂F/∂u \; du/dp + ∂F/∂p = 0, \quad\text{so}\quad du/dp = -(∂F/∂u)^{-1} ∂F/∂p
```

This is the implicit function theorem. [`UQModel`](@ref STREAM.UQ.UQModel) solves the steady
state in ordinary floating point, with whatever solver converges it, then forms both partial
derivatives of ``F`` at the root by ForwardDiff and solves the one linear system. The
derivatives are those of the steady state itself, so they do not depend on how the solver got
there: a Newton iteration and a `DynamicSS` integration give the same ``J``. The solution
handed to the output function carries ``du/dp`` in its values. Reading a variable, building a
[`ChannelState`](@ref STREAM.Thresholds.ChannelState), or calling a threshold correlation then
carries the derivatives through without any change to that code.

## When first order is enough

First order is exact for an output that is linear in its inputs, and close for one that is
smooth over the range the uncertainties span. Three things in a thermal-hydraulic model break
that.

- **A regime switch.** The friction factor and the heat transfer coefficient change form between
  laminar and turbulent flow, and subcooled boiling turns on at the onset of boiling. The
  derivative is that of the branch the nominal state is on. An uncertainty that would take the
  state across the switch is not seen.
- **A minimum over cells or faces.** The smallest CHF ratio in a channel, or the hotter of two
  faces, follows one cell. The derivative is that cell's, and when an input moves the minimum to
  another cell the slope changes there.
- **A large uncertainty.** A response that curves over the range of the inputs is misjudged by
  its tangent, in one direction or the other.

Sampling handles all three: solve the model at inputs drawn from their distributions, and read
the spread of the outputs. A first-order result is the place to start, because it costs one
solve and shows which inputs matter.

## What is not covered yet

The models are steady states and plain functions. A transient goes through the same machinery,
with the derivatives carried through the integration, but a model with a
[`StateMachine`](@ref STREAM.Components.StateMachine) keeps its trip time outside the problem,
so a derivative with respect to a setpoint would come back as if the trip never moved.
`GAPS.md` in the repository tracks this.
