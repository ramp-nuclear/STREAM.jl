# Propagate input uncertainties

[`UQ.uq`](@ref STREAM.UQ.uq) carries the uncertainty of a model's inputs through to its
outputs, to first order: how far the CHF ratio moves when the power is known to 5%, or the
gap to a tenth of a millimetre. [Uncertainty quantification](../explanation/uncertainty.md)
explains what the numbers mean and when first order is enough.

The example is the plate of [Compute safety margins](margins.md), with its channel gap a
[design knob](design_knobs.md) so that the gap can be one of the inputs:

```@example uq
using STREAM
using STREAM.Thresholds
using STREAM.UQ
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, Slab, ChannelAndContacts
using STREAM.Assemblies: inseries, symmetric_plate
using ModelingToolkit: @named, mtkcompile

gap = @design_knob gap = 0.0024
geometry = PipeGeometry_rectangular(0.6, 0.067, gap, 0.063)
n = 10
plate = Slab(; x=range(0.0, 0.00127; length=3), z=range(0.0, 0.6; length=n + 1), y=0.063,
             material=Solid(2700.0, 900.0, 180.0))
@named fuel = HeatDiffusion(plate; power=3.0e4)
@named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
@named cell = symmetric_plate(ch, fuel)
@named pump = Pump(; ṁ0=0.4)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.outlet.p ~ 1.7e5],
                       pump, hx, cell)
sys = mtkcompile(loop)
nothing # hide
```

## Wrap the model

A [`UQModel`](@ref STREAM.UQ.UQModel) needs the inputs that carry an uncertainty, and the
outputs to carry it to. The inputs are parameters of the compiled system, here the knob and
three component parameters. The outputs come from a function of the solution, written as for
[`threshold_analysis`](@ref STREAM.Thresholds.threshold_analysis):

```@example uq
function margins(sol)
    state = ChannelState(sol, sys.cell.ch; pipe=geometry)
    return [minimum(chfr(q_CHF_sudo_kaminaga)(state)),            # smallest CHF ratio
            minimum(bergles_rohsenow_t_onb(state) .- state.T_wall)] # K to the onset of boiling
end

inputs = [sys.cell.fuel.power, sys.pump.ṁ0, sys.hx.T_bc, gap]
model = UQModel(sys, knob_defaults([gap]), inputs; output=margins)
model.nominal
```

Building the model solves the steady state once and takes its derivatives there. A pipe built
from a knob can go to `ChannelState` as it is, and is evaluated at the knob's value.

## Give each input its uncertainty

An [`Uncertainty`](@ref STREAM.UQ.Uncertainty) has a systematic part, a bias of known size,
and a statistical part, a standard deviation. Either can be relative to the nominal value or
absolute:

```@example uq
uncertainties = (
    sys.cell.fuel.power => Uncertainty(systematic_relative=0.05),  # power calibration
    sys.pump.ṁ0 => Uncertainty(statistical_relative=0.03),         # flow measurement
    sys.hx.T_bc => Uncertainty(statistical_absolute=1.0),          # inlet temperature, K
    gap => Uncertainty(statistical_absolute=1.0e-4),               # gap tolerance, m
)
result = uq(model, uncertainties...)
```

An input left out has no uncertainty. The systematic parts add up linearly and the
statistical ones in quadrature, so a margin with both is commonly checked as
`nominal - sys - k * stat` for a coverage factor `k`:

```@example uq
result.nominal .- result.sys .- 2 .* result.stat
```

## See which input matters

[`jacobian`](@ref STREAM.UQ.jacobian) gives the derivatives behind the result, a row per output
and a column per input:

```@example uq
J = jacobian(model)
```

Multiplied by each input's uncertainty, a column shows what that input contributes:

```@example uq
J .* [0.05 * 3.0e4  0.03 * 0.4  1.0  1.0e-4]
```

More power takes margin away from both limits, and more flow gives it back:

```@example uq
@assert J[1, 1] < 0 && J[2, 1] < 0
@assert J[1, 2] > 0 && J[2, 2] > 0
```

## Plot an uncertainty band

Any quantity the solution holds can be an output, such as the temperature in every cell.
With the coolant and the wall temperatures as the outputs, the same uncertainties give a band
along the channel:

