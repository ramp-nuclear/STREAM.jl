# # Hydraulic networks
#
#md # *Download this tutorial as a [Julia script](02_hydraulic_networks.jl) or a
#md # [Jupyter notebook](02_hydraulic_networks.ipynb).*
#
# A reactor's cooling system is a network: the flow divides between parallel branches, such
# as the channels of a core, and joins again. This tutorial builds two networks with known
# answers. The first is a classic puzzle in electrical circuits. In the second, nothing drives
# the flow except the different temperatures of the branches.
#
# Both use [`Resistor`](@ref STREAM.Components.Resistor), the simplest hydraulic component,
# with a pressure drop proportional to the flow, ``\Delta p = R\,\dot m``. It is the analogue
# of an electrical resistor, with pressure for voltage and mass flow for current.
#
# ## The cube
#
# Twelve equal resistors form the edges of a cube, and a pump drives flow from one corner to
# the opposite one. What is the resistance of the cube between those corners?
#
# By symmetry, the flow ``I`` leaving the first corner splits equally into its three edges.
# Each of the three corners it reaches splits its share in two, and the three edges into the
# far corner each carry a third again. The pressure drop along any path is then
# ``R\,I/3 + R\,I/6 + R\,I/3 = \tfrac56 R\,I``, so the cube's equivalent resistance is
# ``\tfrac56 R``.
#
# Label the corners 0 to 7 by the binary digits of their position, so that edges join
# corners differing in one bit. Corner 0 is the source and corner 7 the sink.

using STREAM
using STREAM.Components: Pump, Resistor, HeatExchanger, Gravity
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile, connect

R = 1.0e4                                   # Pa per kg/s
@named pump = Pump(3.0e4)
edges = [(0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6), (3, 7), (4, 5), (4, 6),
         (5, 7), (6, 7)]
resistors = [Resistor(R; name=Symbol(:r, a, b)) for (a, b) in edges];

# Each corner is a junction where several ports meet. `connect` with more than two ports
# makes one: the pressure is the same at all of them and the flows sum to zero. Corner ``c``
# joins the outlets of the edges that end there and the inlets of the edges that start
# there, and the pump closes the loop from corner 7 back to corner 0.

function corner(c)
    ports = []
    c == 0 && push!(ports, pump.outlet)
    c == 7 && push!(ports, pump.inlet)
    for ((a, b), r) in zip(edges, resistors)
        a == c && push!(ports, r.inlet)
        b == c && push!(ports, r.outlet)
    end
    return connect(ports...)
end

connections = [corner.(0:7); pump.inlet.p ~ 1.0e5]
@named cube = assembly(connections, pump, resistors...)
sys = mtkcompile(cube)
sol = solve_steady(sys)

# The pump's head over its flow is the cube's resistance:

I = sol[sys.pump.inlet.ṁ]
R_cube = 3.0e4 / I
@assert isapprox(R_cube, 5 / 6 * R; rtol=1e-8)
R_cube / R

# and each edge carries the share the symmetry argument gave it:

flows = [sol[getproperty(sys, nameof(r)).inlet.ṁ] / I for r in resistors]
@assert all(isapprox.(flows, [1/3, 1/3, 1/3, 1/6, 1/6, 1/6, 1/6, 1/3, 1/6, 1/6, 1/3, 1/3];
                      rtol=1e-8));
# ## Flow driven by temperature
#
# Three vertical branches of height ``H`` join a common plenum at the top and another at the
# bottom, with no pump. Each branch holds water at its own temperature, so each column has a
# different weight. The heavier, colder column sinks and pushes water up through the lighter
# ones: a thermosyphon. Python STREAM uses this case to check how a loop circulates when
# its channels run at different temperatures.
#
# Take each branch's flow ``\dot m_k`` positive upward, from the bottom plenum to the top.
# Every branch sees the same pressure difference between the plenums,
#
# ```math
# p_\text{bottom} - p_\text{top} = R_k\,\dot m_k + \rho_k\,g\,H,
# ```
#
# and no mass is lost, ``\sum_k \dot m_k = 0``. Solving the two together gives
#
# ```math
# p_\text{bottom} - p_\text{top} = g\,H\,\frac{\sum_k \rho_k/R_k}{\sum_k 1/R_k},
# \qquad
# \dot m_k = \frac{(p_\text{bottom} - p_\text{top}) - \rho_k\,g\,H}{R_k}.
# ```
#
# Each branch is a [`HeatExchanger`](@ref STREAM.Components.HeatExchanger) that holds its
# water at the branch temperature, a [`Gravity`](@ref STREAM.Components.Gravity) element for
# the weight of its column, and its resistance. `Gravity` reads the density of the water
# entering it, and with the heat exchanger next to it, that is the branch temperature
# whichever way the water flows.

H = 2.0                                     # m
names = [:hot, :mean, :cold]
T_k = [80.0, 50.0, 20.0]                    # °C
R_k = [1.0e3, 2.0e3, 1.5e3]                 # Pa per kg/s
hxs = [HeatExchanger(T; name=Symbol(:hx_, n)) for (n, T) in zip(names, T_k)]
rises = [Gravity(H; name=Symbol(:rise_, n)) for n in names]
rs = [Resistor(R; name=Symbol(:r_, n)) for (n, R) in zip(names, R_k)]

connections = [
    [inseries(hx, rise, r) for (hx, rise, r) in zip(hxs, rises, rs)]...,
    connect((hx.inlet for hx in hxs)...),   # the bottom plenum
    connect((r.outlet for r in rs)...),     # the top plenum
    hxs[1].inlet.p ~ 2.0e5,
]
@named syphon = assembly(connections, hxs..., rises..., rs...)
sys = mtkcompile(syphon)
sol = solve_steady(sys)

# The flows STREAM finds, hot, mean and cold:

ṁ = [sol[getproperty(sys, nameof(r)).inlet.ṁ] for r in rs]

# and the closed form:

ρ_k = ρ.(H2O, T_k)
Δp = G_EARTH * H * sum(ρ_k ./ R_k) / sum(1 ./ R_k)
ṁ_exact = (Δp .- ρ_k .* G_EARTH .* H) ./ R_k

#-

@assert isapprox(ṁ, ṁ_exact; rtol=1e-8)
@assert isapprox(sum(ṁ), 0.0; atol=1e-12)

# The closed form says which way each branch goes. Write the pressure difference as
# ``g H \bar\rho``, with ``\bar\rho = \sum_k (\rho_k/R_k) / \sum_k (1/R_k)`` the
# resistance-weighted mean density. Then ``\dot m_k`` has the sign of
# ``\bar\rho - \rho_k``: a branch rises when it is lighter than the weighted mean and sinks
# when it is heavier.

ρ_mean = Δp / (G_EARTH * H)
(ρ_mean, ρ_k)

# The hot branch rises and the cold one sinks, as expected. The middle one, at 50 °C, sinks
# too: it is heavier than the weighted mean, because the hot branch, with the lowest
# resistance, pulls the mean towards its own density. In a reactor core this is how a cooler
# channel next to hot ones can see its flow fall, or reverse, once natural circulation sets
# in.
#
# ## What next
#
# Both networks here have no inertia, so they settle instantly. [Pump coastdown](03_pump_coastdown.md)
# adds the inertia of the water, and follows a loop in time as its pump stops.
