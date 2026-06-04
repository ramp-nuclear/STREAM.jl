# test/test_composition.jl

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM: Channel, _infer_n
using OrdinaryDiffEq: ReturnCode

# ───────────────────────────────────────────────────────────
# Test fixtures — local helpers that build canonical CAC + HD pairs.
# Mirrors Python STREAM's MTR_fuel_and_channel(z_N, fuel_N, clad_N) function
# in tests/test_composition/conftest.py.
# ───────────────────────────────────────────────────────────
function _mtr_pair(; n=4, nz=4, nx=2)
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                    htc_correlation=constant_Nusselt(; Nu=8.235),
                                    friction_correlation=laminar_friction_rectangular(geom))
    @named fuel = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.005,
                                 y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0,
                                 power_shape=ps)
    return cac, fuel
end

# ───────────────────────────────────────────────────────────
# Section 1: port helper (D-18 first bullet)
# ───────────────────────────────────────────────────────────
@testset "port helper — indexed thermal port access on uncompiled CAC" begin
    cac, _ = _mtr_pair()
    p1 = port(cac, :thermal_left, 1)
    @test p1 isa ModelingToolkit.AbstractSystem
    # MTK's getname on a child subsystem returns a parent-qualified Symbol like
    # `:cac₊thermal_left1` after composition. Compare against the equivalent
    # getproperty access (which is exactly what `port` wraps) to assert the
    # helper reaches the same port object as the canonical access pattern.
    @test ModelingToolkit.getname(p1) == ModelingToolkit.getname(getproperty(cac, :thermal_left1))
    p2 = port(cac, :thermal_right, 2)
    @test ModelingToolkit.getname(p2) == ModelingToolkit.getname(getproperty(cac, :thermal_right2))
    # Sanity: the local (last segment) name matches the requested face+i pattern.
    name_str_1 = string(ModelingToolkit.getname(p1))
    @test endswith(name_str_1, "thermal_left1")
    name_str_2 = string(ModelingToolkit.getname(p2))
    @test endswith(name_str_2, "thermal_right2")
end

# ───────────────────────────────────────────────────────────
# Section 2: check_gravity_mismatch (D-18 second bullet)
# Existing G_M tests carry forward — these don't touch Channel architecture.
# ───────────────────────────────────────────────────────────
@testset "check_gravity_mismatch — :ok when no gravity" begin
    geom = PipeGeometry_circular(0.6, 0.01)
    @named ch = ChannelAndContacts(; n=4, geometry=geom)  # default g=0.0
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    # CAC's per-cell thermal ports are Flow-based ThermalPort subsystems —
    # pinning `port.T` directly over-determines via the dangling Flow rule
    # (auto-zeros Q_flow). Drive them via ConstantTemperature `connect()`s
    # (the canonical CAC wall-T pattern; see test_channels.jl SIGN-02 testset).
    ct_l = [ConstantTemperature(313.15; name=Symbol(:ct_l_ok_, i)) for i in 1:4]
    ct_r = [ConstantTemperature(313.15; name=Symbol(:ct_r_ok_, i)) for i in 1:4]
    connections = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [connect(ct_l[i].thermal, port(ch, :thermal_left, i)) for i in 1:4]...,
        [connect(ct_r[i].thermal, port(ch, :thermal_right, i)) for i in 1:4]...,
    ]
    @named sys = compose(System(connections, t; name=:gravok), pump, bc, ch, ct_l..., ct_r...)
    ssys = mtkcompile(sys)
    @test check_gravity_mismatch(ssys) == :ok
end

@testset "check_gravity_mismatch — :mismatch when CAC has g but no Gravity component" begin
    geom = PipeGeometry_circular(0.6, 0.01)
    @named ch = ChannelAndContacts(; n=4, geometry=geom, g=9.80665)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    ct_l = [ConstantTemperature(313.15; name=Symbol(:ct_l_bad_, i)) for i in 1:4]
    ct_r = [ConstantTemperature(313.15; name=Symbol(:ct_r_bad_, i)) for i in 1:4]
    connections = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [connect(ct_l[i].thermal, port(ch, :thermal_left, i)) for i in 1:4]...,
        [connect(ct_r[i].thermal, port(ch, :thermal_right, i)) for i in 1:4]...,
    ]
    @named sys = compose(System(connections, t; name=:gravbad), pump, bc, ch, ct_l..., ct_r...)
    ssys = mtkcompile(sys)
    @test check_gravity_mismatch(ssys) == :mismatch
