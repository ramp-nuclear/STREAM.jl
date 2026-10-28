using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Assemblies: var_length  # private to Assemblies
using OrdinaryDiffEq: ReturnCode

# A channel and fuel plate pair, Python STREAM's MTR_fuel_and_channel in
# tests/test_composition/conftest.py.
function _mtr_pair(; n=4, nz=4, nx=2, power=1.0e3)
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                    htc=HTC.ConstantNusselt(; Nu=8.235),
                                    darcy=Friction.RectangularLaminar())
    slab = Slab(; x=range(0, 0.005, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                  material=Solid(19300.0, 116.0, 174.0))
    @named fuel = HeatDiffusion(slab; power=power)
    return cac, fuel
end

# port helper
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

@testset "port helper: one variable across every cell" begin
    cac, _ = _mtr_pair(; n=4)
    Ts = port(cac, :thermal_left, :T)
    @test length(Ts) == 4
    @test all(isequal(Ts[i], port(cac, :thermal_left, i).T) for i in 1:4)
end

# var_length
# Counts a ChannelAndContacts' thermal ports; a Channel or ChannelHeatFlux has none.
@testset "var_length: counts thermal_left* on CAC (n=4)" begin
    cac, _ = _mtr_pair(; n=4)
    @test var_length(cac, :thermal_left) == 4
end

@testset "var_length: counts thermal_left* on CAC (n=10)" begin
    cac10, _ = _mtr_pair(; n=10)
    @test var_length(cac10, :thermal_left) == 10
end

@testset "var_length: errors on a Channel, which has no thermal ports" begin
    @named ch = Channel(; n=4, geometry=Duct(0.6, Circular(0.01)))
    @test_throws ArgumentError var_length(ch, :thermal_outer)
end

@testset "var_length: errors on a ChannelHeatFlux, which has no thermal ports" begin
    @named chf = ChannelHeatFlux(; n=4, geometry=Duct(0.6, Circular(0.01)))
    @test_throws ArgumentError var_length(chf, :thermal_outer)
end

# symmetric_plate compose-correctness
# Multiple shapes; both faces wired correctly; no mtkcompile errors.
@testset "symmetric_plate(cac, fuel) — n=4, nz=4, nx=2 compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    # Add a pump loop to make it solvable
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> rods.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
    # Solve briefly to verify composition produces meaningful steady state
    sol = solve_transient(ssys, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

@testset "symmetric_plate — asymmetric nx=4 (wide plate, nx > n)" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=4)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> rods.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
    sol = solve_transient(ssys, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

@testset "symmetric_plate — asymmetric nx=3 (non-square plate)" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=3)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> rods.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
    sol = solve_transient(ssys, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end

# plate (dual-CAC + HD) compose-correctness
@testset "plate(ch_left, ch_right, fuel) — both faces wired correctly" begin
    # plate wires fuel.thermal_left[i] <-> ch_left.thermal_right[i] and
    # fuel.thermal_right[i] <-> ch_right.thermal_left[i]. Solve a steady loop with
    # both channels live (dittus_boelter, aluminum plate, same config as the
    # single_channel both-faces-active test) and verify the wiring is real:
    # each fuel face actually sheds heat to its own channel, the signs are right
    # (heat leaves the powered plate), and the plate temperature sits above both
    # coolant temperatures.
    geom = Duct(0.6, Rectangular(0.07, 0.00127))
    nz = 10
    nx = 3
    power_val = 1.0e4
    @named ch_left = ChannelAndContacts(; n=nz, geometry=geom)
    @named ch_right = ChannelAndContacts(; n=nz, geometry=geom)
    slab = Slab(; x=range(0, 0.00127, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                  material=Solid(2700.0, 900.0, 200.0))
    @named fuel = HeatDiffusion(slab; power=power_val)
    pl = plate(ch_left, ch_right, fuel; name=:pl)
    @test pl isa ModelingToolkit.AbstractSystem
    @assembly ssys begin
        pump_l = Pump(3.0e4)
        bc_l = HeatExchanger(40.0)
        pump_r = Pump(3.0e4)
        bc_r = HeatExchanger(40.0)
        pump_l --> bc_l --> pl.ch_left --> pump_l
        pump_l.inlet.p ~ 1.0e5
        pump_r --> bc_r --> pl.ch_right --> pump_r
        pump_r.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    # Both fuel faces exchange heat with their own channel. thermal_left[i].Q is
    # heat INTO the fuel from ch_left; the powered plate is hotter than the coolant, so
    # heat leaves the plate and Q is negative on every cell of both faces.
    left_face_Q = sol[port(ssys.pl.fuel, :thermal_left, :Q)]
    right_face_Q = [
        sol[port(ssys.pl.fuel, :thermal_right, i).Q] for i in 1:nz
    ]
    @test all(left_face_Q[i] < -1e-3 for i in 1:nz)    # left face sheds heat to ch_left
    @test all(right_face_Q[i] < -1e-3 for i in 1:nz)   # right face sheds heat to ch_right
    # Energy balance: the heat leaving both faces accounts for the injected power.
    @test isapprox(-(sum(left_face_Q) + sum(right_face_Q)), power_val; rtol=1e-3)
    # The heat each face sheds lands in its channel as a coolant temperature rise:
    # ṁ*cp*(T_out - T_in) matches the heat into that channel. T_in is the bc inlet (40.0),
    # T_out is the last coolant cell. cp is taken at the mean coolant temperature.
    T_in = 40.0
    ṁ_l = sol[ssys.pl.ch_left.inlet.ṁ]
    ṁ_r = sol[ssys.pl.ch_right.inlet.ṁ]
    T_out_l = sol[ssys.pl.ch_left.T[nz]]
    T_out_r = sol[ssys.pl.ch_right.T[nz]]
    Q_into_left = ṁ_l * cₚ(H2O, (T_in + T_out_l) / 2) * (T_out_l - T_in)
    Q_into_right = ṁ_r * cₚ(H2O, (T_in + T_out_r) / 2) * (T_out_r - T_in)
    @test isapprox(Q_into_left, -sum(left_face_Q); rtol=2e-2)
    @test isapprox(Q_into_right, -sum(right_face_Q); rtol=2e-2)
    # The plate temperature sits above both coolant streams it dumps heat into.
    @test all(sol[ssys.pl.fuel.T[i, 1]] > sol[ssys.pl.ch_left.T[i]] for i in 1:nz)
    @test all(sol[ssys.pl.fuel.T[i, nx]] > sol[ssys.pl.ch_right.T[i]] for i in 1:nz)
end

# one_sided
# Shared config for the one_sided physics tests: dittus_boelter +
# aluminum plate (same family as the plate / single_channel tests) so the steady
# loop converges. one_sided wires exactly ONE fuel face to the channel
# and leaves the opposite face dangling, which is adiabatic (Q ~ 0) under the
# ThermalPort Flow rule.
function _build_osc_loop(side::Symbol, name_suffix)
    geom = Duct(0.6, Rectangular(0.07, 0.00127))
    nz = 10
    nx = 3
    @named cac = ChannelAndContacts(; n=nz, geometry=geom)
    slab = Slab(; x=range(0, 0.00127, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                  material=Solid(2700.0, 900.0, 200.0))
    @named fuel = HeatDiffusion(slab; power=1e4)
    osc = one_sided(cac, fuel; side=side, name=Symbol(:osc_, name_suffix))
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> osc.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    return ssys, sol, getproperty(ssys, Symbol(:osc_, name_suffix)), nz, nx
end

# Shared physics checks for a one_sided loop, called by both side variants. The single
# connected face sheds all the injected power into the channel, the opposite face is adiabatic, and
# the plate runs hotter than the coolant. `conn_face`/`adia_face` are the per-cell thermal-port name
# prefixes, and `x_conn` is the fuel x-column on the connected side.
function _assert_osc(oscsys, sol, nz, conn_face, adia_face, x_conn)
    @test sol.retcode == ReturnCode.Success
    conn_Q = sol[port(oscsys.fuel, conn_face, :Q)]
    adia_Q = sol[port(oscsys.fuel, adia_face, :Q)]
    @test all(conn_Q[i] < -1e-3 for i in 1:nz)                  # connected face sheds heat
    @test all(isapprox(adia_Q[i], 0.0; atol=1e-9) for i in 1:nz)  # opposite face adiabatic
    @test isapprox(-sum(conn_Q), 1e4; rtol=1e-3)                 # all power leaves the one face
    @test all(sol[oscsys.fuel.T[i, x_conn]] > sol[oscsys.cac.T[i]] for i in 1:nz)
end

@testset "one_sided — side=:left connects right face, left face adiabatic" begin
    osc = one_sided(_mtr_pair(; n=4, nz=4, nx=2)...; side=:left, name=:osc_l)
    @test osc isa ModelingToolkit.AbstractSystem
    # side=:left wires cac.thermal_left <-> fuel.thermal_right, so the fuel's RIGHT
    # face carries heat and the LEFT face is left dangling (adiabatic).
    ssys, sol, oscsys, nz, nx = _build_osc_loop(:left, :l)
    _assert_osc(oscsys, sol, nz, :thermal_right, :thermal_left, nx)
end

@testset "one_sided — side=:right connects left face, right face adiabatic" begin
    osc = one_sided(_mtr_pair(; n=4, nz=4, nx=2)...; side=:right, name=:osc_r)
    @test osc isa ModelingToolkit.AbstractSystem
    # side=:right wires cac.thermal_right <-> fuel.thermal_left, so the fuel's LEFT
    # face carries heat and the RIGHT face is left dangling (adiabatic).
    ssys, sol, oscsys, nz, nx = _build_osc_loop(:right, :r)
    _assert_osc(oscsys, sol, nz, :thermal_left, :thermal_right, 1)
end

@testset "one_sided — invalid side errors" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test_throws ArgumentError one_sided(cac, fuel; side=:bogus, name=:bad)
end

@testset "one_sided — a channel with two faces needs its side named" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test_throws ArgumentError one_sided(cac, fuel; name=:bad)
    @test_throws ArgumentError single_channel(cac, fuel; name=:bad)
end

@testset "one_sided — a channel heated on one wall uses that face" begin
    geom = Duct(0.6, Rectangular(0.070, 0.0025); heated=(right=0.070,))
    @named cac = ChannelAndContacts(; n=4, geometry=geom)
    _, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test string.(equations(one_sided(cac, fuel; name=:osc))) ==
          string.(equations(one_sided(cac, fuel; side=:right, name=:osc)))
    @test_throws ArgumentError one_sided(cac, fuel; side=:left, name=:bad)
    @test_throws ArgumentError single_channel(cac, fuel; fuel_side=:left, name=:bad)
end

# single_channel (edge-channel — plate cooled on both faces)
@testset "single_channel — fuel_side=:left compiles cleanly" begin
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    scc = single_channel(cac, fuel; fuel_side=:left, name=:scc_l)
    @test scc isa ModelingToolkit.AbstractSystem
    # One ConvectiveBoundary per axial cell on the far face (n=4).
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(scc)))
    @test count(s -> startswith(s, "scc_l_far"), sub_names) == 4
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> scc.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "single_channel — fuel_side=:right compiles cleanly" begin
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    scc = single_channel(cac, fuel; fuel_side=:right, name=:scc_r)
    @test scc isa ModelingToolkit.AbstractSystem
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> scc.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "single_channel — both faces active, plate laterally symmetric" begin
    # Use the parity-proven MTR config (dittus_boelter, both faces heated) so the steady
    # solve converges. The far face sheds heat (unlike one_sided) and, cooled
    # by the same h and coolant as the near face, the plate is laterally symmetric.
    geom = Duct(0.6, Rectangular(0.07, 0.00127))
    nz = 10
    nx = 3
    @named cac = ChannelAndContacts(; n=nz, geometry=geom)
    slab = Slab(; x=range(0, 0.00127, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                  material=Solid(2700.0, 900.0, 200.0))
    @named fuel = HeatDiffusion(slab; power=1e4)
    scc = single_channel(cac, fuel; fuel_side=:left, name=:scc_s)
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> scc.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    # Far face carries heat into the convective sink (one_sided would be adiabatic here).
    far_Q = sol[port(ssys.scc_s.fuel, :thermal_right, 1).Q]
    @test abs(far_Q) > 1e-6
    # Laterally symmetric plate (left col == right col).
    for z in 1:nz
        @test isapprox(sol[ssys.scc_s.fuel.T[z, 1]], sol[ssys.scc_s.fuel.T[z, nx]]; rtol=1e-6)
    end
end

@testset "single_channel — invalid fuel_side errors" begin
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test_throws ArgumentError single_channel(cac, fuel; fuel_side=:bogus, name=:bad)
end

# assembly
# Stitch two symmetric_plate assemblies into one hydraulic series.
@testset "assembly: two plates in series" begin
    cac1, fuel1 = _mtr_pair(; n=4, nz=4, nx=2)
    cac2, fuel2 = _mtr_pair(; n=4, nz=4, nx=2)
    p1 = symmetric_plate(cac1, fuel1; name=:p1)
    p2 = symmetric_plate(cac2, fuel2; name=:p2)
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> p1.cac --> p2.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test ssys isa ModelingToolkit.AbstractSystem
    sol = solve_transient(ssys, range(0.0, 0.2, length=5))
    @test sol.retcode == ReturnCode.Success
end

@testset "assembly: connections nest without splatting" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2, power=nothing)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(40.0)
    conns = [
        inseries(pump, bc, cac, pump),
        (pump.inlet.p ~ 1.0e5, fuel.power ~ 1.0e3),
        faces((cac, :thermal_right) => (fuel, :thermal_left)),
        port(cac, :thermal_left, :T) .~ cac.T,
        cac.T .~ 40.0,     # a symbolic array broadcast
    ]
    @named sys = assembly(conns, cac, fuel, pump, bc)
    @test length(ModelingToolkit.get_eqs(sys)) == 3 + 2 + 4 + 4 + 4
    @test Set(nameof.(ModelingToolkit.get_systems(sys))) == Set([:cac, :fuel, :pump, :bc])

    @named single = assembly(pump.inlet.p ~ 1.0e5, pump)
    @test length(ModelingToolkit.get_eqs(single)) == 1
    @named empty = assembly([], pump)
    @test isempty(ModelingToolkit.get_eqs(empty))

    @parameters k_unused = 1.0
    @named withpar = assembly([], pump; parameters=[k_unused])
    @test any(isequal(k_unused), ModelingToolkit.get_ps(withpar))

    @test_throws ArgumentError assembly([pump.inlet.p], pump; name=:bad)
end

# temperature_feedback
# Equation-counting tests for temperature_feedback.
@testset "temperature_feedback — 1D (CAC) emits n equations" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_cac = rods.cac
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_cac => 1.0e-4))
    eqs = temperature_feedback(pk, [rods_cac])
    @test length(eqs) == 4    # n=4 cells
