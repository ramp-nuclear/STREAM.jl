using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM: HeatDiffusion, PipeGeometry_rectangular, PipeGeometry_circular

@testset "HeatDiffusion callable and returns MTK System" begin
    ps = fill(1.0 / (5 * 3), 5, 3)
    @named hd = HeatDiffusion(
        nz=5,
        nx=3,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    @test hd isa ModelingToolkit.System
end

@testset "HeatDiffusion exported from STREAM" begin
    @test isdefined(STREAM, :HeatDiffusion)
end

@testset "HeatDiffusion mtkcompile bare (no connections)" begin
    ps = fill(1.0 / (3 * 2), 3, 2)
    @named hd = HeatDiffusion(
        nz=3,
        nx=2,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    @test_nowarn mtkcompile(hd; fully_determined=false)  # isolated component: dangling thermal ports + unset power(t) by design
end

@testset "HeatDiffusion state T[1:nz, 1:nx] present in unknowns" begin
    nz, nx = 3, 2
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    unames = Symbol.(ModelingToolkit.getname.(unknowns(hd)))
    @test :T in unames
    # Count only plate temperature unknowns (excluding thermal port subsystem variables)
    @test count(u -> ModelingToolkit.getname(u) == :T, unknowns(hd)) == nz * nx
end

@testset "HeatDiffusion has thermal_left and thermal_right subsystems" begin
    nz = 3
    ps = fill(1.0 / (nz * 2), nz, 2)
    @named hd = HeatDiffusion(
        nz=nz,
        nx=2,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    sub_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(hd)))
    for i in 1:nz
        @test Symbol(:thermal_left, i) in sub_names
        @test Symbol(:thermal_right, i) in sub_names
    end
end

@testset "Steady-state plate T > T_boundary and Q_flow signs correct" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr = 1e5
    ps = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
        power=pwr,
    )

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct_l, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_bc; name=Symbol(:ct_r, i)) for i in 1:nz]

    conns = [
        [
            connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for
            i in 1:nz
        ]...,
        [
            connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for
            i in 1:nz
        ]...,
        hd.power ~ pwr,
    ]
    @named sys = compose(System(conns, t; name=:sys), hd, ct_l..., ct_r...)
    ssys = mtkcompile(sys)

    # Initial guess: slightly above T_bc to break symmetry
    op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    # All plate temperatures should be >= T_bc (heat source raises interior)
    for i in 1:nz, j in 1:nx
        @test sol[ssys.hd.T[i, j]] >= T_bc - 1e-6
    end

    left_syms = [getproperty(ssys.hd, Symbol(:thermal_left, i)) for i in 1:nz]
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    Q_left_total = sum(sol[left_syms[i].Q_flow] for i in 1:nz)
    Q_right_total = sum(sol[right_syms[i].Q_flow] for i in 1:nz)

    # Both Q_flow < 0: heat leaving the plate (symmetric, plate hotter than T_bc)
    @test Q_left_total < 0.0
    @test Q_right_total < 0.0

    # Energy balance check: |Q_left| + |Q_right| ≈ power (within 5% for FD approximation)
    @test isapprox(abs(Q_left_total) + abs(Q_right_total), pwr; rtol=0.05)
end

@testset "Unconnected thermal_right has Q_flow == 0 (adiabatic)" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr = 5e4
    ps = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
        power=pwr,
    )

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct5_l, i)) for i in 1:nz]
    conns = vcat(
        [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for i in 1:nz],
        [hd.power ~ pwr],
    )
    @named sys = compose(System(conns, t; name=:sys), hd, ct_l...)
    ssys = mtkcompile(sys; fully_determined=true)

    op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    # Unconnected thermal_right ports must have Q_flow == 0
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    for i in 1:nz
        @test isapprox(sol[right_syms[i].Q_flow], 0.0; atol=1e-8)
    end
end

@testset "Non-uniform power_shape: center-only source cell is hottest" begin
    nz, nx = 1, 3
    T_bc = 600.0
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

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct12_l, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_bc; name=Symbol(:ct12_r, i)) for i in 1:nz]

    conns = [
        [
            connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for
            i in 1:nz
        ]...,
        [
            connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for
            i in 1:nz
        ]...,
        hd.power ~ pwr,
    ]
    @named sys = compose(System(conns, t; name=:sys12gap), hd, ct_l..., ct_r...)
    ssys = mtkcompile(sys)

    op = [ssys.hd.T[i, j] => T_bc + 5.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

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
    T_bc = 500.0
    pwr = 8e4
    ps = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(
        nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps, power=pwr,
    )
    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct6_l, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_bc; name=Symbol(:ct6_r, i)) for i in 1:nz]
    conns = [
        [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i))) for i in 1:nz]...,
        [connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for i in 1:nz]...,
        hd.power ~ pwr,
    ]
    @named sys = compose(System(conns, t; name=:sys6), hd, ct_l..., ct_r...)
    ssys = mtkcompile(sys)
    op = [ssys.hd.T[i, j] => T_bc + 5.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    for i in 1:nz, j in 1:nx
        @test isapprox(sol[ssys.hd.T[i, j]], sol[ssys.hd.T[i, nx + 1 - j]]; rtol=1e-6)
    end
    # And the boundary cells must actually be evolved (hotter than the wall they touch).
    for i in 1:nz
        @test sol[ssys.hd.T[i, 1]]  > T_bc
        @test sol[ssys.hd.T[i, nx]] > T_bc
    end
end