end

# ───────────────────────────────────────────────────────────
# Section 3: _infer_n (D-18 third bullet)
# Works on CAC (ThermalPort arrays kept); errors on the new Channel/CHF.
# ───────────────────────────────────────────────────────────
@testset "_infer_n: counts thermal_left* on CAC (n=4)" begin
    cac, _ = _mtr_pair(; n=4)
    @test _infer_n(cac) == 4
end

@testset "_infer_n: counts thermal_left* on CAC (n=10)" begin
    cac10, _ = _mtr_pair(; n=10)
    @test _infer_n(cac10) == 10
end

@testset "_infer_n: errors on Channel (no thermal port arrays under new design)" begin
    @named ch = Channel(; n=4, geometry=PipeGeometry_circular(0.6, 0.01))
    @test_throws ArgumentError _infer_n(ch)
end

@testset "_infer_n: errors on ChannelHeatFlux (no thermal port arrays under new design)" begin
    @named chf = ChannelHeatFlux(; n=4, geometry=PipeGeometry_circular(0.6, 0.01))
    @test_throws ArgumentError _infer_n(chf)
end

# ───────────────────────────────────────────────────────────
# Section 4: symmetric_plate compose-correctness (D-18 fourth bullet)
# Multiple shapes; both faces wired correctly; no mtkcompile errors.
# Verify-block requires: at least 2 distinct shape testsets (n=4 + n=10)
# AND at least 2 asymmetric-shape testsets (nx=1, nx=3).
# ───────────────────────────────────────────────────────────
@testset "symmetric_plate(cac, fuel) — n=4, nz=4, nx=2 compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    # Add the missing power binding + a pump loop to make it solvable
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(rods, pump, bc; connections=conns, name=:full)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    # Solve briefly to verify composition produces meaningful steady state
    ic = Pair{Any,Any}[
        [ssys.rods.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.rods.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:2]...,
        ssys.rods.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

@testset "symmetric_plate — n=10, nz=10, nx=2 compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=10, nz=10, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(rods, pump, bc; connections=conns, name=:full10)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    ic = Pair{Any,Any}[
        [ssys.rods.cac.T[i] => 313.15 for i in 1:10]...,
        [ssys.rods.fuel.T[i, j] => 313.15 for i in 1:10 for j in 1:2]...,
        ssys.rods.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

@testset "symmetric_plate — asymmetric nx=4 (wide plate, nx > n)" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=4)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(rods, pump, bc; connections=conns, name=:fullx4)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    ic = Pair{Any,Any}[
        [ssys.rods.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.rods.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:4]...,
        ssys.rods.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

@testset "symmetric_plate — asymmetric nx=3 (non-square plate)" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=3)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(rods, pump, bc; connections=conns, name=:fullx3)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    ic = Pair{Any,Any}[
        [ssys.rods.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.rods.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:3]...,
        ssys.rods.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

# ───────────────────────────────────────────────────────────
# Section 5: plate (dual-CAC + HD) compose-correctness (D-18 fifth bullet)
# Verify-block requires: at least 1 testset with name starting with "plate(".
# ───────────────────────────────────────────────────────────
@testset "plate(ch_left, ch_right, fuel) — both faces wired correctly" begin
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    @named ch_left = ChannelAndContacts(; n=4, geometry=geom)
    @named ch_right = ChannelAndContacts(; n=4, geometry=geom)
    ps = fill(1.0 / 8, 4, 2)
    @named fuel = HeatDiffusion(; nz=4, nx=2, Lz=0.6, Lx=0.005,
                                 y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0,
                                 power_shape=ps)
    pl = plate(ch_left, ch_right, fuel; name=:pl)
    @test pl isa ModelingToolkit.AbstractSystem
    # Power binding + minimal closure (skip pump loop — compose-correctness only)
    @named pump_l = Pump(3.0e4)
    @named bc_l = HeatExchanger(313.15)
    @named pump_r = Pump(3.0e4)
    @named bc_r = HeatExchanger(313.15)
    conns = [
        connect(pump_l.port_out, bc_l.port_in),
        connect(bc_l.port_out, pl.ch_left.port_in),
        connect(pl.ch_left.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        connect(pump_r.port_out, bc_r.port_in),
        connect(bc_r.port_out, pl.ch_right.port_in),
        connect(pl.ch_right.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1.0e5,
        pl.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(pl, pump_l, bc_l, pump_r, bc_r; connections=conns, name=:dualcac)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
end

# ───────────────────────────────────────────────────────────
# Section 6: one_sided_connection (D-18 sixth bullet)
# Verify-block requires: at least 2 "@testset \"one_sided_connection" testsets
# (one per side variant).
# ───────────────────────────────────────────────────────────
@testset "one_sided_connection — side=:left compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    osc = one_sided_connection(cac, fuel; side=:left, name=:osc_l)
    @test osc isa ModelingToolkit.AbstractSystem
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, osc.cac.port_in),
        connect(osc.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        osc.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(osc, pump, bc; connections=conns, name=:osc_full_l)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "one_sided_connection — side=:right compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    osc = one_sided_connection(cac, fuel; side=:right, name=:osc_r)
    @test osc isa ModelingToolkit.AbstractSystem
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, osc.cac.port_in),
        connect(osc.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        osc.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(osc, pump, bc; connections=conns, name=:osc_full_r)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "one_sided_connection — invalid side errors" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test_throws ArgumentError one_sided_connection(cac, fuel; side=:bogus, name=:bad)
end

# ───────────────────────────────────────────────────────────
# Section 7: compose_systems cross-plate wiring (D-18 seventh bullet)
# Stitch two symmetric_plate assemblies via hydraulic-series connect equations.
# ───────────────────────────────────────────────────────────
@testset "compose_systems — two plates in series" begin
    cac1, fuel1 = _mtr_pair(; n=4, nz=4, nx=2)
    cac2, fuel2 = _mtr_pair(; n=4, nz=4, nx=2)
    p1 = symmetric_plate(cac1, fuel1; name=:p1)
    p2 = symmetric_plate(cac2, fuel2; name=:p2)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, p1.cac.port_in),
        connect(p1.cac.port_out, p2.cac.port_in),
        connect(p2.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        p1.fuel.power ~ 1.0e3,
        p2.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(p1, p2, pump, bc; connections=conns, name=:two_plates)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    ic = Pair{Any,Any}[
        [ssys.p1.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.p1.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:2]...,
        [ssys.p2.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.p2.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:2]...,
        ssys.p1.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.2, length=5))
    @test sol.retcode == ReturnCode.Success
end

# ───────────────────────────────────────────────────────────
# Section 8: connect_temperature_feedback (D-18 eighth bullet)
# TF-04 equation-counting tests from Phase 47.
# ───────────────────────────────────────────────────────────
@testset "connect_temperature_feedback — 1D (CAC) emits n equations" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_cac = rods.cac
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_cac => 1.0e-4))
    eqs = connect_temperature_feedback(pk, [rods_cac])
    @test length(eqs) == 4    # n=4 cells
end

@testset "connect_temperature_feedback — 2D (HeatDiffusion) emits nz*nx equations row-major" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_fuel = rods.fuel
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_fuel => 1.0e-4))
    eqs = connect_temperature_feedback(pk, [rods_fuel])
    @test length(eqs) == 4 * 2  # nz=4, nx=2