end

@testset "temperature_feedback — 2D (HeatDiffusion) emits nz*nx equations row-major" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_fuel = rods.fuel
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_fuel => 1.0e-4))
    eqs = temperature_feedback(pk, [rods_fuel])
    @test length(eqs) == 4 * 2  # nz=4, nx=2
end

@testset "temperature_feedback — multiple components sum" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    rho_c_fn(t) = 0.0
    rods_cac = rods.cac
    rods_fuel = rods.fuel
    @named pk = PointKinetics(rho_c_fn; temp_worth=Dict(rods_cac => 1.0e-4, rods_fuel => 1.0e-4))
    eqs = temperature_feedback(pk, [rods_cac, rods_fuel])
    @test length(eqs) == 4 + 4 * 2  # 4 cells + 4*2 grid
end

# fuel_assembly: the four chain shapes. Each variant checks that the helper writes the
# same connections as a hand-written faces() chain over the same components, which needs
# no compile. Variant 1 also compiles and solves, to show an assembly built this way runs,
# and so does variant 4, the closed ring, the one shape with no free face.
# Then the ArgumentError paths and an uncompiled-return smoke.

# Helper: build a fresh (CAC, HD) pair under a caller-supplied name prefix.
# Calls the constructors with name=... directly (not via @named) so the prefix
# can be a runtime Symbol.
function _fa_cac(prefix::Symbol; n=4)
    geom = Duct(0.6, Rectangular(0.070, 0.0025))
    ChannelAndContacts(; name=prefix, n=n, geometry=geom,
                       htc=HTC.ConstantNusselt(; Nu=8.235),
                       darcy=Friction.RectangularLaminar())
