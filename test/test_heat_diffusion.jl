using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components

@testset "HeatDiffusion callable and returns MTK System" begin
    @named hd = HeatDiffusion(
        nz=5,
        nx=3,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
    )
    @test hd isa ModelingToolkit.System
end

@testset "HeatDiffusion exported from STREAM" begin
    @test isdefined(STREAM.Components, :HeatDiffusion)
end

@testset "HeatDiffusion mtkcompile bare (no connections)" begin
    @named hd = HeatDiffusion(
        nz=3,
        nx=2,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
    )
    @test_nowarn mtkcompile(hd; fully_determined=false)  # isolated component: dangling thermal ports + unset power(t) by design
end

@testset "HeatDiffusion state T[1:nz, 1:nx] present in unknowns" begin
    nz, nx = 3, 2
    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
    )
    unames = Symbol.(ModelingToolkit.getname.(unknowns(hd)))
    @test :T in unames
    # Count only plate temperature unknowns (excluding thermal port subsystem variables)
    @test count(u -> ModelingToolkit.getname(u) == :T, unknowns(hd)) == nz * nx
end

@testset "HeatDiffusion power: a number is a parameter, nothing an unknown" begin
    kw = (nz=2, nx=2, Lz=0.6, Lx=0.005, y=0.07, rho_s=2700.0, cp_s=900.0, k_s=200.0)
    named(xs) = ModelingToolkit.getname.(xs)
    @named fixed = HeatDiffusion(; kw..., power=1e3)
    @named free = HeatDiffusion(; kw...)
    @test :power in named(parameters(fixed))
    @test :power ∉ named(unknowns(fixed))
    @test :power in named(unknowns(free))
    @test_throws ArgumentError HeatDiffusion(; kw..., power="1e3", name=:bad)

    # A parameter power changes between solves of one compiled system, and with fixed
    # boundary temperatures the heat leaving the plate follows it.
    @named bath = ConstantTemperature(40.0; n=2)
    @named sys = assembly(
        faces((bath, :thermal) => (fixed, :thermal_left)), fixed, bath
    )
    ssys = mtkcompile(sys)
    Q_out(P) = -sum(solve_steady(ssys, [ssys.fixed.power => P])[port(ssys.fixed, :thermal_left, :Q)])
    @test Q_out(1e3) ≈ 1e3 rtol = 1e-6
    @test Q_out(2e3) ≈ 2e3 rtol = 1e-6
end

@testset "HeatDiffusion has thermal_left and thermal_right subsystems" begin
    nz = 3
    @named hd = HeatDiffusion(
        nz=nz,
        nx=2,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
    )
    sub_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(hd)))
    for i in 1:nz
        @test Symbol(:thermal_left, i) in sub_names
        @test Symbol(:thermal_right, i) in sub_names
    end
end

@testset "Steady-state plate T > T_boundary and Q signs correct" begin
    nz, nx = 3, 3
    T_bc = 326.85
    pwr = 1e5

    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power=pwr,
    )

    @named ct_l = ConstantTemperature(T_bc; n=nz)
    @named ct_r = ConstantTemperature(T_bc; n=nz)

    conns = [
        faces(
            (ct_l, :thermal) => (hd, :thermal_left),
            (ct_r, :thermal) => (hd, :thermal_right),
        ),
    ]
    @named sys = assembly(conns, hd, ct_l, ct_r)
    ssys = mtkcompile(sys)

    sol = solve_steady(ssys)

    # All plate temperatures should be >= T_bc (heat source raises interior)
    for i in 1:nz, j in 1:nx
        @test sol[ssys.hd.T[i, j]] >= T_bc - 1e-6
    end

    left_syms = [port(ssys.hd, :thermal_left, i) for i in 1:nz]
    right_syms = [port(ssys.hd, :thermal_right, i) for i in 1:nz]
    Q_left_total = sum(sol[left_syms[i].Q] for i in 1:nz)
    Q_right_total = sum(sol[right_syms[i].Q] for i in 1:nz)

    # Both Q < 0: heat leaving the plate (symmetric, plate hotter than T_bc)
    @test Q_left_total < 0.0
    @test Q_right_total < 0.0

    # Energy balance: at steady state every watt deposited must leave through the two
    # walls, so |Q_left| + |Q_right| == power as an exact conservation identity. It holds
    # for any grid resolution (the finite-difference spatial error sits in the temperature
    # profile, not in the integrated flux balance). Measured residual here is ~1e-14.
    @test isapprox(abs(Q_left_total) + abs(Q_right_total), pwr; rtol=1e-10)
