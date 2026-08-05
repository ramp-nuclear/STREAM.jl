using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM: PipeGeometry_rectangular, PipeGeometry_circular

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
    @test isdefined(STREAM.Components, :HeatDiffusion)
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

@testset "Steady-state plate T > T_boundary and Q signs correct" begin
    nz, nx = 3, 3
    T_bc = 326.85
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

    # Unconnected thermal_right ports must have Q == 0
    right_syms = [getproperty(ssys.hd, Symbol(:thermal_right, i)) for i in 1:nz]
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
    T_bc = 226.85
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

# ---------------------------------------------------------------------------
# The mesh constructor
# ---------------------------------------------------------------------------

using Meshes: Ball
using STREAM.Solids

# Hold every boundary face of a tag at a fixed temperature and solve to steady state.
function _pin_and_solve(hd, mesh, T_bc, pwr; guess=T_bc + 10.0, prefix=:pin)
    nz = nlayers(mesh)
    cts = Dict{Symbol,Vector{Any}}()
    conns = Equation[]
    for tag in tags(mesh)
        v = [ConstantTemperature(T_bc; name=Symbol(prefix, tag, i)) for i in 1:nz]
        cts[tag] = v
        append!(conns, [connect(v[i].thermal, port(hd, Symbol(:thermal_, tag), i))
                        for i in 1:nz])
    end
    push!(conns, hd.power ~ pwr)
    flat = reduce(vcat, values(cts))
    @named sys = compose(System(conns, t; name=Symbol(prefix, :_sys)), hd, flat...)
    ssys = mtkcompile(sys)
    sub = getproperty(ssys, nameof(hd))
    op = [sub.T[i, j] => guess for i in 1:nz for j in 1:ncross(mesh)]
    sol = solve_steady(ssys, op)
    # Return a getter so callers do not have to know the component's name.
    return (i, j) -> sol[sub.T[i, j]]
end

@testset "mesh constructor on a slab reproduces the keyword constructor" begin
    nz, nx, Lz, Lx, y = 4, 5, 0.6, 0.005, 0.07
    ρ, cp, k, pwr, T_bc = 19300.0, 116.0, 174.0, 1.0e4, 50.0
    ps = fill(1.0 / (nz * nx), nz, nx)

    @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=Lz, Lx=Lx, y=y,
                              rho_s=ρ, cp_s=cp, k_s=k, power_shape=ps, power=pwr)
    mesh = extrude(slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y),
                   [(i - 1) * Lz / nz for i in 1:(nz + 1)]; axial=false)
    @named hd2 = HeatDiffusion(mesh; materials=[SolidMaterial(ρ, cp, k)],
                               power_shape=ps, power=pwr)

    T1 = _pin_and_solve(hd, mesh, T_bc, pwr; prefix=:kw)
    T2 = _pin_and_solve(hd2, mesh, T_bc, pwr; prefix=:ms)
    for i in 1:nz, j in 1:nx
        @test T1(i, j) ≈ T2(i, j) rtol=1e-10
    end
end

@testset "slab against the analytic parabolic profile" begin
    # A plate with uniform volumetric heating held at T_bc on both faces has
    # T(x) - T_bc = q'''(L^2/4 - (x - L/2)^2) / (2k), peaking at L^2 q''' / (8k).
    nz, nx, Lz, Lx, y = 1, 40, 1.0, 0.02, 1.0
    k, pwr, T_bc = 20.0, 5.0e3, 100.0
    ps = fill(1.0 / nx, nz, nx)
    mesh = extrude(slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y),
                   [0.0, Lz]; axial=false)
    @named hd = HeatDiffusion(mesh; materials=[SolidMaterial(1.0, 1.0, k)],
                              power_shape=ps, power=pwr)
    Tof = _pin_and_solve(hd, mesh, T_bc, pwr; prefix=:par)

    qppp = pwr / (Lx * Lz * y)
    for j in 1:nx
        x = (j - 0.5) * Lx / nx
        want = T_bc + qppp * (Lx^2 / 4 - (x - Lx / 2)^2) / (2k)
        @test Tof(1, j) ≈ want rtol=2e-3
    end
    @test maximum(Tof(1, j) for j in 1:nx) ≈ T_bc + qppp * Lx^2 / (8k) rtol=2e-3
end

@testset "annulus against the analytic radial profile" begin
    # Adiabatic bore, fixed outer wall, uniform q'''. Integrating the shell balance,
    #   T(r_i) - T(r_o) = q'''/(2k) * [ (r_o^2 - r_i^2)/2 - r_i^2 ln(r_o/r_i) ].
    # The O-grid on a concentric annulus is exactly orthogonal, so this is a clean check
    # on the conduction rather than on the mesh.
    ri, ro, k, pwr, T_bc = 2.0e-3, 6.0e-3, 20.0, 800.0, 60.0
    bore = Ball((0.0, 0.0), ri)
    wall = Ball((0.0, 0.0), ro)
    nθ, nr = 48, 12
    # Only the outer wall is tagged, so the bore is adiabatic by omission.
    cross = ogrid_cross_section(bore, wall; n_angular=nθ, n_radial=nr,
                                boundaries=(wall => :wall,))
    mesh = extrude(cross, [0.0, 1.0]; axial=false)
    ps = [cross.area[j] / sum(cross.area) for i in 1:1, j in 1:ncross(cross)]
    @named hd = HeatDiffusion(mesh; materials=[SolidMaterial(1.0, 1.0, k)],
                              power_shape=ps, power=pwr)
    Tof = _pin_and_solve(hd, mesh, T_bc, pwr; prefix=:ann)

    qppp = pwr / sum(cross.area)
    want = qppp / (2k) * ((ro^2 - ri^2) / 2 - ri^2 * log(ro / ri))
    inner = maximum(Tof(1, j) for j in 1:nθ)
    @test inner - T_bc ≈ want rtol=2e-2

    # Azimuthal symmetry: the innermost ring is all one temperature.
    ring = [Tof(1, j) for j in 1:nθ]
    @test maximum(ring) - minimum(ring) < 1e-6 * (inner - T_bc)
