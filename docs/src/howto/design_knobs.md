# Scan a design parameter

Compiling a model takes far longer than solving it. To compare designs that differ in a
dimension, make the dimension a *design knob*: a parameter that stays symbolic through the
geometry and the equations, so each solve can give it a new value without rebuilding.

```@example knob
using STREAM
using STREAM.Components: Pump, HeatExchanger, HeatDiffusion, ChannelAndContacts
using STREAM.Assemblies: inseries, symmetric_plate
using ModelingToolkit: @named, mtkcompile
nothing # hide
```

## Declare the knob and build with it

[`@design_knob`](@ref) declares one, with a default. Use it wherever the dimension appears.
Here the knob is the channel gap, and the plate keeps its thickness:

```@example knob
gap = @design_knob gap = 0.0024
geometry = PipeGeometry_rectangular(0.6, 0.067, gap, 0.063)

n = 10
@named fuel = HeatDiffusion(; nz=n, nx=2, Lz=0.6, Lx=0.00127, y=0.063,
                            rho_s=2700.0, cp_s=900.0, k_s=180.0, power=2.5e4)
@named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
@named cell = symmetric_plate(ch, fuel)
@named pump = Pump(2.0e4)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.inlet.p ~ 1.7e5],
                       pump, hx, cell)
sys = mtkcompile(loop)
nothing # hide
```

[`PipeGeometry_rectangular`](@ref) and [`PipeGeometry_circular`](@ref) accept a knob for any
length, and the area, hydraulic diameter and perimeters follow it. A knob used in several
components is one parameter: changing it moves all of them.

## Solve at each value

Give the knob's value in the operating point. [`knob_defaults`](@ref) collects the defaults,
for a solve at the declared design:

```@example knob
base = [knob_defaults([gap]); sys.cell.ch.inlet.ṁ => 0.4]
sol = solve_steady(sys, base)
sol[sys.cell.ch.inlet.ṁ]
```

and a scan sets it explicitly, compiling nothing:

```@example knob
gaps = [0.0018, 0.0021, 0.0024, 0.0027, 0.0030]
results = map(gaps) do g
    s = solve_steady(sys, [gap => g, sys.cell.ch.inlet.ṁ => 0.4])
    (gap_mm=1e3g, ṁ=round(s[sys.cell.ch.inlet.ṁ]; digits=3), T_out=round(s[sys.cell.ch.T_out]; digits=2))
end
```

At a fixed pump head, a wider gap lets more water through, and the outlet runs cooler.

## Other parameters

Not every input needs a knob. A component's own parameters, such as a pump's head
`pump.dP_pump`, a plate's power `fuel.power` or a heat exchanger's temperature `hx.T_bc`,
already change in the same way, by name in the operating point. A knob is for a quantity that
enters through a constructor argument, like a dimension that shapes the geometry, or one
shared by several components.
