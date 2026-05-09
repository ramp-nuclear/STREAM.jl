# Phase 58 — verify the strict determinacy contract on the canonical build_loop.
# Reuses build_loop's body, but tests mtkcompile(sys; fully_determined=true).
# Workaround for daemon Phase 57 D-04 dev #1: import connect from ModelingToolkit
# to disambiguate from Sockets.connect.
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect          # disambiguate from Sockets.connect
using STREAM
import STREAM: Pump, Channel, HeatExchanger, PipeGeometry_circular, ChannelAndContacts,
                HeatDiffusion, PipeGeometry_rectangular

println("\n=== Strict-determinacy contract on build_loop() ===\n")
n = 10
T_wall = 373.15
T_inlet = 313.15
@named pump = Pump(3.0e4)
@named ch = Channel(; n=n, geometry=PipeGeometry_circular(0.6, 0.01), h_left=5000.0, h_right=0.0)
@named bc = HeatExchanger(T_inlet)
connections = Equation[
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out, ch.port_in),
    connect(ch.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
    [ch.T_wall_left[i]  ~ T_wall  for i in 1:n]...,
    [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,
]
@named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
try
    ssys_strict = mtkcompile(sys; fully_determined=true)
    println("mtkcompile(sys; fully_determined=true) -> SUCCESS")
    println("  n_eqs=", length(equations(ssys_strict)))
    println("  n_unknowns=", length(unknowns(ssys_strict)))
catch e
    println("mtkcompile(sys; fully_determined=true) -> FAILED")
    println("  ", typeof(e))
    println("  ", sprint(showerror, e))
end

# ----- MTR symmetric scenario (the canonical broken case). Mirror /tmp/test_mtr.jl
println("\n=== MTR symmetric — under-determined diagnostic ===\n")
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
]
@named sys_mtr = compose(System(conns, t; name=:mtr_sym), pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)

# Default kwarg
try
    ssys = mtkcompile(sys_mtr)
    println("mtkcompile(sys_mtr) [default] -> SUCCESS")
    println("  n_eqs=", length(equations(ssys)), "  n_unknowns=", length(unknowns(ssys)),
            "  Δ=", length(equations(ssys)) - length(unknowns(ssys)))
catch e
    println("mtkcompile(sys_mtr) [default] -> FAILED")
    println("  ", typeof(e))
    msg = sprint(showerror, e); println("  ", split(msg, "\n")[1])
end

# fully_determined=false
ssys = mtkcompile(sys_mtr; fully_determined=false)
n_eq = length(equations(ssys))
n_uk = length(unknowns(ssys))
println("mtkcompile(sys_mtr; fully_determined=false) -> n_eqs=", n_eq, "  n_unknowns=", n_uk,
        "  Δ=", n_eq - n_uk)
println("\nUnknowns list (compact):")
for (i, u) in enumerate(unknowns(ssys))
    println("  [", i, "] ", u)
end

println("\nEquations (count and sample):")
for (i, eq) in enumerate(equations(ssys))
    if i <= 6 || i > n_eq - 4
        s = string(eq); println("  [", i, "] ", length(s) > 200 ? s[1:200]*"..." : s)
    elseif i == 7
        println("  ... (", n_eq - 10, " elided) ...")
    end
end

# fully_determined=true
println("\nmtkcompile(sys_mtr; fully_determined=true) attempt:")
try
    ssys_t = mtkcompile(sys_mtr; fully_determined=true)
    println("  SUCCESS — n_eqs=", length(equations(ssys_t)), " n_unknowns=", length(unknowns(ssys_t)))
catch e
    println("  FAILED — ", typeof(e))
    println("  ", split(sprint(showerror, e), "\n")[1])
end
