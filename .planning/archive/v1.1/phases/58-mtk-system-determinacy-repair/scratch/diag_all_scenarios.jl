# Phase 58 — measure n_eqs/n_unknowns across all in-scope scenarios.
# Each scenario is exercised twice: as-is (broken) and with the +1 power pin
# applied to all HeatDiffusion instances in the topology.
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion, ConstantTemperature,
                PipeGeometry_rectangular, Channel, PipeGeometry_circular

function probe_default(label::String, sys)
    print("  ", rpad(label, 36))
    try
        ssys = mtkcompile(sys; fully_determined=false)
        n_eq = length(equations(ssys)); n_uk = length(unknowns(ssys))
        ok_strict = false
        try
            mtkcompile(sys; fully_determined=true); ok_strict = true
        catch
        end
        println("Δ=", lpad(string(n_eq - n_uk), 3),
                "  n_eqs=", lpad(n_eq, 4), "  n_unk=", lpad(n_uk, 4),
                "  fully_determined=true: ", ok_strict ? "PASS" : "FAIL")
    catch e
        println("compile FAILED — ", split(sprint(showerror, e), "\n")[1])
    end
end

println("\n=== Scenario A: MTR symmetric ===")
function build_mtr_sym(; pin_power::Bool=false)
    nz, nx, T_in = 10, 3, 313.15
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4); @named hx_l = HeatExchanger(T_in)
    @named cac_l  = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4); @named hx_r = HeatExchanger(T_in)
    @named cac_r  = ChannelAndContacts(; n=nz, geometry=geom_mtr)
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
    ]
    pin_power && push!(conns, hd.power ~ 1e4)
    @named sys = compose(System(conns, t; name=:mtr_sym),
        pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    return sys
end
probe_default("as-is",         build_mtr_sym())
probe_default("with hd.power pin", build_mtr_sym(; pin_power=true))

println("\n=== Scenario B: MTR asymmetric (different inlet T) ===")
function build_mtr_asym(; pin_power::Bool=false)
    nz, nx = 10, 3
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4); @named hx_l = HeatExchanger(313.15)
    @named cac_l  = ChannelAndContacts(; n=nz, geometry=geom_mtr)
    @named pump_r = Pump(3.0e4); @named hx_r = HeatExchanger(363.15)
    @named cac_r  = ChannelAndContacts(; n=nz, geometry=geom_mtr)
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
    ]
    pin_power && push!(conns, hd.power ~ 1e4)
    @named sys = compose(System(conns, t; name=:mtr_asym),
        pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    return sys
end
probe_default("as-is",         build_mtr_asym())
probe_default("with hd.power pin", build_mtr_asym(; pin_power=true))

println("\n=== Scenario C: MTR one-sided ===")
function build_mtr_onesided(; pin_power::Bool=false)
    nz, nx, T_in = 10, 3, 313.15
    geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named pump_l = Pump(3.0e4); @named hx_l = HeatExchanger(T_in)
    @named cac_l  = ChannelAndContacts(; n=nz, geometry=geom_mtr)
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
    ]
    pin_power && push!(conns, hd.power ~ 1e4)
    @named sys = compose(System(conns, t; name=:mtr_onesided),
        pump_l, hx_l, cac_l, hd)
    return sys
end
probe_default("as-is",         build_mtr_onesided())
probe_default("with hd.power pin", build_mtr_onesided(; pin_power=true))

println("\n=== Scenario D: VAL-01 HD Fourier (HD only, both faces ConstantTemperature) ===")
function build_val01_fourier(; pin_power::Bool=false)
    nz, nx = 10, 5
    Lx = 0.00127
    T_wall = 300.0
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd_v01 = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=Lx, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=0.0)
    ct_l = [ConstantTemperature(T_wall; name=Symbol(:ct_l_, i)) for i in 1:nz]
    ct_r = [ConstantTemperature(T_wall; name=Symbol(:ct_r_, i)) for i in 1:nz]
    conns = Equation[
        [connect(ct_l[i].thermal, getproperty(hd_v01, Symbol(:thermal_left,  i))) for i in 1:nz]...,
        [connect(ct_r[i].thermal, getproperty(hd_v01, Symbol(:thermal_right, i))) for i in 1:nz]...,
    ]
    pin_power && push!(conns, hd_v01.power ~ 0.0)
    @named sys = compose(System(conns, t; name=:val01_sys), ct_l..., ct_r..., hd_v01)
    return sys
end
probe_default("as-is",         build_val01_fourier())
probe_default("with hd.power pin", build_val01_fourier(; pin_power=true))

println("\n=== Scenario E: VAL-02 two-plate one-channel (steady) ===")
function build_val02_twoplate(; pin_power::Bool=false)
    nz, nx, T_in = 10, 3, 313.15
    @named pump = Pump(3.0e4); @named hx = HeatExchanger(T_in)
    @named cac  = ChannelAndContacts(;
        n=nz, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd1 = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)
    @named hd2 = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)
    conns = Equation[
        connect(pump.port_out, hx.port_in),
        connect(hx.port_out, cac.port_in),
        connect(cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [connect(getproperty(hd1, Symbol(:thermal_left,  i)),
                 getproperty(cac, Symbol(:thermal_left,  i))) for i in 1:nz]...,
        [connect(getproperty(hd2, Symbol(:thermal_left,  i)),
                 getproperty(cac, Symbol(:thermal_right, i))) for i in 1:nz]...,
    ]
    if pin_power
        push!(conns, hd1.power ~ 1e4)
        push!(conns, hd2.power ~ 1e4)
    end
    @named sys = compose(System(conns, t; name=:val02_sys), pump, hx, cac, hd1, hd2)
    return sys
end
probe_default("as-is",         build_val02_twoplate())
probe_default("with hd.power pin (x2)", build_val02_twoplate(; pin_power=true))

# VAL-02 transient T_wall step is build_loop_transient (NO HeatDiffusion).
println("\n=== Scenario F: VAL-02 transient T_wall step (build_loop_transient) ===")
import STREAM: build_loop_transient
T_wall_step = t -> t < 10.0 ? 373.15 : 393.15
ssys_callable = build_loop_transient(; T_inlet=313.15, T_wall_fn=T_wall_step)
n_eq = length(equations(ssys_callable)); n_uk = length(unknowns(ssys_callable))
println("  build_loop_transient(T_wall_fn=...) compiled. Δ=", n_eq - n_uk,
        "  n_eqs=", n_eq, "  n_unk=", n_uk)
println("  -- ssys.sys getproperty :T_wall_callable existence test:")
try
    sym = ssys_callable.sys.T_wall_callable
    println("     OK — found ", sym)
catch e
    println("     FAILED: ", split(sprint(showerror, e), "\n")[1])
end
# Try the alternate access path used by user code
try
    sym = ssys_callable.T_wall_callable
    println("     direct ssys.T_wall_callable -> ", sym)
catch e
    println("     direct ssys.T_wall_callable -> FAILED: ",
            split(sprint(showerror, e), "\n")[1])
end
