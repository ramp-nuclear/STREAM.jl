using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: _areas_volumes

include(joinpath(@__DIR__, "data", "heat_diffusion_reference.jl"))

# Python's mock_solid.
const MOCK = Solid(1.0, 1.0, 1.0)
const WALLS = (:thermal_left, :thermal_right, :thermal_top, :thermal_bottom)

"""The faces of `hd` that carry ports, out of left, right, top and bottom."""
faces_of(hd) = filter(f -> any(s -> startswith(String(nameof(s)), String(f)),
                               ModelingToolkit.get_systems(hd)), WALLS)

"""
Compile `hd` with every face in `walls` held at fixed temperatures, Python's `h = inf`. The
temperatures are the parameter `<face>_T.T_bc`, set through [`fixed`](@ref).
"""
function fixed_walls(hd, walls=faces_of(hd))
    bcs = [ConstantTemperature(zeros(var_length(hd, f)); name=Symbol(f, :_T)) for f in walls]
    @named sys = assembly([faces((bc, :thermal) => (hd, f)) for (bc, f) in zip(bcs, walls)],
                          hd, bcs...)
    return mtkcompile(sys)
end

"""Operating point setting the fixed wall temperatures of `ssys`, one `face => T` per wall."""
fixed(ssys, walls...) = [getproperty(ssys, Symbol(f, :_T)).T_bc => T for (f, T) in walls]

"""`dT/dt` of `ssys.hd.T` at cell temperatures `T`, with `op` setting walls and power.

Python's convective wall inputs `T` and `h` are a fixed wall at `T` behind an outer contact `h`,
which is how the tests below pass them.
"""
function dTdt(ssys, T, op=[])
    Ts = collect(ssys.hd.T)
    @assert length(unknowns(ssys)) == length(Ts)   # walls solved, so du is all dT/dt
    prob = ODEProblem(ssys, Pair{Any,Any}[vec(Ts) .=> vec(T); op], (0.0, 1.0);
                      build_initializeprob=false)
    return remake(prob; u0=prob.f(prob.u0, prob.p, 0.0))[Ts]
end

@testset "Solid geometry metrics match Python's cylindrical_areas_volumes" begin
    r_areas, z_areas, volumes = _areas_volumes(Cylinder(), [0, 1, 4, 14], [0, 3, 5, 15])
    @test r_areas ./ 2π ≈ [0 3 12 42; 0 2 8 28; 0 10 40 140]
    @test z_areas ./ π ≈ repeat([1 15 180], 4)
    @test volumes ./ π ≈ [3 45 540; 2 30 360; 10 150 1800]
end

@testset "ports: a solid rod has no inner wall, axial conduction adds top and bottom" begin
    names(hd) = Set(nameof.(ModelingToolkit.get_systems(hd)))
    @named plate = HeatDiffusion(; x=0:2, z=0:3, material=MOCK)
    @test names(plate) == Set([Symbol.(:thermal_left, 1:3); Symbol.(:thermal_right, 1:3)])
    @named rod = HeatDiffusion(; x=0:2, z=0:3, material=MOCK, geometry=Cylinder(), axial=true)
    @test names(rod) ==
          Set([Symbol.(:thermal_right, 1:3); Symbol.(:thermal_top, 1:2); Symbol.(:thermal_bottom, 1:2)])
    @named annulus = HeatDiffusion(; x=1:3, z=0:3, material=MOCK, geometry=Cylinder())
    @test :thermal_left1 in names(annulus)
end

