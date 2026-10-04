# Move a profile between meshes

A power distribution from a neutronics code rarely comes on the mesh of the thermal-hydraulic
model. [`Utilities`](@ref STREAM.Utilities) moves per-cell data between meshes, treating it
as constant over each source cell and integrating its overlap with each target cell.

```@example rb
using STREAM
using STREAM.Utilities: rebin_extensive, rebin_intensive, cosine_shape, cosine_power_shape
```

## Amounts: keep the total

A power per cell, or a mass per cell, is an *amount*: splitting a cell splits it.
[`rebin_extensive`](@ref STREAM.Utilities.rebin_extensive) keeps the total:

```@example rb
power_neutronics = [1.0, 3.0, 4.0, 2.0] .* 1e3      # W in 4 cells
power_th = rebin_extensive(power_neutronics, 6)
(power_th, sum(power_th))
```

## Values: keep the value

A temperature or a heat flux is a *value*: splitting a cell copies it, merging averages it.
[`rebin_intensive`](@ref STREAM.Utilities.rebin_intensive) keeps it:

```@example rb
rebin_intensive([300.0, 320.0, 340.0, 360.0], 2)
```

## Uneven meshes and two dimensions

Give the cell boundaries for meshes that are not uniform:

```@example rb
src_edges = [0.0, 0.1, 0.3, 0.6]
tgt_edges = [0.0, 0.2, 0.4, 0.6]
rebin_extensive([1.0, 2.0, 3.0], src_edges, tgt_edges)
```

A matrix is rebinned along both directions, axial first, which suits a plate's
`(nz, nx)` power shape:

```@example rb
size(rebin_extensive(ones(8, 3), (4, 2)))
```

None of these checks its input: negative values, zeros and NaNs pass through.

## Shapes to start from

[`cosine_shape`](@ref STREAM.Utilities.cosine_shape) gives each axial cell its share of a
cosine power shape with a chosen peaking factor, integrated over the cell so the shares sum to
1 on any mesh. Spread across a plate's `nx` lateral cells, it is a `power_shape` for
[`HeatDiffusion`](@ref STREAM.Components.HeatDiffusion):

```@example rb
nz, nx = 10, 3
shares = cosine_shape(range(0.0, 0.6; length=nz + 1), 1.4)
power_shape = repeat(shares ./ nx, 1, nx)
(sum(power_shape), maximum(shares) / (1 / nz))
```

The second number is the peak cell's share over the average, a little under 1.4 because a
cell averages over the peak. [`cosine_power_shape`](@ref STREAM.Utilities.cosine_power_shape)
gives an unnormalised cosine-squared shape sampled at cell centres instead.