end

function _fa_hd(prefix::Symbol; nz=4, nx=2, power=1.0e3)
    slab = Slab(; x=range(0, 0.005, nx + 1), z=range(0, 0.6, nz + 1), y=0.07,
                  material=Solid(19300.0, 116.0, 174.0))
    return HeatDiffusion(slab; name=prefix, power=power)
end

"""
    _fa_connections(sys) -> Set{String}

The connection equations `sys` holds, as strings. Equations print relative to the system
that holds them, so two assemblies of the same components compare equal exactly when they
are wired the same way.
"""
_fa_connections(sys) = Set(string.(ModelingToolkit.get_eqs(sys)))

"""
    _fa_hand(pairs, components) -> Set{String}

The connections of a hand-wired assembly, `faces(pairs...)` over `components`.
"""
_fa_hand(pairs, components) =
    _fa_connections(assembly(faces(pairs...), components...; name=:hand))

"""
    _fa_pair(left, right)

One adjacent pair of the chain: `left`'s right face against `right`'s left face.
"""
_fa_pair(left, right) = (left, :thermal_right) => (right, :thermal_left)

@testset "fuel_assembly variant 1 (channel-bookended, k=2) wiring and solve" begin
    c1, c2, c3 = _fa_cac(:c1), _fa_cac(:c2), _fa_cac(:c3)
    p1, p2 = _fa_hd(:p1), _fa_hd(:p2)
    asm = fuel_assembly([c1, c2, c3], [p1, p2]; name=:asm)
    parts = (c1, c2, c3, p1, p2)
    chain = (_fa_pair(c1, p1), _fa_pair(p1, c2), _fa_pair(c2, p2), _fa_pair(p2, c3))
    @test _fa_connections(asm) == _fa_hand(chain, parts)
    # The comparison has teeth: one face swapped is a different wiring.
    miswired = (chain[1:3]..., (p2, :thermal_left) => (c3, :thermal_left))
    @test _fa_connections(asm) != _fa_hand(miswired, parts)

    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> asm.c1 --> asm.c2 --> asm.c3 --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