@testset "power: a number is a parameter, nothing an unknown" begin
    kw = (x=range(0, 0.005, 3), z=range(0, 0.6, 3), geometry=Slab(0.07),
          material=Solid(2700.0, 900.0, 200.0))
    named(xs) = ModelingToolkit.getname.(xs)
    @named fixed_power = HeatDiffusion(; kw..., power=1e3)
    @named free = HeatDiffusion(; kw...)
    @test :power in named(parameters(fixed_power))
    @test :power ∉ named(unknowns(fixed_power))
    @test :power in named(unknowns(free))
    @test_throws ArgumentError HeatDiffusion(; kw..., power="1e3", name=:bad)

    # A parameter power changes between solves of one compiled system. The right face is
    # unconnected, hence adiabatic, so all of it leaves through the left.
    @named hd = HeatDiffusion(; kw..., power=1e3)
    ssys = fixed_walls(hd, (:thermal_left,))
    sol(P) = solve_steady(ssys, [fixed(ssys, :thermal_left => [40.0, 40.0]); ssys.hd.power => P])
    @test -sum(sol(1e3)[port(ssys.hd, :thermal_left, :Q)]) ≈ 1e3 rtol = 1e-6
    @test -sum(sol(2e3)[port(ssys.hd, :thermal_left, :Q)]) ≈ 2e3 rtol = 1e-6
    @test all(abs.(sol(2e3)[port(ssys.hd, :thermal_right, :Q)]) .< 1e-8)
end

# Ports of Python's tests/test_calculations/test_heat.py follow, under the Python names.

@testset "Fuel at constant temperature has derivative 0" begin
    @named hd = HeatDiffusion(; x=0:5, z=0:2, material=MOCK, x_contacts=[1 Inf Inf Inf Inf 1],
                              power_shape=zeros(2, 5), power=0.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, :thermal_left => [30.0, 30.0], :thermal_right => [30.0, 30.0])
    @test all(abs.(dTdt(ssys, fill(30.0, 2, 5), op)) .< 1e-12)
end

@testset "diffusion gives 0 for uniform temperatures: $(nameof(typeof(g))), axial=$axial" for
        g in (Slab(1.0), Cylinder()), axial in (false, true)
    @named hd = HeatDiffusion(; x=0:3, z=0:2, material=MOCK, geometry=g, axial, power=0.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, (f => fill(37.0, var_length(hd, f)) for f in faces_of(hd))...)
    @test all(abs.(dTdt(ssys, fill(37.0, 2, 3), op)) .< 1e-12)
end

@testset "derivative of one cell follows the x diffusion kernel" begin
    @named hd = HeatDiffusion(; x=[0.0, 1.0], z=[0.0, 1.0], material=MOCK, power=0.0)
    ssys = fixed_walls(hd)
    for (T, Tl, Tr) in ((5.0, 3.0, 11.0), (80.0, 0.5, 2.0e3))
        op = fixed(ssys, :thermal_left => [Tl], :thermal_right => [Tr])
        @test only(dTdt(ssys, fill(T, 1, 1), op)) ≈ (Tl + Tr - 2T) * 2 * MOCK.κ / 1.0
    end
end

@testset "not equispaced" begin
    @named hd = HeatDiffusion(; x=[0.0, 1, 3, 4], z=[0.0, 1.0], material=MOCK, power=0.0)
    ssys = fixed_walls(hd)
    T0, Tl, Tr = 7.0, 2.0, 11.0
    op = fixed(ssys, :thermal_left => [Tl], :thermal_right => [Tr])
    @test vec(dTdt(ssys, [Tl T0 Tr], op)) ≈ [(T0 - Tl) / 1.5, (Tl + Tr - 2T0) / 3, (T0 - Tr) / 1.5]
end

@testset "specific multi cell has the right dTdt" begin
    # Python's meat_indices [0 1 1; 0 1 1] are the zeros in power_shape, and its contact sits
    # between the first and second cells of every row.
    @named hd = HeatDiffusion(; x=[0.0, 1, 3, 4], z=0:2, material=MOCK,
                              x_contacts=[1e-9 2e4 Inf 1e-9], power_shape=[0 1 1; 0 1 1], power=100.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, :thermal_left => [10.0, 10.0], :thermal_right => [10.0, 10.0])
    @test dTdt(ssys, fill(10.0, 2, 3), op) ≈ [0 50 100; 0 50 100] atol = 1e-6
end

