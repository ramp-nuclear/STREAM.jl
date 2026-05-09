# Phase 58 — verify the hypothesis: HD.power is the missing equation in MTR scenarios.
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion,
                PipeGeometry_rectangular

nz = 10
nx = 3
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
conns = [
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
    hd.power ~ 1.0e4,    # <-- HYPOTHESIS: this is the missing eq
]
@named sys_mtr = compose(System(conns, t; name=:mtr_sym), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
println("\n=== MTR symmetric WITH hd.power pin ===\n")
try
    ssys = mtkcompile(sys_mtr)
    println("mtkcompile(sys_mtr) [default] -> SUCCESS")
    println("  n_eqs=", length(equations(ssys)), "  n_unknowns=", length(unknowns(ssys)),
            "  Δ=", length(equations(ssys)) - length(unknowns(ssys)))
catch e
    println("mtkcompile(sys_mtr) [default] -> FAILED")
    println("  ", split(sprint(showerror, e), "\n")[1])
end
try
    ssys_t = mtkcompile(sys_mtr; fully_determined=true)
    println("mtkcompile(sys_mtr; fully_determined=true) -> SUCCESS")
    println("  n_eqs=", length(equations(ssys_t)), "  n_unknowns=", length(unknowns(ssys_t)))
    # Now try a steady-state solve
    T_w = 315.0
    op = vcat(
        [ssys_t.hd.T[i, j] => T_w for i in 1:nz for j in 1:nx],
        [ssys_t.cac_l.T[i] => T_w for i in 1:nz],
        [ssys_t.cac_r.T[i] => T_w for i in 1:nz],
        [ssys_t.cac_l.port_in.mdot => +0.250],
        [ssys_t.cac_r.port_in.mdot => +0.250],
    )
    sol = solve_steady(ssys_t, op)
    println("solve_steady retcode: ", sol.retcode)
catch e
    println("FAILED — ", split(sprint(showerror, e), "\n")[1])
end