end

@testset "Unconnected thermal_right has Q == 0 (adiabatic)" begin
    nz, nx = 3, 3
    T_bc = 326.85
    pwr = 5e4

    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power=pwr,
    )

    @named ct_l = ConstantTemperature(T_bc; n=nz)
    conns = faces((ct_l, :thermal) => (hd, :thermal_left))
    @named sys = assembly(conns, hd, ct_l)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)

    # Unconnected thermal_right ports must have Q == 0
    right_syms = [port(ssys.hd, :thermal_right, i) for i in 1:nz]
    for i in 1:nz
        @test isapprox(sol[right_syms[i].Q], 0.0; atol=1e-8)
    end
end

@testset "Non-uniform power_shape: center-only source cell is hottest" begin
    nz, nx = 1, 3
    T_bc = 326.85
    pwr = 1e4
    ps = reshape([0.0, 1.0, 0.0], nz, nx)
    @test isapprox(sum(ps), 1.0; atol=1e-12)

    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=2700.0,
        cp_s=900.0,
        k_s=200.0,
        power_shape=ps,
        power=pwr,
    )

    @named ct_l = ConstantTemperature(T_bc; n=nz)
    @named ct_r = ConstantTemperature(T_bc; n=nz)

    conns = [
        faces(
            (ct_l, :thermal) => (hd, :thermal_left),
            (ct_r, :thermal) => (hd, :thermal_right),
        ),
    ]
    @named sys = assembly(conns, hd, ct_l, ct_r)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)

    T_left = sol[ssys.hd.T[1, 1]]
    T_center = sol[ssys.hd.T[1, 2]]
    T_right = sol[ssys.hd.T[1, 3]]

    @test T_center > T_left + 0.01
    @test T_center > T_right + 0.01
    @test T_center > T_bc
    @test T_left > T_bc
    @test T_right > T_bc
end

@testset "lateral symmetry — symmetric BCs + uniform power give T[:,j]==T[:,nx+1-j]" begin
    # Regression guard for the right-boundary cell equation. With both walls at the
    # same T and a uniform volumetric source, the steady lateral profile must be
    # mirror-symmetric: T[i,j] == T[i, nx+1-j]. A wrong/duplicated boundary-cell
    # equation (right cell not evolved) breaks this symmetry.
    nz, nx = 2, 5
    T_bc = 226.85
    pwr = 8e4

    @named hd = HeatDiffusion(
        nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power=pwr,
    )
    @named ct_l = ConstantTemperature(T_bc; n=nz)
    @named ct_r = ConstantTemperature(T_bc; n=nz)
    conns = [
        faces(
            (ct_l, :thermal) => (hd, :thermal_left),
            (ct_r, :thermal) => (hd, :thermal_right),
        ),
    ]
    @named sys = assembly(conns, hd, ct_l, ct_r)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys)

    for i in 1:nz, j in 1:nx
        @test isapprox(sol[ssys.hd.T[i, j]], sol[ssys.hd.T[i, nx + 1 - j]]; rtol=1e-6)
    end
    # And the boundary cells must actually be evolved (hotter than the wall they touch).
    for i in 1:nz
        @test sol[ssys.hd.T[i, 1]]  > T_bc
        @test sol[ssys.hd.T[i, nx]] > T_bc
    end
end