end

@testset "fuel_assembly variant 2 (plate-bookended, k=2) wiring" begin
    c1, c2 = _fa_cac(:c1), _fa_cac(:c2)
    p1, p2, p3 = _fa_hd(:p1), _fa_hd(:p2), _fa_hd(:p3)
    asm = fuel_assembly([c1, c2], [p1, p2, p3]; name=:asm)
    chain = (_fa_pair(p1, c1), _fa_pair(c1, p2), _fa_pair(p2, c2), _fa_pair(c2, p3))
    @test _fa_connections(asm) == _fa_hand(chain, (c1, c2, p1, p2, p3))
end

@testset "fuel_assembly variant 3 (mixed, k=2, start=:channel) wiring" begin
    c1, c2 = _fa_cac(:c1), _fa_cac(:c2)
    p1, p2 = _fa_hd(:p1), _fa_hd(:p2)
    asm = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm)
    chain = (_fa_pair(c1, p1), _fa_pair(p1, c2), _fa_pair(c2, p2))
    @test _fa_connections(asm) == _fa_hand(chain, (c1, c2, p1, p2))
end

@testset "fuel_assembly variant 4 (closed annular, k=3) wiring and solve" begin
    c1, c2, c3 = _fa_cac(:c1), _fa_cac(:c2), _fa_cac(:c3)
    p1, p2, p3 = _fa_hd(:p1), _fa_hd(:p2), _fa_hd(:p3)
    asm = fuel_assembly([c1, c2, c3], [p1, p2, p3]; closed=true, name=:asm)
    chain = (
        _fa_pair(c1, p1), _fa_pair(p1, c2), _fa_pair(c2, p2),
        _fa_pair(p2, c3), _fa_pair(c3, p3), _fa_pair(p3, c1),  # the last pair wraps round
    )
    @test _fa_connections(asm) == _fa_hand(chain, (c1, c2, c3, p1, p2, p3))

    # The ring is the one shape with no free face, so it is compiled and solved too.
    @assembly ssys begin
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> asm.c1 --> asm.c2 --> asm.c3 --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
end

