using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: _areas_volumes

"""A solid of conductivity `κ`. Steady states do not depend on its density or heat capacity."""
conductor(κ) = Solid(1.0, 1.0, κ)
const UNIT = conductor(1.0)
const WALLS = (:thermal_left, :thermal_right, :thermal_top, :thermal_bottom)

"""The faces of `hd` that carry ports, out of left, right, top and bottom."""
faces_of(hd) = filter(f -> any(s -> startswith(String(nameof(s)), String(f)),
                               ModelingToolkit.get_systems(hd)), WALLS)

"""
Compile `hd` with every face in `walls` held at a fixed temperature, the parameter
`<face>_T.T_bc` that [`fixed`](@ref) sets.
"""
function fixed_walls(hd, walls=faces_of(hd))
    bcs = [ConstantTemperature(zeros(var_length(hd, f)); name=Symbol(f, :_T)) for f in walls]
    @named sys = assembly([faces((bc, :thermal) => (hd, f)) for (bc, f) in zip(bcs, walls)],
                          hd, bcs...)
    return mtkcompile(sys)
end

"""Operating point setting the fixed wall temperatures of `ssys`, one `face => T` per wall."""
fixed(ssys, walls...) = [getproperty(ssys, Symbol(f, :_T)).T_bc => T for (f, T) in walls]

"""
Steady cell temperatures of `body` holding `power`, with each `face => T` in `walls` fixed at
that temperature and every other face adiabatic.
"""
function steady_T(body, walls...; power, kw...)
    @named hd = HeatDiffusion(body; power, kw...)
    ssys = fixed_walls(hd, first.(walls))
    op = fixed(ssys, (f => fill(T, var_length(hd, f)) for (f, T) in walls)...)
    return solve_steady(ssys, op)[ssys.hd.T]
end

"""`dT/dt` of `ssys.hd.T` at cell temperatures `T`, with `op` setting walls and power."""
function dTdt(ssys, T, op=[])
    Ts = collect(ssys.hd.T)
    prob = ODEProblem(ssys, Pair{Any,Any}[vec(Ts) .=> vec(T); op], (0.0, 1.0);
                      build_initializeprob=false)
    return remake(prob; u0=prob.f(prob.u0, prob.p, 0.0))[Ts]
end

"""`n + 1` boundaries from `a` to `b`, each cell `ratio` times as wide as the one before."""
function graded(a, b, n; ratio)
    w = ratio .^ (0:(n - 1))
    return a .+ (b - a) .* [0; cumsum(w)] ./ sum(w)
end

"""The uniform and the graded mesh of `n` cells from `a` to `b`, by name."""
meshes(a, b, n; ratio) = ("uniform" => range(a, b, n + 1), "graded" => graded(a, b, n; ratio))

centres(x) = (x[1:(end - 1)] .+ x[2:end]) ./ 2

"""A slab one cell long and 1 m wide, so its steady state is 1D across `x`."""
slab_row(x, material; kw...) = Slab(; x, z=0:1, y=1.0, material, kw...)

"""A cylinder one cell long, so its steady state is 1D along `r`."""
cylinder_row(r, material; kw...) = Cylinder(; r, z=0:1, material, kw...)

"""Both lateral walls held at `T`."""
both_walls(T) = (:thermal_left => T, :thermal_right => T)

# Two cells across, three along.
const ACROSS, ALONG = 0:2, 0:3
const ROD = Cylinder(; r=ACROSS, z=ALONG, material=UNIT)
names_of(hd) = Set(nameof.(ModelingToolkit.get_systems(hd)))

@testset "cylinder face areas and cell volumes" begin
    Ar, Az, V = _areas_volumes(Cylinder(; r=[0, 1, 4, 14], z=[0, 3, 5, 15], material=UNIT))
    @test Ar ./ 2π ≈ [0 3 12 42; 0 2 8 28; 0 10 40 140]
    @test Az ./ π ≈ repeat([1 15 180], 4)
    @test V ./ π ≈ [3 45 540; 2 30 360; 10 150 1800]
