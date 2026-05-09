# Phase 58 — Scenario E — VAL-02 two-plate one-channel topology diagnostic
#
# Lifts test/test_validation.jl:935-996 verbatim. TWO HeatDiffusion instances
# (hd1, hd2) connect to a single ChannelAndContacts on its left and right faces.
# Each HD instance contributes a missing-pin gap; without pins the system is
# structurally Δ=-2. With both `hd1.power ~ power_per_plate` AND `hd2.power ~
# power_per_plate` appended the system is Δ=0.
#
# Confirms RESEARCH §3 Scenario E live numbers: 91/93 (-2) → 91/91 (0).
#
# R-1 mitigation: explicit `using ModelingToolkit: connect`.

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: Pump, HeatExchanger, ChannelAndContacts, HeatDiffusion,
                PipeGeometry_rectangular

function build_val02_twoplate(; pin_power::Bool=false)
    nz_v02 = 10
    nx_v02 = 3
    T_in_v02 = 313.15
    power_per_plate = 1e4

    @named pump_v02 = Pump(3.0e4)
    @named hx_v02 = HeatExchanger(T_in_v02)
    @named cac_v02 = ChannelAndContacts(;
        n=nz_v02, geometry=PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07))

    ps_v02 = fill(1.0 / (nz_v02 * nx_v02), nz_v02, nx_v02)
    @named hd1 = HeatDiffusion(;
        nz=nz_v02, nx=nx_v02, Lz=0.6, Lx=0.00127, y=0.07,
        rho_s=2700.0, cp_s=900.0, k_s=200.0,
        power_shape=ps_v02, power=power_per_plate)
    @named hd2 = HeatDiffusion(;
        nz=nz_v02, nx=nx_v02, Lz=0.6, Lx=0.00127, y=0.07,
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
    ]
    if pin_power
        push!(conns_v02, hd1.power ~ power_per_plate)
        push!(conns_v02, hd2.power ~ power_per_plate)
    end

    @named sys_v02 = compose(System(conns_v02, t; name=:val02_sys),
        pump_v02, hx_v02, cac_v02, hd1, hd2)
    return sys_v02
end

println("\n=== Scenario E: VAL-02 two-plate one-channel (steady) ===\n")

println("-- as-is (no pins) --")
sys_broken = build_val02_twoplate(; pin_power=false)
ssys_broken = mtkcompile(sys_broken; fully_determined=false)
n_eq = length(equations(ssys_broken)); n_uk = length(unknowns(ssys_broken))
n_init = length(ModelingToolkit.initialization_equations(ssys_broken))
println("  Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unknowns=", n_uk, "  n_init_eqs=", n_init)

print("  fully_determined=true: ")
try
    mtkcompile(sys_broken; fully_determined=true)
    println("PASS (unexpected)")
catch e
    println("FAIL — ", typeof(e))
end

println("\n-- with hd1.power ~ pwr AND hd2.power ~ pwr --")
sys_pinned = build_val02_twoplate(; pin_power=true)
ssys_pinned = mtkcompile(sys_pinned; fully_determined=false)
n_eq = length(equations(ssys_pinned)); n_uk = length(unknowns(ssys_pinned))
n_init = length(ModelingToolkit.initialization_equations(ssys_pinned))
println("  Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unknowns=", n_uk, "  n_init_eqs=", n_init)

print("  fully_determined=true: ")
try
    mtkcompile(sys_pinned; fully_determined=true)
    println("PASS")
catch e
    println("FAIL — ", typeof(e))
end