# #### ArgumentError paths

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

# #### Smoke: helper returns an uncompiled System (no premature mtkcompile)
@testset "fuel_assembly — uncompiled System smoke" begin
    # The helper returns an uncompiled system. It is not compiled here: without a pump
    # loop around the channels it has more unknowns than equations.
    c1 = _fa_cac(:c1); c2 = _fa_cac(:c2)
    p1 = _fa_hd(:p1); p2 = _fa_hd(:p2)
    asm = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm_smoke)
    @test asm isa ModelingToolkit.AbstractSystem
end

@testset "weighted: one channel standing for N" begin
    # A branch wrapped by weighted(N, ...) has to behave, per channel, exactly like a lone
    # channel under the same head. The weights pass pressure through, so the channel sees
    # the same drop and carries the same flow, and only the junctions see N times it. N = 50
    # mirrors Python STREAM's test_Kirchoff_kcl_matrix_fits_known_example_with_weights
    # (signify=50).
    N, n = 50, 4
    geom = Duct(0.6, Circular(0.01))
    function channel_loop(; copies)
        @assembly ssys begin
            pump = Pump(3.0e4)
            hx = HeatExchanger(40.0)
            ch = Channel(; n=n, geometry=geom, g=0.0, h=5000.0)
            branch = copies === nothing ? (ch,) : weighted(copies, ch; name=:core)
            pump --> hx --> branch... --> pump
            pump.inlet.p ~ 1.0e5
            ch.T_wall_outer .~ 100.0
        end
        sol = solve_steady(ssys)
        @test sol.retcode == ReturnCode.Success
        return ssys, sol
    end

    lone, sol_lone = channel_loop(; copies=nothing)
    wtd, sol_wtd = channel_loop(; copies=N)
    ṁ_ch = sol_wtd[wtd.ch.inlet.ṁ]
    @test ṁ_ch ≈ sol_lone[lone.ch.inlet.ṁ] rtol = 1e-8
    T_wtd = sol_wtd[wtd.ch.T]
    @test T_wtd ≈ sol_lone[lone.ch.T] rtol = 1e-8
    @test sol_wtd[wtd.pump.inlet.ṁ] ≈ N * ṁ_ch rtol = 1e-8
    # Pressure passes through the weights, which is why the channel sees the whole head.
    @test sol_wtd[wtd.core_weight_in.outlet.p] ≈ sol_wtd[wtd.core_weight_in.inlet.p] rtol = 1e-12

    @named r = Resistor(1.0)
    @test length(weighted(3, r; name=:hot)) == 3
    @test_throws ArgumentError weighted(0, r; name=:hot)
    @test_throws ArgumentError weighted(2.5, r; name=:hot)
    @test_throws ArgumentError weighted(2; name=:hot)
    @test_throws UndefKeywordError weighted(2, r)