```@example uq
using CairoMakie

coolant, wall = collect(sys.cell.ch.T), collect(sys.cell.ch.T_wall_left)
profiles = UQModel(sys, knob_defaults([gap]), inputs; output=[coolant; wall])
r = uq(profiles, uncertainties...)

z = ((1:n) .- 0.5) .* 0.6 ./ n
fig = Figure(size=(700, 420))
ax = Axis(fig[1, 1]; xlabel="distance from the inlet [m]", ylabel="temperature [°C]")
for (cells, color, label) in ((n+1:2n, "#eb6834", "wall"), (1:n, "#2a78d6", "bulk coolant"))
    y, s, σ = r.nominal[cells], r.sys[cells], r.stat[cells]
    band!(ax, z, y .- s .- 2σ, y .+ s .+ 2σ; color=(color, 0.15))
    band!(ax, z, y .- 2σ, y .+ 2σ; color=(color, 0.35))
    lines!(ax, z, y; color, linewidth=2, label)
end
axislegend(ax; position=:lt)
fig
```

The darker band is ``±2σ``, the statistical part alone, and the lighter one adds the
systematic part on either side. The coolant enters with only the inlet temperature's
uncertainty, and gathers the power's and the flow's as it heats up along the channel:

```@example uq
@assert r.stat[n] > r.stat[1] && r.sys[n] > r.sys[1]
```

## Over a transient

Give the saved times as a fourth argument and the model is a transient. With
`start=:steady` it settles first at the operating point and then runs with `overrides`
applied, here the flow cut to half. The steady state it starts from carries the derivatives
too, so an input counts both through where the run starts and through what follows:

```@example uq
times = 0.0:0.05:2.0
peak_wall(sol) = [maximum(sol[sys.cell.ch.T_wall_left[i], k] for i in 1:n)
                  for k in eachindex(sol.t)]
cut = UQModel(sys, knob_defaults([gap]), [sys.cell.fuel.power, sys.hx.T_bc, gap], times;
              output=peak_wall, start=:steady, overrides=[sys.pump.ṁ0 => 0.2])
r = uq(cut, uncertainties[1], uncertainties[3], uncertainties[4])

fig = Figure(size=(700, 380))
ax = Axis(fig[1, 1]; xlabel="time after the flow cut [s]",
          ylabel="peak wall temperature [°C]")
band!(ax, times, r.nominal .- r.sys .- 2r.stat, r.nominal .+ r.sys .+ 2r.stat;
      color=("#eb6834", 0.15))
band!(ax, times, r.nominal .- 2r.stat, r.nominal .+ 2r.stat; color=("#eb6834", 0.35))
lines!(ax, times, r.nominal; color="#eb6834", linewidth=2)
fig
```

The flow is an override here, so it carries no uncertainty of its own. A trip or a scram
cannot be differentiated this way, since its time lives outside the problem; the next section
samples one instead.

```@example uq
@assert r.nominal[end] > r.nominal[1]
```

## Check first order by sampling

[`monte_carlo`](@ref STREAM.UQ.monte_carlo) solves the full model at inputs drawn from their
uncertainties. Its standard deviations match the first-order ones where the response is close
to linear over the spread, and part from them where it curves:

```@example uq
sampled = monte_carlo(model, uncertainties...; n=1000)
(first_order=result.stat, sampled=sampled.std)
```

The samples are the distribution of each output. The systematic part moves every sample the
same way, so the first-order normal to set beside them sits at the nominal value plus
``J s``, with its sign, and has the width of the statistical part:

```@example uq
shift = J[:, 1] .* (0.05 * 3.0e4)   # the power bias, through the power's column of J
fig = Figure(size=(760, 340))
for (k, label) in enumerate(("smallest CHF ratio", "K to the onset of boiling"))
    ax = Axis(fig[1, k]; xlabel=label, ylabel=k == 1 ? "probability density" : "")
    hist!(ax, filter(!isnan, sampled.samples[k, :]); bins=40, normalization=:pdf,
          color=("#eb6834", 0.6), strokewidth=1, strokecolor=:white, label="sampled")
    μ, σ = result.nominal[k] + shift[k], result.stat[k]
    xs = range(μ - 4σ, μ + 4σ; length=200)
    lines!(ax, xs, @. exp(-(xs - μ)^2 / (2σ^2)) / (σ * sqrt(2π)); color="#2a78d6",
           linewidth=2, label="first order")
    k == 1 && axislegend(ax; position=:lt)
end
fig
```

