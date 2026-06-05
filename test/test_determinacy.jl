# test/test_determinacy.jl

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect    # disambiguate from Sockets.connect
using STREAM
using STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion,
                ConstantTemperature, Channel,
                PipeGeometry_circular, PipeGeometry_rectangular,
                build_loop, build_loop_vertical, build_loop_transient,
                build_cube, build_loop_lof_bypass, build_loop_pk,
                ReactivityController

# Helper: assert determinacy contract on an UNCOMPILED system. Calls
# `mtkcompile(...; fully_determined=true)` which raises on imbalance,
# then re-checks Δ=0 against the compiled system.
function assert_determined(label::String, sys)
    ssys = mtkcompile(sys; fully_determined=true)   # raises on imbalance
    @test length(equations(ssys)) == length(unknowns(ssys))
    return ssys
end

# Helper: assert determinacy contract on an ALREADY-COMPILED system.
# All `build_*` builders in src/examples.jl call `mtkcompile` internally
# and return the compiled `ssys` — re-running `mtkcompile` would error
# with "Double simplification is not allowed". So for canonical builders
# we verify the length-equality contract directly: if Δ ≠ 0, the
# internal `mtkcompile` would have either thrown ExtraVariablesSystemException
# (under fully_determined=true) or silently returned an imbalanced
# compiled system that downstream `process_SciMLProblem.check_eqs_u0`
# would reject. The check below catches both regression classes.
function assert_determined_compiled(label::String, ssys)
    @test length(equations(ssys)) == length(unknowns(ssys))
    return ssys
end