@testset "steady state for a configuration with zero and uniform power" begin
    z, x, y = (0:2) .* 0.32, [0, 1, 3, 4] .* 0.38e-3, 51.4e-3
    T_cool, h = [20.0, 40.0], 1e5
    @named hd = HeatDiffusion(; x, z, material=Solid(3000.0, 700.0, 240.0), geometry=Slab(y),
                              x_contacts=[h Inf Inf h], power_shape=ones(2, 3), power=0.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, :thermal_left => T_cool, :thermal_right => T_cool)
    Q(sol, side) = sol[port(ssys.hd, side, :Q)]

    # Zero power: the boundary conditions rule.
    sol = solve_steady(ssys, op)
    @test sol[ssys.hd.T] ≈ repeat(T_cool, 1, 3)
    @test all(abs.(Q(sol, :thermal_left)) .< 1e-8)

    # Uniform power: what leaves through the walls at each elevation is what that row makes.
    sol = solve_steady(ssys, [op; ssys.hd.power => 100.0])
    @test -(Q(sol, :thermal_left) .+ Q(sol, :thermal_right)) ≈ fill(300.0, 2)
end

@testset "derivative of one cell follows the r diffusion kernel" begin
    r1, r2 = 0.5, 0.75
    @named hd = HeatDiffusion(; x=[r1, r2], z=[0.0, 1.0], material=MOCK, geometry=Cylinder(),
                              power=0.0)
    ssys = fixed_walls(hd)
    T, Tl, Tr = 30.0, 12.0, 70.0
    c = 2 * MOCK.κ * (2 / (r2 - r1)) / (r2^2 - r1^2)
    op = fixed(ssys, :thermal_left => [Tl], :thermal_right => [Tr])
    @test only(dTdt(ssys, fill(T, 1, 1), op)) ≈ c * ((Tl - T) * r1 + (Tr - T) * r2)
end

@testset "derivative of one cell follows the rz diffusion kernel" begin
    r1, r2, z1, dz = 0.5, 0.75, 2.0, 0.05
    @named hd = HeatDiffusion(; x=[r1, r2], z=[z1, z1 + dz], material=MOCK, geometry=Cylinder(),
                              axial=true, power=0.0)
    ssys = fixed_walls(hd)
    T, walls = 30.0, (:thermal_left => 12.0, :thermal_right => 70.0, :thermal_top => 5.0,
                      :thermal_bottom => 55.0)
    c = 2 / (r2 - r1) / (r2^2 - r1^2)
    a = (r1 * c, r2 * c, 1 / dz^2, 1 / dz^2)
    expected = 2 * MOCK.κ * sum(a .* (last.(walls) .- T))
    @test only(dTdt(ssys, fill(T, 1, 1), fixed(ssys, (f => [v] for (f, v) in walls)...))) ≈ expected
end

@testset "annulus given wall temperatures" begin
    # T(r) = (T1 - T2) ln(r/r2) / ln(r1/r2) + T2, Incropera (6th ed.) p. 116.
    (Ts1, Ts2), (r1, r2) = (45.0, 75.0), (1.0, 3.0)
    r = range(r1, r2, 201)
    @named hd = HeatDiffusion(; x=r, z=0:1, material=MOCK, geometry=Cylinder(), power=0.0)
    ssys = fixed_walls(hd)
    sol = solve_steady(ssys, fixed(ssys, :thermal_left => [Ts1], :thermal_right => [Ts2]))
    rc = (r[1:end-1] .+ r[2:end]) ./ 2
    @test isapprox.(vec(sol[ssys.hd.T]), (Ts1 - Ts2) .* log.(rc ./ r2) ./ log(r1 / r2) .+ Ts2;
                    rtol=1e-5, atol=1e-8) |> all
end

@testset "cylinder given heat production and wall temperature" begin
    # T(r) = Ts + q'''(r0² - r²)/4k.
    Twall, r0, P = 45.0, 3.0, 100.0
    r, z = range(0, r0, 101), 0:1
    V = _areas_volumes(Cylinder(), r, z)[3]
    @named hd = HeatDiffusion(; x=r, z, material=MOCK, geometry=Cylinder(), power_shape=V ./ sum(V),
                              power=P)
    ssys = fixed_walls(hd)
    sol = solve_steady(ssys, fixed(ssys, :thermal_right => [Twall]))
    rc = (r[1:end-1] .+ r[2:end]) ./ 2
    qdot = P / (π * r0^2)
    @test isapprox.(vec(sol[ssys.hd.T]), qdot .* (r0^2 .- rc .^ 2) ./ (4MOCK.κ) .+ Twall;
                    rtol=1e-5, atol=1e-8) |> all
