# Model a clad plate or a fuel rod

[`HeatDiffusion`](@ref STREAM.Components.HeatDiffusion) conducts heat through a body
described by a [`Slab`](@ref STREAM.Components.Slab), for a plate, or a
[`Cylinder`](@ref STREAM.Components.Cylinder), for a rod or an annulus. Each describes the
mesh, what every cell is made of, and the contacts between cells. The equations are in
[Heat conduction in fuel](../explanation/conduction.md).

```@example hs
using STREAM
using STREAM.Components: HeatDiffusion, Slab, Cylinder, ChannelAndContacts, Pump,
                         HeatExchanger, ConvectiveBoundary
using STREAM.Assemblies: inseries, symmetric_plate, face
using STREAM.Utilities: cosine_shape, x_boundaries
using ModelingToolkit: @named, mtkcompile
nothing # hide
```

## A clad plate

A plate is fuel meat between two layers of cladding. [`x_boundaries`](@ref STREAM.Utilities.x_boundaries)
places the cell boundaries through its thickness: here two cells in each 0.38 mm cladding
layer and three in the 0.51 mm of meat. A matrix of [`Solid`](@ref)s, one per cell, gives each
cell its material:

```@example hs
n_clad, n_meat, n = 2, 3, 12
nx = n_meat + 2n_clad
x = x_boundaries(n_clad, n_meat, 0.38e-3, 0.51e-3)
z = range(0.0, 0.6; length=n + 1)
clad, meat = Solid(2700.0, 900.0, 180.0), Solid(3000.0, 800.0, 60.0)
in_meat = permutedims(n_clad .< (1:nx) .<= n_clad + n_meat)     # 1 × nx
materials = repeat(ifelse.(in_meat, meat, clad), n, 1)          # n × nx
nothing # hide
```

The power goes into the meat only. `power_shape` gives every cell its share, and is used as
given: zero in the cladding, and in the meat the axial shape split by each cell's width.

```@example hs
widths = in_meat .* permutedims(diff(x))
shape = cosine_shape(z, 1.4) .* (widths ./ sum(widths))
@assert sum(shape) ≈ 1
nothing # hide
```

A contact conductance on the faces between meat and cladding, `x_contacts`, stands for an
imperfect bond. It takes one value per face through the plate, `Inf` for perfect contact:

```@example hs
interfaces = permutedims(in.(1:nx+1, Ref((n_clad + 1, n_clad + n_meat + 1))))
plate = Slab(; x, z, y=0.063, material=materials, x_contacts=ifelse.(interfaces, 2.0e5, Inf))
@named fuel = HeatDiffusion(plate; power=3.0e4, power_shape=shape)
nothing # hide
```

The plate then joins a channel as any other does. Between two channels:

```@example hs
geometry = Duct(0.6, Rectangular(0.067, 0.0024); heated=0.063)
@named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
@named cell = symmetric_plate(ch, fuel)
@named pump = Pump(; ṁ0=0.4)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.outlet.p ~ 1.7e5],
                       pump, hx, cell)
sys = mtkcompile(loop)
sol = solve_steady(sys)
T = [sol[sys.cell.fuel.T[i, j]] for i in 1:n, j in 1:nx]
(hottest_meat=maximum(T[:, vec(in_meat)]), hottest_wall=maximum(sol[sys.cell.ch.T_wall_left]))
```

## Conduct along the plate as well

By default each axial slice conducts across the plate only. `axial=true` adds conduction
along it, and two more port arrays, `thermal_top` and `thermal_bottom`, at the plate's ends.
A port left unconnected is adiabatic, so the ends need nothing unless something cools them:

```@example hs
@named long_fuel = HeatDiffusion(plate; axial=true, power=3.0e4, power_shape=shape)
nothing # hide
```

## A fuel rod

A rod is a [`Cylinder`](@ref STREAM.Components.Cylinder) whose radii start at zero. Its rings
can be pellet and cladding, and the gas gap between them a contact conductance on the face
between them, `r_contacts`:

```@example hs
R_p, R_c, n_rod = 4.1e-3, 4.75e-3, 10
r = [range(0.0, R_p; length=9); range(R_p, R_c; length=4)[2:end]]
pellet = permutedims(r[2:end] .<= R_p)
gap = permutedims(r .== R_p)
rod = Cylinder(; r, z=range(0.0, 1.0; length=n_rod + 1),
               material=repeat(ifelse.(pellet, Solid(10_400.0, 300.0, 3.0),
                                       Solid(6_500.0, 330.0, 16.0)), n_rod, 1),
               r_contacts=ifelse.(gap, 5.0e3, Inf))
rings = pellet .* permutedims(diff(r .^ 2))                  # volume of each pellet ring
shape = cosine_shape(range(0.0, 1.0; length=n_rod + 1), 1.3) .* (rings ./ sum(rings))
@named pin = HeatDiffusion(rod; power=2.0e4, power_shape=shape)
nothing # hide
```

A solid rod has one port array, `thermal_right`, on its outer surface; its axis has none. Each
port joins whatever cools that cell of the surface. Here every cell is cooled by a
[`ConvectiveBoundary`](@ref STREAM.Components.ConvectiveBoundary) at a given heat transfer
coefficient and coolant temperature; a coolant channel would join the same ports, with a
geometry whose heated perimeter is the rod's circumference.

```@example hs
dz = 1.0 / n_rod
films = [ConvectiveBoundary(; name=Symbol(:film, i), area=2π * R_c * dz) for i in 1:n_rod]
cooling = [[f.h ~ 3.0e4 for f in films]; [f.T_fluid ~ 300.0 for f in films]]
@named cooled = assembly([face(films, pin, :thermal_right); cooling], pin, films...)
sys = mtkcompile(cooled)
sol = solve_steady(sys)
centre = [sol[sys.pin.T[i, 1]] for i in 1:n_rod]
surface = [sol[sys.pin.T[i, length(r) - 1]] for i in 1:n_rod]
(hottest_centre=maximum(centre), hottest_clad=maximum(surface))
```

All of the rod's power reaches the coolant:

```@example hs
Q = sum(sol[f.thermal.Q] for f in (getproperty(sys, Symbol(:film, i)) for i in 1:n_rod))
@assert isapprox(Q, 2.0e4; rtol=1e-6)
Q
```

An annulus, such as a tube of fuel cooled inside and out, is a `Cylinder` whose radii start
above zero. It has a `thermal_left` port array on its inner wall as well.
