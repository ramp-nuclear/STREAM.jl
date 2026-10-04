using STREAM
using STREAM.Components: Pump, Resistor, HeatExchanger, Gravity
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile, connect

R = 1.0e4                                   # Pa per kg/s
@named pump = Pump(3.0e4)
edges = [(0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6), (3, 7), (4, 5), (4, 6),
         (5, 7), (6, 7)]
resistors = [Resistor(R; name=Symbol(:r, a, b)) for (a, b) in edges]

function corner(c)
    ports = Any[]
    c == 0 && push!(ports, pump.outlet)
    c == 7 && push!(ports, pump.inlet)
    for ((a, b), r) in zip(edges, resistors)
        a == c && push!(ports, r.inlet)
        b == c && push!(ports, r.outlet)
    end
    return connect(ports...)
end

connections = [[corner(c) for c in 0:7]; pump.inlet.p ~ 1.0e5]
@named cube = assembly(connections, pump, resistors...)
sys = mtkcompile(cube)
sol = solve_steady(sys)

I = sol[sys.pump.inlet.ṁ]
R_cube = 3.0e4 / I
@assert isapprox(R_cube, 5 / 6 * R; rtol=1e-8)
R_cube / R

flows = [sol[getproperty(sys, nameof(r)).inlet.ṁ] / I for r in resistors]
@assert all(isapprox.(flows, [1/3, 1/3, 1/3, 1/6, 1/6, 1/6, 1/6, 1/3, 1/6, 1/6, 1/3, 1/3];
                      rtol=1e-8))
round.(flows; digits=4)

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

ṁ = [sol[getproperty(sys, nameof(r)).inlet.ṁ] for r in rs]

ρ_k = ρ.(H2O, T_k)
Δp = G_EARTH * H * sum(ρ_k ./ R_k) / sum(1 ./ R_k)
ṁ_exact = (Δp .- ρ_k .* G_EARTH .* H) ./ R_k

@assert isapprox(ṁ, ṁ_exact; rtol=1e-8)
@assert isapprox(sum(ṁ), 0.0; atol=1e-12)

ρ_mean = Δp / (G_EARTH * H)
(ρ_mean, ρ_k)