end

@testset "inseries and inparallel take a port only at an end" begin
    @named pool = Tank(; area=2.0, L0=4.0, ports=(bottom=0.0, side=1.0))
    @named r1 = Resistor(1.0)
    @named r2 = Resistor(1.0)
    @named ambient = Environment()
    @test length(inseries(pool.bottom, r1, r2, ambient.port)) == 3
    @test length(inparallel(pool.bottom, (r1, r2), ambient.port)) == 2
    @test_throws r"side is a port" inseries(r1, pool.side, r2)
    @test_throws r"side is a port" inparallel(r1, ((r2, pool.side),), ambient.port)
end

@testset "@assembly names, composes and compiles a block" begin
    @named hx = HeatExchanger(40.0)   # built before the block, and brought in by use
    @assembly loop begin
        geom = Duct(0.6, Circular(0.01))
        pump = Pump(3.0e4)
        ch = Channel(; n=10, geometry=geom, h=5000.0)
        pump --> hx --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ 100.0
    end
    @test nameof(loop) === :loop && ModelingToolkit.iscomplete(loop)
    @test nameof(pump) === :pump && nameof(ch) === :ch && geom isa Duct
    @mtkcompile ssys = assembly([inseries(pump, hx, ch, pump), pump.inlet.p ~ 1.0e5,
                                 ch.T_wall_outer .~ 100.0], pump, hx, ch)
    @test solve_steady(loop)[loop.ch.T] ≈ solve_steady(ssys)[ssys.ch.T] rtol = 1e-10
end

@testset "@assembly composes a system only through the one built from it" begin
    @assembly loop begin
        cac = _fa_cac(:cac)
        fuel = _fa_hd(:fuel)
        rods = symmetric_plate(cac, fuel; name=:rods)
        pump = Pump(3.0e4)
        bc = HeatExchanger(40.0)
        pump --> bc --> rods.cac --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test solve_steady(loop).retcode == ReturnCode.Success
end

@testset "@assembly takes systems in vectors" begin
    pumps = [Pump(; ṁ0=0.5i, name=Symbol(:pump, i)) for i in 1:2]
    hxs = [HeatExchanger(30.0; name=Symbol(:hx, i)) for i in 1:2]
    @assembly loops begin
        [inseries(pumps[i], hxs[i], pumps[i]) for i in 1:2]
        [pumps[i].inlet.p ~ 1.0e5 for i in 1:2]
    end
    @test solve_steady(loops)[loops.pump2.inlet.ṁ] ≈ 1.0
end