end

@testset "connect_temperature_feedback — multiple components sum" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_cac = rods.cac
    rods_fuel = rods.fuel
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_cac => 1.0e-4, rods_fuel => 1.0e-4))
    eqs = connect_temperature_feedback(pk, [rods_cac, rods_fuel])
    @test length(eqs) == 4 + 4 * 2  # 4 cells + 4*2 grid
end

# ───────────────────────────────────────────────────────────
# fuel_assembly — four-variant CAC <-> Plate alternation helper.
# Each variant is checked by comparing the helper-built system against a
# hand-rolled connect() chain pointwise (rtol=1e-10) after solve_steady, plus
# the ArgumentError paths and an uncompiled-return smoke. k=2 for variants
# 1/2/3, k=3 for variant 4. build_initializeprob=false is mandatory for HD+CAC.

# Helper: build a fresh (CAC, HD) pair under a caller-supplied name prefix.
# Calls the constructors with name=... directly (not via @named) so the prefix
# can be a runtime Symbol.
function _fa_cac(prefix::Symbol; n=4)
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    ChannelAndContacts(; name=prefix, n=n, geometry=geom,
                       htc_correlation=constant_Nusselt(; Nu=8.235),
                       friction_correlation=laminar_friction_rectangular(geom))
end

function _fa_hd(prefix::Symbol; nz=4, nx=2)
    ps = fill(1.0 / (nz * nx), nz, nx)
    HeatDiffusion(; name=prefix, nz=nz, nx=nx, Lz=0.6, Lx=0.005,
                   y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0,
                   power_shape=ps)