end

@testset "annulus given heat production and wall temperatures" begin
    (Ts1, Ts2), (r1, r2), P = (45.0, 75.0), (1.0, 3.123), 100.0
    r, z = range(r1, r2, 211), 0:1
    V = _areas_volumes(Cylinder(), r, z)[3]
    @named hd = HeatDiffusion(; x=r, z, material=MOCK, geometry=Cylinder(), power_shape=V ./ sum(V),
                              power=P)
    ssys = fixed_walls(hd)
    sol = solve_steady(ssys, fixed(ssys, :thermal_left => [Ts1], :thermal_right => [Ts2]))
    rc = (r[1:end-1] .+ r[2:end]) ./ 2
    qdot = P / (π * (r2^2 - r1^2))
    ln_ratio = log.(rc ./ r1) ./ log(r2 / r1)
    expected = qdot / 4MOCK.κ .* (r1^2 .- rc .^ 2 .+ ln_ratio .* (r2^2 - r1^2)) .+ (Ts2 - Ts1) .* ln_ratio .+ Ts1
    @test isapprox.(vec(sol[ssys.hd.T]), expected; rtol=1e-5, atol=1e-8) |> all
end

# Beyond Python's own tests.

@testset "two layers with a contact conduct ΔT over the summed resistances" begin
    # Half cells 1/(2·2) and 2/(2·4) on either side of a 1/5 contact: ΣR = 1.2 m²K/W.
    @named hd = HeatDiffusion(; x=[0.0, 1, 3], z=0:1, material=[Solid(1.0, 1.0, 2.0) Solid(1.0, 1.0, 4.0)],
                              x_contacts=[Inf 5.0 Inf], power=0.0)
    ssys = fixed_walls(hd)
    sol = solve_steady(ssys, fixed(ssys, :thermal_left => [10.0], :thermal_right => [50.0]))
    @test only(sol[port(ssys.hd, :thermal_right, :Q)]) ≈ 40 / 1.2
    @test only(sol[port(ssys.hd, :thermal_left, :Q)]) ≈ -40 / 1.2
end

@testset "axial conduction between fixed ends is linear, sides adiabatic" begin
    @named hd = HeatDiffusion(; x=[0.0, 1.0], z=0:4, material=MOCK, axial=true, power=0.0)
    ssys = fixed_walls(hd, (:thermal_top, :thermal_bottom))
    sol = solve_steady(ssys, fixed(ssys, :thermal_top => [100.0], :thermal_bottom => [20.0]))
    @test vec(sol[ssys.hd.T]) ≈ 100 .- 80 .* (0.5:3.5) ./ 4
end

@testset "kernel matches Python Fuel: $name" for (name, c) in pairs(HEAT_REFERENCE)
    geometry = startswith(String(name), "rod") ? Cylinder() : Slab(c.y)
    axial = endswith(String(name), "z")
    xc, zc = copy(c.x_contacts), fill(Inf, size(c.T) .+ (1, 0))
    walls = [:thermal_right => c.T_right]
    xc[:, end] = c.h_right
    if hasproperty(c, :T_left)
        xc[:, 1] = c.h_left
        push!(walls, :thermal_left => c.T_left)
    end
    if axial
        zc[1, :], zc[end, :] = c.h_top, c.h_bottom
        append!(walls, [:thermal_top => c.T_top, :thermal_bottom => c.T_bottom])
    end
    @named hd = HeatDiffusion(; x=c.x, z=c.z, material=Solid.(c.rho, c.cp, c.k), geometry, axial,
                              x_contacts=xc, z_contacts=zc, power_shape=c.power_shape, power=c.power)
    ssys = fixed_walls(hd)
    @test dTdt(ssys, c.T, fixed(ssys, walls...)) ≈ c.dT rtol = 1e-10
end