end

@testset "contact resistance recovers the series resistance" begin
    # A slab with a gap in the middle carries the same heat, so the temperature jump
    # across the gap is q * r_contact with q the flux density through it.
    nx, Lx, y, Lz = 6, 0.006, 1.0, 1.0
    k, pwr, T_bc = 10.0, 1.0e3, 0.0
    r_gap = 0.002
    cross = slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y)
    # Heat only in the left half, so the flux through the gap is known exactly.
    set_contact!(cross, r_gap; where=(c1, c2) -> c1 == 3)
    mesh = extrude(cross, [0.0, Lz]; axial=false)
    ps = [j <= 3 ? 1.0 / 3 : 0.0 for i in 1:1, j in 1:nx]
    @named hd = HeatDiffusion(mesh; materials=[SolidMaterial(1.0, 1.0, k)],
                              power_shape=ps, power=pwr)

    # Pin only the right face, so all the heat leaves through the gap.
    ct = [ConstantTemperature(T_bc; name=Symbol(:gap_r, i)) for i in 1:1]
    conns = [connect(ct[1].thermal, port(hd, :thermal_right, 1)), hd.power ~ pwr]
    @named sys = compose(System(conns, t; name=:gapsys), hd, ct...)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.hd.T[1, j] => T_bc + 10.0 for j in 1:nx])

    # All pwr crosses the gap, over area y*Lz.
    q = pwr / (y * Lz)
    jump = sol[ssys.hd.T[1, 3]] - sol[ssys.hd.T[1, 4]]
    conduction = q * (Lx / nx) / k        # the two half-cells either side
    @test jump - conduction ≈ q * r_gap rtol=1e-6
end

@testset "axial conduction flattens an axially peaked source" begin
    # Short and thick, so the axial conductance is comparable to the lateral one. On a
    # long thin plate the walls hold the ends down whatever the axial term does.
    nz, nx, Lz, Lx, y = 9, 3, 0.02, 0.02, 0.05
    k, pwr, T_bc = 50.0, 2.0e3, 40.0
    # All the power in the middle layer.
    ps = zeros(nz, nx)
    ps[5, :] .= 1.0 / nx

    function peak_and_edge(axial)
        @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=Lz, Lx=Lx, y=y, rho_s=1.0,
                                  cp_s=1.0, k_s=k, power_shape=ps, power=pwr, axial=axial)
        mesh = extrude(slab_cross_section([(j - 1) * Lx / nx for j in 1:(nx + 1)], y),
                       [(i - 1) * Lz / nz for i in 1:(nz + 1)]; axial=axial)
        Tof = _pin_and_solve(hd, mesh, T_bc, pwr; prefix=Symbol(:ax, axial))
        return (Tof(5, 1), Tof(4, 1))
    end

    off_peak, off_next = peak_and_edge(false)
    on_peak, on_next = peak_and_edge(true)

    # With the layers thermally independent, an unheated layer sits at the wall.
    @test off_next ≈ T_bc atol=1e-6
    # Turning axial conduction on spreads the heat into the neighbouring layers, which
    # both lowers the peak and lifts its neighbour well clear of the wall.
    @test on_peak < off_peak
    @test on_next > T_bc + 0.05 * (on_peak - T_bc)
end

@testset "temperature_feedback reaches every mesh cell" begin
    nz, nx = 3, 4
    mesh = extrude(slab_cross_section([(j - 1) * 0.004 / nx for j in 1:(nx + 1)], 0.05),
                   [(i - 1) * 0.3 / nz for i in 1:(nz + 1)])
    @named hd = HeatDiffusion(mesh; materials=[SolidMaterial(1.0, 1.0, 50.0)],
                              power_shape=fill(1.0 / (nz * nx), nz, nx))
    @named pk = PointKinetics(nothing; temp_worth=Dict(hd => -1.0e-5))
    eqs = temperature_feedback(pk, [hd])
    @test length(eqs) == nz * nx
end

@testset "the mesh constructor rejects a mismatched power_shape or material list" begin
    mesh = extrude(slab_cross_section([0.0, 1.0, 2.0], 1.0), [0.0, 1.0])
    @test_throws ArgumentError HeatDiffusion(mesh; name=:bad,
        materials=[SolidMaterial(1.0, 1.0, 1.0)], power_shape=fill(0.5, 1, 3))
    cross = slab_cross_section([0.0, 1.0, 2.0], 1.0)
    cross.material[2] = 3
    @test_throws ArgumentError HeatDiffusion(extrude(cross, [0.0, 1.0]); name=:bad2,
        materials=[SolidMaterial(1.0, 1.0, 1.0)], power_shape=fill(0.5, 1, 2))
end