end

@testset "a material matrix needs one solid per cell" begin
    @test_throws DimensionMismatch Slab(; x=ACROSS, z=ALONG, y=1.0, material=fill(UNIT, 2, 2))
end

@testset "a mesh is a vector of boundaries" begin
    @test_throws TypeError Slab(; x=(0, 1), z=ALONG, y=1.0, material=UNIT)
    @test_throws TypeError Cylinder(; r=ACROSS, z=(0, 1), material=UNIT)
end

@testset "a slab has a port per cell on each face" begin
    @named hd = HeatDiffusion(Slab(; x=ACROSS, z=ALONG, y=1.0, material=UNIT))
    @test names_of(hd) == Set([Symbol.(:thermal_left, 1:3); Symbol.(:thermal_right, 1:3)])
end

@testset "a solid rod has no port on its axis" begin
    @named hd = HeatDiffusion(ROD)
    @test names_of(hd) == Set(Symbol.(:thermal_right, 1:3))
end

@testset "an annulus has a port on its inner face" begin
    @named hd = HeatDiffusion(Cylinder(; r=ACROSS .+ 1, z=ALONG, material=UNIT))
    @test :thermal_left1 in names_of(hd)
end

@testset "axial conduction adds a port per column at each end" begin
    @named hd = HeatDiffusion(ROD; axial=true)
    @test names_of(hd) ⊇ Set([Symbol.(:thermal_top, 1:2); Symbol.(:thermal_bottom, 1:2)])
end

const PLATE = Slab(; x=range(0, 0.005, 3), z=range(0, 0.6, 3), y=0.07,
                   material=Solid(2700.0, 900.0, 200.0))

@testset "power: a number is a parameter, nothing an unknown" begin
    named(xs) = ModelingToolkit.getname.(xs)
    @named fixed_power = HeatDiffusion(PLATE; power=1e3)
    @named free = HeatDiffusion(PLATE)
    @test :power in named(parameters(fixed_power))
    @test :power ∉ named(unknowns(fixed_power))
    @test :power in named(unknowns(free))
    @test_throws ArgumentError HeatDiffusion(PLATE; power="1e3", name=:bad)
end

@testset "a parameter power changes between solves of one compiled system" begin
    # The right face is unconnected, hence adiabatic, so all the power leaves on the left.
    @named hd = HeatDiffusion(PLATE; power=1e3)
    ssys = fixed_walls(hd, (:thermal_left,))
    sol(P) = solve_steady(ssys, [fixed(ssys, :thermal_left => [40.0, 40.0]); ssys.hd.power => P])
    @test -sum(sol(1e3)[port(ssys.hd, :thermal_left, :Q)]) ≈ 1e3 rtol = 1e-6
    @test -sum(sol(2e3)[port(ssys.hd, :thermal_left, :Q)]) ≈ 2e3 rtol = 1e-6
    @test all(abs.(sol(2e3)[port(ssys.hd, :thermal_right, :Q)]) .< 1e-8)
end

@testset "a uniform temperature stays put: $(nameof(typeof(body))), axial=$axial" for
        body in (Slab(; x=0:3, z=0:2, y=1.0, material=UNIT), Cylinder(; r=0:3, z=0:2, material=UNIT)),
        axial in (false, true)
    @named hd = HeatDiffusion(body; axial, power=0.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, (f => fill(37.0, var_length(hd, f)) for f in faces_of(hd))...)
    @test all(abs.(dTdt(ssys, fill(37.0, 2, 3), op)) .< 1e-12)
end