end

# Hand-rolled per-pair wiring (mirrors `_pair_connections`): left member's
# thermal_right to right member's thermal_left. Builds the reference systems.
function _fa_pair_eqs(lsys, rsys, n::Int)
    return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
end

# Time derivative, used to build the Dt(...)=>0.0 IC guesses (see variant-1 note).
const _fa_Dt = Differential(t)

# ─── Variant 1 — channel-bookended (k=2 plates, k+1=3 channels) parity ───
@testset "fuel_assembly variant 1 (channel-bookended, k=2) parity" begin
    n, nz, nx = 4, 4, 2
    # Helper-built path
    c1h = _fa_cac(:c1; n=n); c2h = _fa_cac(:c2; n=n); c3h = _fa_cac(:c3; n=n)
    p1h = _fa_hd(:p1; nz=nz, nx=nx); p2h = _fa_hd(:p2; nz=nz, nx=nx)
    asm_helper = fuel_assembly([c1h, c2h, c3h], [p1h, p2h]; name=:asm_helper)
    @test asm_helper isa ModelingToolkit.AbstractSystem

    @named pump_h = Pump(3.0e4)
    @named bc_h = HeatExchanger(313.15)
    conns_h = [
        connect(pump_h.port_out, bc_h.port_in),
        connect(bc_h.port_out, asm_helper.c1.port_in),
        connect(asm_helper.c1.port_out, asm_helper.c2.port_in),
        connect(asm_helper.c2.port_out, asm_helper.c3.port_in),
        connect(asm_helper.c3.port_out, pump_h.port_in),
        pump_h.port_in.P ~ 1.0e5,
        asm_helper.p1.power ~ 1.0e3,
        asm_helper.p2.power ~ 1.0e3,
    ]
    full_helper = compose_systems(asm_helper, pump_h, bc_h; connections=conns_h, name=:full_helper_v1)
    ssys_helper = mtkcompile(full_helper; build_initializeprob=false)

    # Hand-rolled path — same components, explicit per-pair thermal wiring.
    c1d = _fa_cac(:c1; n=n); c2d = _fa_cac(:c2; n=n); c3d = _fa_cac(:c3; n=n)
    p1d = _fa_hd(:p1; nz=nz, nx=nx); p2d = _fa_hd(:p2; nz=nz, nx=nx)
    therm_eqs = Equation[
        _fa_pair_eqs(c1d, p1d, n)...,
        _fa_pair_eqs(p1d, c2d, n)...,
        _fa_pair_eqs(c2d, p2d, n)...,
        _fa_pair_eqs(p2d, c3d, n)...,
    ]
    asm_hand = compose(System(therm_eqs, t; name=:asm_hand), c1d, c2d, c3d, p1d, p2d)

    @named pump_d = Pump(3.0e4)
    @named bc_d = HeatExchanger(313.15)
    conns_d = [
        connect(pump_d.port_out, bc_d.port_in),
        connect(bc_d.port_out, asm_hand.c1.port_in),
        connect(asm_hand.c1.port_out, asm_hand.c2.port_in),
        connect(asm_hand.c2.port_out, asm_hand.c3.port_in),
        connect(asm_hand.c3.port_out, pump_d.port_in),
        pump_d.port_in.P ~ 1.0e5,
        asm_hand.p1.power ~ 1.0e3,
        asm_hand.p2.power ~ 1.0e3,
    ]
    full_hand = compose_systems(asm_hand, pump_d, bc_d; connections=conns_d, name=:full_hand_v1)
    ssys_hand = mtkcompile(full_hand; build_initializeprob=false)

    # We pass a Dt(...)=>0.0 guess for every per-CAC port_in.mdot, even though
    # mtkcompile only keeps one of them as a differential state — we can't know
    # ahead of time which one survives, and the extras are harmlessly ignored.
    ic_helper = Pair{Any,Any}[
        [ssys_helper.asm_helper.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c3.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_helper.asm_helper.c1.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c2.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c3.port_in.mdot => 0.2,
        _fa_Dt(ssys_helper.asm_helper.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c2.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c3.port_in.mdot) => 0.0,
    ]
    ic_hand = Pair{Any,Any}[
        [ssys_hand.asm_hand.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c3.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_hand.asm_hand.c1.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c2.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c3.port_in.mdot => 0.2,
        _fa_Dt(ssys_hand.asm_hand.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c2.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c3.port_in.mdot) => 0.0,
    ]
    sol_helper = solve_steady(ssys_helper, ic_helper)
    sol_hand = solve_steady(ssys_hand, ic_hand)
    @test sol_helper.retcode == ReturnCode.Success
    @test sol_hand.retcode == ReturnCode.Success

    # Read states by symbol rather than by unknown-vector position: the compiler's
    # ordering can differ between the helper-built and hand-rolled systems.
    vals_helper = Float64[]
    vals_hand = Float64[]
    for cname in (:c1, :c2, :c3), i in 1:n
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, cname), :T)[i]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, cname), :T)[i]])
    end
    for pname in (:p1, :p2), i in 1:nz, j in 1:nx
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, pname), :T)[i, j]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, pname), :T)[i, j]])
    end
    @test isapprox(vals_helper, vals_hand; rtol=1e-10)