function _build_mtr_sym()
    nz = 10; nx = 3
    T_in = 313.15
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(T_in)
    @named cac_r = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)
    conns = Equation[
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        connect(pump_r.port_out, hx_r.port_in),
        connect(hx_r.port_out, cac_r.port_in),
        connect(cac_r.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left, i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
        [connect(getproperty(hd, Symbol(:thermal_right, i)),
                 getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(System(conns, t; name=:mtr_sym_det),
                         pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    return sys
end

function _build_mtr_asym()
    nz = 10; nx = 3
    T_in_l = 313.15; T_in_r = 363.15
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in_l)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(T_in_r)
    @named cac_r = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)
    conns = Equation[
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        connect(pump_r.port_out, hx_r.port_in),
        connect(hx_r.port_out, cac_r.port_in),
        connect(cac_r.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left, i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
        [connect(getproperty(hd, Symbol(:thermal_right, i)),
                 getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(System(conns, t; name=:mtr_asym_det),
                         pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    return sys
end

function _build_mtr_onesided()
    nz = 10; nx = 3
    T_in = 313.15
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)
    conns = Equation[
        connect(pump_l.port_out, hx_l.port_in),
        connect(hx_l.port_out, cac_l.port_in),
        connect(cac_l.port_out, pump_l.port_in),
        pump_l.port_in.P ~ 1.0e5,
        [connect(getproperty(hd, Symbol(:thermal_left, i)),
                 getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(System(conns, t; name=:mtr_onesided_det),
                         pump_l, hx_l, cac_l, hd)
    return sys
end

function _build_val01_fourier()
    nz_v01 = 10; nx_v01 = 5
    Lx_v01 = 0.00127
    T_wall = 300.0
    ps_v01 = fill(1.0 / (nz_v01 * nx_v01), nz_v01, nx_v01)
    @named hd_v01 = HeatDiffusion(;
        nz=nz_v01, nx=nx_v01, Lz=0.6, Lx=Lx_v01, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps_v01, power=0.0)
    ct_l = [ConstantTemperature(T_wall; name=Symbol(:ct_l_, i)) for i in 1:nz_v01]
    ct_r = [ConstantTemperature(T_wall; name=Symbol(:ct_r_, i)) for i in 1:nz_v01]
    conns_v01 = Equation[
        [connect(ct_l[i].thermal, getproperty(hd_v01, Symbol(:thermal_left,  i))) for i in 1:nz_v01]...,
        [connect(ct_r[i].thermal, getproperty(hd_v01, Symbol(:thermal_right, i))) for i in 1:nz_v01]...,
        hd_v01.power ~ 0.0,
    ]
    @named sys_v01 = compose(System(conns_v01, t; name=:val01_det),
                             ct_l..., ct_r..., hd_v01)
    return sys_v01
end

function _build_val02_twoplate()
    nz_v02 = 10; nx_v02 = 3
    T_in_v02 = 313.15
    power_per_plate = 1e4
    @named pump_v02 = Pump(3.0e4)
    @named hx_v02 = HeatExchanger(T_in_v02)
    @named cac_v02 = ChannelAndContacts(;
        n=nz_v02, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps_v02 = fill(1.0 / (nz_v02 * nx_v02), nz_v02, nx_v02)
    @named hd1 = HeatDiffusion(; nz=nz_v02, nx=nx_v02,
        Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps_v02, power=power_per_plate)
    @named hd2 = HeatDiffusion(; nz=nz_v02, nx=nx_v02,
        Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps_v02, power=power_per_plate)
    conns_v02 = Equation[
        connect(pump_v02.port_out, hx_v02.port_in),
        connect(hx_v02.port_out, cac_v02.port_in),
        connect(cac_v02.port_out, pump_v02.port_in),
        pump_v02.port_in.P ~ 1.0e5,
        [connect(getproperty(hd1, Symbol(:thermal_left, i)),
                 getproperty(cac_v02, Symbol(:thermal_left, i))) for i in 1:nz_v02]...,
        [connect(getproperty(hd2, Symbol(:thermal_left, i)),
                 getproperty(cac_v02, Symbol(:thermal_right, i))) for i in 1:nz_v02]...,
        # Close the Δ=−2 deficit (two HD instances → two `power(t)` pins).
        hd1.power ~ power_per_plate,
        hd2.power ~ power_per_plate,
    ]
    @named sys_v02 = compose(System(conns_v02, t; name=:val02_det),
                             pump_v02, hx_v02, cac_v02, hd1, hd2)
    return sys_v02
end

# Testset 1 — canonical builders (GREEN at plan-end)
@testset "Determinacy: canonical builders are fully determined" begin
    @testset "build_loop"            begin assert_determined_compiled("build_loop",            build_loop()) end
    @testset "build_loop_vertical"   begin assert_determined_compiled("build_loop_vertical",   build_loop_vertical()) end
    @testset "build_loop_transient"  begin assert_determined_compiled("build_loop_transient",  build_loop_transient()) end
    @testset "build_cube"            begin assert_determined_compiled("build_cube",            build_cube()) end
    @testset "build_loop_lof_bypass" begin assert_determined_compiled("build_loop_lof_bypass", build_loop_lof_bypass()) end
    @testset "build_loop_pk" begin
        ctrl = ReactivityController()
        ssys, _ic = build_loop_pk(ctrl; n=7, T_inlet=293.15)
        # build_loop_pk returns (ssys, ic); ssys is already compiled.
        assert_determined_compiled("build_loop_pk", ssys)
    end
end

# Scenario topologies
# RED-as-expected at plan-end of 58-01; each row flips to GREEN as its
# corresponding fix plan (58-02 / 58-03 / 58-04) lands.
@testset "Determinacy scenarios" begin
    @testset "MTR symmetric"   begin assert_determined("MTR sym",       _build_mtr_sym()) end
    @testset "MTR asymmetric"  begin assert_determined("MTR asym",      _build_mtr_asym()) end
    @testset "MTR one-sided"   begin assert_determined("MTR onesided",  _build_mtr_onesided()) end
    @testset "Fourier determinacy"  begin assert_determined("Fourier",        _build_val01_fourier()) end
    @testset "two-plate determinacy" begin assert_determined("two-plate",        _build_val02_twoplate()) end
end