@testset "steady state of a plate with zero and uniform power" begin
    # A wall at T_cool behind a contact h is a coolant at T_cool with a heat transfer
    # coefficient h.
    z, x, y = (0:2) .* 0.32, [0, 1, 3, 4] .* 0.38e-3, 51.4e-3
    T_cool, h = [20.0, 40.0], 1e5
    slab = Slab(; x, z, y, material=Solid(3000.0, 700.0, 240.0), x_contacts=[h Inf Inf h])
    @named hd = HeatDiffusion(slab; power_shape=ones(2, 3), power=0.0)
    ssys = fixed_walls(hd)
    op = fixed(ssys, both_walls(T_cool)...)
    Q(sol, side) = sol[port(ssys.hd, side, :Q)]

    # Zero power: the boundary conditions rule.
    sol = solve_steady(ssys, op)
    @test sol[ssys.hd.T] ≈ repeat(T_cool, 1, 3)
    @test all(abs.(Q(sol, :thermal_left)) .< 1e-8)

    # Uniform power: what leaves through the walls at each elevation is what that row makes.
    sol = solve_steady(ssys, [op; ssys.hd.power => 100.0])
    @test -(Q(sol, :thermal_left) .+ Q(sol, :thermal_right)) ≈ fill(300.0, 2)
end

# Steady states against closed forms, each on two meshes.

@testset "slab with uniform heating between fixed walls: $mesh" for (mesh, x) in
        meshes(0, 2e-3, 40; ratio=1.05)
    # T = T_s + q'''x(L - x)/2κ.
    L, κ, q, Ts = 2e-3, 200.0, 1e9, 40.0
    T = steady_T(slab_row(x, conductor(κ)), both_walls(Ts)...; power=q * L)
    xc = centres(x)
    @test vec(T) ≈ Ts .+ q .* xc .* (L .- xc) ./ 2κ rtol = 1e-4
end

@testset "clad slab heated in the meat, with contacts at both interfaces: $mesh" for
        (mesh, (nc, nm)) in ("fine clad" => (8, 12), "fine meat" => (3, 30))
    # The meat makes q'''w_m. Half crosses each clad, linearly, after a jump across the contact;
    # the meat is a parabola on top.
    wc, wm, κc, κm, h, q, Ts = 0.4e-3, 0.5e-3, 250.0, 100.0, 5e4, 1e9, 40.0
    x = Utilities.x_boundaries(nc, nm, wc, wm)
    meat = permutedims(nc .< (1:(2nc + nm)) .<= nc + nm)
    interfaces = permutedims(in.(1:(2nc + nm + 1), Ref((nc + 1, nc + nm + 1))))
    slab = slab_row(x, ifelse.(meat, conductor(κm), conductor(κc));
                    x_contacts=ifelse.(interfaces, h, Inf))
    shape = meat .* permutedims(diff(x))
    T = steady_T(slab, both_walls(Ts)...; power=q * wm, power_shape=shape ./ sum(shape))
    half_flux = q * wm / 2
    T_meat_edge = Ts + half_flux * wc / κc + half_flux / h
    exact(x) = x < wc ? Ts + half_flux * x / κc :
               x > wc + wm ? Ts + half_flux * (2wc + wm - x) / κc :
               T_meat_edge + q * (x - wc) * (wc + wm - x) / 2κm
    @test vec(T) ≈ exact.(centres(x)) rtol = 1e-4
end

# The inner and outer wall temperatures of Python's annulus tests.
const T1, T2 = 45.0, 75.0
const ANNULUS_WALLS = (:thermal_left => T1, :thermal_right => T2)

@testset "annulus with fixed wall temperatures: $mesh" for (mesh, r) in
        meshes(1.0, 3.0, 200; ratio=1.01)
    # T = (T_1 - T_2) ln(r/r_2) / ln(r_1/r_2) + T_2, Incropera (6th ed.) p. 116.
    r1, r2 = extrema(r)
    T = steady_T(cylinder_row(r, UNIT), ANNULUS_WALLS...; power=0.0)
    @test vec(T) ≈ (T1 - T2) .* log.(centres(r) ./ r2) ./ log(r1 / r2) .+ T2 rtol = 1e-5
end