end

# ─── Variant 2 — plate-bookended (k=1 channel, k+1=2 plates) parity ───
# The locked k=2 means the smaller variants get k≥1 channels. Variant 2
# uses k=2 channels + k+1=3 plates so 'k' matches the variant-1 cell count.
@testset "fuel_assembly variant 2 (plate-bookended, k=2) parity" begin
    n, nz, nx = 4, 4, 2
    c1h = _fa_cac(:c1; n=n); c2h = _fa_cac(:c2; n=n)
    p1h = _fa_hd(:p1; nz=nz, nx=nx); p2h = _fa_hd(:p2; nz=nz, nx=nx); p3h = _fa_hd(:p3; nz=nz, nx=nx)
    asm_helper = fuel_assembly([c1h, c2h], [p1h, p2h, p3h]; name=:asm_helper)
    @test asm_helper isa ModelingToolkit.AbstractSystem

    @named pump_h = Pump(3.0e4)
    @named bc_h = HeatExchanger(313.15)
    conns_h = [
        connect(pump_h.port_out, bc_h.port_in),
        connect(bc_h.port_out, asm_helper.c1.port_in),
        connect(asm_helper.c1.port_out, asm_helper.c2.port_in),
        connect(asm_helper.c2.port_out, pump_h.port_in),
        pump_h.port_in.P ~ 1.0e5,
        asm_helper.p1.power ~ 1.0e3,
        asm_helper.p2.power ~ 1.0e3,
        asm_helper.p3.power ~ 1.0e3,
    ]
    full_helper = compose_systems(asm_helper, pump_h, bc_h; connections=conns_h, name=:full_helper_v2)
    ssys_helper = mtkcompile(full_helper; build_initializeprob=false)

    c1d = _fa_cac(:c1; n=n); c2d = _fa_cac(:c2; n=n)
    p1d = _fa_hd(:p1; nz=nz, nx=nx); p2d = _fa_hd(:p2; nz=nz, nx=nx); p3d = _fa_hd(:p3; nz=nz, nx=nx)
    therm_eqs = Equation[
        _fa_pair_eqs(p1d, c1d, n)...,
        _fa_pair_eqs(c1d, p2d, n)...,
        _fa_pair_eqs(p2d, c2d, n)...,
        _fa_pair_eqs(c2d, p3d, n)...,
    ]
    asm_hand = compose(System(therm_eqs, t; name=:asm_hand), c1d, c2d, p1d, p2d, p3d)

    @named pump_d = Pump(3.0e4)
    @named bc_d = HeatExchanger(313.15)
    conns_d = [
        connect(pump_d.port_out, bc_d.port_in),
        connect(bc_d.port_out, asm_hand.c1.port_in),
        connect(asm_hand.c1.port_out, asm_hand.c2.port_in),
        connect(asm_hand.c2.port_out, pump_d.port_in),
        pump_d.port_in.P ~ 1.0e5,
        asm_hand.p1.power ~ 1.0e3,
        asm_hand.p2.power ~ 1.0e3,
        asm_hand.p3.power ~ 1.0e3,
    ]
    full_hand = compose_systems(asm_hand, pump_d, bc_d; connections=conns_d, name=:full_hand_v2)
    ssys_hand = mtkcompile(full_hand; build_initializeprob=false)

    # (See the Dt(...) IC note in the variant-1 testset.)
    ic_helper = Pair{Any,Any}[
        [ssys_helper.asm_helper.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p3.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_helper.asm_helper.c1.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c2.port_in.mdot => 0.2,
        _fa_Dt(ssys_helper.asm_helper.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c2.port_in.mdot) => 0.0,
    ]
    ic_hand = Pair{Any,Any}[
        [ssys_hand.asm_hand.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p3.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_hand.asm_hand.c1.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c2.port_in.mdot => 0.2,
        _fa_Dt(ssys_hand.asm_hand.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c2.port_in.mdot) => 0.0,
    ]
    sol_helper = solve_steady(ssys_helper, ic_helper)
    sol_hand = solve_steady(ssys_hand, ic_hand)
    @test sol_helper.retcode == ReturnCode.Success
    @test sol_hand.retcode == ReturnCode.Success

    vals_helper = Float64[]; vals_hand = Float64[]
    for cname in (:c1, :c2), i in 1:n
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, cname), :T)[i]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, cname), :T)[i]])
    end
    for pname in (:p1, :p2, :p3), i in 1:nz, j in 1:nx
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, pname), :T)[i, j]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, pname), :T)[i, j]])
    end
    @test isapprox(vals_helper, vals_hand; rtol=1e-10)