With uncertainties of a few percent the two agree. [Uncertainty
quantification](../explanation/uncertainty.md) shows where they part.

## A trip the uncertainty moves

A reactor protection trips when a measured power passes its setpoint, and the measurement is
itself uncertain: where the channel reads 120%, the true power may be a few percent either
side. That makes the trip setpoint, in true power, an uncertain input, and the time of the
trip an uncertain output. The reactor here is the one of [Trip a reactor or open a
valve](events.md), its rods withdrawing slowly until the trip:

```@example uq
using STREAM.Components: PointKinetics, ReactivityController, StateMachine, machine_callbacks
using ModelingToolkit: @parameters
using Statistics: cor

@parameters trip_at = 1.2
machine = StateMachine()
withdrawal(t) = 2.0e-4 * t                                  # reactivity rising 20 pcm/s
scram(τ) = -0.05 * clamp(τ / 0.5, 0.0, 1.0)
rods = ReactivityController(machine=machine) do state, t_state, t
    state === :SCRAM ? withdrawal(t) + scram(t - t_state) : withdrawal(t)
end
@named pk = PointKinetics(rods)
machine.transitions = [(:NORMAL => :SCRAM, pk.P_neutron > trip_at, "power above setpoint")]
@named reactor = assembly([], pk; parameters=[trip_at])
ria = mtkcompile(reactor)

tripped(sol) = [machine.t_state, maximum(sol[ria.pk.P_neutron])]   # trip time, peak power
trip = UQModel(ria, Pair[], [trip_at], 0.0:0.05:30.0; output=tripped,
               callbacks=machine_callbacks(ria, machine), machines=(machine,))
trip.nominal
```

Pass the run's `callbacks` and the `machines` they drive. Every sample is then a full run,
with each machine reset first, so the trip falls wherever that sample's power takes it. The
runs share the machine, so they are solved one at a time:

```@example uq
runs = monte_carlo(trip, trip_at => Uncertainty(statistical_relative=0.03); n=400)

fig = Figure(size=(760, 340))
for (k, label) in enumerate(("time of the trip [s]", "peak power [relative to nominal]"))
    ax = Axis(fig[1, k]; xlabel=label, ylabel=k == 1 ? "probability density" : "")
    hist!(ax, filter(!isnan, runs.samples[k, :]); bins=30, normalization=:pdf,
          color=("#eb6834", 0.6), strokewidth=1, strokecolor=:white, label="sampled")
    vlines!(ax, trip.nominal[k]; color="#2a78d6", linewidth=2, linestyle=:dash,
            label="nominal")
    k == 1 && axislegend(ax; position=:rt)
end
fig
```

A run whose setpoint lies high trips later, at a higher power:

```@example uq
@assert runs.failed == 0 && cor(runs.samples[1, :], runs.samples[2, :]) > 0.9
```

Derivatives cannot be taken through the trip, so `jacobian` and `uq` refuse a model with
callbacks and point here.

## Propagate through a function

For a correlation on its own, or any calculation that is not one steady solve, wrap a function
of named inputs. It is called with dual numbers, so keep it free of `Float64` conversions:

```@example uq
pipe = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
ofi = UQModel(x -> q_OFI_whittle_forgan(x.ṁ, x.T_sat, x.T_in, pipe),
              (ṁ=0.4, T_sat=115.0, T_in=40.0))
uq(ofi, :ṁ => Uncertainty(statistical_relative=0.03),
        :T_in => Uncertainty(statistical_absolute=1.0))
```

## Get the outputs as Measurements

With Measurements.jl loaded, [`measurements`](@ref STREAM.UQ.measurements) returns the outputs
as `value ± σ`. They keep track of the inputs they came from, so arithmetic on them is right
even where outputs are correlated:

```@example uq
using Measurements
y = measurements(model, sys.pump.ṁ0 => Uncertainty(statistical_relative=0.03),
                        gap => Uncertainty(statistical_absolute=1.0e-4))
```

A Measurement holds a standard deviation only, so this takes statistical parts alone.
