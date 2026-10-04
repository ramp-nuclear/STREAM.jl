# Compute safety margins

[`threshold_analysis`](@ref STREAM.Thresholds.threshold_analysis) applies the
thermal-hydraulic limits to one channel of a solution. What each limit means is in
[Thermal-hydraulic limits](../explanation/limits/overview.md), and how to read the numbers in
[Margins](../explanation/limits/margins.md).

The examples use a plate cooled on both faces by one channel, as in
[A fuel plate between two channels](../tutorials/04_plate_and_channels.md).

```@example mg
using STREAM
using STREAM.Thresholds
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, ChannelAndContacts
using STREAM.Assemblies: inseries, symmetric_plate
using ModelingToolkit: @named, mtkcompile

n = 10
geometry = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
@named fuel = HeatDiffusion(; nz=n, nx=2, Lz=0.6, Lx=0.00127, y=0.063,
                            rho_s=2700.0, cp_s=900.0, k_s=180.0, power=3.0e4)
@named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
@named cell = symmetric_plate(ch, fuel)
@named pump = Pump(; ṁ0=0.4)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.outlet.p ~ 1.7e5],
                       pump, hx, cell)
sys = mtkcompile(loop)
sol = solve_steady(sys)
nothing # hide
```

## Margins of a steady state

Name each margin you want and give the function that computes it from a
[`ChannelState`](@ref STREAM.Thresholds.ChannelState), the channel's solved state. The
correlations take one directly. Arrange each so that larger is safer:

```@example mg
m = threshold_analysis(sol, sys.cell.ch; pipe=geometry,
    onb = s -> bergles_rohsenow_t_onb(s) .- s.T_wall,      # K to the onset of boiling
    chfr = chfr(q_CHF_sudo_kaminaga),                     # CHF over the local flux
    ofi = s -> q_OFI_whittle_forgan(s) / 3.0e4,           # OFI power over channel power
    twall = s -> 150.0 .- twall_limit(s; inhomogeneity_factor=1.2),  # K to a 150 °C limit
)
worst_case(m.chfr)
```

Pass `pipe`, the channel's geometry: the heat fluxes and the geometric correlations need it.
Per-cell margins come back as vectors and channel-wide ones, like the OFI ratio, as numbers.
[`worst_case`](@ref STREAM.Thresholds.worst_case) gives the smallest value and its cell.

## Choose the face

A channel between two plates has a heat flux on each face. [`chfr`](@ref STREAM.Thresholds.chfr)
and the flux-based correlations take a `direction`: `:left`, `:right`, or `:max`, the larger of
the two and the default. Face-by-face margins:

```@example mg
m = threshold_analysis(sol, sys.cell.ch; pipe=geometry,
    left = chfr(q_CHF_mirshak; direction=:left),
    right = chfr(q_CHF_mirshak; direction=:right))
(minimum(m.left), minimum(m.right))
```

## Margins over a transient

Pass a transient solution, and each margin is evaluated at every saved time. A per-cell
margin becomes a matrix, cells by times, and `worst_case` with the times finds when:

```@example mg
sol_tr = solve_transient(sys, sol, 0.0:0.1:5.0; overrides=[sys.cell.fuel.power => 4.5e4])
m = threshold_analysis(sol_tr, sys.cell.ch; pipe=geometry, chfr=chfr(q_CHF_sudo_kaminaga))
size(m.chfr), worst_case(m.chfr; times=sol_tr.t)
```

The minimum can only fall on a saved time. Save often enough to resolve the events that drive
it.

## Leave out what a correlation does not cover

The OSV and OFI correlations are for forced flow. In a loss of flow, near zero flow they stop
meaning anything. Mask those times out of the search rather than dropping the margin:

```julia
forced = sol[sys.cell.ch.inlet.ṁ, :] .> 0.05 * design_ṁ
ofi = m.ofi                                   # one value per saved time
worst_case(ifelse.(forced, ofi, Inf); times=sol.t)
```

## Margins of a state from elsewhere

The correlations also take plain numbers, for a check by hand or for states computed outside
STREAM:

```@example mg
q_CHF_mirshak(60.0, 115.0, 1.7e5, 3.0)   # bulk °C, saturation °C, pressure Pa, velocity m/s
```