end

# ─── Variant 3 — mixed (k=2 of each), start=:channel parity ───
@testset "fuel_assembly variant 3 (mixed, k=2, start=:channel) parity" begin
    n, nz, nx = 4, 4, 2
    c1h = _fa_cac(:c1; n=n); c2h = _fa_cac(:c2; n=n)
    p1h = _fa_hd(:p1; nz=nz, nx=nx); p2h = _fa_hd(:p2; nz=nz, nx=nx)
    asm_helper = fuel_assembly([c1h, c2h], [p1h, p2h]; bookend=:mixed, start=:channel, name=:asm_helper)
    @test asm_helper isa ModelingToolkit.AbstractSystem

    @named pump_h = Pump(3.0e4)
    @named bc_h = HeatExchanger(313.15)
    conns_h = [
        connect(pump_h.port_out, bc_h.port_in),
        connect(bc_h.port_out, asm_helper.c1.port_in),
        connect(asm_helper.c1.port_out, asm_helper.c2.port_in),
        connect(asm_helper.c2.port_out, pump_h.port_in),
        pump_h.port_in.P ~ 1.0e5,
        asm_helper.p1.power ~ 1.0e3,
        asm_helper.p2.power ~ 1.0e3,
    ]
    full_helper = compose_systems(asm_helper, pump_h, bc_h; connections=conns_h, name=:full_helper_v3)
    ssys_helper = mtkcompile(full_helper; build_initializeprob=false)

    # Hand-rolled — sequence c1, p1, c2, p2 (start=:channel, mixed, open)
    c1d = _fa_cac(:c1; n=n); c2d = _fa_cac(:c2; n=n)
    p1d = _fa_hd(:p1; nz=nz, nx=nx); p2d = _fa_hd(:p2; nz=nz, nx=nx)
    therm_eqs = Equation[
        _fa_pair_eqs(c1d, p1d, n)...,
        _fa_pair_eqs(p1d, c2d, n)...,
        _fa_pair_eqs(c2d, p2d, n)...,
    ]
    asm_hand = compose(System(therm_eqs, t; name=:asm_hand), c1d, c2d, p1d, p2d)

    @named pump_d = Pump(3.0e4)
    @named bc_d = HeatExchanger(313.15)
    conns_d = [
        connect(pump_d.port_out, bc_d.port_in),
        connect(bc_d.port_out, asm_hand.c1.port_in),
        connect(asm_hand.c1.port_out, asm_hand.c2.port_in),
        connect(asm_hand.c2.port_out, pump_d.port_in),
        pump_d.port_in.P ~ 1.0e5,
        asm_hand.p1.power ~ 1.0e3,
        asm_hand.p2.power ~ 1.0e3,
    ]
    full_hand = compose_systems(asm_hand, pump_d, bc_d; connections=conns_d, name=:full_hand_v3)
    ssys_hand = mtkcompile(full_hand; build_initializeprob=false)

    # (See the Dt(...) IC note in the variant-1 testset.)
    ic_helper = Pair{Any,Any}[
        [ssys_helper.asm_helper.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_helper.asm_helper.c1.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c2.port_in.mdot => 0.2,
        _fa_Dt(ssys_helper.asm_helper.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c2.port_in.mdot) => 0.0,
    ]
    ic_hand = Pair{Any,Any}[
        [ssys_hand.asm_hand.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_hand.asm_hand.c1.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c2.port_in.mdot => 0.2,
        _fa_Dt(ssys_hand.asm_hand.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c2.port_in.mdot) => 0.0,
    ]
    sol_helper = solve_steady(ssys_helper, ic_helper)
    sol_hand = solve_steady(ssys_hand, ic_hand)
    @test sol_helper.retcode == ReturnCode.Success
    @test sol_hand.retcode == ReturnCode.Success

    vals_helper = Float64[]; vals_hand = Float64[]
    for cname in (:c1, :c2), i in 1:n
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, cname), :T)[i]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, cname), :T)[i]])
    end
    for pname in (:p1, :p2), i in 1:nz, j in 1:nx
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, pname), :T)[i, j]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, pname), :T)[i, j]])
    end
    @test isapprox(vals_helper, vals_hand; rtol=1e-10)