@testset "cylinder given heat production and wall temperature: $mesh" for (mesh, r) in
        meshes(0.0, 3.0, 100; ratio=0.98)
    # T = T_s + q'''(R² - r²)/4κ, with the default uniform power density. No port on the axis,
    # so the first cell's inner face carries no heat.
    R, P = last(r), 100.0
    T = steady_T(cylinder_row(r, UNIT), :thermal_right => T1; power=P)
    q = P / (π * R^2)
    @test vec(T) ≈ q .* (R^2 .- centres(r) .^ 2) ./ 4UNIT.κ .+ T1 rtol = 1e-4
end

@testset "annulus given heat production and wall temperatures: $mesh" for (mesh, r) in
        meshes(1.0, 3.123, 210; ratio=1.01)
    (r1, r2), P = extrema(r), 100.0
    T = steady_T(cylinder_row(r, UNIT), ANNULUS_WALLS...; power=P)
    rc = centres(r)
    q = P / (π * (r2^2 - r1^2))
    ln_ratio = log.(rc ./ r1) ./ log(r2 / r1)
    exact = q / 4UNIT.κ .* (r1^2 .- rc .^ 2 .+ ln_ratio .* (r2^2 - r1^2)) .+ (T2 - T1) .* ln_ratio .+ T1
    @test vec(T) ≈ exact rtol = 1e-5
end

@testset "rod with a pellet-clad gap: $mesh" for ((mesh, pellet), (_, clad)) in
        zip(meshes(0, 4.1e-3, 40; ratio=0.99), meshes(4.1e-3, 4.75e-3, 10; ratio=1.1))
    # Heated pellet, a gap conductance at its surface, unheated clad, a fixed outer wall. The
    # pellet is a parabola, the gap a jump q'''R_p/2h, the clad logarithmic.
    Rp, Rc, κp, κc, hg, q, Ts = 4.1e-3, 4.75e-3, 3.0, 16.0, 5e3, 3e8, 300.0
    r = [pellet; clad[2:end]]
    in_pellet = permutedims(centres(r) .< Rp)
    rod = cylinder_row(r, ifelse.(in_pellet, conductor(κp), conductor(κc));
                       r_contacts=ifelse.(permutedims(r .≈ Rp), hg, Inf))
    V = _areas_volumes(rod)[3]
    shape = in_pellet .* V
    T = steady_T(rod, :thermal_right => Ts; power=q * π * Rp^2, power_shape=shape ./ sum(shape))
    T_clad(r) = Ts + q * Rp^2 / 2κc * log(Rc / r)
    exact(r) = r > Rp ? T_clad(r) : T_clad(Rp) + q * Rp / 2hg + q * (Rp^2 - r^2) / 4κp
    @test vec(T) ≈ exact.(centres(r)) rtol = 1e-4
end

@testset "axial conduction between fixed ends is linear, sides adiabatic" begin
    T = steady_T(Slab(; x=[0.0, 1.0], z=0:4, y=1.0, material=UNIT),
                 :thermal_top => 100.0, :thermal_bottom => 20.0; power=0.0, axial=true)
    @test vec(T) ≈ 100 .- 80 .* (0.5:3.5) ./ 4
end

@testset "two layers with a contact conduct ΔT over the summed resistances" begin
    # Half cells 1/(2·2) and 2/(2·4) on either side of a 1/5 contact: ΣR = 1.2 m²K/W.
    slab = slab_row([0.0, 1, 3], [conductor(2.0) conductor(4.0)]; x_contacts=[Inf 5.0 Inf])
    @named hd = HeatDiffusion(slab; power=0.0)
    ssys = fixed_walls(hd)
    sol = solve_steady(ssys, fixed(ssys, :thermal_left => [10.0], :thermal_right => [50.0]))
    @test only(sol[port(ssys.hd, :thermal_right, :Q)]) ≈ 40 / 1.2
    @test only(sol[port(ssys.hd, :thermal_left, :Q)]) ≈ -40 / 1.2
end
