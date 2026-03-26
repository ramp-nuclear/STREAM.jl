using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: HeatDiffusion, PipeGeometry_rectangular, PipeGeometry_circular

# ─────────────────────────────────────────────────────────────────
# HDIFF-01: HeatDiffusion instantiation and 2D state variable
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-01: HeatDiffusion callable and returns MTK System" begin
    ps = fill(1.0 / (5 * 3), 5, 3)
    @named hd = HeatDiffusion(nz=5, nx=3, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    @test hd isa ModelingToolkit.System
end

@testset "HDIFF-01: HeatDiffusion exported from STREAM" begin
    @test isdefined(STREAM, :HeatDiffusion)
end

@testset "HDIFF-01: HeatDiffusion mtkcompile bare (no connections)" begin
    ps = fill(1.0 / (3 * 2), 3, 2)
    @named hd = HeatDiffusion(nz=3, nx=2, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    @test_nowarn mtkcompile(hd; fully_determined=false)
end

@testset "HDIFF-01: HeatDiffusion state T[1:nz, 1:nx] present in unknowns" begin
    nz, nx = 3, 2
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    unames = Symbol.(ModelingToolkit.getname.(unknowns(hd)))
    @test :T in unames
    # Count only plate temperature unknowns (excluding thermal port subsystem variables)
    @test count(u -> ModelingToolkit.getname(u) == :T, unknowns(hd)) == nz * nx
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-04: ThermalPort arrays present as named subsystems
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-04: HeatDiffusion has thermal_left and thermal_right subsystems" begin
    nz = 3
    ps = fill(1.0 / (nz * 2), nz, 2)
    @named hd = HeatDiffusion(nz=nz, nx=2, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps)
    sub_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(hd)))
    for i in 1:nz
        @test Symbol(:thermal_left, i)  in sub_names
        @test Symbol(:thermal_right, i) in sub_names
    end
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-02/03: Steady-state behavioral test with pinned boundaries and uniform power
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-02/03: Steady-state plate T > T_boundary and Q_flow signs correct" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr  = 1e5
    ps   = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps, power=pwr)

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct_l, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_bc; name=Symbol(:ct_r, i)) for i in 1:nz]

    conns = [
        [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i)))  for i in 1:nz]...,
        [connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for i in 1:nz]...,
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

    # Q_flow sign check: both left and right use k*(T_bc - T_plate)/(dx/2).
    # When plate is hotter than T_bc: Q_flow < 0 (heat leaving plate = negative into component).
    # MTK convention: Q_flow > 0 means heat INTO the component (HeatDiffusion).
    # So heat leaving the hot plate gives Q_flow < 0 on BOTH faces.
    # Energy balance: |Q_left| + |Q_right| = pwr (total power dissipated).
    left_syms  = [getproperty(ssys.hd, Symbol(:thermal_left, i))  for i in 1:nz]
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    Q_left_total  = sum(sol[left_syms[i].Q_flow]  for i in 1:nz)
    Q_right_total = sum(sol[right_syms[i].Q_flow] for i in 1:nz)

    # Both Q_flow < 0: heat leaving the plate (symmetric, plate hotter than T_bc)
    @test Q_left_total < 0.0
    @test Q_right_total < 0.0

    # Energy balance check: |Q_left| + |Q_right| ≈ power (within 5% for FD approximation)
    @test isapprox(abs(Q_left_total) + abs(Q_right_total), pwr; rtol=0.05)
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-05: One-sided connection — unconnected thermal_right is adiabatic
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-05: Unconnected thermal_right has Q_flow == 0 (adiabatic)" begin
    nz, nx = 3, 3
    T_bc = 600.0
    pwr  = 5e4
    ps   = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=19300.0, cp_s=116.0, k_s=174.0,
                               power_shape=ps, power=pwr)

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct5_l, i)) for i in 1:nz]
    conns = [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left, i)))
             for i in 1:nz]
    @named sys = compose(System(conns, t; name=:sys), hd, ct_l...)
    ssys = mtkcompile(sys; fully_determined=false)

    op = [ssys.hd.T[i, j] => T_bc + 10.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    # Unconnected thermal_right ports must have Q_flow == 0
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
    for i in 1:nz
        @test isapprox(sol[right_syms[i].Q_flow], 0.0; atol=1e-8)
    end
end

# ─────────────────────────────────────────────────────────────────
# HDIFF-03 gap: Non-uniform power_shape — zero center cell is colder
# power_shape = [0.5, 0.0, 0.5] (nx=3): outer cells get all the heat,
# center cell has zero source and must be colder than neighbors at steady state.
# ─────────────────────────────────────────────────────────────────
@testset "HDIFF-03-gap: Non-uniform power_shape: center-only source cell is hottest" begin
    # Rule-1 auto-fix: The originally planned [0.5, 0.0, 0.5] test is physically incorrect.
    # With symmetric BCs and equal outer sources, the Laplacian=0 constraint forces
    # T_center = (T_left + T_right)/2 = T_left at steady state — center is NOT colder.
    # Correct test: put ALL power in center cell [0.0, 1.0, 0.0].
    # At steady state T_center must be strictly hotter than both outer cells,
    # which have zero source and sit adjacent to the cold boundary (T_bc).
    # This verifies that power_shape is applied per-cell correctly.
    nz, nx = 1, 3
    T_bc = 600.0
    pwr  = 1e4
    # All power in center, zero in outer cells: sum = 1.0 (normalized)
    ps = reshape([0.0, 1.0, 0.0], nz, nx)
    @test isapprox(sum(ps), 1.0; atol=1e-12)

    @named hd = HeatDiffusion(nz=nz, nx=nx, Lz=0.6, Lx=0.005, y=0.07,
                               rho_s=2700.0, cp_s=900.0, k_s=200.0,
                               power_shape=ps, power=pwr)

    ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct12_l, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_bc; name=Symbol(:ct12_r, i)) for i in 1:nz]

    conns = [
        [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left,  i))) for i in 1:nz]...,
        [connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for i in 1:nz]...,
    ]
    @named sys = compose(System(conns, t; name=:sys12gap), hd, ct_l..., ct_r...)
    ssys = mtkcompile(sys)

    op = [ssys.hd.T[i, j] => T_bc + 5.0 for i in 1:nz for j in 1:nx]
    sol = solve_steady(ssys, op)

    T_left   = sol[ssys.hd.T[1, 1]]
    T_center = sol[ssys.hd.T[1, 2]]
    T_right  = sol[ssys.hd.T[1, 3]]

    # Center cell (sole source) must be hotter than the zero-source outer cells
    @test T_center > T_left  + 0.01
    @test T_center > T_right + 0.01
    # Center cell must be above T_bc (it receives all the heat)
    @test T_center > T_bc
    # Outer cells (zero source, adjacent to cold BC) must also be above T_bc
    # because they receive heat from the center via diffusion
    @test T_left   > T_bc
    @test T_right  > T_bc
end