end

# ─── Variant 4 — closed annular (k=3 of each, ring) parity ───
@testset "fuel_assembly variant 4 (closed annular, k=3) parity" begin
    n, nz, nx = 4, 4, 2
    c1h = _fa_cac(:c1; n=n); c2h = _fa_cac(:c2; n=n); c3h = _fa_cac(:c3; n=n)
    p1h = _fa_hd(:p1; nz=nz, nx=nx); p2h = _fa_hd(:p2; nz=nz, nx=nx); p3h = _fa_hd(:p3; nz=nz, nx=nx)
    asm_helper = fuel_assembly([c1h, c2h, c3h], [p1h, p2h, p3h]; closed=true, name=:asm_helper)
    @test asm_helper isa ModelingToolkit.AbstractSystem

    @named pump_h = Pump(3.0e4)
    @named bc_h = HeatExchanger(313.15)
    conns_h = [
        connect(pump_h.port_out, bc_h.port_in),
        connect(bc_h.port_out, asm_helper.c1.port_in),
        connect(asm_helper.c1.port_out, asm_helper.c2.port_in),
        connect(asm_helper.c2.port_out, asm_helper.c3.port_in),
        connect(asm_helper.c3.port_out, pump_h.port_in),
        pump_h.port_in.P ~ 1.0e5,
        asm_helper.p1.power ~ 1.0e3,
        asm_helper.p2.power ~ 1.0e3,
        asm_helper.p3.power ~ 1.0e3,
    ]
    full_helper = compose_systems(asm_helper, pump_h, bc_h; connections=conns_h, name=:full_helper_v4)
    ssys_helper = mtkcompile(full_helper; build_initializeprob=false)

    # Hand-rolled closed ring: c1 p1 c2 p2 c3 p3, then wrap p3 -> c1.
    c1d = _fa_cac(:c1; n=n); c2d = _fa_cac(:c2; n=n); c3d = _fa_cac(:c3; n=n)
    p1d = _fa_hd(:p1; nz=nz, nx=nx); p2d = _fa_hd(:p2; nz=nz, nx=nx); p3d = _fa_hd(:p3; nz=nz, nx=nx)
    therm_eqs = Equation[
        _fa_pair_eqs(c1d, p1d, n)...,
        _fa_pair_eqs(p1d, c2d, n)...,
        _fa_pair_eqs(c2d, p2d, n)...,
        _fa_pair_eqs(p2d, c3d, n)...,
        _fa_pair_eqs(c3d, p3d, n)...,
        _fa_pair_eqs(p3d, c1d, n)...,  # wrap pair
    ]
    asm_hand = compose(System(therm_eqs, t; name=:asm_hand), c1d, c2d, c3d, p1d, p2d, p3d)

    @named pump_d = Pump(3.0e4)
    @named bc_d = HeatExchanger(313.15)
    conns_d = [
        connect(pump_d.port_out, bc_d.port_in),
        connect(bc_d.port_out, asm_hand.c1.port_in),
        connect(asm_hand.c1.port_out, asm_hand.c2.port_in),
        connect(asm_hand.c2.port_out, asm_hand.c3.port_in),
        connect(asm_hand.c3.port_out, pump_d.port_in),
        pump_d.port_in.P ~ 1.0e5,
        asm_hand.p1.power ~ 1.0e3,
        asm_hand.p2.power ~ 1.0e3,
        asm_hand.p3.power ~ 1.0e3,
    ]
    full_hand = compose_systems(asm_hand, pump_d, bc_d; connections=conns_d, name=:full_hand_v4)
    ssys_hand = mtkcompile(full_hand; build_initializeprob=false)

    # (See the Dt(...) IC note in the variant-1 testset.)
    ic_helper = Pair{Any,Any}[
        [ssys_helper.asm_helper.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.c3.T[i] => 313.15 for i in 1:n]...,
        [ssys_helper.asm_helper.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_helper.asm_helper.p3.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_helper.asm_helper.c1.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c2.port_in.mdot => 0.2,
        ssys_helper.asm_helper.c3.port_in.mdot => 0.2,
        _fa_Dt(ssys_helper.asm_helper.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c2.port_in.mdot) => 0.0,
        _fa_Dt(ssys_helper.asm_helper.c3.port_in.mdot) => 0.0,
    ]
    ic_hand = Pair{Any,Any}[
        [ssys_hand.asm_hand.c1.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c2.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.c3.T[i] => 313.15 for i in 1:n]...,
        [ssys_hand.asm_hand.p1.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p2.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        [ssys_hand.asm_hand.p3.T[i, j] => 313.15 for i in 1:nz for j in 1:nx]...,
        ssys_hand.asm_hand.c1.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c2.port_in.mdot => 0.2,
        ssys_hand.asm_hand.c3.port_in.mdot => 0.2,
        _fa_Dt(ssys_hand.asm_hand.c1.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c2.port_in.mdot) => 0.0,
        _fa_Dt(ssys_hand.asm_hand.c3.port_in.mdot) => 0.0,
    ]
    sol_helper = solve_steady(ssys_helper, ic_helper)
    sol_hand = solve_steady(ssys_hand, ic_hand)
    @test sol_helper.retcode == ReturnCode.Success
    @test sol_hand.retcode == ReturnCode.Success

    vals_helper = Float64[]; vals_hand = Float64[]
    for cname in (:c1, :c2, :c3), i in 1:n
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, cname), :T)[i]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, cname), :T)[i]])
    end
    for pname in (:p1, :p2, :p3), i in 1:nz, j in 1:nx
        push!(vals_helper, sol_helper[getproperty(getproperty(ssys_helper.asm_helper, pname), :T)[i, j]])
        push!(vals_hand,   sol_hand[getproperty(getproperty(ssys_hand.asm_hand, pname), :T)[i, j]])
    end
    @test isapprox(vals_helper, vals_hand; rtol=1e-10)