@testset "@assembly composes a system listed on its own, and passes keywords on" begin
    @named lone = Inertia(1.0)   # connected to nothing, so the system is underdetermined
    @parameters k_extra = 2.0
    @assembly loop begin
        pump = Pump(3.0e4)
        hx = HeatExchanger(40.0)
        pump --> hx --> pump
        pump.inlet.p ~ 1.0e5
        lone
    end parameters=[k_extra] fully_determined=false
    @test occursin("lone₊", string(unknowns(loop)) * string(observed(loop)))
    @test any(isequal(loop.k_extra), parameters(loop))
end

@testset "@assembly rejects a line that is neither equations nor systems" begin
    machine = StateMachine()
    @test_throws r"put it before the @assembly block" @assembly loop begin
        pump = Pump(3.0e4)
        hx = HeatExchanger(40.0)
        pump --> hx --> pump
        push!(machine, (:A => :B, pump.inlet.ṁ < 0.1))
    end
end

"""The equations `eqs` give, as a set of strings, to compare two wirings."""
_wiring(eqs) = Set(string.(eqs))

@testset "@flowgraph gives the equations inseries and inparallel give" begin
    @named pump = Pump(1.0e4)
    @named hx = HeatExchanger(40.0)
    @named a = Resistor(1.0e3)
    @named b1 = Resistor(1.0e3)
    @named b2 = Resistor(1.0e3)
    @named c = Resistor(1.0e3)
    @test _wiring(@flowgraph pump --> hx --> a || (b1 --> b2) --> pump) ==
          _wiring([inseries(pump, hx); inparallel(hx, [a, (b1, b2)], pump)])
    @test _wiring(@flowgraph pump --> a || b1 --> hx --> b2 || c --> pump) ==
          _wiring([inparallel(pump, [a, b1], hx); inparallel(hx, [b2, c], pump)])
    @test length(@flowgraph begin
        pump --> hx
        hx --> a --> pump
    end) == 3
end

@testset "@flowgraph takes paths built outside it" begin
    @named pump = Pump(1.0e4)
    @named hx = HeatExchanger(40.0)
    @named a = Resistor(1.0e3)
    @named b1 = Resistor(1.0e3)
    @named b2 = Resistor(1.0e3)
    path = (b1, b2)
    @test _wiring(@flowgraph hx --> path --> pump) == _wiring(inseries(hx, b1, b2, pump))
    @test _wiring(@flowgraph hx --> path... --> pump) == _wiring(inseries(hx, b1, b2, pump))
    @test _wiring(@flowgraph hx --> a || path --> pump) ==
          _wiring(inparallel(hx, [a, path], pump))
    @named c = Resistor(1.0e3)
    branches = [a, path]
    @test _wiring(@flowgraph hx --> branches... || c --> pump) ==
          _wiring(inparallel(hx, [a, path, c], pump))
    @named pool = Tank(; area=2.0, L0=4.0, ports=(bottom=0.0,))
    @named ambient = Environment()
    @test _wiring(@flowgraph pool.bottom --> a || b1 --> ambient.port) ==
          _wiring(inparallel(pool.bottom, [a, b1], ambient.port))
end

@testset "@flowgraph rejects a path it cannot wire" begin
    @named pump = Pump(1.0e4)
    @named a = Resistor(1.0e3)
    @named b = Resistor(1.0e3)
    @test_throws r"at least two" @flowgraph pump
    @test_throws r"on each side" @flowgraph a || b --> pump
    @test_throws r"on each side" @flowgraph pump --> a || b --> a || b --> pump
    @test_throws r"`a \|\| b`" Connect._flow_expr(:(pump --> [a, b] --> pump))
    @test_throws r"cannot hold" Connect._flow_expr(:(pump --> a || (b --> a || b) --> pump))
end

@testset "@assembly reads an arrow line as @flowgraph does" begin
    @assembly sys begin
        pump = Pump(1.0e4)
        hx = HeatExchanger(40.0)
        a = Resistor(1.0e3)
        b1 = Resistor(1.0e3)
        b2 = Resistor(1.0e3)
        pump --> hx --> a || (b1 --> b2) --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(sys)
    @test sol[sys.a.inlet.ṁ] ≈ 2 * sol[sys.b1.inlet.ṁ] rtol = 1e-8
    @assembly again begin
        @flowgraph pump --> hx --> a || (b1 --> b2) --> pump
        pump.inlet.p ~ 1.0e5
    end
    @test solve_steady(again)[again.a.inlet.ṁ] ≈ sol[sys.a.inlet.ṁ] rtol = 1e-8
end