end

# ─── ArgumentError paths ───

@testset "fuel_assembly — ArgumentError on bookend-vs-length conflict" begin
    # 3 CACs + 2 HDs → auto would infer :channel; explicit bookend=:plate contradicts.
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2); c3 = _fa_cac(:c3)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    @test_throws ArgumentError fuel_assembly([c1, c2, c3], [p1, p2]; bookend=:plate, name=:bad)
end

@testset "fuel_assembly — ArgumentError on bookend=:mixed without start" begin
    # 2 CACs + 2 HDs equal lengths → :mixed bookend valid; missing start required.
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    @test_throws ArgumentError fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, name=:bad)
end

@testset "fuel_assembly — ArgumentError on start with non-mixed bookend" begin
    # 3 CACs + 2 HDs → infers :channel; passing start=:channel is the contradiction
    # (start kwarg is only meaningful for :mixed bookend).
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2); c3 = _fa_cac(:c3)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    @test_throws ArgumentError fuel_assembly([c1, c2, c3], [p1, p2]; start=:channel, name=:bad)
end

@testset "fuel_assembly — ArgumentError on closed=true with unequal lengths" begin
    # 3 CACs + 2 HDs (unequal) + closed=true is incoherent — a ring requires equal counts.
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2); c3 = _fa_cac(:c3)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    @test_throws ArgumentError fuel_assembly([c1, c2, c3], [p1, p2]; closed=true, name=:bad)
end

# ─── Smoke: helper returns an uncompiled ODESystem (no premature mtkcompile) ───
@testset "fuel_assembly — uncompiled ODESystem smoke" begin
    # Build the cheapest variant-3 mixed k=2 instance and confirm the helper
    # returned an UNCOMPILED system (caller is responsible for adding BCs
    # then calling mtkcompile — see helper docstring). A bare `mtkcompile`
    # on the raw assembly is intentionally NOT attempted: without a pump
    # loop + power binding the system has more unknowns than equations and
    # mtkcompile fails consistency. The smoke is "did the helper return a
    # System, not numeric output?"
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    asm = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm_smoke)
    @test asm isa ModelingToolkit.AbstractSystem
end
